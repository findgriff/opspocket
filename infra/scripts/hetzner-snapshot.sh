#!/usr/bin/env bash
# hetzner-snapshot.sh — create a Hetzner Cloud snapshot of a server and
# prune old ones.
#
# Designed to run unattended from a systemd timer on the dev box, and also
# to be callable inline from provisioning scripts after install completes
# (so customers get a "post-install known-good" baseline).
#
# Usage:
#   hetzner-snapshot.sh                       # uses default name "opspocket-dev"
#   hetzner-snapshot.sh <server-name-or-id>
#   hetzner-snapshot.sh <name> --description "post-install t-abc123"
#   hetzner-snapshot.sh <name> --label-key snapshot_of --label-value opspocket-dev
#
# Environment:
#   HETZNER_TOKEN            Hetzner Cloud API token (read from env, else from
#                            /etc/opspocket/hetzner-token, else from
#                            ~/.opspocket/hetzner-token).
#   SNAPSHOT_RETENTION_DAYS  Delete snapshots older than N days (default: 7).
#                            Only snapshots with our own label (see below)
#                            are considered for deletion so we never touch
#                            snapshots we didn't create.
#   SNAPSHOT_LABEL_KEY       Label key used to tag + filter our snapshots
#                            (default: opspocket_snapshot).
#   SNAPSHOT_LABEL_VALUE     Label value (default: "daily").
#   SNAPSHOT_PRUNE           "1" (default) to prune old snapshots, "0" to skip.
#   SNAPSHOT_DESCRIPTION     Override the auto-generated description.
#
# Exit codes:
#   0  success (snapshot created; prune best-effort)
#   1  usage error / missing token
#   2  server not found
#   3  snapshot API call failed
#
# Hetzner API references (stable as of 2026):
#   POST /v1/servers/{id}/actions/create_image
#   GET  /v1/images?type=snapshot&label_selector=...
#   DELETE /v1/images/{id}

set -euo pipefail

API="https://api.hetzner.cloud/v1"

log()  { printf "[%s] %s\n" "$(date -u +%FT%TZ)" "$*"; }
err()  { printf "[%s] ERROR: %s\n" "$(date -u +%FT%TZ)" "$*" >&2; }
die()  { err "$*"; exit "${2:-1}"; }

# ── Load token ─────────────────────────────────────────────────────────
if [[ -z "${HETZNER_TOKEN:-}" ]]; then
  for f in /etc/opspocket/hetzner-token "${HOME:-/root}/.opspocket/hetzner-token"; do
    if [[ -r "$f" ]]; then
      HETZNER_TOKEN="$(tr -d ' \t\r\n' < "$f")"
      export HETZNER_TOKEN
      break
    fi
  done
fi
[[ -z "${HETZNER_TOKEN:-}" ]] && die "HETZNER_TOKEN not set and no token file found at /etc/opspocket/hetzner-token or ~/.opspocket/hetzner-token"

for tool in curl jq; do
  command -v "$tool" >/dev/null 2>&1 || die "missing tool: $tool"
done

# ── Args ───────────────────────────────────────────────────────────────
SERVER_ARG="${1:-opspocket-dev}"
shift || true

DESCRIPTION_OVERRIDE="${SNAPSHOT_DESCRIPTION:-}"
LABEL_KEY="${SNAPSHOT_LABEL_KEY:-opspocket_snapshot}"
LABEL_VALUE="${SNAPSHOT_LABEL_VALUE:-daily}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --description)   DESCRIPTION_OVERRIDE="$2"; shift 2 ;;
    --label-key)     LABEL_KEY="$2"; shift 2 ;;
    --label-value)   LABEL_VALUE="$2"; shift 2 ;;
    *) die "unknown arg: $1" ;;
  esac
done

RETENTION_DAYS="${SNAPSHOT_RETENTION_DAYS:-7}"
PRUNE="${SNAPSHOT_PRUNE:-1}"

api_get() {
  curl -sS --fail-with-body \
    -H "Authorization: Bearer $HETZNER_TOKEN" \
    "$API$1"
}

api_post() {
  curl -sS --fail-with-body -X POST \
    -H "Authorization: Bearer $HETZNER_TOKEN" \
    -H "Content-Type: application/json" \
    -d "$2" \
    "$API$1"
}

api_delete() {
  curl -sS --fail-with-body -X DELETE \
    -H "Authorization: Bearer $HETZNER_TOKEN" \
    "$API$1"
}

# ── Resolve server id ──────────────────────────────────────────────────
SERVER_ID=""
SERVER_NAME=""
if [[ "$SERVER_ARG" =~ ^[0-9]+$ ]]; then
  if ! RESP=$(api_get "/servers/$SERVER_ARG"); then
    die "server id $SERVER_ARG not found" 2
  fi
  SERVER_ID="$SERVER_ARG"
  SERVER_NAME=$(echo "$RESP" | jq -r '.server.name')
else
  RESP=$(api_get "/servers?name=$SERVER_ARG") || die "failed to look up server '$SERVER_ARG'" 2
  SERVER_ID=$(echo "$RESP" | jq -r '.servers[0].id // empty')
  SERVER_NAME="$SERVER_ARG"
  [[ -z "$SERVER_ID" ]] && die "server '$SERVER_ARG' not found" 2
fi
log "server: $SERVER_NAME (id $SERVER_ID)"

# ── Create snapshot ────────────────────────────────────────────────────
TIMESTAMP=$(date -u +%FT%H:%M)
DESCRIPTION="${DESCRIPTION_OVERRIDE:-$SERVER_NAME daily $TIMESTAMP}"
log "creating snapshot: \"$DESCRIPTION\""

BODY=$(jq -n \
  --arg desc "$DESCRIPTION" \
  --arg lk "$LABEL_KEY" \
  --arg lv "$LABEL_VALUE" \
  --arg server "$SERVER_NAME" \
  '{
    type: "snapshot",
    description: $desc,
    labels: {
      ($lk): $lv,
      "server_name": $server,
      "created_by": "hetzner-snapshot.sh"
    }
  }')

if ! RESP=$(api_post "/servers/$SERVER_ID/actions/create_image" "$BODY"); then
  err "snapshot API call failed:"
  echo "$RESP" >&2
  exit 3
fi

IMAGE_ID=$(echo "$RESP" | jq -r '.image.id // empty')
ACTION_ID=$(echo "$RESP" | jq -r '.action.id // empty')
if [[ -z "$IMAGE_ID" ]]; then
  err "no image id in response:"
  echo "$RESP" | jq . >&2
  exit 3
fi
log "snapshot created: image_id=$IMAGE_ID action_id=$ACTION_ID"

# ── Prune old snapshots ────────────────────────────────────────────────
if [[ "$PRUNE" != "1" ]]; then
  log "SNAPSHOT_PRUNE=0 — skipping prune"
  exit 0
fi

log "pruning snapshots older than ${RETENTION_DAYS} day(s) with label ${LABEL_KEY}=${LABEL_VALUE} and server_name=${SERVER_NAME}"

# label_selector lets Hetzner filter server-side.
SELECTOR=$(printf '%s==%s,server_name==%s' "$LABEL_KEY" "$LABEL_VALUE" "$SERVER_NAME")
ENCODED_SELECTOR=$(jq -rn --arg s "$SELECTOR" '$s|@uri')

if ! LIST=$(api_get "/images?type=snapshot&label_selector=${ENCODED_SELECTOR}&per_page=50"); then
  err "failed to list snapshots for prune — skipping"
  exit 0
fi

# Compute cutoff in epoch seconds. date formats differ between GNU and BSD;
# both understand ISO with -d on GNU. On the dev box (Ubuntu) this is GNU.
CUTOFF=$(date -u -d "${RETENTION_DAYS} days ago" +%s 2>/dev/null || \
         python3 -c "import time; print(int(time.time()-${RETENTION_DAYS}*86400))")

DELETED=0
while IFS=$'\t' read -r id created desc; do
  [[ -z "$id" ]] && continue
  # created is RFC3339 "2026-04-22T04:00:00+00:00"
  CREATED_EPOCH=$(date -u -d "$created" +%s 2>/dev/null || \
                  python3 -c "from datetime import datetime; print(int(datetime.fromisoformat('${created}').timestamp()))")
  if (( CREATED_EPOCH < CUTOFF )); then
    log "deleting old snapshot id=$id created=$created desc=\"$desc\""
    if api_delete "/images/$id" >/dev/null; then
      DELETED=$((DELETED+1))
    else
      err "failed to delete snapshot $id (continuing)"
    fi
  fi
done < <(echo "$LIST" | jq -r '.images[] | [.id, .created, .description] | @tsv')

log "prune complete: deleted ${DELETED} snapshot(s)"
log "done"
