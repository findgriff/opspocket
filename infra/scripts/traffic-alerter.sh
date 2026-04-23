#!/usr/bin/env bash
# traffic-alerter.sh — nightly cron. Alerts ops when any tenant VPS
# has used >=80% of its included monthly traffic (Hetzner includes 20 TB
# on CPX22/32/42).
#
# Runs after sync_hetzner has refreshed the hetzner_traffic table.

set -euo pipefail

DB=/var/lib/opspocket/tenants.db
OPS_EMAIL="${OPS_EMAIL:-hello@opspocket.com}"

mapfile -t alerts < <(sqlite3 -separator '|' "$DB" "
  SELECT
    t.id, t.customer_email, t.domain, t.tier,
    tr.outgoing_bytes, tr.ingoing_bytes, tr.included_bytes,
    ROUND(100.0 * tr.outgoing_bytes / NULLIF(tr.included_bytes,0), 1) AS pct
  FROM hetzner_traffic tr
  JOIN tenants t ON t.hetzner_server_id = tr.server_id
  WHERE tr.included_bytes IS NOT NULL
    AND tr.included_bytes > 0
    AND (1.0 * tr.outgoing_bytes / tr.included_bytes) >= 0.8
")

if [[ ${#alerts[@]} -eq 0 ]]; then
  echo "traffic-alerter: no tenants over 80% — nothing to do"
  exit 0
fi

SUBJECT="[opspocket] Traffic usage alert — ${#alerts[@]} tenants near quota"
BODY="Tenants at or over 80% of their included Hetzner traffic this month:"$'\n\n'

for row in "${alerts[@]}"; do
  IFS='|' read -r id email domain tier out_b in_b inc_b pct <<<"$row"
  out_gb=$(awk -v b="$out_b" 'BEGIN{printf "%.1f", b/1073741824}')
  inc_gb=$(awk -v b="$inc_b" 'BEGIN{printf "%.0f", b/1073741824}')
  BODY+="  · ${id}  ${email}  (${tier})  ${out_gb} GB / ${inc_gb} GB  (${pct}%)"$'\n'
  BODY+="    domain: ${domain}"$'\n\n'
done

BODY+=$'\n'"Contact customer, suggest upgrade to next tier, or reach out to Hetzner for overage guidance."

# Send via the backend's send_email helper
python3 - <<PY
import sys
sys.path.insert(0, '/opt/opspocket/backend')
from email_sender import send_email
ok = send_email(
    to="${OPS_EMAIL}",
    subject="${SUBJECT}",
    text="""${BODY}""",
    html=None,
)
print("alert email sent:", ok)
PY
