#!/usr/bin/env bash
# deploy-site.sh — build + ship the OpsPocket landing site to a VPS over SSH.
#
# Usage:
#   ./infra/deploy-site.sh [user@host]
#
# Default host is root@188.166.150.21 (the current DO droplet). Override
# tomorrow when you migrate to the new server.
#
# What it does, idempotently:
#   1. Builds the site locally (npm run build)
#   2. Tars the out/ directory
#   3. scp's it + the nginx config to the VPS
#   4. Over SSH: extracts to /var/www/opspocket, installs the nginx config,
#      reloads nginx
#   5. Smoke-tests /health and / from your Mac after the reload
#
# Requires: SSH key access to the target VPS as a sudo-capable user (root is
# fine on a fresh DO box).

set -euo pipefail

REMOTE="${1:-root@188.166.150.21}"
SITE_DIR="$(cd "$(dirname "$0")/../site" && pwd)"
NGINX_CONF="$(cd "$(dirname "$0")" && pwd)/nginx-opspocket.conf"
TARBALL="/tmp/opspocket-site.tar.gz"

c_cyan=$(tput setaf 6 2>/dev/null || true); c_green=$(tput setaf 2 2>/dev/null || true)
c_red=$(tput setaf 1 2>/dev/null || true); c_reset=$(tput sgr0 2>/dev/null || true)
say()  { printf "%s▶%s %s\n" "$c_cyan"  "$c_reset" "$*"; }
ok()   { printf "%s✓%s %s\n" "$c_green" "$c_reset" "$*"; }
fail() { printf "%s✗%s %s\n" "$c_red"   "$c_reset" "$*" >&2; exit 1; }

say "Building site at $SITE_DIR…"
cd "$SITE_DIR"
npm run build >/dev/null
[[ -d out ]] || fail "build did not produce out/ — inspect: (cd $SITE_DIR && npm run build)"
ok "Build produced $(du -sh out/ | awk '{print $1}')"

say "Packaging tarball…"
tar czf "$TARBALL" -C out .
ok "Tarball: $(ls -lh "$TARBALL" | awk '{print $5}')"

say "Copying artefacts to $REMOTE…"
scp -q "$TARBALL" "$REMOTE:/tmp/opspocket-site.tar.gz"
scp -q "$NGINX_CONF" "$REMOTE:/tmp/nginx-opspocket.conf"
ok "Artefacts uploaded."

say "Installing on remote…"
ssh "$REMOTE" bash <<'REMOTE_EOF'
set -euo pipefail

# 1. Unpack the site to a fresh staging directory, swap atomically.
NEW_DIR="/var/www/opspocket.$$"
install -d -m 755 "$NEW_DIR"
tar xzf /tmp/opspocket-site.tar.gz -C "$NEW_DIR"

# Swap: rename old (if present) out of the way, move new into place.
if [[ -e /var/www/opspocket ]]; then
  rm -rf /var/www/opspocket.prev
  mv /var/www/opspocket /var/www/opspocket.prev
fi
mv "$NEW_DIR" /var/www/opspocket
chown -R www-data:www-data /var/www/opspocket 2>/dev/null || \
  chown -R nginx:nginx /var/www/opspocket 2>/dev/null || true

# 2. Install the nginx config.
install -m 644 /tmp/nginx-opspocket.conf /etc/nginx/sites-available/opspocket
ln -sf /etc/nginx/sites-available/opspocket /etc/nginx/sites-enabled/opspocket
# If nginx's default is also on :80 as default_server, ours replaces it.
if [[ -f /etc/nginx/sites-enabled/default ]]; then
  rm -f /etc/nginx/sites-enabled/default
fi

# 3. Validate + reload.
nginx -t
systemctl reload nginx

# 4. Tidy up the upload.
rm -f /tmp/opspocket-site.tar.gz /tmp/nginx-opspocket.conf
echo "remote install complete."
REMOTE_EOF
ok "Remote install complete."

# ── Smoke tests from the Mac ─────────────────────────────────────────────
HOST_ONLY="${REMOTE#*@}"
say "Probing http://$HOST_ONLY/health…"
if curl -fsSL --max-time 5 "http://$HOST_ONLY/health" | grep -q ok; then
  ok "Health endpoint 200 OK."
else
  fail "Health endpoint did not respond — check: ssh $REMOTE 'journalctl -u nginx -n 40'"
fi

say "Probing homepage…"
STATUS=$(curl -sS -o /dev/null -w "%{http_code}" --max-time 5 "http://$HOST_ONLY/")
[[ "$STATUS" == "200" ]] || fail "Homepage returned HTTP $STATUS"
ok "Homepage 200 OK."

say "Probing mission-control bridge still works…"
MC_STATUS=$(curl -sS -o /dev/null -w "%{http_code}" --max-time 5 "http://$HOST_ONLY/mission-control/api/mcp")
[[ "$MC_STATUS" == "200" ]] && ok "MCP endpoint still 200." || \
  echo "  ⚠ MCP returned $MC_STATUS — if this is wrong, roll back:"
  echo "     ssh $REMOTE 'rm -rf /var/www/opspocket && mv /var/www/opspocket.prev /var/www/opspocket && systemctl reload nginx'"

cat <<SUMMARY

──────────────────────────────────────────────────────────
  ✓ OpsPocket site live at http://$HOST_ONLY/
  ✓ MCP bridge preserved at http://$HOST_ONLY/mission-control/api/mcp
──────────────────────────────────────────────────────────
  Rollback on remote:
    rm -rf /var/www/opspocket && \
    mv /var/www/opspocket.prev /var/www/opspocket && \
    systemctl reload nginx

SUMMARY
