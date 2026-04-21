#!/usr/bin/env bash
# vps-build-site.sh — run ON the VPS to pull the latest landing site source
# from GitHub, build it, and point nginx at the output.
#
# Usage (on the VPS, as root or sudo):
#
#   # First time:
#   curl -fsSL https://raw.githubusercontent.com/findgriff/opspocket/landing-site/infra/vps-build-site.sh \
#     | bash
#
#   # Subsequent updates (every time code on landing-site changes):
#   /opt/opspocket/infra/vps-build-site.sh
#
# It's idempotent — safe to run repeatedly. Each run:
#   1. Clones the repo to /opt/opspocket if missing, or `git pull`s if present
#   2. Checks out the landing-site branch
#   3. Installs npm deps + runs `next build` with static export
#   4. Swaps the build output into /var/www/opspocket (atomic — old parked as .prev)
#   5. Installs/updates the nginx vhost so / serves the static site
#      (preserves /mission-control/* proxy untouched)
#   6. Reloads nginx + prints a summary
#
# What you need on the VPS beforehand:
#   * Node.js 18+ (we use 20) — already present because mission-control needs it
#   * git, nginx, curl — standard on a DO / Vultr Ubuntu box
#   * An SSH deploy key for the repo, OR the repo is public

set -euo pipefail

REPO_URL="${REPO_URL:-https://github.com/findgriff/opspocket.git}"
BRANCH="${BRANCH:-landing-site}"
CHECKOUT_DIR="${CHECKOUT_DIR:-/opt/opspocket}"
WEB_DIR="${WEB_DIR:-/var/www/opspocket}"
NGINX_SITES="/etc/nginx/sites-available"
NGINX_ENABLED="/etc/nginx/sites-enabled"

c_cyan=$(tput setaf 6 2>/dev/null || true); c_green=$(tput setaf 2 2>/dev/null || true)
c_red=$(tput setaf 1 2>/dev/null || true); c_reset=$(tput sgr0 2>/dev/null || true)
say()  { printf "%s▶%s %s\n" "$c_cyan"  "$c_reset" "$*"; }
ok()   { printf "%s✓%s %s\n" "$c_green" "$c_reset" "$*"; }
fail() { printf "%s✗%s %s\n" "$c_red"   "$c_reset" "$*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || fail "run as root (or with sudo)"

# ── 1. Clone or pull ────────────────────────────────────────────────────────
if [[ -d $CHECKOUT_DIR/.git ]]; then
  say "Updating existing checkout at $CHECKOUT_DIR…"
  git -C "$CHECKOUT_DIR" fetch --depth=1 origin "$BRANCH"
  git -C "$CHECKOUT_DIR" checkout "$BRANCH"
  git -C "$CHECKOUT_DIR" reset --hard "origin/$BRANCH"
else
  say "Cloning $REPO_URL ($BRANCH) to $CHECKOUT_DIR…"
  git clone --depth=1 --branch "$BRANCH" "$REPO_URL" "$CHECKOUT_DIR"
fi
ok "Repo at $(git -C "$CHECKOUT_DIR" rev-parse --short HEAD)."

# ── 2. npm install + build ──────────────────────────────────────────────────
command -v node >/dev/null || fail "node not installed — 'apt install -y nodejs npm'"
say "Installing npm deps…"
cd "$CHECKOUT_DIR/site"
npm ci --no-audit --no-fund --silent >/dev/null 2>&1 || npm install --no-audit --no-fund --silent
ok "Deps resolved."

say "Building static export…"
npm run build >/tmp/opspocket-build.log 2>&1 || {
  tail -40 /tmp/opspocket-build.log >&2
  fail "build failed — see /tmp/opspocket-build.log for the full trace"
}
[[ -d "$CHECKOUT_DIR/site/out" ]] || fail "build succeeded but out/ is missing"
ok "Build output: $(du -sh "$CHECKOUT_DIR/site/out" | awk '{print $1}')"

# ── 3. Atomic swap into /var/www/opspocket ──────────────────────────────────
say "Installing to $WEB_DIR…"
NEW_DIR="${WEB_DIR}.new.$$"
rm -rf "$NEW_DIR"
cp -a "$CHECKOUT_DIR/site/out" "$NEW_DIR"
chown -R www-data:www-data "$NEW_DIR" 2>/dev/null || \
  chown -R nginx:nginx "$NEW_DIR" 2>/dev/null || true

if [[ -e $WEB_DIR ]]; then
  rm -rf "${WEB_DIR}.prev"
  mv "$WEB_DIR" "${WEB_DIR}.prev"
fi
mv "$NEW_DIR" "$WEB_DIR"
ok "Site live at $WEB_DIR (previous parked at ${WEB_DIR}.prev)."

# ── 4. Install nginx vhost (idempotent) ─────────────────────────────────────
say "Installing nginx vhost…"
install -m 644 "$CHECKOUT_DIR/infra/nginx-opspocket.conf" \
  "$NGINX_SITES/opspocket"
ln -sf "$NGINX_SITES/opspocket" "$NGINX_ENABLED/opspocket"

# If the default vhost is still active on :80, retire it so ours takes over.
[[ -L $NGINX_ENABLED/default ]] && rm -f "$NGINX_ENABLED/default"

nginx -t >/dev/null
systemctl reload nginx
ok "nginx reloaded."

# ── 5. Smoke tests from the VPS itself ──────────────────────────────────────
say "Smoke tests…"
for probe in /health / /mission-control/api/mcp; do
  STATUS=$(curl -sS -o /dev/null -w "%{http_code}" --max-time 5 "http://127.0.0.1${probe}" || echo 000)
  if [[ "$STATUS" == "200" ]]; then
    printf "    %s✓%s %s → 200\n" "$c_green" "$c_reset" "$probe"
  else
    printf "    %s⚠%s %s → %s\n" "$c_red" "$c_reset" "$probe" "$STATUS"
  fi
done

PUBLIC_IP=$(curl -fsSL --max-time 5 ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')
cat <<SUMMARY

──────────────────────────────────────────────────────────
  ✓ OpsPocket site deployed from $BRANCH@$(git -C "$CHECKOUT_DIR" rev-parse --short HEAD)
──────────────────────────────────────────────────────────
  Live at:   http://$PUBLIC_IP/
  MCP:       http://$PUBLIC_IP/mission-control/api/mcp   (unchanged)
  Source:    $CHECKOUT_DIR
  Served:    $WEB_DIR

  Re-run this script to deploy any update:
    $CHECKOUT_DIR/infra/vps-build-site.sh

  Rollback:
    rm -rf $WEB_DIR && mv ${WEB_DIR}.prev $WEB_DIR && systemctl reload nginx

SUMMARY
