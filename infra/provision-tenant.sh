#!/usr/bin/env bash
# provision-tenant.sh — end-to-end customer onboarding on Hetzner Cloud.
#
# This is the MANUAL-but-repeatable MVP of the orchestrator. Run it from
# your Mac each time a new customer signs up; it does everything the
# eventual web signup flow will do (provision + configure + email-ready
# credentials) — just with you in the loop instead of Stripe webhooks.
#
# Usage:
#   ./infra/provision-tenant.sh \
#     --email craig@example.com \
#     --region fsn1 \
#     --tier starter \
#     --openai-key sk-proj-...
#
# Required env:
#   HETZNER_TOKEN    Your Hetzner Cloud API token (Console → Security → API)
#
# Optional env:
#   SSH_KEY_NAME     Name of an existing Hetzner SSH key to attach (default:
#                    "findgriff-macbook" — that's the key you added today).
#                    The customer never logs in via SSH — this is for you
#                    to have ops access if anything goes wrong.
#   DOMAIN_ROOT      Your public DNS zone (default: opspocket.cloud).
#                    Tenants get t-<id>.<DOMAIN_ROOT>. If you haven't set
#                    up wildcard DNS yet, use sslip.io as the domain root
#                    and each tenant gets auto-resolving DNS via its IP.
#
# What it does:
#   1. Validates inputs + Hetzner token
#   2. Generates: tenant_id, MCP gateway token, basic_auth password
#   3. Provisions a Hetzner server via API with cloud-init user-data that
#      curl-pipes our install-openclaw.sh (on main branch) with all params
#   4. Polls for server ready
#   5. Waits for install to complete (cloud-init finish)
#   6. Prints a credentials card you paste into the welcome email
#   7. Saves a local record in tenants.json so you can track who's where
#
# Cost: ~€0.01 per minute the server exists. Destroy with:
#   curl -X DELETE -H "Authorization: Bearer $HETZNER_TOKEN" \
#     https://api.hetzner.cloud/v1/servers/<id>

set -euo pipefail

# ── CLI parsing ────────────────────────────────────────────────────────
EMAIL=""
REGION=""
TIER="starter"
OPENAI_KEY=""
DOMAIN_ROOT="${DOMAIN_ROOT:-opspocket.cloud}"
SSH_KEY_NAME="${SSH_KEY_NAME:-findgriff-macbook}"

usage() {
  cat <<'USAGE'
provision-tenant.sh — provision a Hetzner VPS for a new OpsPocket customer.

Usage:
  provision-tenant.sh --email <addr> --region <code> [--tier <name>] [--openai-key <key>]

Required:
  --email <addr>        Customer's email (used for the server hostname + tracking)
  --region <code>       Hetzner region: fsn1 (Frankfurt), nbg1 (Nuremberg),
                        hel1 (Helsinki), ash (Ashburn VA), hil (Hillsboro OR),
                        sin (Singapore)

Optional:
  --tier <name>         starter | pro | agency  (default: starter)
                        starter = cpx22 (2 vCPU / 4 GB)  · £7.99/mo
                        pro     = cpx32 (4 vCPU / 8 GB)  · £13.99/mo
                        agency  = cpx42 (8 vCPU / 16 GB) · £25.49/mo
  --openai-key <key>    Customer's OpenAI API key (required for now)
  --help                Show this message

Environment:
  HETZNER_TOKEN         Required — Hetzner Cloud API token
  SSH_KEY_NAME          Name of your admin SSH key in Hetzner (default: findgriff-macbook)
  DOMAIN_ROOT           Public DNS zone (default: opspocket.cloud)

Example:
  HETZNER_TOKEN=hcloud_... \
  ./provision-tenant.sh \
    --email test@example.com \
    --region fsn1 \
    --tier starter \
    --openai-key sk-proj-...
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --email)       EMAIL="$2"; shift 2 ;;
    --region)      REGION="$2"; shift 2 ;;
    --tier)        TIER="$2"; shift 2 ;;
    --openai-key)  OPENAI_KEY="$2"; shift 2 ;;
    --help|-h)     usage; exit 0 ;;
    *)             echo "Unknown option: $1" >&2; usage; exit 1 ;;
  esac
done

# ── Colour helpers ─────────────────────────────────────────────────────
say()  { printf "\e[36m▶\e[0m %s\n" "$*"; }
ok()   { printf "\e[32m✓\e[0m %s\n" "$*"; }
warn() { printf "\e[33m⚠\e[0m %s\n" "$*"; }
fail() { printf "\e[31m✗\e[0m %s\n" "$*" >&2; exit 1; }

# ── Validation ─────────────────────────────────────────────────────────
[[ -z "$EMAIL" ]]        && { usage; fail "--email is required"; }
[[ -z "$REGION" ]]       && { usage; fail "--region is required"; }
[[ -z "$OPENAI_KEY" ]]   && { usage; fail "--openai-key is required (OpenAI provider is the only supported one today)"; }
[[ -z "${HETZNER_TOKEN:-}" ]] && fail "HETZNER_TOKEN env var not set"

for tool in curl jq openssl; do
  command -v "$tool" >/dev/null 2>&1 || fail "missing tool: $tool"
done

# Tier → Hetzner server type
case "$TIER" in
  starter) SERVER_TYPE="cpx22" ;;
  pro)     SERVER_TYPE="cpx32" ;;
  agency)  SERVER_TYPE="cpx42" ;;
  *)       fail "unknown tier: $TIER (pick starter, pro, or agency)" ;;
esac

# ── Identifiers + secrets ──────────────────────────────────────────────
TENANT_ID=$(openssl rand -hex 4)
GATEWAY_TOKEN=$(openssl rand -hex 16)
CLAWMINE_PASSWORD=$(openssl rand -base64 18 | tr -d '=+/' | cut -c1-20)
HOSTNAME="opspocket-$TENANT_ID"
DOMAIN="t-${TENANT_ID}.${DOMAIN_ROOT}"

cat <<BANNER
───────────────────────────────────────────────────────
 OpsPocket tenant provisioning
───────────────────────────────────────────────────────
  Customer : $EMAIL
  Tenant   : $TENANT_ID  ($HOSTNAME)
  Domain   : $DOMAIN
  Region   : $REGION
  Tier     : $TIER ($SERVER_TYPE)
───────────────────────────────────────────────────────
BANNER

# ── Look up the admin SSH key in Hetzner ───────────────────────────────
say "Looking up SSH key '$SSH_KEY_NAME'…"
SSH_KEY_ID=$(curl -sS -H "Authorization: Bearer $HETZNER_TOKEN" \
  "https://api.hetzner.cloud/v1/ssh_keys?name=$SSH_KEY_NAME" \
  | jq -r '.ssh_keys[0].id // empty')
[[ -z "$SSH_KEY_ID" ]] && fail "SSH key '$SSH_KEY_NAME' not found in Hetzner — add it first or set SSH_KEY_NAME"
ok "SSH key id: $SSH_KEY_ID"

# ── Build cloud-init user-data ─────────────────────────────────────────
# The VPS runs this on first boot. It pulls install-openclaw.sh from
# GitHub main and runs it with all the tenant-specific parameters baked
# in. ~3–5 minutes from VPS boot to fully working OpenClaw.
USER_DATA=$(cat <<CLOUD_INIT
#cloud-config
hostname: $HOSTNAME
manage_etc_hosts: true
package_update: true
runcmd:
  - |
    set -eux
    mkdir -p /var/log/opspocket
    curl -fsSL https://raw.githubusercontent.com/findgriff/opspocket/main/infra/install-openclaw.sh \\
      -o /root/install-openclaw.sh
    chmod +x /root/install-openclaw.sh
    DOMAIN='$DOMAIN' \\
      OPENAI_API_KEY='$OPENAI_KEY' \\
      GATEWAY_TOKEN='$GATEWAY_TOKEN' \\
      CLAWMINE_PASSWORD='$CLAWMINE_PASSWORD' \\
      /root/install-openclaw.sh 2>&1 | tee /var/log/opspocket/install.log
    # Mark install done for the poll loop.
    touch /root/.opspocket-install-complete
CLOUD_INIT
)

# ── Create the server via Hetzner API ─────────────────────────────────
say "Creating Hetzner server ($SERVER_TYPE in $REGION)…"
RESPONSE=$(curl -sS -X POST https://api.hetzner.cloud/v1/servers \
  -H "Authorization: Bearer $HETZNER_TOKEN" \
  -H "Content-Type: application/json" \
  -d "$(jq -n \
    --arg name "$HOSTNAME" \
    --arg server_type "$SERVER_TYPE" \
    --arg location "$REGION" \
    --arg user_data "$USER_DATA" \
    --argjson ssh_keys "[$SSH_KEY_ID]" \
    '{
      name: $name,
      server_type: $server_type,
      image: "ubuntu-24.04",
      location: $location,
      ssh_keys: $ssh_keys,
      user_data: $user_data,
      labels: {
        product: "opspocket",
        tier: "'"$TIER"'",
        tenant_id: "'"$TENANT_ID"'",
        customer_email: "'"$EMAIL"'"
      }
    }')")

SERVER_ID=$(echo "$RESPONSE" | jq -r '.server.id // empty')
if [[ -z "$SERVER_ID" ]]; then
  echo "$RESPONSE" | jq . >&2
  fail "Hetzner API did not return a server id"
fi

PUBLIC_IP=$(echo "$RESPONSE" | jq -r '.server.public_net.ipv4.ip')
ok "Server $SERVER_ID created at $PUBLIC_IP"

# ── Poll for server "running" ──────────────────────────────────────────
say "Waiting for server to boot (≤2 min)…"
for _ in $(seq 1 60); do
  STATUS=$(curl -sS -H "Authorization: Bearer $HETZNER_TOKEN" \
    "https://api.hetzner.cloud/v1/servers/$SERVER_ID" \
    | jq -r '.server.status')
  [[ "$STATUS" == "running" ]] && break
  sleep 2
done
[[ "$STATUS" == "running" ]] || warn "server still in status: $STATUS (continuing anyway)"
ok "Server running."

# ── Poll for install completion (cloud-init marker file) ──────────────
say "Waiting for install-openclaw.sh to finish (≤8 min)…"
SSH_OPTS="-o StrictHostKeyChecking=accept-new -o ConnectTimeout=5 -o BatchMode=yes"
INSTALL_DONE=""
for _ in $(seq 1 90); do
  if ssh $SSH_OPTS "root@$PUBLIC_IP" 'test -f /root/.opspocket-install-complete' 2>/dev/null; then
    INSTALL_DONE=1; break
  fi
  sleep 10
done
if [[ -n "$INSTALL_DONE" ]]; then
  ok "OpenClaw install complete."
else
  warn "Install marker not found after 15 min — check: ssh root@$PUBLIC_IP 'cat /var/log/opspocket/install.log'"
fi

# ── Save a local record ────────────────────────────────────────────────
RECORD_FILE="$(dirname "$0")/tenants.json"
touch "$RECORD_FILE"
[[ ! -s "$RECORD_FILE" ]] && echo "[]" > "$RECORD_FILE"
jq --arg email "$EMAIL" \
   --arg tenant_id "$TENANT_ID" \
   --arg server_id "$SERVER_ID" \
   --arg public_ip "$PUBLIC_IP" \
   --arg domain "$DOMAIN" \
   --arg tier "$TIER" \
   --arg region "$REGION" \
   --arg provisioned_at "$(date -u +%FT%TZ)" \
  '. + [{email:$email, tenant_id:$tenant_id, server_id:$server_id, public_ip:$public_ip, domain:$domain, tier:$tier, region:$region, provisioned_at:$provisioned_at}]' \
  "$RECORD_FILE" > "$RECORD_FILE.tmp" && mv "$RECORD_FILE.tmp" "$RECORD_FILE"
ok "Tenant record saved to $RECORD_FILE"

# ── Summary card — copy-paste into the customer welcome email ─────────
cat <<SUMMARY

╔════════════════════════════════════════════════════════════════════════╗
║                 ✓  OpsPocket tenant ready to email                    ║
╚════════════════════════════════════════════════════════════════════════╝

  Customer email      : $EMAIL

  Hosted at           : https://$DOMAIN
                        (DNS: point A record $DOMAIN → $PUBLIC_IP)

  Username            : clawmine
  Password            : $CLAWMINE_PASSWORD

  MCP endpoint        : https://$DOMAIN/mcp
  MCP auth token      : $GATEWAY_TOKEN

  Server info
    Hetzner ID        : $SERVER_ID
    Public IP         : $PUBLIC_IP
    Region            : $REGION
    Tier              : $TIER ($SERVER_TYPE)

  Admin access
    ssh root@$PUBLIC_IP
    Install log       : /var/log/opspocket/install.log

  Destroy (if needed)
    curl -X DELETE -H "Authorization: Bearer \$HETZNER_TOKEN" \\
      https://api.hetzner.cloud/v1/servers/$SERVER_ID

══════════════════════════════════════════════════════════════════════════

Paste this block into your welcome email (minus the "Admin access" /
"Destroy" sections — those are for you). The customer needs:

  1. The $DOMAIN URL
  2. clawmine + $CLAWMINE_PASSWORD to log into Control UI
  3. The MCP token so the iOS app can connect
  4. A link to the iOS app download

SUMMARY
