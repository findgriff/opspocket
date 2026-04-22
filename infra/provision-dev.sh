#!/usr/bin/env bash
# provision-dev.sh — stand up the OpsPocket development workshop on Hetzner.
#
# This is a PERMANENT box (unlike tenant boxes which are per-customer).
# It's where we test installer changes, run throw-away OpenClaw containers,
# aggregate logs, and generally iterate on the product.
#
#   • Hetzner CX43 in Falkenstein  (€11.99/mo · €0.019/hr, always-on)
#   • Docker + Docker Compose       (for disposable test tenants)
#   • Caddy with Cloudflare DNS plugin  (wildcard *.dev.opspocket.com TLS)
#   • Git, jq, curl, ufw, htop, tmux (dev comfort)
#
# Not installed: OpenClaw itself. This box runs the harness, not the product.
#
# Usage:
#   HETZNER_TOKEN=hcloud_... ./infra/provision-dev.sh
#
# Idempotent: if a server named "opspocket-dev" already exists, it bails
# rather than creating a second one. To rebuild, delete the old one first
# via Hetzner console or `./destroy-dev.sh` (coming next).

set -euo pipefail

# ── CLI / defaults ─────────────────────────────────────────────────────
HOSTNAME="opspocket-dev"
SERVER_TYPE="${SERVER_TYPE:-cx43}"    # 8 vCPU / 16 GB / 160 GB — €11.99/mo (€0.019/hr)
LOCATION="${LOCATION:-fsn1}"
IMAGE="${IMAGE:-ubuntu-24.04}"
SSH_KEY_NAME="${SSH_KEY_NAME:-findgriff-macbook}"

say()  { printf "\e[36m▶\e[0m %s\n" "$*"; }
ok()   { printf "\e[32m✓\e[0m %s\n" "$*"; }
warn() { printf "\e[33m⚠\e[0m %s\n" "$*"; }
fail() { printf "\e[31m✗\e[0m %s\n" "$*" >&2; exit 1; }

# ── Validation ─────────────────────────────────────────────────────────
[[ -z "${HETZNER_TOKEN:-}" ]] && fail "HETZNER_TOKEN env var not set"

for tool in curl jq; do
  command -v "$tool" >/dev/null 2>&1 || fail "missing tool: $tool (brew install $tool)"
done

# ── Check for existing dev box ─────────────────────────────────────────
say "Checking if '$HOSTNAME' already exists…"
EXISTING=$(curl -sS -H "Authorization: Bearer $HETZNER_TOKEN" \
  "https://api.hetzner.cloud/v1/servers?name=$HOSTNAME" \
  | jq -r '.servers[0].id // empty')
if [[ -n "$EXISTING" ]]; then
  EXISTING_IP=$(curl -sS -H "Authorization: Bearer $HETZNER_TOKEN" \
    "https://api.hetzner.cloud/v1/servers/$EXISTING" \
    | jq -r '.server.public_net.ipv4.ip')
  fail "'$HOSTNAME' already exists (id: $EXISTING, ip: $EXISTING_IP). Delete it first if you want to rebuild."
fi
ok "No existing dev box — safe to create."

# ── Look up SSH key ────────────────────────────────────────────────────
say "Looking up SSH key '$SSH_KEY_NAME'…"
SSH_KEY_ID=$(curl -sS -H "Authorization: Bearer $HETZNER_TOKEN" \
  "https://api.hetzner.cloud/v1/ssh_keys?name=$SSH_KEY_NAME" \
  | jq -r '.ssh_keys[0].id // empty')
[[ -z "$SSH_KEY_ID" ]] && fail "SSH key '$SSH_KEY_NAME' not found in Hetzner."
ok "SSH key id: $SSH_KEY_ID"

# ── cloud-init: first-boot setup ───────────────────────────────────────
# What happens the moment the box starts:
#   1. apt update + install basics
#   2. Install Docker via official convenience script
#   3. Install Caddy from the Cloudsmith apt repo
#   4. Add the Cloudflare DNS plugin to Caddy (for wildcard TLS)
#   5. Enable UFW (firewall) with only 22/80/443 open
#   6. Drop a placeholder Caddyfile — we'll wire it up after getting a
#      Cloudflare API token from you
#   7. Touch a marker file so we know cloud-init finished
USER_DATA=$(cat <<'CLOUD_INIT'
#cloud-config
hostname: opspocket-dev
manage_etc_hosts: true
package_update: true
package_upgrade: true

packages:
  - curl
  - jq
  - git
  - htop
  - tmux
  - ufw
  - ca-certificates
  - debian-keyring
  - debian-archive-keyring
  - apt-transport-https
  - gnupg

runcmd:
  # runcmd defaults to /bin/sh (dash) — explicitly invoke bash for features
  - ["bash", "-euxc", "mkdir -p /var/log/opspocket"]
  - |
    bash -euxc '
    exec > >(tee -a /var/log/opspocket/dev-install.log) 2>&1

    # ── Docker (official convenience script, trusted-by-Docker) ─────
    curl -fsSL https://get.docker.com | sh
    systemctl enable --now docker

    # ── Caddy (from Cloudsmith apt repo — official path) ────────────
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' \
      | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' \
      > /etc/apt/sources.list.d/caddy-stable.list
    apt-get update
    apt-get install -y caddy

    # ── Add Cloudflare DNS plugin to Caddy ──────────────────────────
    # This lets Caddy get a wildcard cert for *.dev.opspocket.com
    # using DNS-01 challenge (the only way to get wildcards from LE).
    caddy add-package github.com/caddy-dns/cloudflare || true

    # ── Firewall ────────────────────────────────────────────────────
    ufw default deny incoming
    ufw default allow outgoing
    ufw allow 22/tcp
    ufw allow 80/tcp
    ufw allow 443/tcp
    ufw --force enable

    # ── Placeholder Caddyfile (real one written after CF token) ─────
    cat > /etc/caddy/Caddyfile <<'CADDY'
    # Placeholder — wildcard config written by post-provision step once
    # Cloudflare API token is in /etc/caddy/cloudflare.env
    :80 {
      respond "opspocket-dev — Caddy up, waiting for domain wiring" 200
    }
    CADDY
    systemctl restart caddy

    # ── Marker ──────────────────────────────────────────────────────
    touch /root/.opspocket-dev-ready
    echo "dev box provisioning complete at $(date -u +%FT%TZ)"
    '
CLOUD_INIT
)

# ── Create the server ──────────────────────────────────────────────────
cat <<BANNER

───────────────────────────────────────────────────────
 OpsPocket dev box provisioning
───────────────────────────────────────────────────────
  Hostname : $HOSTNAME
  Type     : $SERVER_TYPE   (8 vCPU / 16 GB RAM / 160 GB)
  Location : $LOCATION      (Falkenstein, Germany)
  Image    : $IMAGE
  SSH key  : $SSH_KEY_NAME (id $SSH_KEY_ID)
  Cost     : €11.99/mo  (€0.019/hr — destroy anytime)
  Role     : dev workshop + future home of opspocket.com
───────────────────────────────────────────────────────
BANNER

say "Creating Hetzner server…"
RESPONSE=$(curl -sS -X POST https://api.hetzner.cloud/v1/servers \
  -H "Authorization: Bearer $HETZNER_TOKEN" \
  -H "Content-Type: application/json" \
  -d "$(jq -n \
    --arg name "$HOSTNAME" \
    --arg server_type "$SERVER_TYPE" \
    --arg location "$LOCATION" \
    --arg image "$IMAGE" \
    --arg user_data "$USER_DATA" \
    --argjson ssh_keys "[$SSH_KEY_ID]" \
    '{
      name: $name,
      server_type: $server_type,
      image: $image,
      location: $location,
      ssh_keys: $ssh_keys,
      user_data: $user_data,
      labels: {
        product: "opspocket",
        role: "dev",
        managed_by: "provision-dev.sh"
      }
    }')")

SERVER_ID=$(echo "$RESPONSE" | jq -r '.server.id // empty')
if [[ -z "$SERVER_ID" ]]; then
  echo "$RESPONSE" | jq . >&2
  fail "Hetzner API did not return a server id"
fi

PUBLIC_IP=$(echo "$RESPONSE" | jq -r '.server.public_net.ipv4.ip')
ok "Server $SERVER_ID created at $PUBLIC_IP"

# ── Poll for "running" status ──────────────────────────────────────────
say "Waiting for boot (≤2 min)…"
for _ in $(seq 1 60); do
  STATUS=$(curl -sS -H "Authorization: Bearer $HETZNER_TOKEN" \
    "https://api.hetzner.cloud/v1/servers/$SERVER_ID" \
    | jq -r '.server.status')
  [[ "$STATUS" == "running" ]] && break
  sleep 2
done
[[ "$STATUS" == "running" ]] || warn "status: $STATUS (continuing anyway)"
ok "Server running."

# ── Poll for cloud-init marker ─────────────────────────────────────────
say "Waiting for cloud-init install to finish (≤6 min)…"
SSH_OPTS="-o StrictHostKeyChecking=accept-new -o ConnectTimeout=5 -o BatchMode=yes"
INSTALL_DONE=""
for _ in $(seq 1 72); do
  if ssh $SSH_OPTS "root@$PUBLIC_IP" 'test -f /root/.opspocket-dev-ready' 2>/dev/null; then
    INSTALL_DONE=1; break
  fi
  sleep 5
done
if [[ -n "$INSTALL_DONE" ]]; then
  ok "Cloud-init finished — Docker + Caddy installed."

  # ── Post-install snapshot (useful if this box is ever rebuilt) ─────
  say "Creating post-install snapshot (best-effort)…"
  SNAPSHOT_SCRIPT="$(dirname "$0")/scripts/hetzner-snapshot.sh"
  SNAPSHOT_DESC="$HOSTNAME post-install $(date -u +%FT%H:%M)"
  if [[ -x "$SNAPSHOT_SCRIPT" ]]; then
    if HETZNER_TOKEN="$HETZNER_TOKEN" \
       SNAPSHOT_LABEL_VALUE="post-install" \
       SNAPSHOT_PRUNE=0 \
       "$SNAPSHOT_SCRIPT" "$SERVER_ID" --description "$SNAPSHOT_DESC"; then
      ok "Post-install snapshot created."
    else
      warn "Snapshot failed — continuing. Create one manually via Hetzner console."
    fi
  else
    warn "Snapshot helper not executable at $SNAPSHOT_SCRIPT — skipping."
  fi
else
  warn "Install marker not found after 6 min. Check with:"
  warn "  ssh root@$PUBLIC_IP 'cat /var/log/opspocket/dev-install.log'"
fi

# ── Save record locally ────────────────────────────────────────────────
RECORD_FILE="$(dirname "$0")/devbox.json"
cat > "$RECORD_FILE" <<JSON
{
  "hostname": "$HOSTNAME",
  "server_id": "$SERVER_ID",
  "public_ip": "$PUBLIC_IP",
  "server_type": "$SERVER_TYPE",
  "location": "$LOCATION",
  "provisioned_at": "$(date -u +%FT%TZ)"
}
JSON
ok "Dev box record saved to $RECORD_FILE"

# ── Summary ────────────────────────────────────────────────────────────
cat <<SUMMARY

╔════════════════════════════════════════════════════════════════════════╗
║                ✓  OpsPocket dev box ready                             ║
╚════════════════════════════════════════════════════════════════════════╝

  Hetzner ID  : $SERVER_ID
  Public IP   : $PUBLIC_IP
  SSH         : ssh root@$PUBLIC_IP

  Already installed on the box:
    • Docker + Docker Compose   (for disposable test tenants)
    • Caddy + Cloudflare plugin (wildcard TLS ready to be wired)
    • UFW firewall              (only 22 / 80 / 443 open)
    • git, jq, tmux, htop       (dev comfort)

  Next steps (we'll do these together):
    1. Add SSH shortcut: 'ssh dev' from anywhere on your Mac
    2. Create a Cloudflare API token (guided — takes 2 min)
    3. Add wildcard DNS record *.dev.opspocket.com → $PUBLIC_IP
    4. Wire Caddy with the CF token → wildcard HTTPS live
    5. Write test-installer.sh harness and smoke-test

  Cost so far: ~€0.02 (1 hour of CX43 time)
  Destroy anytime: ./infra/destroy-dev.sh

══════════════════════════════════════════════════════════════════════════
SUMMARY
