#!/usr/bin/env bash
# first-deploy.sh — interactive wizard for your very first Hetzner deploy.
#
# Walks you through:
#   1. Getting your Hetzner API token
#   2. Making sure your SSH key is registered with Hetzner
#   3. Picking a region + tier
#   4. Entering an OpenAI key (for the new box to use)
#   5. Kicking off provision-tenant.sh with the right args
#
# After this runs successfully once, you'll never need it again — future
# deploys just use provision-tenant.sh directly.
#
# Run it from your Mac:
#   ./infra/first-deploy.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROVISION_SCRIPT="$SCRIPT_DIR/provision-tenant.sh"
TOKEN_FILE="$HOME/.opspocket/hetzner-token"

# ── Colours ─────────────────────────────────────────────────────────────
BOLD=$(tput bold 2>/dev/null || true)
CYAN=$(tput setaf 6 2>/dev/null || true)
GREEN=$(tput setaf 2 2>/dev/null || true)
YELLOW=$(tput setaf 3 2>/dev/null || true)
RED=$(tput setaf 1 2>/dev/null || true)
NC=$(tput sgr0 2>/dev/null || true)

say()  { printf "${CYAN}▶${NC} %s\n" "$*"; }
ok()   { printf "${GREEN}✓${NC} %s\n" "$*"; }
warn() { printf "${YELLOW}⚠${NC} %s\n" "$*"; }
fail() { printf "${RED}✗${NC} %s\n" "$*" >&2; exit 1; }

# ── Pretty banner ───────────────────────────────────────────────────────
cat <<BANNER

${BOLD}${CYAN}╔═══════════════════════════════════════════════════════════════════╗
║            OpsPocket — First-time Hetzner deploy wizard          ║
╚═══════════════════════════════════════════════════════════════════╝${NC}

This walks you through deploying your first OpenClaw instance on
Hetzner. Takes about 5–10 minutes end to end.

You'll need:
  • A Hetzner Cloud account        (free to sign up)
  • Your SSH public key             (we have this: ~/.ssh/id_ed25519.pub)
  • An OpenAI API key               (for the bot to actually think)

BANNER

[[ -f "$PROVISION_SCRIPT" ]] || fail "Can't find provision-tenant.sh in the same folder."

read -rp "Press Enter to begin, or Ctrl-C to bail… " _

# ── Step 1: Hetzner account + API token ────────────────────────────────
echo
echo "${BOLD}Step 1 — Hetzner API token${NC}"
cat <<INSTR

We need a token that lets our script provision servers on your behalf.

  1. Open ${BOLD}https://console.hetzner.cloud/${NC}
  2. Sign up or log in
  3. Create a project (name it 'OpsPocket' or similar)
  4. In the project: left-sidebar → ${BOLD}Security${NC} → ${BOLD}API Tokens${NC}
  5. Click ${BOLD}Generate API Token${NC}, name it 'provisioning', permissions ${BOLD}Read & Write${NC}
  6. Copy the token — starts with ${BOLD}hcloud_${NC} — it only shows once

INSTR

if [[ -f "$TOKEN_FILE" ]]; then
  SAVED_TOKEN=$(cat "$TOKEN_FILE")
  read -rp "We have a saved token from a previous run. Use it? (Y/n) " use_saved
  if [[ -z "$use_saved" || "$use_saved" =~ ^[Yy]$ ]]; then
    HETZNER_TOKEN="$SAVED_TOKEN"
  fi
fi

if [[ -z "${HETZNER_TOKEN:-}" ]]; then
  read -rsp "Paste your Hetzner API token (input hidden): " HETZNER_TOKEN
  echo
  [[ -z "$HETZNER_TOKEN" ]] && fail "No token entered."
fi

# Validate token by making a real API call.
say "Validating token with Hetzner API…"
if ! curl -sSf -H "Authorization: Bearer $HETZNER_TOKEN" \
     "https://api.hetzner.cloud/v1/locations" > /dev/null 2>&1; then
  fail "Token rejected by Hetzner. Double-check you copied all of it."
fi
ok "Token works."

# Save for next time (local-only, never committed).
mkdir -p "$(dirname "$TOKEN_FILE")"
umask 077
echo "$HETZNER_TOKEN" > "$TOKEN_FILE"
chmod 600 "$TOKEN_FILE"
export HETZNER_TOKEN

# ── Step 2: SSH key registration ───────────────────────────────────────
echo
echo "${BOLD}Step 2 — SSH key${NC}"
echo "We'll upload your public key so you can SSH into the new box."
echo

SSH_KEY_NAME="findgriff-macbook"
SSH_PUB="$HOME/.ssh/id_ed25519.pub"
[[ -f "$SSH_PUB" ]] || fail "Can't find $SSH_PUB — generate one with: ssh-keygen -t ed25519"

EXISTING_KEY_ID=$(curl -sS -H "Authorization: Bearer $HETZNER_TOKEN" \
  "https://api.hetzner.cloud/v1/ssh_keys?name=$SSH_KEY_NAME" \
  | jq -r '.ssh_keys[0].id // empty')

if [[ -n "$EXISTING_KEY_ID" ]]; then
  ok "SSH key '$SSH_KEY_NAME' already registered (id: $EXISTING_KEY_ID)."
else
  say "Uploading key to Hetzner…"
  PUBKEY=$(cat "$SSH_PUB")
  RESPONSE=$(curl -sS -X POST https://api.hetzner.cloud/v1/ssh_keys \
    -H "Authorization: Bearer $HETZNER_TOKEN" \
    -H "Content-Type: application/json" \
    -d "$(jq -n --arg name "$SSH_KEY_NAME" --arg pk "$PUBKEY" \
      '{name: $name, public_key: $pk}')")
  NEW_KEY_ID=$(echo "$RESPONSE" | jq -r '.ssh_key.id // empty')
  [[ -n "$NEW_KEY_ID" ]] || { echo "$RESPONSE" | jq . >&2; fail "Failed to upload SSH key."; }
  ok "Uploaded (id: $NEW_KEY_ID)."
fi

# ── Step 3: Region + tier picker ───────────────────────────────────────
echo
echo "${BOLD}Step 3 — Where should the server live?${NC}"
cat <<REGIONS
  1) fsn1  — Falkenstein, Germany    (lowest latency from UK)
  2) nbg1  — Nuremberg, Germany      (same ballpark)
  3) hel1  — Helsinki, Finland
  4) ash   — Ashburn, Virginia (US East)
  5) hil   — Hillsboro, Oregon (US West)
  6) sin   — Singapore

REGIONS
read -rp "Pick 1-6 (default 1): " region_choice
case "${region_choice:-1}" in
  1) REGION="fsn1" ;;
  2) REGION="nbg1" ;;
  3) REGION="hel1" ;;
  4) REGION="ash"  ;;
  5) REGION="hil"  ;;
  6) REGION="sin"  ;;
  *) fail "Invalid choice: $region_choice" ;;
esac
ok "Region: $REGION"

echo
echo "${BOLD}Tier?${NC}"
cat <<TIERS
  1) starter — CPX22 · 2 vCPU · 4 GB  · €7.99/mo   (recommended for test)
  2) pro     — CPX32 · 4 vCPU · 8 GB  · €13.99/mo
  3) agency  — CPX42 · 8 vCPU · 16 GB · €25.49/mo

TIERS
read -rp "Pick 1-3 (default 1): " tier_choice
case "${tier_choice:-1}" in
  1) TIER="starter" ;;
  2) TIER="pro"     ;;
  3) TIER="agency"  ;;
  *) fail "Invalid choice: $tier_choice" ;;
esac
ok "Tier: $TIER"

# ── Step 4: OpenAI key + email ─────────────────────────────────────────
echo
echo "${BOLD}Step 4 — OpenAI API key${NC}"
echo "This gets baked into the server so the agent can actually run."
echo "Starts with ${BOLD}sk-proj-${NC} or ${BOLD}sk-${NC}. Get one at platform.openai.com."
echo
read -rsp "Paste your OpenAI key (input hidden): " OPENAI_KEY
echo
[[ -z "$OPENAI_KEY" ]] && fail "No key entered."
if [[ ! "$OPENAI_KEY" =~ ^sk- ]]; then
  warn "Key doesn't start with 'sk-' — are you sure that's right?"
  read -rp "Continue anyway? (y/N) " cont
  [[ "$cont" =~ ^[Yy]$ ]] || fail "Bailing — re-run with a valid key."
fi
ok "Key captured (not printed)."

echo
read -rp "Your email (used for the server's tenant label): " EMAIL
[[ -z "$EMAIL" ]] && fail "Email required."

# ── Step 5: Confirm + run ──────────────────────────────────────────────
echo
echo "${BOLD}Ready to deploy${NC}"
cat <<CONFIRM

  Email      : $EMAIL
  Region     : $REGION
  Tier       : $TIER
  OpenAI key : sk-${OPENAI_KEY:3:4}…${OPENAI_KEY: -4} (masked)

This will cost ~${YELLOW}€0.01 per minute${NC} the server is running, billed by
Hetzner to the card on your account. Destroy whenever you're done testing.

CONFIRM

read -rp "Provision now? (y/N) " go
[[ "$go" =~ ^[Yy]$ ]] || { echo "Bailed. Nothing provisioned."; exit 0; }

# Run the real provisioner with the values we gathered.
exec "$PROVISION_SCRIPT" \
  --email "$EMAIL" \
  --region "$REGION" \
  --tier "$TIER" \
  --openai-key "$OPENAI_KEY"
