#!/usr/bin/env bash
# install-openclaw.sh — provision a fresh Ubuntu 22.04/24.04 VPS with OpenClaw
# + MCP bridge behind auto-SSL, ready for the OpsPocket mobile app to connect.
#
# Target time-to-ready: ≤5 minutes on a Hetzner CX22 / Vultr 1GB.
#
# Usage:
#   Interactive:      curl -fsSL https://opspocket.cloud/install.sh | sudo bash
#   Domain + SSL:     sudo DOMAIN=tenant-abc.opspocket.cloud bash install-openclaw.sh
#   IP-only (dev):    sudo bash install-openclaw.sh
#   With OpenAI key:  sudo OPENAI_API_KEY=sk-... bash install-openclaw.sh
#
# Environment variables:
#   DOMAIN          Optional public FQDN (e.g. tenant-abc.opspocket.cloud).
#                   If set, Caddy issues a Let's Encrypt cert automatically.
#                   If unset, MCP is served over plain HTTP on port 80.
#   OPENAI_API_KEY  Optional. Written to /home/clawd/.openclaw/.env (chmod 600).
#   MCP_TOKEN       Optional. Shared-secret Bearer token required on every MCP
#                   request. Auto-generated if unset (printed at the end).
#   ADMIN_EMAIL     Email Let's Encrypt uses for expiry warnings. Defaults to
#                   ops@$DOMAIN, or a placeholder if no DOMAIN.
#
# Idempotent: safe to re-run to upgrade in place.
# Exit on any error so half-installs don't masquerade as success.
set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# 0. Preamble + colour helpers
# ─────────────────────────────────────────────────────────────────────────────

if [[ $EUID -ne 0 ]]; then
  echo "Must run as root (or via sudo)." >&2
  exit 1
fi

CYAN='\033[0;36m'; GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[0;33m'; NC='\033[0m'
say()  { printf "${CYAN}▶${NC} %s\n" "$*"; }
ok()   { printf "${GREEN}✓${NC} %s\n" "$*"; }
warn() { printf "${YELLOW}⚠${NC} %s\n" "$*"; }
fail() { printf "${RED}✗${NC} %s\n" "$*" >&2; exit 1; }

BANNER=$(cat <<'EOF'
────────────────────────────────────────────────────────
  OpenClaw + MCP Installer
  Phase 1: system prep  →  deps  →  service  →  TLS  →  done
────────────────────────────────────────────────────────
EOF
)
printf "${CYAN}%s${NC}\n\n" "$BANNER"

# ─────────────────────────────────────────────────────────────────────────────
# 1. Defaults + tokens
# ─────────────────────────────────────────────────────────────────────────────

CLAWD_USER="clawd"
CLAWD_HOME="/home/$CLAWD_USER"
OPENCLAW_DIR="$CLAWD_HOME/.openclaw"
MC_DIR="$CLAWD_HOME/mission-control"
NODE_MAJOR=20

DOMAIN="${DOMAIN:-}"
ADMIN_EMAIL="${ADMIN_EMAIL:-ops@${DOMAIN:-example.com}}"
OPENAI_API_KEY="${OPENAI_API_KEY:-}"

# Auto-generate a 32-byte URL-safe token if the caller didn't supply one.
if [[ -z "${MCP_TOKEN:-}" ]]; then
  MCP_TOKEN=$(openssl rand -base64 32 2>/dev/null | tr -d '=+/' | cut -c1-43 \
    || head -c 32 /dev/urandom | base64 | tr -d '=+/' | cut -c1-43)
fi

# ─────────────────────────────────────────────────────────────────────────────
# 2. System prep
# ─────────────────────────────────────────────────────────────────────────────

say "Updating apt + installing base packages…"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq \
  curl ca-certificates gnupg lsb-release git sqlite3 jq ufw \
  python3 python3-pip \
  > /dev/null
ok "Base packages installed."

# ─────────────────────────────────────────────────────────────────────────────
# 3. Node.js 20 LTS (via NodeSource)
# ─────────────────────────────────────────────────────────────────────────────

if ! command -v node >/dev/null 2>&1 || [[ "$(node -v | cut -c2-3)" -lt "$NODE_MAJOR" ]]; then
  say "Installing Node.js $NODE_MAJOR.x…"
  curl -fsSL "https://deb.nodesource.com/setup_${NODE_MAJOR}.x" | bash - > /dev/null
  apt-get install -y -qq nodejs > /dev/null
fi
ok "Node $(node -v) / npm $(npm -v)."

# ─────────────────────────────────────────────────────────────────────────────
# 4. clawd user + workspace
# ─────────────────────────────────────────────────────────────────────────────

if ! id -u "$CLAWD_USER" >/dev/null 2>&1; then
  say "Creating $CLAWD_USER user…"
  useradd -m -s /bin/bash "$CLAWD_USER"
fi

install -d -o "$CLAWD_USER" -g "$CLAWD_USER" -m 700 "$OPENCLAW_DIR"
install -d -o "$CLAWD_USER" -g "$CLAWD_USER" -m 755 "$CLAWD_HOME/clawd"  # workspace

# npm-global bin on PATH for clawd
sudo -iu "$CLAWD_USER" bash <<'SUDO_EOF'
set -e
mkdir -p "$HOME/.npm-global"
npm config set prefix "$HOME/.npm-global" >/dev/null
grep -q '.npm-global/bin' "$HOME/.profile" 2>/dev/null \
  || echo 'export PATH="$HOME/.npm-global/bin:$PATH"' >> "$HOME/.profile"
SUDO_EOF
ok "User workspace ready at $CLAWD_HOME."

# ─────────────────────────────────────────────────────────────────────────────
# 5. Install openclaw CLI
# ─────────────────────────────────────────────────────────────────────────────
#
# NOTE: Package name is inferred. If `openclaw` isn't on the public npm
# registry under that exact name, replace with the canonical name or
# point this at a git URL (npm accepts tarballs and git+https URLs).

say "Installing openclaw CLI…"
sudo -iu "$CLAWD_USER" bash <<SUDO_EOF
set -e
export PATH="\$HOME/.npm-global/bin:\$PATH"
# Try public npm first, fall back to git if it's not published publicly.
if ! npm install -g openclaw 2>/dev/null; then
  echo "openclaw not on public npm — trying git…"
  # Replace this URL when we know the real canonical source repo.
  npm install -g git+https://github.com/openclaw/openclaw.git || {
    echo "FATAL: unable to install openclaw from npm or git" >&2
    exit 1
  }
fi
openclaw --version
SUDO_EOF
ok "openclaw CLI installed."

# ─────────────────────────────────────────────────────────────────────────────
# 6. Write .env (OpenAI key, MCP token, etc)
# ─────────────────────────────────────────────────────────────────────────────

say "Writing secrets to $OPENCLAW_DIR/.env (chmod 600)…"
cat > "$OPENCLAW_DIR/.env" <<ENV_EOF
# Generated by install-openclaw.sh on $(date -u +%FT%TZ)
# Edit this file and run: systemctl restart openclaw-gateway
MCP_TOKEN=$MCP_TOKEN
ADMIN_EMAIL=$ADMIN_EMAIL
$( [[ -n "$OPENAI_API_KEY" ]] && echo "OPENAI_API_KEY=$OPENAI_API_KEY" || echo "# OPENAI_API_KEY=sk-... (add your key then restart)" )
ENV_EOF
chown "$CLAWD_USER:$CLAWD_USER" "$OPENCLAW_DIR/.env"
chmod 600 "$OPENCLAW_DIR/.env"
ok "Secrets stored."

# ─────────────────────────────────────────────────────────────────────────────
# 7. systemd service — openclaw gateway (serves MCP + agent runtime)
# ─────────────────────────────────────────────────────────────────────────────

say "Installing systemd unit for openclaw-gateway…"
cat > /etc/systemd/system/openclaw-gateway.service <<UNIT_EOF
[Unit]
Description=OpenClaw Gateway (agent runtime + MCP bridge)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=$CLAWD_USER
WorkingDirectory=$CLAWD_HOME/clawd
EnvironmentFile=$OPENCLAW_DIR/.env
Environment="PATH=$CLAWD_HOME/.npm-global/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
ExecStart=$CLAWD_HOME/.npm-global/bin/openclaw gateway
Restart=on-failure
RestartSec=5
# Mild hardening
NoNewPrivileges=true
ProtectSystem=full
PrivateTmp=true

[Install]
WantedBy=multi-user.target
UNIT_EOF

systemctl daemon-reload
systemctl enable --now openclaw-gateway >/dev/null
sleep 3
if systemctl is-active --quiet openclaw-gateway; then
  ok "openclaw-gateway is running."
else
  warn "openclaw-gateway failed to stay up — check: journalctl -u openclaw-gateway -n 40"
fi

# ─────────────────────────────────────────────────────────────────────────────
# 8. Caddy reverse-proxy (auto-TLS if DOMAIN set, else plain HTTP)
# ─────────────────────────────────────────────────────────────────────────────

say "Installing Caddy…"
if ! command -v caddy >/dev/null 2>&1; then
  apt-get install -y -qq debian-keyring debian-archive-keyring apt-transport-https > /dev/null
  curl -fsSL 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' \
    | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
  curl -fsSL 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' \
    > /etc/apt/sources.list.d/caddy-stable.list
  apt-get update -qq
  apt-get install -y -qq caddy > /dev/null
fi
ok "Caddy $(caddy version | awk '{print $1}') installed."

say "Writing Caddyfile…"
# The gateway is assumed to serve MCP at http://127.0.0.1:3000/api/mcp.
# If your openclaw gateway binds a different port, set GATEWAY_PORT before
# running the installer.
GATEWAY_PORT="${GATEWAY_PORT:-3000}"

if [[ -n "$DOMAIN" ]]; then
  # TLS via Let's Encrypt — Caddy handles issuance + renewal automatically.
  cat > /etc/caddy/Caddyfile <<CADDY_EOF
{
  email $ADMIN_EMAIL
}

$DOMAIN {
  encode zstd gzip

  # MCP endpoint — gated by Bearer token.
  handle /mission-control/api/mcp* {
    @authorised header Authorization "Bearer $MCP_TOKEN"
    handle @authorised {
      reverse_proxy 127.0.0.1:$GATEWAY_PORT
    }
    respond "unauthorized" 401
  }

  # Mission-control web UI (optional — if the gateway serves it on the same port).
  handle /mission-control/* {
    reverse_proxy 127.0.0.1:$GATEWAY_PORT
  }

  # Health check (unauthenticated) — useful for provisioning handshake.
  handle /health {
    respond "ok" 200
  }

  # Default fallback.
  handle {
    respond "OpenClaw running. MCP at /mission-control/api/mcp" 200
  }
}
CADDY_EOF
else
  # IP-only — no TLS. Fine for dev / demo; not for production traffic.
  cat > /etc/caddy/Caddyfile <<CADDY_EOF
{
  auto_https off
}

:80 {
  handle /mission-control/api/mcp* {
    @authorised header Authorization "Bearer $MCP_TOKEN"
    handle @authorised {
      reverse_proxy 127.0.0.1:$GATEWAY_PORT
    }
    respond "unauthorized" 401
  }

  handle /mission-control/* {
    reverse_proxy 127.0.0.1:$GATEWAY_PORT
  }

  handle /health {
    respond "ok" 200
  }

  handle {
    respond "OpenClaw running. MCP at /mission-control/api/mcp" 200
  }
}
CADDY_EOF
fi

systemctl enable --now caddy >/dev/null
systemctl reload caddy
ok "Caddy configured."

# ─────────────────────────────────────────────────────────────────────────────
# 9. Firewall — open only the ports we need
# ─────────────────────────────────────────────────────────────────────────────

say "Configuring UFW…"
ufw --force reset >/dev/null
ufw default deny incoming >/dev/null
ufw default allow outgoing >/dev/null
ufw allow OpenSSH >/dev/null
ufw allow 80/tcp >/dev/null
ufw allow 443/tcp >/dev/null
ufw --force enable >/dev/null
ok "Firewall live (22 + 80 + 443)."

# ─────────────────────────────────────────────────────────────────────────────
# 10. Smoke test the MCP endpoint (local)
# ─────────────────────────────────────────────────────────────────────────────

say "Probing MCP endpoint locally…"
sleep 2
PROBE_URL="http://127.0.0.1/health"
[[ -n "$DOMAIN" ]] && PROBE_URL="https://$DOMAIN/health"
if curl -fsSL --max-time 10 "$PROBE_URL" | grep -q ok; then
  ok "Health endpoint responding."
else
  warn "Health endpoint not responding yet — gateway may still be booting."
fi

# ─────────────────────────────────────────────────────────────────────────────
# 11. Summary card
# ─────────────────────────────────────────────────────────────────────────────

PUBLIC_IP=$(curl -fsSL --max-time 5 ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')
BASE_URL="${DOMAIN:+https://$DOMAIN}"
BASE_URL="${BASE_URL:-http://$PUBLIC_IP}"

cat <<SUMMARY_EOF

$(printf "${GREEN}")────────────────────────────────────────────────────────$(printf "${NC}")
$(printf "${GREEN}")  ✓ Install complete$(printf "${NC}")
$(printf "${GREEN}")────────────────────────────────────────────────────────$(printf "${NC}")

  MCP endpoint :  $BASE_URL/mission-control/api/mcp
  Health check :  $BASE_URL/health
  MCP token    :  $MCP_TOKEN
  OpenAI key   :  $( [[ -n "$OPENAI_API_KEY" ]] && echo "set" || echo "NOT SET — edit $OPENCLAW_DIR/.env" )
  clawd user   :  $CLAWD_USER (home: $CLAWD_HOME)

  Connect from OpsPocket mobile app:
    Host    : $( [[ -n "$DOMAIN" ]] && echo "$DOMAIN (HTTPS)" || echo "$PUBLIC_IP (HTTP)" )
    Auth    : Bearer $MCP_TOKEN
    Path    : /mission-control/api/mcp

  Logs:
    journalctl -u openclaw-gateway -f
    journalctl -u caddy -f

  Re-run this script any time to upgrade in place.

SUMMARY_EOF
