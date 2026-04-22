#!/usr/bin/env bash
# destroy-dev.sh — wipe the OpsPocket dev box from Hetzner.
#
# For when you want a clean rebuild. Deletes the 'opspocket-dev' server
# via Hetzner API so billing stops immediately.
#
# Usage:
#   HETZNER_TOKEN=hcloud_... ./infra/destroy-dev.sh
#   # or, if token is saved:
#   ./infra/destroy-dev.sh

set -euo pipefail

TOKEN_FILE="$HOME/.opspocket/hetzner-token"
HOSTNAME="opspocket-dev"

say()  { printf "\e[36m▶\e[0m %s\n" "$*"; }
ok()   { printf "\e[32m✓\e[0m %s\n" "$*"; }
warn() { printf "\e[33m⚠\e[0m %s\n" "$*"; }
fail() { printf "\e[31m✗\e[0m %s\n" "$*" >&2; exit 1; }

if [[ -z "${HETZNER_TOKEN:-}" && -f "$TOKEN_FILE" ]]; then
  HETZNER_TOKEN=$(cat "$TOKEN_FILE")
fi
[[ -z "${HETZNER_TOKEN:-}" ]] && fail "HETZNER_TOKEN not set and no saved token."

say "Looking up '$HOSTNAME'…"
SERVER=$(curl -sS -H "Authorization: Bearer $HETZNER_TOKEN" \
  "https://api.hetzner.cloud/v1/servers?name=$HOSTNAME" \
  | jq -r '.servers[0]')

SERVER_ID=$(echo "$SERVER" | jq -r '.id // empty')
if [[ -z "$SERVER_ID" || "$SERVER_ID" == "null" ]]; then
  warn "No server named '$HOSTNAME' found. Nothing to destroy."
  exit 0
fi

PUBLIC_IP=$(echo "$SERVER" | jq -r '.public_net.ipv4.ip')
cat <<CONFIRM

  About to DELETE:
    Hostname : $HOSTNAME
    Server   : $SERVER_ID
    IP       : $PUBLIC_IP

  This is irreversible. Billing stops the moment deletion completes.

CONFIRM
read -rp "Type 'destroy' to confirm: " answer
[[ "$answer" == "destroy" ]] || { echo "Aborted."; exit 1; }

say "Deleting server $SERVER_ID…"
curl -sS -X DELETE -H "Authorization: Bearer $HETZNER_TOKEN" \
  "https://api.hetzner.cloud/v1/servers/$SERVER_ID" | jq . || true

# Clean up local SSH known_hosts entry so next rebuild doesn't scream MITM
if [[ -n "$PUBLIC_IP" ]]; then
  ssh-keygen -R "$PUBLIC_IP" >/dev/null 2>&1 || true
fi

# Clean up local record
rm -f "$(dirname "$0")/devbox.json"

ok "Dev box destroyed. Run provision-dev.sh to rebuild."
