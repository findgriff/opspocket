#!/bin/bash
# opspocket-heartbeat.sh — pushes tenant telemetry to the OpsPocket
# backend every 60s (driven by opspocket-heartbeat.timer).
#
# Installed by install-openclaw.sh at /usr/local/bin/opspocket-heartbeat.sh
# Config file at /etc/opspocket/heartbeat.conf (mode 0600) with:
#     TENANT_ID=<short hex>
#     HEARTBEAT_SECRET=<url-safe token>
#     HEARTBEAT_URL=https://opspocket.com/api/tenants/<TENANT_ID>/heartbeat
#
# Dependencies: bash, coreutils, curl, jq (optional — we skip jq and
# build the JSON by hand for portability).

set -euo pipefail

CONF=/etc/opspocket/heartbeat.conf
if [[ ! -r "$CONF" ]]; then
  echo "heartbeat: config not readable at $CONF" >&2
  exit 1
fi
# shellcheck disable=SC1090
source "$CONF"
: "${TENANT_ID:?TENANT_ID unset}"
: "${HEARTBEAT_SECRET:?HEARTBEAT_SECRET unset}"
: "${HEARTBEAT_URL:?HEARTBEAT_URL unset}"

# ── Gather metrics ────────────────────────────────────────────────────

# CPU %: average busy across all CPUs over the last 1-second delta.
# Read /proc/stat twice, 1 s apart.
cpu_pct() {
  read -r _ a b c idle1 rest1 < /proc/stat
  sleep 1
  read -r _ a2 b2 c2 idle2 rest2 < /proc/stat
  local total1=$((a + b + c + idle1))
  local total2=$((a2 + b2 + c2 + idle2))
  local d_idle=$((idle2 - idle1))
  local d_total=$((total2 - total1))
  if (( d_total <= 0 )); then echo 0; return; fi
  awk -v idle="$d_idle" -v total="$d_total" 'BEGIN{printf "%.1f", (1 - idle/total) * 100}'
}

ram_pct() {
  local total avail
  total=$(awk '/^MemTotal:/ {print $2}' /proc/meminfo)
  avail=$(awk '/^MemAvailable:/ {print $2}' /proc/meminfo)
  if [[ -z "$total" || -z "$avail" ]]; then echo 0; return; fi
  awk -v t="$total" -v a="$avail" 'BEGIN{printf "%.1f", (1 - a/t) * 100}'
}

disk_pct() {
  df -P / | awk 'NR==2 {gsub("%",""); print $5}'
}

uptime_s() {
  awk '{printf "%d", $1}' /proc/uptime
}

load_avg() {
  # returns "[0.12,0.34,0.56]"
  read -r l1 l5 l15 _ _ < /proc/loadavg
  echo "[${l1},${l5},${l15}]"
}

openclaw_ver() {
  if command -v openclaw >/dev/null 2>&1; then
    openclaw --version 2>/dev/null | head -1 | awk '{print $NF}' || echo "unknown"
  else
    echo "unknown"
  fi
}

docker_counts() {
  # echoes "total running" — "0 0" if docker isn't installed
  if ! command -v docker >/dev/null 2>&1; then
    echo "0 0"; return
  fi
  local total running
  total=$(docker ps -a -q 2>/dev/null | wc -l | tr -d ' ')
  running=$(docker ps -q 2>/dev/null | wc -l | tr -d ' ')
  echo "${total:-0} ${running:-0}"
}

failed_services() {
  # returns "N svc1,svc2"
  local list count
  list=$(systemctl --failed --no-legend --plain 2>/dev/null | awk '{print $1}' | head -10 | paste -sd',' -)
  count=$(echo -n "$list" | tr ',' '\n' | grep -c . || true)
  echo "${count:-0}|${list:-}"
}

tls_days_left() {
  # Checks the first cert in Caddy's data dir (typical: acme-v02 /
  # letsencrypt dir under /var/lib/caddy/). Returns integer days or
  # -1 if no cert found.
  local cert
  cert=$(find /var/lib/caddy -name 'cert*.pem' -type f 2>/dev/null | head -1)
  if [[ -z "$cert" ]]; then echo -1; return; fi
  local end_ts now_ts
  end_ts=$(openssl x509 -in "$cert" -noout -enddate 2>/dev/null | cut -d= -f2)
  if [[ -z "$end_ts" ]]; then echo -1; return; fi
  end_ts=$(date -d "$end_ts" +%s 2>/dev/null || echo 0)
  now_ts=$(date +%s)
  if (( end_ts <= 0 )); then echo -1; return; fi
  echo $(( (end_ts - now_ts) / 86400 ))
}

restart_loops() {
  # containers that restarted >2x in last 10 min — naive heuristic:
  # check docker inspect RestartCount and filter by recency.
  if ! command -v docker >/dev/null 2>&1; then echo 0; return; fi
  local ten_min_ago count=0
  ten_min_ago=$(date -u -d '10 minutes ago' +%s 2>/dev/null || echo 0)
  for id in $(docker ps -q 2>/dev/null); do
    local rc start
    rc=$(docker inspect --format '{{.RestartCount}}' "$id" 2>/dev/null || echo 0)
    start=$(docker inspect --format '{{.State.StartedAt}}' "$id" 2>/dev/null)
    start=$(date -u -d "$start" +%s 2>/dev/null || echo 0)
    if (( rc > 2 )) && (( start > ten_min_ago )); then
      count=$((count + 1))
    fi
  done
  echo "$count"
}

# ── Build JSON payload ────────────────────────────────────────────────

CPU=$(cpu_pct)
RAM=$(ram_pct)
DISK=$(disk_pct)
UPT=$(uptime_s)
LOAD=$(load_avg)
OC_VER=$(openclaw_ver)
read -r DKR_TOTAL DKR_RUNNING <<<"$(docker_counts)"
FS_RESULT=$(failed_services)
FS_COUNT="${FS_RESULT%%|*}"
FS_LIST="${FS_RESULT#*|}"
TLS_DAYS=$(tls_days_left)
RESTARTS=$(restart_loops)

# Build failed_service_names JSON array
if [[ -z "$FS_LIST" ]]; then
  FS_JSON='[]'
else
  FS_JSON=$(printf '%s' "$FS_LIST" | awk -F',' '{
    printf "["
    for (i=1; i<=NF; i++) {
      if (i>1) printf ","
      printf "\"%s\"", $i
    }
    printf "]"
  }')
fi

PAYLOAD=$(cat <<EOF
{"cpu":${CPU:-0},"ram":${RAM:-0},"disk":${DISK:-0},"uptime":${UPT:-0},"load":${LOAD},"openclaw_version":"${OC_VER}","docker_total":${DKR_TOTAL:-0},"docker_running":${DKR_RUNNING:-0},"failed_services":${FS_COUNT:-0},"failed_service_names":${FS_JSON},"tls_days_left":${TLS_DAYS:--1},"restart_loops":${RESTARTS:-0}}
EOF
)

# ── Sign + POST ───────────────────────────────────────────────────────

SIG=$(printf '%s' "$PAYLOAD" | openssl dgst -sha256 -hmac "$HEARTBEAT_SECRET" -binary | xxd -p -c 256 | tr -d '\n')

curl -fsS -o /dev/null \
  --max-time 10 \
  -H "Content-Type: application/json" \
  -H "X-OpsPocket-Signature: sha256=${SIG}" \
  -d "$PAYLOAD" \
  "$HEARTBEAT_URL" \
  || { echo "heartbeat: POST failed" >&2; exit 2; }
