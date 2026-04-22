#!/usr/bin/env bash
# test-installer.sh — smoke-test infra/install-openclaw.sh in a throwaway Docker container.
#
# Runs on the DEV BOX (opspocket-dev), not your Mac. SSH there first or
# invoke via `ssh dev 'bash -s' < test-installer.sh`.
#
# What it does:
#   1. Spins up a fresh Ubuntu 24.04 container (disposable, no port mapping)
#   2. Pastes install-openclaw.sh from this repo's GitHub main branch in
#   3. Runs it inside the container with test parameters
#   4. Verifies gateway + Caddy came up
#   5. Prints pass/fail summary
#   6. Destroys the container
#
# Runtime: ~90 seconds per test (vs ~3 min + €0.02 per real VPS cycle)
# Cost:    free (just CPU/RAM on the dev box we're already paying for)
#
# Usage:
#   # From your Mac:
#   ssh dev "bash -s" < infra/test-installer.sh
#
#   # Or copy it there and run:
#   scp infra/test-installer.sh dev:/root/
#   ssh dev "/root/test-installer.sh"
#
# Env overrides:
#   INSTALLER_URL  URL to curl install-openclaw.sh from
#                  (default: GitHub main branch)
#   INSTALLER_REF  Git ref to test (default: main — try a PR branch for
#                  testing changes before merging)
#   MODEL_PROVIDER openai | ollama  (default: ollama — uses dev box's
#                  local Ollama endpoint, no API cost)

set -euo pipefail

INSTALLER_REF="${INSTALLER_REF:-main}"
INSTALLER_URL="${INSTALLER_URL:-https://raw.githubusercontent.com/findgriff/opspocket/${INSTALLER_REF}/infra/install-openclaw.sh}"
MODEL_PROVIDER="${MODEL_PROVIDER:-ollama}"

# ── Colours ─────────────────────────────────────────────────────────
say()  { printf "\e[36m▶\e[0m %s\n" "$*"; }
ok()   { printf "\e[32m✓\e[0m %s\n" "$*"; }
warn() { printf "\e[33m⚠\e[0m %s\n" "$*"; }
fail() { printf "\e[31m✗\e[0m %s\n" "$*" >&2; exit 1; }

command -v docker >/dev/null 2>&1 || fail "docker not installed (this should run on dev box)"

RUN_ID=$(date +%s | tail -c 6)
CONTAINER="test-openclaw-$RUN_ID"
TEST_DOMAIN="test-$RUN_ID.dev.opspocket.com"

# Throwaway test creds — never leave the container
TEST_PASSWORD="testpass-$RUN_ID"
TEST_TOKEN=$(tr -dc 'a-f0-9' < /dev/urandom | head -c 32)

cat <<BANNER

───────────────────────────────────────────────────────
 OpenClaw installer smoke test
───────────────────────────────────────────────────────
  Container  : $CONTAINER
  Installer  : $INSTALLER_URL
  Domain     : $TEST_DOMAIN  (not public — internal-only)
  Provider   : $MODEL_PROVIDER
───────────────────────────────────────────────────────
BANNER

# ── Always clean up, even if we crash ──────────────────────────────
cleanup() {
  if docker ps -a --format '{{.Names}}' | grep -q "^$CONTAINER$"; then
    say "Cleaning up container $CONTAINER…"
    docker rm -f "$CONTAINER" >/dev/null
  fi
}
trap cleanup EXIT

# ── Spin up throwaway Ubuntu 24.04 ─────────────────────────────────
say "Starting fresh Ubuntu 24.04 container…"
docker run -d \
  --name "$CONTAINER" \
  --privileged \
  --cgroupns=host \
  --tmpfs /run \
  --tmpfs /run/lock \
  -v /sys/fs/cgroup:/sys/fs/cgroup:rw \
  ubuntu:24.04 \
  /bin/sleep infinity >/dev/null
ok "Container started."

# ── Install systemd + basic tools inside (minimal image doesn't have them) ──
say "Bootstrapping container with systemd + curl (needed by installer)…"
docker exec "$CONTAINER" bash -c '
  apt-get update -qq
  apt-get install -y -qq systemd systemd-sysv curl sudo ca-certificates
  # Pretend we booted with systemd (for services to start properly)
  exec /lib/systemd/systemd --system &
  sleep 3
' >/dev/null 2>&1 || warn "bootstrap had non-fatal warnings"

# ── Prep ollama endpoint for the installer ─────────────────────────
# The dev box runs Ollama on 127.0.0.1:11434 (not reachable from container
# by default). We use the Docker bridge gateway address instead.
DOCKER_GATEWAY=$(docker exec "$CONTAINER" sh -c "ip route | awk '/default/ {print \$3}'")
OLLAMA_URL="http://${DOCKER_GATEWAY}:11434"

# ── Download installer inside container ────────────────────────────
say "Fetching install-openclaw.sh from $INSTALLER_REF…"
docker exec "$CONTAINER" curl -fsSL "$INSTALLER_URL" -o /root/install-openclaw.sh
docker exec "$CONTAINER" chmod +x /root/install-openclaw.sh

# ── Run the installer ──────────────────────────────────────────────
say "Running installer (this is the test — takes ~60s)…"
set +e
docker exec \
  -e DOMAIN="$TEST_DOMAIN" \
  -e MODEL_PROVIDER="$MODEL_PROVIDER" \
  -e OLLAMA_HOST="$OLLAMA_URL" \
  -e CLAWMINE_PASSWORD="$TEST_PASSWORD" \
  -e GATEWAY_TOKEN="$TEST_TOKEN" \
  -e SKIP_UFW="1" \
  "$CONTAINER" \
  /root/install-openclaw.sh
INSTALL_EXIT=$?
set -e

# ── Verify: what's running inside? ─────────────────────────────────
echo
say "Verification…"

check() {
  local label="$1"; local cmd="$2"
  if docker exec "$CONTAINER" bash -c "$cmd" >/dev/null 2>&1; then
    ok "$label"
    return 0
  else
    warn "$label — FAILED"
    return 1
  fi
}

FAILURES=0
check "installer exit code 0"          "[ $INSTALL_EXIT = 0 ]" || ((FAILURES++))
check "node installed"                 "command -v node"        || ((FAILURES++))
check "openclaw binary installed"      "command -v openclaw"    || ((FAILURES++))
check "caddy binary installed"         "command -v caddy"       || ((FAILURES++))
check "openclaw.json exists"           "test -f /home/openclaw/.openclaw/openclaw.json" || ((FAILURES++))
check "gateway listening on 18789"     "ss -tln | grep -q ':18789'"  || ((FAILURES++))
check "gateway responds on /health"    "curl -sf http://127.0.0.1:18789/health -o /dev/null" || ((FAILURES++))

echo
if [[ "$FAILURES" = 0 ]]; then
  ok "ALL CHECKS PASSED — installer is healthy on $INSTALLER_REF"
  exit 0
else
  fail "$FAILURES check(s) failed — see 'docker logs $CONTAINER' before the cleanup trap fires (or comment out trap while debugging)"
fi
