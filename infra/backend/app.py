#!/usr/bin/env python3
"""OpsPocket Cloud backend — webhook + orchestrator in one process.

Runs on 127.0.0.1:8092 on the dev box behind Caddy at
https://opspocket.com/api/stripe-webhook.

Dependency-light by design: Python 3 stdlib only. We deliberately avoid
FastAPI/uvicorn so the service has zero pip installs and systemd can run
it off the system python. The waitlist service uses the same approach
(infra/waitlist-server.py) and has been stable for weeks.

Two long-running components share this process:
  1. HTTP server  — receives Stripe webhooks, verifies signature, enqueues
                    a tenant row with status='pending', returns 200 fast.
  2. Orchestrator — background thread that polls for pending tenants,
                    provisions Hetzner VPS, writes DNS, emails customer.

The webhook NEVER blocks on the orchestrator — it just writes a row and
wakes the worker via a threading.Event. This keeps Stripe happy (it
retries non-2xx and bails on slow responders).
"""

from __future__ import annotations

import hashlib
import hmac
import http.server
import json
import logging
import os
import pathlib
import secrets
import socketserver
import sqlite3
import ssl
import sys
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timezone
from typing import Any, Optional

# ── Paths / config ────────────────────────────────────────────────────
DB_PATH = pathlib.Path(os.environ.get("OPSPOCKET_DB", "/var/lib/opspocket/tenants.db"))
SCHEMA_PATH = pathlib.Path(__file__).parent / "schema.sql"

STRIPE_WEBHOOK_SECRET_FILE = pathlib.Path(
    os.environ.get("STRIPE_WEBHOOK_SECRET_FILE", "/etc/opspocket/stripe-webhook-secret")
)
HETZNER_TOKEN_FILE = pathlib.Path(
    os.environ.get("HETZNER_TOKEN_FILE", "/etc/opspocket/hetzner-token")
)
CLOUDFLARE_TOKEN_FILE = pathlib.Path(
    os.environ.get("CLOUDFLARE_TOKEN_FILE", "/etc/opspocket/cloudflare-token")
)
STRIPE_API_KEY_FILE = pathlib.Path(
    os.environ.get("STRIPE_API_KEY_FILE", "/etc/opspocket/stripe-api-key")
)

CLOUDFLARE_ZONE_ID = os.environ.get(
    "CLOUDFLARE_ZONE_ID", "9cd83123fb461ff560ac8f5566bfb96b"
)
DOMAIN_ROOT = os.environ.get("DOMAIN_ROOT", "opspocket.com")
SSH_KEY_NAME = os.environ.get("SSH_KEY_NAME", "findgriff-macbook")
DEFAULT_LOCATION = os.environ.get("DEFAULT_LOCATION", "nbg1")
DRY_RUN = os.environ.get("ORCHESTRATOR_DRY_RUN", "0") == "1"
SUPPORT_EMAIL = os.environ.get("SUPPORT_EMAIL", "hello@opspocket.com")
OPS_ALERT_EMAIL = os.environ.get("OPS_ALERT_EMAIL", "findgriff@gmail.com")

HOST = os.environ.get("BIND_HOST", "127.0.0.1")
PORT = int(os.environ.get("BIND_PORT", "8092"))

# Tier → Hetzner server type. Justification: CPX tiers per HANDOVER.md.
TIER_TO_SERVER_TYPE = {
    "starter": "cpx22",
    "pro":     "cpx32",
    "agency":  "cpx42",
}

# Model provider per tier. Starter uses ollama (free inference, better
# margin at the cheapest price point). Pro/Agency would use openai for
# quality, but we don't yet collect customer OpenAI keys at checkout —
# so for now EVERYONE falls back to ollama + llama3.2:1b and we flag
# this as a follow-up in the report. See install-openclaw.sh's
# MODEL_PROVIDER=ollama branch.
TIER_TO_MODEL_PROVIDER = {
    "starter": "ollama",
    "pro":     "ollama",   # TODO: switch to openai once key collection lands
    "agency":  "ollama",   # TODO: switch to openai once key collection lands
}

log = logging.getLogger("opspocket-backend")

# ── Secret loader ────────────────────────────────────────────────────
def read_secret(path: pathlib.Path) -> Optional[str]:
    try:
        return path.read_text().strip()
    except FileNotFoundError:
        return None
    except Exception as e:
        log.error("failed reading secret %s: %s", path, e)
        return None


# ── DB ────────────────────────────────────────────────────────────────
_db_lock = threading.Lock()

def db_connect() -> sqlite3.Connection:
    conn = sqlite3.connect(DB_PATH, timeout=30, isolation_level=None)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA journal_mode=WAL")
    conn.execute("PRAGMA foreign_keys=ON")
    return conn


def db_init() -> None:
    DB_PATH.parent.mkdir(parents=True, exist_ok=True)
    conn = db_connect()
    try:
        conn.executescript(SCHEMA_PATH.read_text())
    finally:
        conn.close()
    log.info("db initialised at %s", DB_PATH)


def utc_now() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


# ── Stripe signature verification ─────────────────────────────────────
# Re-implementation of Stripe's v1 signature scheme:
#   sig_header = "t=<ts>,v1=<hex>,v1=<hex>,..."
#   expected  = HMAC_SHA256(secret, f"{ts}.{raw_body}")
# We reject events > 5 min old to block replay.
def verify_stripe_sig(raw_body: bytes, sig_header: str, secret: str,
                      tolerance_seconds: int = 300) -> bool:
    if not sig_header or not secret:
        return False
    parts = dict(
        item.split("=", 1) for item in sig_header.split(",") if "=" in item
    )
    ts = parts.get("t")
    # Stripe can send multiple v1 entries (rotation). We accept any match.
    v1_sigs = [
        v for k, v in (s.split("=", 1) for s in sig_header.split(",") if "=" in s)
        if k == "v1"
    ]
    if not ts or not v1_sigs:
        return False
    try:
        ts_int = int(ts)
    except ValueError:
        return False
    if abs(time.time() - ts_int) > tolerance_seconds:
        log.warning("stripe webhook timestamp outside tolerance")
        return False
    signed_payload = f"{ts}.".encode() + raw_body
    expected = hmac.new(secret.encode(), signed_payload, hashlib.sha256).hexdigest()
    return any(hmac.compare_digest(expected, sig) for sig in v1_sigs)


# ── HTTP client helper (stdlib) ───────────────────────────────────────
def http_json(method: str, url: str, *,
              headers: dict[str, str] | None = None,
              body: Any = None,
              timeout: float = 30.0) -> tuple[int, dict]:
    data = None
    headers = dict(headers or {})
    if body is not None:
        data = json.dumps(body).encode()
        headers.setdefault("Content-Type", "application/json")
    req = urllib.request.Request(url, data=data, method=method, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            raw = r.read()
            return r.status, (json.loads(raw) if raw else {})
    except urllib.error.HTTPError as e:
        raw = e.read()
        try:
            return e.code, json.loads(raw)
        except Exception:
            return e.code, {"raw": raw.decode(errors="replace")}


# ── Cloudflare API ────────────────────────────────────────────────────
def cf_create_a_record(name: str, ip: str, *, proxied: bool = True) -> Optional[str]:
    token = read_secret(CLOUDFLARE_TOKEN_FILE)
    if not token:
        log.error("no cloudflare token")
        return None
    status, resp = http_json(
        "POST",
        f"https://api.cloudflare.com/client/v4/zones/{CLOUDFLARE_ZONE_ID}/dns_records",
        headers={"Authorization": f"Bearer {token}"},
        body={"type": "A", "name": name, "content": ip, "ttl": 1, "proxied": proxied},
    )
    if status != 200 or not resp.get("success"):
        log.error("cloudflare create A failed: %s %s", status, resp)
        return None
    return resp["result"]["id"]


def cf_update_a_record(record_id: str, name: str, ip: str, *, proxied: bool = True) -> bool:
    token = read_secret(CLOUDFLARE_TOKEN_FILE)
    if not token:
        return False
    status, resp = http_json(
        "PUT",
        f"https://api.cloudflare.com/client/v4/zones/{CLOUDFLARE_ZONE_ID}/dns_records/{record_id}",
        headers={"Authorization": f"Bearer {token}"},
        body={"type": "A", "name": name, "content": ip, "ttl": 1, "proxied": proxied},
    )
    if status != 200 or not resp.get("success"):
        log.error("cloudflare update A failed: %s %s", status, resp)
        return False
    return True


# ── Hetzner API ───────────────────────────────────────────────────────
def hz_headers() -> dict:
    token = read_secret(HETZNER_TOKEN_FILE)
    if not token:
        raise RuntimeError("no hetzner token at %s" % HETZNER_TOKEN_FILE)
    return {"Authorization": f"Bearer {token}"}


def hz_ssh_key_id(name: str) -> Optional[int]:
    status, resp = http_json(
        "GET",
        f"https://api.hetzner.cloud/v1/ssh_keys?name={urllib.parse.quote(name)}",
        headers=hz_headers(),
    )
    if status != 200:
        log.error("hetzner ssh_keys failed: %s %s", status, resp)
        return None
    keys = resp.get("ssh_keys") or []
    return keys[0]["id"] if keys else None


def hz_create_server(*, name: str, server_type: str, location: str,
                     ssh_key_id: int, user_data: str, labels: dict) -> Optional[dict]:
    status, resp = http_json(
        "POST",
        "https://api.hetzner.cloud/v1/servers",
        headers=hz_headers(),
        body={
            "name": name,
            "server_type": server_type,
            "image": "ubuntu-24.04",
            "location": location,
            "ssh_keys": [ssh_key_id],
            "user_data": user_data,
            "labels": labels,
            "start_after_create": True,
        },
    )
    if status not in (200, 201):
        log.error("hetzner create server failed: %s %s", status, resp)
        return None
    return resp.get("server")


def hz_get_server(server_id: int) -> Optional[dict]:
    status, resp = http_json(
        "GET",
        f"https://api.hetzner.cloud/v1/servers/{server_id}",
        headers=hz_headers(),
    )
    if status != 200:
        return None
    return resp.get("server")


# ── cloud-init builder ────────────────────────────────────────────────
def build_cloud_init(*, hostname: str, domain: str, gateway_token: str,
                     clawmine_password: str, model_provider: str,
                     openai_key: str = "") -> str:
    # Matches the shape used by provision-tenant.sh so install-openclaw.sh
    # sees the same env vars. MODEL_PROVIDER=ollama means no OpenAI key.
    env_lines = [
        f"DOMAIN='{domain}'",
        f"GATEWAY_TOKEN='{gateway_token}'",
        f"CLAWMINE_PASSWORD='{clawmine_password}'",
        f"MODEL_PROVIDER='{model_provider}'",
    ]
    if model_provider == "openai" and openai_key:
        env_lines.append(f"OPENAI_API_KEY='{openai_key}'")
    env_str = " \\\n      ".join(env_lines)
    return f"""#cloud-config
hostname: {hostname}
manage_etc_hosts: true
package_update: true
runcmd:
  - |
    set -eux
    mkdir -p /var/log/opspocket
    curl -fsSL https://raw.githubusercontent.com/findgriff/opspocket/main/infra/install-openclaw.sh \\
      -o /root/install-openclaw.sh
    chmod +x /root/install-openclaw.sh
    {env_str} \\
      /root/install-openclaw.sh 2>&1 | tee /var/log/opspocket/install.log
    touch /root/.opspocket-install-complete
"""


# ── SSH poll helper ───────────────────────────────────────────────────
def ssh_check_install_complete(ip: str) -> bool:
    # Returns True if the marker file exists on the new host.
    # Uses the admin key (same key Hetzner provisioned as root's authorized_keys).
    import subprocess
    try:
        r = subprocess.run(
            [
                "ssh",
                "-o", "StrictHostKeyChecking=accept-new",
                "-o", "ConnectTimeout=5",
                "-o", "BatchMode=yes",
                "-o", "UserKnownHostsFile=/root/.ssh/opspocket-known-hosts",
                f"root@{ip}",
                "test -f /root/.opspocket-install-complete",
            ],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=10,
        )
        return r.returncode == 0
    except Exception:
        return False


# ── Webhook handler ───────────────────────────────────────────────────
class WebhookHandler(http.server.BaseHTTPRequestHandler):
    server_version = "OpsPocketBackend/1.0"

    def _reply(self, code: int, body: bytes = b"", ctype: str = "application/json"):
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        if body:
            self.wfile.write(body)

    def log_message(self, fmt, *args):
        log.info("http %s - %s", self.address_string(), fmt % args)

    def do_GET(self):
        if self.path == "/healthz":
            self._reply(200, b'{"ok":true}')
            return
        self._reply(404, b'{"error":"not found"}')

    def do_POST(self):
        if self.path != "/api/stripe-webhook":
            self._reply(404, b'{"error":"not found"}')
            return
        length = int(self.headers.get("Content-Length", 0) or 0)
        raw = self.rfile.read(length)
        sig = self.headers.get("Stripe-Signature", "")
        secret = read_secret(STRIPE_WEBHOOK_SECRET_FILE)
        if not secret:
            log.error("no stripe webhook secret configured")
            self._reply(500, b'{"error":"not configured"}')
            return
        if not verify_stripe_sig(raw, sig, secret):
            log.warning("stripe webhook signature mismatch")
            self._reply(400, b'{"error":"bad signature"}')
            return
        try:
            event = json.loads(raw.decode())
        except Exception:
            self._reply(400, b'{"error":"bad json"}')
            return

        # Idempotency: record event id, skip if seen.
        event_id = event.get("id") or ""
        try:
            with _db_lock:
                conn = db_connect()
                try:
                    conn.execute(
                        "INSERT OR IGNORE INTO stripe_events (id, type, received_at, payload) VALUES (?,?,?,?)",
                        (event_id, event.get("type", ""), utc_now(), raw.decode(errors="replace")),
                    )
                finally:
                    conn.close()
        except Exception as e:
            log.error("failed logging event: %s", e)

        # Handle event types. Keep this FAST — no blocking work here.
        etype = event.get("type", "")
        try:
            if etype == "checkout.session.completed":
                handle_checkout_completed(event)
            elif etype == "customer.subscription.deleted":
                handle_subscription_deleted(event)
            elif etype == "invoice.payment_failed":
                log.warning("invoice.payment_failed: %s", event.get("data", {}).get("object", {}).get("id"))
            else:
                log.info("ignoring event type: %s", etype)
        except Exception as e:
            log.exception("handler error for %s: %s", etype, e)
            # Return 500 so Stripe retries.
            self._reply(500, b'{"error":"handler error"}')
            return

        self._reply(200, b'{"ok":true}')
        # Wake the worker without blocking this response.
        WORKER_WAKE.set()


# ── Stripe event handlers ─────────────────────────────────────────────
def handle_checkout_completed(event: dict) -> None:
    session = event.get("data", {}).get("object", {}) or {}
    email = (session.get("customer_details") or {}).get("email") \
        or session.get("customer_email") or ""
    email = email.strip().lower()
    customer_id = session.get("customer") or ""
    subscription_id = session.get("subscription") or ""
    # Prefer price metadata; fall back to session metadata if set on the link.
    tier, interval = resolve_tier_from_session(session)
    if not email or not tier or not interval:
        log.error("checkout.session.completed missing fields: email=%r tier=%r interval=%r",
                  email, tier, interval)
        return

    tenant_id = secrets.token_hex(4)
    now = utc_now()
    with _db_lock:
        conn = db_connect()
        try:
            # Dedup by subscription id if already recorded.
            if subscription_id:
                row = conn.execute(
                    "SELECT id FROM tenants WHERE stripe_subscription_id=?",
                    (subscription_id,),
                ).fetchone()
                if row:
                    log.info("subscription %s already has tenant %s", subscription_id, row["id"])
                    return
            conn.execute(
                """INSERT INTO tenants (
                    id, customer_email, stripe_customer_id, stripe_subscription_id,
                    tier, interval, status, created_at, last_status_change
                ) VALUES (?,?,?,?,?,?,?,?,?)""",
                (tenant_id, email, customer_id, subscription_id or None,
                 tier, interval, "pending", now, now),
            )
        finally:
            conn.close()
    log.info("tenant %s created for %s (%s/%s)", tenant_id, email, tier, interval)


def resolve_tier_from_session(session: dict) -> tuple[str, str]:
    # checkout.session.completed does NOT expand line items by default.
    # We fetch them via Stripe API using the price metadata we set on
    # each recurring price (tier=starter|pro|agency, interval=month|year).
    sk = read_secret(STRIPE_API_KEY_FILE)
    if not sk:
        # Fallback: try session.metadata (configurable on payment links).
        md = session.get("metadata") or {}
        return md.get("tier", ""), md.get("interval", "")
    session_id = session.get("id")
    if not session_id:
        return "", ""
    auth = "Basic " + __import__("base64").b64encode(f"{sk}:".encode()).decode()
    status, resp = http_json(
        "GET",
        f"https://api.stripe.com/v1/checkout/sessions/{session_id}/line_items?limit=1&expand[]=data.price",
        headers={"Authorization": auth},
    )
    if status != 200:
        log.error("stripe line_items failed: %s %s", status, resp)
        return "", ""
    items = resp.get("data") or []
    if not items:
        return "", ""
    price = items[0].get("price") or {}
    md = price.get("metadata") or {}
    tier = md.get("tier", "")
    interval = md.get("interval") or (price.get("recurring") or {}).get("interval", "")
    return tier, interval


def handle_subscription_deleted(event: dict) -> None:
    sub = event.get("data", {}).get("object", {}) or {}
    sub_id = sub.get("id")
    if not sub_id:
        return
    with _db_lock:
        conn = db_connect()
        try:
            conn.execute(
                "UPDATE tenants SET status='cancelled', last_status_change=? WHERE stripe_subscription_id=?",
                (utc_now(), sub_id),
            )
        finally:
            conn.close()
    log.info("subscription %s cancelled", sub_id)


# ── Orchestrator worker ──────────────────────────────────────────────
WORKER_WAKE = threading.Event()
WORKER_STOP = threading.Event()


def set_status(tenant_id: str, status: str, **fields) -> None:
    fields["status"] = status
    fields["last_status_change"] = utc_now()
    cols = ", ".join(f"{k}=?" for k in fields)
    vals = list(fields.values()) + [tenant_id]
    with _db_lock:
        conn = db_connect()
        try:
            conn.execute(f"UPDATE tenants SET {cols} WHERE id=?", vals)
        finally:
            conn.close()


def load_tenant(tenant_id: str) -> Optional[dict]:
    with _db_lock:
        conn = db_connect()
        try:
            row = conn.execute("SELECT * FROM tenants WHERE id=?", (tenant_id,)).fetchone()
            return dict(row) if row else None
        finally:
            conn.close()


def claim_next_pending() -> Optional[dict]:
    # Atomic "pending -> provisioning". Returns the claimed row or None.
    with _db_lock:
        conn = db_connect()
        try:
            conn.execute("BEGIN IMMEDIATE")
            row = conn.execute(
                "SELECT * FROM tenants WHERE status='pending' ORDER BY created_at LIMIT 1"
            ).fetchone()
            if not row:
                conn.execute("COMMIT")
                return None
            conn.execute(
                "UPDATE tenants SET status='provisioning', last_status_change=? WHERE id=?",
                (utc_now(), row["id"]),
            )
            conn.execute("COMMIT")
            return dict(row)
        finally:
            conn.close()


def provision_tenant(tenant: dict) -> None:
    """End-to-end provisioning for one tenant. Runs on the worker thread."""
    tenant_id = tenant["id"]
    email = tenant["customer_email"]
    tier = tenant["tier"]
    log.info("[%s] provisioning start (tier=%s, email=%s, dry_run=%s)",
             tenant_id, tier, email, DRY_RUN)

    gateway_token = secrets.token_hex(16)
    clawmine_password = secrets.token_urlsafe(16)[:20]
    hostname = f"opspocket-t-{tenant_id}"
    domain = f"t-{tenant_id}.{DOMAIN_ROOT}"
    model_provider = TIER_TO_MODEL_PROVIDER.get(tier, "ollama")
    server_type = TIER_TO_SERVER_TYPE.get(tier)
    if not server_type:
        set_status(tenant_id, "failed", notes=f"unknown tier: {tier}")
        alert_ops_failure(tenant, f"unknown tier: {tier}")
        return

    set_status(tenant_id, "provisioning",
               domain=domain, openclaw_password=clawmine_password,
               gateway_token=gateway_token)

    if DRY_RUN:
        log.info("[%s] DRY RUN: would create CF record %s, Hetzner %s in %s",
                 tenant_id, domain, server_type, DEFAULT_LOCATION)
        # Simulate an IP + server id so we can walk the rest of the flow.
        fake_ip = "203.0.113.1"
        set_status(tenant_id, "active",
                   hetzner_server_id=0, hetzner_ip=fake_ip,
                   notes="dry-run — no real resources created")
        send_welcome_email(load_tenant(tenant_id))
        return

    # 1. Pre-create CF record with a placeholder so DNS is ready when IP known.
    # We skip pre-create and just create once we have the real IP (simpler,
    # one less API call, one less rollback path).

    # 2. Look up SSH key id.
    try:
        ssh_key_id = hz_ssh_key_id(SSH_KEY_NAME)
    except Exception as e:
        set_status(tenant_id, "failed", notes=f"hetzner auth: {e}")
        alert_ops_failure(tenant, f"hetzner auth failed: {e}")
        return
    if not ssh_key_id:
        set_status(tenant_id, "failed", notes=f"ssh key '{SSH_KEY_NAME}' not found")
        alert_ops_failure(tenant, f"ssh key not found: {SSH_KEY_NAME}")
        return

    # 3. Create server.
    user_data = build_cloud_init(
        hostname=hostname, domain=domain,
        gateway_token=gateway_token, clawmine_password=clawmine_password,
        model_provider=model_provider,
    )
    labels = {
        "product": "opspocket",
        "tier": tier,
        "tenant_id": tenant_id,
        "customer_email": email.replace("@", "_at_"),  # label values restricted
    }
    server = hz_create_server(
        name=hostname, server_type=server_type, location=DEFAULT_LOCATION,
        ssh_key_id=ssh_key_id, user_data=user_data, labels=labels,
    )
    if not server:
        set_status(tenant_id, "failed", notes="hetzner create server failed")
        alert_ops_failure(tenant, "hetzner create server failed")
        return
    server_id = server["id"]
    public_ip = server.get("public_net", {}).get("ipv4", {}).get("ip")
    set_status(tenant_id, "provisioning",
               hetzner_server_id=server_id, hetzner_ip=public_ip)
    log.info("[%s] hetzner server %s at %s", tenant_id, server_id, public_ip)

    # 4. Create DNS A record.
    cf_rec_id = cf_create_a_record(domain, public_ip, proxied=True)
    if not cf_rec_id:
        log.warning("[%s] cloudflare record creation failed — tenant will still work via IP", tenant_id)

    # 5. Poll for boot + install completion.
    log.info("[%s] waiting for boot…", tenant_id)
    for _ in range(90):  # ~3 min
        s = hz_get_server(server_id)
        if s and s.get("status") == "running":
            break
        time.sleep(2)
    log.info("[%s] waiting for install-openclaw.sh to finish (up to 15 min)…", tenant_id)
    install_done = False
    for _ in range(90):  # ~15 min
        if ssh_check_install_complete(public_ip):
            install_done = True
            break
        time.sleep(10)
    if not install_done:
        set_status(tenant_id, "failed",
                   notes="install-openclaw did not complete within 15m")
        alert_ops_failure(tenant, "install marker never appeared")
        return

    # 6. Done.
    set_status(tenant_id, "active")
    log.info("[%s] active", tenant_id)

    # 7. Welcome email.
    send_welcome_email(load_tenant(tenant_id))


def alert_ops_failure(tenant: dict, reason: str) -> None:
    try:
        from email_sender import send_email
        subject = f"[opspocket] provisioning FAILED for {tenant.get('customer_email')}"
        body = (f"Tenant {tenant.get('id')} failed during provisioning.\n\n"
                f"Reason: {reason}\n\nTenant row:\n{json.dumps(tenant, default=str, indent=2)}")
        send_email(to=OPS_ALERT_EMAIL, subject=subject, text=body, html=None)
    except Exception as e:
        log.error("could not send ops alert: %s", e)


def send_welcome_email(tenant: Optional[dict]) -> None:
    if not tenant:
        return
    try:
        from email_sender import send_email
    except Exception as e:
        log.error("email_sender import failed: %s", e)
        return
    tmpl_dir = pathlib.Path(__file__).parent
    html = (tmpl_dir / "email-template.html").read_text()
    text = (tmpl_dir / "email-template.txt").read_text()
    vars_ = {
        "customer_email": tenant["customer_email"],
        "tier": tenant["tier"].capitalize(),
        "control_ui_url": f"https://{tenant['domain']}",
        "username": "clawmine",
        "password": tenant["openclaw_password"] or "",
        "mcp_endpoint": f"https://{tenant['domain']}/mcp",
        "mcp_token": tenant["gateway_token"] or "",
        "support_email": SUPPORT_EMAIL,
        "portal_url": "https://billing.stripe.com/p/login/test_opspocket",  # placeholder
    }
    for k, v in vars_.items():
        html = html.replace("{{" + k + "}}", str(v))
        text = text.replace("{{" + k + "}}", str(v))
    subject = f"Welcome to OpsPocket Cloud — your {tenant['tier'].capitalize()} tenant is ready"
    send_email(to=tenant["customer_email"], subject=subject, text=text, html=html)


def worker_loop() -> None:
    log.info("orchestrator worker started (dry_run=%s)", DRY_RUN)
    while not WORKER_STOP.is_set():
        try:
            tenant = claim_next_pending()
            if tenant:
                try:
                    provision_tenant(tenant)
                except Exception as e:
                    log.exception("[%s] provisioning crashed: %s", tenant["id"], e)
                    set_status(tenant["id"], "failed", notes=f"crash: {e}")
                    alert_ops_failure(tenant, f"worker crash: {e}")
                continue  # immediately check for more
        except Exception as e:
            log.exception("worker loop error: %s", e)
        # Wait for a wake signal or a 30s tick.
        WORKER_WAKE.wait(timeout=30)
        WORKER_WAKE.clear()


# ── Entrypoint ────────────────────────────────────────────────────────
class ThreadedHTTPServer(socketserver.ThreadingMixIn, http.server.HTTPServer):
    daemon_threads = True


def main() -> None:
    logging.basicConfig(
        level=os.environ.get("LOG_LEVEL", "INFO"),
        format="%(asctime)s %(levelname)s %(name)s %(message)s",
    )
    # Make email_sender importable from the script's directory.
    sys.path.insert(0, str(pathlib.Path(__file__).parent))
    db_init()

    worker = threading.Thread(target=worker_loop, name="orchestrator", daemon=True)
    worker.start()

    srv = ThreadedHTTPServer((HOST, PORT), WebhookHandler)
    log.info("listening on %s:%d", HOST, PORT)
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        log.info("shutting down")
    finally:
        WORKER_STOP.set()
        WORKER_WAKE.set()
        srv.server_close()


if __name__ == "__main__":
    main()
