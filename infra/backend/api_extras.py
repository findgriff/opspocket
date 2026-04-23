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
            "SELECT t.id, t.tier, t.interval, t.domain, t.status, "
            "t.created_at, t.last_status_change, t.hetzner_server_id, "
            "hz.server_type, hz.vcpus, hz.memory_gb, hz.disk_gb, "
            "hz.datacenter, hz.ipv4, hz.status AS hz_status, "
            "hb.received_at AS hb_received_at, "
            "hb.cpu_percent, hb.ram_percent, hb.disk_percent, "
            "hb.uptime_seconds, hb.openclaw_version, "
            "hb.failed_services, hb.restart_loop_count "
            "FROM tenants t "
            "LEFT JOIN hetzner_servers hz ON hz.id = t.hetzner_server_id "
            "LEFT JOIN tenant_heartbeats hb ON hb.tenant_id = t.id "
            "WHERE lower(t.customer_email)=? "
            "ORDER BY t.created_at DESC",
            (email,),
        ).fetchall()
        # Active subscription + next renewal from Stripe cache
        stripe_cust_ids = [r["id"] for r in conn.execute(
            "SELECT DISTINCT stripe_customer_id AS id FROM tenants "
            "WHERE lower(customer_email)=? AND stripe_customer_id IS NOT NULL",
            (email,),
        ).fetchall()]
        sub_row = None
        if stripe_cust_ids:
            ph = ",".join("?" * len(stripe_cust_ids))
            sub_row = conn.execute(
                f"SELECT * FROM stripe_subscriptions "
                f"WHERE customer_id IN ({ph}) "
                f"AND status IN ('active','trialing','past_due') "
                f"ORDER BY current_period_end DESC LIMIT 1",
                stripe_cust_ids,
            ).fetchone()
    finally:
        conn.close()
    tenants = []
    for r in rows:
        d = dict(r)
        hb = None
        if d.get("hb_received_at"):
            hb = {
                "received_at": d["hb_received_at"],
                "cpu_percent": d.get("cpu_percent"),
                "ram_percent": d.get("ram_percent"),
                "disk_percent": d.get("disk_percent"),
                "failed_services": d.get("failed_services"),
                "restart_loop_count": d.get("restart_loop_count"),
            }
        health = tenant_health_status(hb)
        tenants.append({
            "id": d["id"],
            "tier": d["tier"],
            "interval": d["interval"],
            "domain": d["domain"],
            "status": d["status"],
            "url": f"https://{d['domain']}/" if d["domain"] else None,
            "created_at": d["created_at"],
            "last_status_change": d["last_status_change"],
            "health_status": health,
            "ipv4": d.get("ipv4"),
            "server_type": d.get("server_type"),
            "vcpus": d.get("vcpus"),
            "memory_gb": d.get("memory_gb"),
            "disk_gb": d.get("disk_gb"),
            "datacenter": d.get("datacenter"),
            "power_state": d.get("hz_status"),
            "uptime_seconds": d.get("uptime_seconds"),
            "openclaw_version": d.get("openclaw_version"),
            "cpu_percent": d.get("cpu_percent"),
            "ram_percent": d.get("ram_percent"),
            "disk_percent": d.get("disk_percent"),
            "last_seen_seconds_ago": (
                _now() - d["hb_received_at"] if d.get("hb_received_at") else None
            ),
        })
    sub = dict(sub_row) if sub_row else None
    _reply(h, 200, {
        "email": email,
        "tenants": tenants,
        "subscription": sub,
    })


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


def handle_account_profile_get(h: http.server.BaseHTTPRequestHandler) -> None:
    sid = _read_cookie(h, SESSION_COOKIE)
    email = session_email(sid)
    if not email:
        _reply(h, 401, {"error": "not signed in"})
        return
    conn = _db()
    try:
        row = conn.execute(
            "SELECT * FROM customers WHERE email=?", (email,)
        ).fetchone()
    finally:
        conn.close()
    if row:
        _reply(h, 200, dict(row))
    else:
        _reply(h, 200, {"email": email})


def handle_account_profile_update(h: http.server.BaseHTTPRequestHandler) -> None:
    sid = _read_cookie(h, SESSION_COOKIE)
    email = session_email(sid)
    if not email:
        _reply(h, 401, {"error": "not signed in"})
        return
    body = _body_json(h)
    allowed = {
        "company_name", "contact_name", "job_title", "phone",
        "website", "industry", "billing_address", "vat_number",
        "country", "consent_marketing",
    }
    fields = {k: v for k, v in body.items() if k in allowed}
    if not fields:
        _reply(h, 400, {"error": "no valid fields"})
        return
    now_iso = _iso_now()
    conn = _db()
    try:
        existing = conn.execute(
            "SELECT email FROM customers WHERE email=?", (email,)
        ).fetchone()
        if not existing:
            # Build an insert with defaults
            keys = list(fields.keys())
            placeholders = ",".join(["?"] * len(keys))
            colnames = ",".join(keys)
            conn.execute(
                f"INSERT INTO customers (email, {colnames}, created_at, updated_at) "
                f"VALUES (?, {placeholders}, ?, ?)",
                [email] + list(fields.values()) + [now_iso, now_iso],
            )
        else:
            sets = ",".join(f"{k}=?" for k in fields)
            conn.execute(
                f"UPDATE customers SET {sets}, updated_at=? WHERE email=?",
                list(fields.values()) + [now_iso, email],
            )
        if "consent_marketing" in fields:
            conn.execute(
                "UPDATE customers SET consent_updated_at=? WHERE email=?",
                (now_iso, email),
            )
        conn.commit()
    finally:
        conn.close()
    _reply(h, 200, {"ok": True})


def handle_account_invoices(h: http.server.BaseHTTPRequestHandler) -> None:
    sid = _read_cookie(h, SESSION_COOKIE)
    email = session_email(sid)
    if not email:
        _reply(h, 401, {"error": "not signed in"})
        return
    conn = _db()
    try:
        # Resolve stripe_customer_id(s) via tenants
        ids = [r["stripe_customer_id"] for r in conn.execute(
            "SELECT DISTINCT stripe_customer_id FROM tenants "
            "WHERE lower(customer_email)=? AND stripe_customer_id IS NOT NULL",
            (email,),
        ).fetchall()]
        if not ids:
            _reply(h, 200, {"invoices": []})
            return
        q = "SELECT * FROM stripe_invoices WHERE customer_id IN ({}) ORDER BY created_at DESC LIMIT 50".format(
            ",".join("?" * len(ids))
        )
        rows = conn.execute(q, ids).fetchall()
    finally:
        conn.close()
    out = [dict(r) for r in rows]
    _reply(h, 200, {"invoices": out})


def handle_account_support_create(h: http.server.BaseHTTPRequestHandler) -> None:
    sid = _read_cookie(h, SESSION_COOKIE)
    email = session_email(sid)
    if not email:
        _reply(h, 401, {"error": "not signed in"})
        return
    body = _body_json(h)
    subject = (body.get("subject") or "").strip()
    msg_body = (body.get("body") or "").strip()
    if not subject:
        _reply(h, 400, {"error": "subject required"})
        return
    now_iso = _iso_now()
    conn = _db()
    try:
        cur = conn.execute(
            "INSERT INTO support_tickets (customer_email, subject, body, "
            "status, priority, created_at, updated_at) "
            "VALUES (?,?,?,?,?,?,?)",
            (email, subject, msg_body, "open", "normal", now_iso, now_iso),
        )
        tid = cur.lastrowid
        conn.commit()
    finally:
        conn.close()
    # Fire off an email to ops so we know about it.
    try:
        from email_sender import send_email  # type: ignore
        send_email(
            to="hello@opspocket.com",
            subject=f"[support] {subject} (#{tid})",
            text=f"From: {email}\n\n{msg_body}\n\nTicket ID: {tid}",
            html=None,
        )
    except Exception as e:
        log.error("support email failed: %s", e)
    _reply(h, 200, {"ok": True, "ticket_id": tid})


# ── Admin endpoints (/api/admin/*) ────────────────────────────────────
#
# These endpoints are ONLY exposed behind Caddy basic_auth at the edge.
# The backend trusts that if Caddy forwarded the request, it's
# authenticated. No in-backend credential check — single source of truth.

def handle_admin_tenants(h: http.server.BaseHTTPRequestHandler) -> None:
    conn = _db()
    try:
        rows = conn.execute(
            "SELECT t.id, t.customer_email, t.tier, t.interval, t.domain, "
            "t.hetzner_ip, t.status, t.created_at, t.last_status_change, "
            "t.notes, "
            "hb.received_at AS hb_received_at, "
            "hb.cpu_percent AS hb_cpu, hb.ram_percent AS hb_ram, "
            "hb.disk_percent AS hb_disk, hb.failed_services AS hb_failed "
            "FROM tenants t "
            "LEFT JOIN tenant_heartbeats hb ON hb.tenant_id = t.id "
            "ORDER BY t.created_at DESC"
        ).fetchall()
    finally:
        conn.close()
    out = []
    for r in rows:
        d = dict(r)
        hb = {
            "received_at": d.pop("hb_received_at"),
            "cpu_percent": d.pop("hb_cpu"),
            "ram_percent": d.pop("hb_ram"),
            "disk_percent": d.pop("hb_disk"),
            "failed_services": d.pop("hb_failed"),
        } if d.get("hb_received_at") is not None else None
        d["health_status"] = tenant_health_status(hb) if hb else "unknown"
        d["last_seen_seconds_ago"] = (
            _now() - hb["received_at"] if hb else None
        )
        out.append(d)
    _reply(h, 200, {"count": len(out), "tenants": out})


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


def _audit(conn: sqlite3.Connection, actor: str, action: str,
           target_type: Optional[str] = None, target_id: Optional[str] = None,
           detail: Optional[str] = None, ip: Optional[str] = None) -> None:
    conn.execute(
        "INSERT INTO audit_log (actor, action, target_type, target_id, "
        "detail, ip, created_at) VALUES (?,?,?,?,?,?,?)",
        (actor, action, target_type, target_id, detail, ip, _iso_now()),
    )


def _admin_actor(h: http.server.BaseHTTPRequestHandler) -> str:
    """Caddy passes through the Authorization header; we extract the
    basic-auth user for audit attribution. Falls back to 'admin'."""
    auth = h.headers.get("Authorization") or ""
    if auth.startswith("Basic "):
        try:
            import base64 as _b64
            decoded = _b64.b64decode(auth[6:]).decode("utf-8")
            user = decoded.split(":", 1)[0]
            return user or "admin"
        except Exception:
            pass
    return "admin"


def _remote_ip(h: http.server.BaseHTTPRequestHandler) -> str:
    # Caddy forwards the real client IP in X-Forwarded-For.
    fwd = h.headers.get("X-Forwarded-For", "")
    if fwd:
        return fwd.split(",")[0].strip()
    return h.client_address[0] if h.client_address else ""


def handle_admin_tenant_detail(h: http.server.BaseHTTPRequestHandler,
                               tenant_id: str) -> None:
    conn = _db()
    try:
        t = conn.execute(
            "SELECT * FROM tenants WHERE id=?", (tenant_id,)
        ).fetchone()
        if not t:
            _reply(h, 404, {"error": "tenant not found"})
            return
        tenant = dict(t)
        # Attach Stripe data
        sc = None
        subs = []
        invs = []
        chs = []
        if tenant.get("stripe_customer_id"):
            cust = conn.execute(
                "SELECT * FROM stripe_customers WHERE id=?",
                (tenant["stripe_customer_id"],),
            ).fetchone()
            sc = dict(cust) if cust else None
            subs = [dict(r) for r in conn.execute(
                "SELECT * FROM stripe_subscriptions WHERE customer_id=?",
                (tenant["stripe_customer_id"],),
            ).fetchall()]
            invs = [dict(r) for r in conn.execute(
                "SELECT * FROM stripe_invoices WHERE customer_id=? "
                "ORDER BY created_at DESC LIMIT 24",
                (tenant["stripe_customer_id"],),
            ).fetchall()]
            chs = [dict(r) for r in conn.execute(
                "SELECT * FROM stripe_charges WHERE customer_id=? "
                "ORDER BY created_at DESC LIMIT 24",
                (tenant["stripe_customer_id"],),
            ).fetchall()]
        # Hetzner data
        hz = None
        if tenant.get("hetzner_server_id"):
            hzrow = conn.execute(
                "SELECT * FROM hetzner_servers WHERE id=?",
                (tenant["hetzner_server_id"],),
            ).fetchone()
            hz = dict(hzrow) if hzrow else None
        snaps = [dict(r) for r in conn.execute(
            "SELECT * FROM hetzner_snapshots WHERE server_id=? "
            "ORDER BY created_at DESC LIMIT 14",
            (tenant.get("hetzner_server_id"),),
        ).fetchall()] if tenant.get("hetzner_server_id") else []
        # Customer row + notes/tasks
        cust_row = conn.execute(
            "SELECT * FROM customers WHERE email=?",
            (tenant["customer_email"].lower(),),
        ).fetchone()
        notes = [dict(r) for r in conn.execute(
            "SELECT * FROM crm_notes WHERE tenant_id=? OR customer_email=? "
            "ORDER BY pinned DESC, created_at DESC LIMIT 50",
            (tenant_id, tenant["customer_email"].lower()),
        ).fetchall()]
        tasks = [dict(r) for r in conn.execute(
            "SELECT * FROM crm_tasks WHERE tenant_id=? OR customer_email=? "
            "ORDER BY (status='open') DESC, created_at DESC LIMIT 50",
            (tenant_id, tenant["customer_email"].lower()),
        ).fetchall()]
        flags = [dict(r) for r in conn.execute(
            "SELECT * FROM feature_flags WHERE tenant_id=?", (tenant_id,),
        ).fetchall()]
        audit = [dict(r) for r in conn.execute(
            "SELECT * FROM audit_log WHERE (target_type='tenant' AND target_id=?) "
            "OR (target_type='customer' AND target_id=?) "
            "ORDER BY created_at DESC LIMIT 50",
            (tenant_id, tenant["customer_email"].lower()),
        ).fetchall()]
        # Heartbeat (latest + 24h sparkline)
        hb_row = conn.execute(
            "SELECT * FROM tenant_heartbeats WHERE tenant_id=?", (tenant_id,),
        ).fetchone()
        hb = dict(hb_row) if hb_row else None
        hb_history = [dict(r) for r in conn.execute(
            "SELECT received_at, cpu_percent, ram_percent, disk_percent "
            "FROM tenant_heartbeat_history "
            "WHERE tenant_id=? AND received_at > ? "
            "ORDER BY received_at ASC",
            (tenant_id, _now() - 24 * 3600),
        ).fetchall()]
        traffic = None
        if tenant.get("hetzner_server_id"):
            tr = conn.execute(
                "SELECT * FROM hetzner_traffic WHERE server_id=?",
                (tenant["hetzner_server_id"],),
            ).fetchone()
            traffic = dict(tr) if tr else None
    finally:
        conn.close()
    # Strip the per-tenant heartbeat_secret — never leak it.
    tenant.pop("heartbeat_secret", None)
    _reply(h, 200, {
        "tenant": tenant,
        "customer": dict(cust_row) if cust_row else None,
        "stripe_customer": sc,
        "stripe_subscriptions": subs,
        "stripe_invoices": invs,
        "stripe_charges": chs,
        "hetzner_server": hz,
        "hetzner_snapshots": snaps,
        "hetzner_traffic": traffic,
        "heartbeat": hb,
        "heartbeat_history": hb_history,
        "health_status": tenant_health_status(hb),
        "notes": notes,
        "tasks": tasks,
        "feature_flags": flags,
        "audit": audit,
    })


def handle_admin_list_notes(h, tenant_id):
    conn = _db()
    try:
        rows = conn.execute(
            "SELECT * FROM crm_notes WHERE tenant_id=? ORDER BY pinned DESC, created_at DESC",
            (tenant_id,),
        ).fetchall()
    finally:
        conn.close()
    _reply(h, 200, {"notes": [dict(r) for r in rows]})


def handle_admin_list_tasks(h, tenant_id):
    conn = _db()
    try:
        rows = conn.execute(
            "SELECT * FROM crm_tasks WHERE tenant_id=? ORDER BY (status='open') DESC, created_at DESC",
            (tenant_id,),
        ).fetchall()
    finally:
        conn.close()
    _reply(h, 200, {"tasks": [dict(r) for r in rows]})


def handle_admin_list_activity(h, tenant_id):
    conn = _db()
    try:
        rows = conn.execute(
            "SELECT * FROM tenant_activity WHERE tenant_id=? ORDER BY ts DESC LIMIT 200",
            (tenant_id,),
        ).fetchall()
    finally:
        conn.close()
    _reply(h, 200, {"activity": [dict(r) for r in rows]})


def handle_admin_customers(h):
    conn = _db()
    try:
        rows = conn.execute(
            "SELECT c.*, "
            "(SELECT count(*) FROM tenants t WHERE lower(t.customer_email)=c.email) AS tenant_count "
            "FROM customers c ORDER BY c.updated_at DESC"
        ).fetchall()
    finally:
        conn.close()
    _reply(h, 200, {"customers": [dict(r) for r in rows]})


def handle_admin_customer_upsert(h):
    body = _body_json(h)
    email = (body.get("email") or "").strip().lower()
    if not email:
        _reply(h, 400, {"error": "email required"})
        return
    allowed = {
        "company_name", "contact_name", "job_title", "phone", "website",
        "industry", "billing_address", "vat_number", "country",
        "lifecycle", "health_score", "tags", "account_owner",
        "lead_source", "notes",
    }
    fields = {k: v for k, v in body.items() if k in allowed}
    now_iso = _iso_now()
    conn = _db()
    try:
        row = conn.execute(
            "SELECT email FROM customers WHERE email=?", (email,)
        ).fetchone()
        if not row:
            cols = ",".join(["email"] + list(fields.keys()) + ["created_at", "updated_at"])
            placeholders = ",".join(["?"] * (len(fields) + 3))
            conn.execute(
                f"INSERT INTO customers ({cols}) VALUES ({placeholders})",
                [email] + list(fields.values()) + [now_iso, now_iso],
            )
        else:
            if fields:
                sets = ",".join(f"{k}=?" for k in fields)
                conn.execute(
                    f"UPDATE customers SET {sets}, updated_at=? WHERE email=?",
                    list(fields.values()) + [now_iso, email],
                )
        _audit(conn, _admin_actor(h), "customer.upsert",
               target_type="customer", target_id=email,
               detail=json.dumps(fields), ip=_remote_ip(h))
        conn.commit()
    finally:
        conn.close()
    _reply(h, 200, {"ok": True})


def handle_admin_note_create(h):
    body = _body_json(h)
    tenant_id = body.get("tenant_id")
    email = (body.get("customer_email") or "").lower() or None
    bodytxt = (body.get("body") or "").strip()
    if not bodytxt:
        _reply(h, 400, {"error": "body required"})
        return
    if not tenant_id and not email:
        _reply(h, 400, {"error": "tenant_id or customer_email required"})
        return
    conn = _db()
    try:
        cur = conn.execute(
            "INSERT INTO crm_notes (tenant_id, customer_email, author, body, "
            "pinned, created_at) VALUES (?,?,?,?,?,?)",
            (tenant_id, email, _admin_actor(h), bodytxt,
             1 if body.get("pinned") else 0, _iso_now()),
        )
        nid = cur.lastrowid
        _audit(conn, _admin_actor(h), "note.create",
               target_type="tenant" if tenant_id else "customer",
               target_id=tenant_id or email, detail=str(nid),
               ip=_remote_ip(h))
        conn.commit()
    finally:
        conn.close()
    _reply(h, 200, {"ok": True, "id": nid})


def handle_admin_task_create(h):
    body = _body_json(h)
    title = (body.get("title") or "").strip()
    if not title:
        _reply(h, 400, {"error": "title required"})
        return
    tenant_id = body.get("tenant_id")
    email = (body.get("customer_email") or "").lower() or None
    conn = _db()
    try:
        cur = conn.execute(
            "INSERT INTO crm_tasks (tenant_id, customer_email, title, due_at, "
            "status, priority, assigned_to, created_at) "
            "VALUES (?,?,?,?,?,?,?,?)",
            (tenant_id, email, title, body.get("due_at"),
             "open", body.get("priority") or "normal",
             body.get("assigned_to") or _admin_actor(h), _iso_now()),
        )
        tid = cur.lastrowid
        _audit(conn, _admin_actor(h), "task.create",
               target_type="tenant" if tenant_id else "customer",
               target_id=tenant_id or email, detail=str(tid),
               ip=_remote_ip(h))
        conn.commit()
    finally:
        conn.close()
    _reply(h, 200, {"ok": True, "id": tid})


def handle_admin_task_complete(h, task_id):
    conn = _db()
    try:
        conn.execute(
            "UPDATE crm_tasks SET status='done', completed_at=? WHERE id=?",
            (_iso_now(), task_id),
        )
        _audit(conn, _admin_actor(h), "task.complete",
               target_type="task", target_id=str(task_id),
               ip=_remote_ip(h))
        conn.commit()
    finally:
        conn.close()
    _reply(h, 200, {"ok": True})


def handle_admin_all_tasks(h):
    conn = _db()
    try:
        rows = conn.execute(
            "SELECT * FROM crm_tasks ORDER BY (status='open') DESC, "
            "CASE priority WHEN 'high' THEN 0 WHEN 'normal' THEN 1 ELSE 2 END, "
            "created_at DESC LIMIT 200"
        ).fetchall()
    finally:
        conn.close()
    _reply(h, 200, {"tasks": [dict(r) for r in rows]})


def handle_admin_support_list(h):
    conn = _db()
    try:
        rows = conn.execute(
            "SELECT * FROM support_tickets ORDER BY "
            "CASE status WHEN 'open' THEN 0 WHEN 'in_progress' THEN 1 WHEN 'waiting' THEN 2 ELSE 3 END, "
            "created_at DESC LIMIT 100"
        ).fetchall()
    finally:
        conn.close()
    _reply(h, 200, {"tickets": [dict(r) for r in rows]})


def handle_admin_audit(h, query):
    limit = int((query.get("limit", ["200"])[0])) if query else 200
    limit = min(limit, 1000)
    conn = _db()
    try:
        rows = conn.execute(
            "SELECT * FROM audit_log ORDER BY created_at DESC LIMIT ?",
            (limit,),
        ).fetchall()
    finally:
        conn.close()
    _reply(h, 200, {"events": [dict(r) for r in rows]})


def handle_admin_sync_stripe(h):
    try:
        import sync_stripe  # type: ignore
        counts = sync_stripe.sync_all()
        sync_stripe.sync_subscriptions_all_statuses()
        conn = _db()
        try:
            _audit(conn, _admin_actor(h), "sync.stripe",
                   detail=json.dumps(counts), ip=_remote_ip(h))
            conn.commit()
        finally:
            conn.close()
        _reply(h, 200, {"ok": True, "counts": counts})
    except Exception as e:
        log.exception("stripe sync failed: %s", e)
        _reply(h, 500, {"error": str(e)})


def handle_admin_sync_hetzner(h):
    try:
        import sync_hetzner  # type: ignore
        counts = sync_hetzner.sync_all()
        conn = _db()
        try:
            _audit(conn, _admin_actor(h), "sync.hetzner",
                   detail=json.dumps(counts), ip=_remote_ip(h))
            conn.commit()
        finally:
            conn.close()
        _reply(h, 200, {"ok": True, "counts": counts})
    except Exception as e:
        log.exception("hetzner sync failed: %s", e)
        _reply(h, 500, {"error": str(e)})


def handle_admin_impersonate(h, tenant_id):
    """Generate a magic-link the admin can paste to support a customer
    without knowing their password. Logged + time-limited."""
    conn = _db()
    try:
        row = conn.execute(
            "SELECT customer_email FROM tenants WHERE id=?", (tenant_id,),
        ).fetchone()
        if not row:
            _reply(h, 404, {"error": "tenant not found"})
            return
        email = row["customer_email"].lower()
    finally:
        conn.close()
    token = issue_magic_token(email)
    conn = _db()
    try:
        _audit(conn, _admin_actor(h), "impersonate",
               target_type="customer", target_id=email,
               detail=f"token issued for tenant {tenant_id}",
               ip=_remote_ip(h))
        conn.commit()
    finally:
        conn.close()
    _reply(h, 200, {
        "login_url": f"https://{DOMAIN_ROOT}/account?token={urllib.parse.quote(token)}",
        "email": email,
        "ttl_minutes": MAGIC_TTL_MINUTES,
    })


def handle_admin_cancel_subscription(h, tenant_id):
    """Cancel a customer's Stripe subscription immediately."""
    conn = _db()
    try:
        row = conn.execute(
            "SELECT stripe_subscription_id, customer_email FROM tenants WHERE id=?",
            (tenant_id,),
        ).fetchone()
    finally:
        conn.close()
    if not row or not row["stripe_subscription_id"]:
        _reply(h, 404, {"error": "no subscription"})
        return
    try:
        key = STRIPE_API_KEY_FILE.read_text().strip()
    except Exception:
        _reply(h, 500, {"error": "stripe key unreadable"})
        return
    req = urllib.request.Request(
        f"https://api.stripe.com/v1/subscriptions/{row['stripe_subscription_id']}",
        headers={
            "Authorization": f"Bearer {key}",
            "Content-Type": "application/x-www-form-urlencoded",
        },
        method="DELETE",
    )
    try:
        with urllib.request.urlopen(req, timeout=15) as r:
            result = json.loads(r.read())
    except Exception as e:
        _reply(h, 502, {"error": str(e)})
        return
    conn = _db()
    try:
        _audit(conn, _admin_actor(h), "subscription.cancel",
               target_type="tenant", target_id=tenant_id,
               detail=row["stripe_subscription_id"], ip=_remote_ip(h))
        conn.commit()
    finally:
        conn.close()
    _reply(h, 200, {"ok": True, "status": result.get("status")})


def handle_admin_flag_set(h, tenant_id):
    body = _body_json(h)
    flag = body.get("flag")
    enabled = 1 if body.get("enabled") else 0
    if not flag:
        _reply(h, 400, {"error": "flag required"})
        return
    conn = _db()
    try:
        conn.execute(
            "INSERT INTO feature_flags (tenant_id, flag, enabled, updated_at) "
            "VALUES (?,?,?,?) "
            "ON CONFLICT(tenant_id, flag) DO UPDATE SET "
            "enabled=excluded.enabled, updated_at=excluded.updated_at",
            (tenant_id, flag, enabled, _iso_now()),
        )
        _audit(conn, _admin_actor(h), "flag.set",
               target_type="tenant", target_id=tenant_id,
               detail=f"{flag}={enabled}", ip=_remote_ip(h))
        conn.commit()
    finally:
        conn.close()
    _reply(h, 200, {"ok": True})


def handle_admin_search(h, query):
    """Search across customers and tenants by name / email / phone /
    company / domain. Returns up to 30 hits."""
    q = (query.get("q", [""])[0] if query else "").strip().lower()
    if not q:
        _reply(h, 200, {"query": "", "customers": [], "tenants": []})
        return
    like = f"%{q}%"
    conn = _db()
    try:
        customers = [dict(r) for r in conn.execute(
            "SELECT email, company_name, contact_name, phone, lifecycle, "
            "health_score, account_owner "
            "FROM customers "
            "WHERE lower(email) LIKE ? OR lower(COALESCE(company_name,'')) LIKE ? "
            "OR lower(COALESCE(contact_name,'')) LIKE ? "
            "OR COALESCE(phone,'') LIKE ? "
            "LIMIT 30",
            (like, like, like, like),
        ).fetchall()]
        tenants = [dict(r) for r in conn.execute(
            "SELECT id, customer_email, tier, domain, hetzner_ip, status, "
            "created_at FROM tenants "
            "WHERE lower(customer_email) LIKE ? OR lower(COALESCE(domain,'')) LIKE ? "
            "OR COALESCE(hetzner_ip,'') LIKE ? "
            "LIMIT 30",
            (like, like, like),
        ).fetchall()]
    finally:
        conn.close()
    _reply(h, 200, {"query": q, "customers": customers, "tenants": tenants})


def handle_admin_customer_detail(h, email):
    """Full customer profile — CRM fields + all tenants + all invoices
    + all charges + all notes + all tasks + audit — joined by email."""
    email = (email or "").strip().lower()
    if not email:
        _reply(h, 400, {"error": "email required"})
        return
    conn = _db()
    try:
        cust = conn.execute(
            "SELECT * FROM customers WHERE email=?", (email,)
        ).fetchone()
        tenants = [dict(r) for r in conn.execute(
            "SELECT * FROM tenants WHERE lower(customer_email)=? "
            "ORDER BY created_at DESC",
            (email,),
        ).fetchall()]
        stripe_ids = [t["stripe_customer_id"] for t in tenants
                      if t.get("stripe_customer_id")]
        invoices = []
        charges = []
        subs = []
        if stripe_ids:
            placeholders = ",".join("?" * len(stripe_ids))
            invoices = [dict(r) for r in conn.execute(
                f"SELECT * FROM stripe_invoices WHERE customer_id IN ({placeholders}) "
                f"ORDER BY created_at DESC LIMIT 50", stripe_ids,
            ).fetchall()]
            charges = [dict(r) for r in conn.execute(
                f"SELECT * FROM stripe_charges WHERE customer_id IN ({placeholders}) "
                f"ORDER BY created_at DESC LIMIT 50", stripe_ids,
            ).fetchall()]
            subs = [dict(r) for r in conn.execute(
                f"SELECT * FROM stripe_subscriptions WHERE customer_id IN ({placeholders})",
                stripe_ids,
            ).fetchall()]
        notes = [dict(r) for r in conn.execute(
            "SELECT * FROM crm_notes WHERE customer_email=? "
            "OR tenant_id IN (SELECT id FROM tenants WHERE lower(customer_email)=?) "
            "ORDER BY pinned DESC, created_at DESC LIMIT 50",
            (email, email),
        ).fetchall()]
        tasks = [dict(r) for r in conn.execute(
            "SELECT * FROM crm_tasks WHERE customer_email=? "
            "OR tenant_id IN (SELECT id FROM tenants WHERE lower(customer_email)=?) "
            "ORDER BY (status='open') DESC, created_at DESC LIMIT 50",
            (email, email),
        ).fetchall()]
        tickets = [dict(r) for r in conn.execute(
            "SELECT * FROM support_tickets WHERE lower(customer_email)=? "
            "ORDER BY created_at DESC LIMIT 50",
            (email,),
        ).fetchall()]
        audit = [dict(r) for r in conn.execute(
            "SELECT * FROM audit_log WHERE "
            "(target_type='customer' AND target_id=?) OR "
            "(target_type='tenant' AND target_id IN "
            "(SELECT id FROM tenants WHERE lower(customer_email)=?)) "
            "ORDER BY created_at DESC LIMIT 50",
            (email, email),
        ).fetchall()]
        sessions_list = [dict(r) for r in conn.execute(
            "SELECT * FROM sessions WHERE lower(email)=? AND expires_at > ? "
            "ORDER BY issued_at DESC LIMIT 10",
            (email, _now()),
        ).fetchall()]
    finally:
        conn.close()
    _reply(h, 200, {
        "email": email,
        "customer": dict(cust) if cust else None,
        "tenants": tenants,
        "stripe_subscriptions": subs,
        "stripe_invoices": invoices,
        "stripe_charges": charges,
        "notes": notes,
        "tasks": tasks,
        "support_tickets": tickets,
        "audit": audit,
        "active_sessions": sessions_list,
    })


def handle_admin_reset_clawmine(h, tenant_id):
    """Rotate the clawmine basic-auth password on the customer's tenant
    VPS and email them the new credentials.

    Steps:
      1. Generate a new URL-safe password
      2. SSH into tenant box (orchestrator SSH key is pre-installed)
      3. Rewrite the Caddyfile basic_auth hash on the tenant
      4. Reload Caddy on the tenant
      5. Update /root/CREDENTIALS.json on the tenant
      6. Update tenants.openclaw_password in local DB
      7. Email the customer the new credentials
      8. Audit
    """
    conn = _db()
    try:
        row = conn.execute(
            "SELECT * FROM tenants WHERE id=?", (tenant_id,),
        ).fetchone()
    finally:
        conn.close()
    if not row:
        _reply(h, 404, {"error": "tenant not found"})
        return
    tenant = dict(row)
    ip = tenant.get("hetzner_ip")
    if not ip:
        _reply(h, 400, {"error": "tenant has no IP — cannot SSH"})
        return

    new_password = secrets.token_urlsafe(18)[:24]
    try:
        bcrypt_hash = _caddy_hash_password(new_password)
    except Exception as e:
        log.error("caddy hash-password failed: %s", e)
        _reply(h, 500, {"error": f"hash generation failed: {e}"})
        return

    # The tenant's OpenClaw Caddy config is at
    # /etc/caddy/Caddyfile.d/openclaw.caddy on the tenant box (per
    # install-openclaw.sh convention). Rewrite the single basic_auth
    # line that starts with 'clawmine ' + reload caddy.
    remote_cmd = (
        f"set -e; "
        f"CF=/etc/caddy/Caddyfile.d/openclaw.caddy; "
        f"if [ ! -f $CF ]; then echo 'no openclaw caddy config'; exit 2; fi; "
        # Replace the line containing 'clawmine ' (bcrypt hash is on same line)
        f"sed -i 's|^\\(\\s*\\)clawmine .*|\\1clawmine {bcrypt_hash}|' $CF; "
        f"caddy validate --config /etc/caddy/Caddyfile 2>&1 >/dev/null || "
        f"(echo 'caddy validate failed'; exit 3); "
        f"systemctl reload caddy; "
        # Update CREDENTIALS.json
        f"CRED=/root/CREDENTIALS.json; "
        f"if [ -f $CRED ]; then "
        f"python3 -c 'import json,sys;p=\"$CRED\";d=json.load(open(p));"
        f"d[\"password\"]=\"{new_password}\";open(p,\"w\").write(json.dumps(d,indent=2))' "
        f"|| true; fi; "
        f"echo OK"
    )

    import subprocess
    try:
        result = subprocess.run(
            [
                "ssh",
                "-o", "StrictHostKeyChecking=no",
                "-o", "UserKnownHostsFile=/dev/null",
                "-o", "ConnectTimeout=6",     # fail fast if tenant is down
                "-o", "ServerAliveInterval=3",
                "-o", "ServerAliveCountMax=2",
                "-o", "BatchMode=yes",
                f"root@{ip}",
                remote_cmd,
            ],
            capture_output=True, text=True, timeout=20,
        )
    except subprocess.TimeoutExpired:
        _reply(h, 200, {"ok": False,
                         "error": "SSH timed out — tenant unreachable"})
        return
    except Exception as e:
        _reply(h, 200, {"ok": False, "error": f"SSH invocation failed: {e}"})
        return

    if result.returncode != 0:
        log.error("reset-clawmine ssh failed: rc=%s stderr=%s",
                  result.returncode, result.stderr)
        _reply(h, 200, {
            "ok": False,
            "error": "SSH command failed",
            "stderr": result.stderr[-500:],
            "returncode": result.returncode,
        })
        return

    # Update local DB
    conn = _db()
    try:
        conn.execute(
            "UPDATE tenants SET openclaw_password=?, last_status_change=? WHERE id=?",
            (new_password, _iso_now(), tenant_id),
        )
        _audit(conn, _admin_actor(h), "clawmine.reset",
               target_type="tenant", target_id=tenant_id,
               detail="password rotated + emailed", ip=_remote_ip(h))
        conn.commit()
    finally:
        conn.close()

    # Email the customer
    email_sent = False
    try:
        from email_sender import send_email  # type: ignore
        control_url = f"https://{tenant.get('domain')}/"
        subject = "OpsPocket — your Control UI password has been reset"
        text = (
            f"Hi {tenant.get('customer_email')},\n\n"
            f"Your OpsPocket Control UI password has just been reset.\n\n"
            f"URL:      {control_url}\n"
            f"Username: clawmine\n"
            f"Password: {new_password}\n\n"
            f"If you didn't ask for this reset, email hello@opspocket.com "
            f"immediately.\n\n— OpsPocket"
        )
        html = (
            f"<div style=\"font-family:-apple-system,sans-serif;max-width:520px;"
            f"margin:0 auto;padding:32px;background:#0b0b0d;color:#eee;"
            f"border-radius:12px\">"
            f"<h1 style=\"font-size:20px;margin:0 0 12px;color:#fff\">"
            f"Your OpsPocket password has been reset</h1>"
            f"<p style=\"color:#aaa;font-size:14px\">Use these new credentials "
            f"to sign in to your Control UI:</p>"
            f"<div style=\"background:#141416;border:1px solid #2a2a2a;"
            f"border-radius:8px;padding:16px;font-family:ui-monospace,monospace;"
            f"font-size:13px;margin:16px 0\">"
            f"<div>URL: <a href=\"{control_url}\" style=\"color:#57e3ff\">{control_url}</a></div>"
            f"<div>Username: <strong style=\"color:#fff\">clawmine</strong></div>"
            f"<div>Password: <strong style=\"color:#fff\">{new_password}</strong></div>"
            f"</div>"
            f"<p style=\"color:#999;font-size:12px\">If you didn't request this, "
            f"email <a href=\"mailto:hello@opspocket.com\" style=\"color:#57e3ff\">"
            f"hello@opspocket.com</a> immediately.</p>"
            f"</div>"
        )
        email_sent = send_email(
            to=tenant["customer_email"], subject=subject, text=text, html=html,
        )
    except Exception as e:
        log.error("password-reset email failed: %s", e)

    _reply(h, 200, {
        "ok": True,
        "email_sent": email_sent,
        "tenant_id": tenant_id,
        "new_password_shown_to_admin_for_copy": new_password,
    })


def _caddy_hash_password(plaintext: str) -> str:
    """Invoke Caddy to bcrypt-hash the password. Caddy is on PATH on
    both dev box and all tenant boxes."""
    import subprocess
    result = subprocess.run(
        ["caddy", "hash-password", "--plaintext", plaintext],
        capture_output=True, text=True, timeout=10,
    )
    if result.returncode != 0:
        raise RuntimeError(result.stderr.strip())
    return result.stdout.strip()


def handle_admin_analytics(h):
    """Compute MRR / ARR / churn / trial / failed payments / etc.
    Uses the local Stripe cache — call /api/admin/sync/stripe first
    for fresh numbers."""
    conn = _db()
    try:
        # MRR — sum of active subscription amounts normalised to monthly
        rows = conn.execute(
            "SELECT status, interval, amount, currency FROM stripe_subscriptions"
        ).fetchall()
        mrr_minor = 0  # in minor units (pence)
        active = 0
        trialing = 0
        past_due = 0
        cancelled = 0
        currency_seen = "gbp"
        for r in rows:
            if r["status"] == "active":
                active += 1
                if r["interval"] == "year":
                    mrr_minor += (r["amount"] or 0) // 12
                else:
                    mrr_minor += (r["amount"] or 0)
                if r["currency"]:
                    currency_seen = r["currency"]
            elif r["status"] == "trialing":
                trialing += 1
            elif r["status"] == "past_due":
                past_due += 1
            elif r["status"] == "canceled":
                cancelled += 1

        failed_payments = conn.execute(
            "SELECT count(*) AS n FROM stripe_charges WHERE status='failed'"
        ).fetchone()["n"]

        # Tenant status distribution
        tenant_status = dict(conn.execute(
            "SELECT status, count(*) AS n FROM tenants GROUP BY status"
        ).fetchall() and {
            r["status"]: r["n"] for r in conn.execute(
                "SELECT status, count(*) AS n FROM tenants GROUP BY status"
            ).fetchall()
        } or {})

        # Recent invoices + last paid
        last_paid = conn.execute(
            "SELECT amount_paid, currency, paid_at FROM stripe_invoices "
            "WHERE status='paid' AND paid_at IS NOT NULL "
            "ORDER BY paid_at DESC LIMIT 1"
        ).fetchone()

        # Total paid ever
        total_paid_minor = conn.execute(
            "SELECT COALESCE(SUM(amount_paid), 0) AS s FROM stripe_invoices "
            "WHERE status='paid'"
        ).fetchone()["s"]

        # Recent failed invoices
        failed_invoices = conn.execute(
            "SELECT count(*) AS n FROM stripe_invoices WHERE status='uncollectible'"
        ).fetchone()["n"]

        # Trial converting / churn counts in last 30 days
        import time as _time
        thirty = _time.time() - 30 * 86400
        new_trials = conn.execute(
            "SELECT count(*) AS n FROM stripe_subscriptions "
            "WHERE trial_end > ? AND status='trialing'",
            (thirty,),
        ).fetchone()["n"]
        recent_churn = conn.execute(
            "SELECT count(*) AS n FROM stripe_subscriptions "
            "WHERE status='canceled' AND canceled_at > ?",
            (thirty,),
        ).fetchone()["n"]

        waitlist_count = 0
        waitlist_path = pathlib.Path("/var/lib/opspocket/waitlist.txt")
        if waitlist_path.exists():
            waitlist_count = len([
                l for l in waitlist_path.read_text().splitlines() if l.strip()
            ])
    finally:
        conn.close()

    _reply(h, 200, {
        "currency": currency_seen,
        "mrr_minor": mrr_minor,
        "mrr_pounds": mrr_minor / 100,
        "arr_minor": mrr_minor * 12,
        "arr_pounds": mrr_minor * 12 / 100,
        "subscriptions": {
            "active": active,
            "trialing": trialing,
            "past_due": past_due,
            "cancelled": cancelled,
        },
        "tenant_status": tenant_status,
        "failed_payments_total": failed_payments,
        "failed_invoices_total": failed_invoices,
        "total_paid_minor": total_paid_minor,
        "total_paid_pounds": total_paid_minor / 100,
        "last_paid_invoice": dict(last_paid) if last_paid else None,
        "new_trials_30d": new_trials,
        "recent_churn_30d": recent_churn,
        "waitlist_count": waitlist_count,
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


# ── Heartbeat receiver ───────────────────────────────────────────────
#
# Tenant boxes run a systemd timer that POSTs every 60 s to
# /api/tenants/<id>/heartbeat with:
#
#   Headers:
#     X-OpsPocket-Signature: sha256=<hex hmac of raw body using heartbeat_secret>
#     Content-Type: application/json
#
#   Body:
#     {"cpu":35.4,"ram":58.2,"disk":22,"uptime":1234567,
#      "load":[0.3,0.5,0.6],"openclaw_version":"2026.4.5",
#      "docker_total":4,"docker_running":4,
#      "failed_services":0,"failed_service_names":[],
#      "tls_days_left":84,"restart_loops":0}
#
# We verify HMAC, upsert tenant_heartbeats, append to history
# (throttled to 5-min samples to keep the table small).

import hashlib as _hashlib
import hmac as _hmac

HISTORY_SAMPLE_INTERVAL = 300  # write to history at most every 5 min


def _read_raw_body(h: http.server.BaseHTTPRequestHandler) -> bytes:
    length = int(h.headers.get("Content-Length", 0) or 0)
    return h.rfile.read(length) if length else b""


def handle_tenant_heartbeat(h: http.server.BaseHTTPRequestHandler,
                            tenant_id: str) -> None:
    raw = _read_raw_body(h)
    sig_header = h.headers.get("X-OpsPocket-Signature", "")
    if not sig_header.startswith("sha256="):
        _reply(h, 400, {"error": "missing or malformed signature"})
        return
    provided = sig_header.split("=", 1)[1]

    conn = _db()
    try:
        row = conn.execute(
            "SELECT heartbeat_secret FROM tenants WHERE id=?", (tenant_id,)
        ).fetchone()
    finally:
        conn.close()
    if not row or not row["heartbeat_secret"]:
        _reply(h, 404, {"error": "unknown tenant"})
        return

    expected = _hmac.new(
        row["heartbeat_secret"].encode(), raw, _hashlib.sha256
    ).hexdigest()
    if not _hmac.compare_digest(expected, provided):
        log.warning("heartbeat HMAC mismatch for tenant %s", tenant_id)
        _reply(h, 401, {"error": "bad signature"})
        return

    try:
        data = json.loads(raw.decode())
    except Exception:
        _reply(h, 400, {"error": "bad json"})
        return

    now_ts = _now()
    load = data.get("load") or [None, None, None]
    failed_names = data.get("failed_service_names") or []
    if isinstance(failed_names, list):
        failed_names = ",".join(str(n) for n in failed_names)[:500]

    conn = _db()
    try:
        # Upsert latest state
        conn.execute(
            """
            INSERT INTO tenant_heartbeats (
                tenant_id, received_at, cpu_percent, ram_percent, disk_percent,
                uptime_seconds, load_1, load_5, load_15, openclaw_version,
                docker_containers, docker_containers_running,
                failed_services, failed_service_names,
                tls_cert_days_left, restart_loop_count, raw_payload
            ) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
            ON CONFLICT(tenant_id) DO UPDATE SET
                received_at=excluded.received_at,
                cpu_percent=excluded.cpu_percent,
                ram_percent=excluded.ram_percent,
                disk_percent=excluded.disk_percent,
                uptime_seconds=excluded.uptime_seconds,
                load_1=excluded.load_1, load_5=excluded.load_5, load_15=excluded.load_15,
                openclaw_version=excluded.openclaw_version,
                docker_containers=excluded.docker_containers,
                docker_containers_running=excluded.docker_containers_running,
                failed_services=excluded.failed_services,
                failed_service_names=excluded.failed_service_names,
                tls_cert_days_left=excluded.tls_cert_days_left,
                restart_loop_count=excluded.restart_loop_count,
                raw_payload=excluded.raw_payload
            """,
            (
                tenant_id, now_ts,
                data.get("cpu"), data.get("ram"), data.get("disk"),
                data.get("uptime"),
                load[0] if len(load) > 0 else None,
                load[1] if len(load) > 1 else None,
                load[2] if len(load) > 2 else None,
                data.get("openclaw_version"),
                data.get("docker_total"), data.get("docker_running"),
                data.get("failed_services"),
                failed_names,
                data.get("tls_days_left"),
                data.get("restart_loops"),
                raw.decode(errors="replace")[:8192],
            ),
        )

        # Append to history if enough time has passed since last sample.
        last = conn.execute(
            "SELECT received_at FROM tenant_heartbeat_history "
            "WHERE tenant_id=? ORDER BY received_at DESC LIMIT 1",
            (tenant_id,),
        ).fetchone()
        if not last or (now_ts - last["received_at"]) >= HISTORY_SAMPLE_INTERVAL:
            conn.execute(
                "INSERT INTO tenant_heartbeat_history "
                "(tenant_id, received_at, cpu_percent, ram_percent, disk_percent) "
                "VALUES (?,?,?,?,?)",
                (tenant_id, now_ts, data.get("cpu"),
                 data.get("ram"), data.get("disk")),
            )
            # Prune: keep 7 days
            cutoff = now_ts - (7 * 86400)
            conn.execute(
                "DELETE FROM tenant_heartbeat_history "
                "WHERE tenant_id=? AND received_at < ?",
                (tenant_id, cutoff),
            )
        conn.commit()
    finally:
        conn.close()
    _reply(h, 200, {"ok": True})


def tenant_health_status(heartbeat_row: Optional[dict]) -> str:
    """Derive a single-word status from a heartbeat row.
    'running' | 'degraded' | 'stale' | 'unknown'."""
    if not heartbeat_row:
        return "unknown"
    age = _now() - (heartbeat_row.get("received_at") or 0)
    if age > 600:                   # > 10 min
        return "stale"
    cpu = heartbeat_row.get("cpu_percent") or 0
    ram = heartbeat_row.get("ram_percent") or 0
    disk = heartbeat_row.get("disk_percent") or 0
    failed = heartbeat_row.get("failed_services") or 0
    restarts = heartbeat_row.get("restart_loop_count") or 0
    if failed > 0 or restarts > 0 or disk > 95:
        return "degraded"
    if cpu > 95 or ram > 95:
        return "degraded"
    return "running"


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
    if path == "/api/account/invoices":
        handle_account_invoices(h)
        return True
    if path == "/api/account/profile":
        handle_account_profile_get(h)
        return True
    # Admin — reading
    if path == "/api/admin/tenants":
        handle_admin_tenants(h)
        return True
    if path.startswith("/api/admin/tenants/"):
        # /api/admin/tenants/<id>[/subpath]
        rest = path[len("/api/admin/tenants/"):]
        parts = rest.split("/", 1)
        tenant_id = parts[0]
        sub = parts[1] if len(parts) > 1 else ""
        if sub == "":
            handle_admin_tenant_detail(h, tenant_id)
            return True
        if sub == "notes":
            handle_admin_list_notes(h, tenant_id)
            return True
        if sub == "tasks":
            handle_admin_list_tasks(h, tenant_id)
            return True
        if sub == "activity":
            handle_admin_list_activity(h, tenant_id)
            return True
    if path == "/api/admin/waitlist":
        handle_admin_waitlist(h)
        return True
    if path == "/api/admin/sessions":
        handle_admin_sessions(h)
        return True
    if path == "/api/admin/customers":
        handle_admin_customers(h)
        return True
    if path == "/api/admin/audit":
        handle_admin_audit(h, query)
        return True
    if path == "/api/admin/analytics":
        handle_admin_analytics(h)
        return True
    if path == "/api/admin/support":
        handle_admin_support_list(h)
        return True
    if path == "/api/admin/tasks":
        handle_admin_all_tasks(h)
        return True
    if path == "/api/admin/search":
        handle_admin_search(h, query)
        return True
    if path.startswith("/api/admin/customers/"):
        email = urllib.parse.unquote(path[len("/api/admin/customers/"):])
        handle_admin_customer_detail(h, email)
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
    if path == "/api/account/profile":
        handle_account_profile_update(h)
        return True
    if path == "/api/account/support":
        handle_account_support_create(h)
        return True
    if path.startswith("/api/account/pair/"):
        tenant_id = path[len("/api/account/pair/"):]
        handle_account_pair(h, tenant_id)
        return True
    # ── Admin ─────────────────────────────────────────────────────
    if path.startswith("/api/admin/pair/"):
        tenant_id = path[len("/api/admin/pair/"):]
        handle_admin_issue_pair(h, tenant_id)
        return True
    if path == "/api/admin/sync/stripe":
        handle_admin_sync_stripe(h)
        return True
    if path == "/api/admin/sync/hetzner":
        handle_admin_sync_hetzner(h)
        return True
    if path == "/api/admin/notes":
        handle_admin_note_create(h)
        return True
    if path == "/api/admin/tasks":
        handle_admin_task_create(h)
        return True
    if path.startswith("/api/admin/tasks/") and path.endswith("/complete"):
        tid = path[len("/api/admin/tasks/"):-len("/complete")]
        handle_admin_task_complete(h, tid)
        return True
    if path == "/api/admin/customers":
        handle_admin_customer_upsert(h)
        return True
    if path.startswith("/api/admin/tenants/") and path.endswith("/impersonate"):
        tid = path[len("/api/admin/tenants/"):-len("/impersonate")]
        handle_admin_impersonate(h, tid)
        return True
    if path.startswith("/api/admin/tenants/") and path.endswith("/cancel"):
        tid = path[len("/api/admin/tenants/"):-len("/cancel")]
        handle_admin_cancel_subscription(h, tid)
        return True
    if path.startswith("/api/admin/tenants/") and path.endswith("/flags"):
        tid = path[len("/api/admin/tenants/"):-len("/flags")]
        handle_admin_flag_set(h, tid)
        return True
    if path.startswith("/api/admin/tenants/") and path.endswith("/reset-clawmine"):
        tid = path[len("/api/admin/tenants/"):-len("/reset-clawmine")]
        handle_admin_reset_clawmine(h, tid)
        return True
    if path.startswith("/api/admin/tenants/") and path.endswith("/reboot"):
        tid = path[len("/api/admin/tenants/"):-len("/reboot")]
        handle_admin_hz_action(h, tid, "reboot")
        return True
    if path.startswith("/api/admin/tenants/") and path.endswith("/snapshot"):
        tid = path[len("/api/admin/tenants/"):-len("/snapshot")]
        handle_admin_snapshot(h, tid)
        return True
    if path.startswith("/api/admin/tenants/") and path.endswith("/destroy"):
        tid = path[len("/api/admin/tenants/"):-len("/destroy")]
        handle_admin_destroy(h, tid)
        return True
    return False


# ── Hetzner action helpers ───────────────────────────────────────────

HETZNER_TOKEN_FILE = pathlib.Path("/etc/opspocket/hetzner-token")


def _hetzner_token() -> Optional[str]:
    try:
        return HETZNER_TOKEN_FILE.read_text().strip() or None
    except Exception:
        return None


def _hetzner_post(path: str, body: Optional[dict] = None) -> tuple[int, dict]:
    key = _hetzner_token()
    if not key:
        return 500, {"error": "hetzner token unreadable"}
    data = json.dumps(body or {}).encode()
    req = urllib.request.Request(
        "https://api.hetzner.cloud/v1" + path,
        data=data,
        headers={
            "Authorization": f"Bearer {key}",
            "Content-Type": "application/json",
            "Accept": "application/json",
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=20) as r:
            return r.status, json.loads(r.read())
    except urllib.error.HTTPError as e:
        try:
            return e.code, json.loads(e.read())
        except Exception:
            return e.code, {"error": str(e)}
    except Exception as e:
        return 0, {"error": str(e)}


def _hetzner_delete(path: str) -> tuple[int, dict]:
    key = _hetzner_token()
    if not key:
        return 500, {"error": "hetzner token unreadable"}
    req = urllib.request.Request(
        "https://api.hetzner.cloud/v1" + path,
        headers={"Authorization": f"Bearer {key}"},
        method="DELETE",
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            raw = r.read()
            return r.status, (json.loads(raw) if raw else {"ok": True})
    except urllib.error.HTTPError as e:
        try:
            return e.code, json.loads(e.read())
        except Exception:
            return e.code, {"error": str(e)}
    except Exception as e:
        return 0, {"error": str(e)}


def _tenant_row(tenant_id: str) -> Optional[dict]:
    conn = _db()
    try:
        r = conn.execute("SELECT * FROM tenants WHERE id=?", (tenant_id,)).fetchone()
        return dict(r) if r else None
    finally:
        conn.close()


def handle_admin_hz_action(h, tenant_id: str, action: str):
    t = _tenant_row(tenant_id)
    if not t or not t.get("hetzner_server_id"):
        _reply(h, 200, {"ok": False, "error": "no hetzner server on tenant"})
        return
    sid = t["hetzner_server_id"]
    status, data = _hetzner_post(f"/servers/{sid}/actions/{action}")
    conn = _db()
    try:
        _audit(conn, _admin_actor(h), f"hetzner.{action}",
               target_type="tenant", target_id=tenant_id,
               detail=json.dumps({"hetzner_server_id": sid,
                                   "response_status": status}),
               ip=_remote_ip(h))
        conn.commit()
    finally:
        conn.close()
    if 200 <= status < 300:
        _reply(h, 200, {"ok": True, "action": data.get("action")})
    else:
        _reply(h, 200, {"ok": False, "error": data, "status": status})


def handle_admin_snapshot(h, tenant_id: str):
    t = _tenant_row(tenant_id)
    if not t or not t.get("hetzner_server_id"):
        _reply(h, 200, {"ok": False, "error": "no hetzner server on tenant"})
        return
    sid = t["hetzner_server_id"]
    desc = f"Manual snapshot — tenant {tenant_id} — {_iso_now()}"
    status, data = _hetzner_post(
        f"/servers/{sid}/actions/create_image",
        {
            "type": "snapshot",
            "description": desc,
            "labels": {
                "opspocket_snapshot": "manual",
                "server_name": t.get("domain") or f"t-{tenant_id}",
                "tenant_id": tenant_id,
            },
        },
    )
    conn = _db()
    try:
        _audit(conn, _admin_actor(h), "hetzner.snapshot",
               target_type="tenant", target_id=tenant_id,
               detail=json.dumps({"image_id": data.get("image", {}).get("id"),
                                   "response_status": status}),
               ip=_remote_ip(h))
        conn.commit()
    finally:
        conn.close()
    if 200 <= status < 300:
        _reply(h, 200, {"ok": True,
                         "image_id": data.get("image", {}).get("id"),
                         "action_id": data.get("action", {}).get("id")})
    else:
        _reply(h, 200, {"ok": False, "error": data, "status": status})


def handle_admin_destroy(h, tenant_id: str):
    """Destroy the Hetzner server + mark tenant cancelled.
    Does NOT touch Stripe (that's a separate action)."""
    body = _body_json(h)
    if body.get("confirm") != tenant_id:
        _reply(h, 200, {
            "ok": False,
            "error": "must POST {\"confirm\": \"<tenant_id>\"} to confirm",
        })
        return
    t = _tenant_row(tenant_id)
    if not t:
        _reply(h, 404, {"error": "tenant not found"})
        return
    sid = t.get("hetzner_server_id")
    if sid:
        status, data = _hetzner_delete(f"/servers/{sid}")
    else:
        status, data = 200, {"ok": True, "note": "no hetzner server to delete"}
    conn = _db()
    try:
        conn.execute(
            "UPDATE tenants SET status='cancelled', last_status_change=?, "
            "notes=COALESCE(notes,'') || ' · destroyed by admin ' || ? "
            "WHERE id=?",
            (_iso_now(), _iso_now(), tenant_id),
        )
        _audit(conn, _admin_actor(h), "tenant.destroy",
               target_type="tenant", target_id=tenant_id,
               detail=json.dumps({"hetzner_server_id": sid,
                                   "response_status": status}),
               ip=_remote_ip(h))
        conn.commit()
    finally:
        conn.close()
    _reply(h, 200, {
        "ok": status < 300,
        "hetzner_response": data,
        "status": status,
    })
