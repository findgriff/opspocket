#!/usr/bin/env python3
"""OpsPocket Cloud — customer dashboard + admin + pairing endpoints.

This module extends the Stripe-webhook-only backend in app.py with
three new surfaces, all under /api/* behind Caddy:

    /api/account/*   — customer self-service (magic-link auth, cookie session)
    /api/admin/*     — internal ops console (Caddy basic-auth at the edge)
    /api/pair/*      — one-shot deep-link payload for the iOS app

Design principles (same as app.py):
  * Python 3 stdlib only — no pip installs.
  * Thin SQL straight to /var/lib/opspocket/tenants.db.
  * No in-process state — all session/token state in sqlite so
    the service can be restarted at any time without logging anyone out.
  * Auth is intentionally minimal:
        - Customer auth: magic-link → email → session cookie (30 days)
        - Admin auth: basic-auth at the Caddy reverse proxy (founder only)
        - Pair auth: one-shot URL-safe code (7 days, single-use)

Imported by app.py; does not run on its own.
"""

from __future__ import annotations

import http.cookies
import http.server
import json
import logging
import pathlib
import secrets
import sqlite3
import time
import urllib.parse
import urllib.request
from datetime import datetime, timezone
from typing import Any, Callable, Optional

log = logging.getLogger("opspocket-api")

# ── Config ────────────────────────────────────────────────────────────
DB_PATH = pathlib.Path("/var/lib/opspocket/tenants.db")
DOMAIN_ROOT = "opspocket.com"
SUPPORT_EMAIL = "hello@opspocket.com"
SESSION_COOKIE = "opspocket_session"
SESSION_TTL_DAYS = 30
MAGIC_TTL_MINUTES = 30
PAIR_TTL_DAYS = 7

STRIPE_API_KEY_FILE = pathlib.Path("/etc/opspocket/stripe-api-key")


def _now() -> int:
    return int(time.time())


def _iso_now() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def _db() -> sqlite3.Connection:
    """Separate connection per request — sqlite3 in WAL mode handles this fine."""
    conn = sqlite3.connect(str(DB_PATH), timeout=10)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA foreign_keys=ON")
    return conn


# ── Magic-link auth ──────────────────────────────────────────────────

def issue_magic_token(email: str) -> str:
    """Mint a single-use login token + record it. Caller emails the link."""
    token = secrets.token_urlsafe(32)
    conn = _db()
    try:
        conn.execute(
            "INSERT INTO magic_tokens (token, email, issued_at) VALUES (?,?,?)",
            (token, email.strip().lower(), _now()),
        )
        conn.commit()
    finally:
        conn.close()
    return token


def consume_magic_token(token: str) -> Optional[str]:
    """Exchange a magic token for a session. Returns the email or None."""
    if not token:
        return None
    now = _now()
    cutoff = now - (MAGIC_TTL_MINUTES * 60)
    conn = _db()
    try:
        row = conn.execute(
            "SELECT email, issued_at, used_at FROM magic_tokens WHERE token=?",
            (token,),
        ).fetchone()
        if not row:
            return None
        if row["used_at"]:
            return None  # already consumed
        if row["issued_at"] < cutoff:
            return None  # expired
        conn.execute(
            "UPDATE magic_tokens SET used_at=? WHERE token=?", (now, token)
        )
        conn.commit()
        return row["email"]
    finally:
        conn.close()


def create_session(email: str) -> str:
    sid = secrets.token_urlsafe(32)
    now = _now()
    expires = now + (SESSION_TTL_DAYS * 86400)
    conn = _db()
    try:
        conn.execute(
            "INSERT INTO sessions (sid, email, issued_at, expires_at) VALUES (?,?,?,?)",
            (sid, email.strip().lower(), now, expires),
        )
        conn.commit()
    finally:
        conn.close()
    return sid


def session_email(sid: Optional[str]) -> Optional[str]:
    if not sid:
        return None
    conn = _db()
    try:
        row = conn.execute(
            "SELECT email, expires_at FROM sessions WHERE sid=?", (sid,)
        ).fetchone()
        if not row:
            return None
        if row["expires_at"] < _now():
            return None
        return row["email"]
    finally:
        conn.close()


def delete_session(sid: str) -> None:
    conn = _db()
    try:
        conn.execute("DELETE FROM sessions WHERE sid=?", (sid,))
        conn.commit()
    finally:
        conn.close()


# ── Pair-code lifecycle ──────────────────────────────────────────────

def create_pair_code(tenant_id: str) -> str:
    """Mint a 7-day single-use pair code for a tenant. Called at 'active'."""
    code = secrets.token_urlsafe(9)[:12]  # ~ 12-char code, URL-safe
    now = _now()
    expires = now + (PAIR_TTL_DAYS * 86400)
    conn = _db()
    try:
        conn.execute(
            "INSERT INTO pair_codes (code, tenant_id, issued_at, expires_at) "
            "VALUES (?,?,?,?)",
            (code, tenant_id, now, expires),
        )
        conn.commit()
    finally:
        conn.close()
    return code


def consume_pair_code(code: str) -> Optional[dict]:
    """Return tenant payload if valid + mark used, else None."""
    if not code:
        return None
    now = _now()
    conn = _db()
    try:
        row = conn.execute(
            "SELECT tenant_id, issued_at, expires_at, used_at "
            "FROM pair_codes WHERE code=?",
            (code,),
        ).fetchone()
        if not row:
            return None
        if row["used_at"]:
            return None
        if row["expires_at"] < now:
            return None
        tenant = conn.execute(
            "SELECT * FROM tenants WHERE id=?", (row["tenant_id"],)
        ).fetchone()
        if not tenant:
            return None
        conn.execute(
            "UPDATE pair_codes SET used_at=? WHERE code=?", (now, code)
        )
        conn.commit()
        return _tenant_pair_payload(dict(tenant))
    finally:
        conn.close()


def _tenant_pair_payload(t: dict) -> dict:
    """Full credential bundle the iOS app needs to create a server profile."""
    return {
        "tenant_id": t["id"],
        "nickname": f"OpsPocket Cloud ({t['tier'].capitalize()})",
        "host": t["domain"],
        "mcp_endpoint": f"https://{t['domain']}/mcp",
        "control_ui_url": f"https://{t['domain']}/",
        "username": "clawmine",
        "password": t["openclaw_password"],
        "gateway_token": t["gateway_token"],
        "tier": t["tier"],
        "ssh_host": t["hetzner_ip"],
        "ssh_port": 22,
    }


# ── Stripe Customer Portal ────────────────────────────────────────────

def stripe_portal_url(customer_id: str, return_url: str) -> Optional[str]:
    """Create a one-shot Customer Portal session so the customer can
    cancel / update card / download invoices in Stripe's hosted UI."""
    try:
        key = STRIPE_API_KEY_FILE.read_text().strip()
    except Exception:
        log.error("stripe api key unreadable")
        return None
    data = urllib.parse.urlencode({
        "customer": customer_id,
        "return_url": return_url,
    }).encode()
    req = urllib.request.Request(
        "https://api.stripe.com/v1/billing_portal/sessions",
        data=data,
        headers={
            "Authorization": f"Bearer {key}",
            "Content-Type": "application/x-www-form-urlencoded",
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=15) as r:
            payload = json.loads(r.read())
            return payload.get("url")
    except Exception as e:
        log.error("stripe portal session failed: %s", e)
        return None


# ── Welcome email hook ────────────────────────────────────────────────

def send_magic_link(email: str, token: str) -> bool:
    """Email the login link. Returns True on success."""
    try:
        from email_sender import send_email  # type: ignore
    except Exception as e:
        log.error("email_sender import failed: %s", e)
        return False
    url = f"https://{DOMAIN_ROOT}/account?token={urllib.parse.quote(token)}"
    subject = "Your OpsPocket login link"
    text = (
        "Click the link below to sign in to your OpsPocket account:\n\n"
        f"{url}\n\n"
        f"Link expires in {MAGIC_TTL_MINUTES} minutes. If you didn't ask for "
        "this, ignore this email.\n\n"
        "— OpsPocket"
    )
    html = (
        "<div style=\"font-family:-apple-system,BlinkMacSystemFont,'SF Pro Text',"
        "sans-serif;max-width:520px;margin:0 auto;padding:32px 24px;"
        "background:#0b0b0d;color:#e9e9ea;border-radius:12px\">"
        "<h1 style=\"font-size:22px;margin:0 0 8px;color:#fff\">Sign in to OpsPocket</h1>"
        "<p style=\"color:#9aa0a6;margin:0 0 24px\">"
        f"Link expires in {MAGIC_TTL_MINUTES} minutes.</p>"
        f"<a href=\"{url}\" style=\"display:inline-block;padding:12px 24px;"
        "background:#e24a3b;color:#fff;text-decoration:none;border-radius:8px;"
        "font-weight:600\">Sign in</a>"
        f"<p style=\"color:#9aa0a6;font-size:12px;margin:32px 0 0\">"
        f"Or paste this into your browser:<br><code style=\"word-break:break-all\">{url}</code></p>"
        "</div>"
    )
    return send_email(to=email, subject=subject, text=text, html=html)


# ── HTTP helpers ──────────────────────────────────────────────────────

def _body_json(h: http.server.BaseHTTPRequestHandler) -> dict:
    length = int(h.headers.get("Content-Length", 0) or 0)
    if not length:
        return {}
    try:
        return json.loads(h.rfile.read(length).decode())
    except Exception:
        return {}


def _reply(h: http.server.BaseHTTPRequestHandler, code: int,
           payload: Any, *, cookie: Optional[str] = None,
           extra_headers: Optional[list] = None) -> None:
    body = (
        payload if isinstance(payload, (bytes, bytearray))
        else json.dumps(payload).encode()
    )
    h.send_response(code)
    h.send_header("Content-Type", "application/json")
    h.send_header("Content-Length", str(len(body)))
    if cookie:
        h.send_header("Set-Cookie", cookie)
    for k, v in (extra_headers or []):
        h.send_header(k, v)
    h.end_headers()
    h.wfile.write(body)


def _read_cookie(h: http.server.BaseHTTPRequestHandler, name: str) -> Optional[str]:
    raw = h.headers.get("Cookie")
    if not raw:
        return None
    try:
        jar = http.cookies.SimpleCookie()
        jar.load(raw)
        if name in jar:
            return jar[name].value
    except Exception:
        pass
    return None


def _build_session_cookie(sid: str, max_age_seconds: int) -> str:
    return (
        f"{SESSION_COOKIE}={sid}; Path=/; HttpOnly; Secure; SameSite=Lax; "
        f"Max-Age={max_age_seconds}"
    )


def _clear_session_cookie() -> str:
    return f"{SESSION_COOKIE}=; Path=/; Max-Age=0"


# ── Account endpoints (/api/account/*) ────────────────────────────────

def handle_account_login(h: http.server.BaseHTTPRequestHandler) -> None:
    body = _body_json(h)
    email = (body.get("email") or "").strip().lower()
    if not email or "@" not in email:
        _reply(h, 400, {"error": "valid email required"})
        return
    token = issue_magic_token(email)
    # Email the link. Always return 200 so the API doesn't leak which
    # emails exist in our customer DB.
    try:
        send_magic_link(email, token)
    except Exception as e:
        log.error("magic-link email failed: %s", e)
    _reply(h, 200, {"ok": True, "message": "check your inbox"})


def handle_account_verify(h: http.server.BaseHTTPRequestHandler,
                          query: dict) -> None:
    token = query.get("token", [""])[0]
    email = consume_magic_token(token)
    if not email:
        _reply(h, 401, {"error": "invalid or expired token"})
        return
    sid = create_session(email)
    _reply(
        h, 200, {"ok": True, "email": email},
        cookie=_build_session_cookie(sid, SESSION_TTL_DAYS * 86400),
    )


def handle_account_me(h: http.server.BaseHTTPRequestHandler) -> None:
    sid = _read_cookie(h, SESSION_COOKIE)
    email = session_email(sid)
    if not email:
        _reply(h, 401, {"error": "not signed in"})
        return
    conn = _db()
    try:
        rows = conn.execute(
            "SELECT id, tier, interval, domain, status, created_at, last_status_change "
            "FROM tenants WHERE lower(customer_email)=? "
            "ORDER BY created_at DESC",
            (email,),
        ).fetchall()
    finally:
        conn.close()
    tenants = []
    for r in rows:
        t = dict(r)
        # Don't leak credentials/tokens from the /me endpoint — those are
        # fetched via /api/pair/:code only, which is single-use.
        tenants.append({
            "id": t["id"],
            "tier": t["tier"],
            "interval": t["interval"],
            "domain": t["domain"],
            "status": t["status"],
            "url": f"https://{t['domain']}/" if t["domain"] else None,
            "created_at": t["created_at"],
            "last_status_change": t["last_status_change"],
        })
    _reply(h, 200, {"email": email, "tenants": tenants})


def handle_account_portal(h: http.server.BaseHTTPRequestHandler) -> None:
    sid = _read_cookie(h, SESSION_COOKIE)
    email = session_email(sid)
    if not email:
        _reply(h, 401, {"error": "not signed in"})
        return
    conn = _db()
    try:
        row = conn.execute(
            "SELECT stripe_customer_id FROM tenants "
            "WHERE lower(customer_email)=? AND stripe_customer_id IS NOT NULL "
            "LIMIT 1",
            (email,),
        ).fetchone()
    finally:
        conn.close()
    if not row or not row["stripe_customer_id"]:
        _reply(h, 404, {"error": "no stripe customer on file"})
        return
    url = stripe_portal_url(
        row["stripe_customer_id"],
        return_url=f"https://{DOMAIN_ROOT}/account",
    )
    if not url:
        _reply(h, 502, {"error": "portal session failed"})
        return
    _reply(h, 200, {"url": url})


def handle_account_pair(h: http.server.BaseHTTPRequestHandler,
                        tenant_id: str) -> None:
    """Generate a fresh pair code for an existing tenant — lets a customer
    re-pair the app after losing credentials."""
    sid = _read_cookie(h, SESSION_COOKIE)
    email = session_email(sid)
    if not email:
        _reply(h, 401, {"error": "not signed in"})
        return
    conn = _db()
    try:
        row = conn.execute(
            "SELECT id FROM tenants WHERE id=? AND lower(customer_email)=?",
            (tenant_id, email),
        ).fetchone()
    finally:
        conn.close()
    if not row:
        _reply(h, 404, {"error": "tenant not found"})
        return
    code = create_pair_code(tenant_id)
    _reply(h, 200, {
        "code": code,
        "deep_link": f"opspocket://pair?code={code}",
        "web_fallback": f"https://{DOMAIN_ROOT}/pair?code={code}",
        "expires_in_days": PAIR_TTL_DAYS,
    })


def handle_account_logout(h: http.server.BaseHTTPRequestHandler) -> None:
    sid = _read_cookie(h, SESSION_COOKIE)
    if sid:
        delete_session(sid)
    _reply(h, 200, {"ok": True}, cookie=_clear_session_cookie())


# ── Admin endpoints (/api/admin/*) ────────────────────────────────────
#
# These endpoints are ONLY exposed behind Caddy basic_auth at the edge.
# The backend trusts that if Caddy forwarded the request, it's
# authenticated. No in-backend credential check — single source of truth.

def handle_admin_tenants(h: http.server.BaseHTTPRequestHandler) -> None:
    conn = _db()
    try:
        rows = conn.execute(
            "SELECT id, customer_email, tier, interval, domain, hetzner_ip, "
            "status, created_at, last_status_change, notes "
            "FROM tenants ORDER BY created_at DESC"
        ).fetchall()
    finally:
        conn.close()
    _reply(h, 200, {
        "count": len(rows),
        "tenants": [dict(r) for r in rows],
    })


def handle_admin_waitlist(h: http.server.BaseHTTPRequestHandler) -> None:
    path = pathlib.Path("/var/lib/opspocket/waitlist.txt")
    if not path.exists():
        _reply(h, 200, {"count": 0, "entries": []})
        return
    entries = []
    for line in path.read_text().splitlines():
        parts = line.split("\t")
        if len(parts) >= 3:
            entries.append({"at": parts[0], "email": parts[1], "tier": parts[2]})
        elif len(parts) >= 2:
            entries.append({"at": parts[0], "email": parts[1], "tier": ""})
    _reply(h, 200, {"count": len(entries), "entries": entries})


def handle_admin_sessions(h: http.server.BaseHTTPRequestHandler) -> None:
    """Active customer sessions — useful for support. No secrets."""
    now = _now()
    conn = _db()
    try:
        rows = conn.execute(
            "SELECT email, issued_at, expires_at FROM sessions "
            "WHERE expires_at > ? ORDER BY issued_at DESC LIMIT 100",
            (now,),
        ).fetchall()
    finally:
        conn.close()
    _reply(h, 200, {
        "count": len(rows),
        "sessions": [dict(r) for r in rows],
    })


def handle_admin_issue_pair(h: http.server.BaseHTTPRequestHandler,
                            tenant_id: str) -> None:
    """Staff-generate a fresh pair code — for support cases where the
    customer needs to re-pair the app but can't log in via magic-link."""
    conn = _db()
    try:
        row = conn.execute("SELECT id FROM tenants WHERE id=?", (tenant_id,)).fetchone()
    finally:
        conn.close()
    if not row:
        _reply(h, 404, {"error": "tenant not found"})
        return
    code = create_pair_code(tenant_id)
    _reply(h, 200, {
        "code": code,
        "deep_link": f"opspocket://pair?code={code}",
        "expires_in_days": PAIR_TTL_DAYS,
    })


# ── Pair endpoint (/api/pair/:code) ───────────────────────────────────

def handle_pair(h: http.server.BaseHTTPRequestHandler, code: str) -> None:
    payload = consume_pair_code(code)
    if not payload:
        _reply(h, 404, {"error": "invalid, expired, or already used"})
        return
    _reply(h, 200, payload)


# ── Main dispatcher ───────────────────────────────────────────────────
#
# Called from WebhookHandler.do_GET / do_POST in app.py to take over
# before the default 404. Returns True if the path was handled.

def handle_get(h: http.server.BaseHTTPRequestHandler) -> bool:
    parsed = urllib.parse.urlparse(h.path)
    path = parsed.path
    query = urllib.parse.parse_qs(parsed.query)

    if path == "/api/account/verify":
        handle_account_verify(h, query)
        return True
    if path == "/api/account/me":
        handle_account_me(h)
        return True
    if path == "/api/admin/tenants":
        handle_admin_tenants(h)
        return True
    if path == "/api/admin/waitlist":
        handle_admin_waitlist(h)
        return True
    if path == "/api/admin/sessions":
        handle_admin_sessions(h)
        return True
    if path.startswith("/api/pair/"):
        code = path[len("/api/pair/"):]
        handle_pair(h, code)
        return True
    return False


def handle_post(h: http.server.BaseHTTPRequestHandler) -> bool:
    path = h.path.split("?", 1)[0]
    if path == "/api/account/login":
        handle_account_login(h)
        return True
    if path == "/api/account/logout":
        handle_account_logout(h)
        return True
    if path == "/api/account/portal":
        handle_account_portal(h)
        return True
    if path.startswith("/api/account/pair/"):
        tenant_id = path[len("/api/account/pair/"):]
        handle_account_pair(h, tenant_id)
        return True
    if path.startswith("/api/admin/pair/"):
        tenant_id = path[len("/api/admin/pair/"):]
        handle_admin_issue_pair(h, tenant_id)
        return True
    return False
