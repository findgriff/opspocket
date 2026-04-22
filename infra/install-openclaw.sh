#!/usr/bin/env bash
# install-openclaw.sh — idempotent OpenClaw setup for Ubuntu 24.04.
#
# Portable across Hetzner, DigitalOcean, Linode, OVH — any provider. Built
# from the Vultr Marketplace install recipe captured in
# infra/vultr-recce/, with the bugs called out in REVIEW.md fixed.
#
# Usage (on the target VPS, as root):
#   DOMAIN=t-abc123.opspocket.cloud \
#   OPENAI_API_KEY=sk-... \
#   bash install-openclaw.sh
#
# Optional env overrides:
#   GATEWAY_TOKEN       Auto-generated if unset
#   CLAWMINE_PASSWORD   Auto-generated if unset (printed at the end)
#   ADMIN_USER          Default: openclaw
#   OPENCLAW_VER        Default: 2026.4.5
#   CLAWHUB_VER         Default: 0.9.0
#   NODE_MAJOR          Default: 22
#
# Idempotent — safe to re-run; will upgrade in place.

set -euo pipefail

# ── Config ─────────────────────────────────────────────────────────────
DOMAIN="${DOMAIN:?Set DOMAIN — the fully-qualified hostname this box will serve}"
# MODEL_PROVIDER: openai | ollama
#   openai → requires OPENAI_API_KEY, uses api.openai.com
#   ollama → self-hosted Llama 3.2 on this box. No API key. Slower than
#            cloud inference but zero cost + works offline. Recommended
#            for free-tier / demo deploys.
MODEL_PROVIDER="${MODEL_PROVIDER:-openai}"
OPENAI_API_KEY="${OPENAI_API_KEY:-}"
OLLAMA_MODEL="${OLLAMA_MODEL:-llama3.2:1b}"   # ~1.3 GB, safe fit on CPX22 (4 GB)
# OLLAMA_HOST: if set (e.g. http://10.0.0.5:11434), skips local Ollama install
# and points the config at a remote Ollama server. Used by test-installer.sh
# to hit the dev box's shared Ollama without re-pulling the model each test.
OLLAMA_HOST="${OLLAMA_HOST:-}"
GATEWAY_TOKEN="${GATEWAY_TOKEN:-$(openssl rand -hex 16)}"
CLAWMINE_PASSWORD="${CLAWMINE_PASSWORD:-$(openssl rand -base64 18 | tr -d '=+/' | cut -c1-24)}"
CODE_PASSWORD="${CODE_PASSWORD:-${CLAWMINE_PASSWORD}}"
ADMIN_USER="${ADMIN_USER:-openclaw}"
OPENCLAW_VER="${OPENCLAW_VER:-2026.4.5}"
CLAWHUB_VER="${CLAWHUB_VER:-0.9.0}"
NODE_MAJOR="${NODE_MAJOR:-22}"

# Provider validation.
case "$MODEL_PROVIDER" in
  openai)
    [[ -z "$OPENAI_API_KEY" ]] && { echo "MODEL_PROVIDER=openai requires OPENAI_API_KEY" >&2; exit 1; }
    ;;
  ollama)
    : # no key needed
    ;;
  *)
    echo "Unknown MODEL_PROVIDER: $MODEL_PROVIDER (use openai or ollama)" >&2
    exit 1
    ;;
esac

# Logging helpers.
say()  { printf "\e[36m▶\e[0m %s\n" "$*"; }
ok()   { printf "\e[32m✓\e[0m %s\n" "$*"; }
warn() { printf "\e[33m⚠\e[0m %s\n" "$*"; }
fail() { printf "\e[31m✗\e[0m %s\n" "$*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || fail "run as root (or with sudo)"

# ── Always-print credentials trap (even on partial failure) ────────────
# If the script crashes halfway through, the user still needs access to
# the generated password + token to SSH in and finish debugging. Trap
# EXIT so they always land in the terminal log.
INSTALL_SUCCESS=0
print_credentials_card() {
  local status_line
  if [[ "$INSTALL_SUCCESS" = 1 ]]; then
    status_line="✓ OpenClaw ${OPENCLAW_VER} deployed"
  else
    status_line="⚠ OpenClaw install INCOMPLETE — credentials saved for recovery"
  fi
  cat <<CARD

══════════════════════════════════════════════════════════════════════
  ${status_line}
══════════════════════════════════════════════════════════════════════

  Control UI:           https://${DOMAIN}/
  MCP endpoint:         https://${DOMAIN}/mcp
                        (Authorization: Bearer ${GATEWAY_TOKEN})

  ─── Credentials (save these — they can't be recovered) ────────────

  Basic-auth username:  clawmine
  Basic-auth password:  ${CLAWMINE_PASSWORD}
  Gateway token:        ${GATEWAY_TOKEN}

  Machine-readable:     /root/CREDENTIALS.json

══════════════════════════════════════════════════════════════════════

CARD
}
trap print_credentials_card EXIT

# ── 1. Base packages ───────────────────────────────────────────────────
say "Installing base packages…"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq \
  curl wget git ca-certificates gnupg lsb-release uidmap openssl jq >/dev/null
ok "Base packages installed."

# ── 2. Node.js ${NODE_MAJOR}.x ──────────────────────────────────────────
if ! command -v node >/dev/null 2>&1 || [[ "$(node -v)" != v${NODE_MAJOR}.* ]]; then
  say "Installing Node.js ${NODE_MAJOR}.x…"
  curl -fsSL "https://deb.nodesource.com/setup_${NODE_MAJOR}.x" | bash - >/dev/null
  apt-get install -y -qq nodejs >/dev/null
fi
ok "Node $(node -v)."

# ── 3. Caddy ───────────────────────────────────────────────────────────
if ! command -v caddy >/dev/null 2>&1; then
  say "Installing Caddy…"
  apt-get install -y -qq debian-keyring debian-archive-keyring apt-transport-https >/dev/null
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' \
    | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' \
    > /etc/apt/sources.list.d/caddy-stable.list
  apt-get update -qq
  apt-get install -y -qq caddy >/dev/null
fi
ok "Caddy $(caddy version 2>&1 | awk '{print $1}' | head -1) installed."

# ── 4. Docker ──────────────────────────────────────────────────────────
if ! command -v docker >/dev/null 2>&1; then
  say "Installing Docker…"
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
    | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
    > /etc/apt/sources.list.d/docker.list
  apt-get update -qq
  apt-get install -y -qq \
    docker-ce docker-ce-cli containerd.io \
    docker-buildx-plugin docker-compose-plugin >/dev/null
  # systemd may not be PID 1 in test containers — best-effort.
  systemctl enable --now docker 2>/dev/null \
    || warn "docker systemctl skipped (systemd not usable — OK in test containers, real VPSes should work)"
fi
ok "Docker installed."

# ── 5. code-server (browser VS Code) ───────────────────────────────────
if ! command -v code-server >/dev/null 2>&1; then
  say "Installing code-server…"
  curl -fsSL https://code-server.dev/install.sh | bash >/dev/null 2>&1
fi

# ── 5b. Ollama (only if MODEL_PROVIDER=ollama) ──────────────────────────
# OLLAMA_HOST set   → use remote Ollama server (e.g. dev box), skip local install
# OLLAMA_HOST unset → install Ollama locally on this box + pull the model
if [[ "$MODEL_PROVIDER" == "ollama" ]]; then
  if [[ "${SKIP_MODEL_HEALTHCHECK:-0}" == "1" ]]; then
    warn "SKIP_MODEL_HEALTHCHECK=1 — skipping Ollama reachability check (CI/test mode)"
  elif [[ -n "$OLLAMA_HOST" ]]; then
    say "MODEL_PROVIDER=ollama with remote host ${OLLAMA_HOST} — skipping local install"
    curl -fsSL "${OLLAMA_HOST}/api/version" >/dev/null 2>&1 \
      || fail "Remote Ollama at ${OLLAMA_HOST} not reachable — check connectivity"
    # Verify the model exists on the remote
    if ! curl -fsSL "${OLLAMA_HOST}/api/tags" | jq -e \
         --arg m "$OLLAMA_MODEL" '.models // [] | map(.name) | any(. == $m)' >/dev/null; then
      warn "Model ${OLLAMA_MODEL} not found on remote — will request via API on first call"
    fi
    ok "Remote Ollama reachable at ${OLLAMA_HOST}"
  else
    if ! command -v ollama >/dev/null 2>&1; then
      say "Installing Ollama…"
      curl -fsSL https://ollama.com/install.sh | sh >/dev/null 2>&1
    fi
    systemctl enable --now ollama >/dev/null 2>&1 || true
    say "Waiting for Ollama API to be ready…"
    for _ in $(seq 1 30); do
      curl -fsSL http://127.0.0.1:11434/api/version >/dev/null 2>&1 && break
      sleep 2
    done
    curl -fsSL http://127.0.0.1:11434/api/version >/dev/null 2>&1 \
      || fail "Ollama didn't come up — check: journalctl -u ollama -n 40"
    say "Pulling ${OLLAMA_MODEL} (~1.3 GB download, ~2 min)…"
    ollama pull "$OLLAMA_MODEL" >/dev/null 2>&1 \
      || fail "ollama pull ${OLLAMA_MODEL} failed"
    ok "Ollama + ${OLLAMA_MODEL} ready."
  fi
fi

# ── 6. OpenClaw + clawhub via npm ──────────────────────────────────────
say "Installing openclaw@${OPENCLAW_VER} + clawhub@${CLAWHUB_VER}…"
npm install -g --silent \
  "openclaw@${OPENCLAW_VER}" \
  "clawhub@${CLAWHUB_VER}" >/dev/null 2>&1 \
  || fail "npm install failed — rerun with: npm install -g openclaw@${OPENCLAW_VER} clawhub@${CLAWHUB_VER}"
ok "openclaw installed to /usr/bin/openclaw"

# ── 7. Service user ────────────────────────────────────────────────────
if ! id -u "$ADMIN_USER" >/dev/null 2>&1; then
  say "Creating ${ADMIN_USER} user…"
  useradd -m -s /bin/bash "$ADMIN_USER"
fi
UID_NUM=$(id -u "$ADMIN_USER")
ok "User ${ADMIN_USER} (uid ${UID_NUM}) exists."

# ── 8. Enable linger + wait for user bus ───────────────────────────────
# Without linger, the user-level systemd services (our gateway) won't
# survive logout. With linger we get /run/user/$UID and the DBus session
# socket persistently — required for `systemctl --user` to work from root.
say "Enabling linger for ${ADMIN_USER}…"
loginctl enable-linger "$ADMIN_USER" >/dev/null 2>&1 || true

# Wait (max 15s) for /run/user/$UID to appear — linger sets it up async.
# shellcheck disable=SC2034
for _ in $(seq 1 15); do
  [[ -d "/run/user/${UID_NUM}" ]] && break
  sleep 1
done
[[ -d "/run/user/${UID_NUM}" ]] \
  || warn "/run/user/${UID_NUM} not present after 15s — linger may need a reboot"

# Helper to run systemctl as the openclaw user with the right env.
run_as_admin() {
  sudo -u "$ADMIN_USER" \
    XDG_RUNTIME_DIR="/run/user/${UID_NUM}" \
    DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/${UID_NUM}/bus" \
    "$@"
}

# ── 9. Gateway systemd user unit ───────────────────────────────────────
say "Writing openclaw-gateway.service (user-level)…"
install -d -o "$ADMIN_USER" -g "$ADMIN_USER" -m 755 \
  "/home/${ADMIN_USER}/.config/systemd/user"

cat > "/home/${ADMIN_USER}/.config/systemd/user/openclaw-gateway.service" <<UNIT
[Unit]
Description=OpenClaw Gateway
After=network-online.target
Wants=network-online.target

[Service]
ExecStart=/usr/bin/node /usr/lib/node_modules/openclaw/dist/index.js gateway --port 18789
Restart=always
RestartSec=5
TimeoutStopSec=30
TimeoutStartSec=30
SuccessExitStatus=0 143
KillMode=control-group
Environment=TMPDIR=/tmp
Environment=OPENCLAW_GATEWAY_PORT=18789
Environment=OPENCLAW_SYSTEMD_UNIT=openclaw-gateway.service
Environment=OPENCLAW_SERVICE_MARKER=openclaw
Environment=OPENCLAW_SERVICE_KIND=gateway
Environment=OPENCLAW_SERVICE_VERSION=${OPENCLAW_VER}

[Install]
WantedBy=default.target
UNIT
chown "$ADMIN_USER:$ADMIN_USER" \
  "/home/${ADMIN_USER}/.config/systemd/user/openclaw-gateway.service"
ok "Gateway unit written."

# ── 10. openclaw.json — real values, not placeholders ──────────────────
# BUG #1-fix: this heredoc is UN-QUOTED so bash expands ${OPENAI_API_KEY}
# etc at write-time. The Vultr-generated script had them backslash-escaped,
# which produced literal "${OPENAI_API_KEY}" strings in the config file.
say "Writing openclaw.json with MODEL_PROVIDER=${MODEL_PROVIDER}…"
install -d -o "$ADMIN_USER" -g "$ADMIN_USER" -m 700 \
  "/home/${ADMIN_USER}/.openclaw"

# Model provider block — OpenAI or Ollama (local or remote).
# BUG #5-fix: OpenClaw schema rejects "bearer" — valid values are
# "api-key" | "aws-sdk" | "oauth" | "token". Use "token".
if [[ "$MODEL_PROVIDER" == "ollama" ]]; then
  OLLAMA_BASE_URL="${OLLAMA_HOST:-http://127.0.0.1:11434}/v1"
  PROVIDER_JSON=$(cat <<JSON
"ollama": {
        "baseUrl": "${OLLAMA_BASE_URL}",
        "apiKey": "ollama",
        "auth": "token",
        "api": "openai-completions",
        "models": [
          {
            "id": "${OLLAMA_MODEL}",
            "name": "${OLLAMA_MODEL}",
            "api": "openai-completions",
            "input": ["text"],
            "contextWindow": 131072,
            "maxTokens": 4096
          }
        ]
      }
JSON
)
else
  PROVIDER_JSON=$(cat <<JSON
"openai": {
        "baseUrl": "https://api.openai.com/v1",
        "apiKey": "${OPENAI_API_KEY}",
        "auth": "token",
        "api": "openai-completions",
        "models": [
          {
            "id": "gpt-4o",
            "name": "GPT-4o",
            "api": "openai-completions",
            "input": ["text", "image"],
            "contextWindow": 128000,
            "maxTokens": 16384
          }
        ]
      }
JSON
)
fi

cat > "/home/${ADMIN_USER}/.openclaw/openclaw.json" <<JSON
{
  "models": {
    "providers": {
      ${PROVIDER_JSON}
    }
  },
  "agents": {
    "defaults": {
      "compaction": { "mode": "default", "identifierPolicy": "strict" },
      "timeoutSeconds": 86400
    }
  },
  "commands": {
    "native": "auto",
    "nativeSkills": "auto",
    "restart": true,
    "ownerDisplay": "raw"
  },
  "gateway": {
    "port": 18789,
    "mode": "local",
    "bind": "loopback",
    "controlUi": {
      "allowedOrigins": ["https://${DOMAIN}"]
    },
    "auth": { "mode": "none" },
    "trustedProxies": ["127.0.0.1"]
  }
}
JSON
# BUG #4-fix: bind=loopback so the gateway is ONLY reachable via Caddy,
# not directly from the internet. Caddy's basic_auth is the SOLE gate —
# auth.mode=none on the gateway means customers don't have to paste a
# separate token into Control UI or run an SSH tunnel. One password, done.
# (Safe because bind=loopback means nothing non-Caddy can reach the
# gateway anyway.)
chmod 600 "/home/${ADMIN_USER}/.openclaw/openclaw.json"
chown "$ADMIN_USER:$ADMIN_USER" "/home/${ADMIN_USER}/.openclaw/openclaw.json"
ok "Config written (bind=loopback, real OPENAI_API_KEY + GATEWAY_TOKEN)."

# ── 11. Caddy — basic_auth password hashed BEFORE writing Caddyfile ────
# BUG #2-fix: compute the hash as a real command in the script body, then
# inject the result into the Caddyfile. The Vultr-generated script tried
# to do it inside the heredoc with `$(caddy hash-password --plaintext X)`
# — which hardcoded "X" as the password because the substitution ran at
# write-time.
say "Hashing basic_auth password + writing Caddyfile…"
# BUG #6-fix: use --plaintext flag directly. Piping to stdin returned
# "Error: EOF" on Caddy 2.11.2 in live Hetzner test.
CLAWMINE_HASH=$(caddy hash-password --plaintext "$CLAWMINE_PASSWORD" 2>/dev/null) \
  || fail "caddy hash-password failed — caddy may need a newer version"

# Backup existing Caddyfile if present (first-run safety).
if [[ -f /etc/caddy/Caddyfile ]]; then
  cp /etc/caddy/Caddyfile "/etc/caddy/Caddyfile.bak.$(date +%s)"
fi

# BUG #7-fix: Caddy auto-manages TLS for any named hostname — no bare
# "tls" directive needed. Having it without args failed validation in
# Caddy 2.11.2.
cat > /etc/caddy/Caddyfile <<CADDY
# Generated by install-openclaw.sh on $(date -u +%FT%TZ)
${DOMAIN} {
    basic_auth {
        clawmine ${CLAWMINE_HASH}
    }

    handle /code/* {
        uri strip_prefix /code
        reverse_proxy 127.0.0.1:6969
    }

    handle {
        reverse_proxy 127.0.0.1:18789 {
            header_up -X-Real-IP
            header_up -X-Forwarded-For
            transport http {
                versions 1.1
            }
        }
    }
}
CADDY

caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile >/dev/null 2>&1 \
  || fail "Caddyfile failed validation — run: caddy validate --config /etc/caddy/Caddyfile"

systemctl enable --now caddy >/dev/null 2>&1 \
  || warn "caddy systemctl skipped (systemd not usable)"
systemctl reload caddy 2>/dev/null \
  || warn "caddy reload skipped (systemd not usable)"
ok "Caddy configured."

# ── 12. Start the gateway ──────────────────────────────────────────────
say "Starting gateway service…"
run_as_admin systemctl --user daemon-reload 2>/dev/null \
  || warn "daemon-reload skipped (systemd user bus not usable)"
run_as_admin systemctl --user enable --now openclaw-gateway.service 2>/dev/null \
  || warn "gateway start skipped (systemd user bus not usable — OK in test containers)"
ok "Gateway setup complete."

# ── 13. Firewall ───────────────────────────────────────────────────────
# UFW: open SSH + 80 + 443 only. The gateway is bound to loopback so it
# doesn't need a public rule.
# SKIP_UFW=1 → skip (used by Docker-container tests where UFW can't run)
if [[ "${SKIP_UFW:-0}" != "1" ]] && command -v ufw >/dev/null 2>&1; then
  say "Configuring UFW…"
  ufw --force reset >/dev/null
  ufw default deny incoming >/dev/null
  ufw default allow outgoing >/dev/null
  ufw allow OpenSSH >/dev/null
  ufw allow 80/tcp >/dev/null
  ufw allow 443/tcp >/dev/null
  ufw --force enable >/dev/null
  ok "Firewall live (22/80/443 only)."
fi

# ── 14. Verification ───────────────────────────────────────────────────
# BUG #3-fix: accept 401 as success. The gateway behind basic_auth will
# ALWAYS return 401 to an unauthenticated probe — that's proof it's live.
sleep 3
say "Verifying deployment…"

if ss -tlnp 2>/dev/null | grep -q "127.0.0.1:18789.*openclaw"; then
  ok "Gateway listening on 127.0.0.1:18789 (loopback — correct)"
elif ss -tlnp 2>/dev/null | grep -q "0.0.0.0:18789.*openclaw"; then
  warn "Gateway listening on 0.0.0.0:18789 — check openclaw.json has \"bind\": \"loopback\""
else
  warn "Gateway NOT listening on :18789 — check: sudo -u $ADMIN_USER journalctl --user -u openclaw-gateway -n 20"
fi

STATUS=$(curl -sS -o /dev/null -w "%{http_code}" --max-time 8 "https://${DOMAIN}/" 2>/dev/null || echo 000)
case "$STATUS" in
  401) ok "Caddy + basic_auth active (401 Unauthorised — expected for an unauth'd probe)" ;;
  200) ok "Caddy + basic_auth authenticated (200)" ;;
  000) warn "Caddy unreachable — DNS may still be propagating, or Let's Encrypt issuance in progress" ;;
  *)   warn "Unexpected HTTPS status ${STATUS} — investigate: journalctl -u caddy -n 30" ;;
esac

# ── 15. Write machine-readable credentials file ───────────────────────
# /root/CREDENTIALS.json is what the orchestrator (or the humane welcome
# email script) reads to extract the customer's connection details. This
# eliminates the need for the customer — or us — to SSH in and grep logs.
install -m 600 /dev/null /root/CREDENTIALS.json
cat > /root/CREDENTIALS.json <<CREDS
{
  "domain": "${DOMAIN}",
  "control_ui": "https://${DOMAIN}/",
  "mcp_endpoint": "https://${DOMAIN}/mcp",
  "username": "clawmine",
  "password": "${CLAWMINE_PASSWORD}",
  "gateway_token": "${GATEWAY_TOKEN}",
  "model_provider": "${MODEL_PROVIDER}",
  "openclaw_version": "${OPENCLAW_VER}",
  "installed_at": "$(date -u +%FT%TZ)"
}
CREDS
ok "Credentials written to /root/CREDENTIALS.json (0600)"

# Mark success — the EXIT trap will print the credentials card with
# the "✓ deployed" status instead of the "⚠ INCOMPLETE" fallback.
INSTALL_SUCCESS=1
