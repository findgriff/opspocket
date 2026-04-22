# OpsPocket Cloud backend

Single Python 3 service (stdlib only) that turns a paid Stripe checkout
into a live OpenClaw tenant VPS. Lives on the dev box alongside
`opspocket-waitlist`.

## Components

Everything runs in one process (`app.py`) with two components:

1. **HTTP server** on `127.0.0.1:8092`. Exposes:
   - `POST /api/stripe-webhook` — verifies Stripe signature, logs event,
     writes a `pending` tenant row, returns 200 immediately.
   - `GET /healthz` — liveness probe.
2. **Orchestrator worker** — background thread that claims pending tenant
   rows, generates credentials + domain, creates a Hetzner server with
   cloud-init that runs `install-openclaw.sh`, creates a Cloudflare A
   record, polls for install completion over SSH, flips status to
   `active`, and sends the welcome email.

The webhook NEVER blocks on provisioning. It just inserts the row and
fires `WORKER_WAKE` on its way out.

## Why stdlib-only (no FastAPI)

Zero pip installs on the dev box keeps ops surface tiny, matches the
existing `waitlist-server.py` pattern, and means systemd can use the
system python. Stripe's signature scheme is 15 lines of `hmac` — not
worth a dep.

## Files

| File | Purpose |
|---|---|
| `app.py` | Main service (webhook + orchestrator worker) |
| `email_sender.py` | Pluggable email backend (Resend / SMTP / NO-BACKEND) |
| `email-template.html` | Styled welcome email (red/cyan/black) |
| `email-template.txt` | Plain-text fallback |
| `schema.sql` | SQLite schema — `tenants` + `stripe_events` |
| `opspocket-backend.service` | systemd unit (source-controlled copy) |
| `../backend-env.example` | Template for `/etc/opspocket/backend.env` |

## Deploy to dev box

```bash
# 1. Copy source.
ssh dev "mkdir -p /opt/opspocket/backend /var/lib/opspocket /etc/opspocket"
scp infra/backend/*.py infra/backend/*.html infra/backend/*.txt \
    infra/backend/schema.sql \
    dev:/opt/opspocket/backend/

# 2. Env file + secrets.
scp infra/backend-env.example dev:/etc/opspocket/backend.env
ssh dev "chmod 600 /etc/opspocket/backend.env"
# Create secret files (one per line, no trailing newline):
#   /etc/opspocket/stripe-webhook-secret  (register endpoint first — see below)
#   /etc/opspocket/stripe-api-key         (sk_test_... for test mode)
#   /etc/opspocket/hetzner-token          (already present)
#   /etc/opspocket/cloudflare-token       (copy from ~/.opspocket/cloudflare-token)
# Optional email backend:
#   /etc/opspocket/email-resend-key       OR
#   /etc/opspocket/email-smtp.conf

# 3. systemd unit.
scp infra/backend/opspocket-backend.service dev:/etc/systemd/system/
ssh dev "systemctl daemon-reload && systemctl enable --now opspocket-backend"

# 4. Caddy route (already edited in infra/caddy-sites/opspocket.caddy).
scp infra/caddy-sites/opspocket.caddy dev:/etc/caddy/Caddyfile.d/opspocket.caddy
ssh dev "systemctl reload caddy"
```

## Register the Stripe webhook

Using the test key (one-off from your Mac):

```bash
SK=$(cat ~/.opspocket/stripe-test-sk)
curl -sS -u "$SK:" https://api.stripe.com/v1/webhook_endpoints \
  -d url=https://opspocket.com/api/stripe-webhook \
  -d "enabled_events[]=checkout.session.completed" \
  -d "enabled_events[]=customer.subscription.deleted" \
  -d "enabled_events[]=invoice.payment_failed"
```

The response contains a `secret` (starts with `whsec_`). Save it:

```bash
ssh dev "install -m 0600 /dev/null /etc/opspocket/stripe-webhook-secret"
ssh dev "cat > /etc/opspocket/stripe-webhook-secret" <<< "whsec_XXXX"
ssh dev "systemctl restart opspocket-backend"
```

## Validate

```bash
# Health.
curl -sS https://opspocket.com/healthz  # 404 — healthz is only on 127.0.0.1:8092
ssh dev "curl -sS http://127.0.0.1:8092/healthz"

# Fire a test event via the Stripe CLI on your Mac:
stripe listen --forward-to https://opspocket.com/api/stripe-webhook
stripe trigger checkout.session.completed

# Inspect DB.
ssh dev "sqlite3 /var/lib/opspocket/tenants.db 'SELECT id,customer_email,tier,status FROM tenants;'"

# Follow logs.
ssh dev "journalctl -u opspocket-backend -f"
```

## Dry-run mode

Set `ORCHESTRATOR_DRY_RUN=1` in `/etc/opspocket/backend.env` and restart.
The worker will simulate provisioning (no Hetzner/Cloudflare calls) and
jump straight to `active`. Useful for testing the webhook + email path
without spending money.

## Known gaps

- **Email backend** — not yet configured. Provide either a Resend API
  key at `/etc/opspocket/email-resend-key` or an SMTP config at
  `/etc/opspocket/email-smtp.conf`. Without one the welcome email is
  logged as `[email] NO BACKEND` and the flow still completes.
- **OpenAI key collection** — all tiers currently run Ollama (llama3.2:1b).
  To use OpenAI on Pro/Agency we need a way to collect customer keys:
  custom field in Stripe Checkout, or a post-signup onboarding page.
- **Stripe live mode** — only test mode is wired up. Switch to `sk_live_*`
  and register a new webhook against live mode when we flip.
- **Portal URL** — `{{portal_url}}` in the email is a placeholder. Create
  a Stripe Customer Portal config and wire the configured URL in.
