#!/usr/bin/env bash
# destroy-tenant.sh — delete a customer's Hetzner VPS and purge local record.
#
# Mirrors destroy-dev.sh but targets a specific tenant identified by one of:
#   --tenant-id <id>        (8-char hex from provision-tenant.sh)
#   --email <addr>          (customer email, looked up in tenants.json)
#   --server-id <hetzner>   (Hetzner numeric server id)
#
# Always prompts for confirmation unless --yes is passed.
#
# Does NOT touch DNS — see README.md "DNS cleanup" for the manual step.
#
# Usage:
#   ./infra/destroy-tenant.sh --tenant-id a1b2c3d4
#   ./infra/destroy-tenant.sh --email customer@example.com
#   ./infra/destroy-tenant.sh --server-id 12345678 --yes
#
# Env:
#   HETZNER_TOKEN   required (or saved at ~/.opspocket/hetzner-token)

set -euo pipefail

TOKEN_FILE="$HOME/.opspocket/hetzner-token"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TENANTS_FILE="$SCRIPT_DIR/tenants.json"

TENANT_ID=""
EMAIL=""
SERVER_ID=""
ASSUME_YES=0

say()  { printf "\e[36m▶\e[0m %s\n" "$*"; }
ok()   { printf "\e[32m✓\e[0m %s\n" "$*"; }
warn() { printf "\e[33m⚠\e[0m %s\n" "$*"; }
fail() { printf "\e[31m✗\e[0m %s\n" "$*" >&2; exit 1; }

usage() {
  cat <<'USAGE'
destroy-tenant.sh — destroy a customer VPS and clean up local records.

Usage:
  destroy-tenant.sh (--tenant-id <id> | --email <addr> | --server-id <id>) [--yes]

One of:
  --tenant-id <id>       8-char tenant id from provision-tenant.sh
  --email <addr>         Customer email (looked up in infra/tenants.json)
  --server-id <id>       Hetzner server id (numeric)

Optional:
  --yes                  Skip the 'type destroy to confirm' prompt
  --help                 Show this help

Environment:
  HETZNER_TOKEN          Hetzner Cloud API token (or ~/.opspocket/hetzner-token)

Notes:
  - Removes the matching entry from infra/tenants.json.
  - Cleans up the local ~/.ssh/known_hosts entry for the deleted IP.
  - Does NOT remove DNS records — handle that separately in your DNS provider.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tenant-id) TENANT_ID="$2"; shift 2 ;;
    --email)     EMAIL="$2";     shift 2 ;;
    --server-id) SERVER_ID="$2"; shift 2 ;;
    --yes|-y)    ASSUME_YES=1;   shift ;;
    --help|-h)   usage; exit 0 ;;
    *)           echo "Unknown option: $1" >&2; usage; exit 1 ;;
  esac
done

# Exactly one selector required
SELECTORS=0
[[ -n "$TENANT_ID" ]] && SELECTORS=$((SELECTORS+1))
[[ -n "$EMAIL"     ]] && SELECTORS=$((SELECTORS+1))
[[ -n "$SERVER_ID" ]] && SELECTORS=$((SELECTORS+1))
if [[ "$SELECTORS" -eq 0 ]]; then
  usage
  fail "one of --tenant-id, --email, or --server-id is required"
fi

for tool in curl jq; do
  command -v "$tool" >/dev/null 2>&1 || fail "missing tool: $tool"
done

if [[ -z "${HETZNER_TOKEN:-}" && -f "$TOKEN_FILE" ]]; then
  HETZNER_TOKEN=$(cat "$TOKEN_FILE")
fi
[[ -z "${HETZNER_TOKEN:-}" ]] && fail "HETZNER_TOKEN not set and no saved token at $TOKEN_FILE"

# ── Look up the tenant in tenants.json (best-effort) ──────────────────
LOCAL_RECORD=""
if [[ -f "$TENANTS_FILE" && -s "$TENANTS_FILE" ]]; then
  if [[ -n "$TENANT_ID" ]]; then
    LOCAL_RECORD=$(jq -c --arg id "$TENANT_ID" '.[] | select(.tenant_id == $id)' "$TENANTS_FILE" | head -n1)
  elif [[ -n "$EMAIL" ]]; then
    LOCAL_RECORD=$(jq -c --arg e "$EMAIL" '.[] | select(.email == $e)' "$TENANTS_FILE" | head -n1)
  elif [[ -n "$SERVER_ID" ]]; then
    LOCAL_RECORD=$(jq -c --arg s "$SERVER_ID" '.[] | select(.server_id == $s)' "$TENANTS_FILE" | head -n1)
  fi
fi

# Fill missing selectors from the local record, if present
if [[ -n "$LOCAL_RECORD" ]]; then
  [[ -z "$TENANT_ID" ]] && TENANT_ID=$(echo "$LOCAL_RECORD" | jq -r '.tenant_id // empty')
  [[ -z "$EMAIL"     ]] && EMAIL=$(echo     "$LOCAL_RECORD" | jq -r '.email     // empty')
  [[ -z "$SERVER_ID" ]] && SERVER_ID=$(echo "$LOCAL_RECORD" | jq -r '.server_id // empty')
  LOCAL_IP=$(echo     "$LOCAL_RECORD" | jq -r '.public_ip // empty')
  LOCAL_DOMAIN=$(echo "$LOCAL_RECORD" | jq -r '.domain    // empty')
  LOCAL_TIER=$(echo   "$LOCAL_RECORD" | jq -r '.tier      // empty')
else
  LOCAL_IP=""; LOCAL_DOMAIN=""; LOCAL_TIER=""
  warn "No local record found in $TENANTS_FILE — will rely on Hetzner API lookup"
fi

# ── Resolve server via Hetzner API ────────────────────────────────────
HETZNER_SERVER_JSON=""
if [[ -n "$SERVER_ID" ]]; then
  say "Looking up Hetzner server $SERVER_ID…"
  HETZNER_SERVER_JSON=$(curl -sS -H "Authorization: Bearer $HETZNER_TOKEN" \
    "https://api.hetzner.cloud/v1/servers/$SERVER_ID" | jq -c '.server // empty')
elif [[ -n "$TENANT_ID" ]]; then
  say "Looking up Hetzner server by tenant_id label…"
  HETZNER_SERVER_JSON=$(curl -sS -H "Authorization: Bearer $HETZNER_TOKEN" \
    "https://api.hetzner.cloud/v1/servers?label_selector=tenant_id=$TENANT_ID" \
    | jq -c '.servers[0] // empty')
elif [[ -n "$EMAIL" ]]; then
  say "Looking up Hetzner server by customer_email label…"
  # Hetzner label values can't easily contain '@', but provision-tenant.sh
  # still writes them. Try it; fall back to enumerating all servers.
  HETZNER_SERVER_JSON=$(curl -sS -H "Authorization: Bearer $HETZNER_TOKEN" \
    "https://api.hetzner.cloud/v1/servers" \
    | jq -c --arg e "$EMAIL" '.servers[] | select(.labels.customer_email == $e)' | head -n1)
fi

if [[ -z "$HETZNER_SERVER_JSON" || "$HETZNER_SERVER_JSON" == "null" ]]; then
  warn "No matching server found in Hetzner."
  if [[ -n "$LOCAL_RECORD" ]]; then
    warn "Local record exists — will remove it without calling Hetzner API."
  else
    fail "Nothing to destroy."
  fi
fi

if [[ -n "$HETZNER_SERVER_JSON" ]]; then
  SERVER_ID=$(echo "$HETZNER_SERVER_JSON" | jq -r '.id // empty')
  PUBLIC_IP=$(echo "$HETZNER_SERVER_JSON" | jq -r '.public_net.ipv4.ip // empty')
  HOSTNAME=$(echo  "$HETZNER_SERVER_JSON" | jq -r '.name // empty')
  LABEL_TIER=$(echo  "$HETZNER_SERVER_JSON" | jq -r '.labels.tier // empty')
  LABEL_EMAIL=$(echo "$HETZNER_SERVER_JSON" | jq -r '.labels.customer_email // empty')
  LABEL_TENANT=$(echo "$HETZNER_SERVER_JSON" | jq -r '.labels.tenant_id // empty')
  [[ -z "$TENANT_ID" ]] && TENANT_ID="$LABEL_TENANT"
  [[ -z "$EMAIL"     ]] && EMAIL="$LABEL_EMAIL"
  [[ -z "$LOCAL_IP"     ]] && LOCAL_IP="$PUBLIC_IP"
  [[ -z "$LOCAL_TIER"   ]] && LOCAL_TIER="$LABEL_TIER"
else
  HOSTNAME=""
  PUBLIC_IP="$LOCAL_IP"
fi

# ── Confirm ───────────────────────────────────────────────────────────
cat <<CONFIRM

  About to DELETE tenant:
    Tenant ID : ${TENANT_ID:-(unknown)}
    Email     : ${EMAIL:-(unknown)}
    Server ID : ${SERVER_ID:-(none — local only)}
    Hostname  : ${HOSTNAME:-(unknown)}
    Public IP : ${PUBLIC_IP:-(unknown)}
    Domain    : ${LOCAL_DOMAIN:-(unknown)}
    Tier      : ${LOCAL_TIER:-(unknown)}

  This is irreversible. DNS records are NOT touched — remove them by hand.

CONFIRM

if [[ "$ASSUME_YES" -ne 1 ]]; then
  read -rp "Type 'destroy' to confirm: " answer
  [[ "$answer" == "destroy" ]] || { echo "Aborted."; exit 1; }
fi

# ── Delete the server ─────────────────────────────────────────────────
if [[ -n "$SERVER_ID" && -n "$HETZNER_SERVER_JSON" ]]; then
  say "Deleting Hetzner server $SERVER_ID…"
  HTTP_CODE=$(curl -sS -o /tmp/destroy-tenant-resp.$$ -w '%{http_code}' \
    -X DELETE -H "Authorization: Bearer $HETZNER_TOKEN" \
    "https://api.hetzner.cloud/v1/servers/$SERVER_ID")
  if [[ "$HTTP_CODE" =~ ^2[0-9][0-9]$ ]]; then
    ok "Hetzner accepted DELETE (HTTP $HTTP_CODE)."
  else
    cat /tmp/destroy-tenant-resp.$$ >&2 || true
    rm -f /tmp/destroy-tenant-resp.$$
    fail "Hetzner DELETE failed (HTTP $HTTP_CODE)"
  fi
  rm -f /tmp/destroy-tenant-resp.$$
fi

# ── Clean up local known_hosts ────────────────────────────────────────
if [[ -n "$PUBLIC_IP" ]]; then
  ssh-keygen -R "$PUBLIC_IP" >/dev/null 2>&1 || true
  ok "Removed $PUBLIC_IP from known_hosts."
fi

# ── Remove local tenant record ────────────────────────────────────────
if [[ -f "$TENANTS_FILE" && -s "$TENANTS_FILE" && -n "$TENANT_ID" ]]; then
  TMP="$TENANTS_FILE.tmp"
  jq --arg id "$TENANT_ID" '[.[] | select(.tenant_id != $id)]' "$TENANTS_FILE" > "$TMP"
  mv "$TMP" "$TENANTS_FILE"
  ok "Removed tenant $TENANT_ID from $TENANTS_FILE."
fi

cat <<SUMMARY

╔════════════════════════════════════════════════════════════════════════╗
║                  ✓  Tenant destroyed                                   ║
╚════════════════════════════════════════════════════════════════════════╝

  Tenant ID : ${TENANT_ID:-(n/a)}
  Email     : ${EMAIL:-(n/a)}
  Server    : ${SERVER_ID:-(n/a)}  (billing stopped)
  IP        : ${PUBLIC_IP:-(n/a)}

  TODO (manual): remove DNS record for ${LOCAL_DOMAIN:-(unknown)} from your DNS provider.

SUMMARY
