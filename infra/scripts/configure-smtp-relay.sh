#!/usr/bin/env bash
# configure-smtp-relay.sh — wire up Postfix on the dev box with a relay provider.
#
# Usage (on dev box):
#   ./configure-smtp-relay.sh resend  RESEND_API_KEY
#   ./configure-smtp-relay.sh mailgun  'postmaster@mg.opspocket.com'  'mailgun_smtp_password'
#   ./configure-smtp-relay.sh smtp2go  'username'  'password'
#
# After that, outbound email from the dev box gets relayed (and DKIM-signed
# via our local OpenDKIM). SPF/DKIM/DMARC records for opspocket.com are
# already live so deliverability should be clean from day 1.

set -euo pipefail

PROVIDER="${1:-}"
case "$PROVIDER" in
  resend)
    RELAY="[smtp.resend.com]:587"
    USER="resend"
    PASS="${2:?need RESEND_API_KEY}"
    ;;
  mailgun)
    RELAY="[smtp.mailgun.org]:587"
    USER="${2:?need mailgun user}"
    PASS="${3:?need mailgun password}"
    ;;
  smtp2go)
    RELAY="[mail.smtp2go.com]:587"
    USER="${2:?need smtp2go user}"
    PASS="${3:?need smtp2go password}"
    ;;
  postmark)
    RELAY="[smtp.postmarkapp.com]:587"
    USER="${2:?need postmark server api token (used as both user + pass)}"
    PASS="$2"
    ;;
  *)
    echo "Usage: $0 {resend|mailgun|smtp2go|postmark} [args]" >&2
    exit 1
    ;;
esac

echo "${RELAY} ${USER}:${PASS}" > /etc/postfix/sasl/sasl_passwd
chmod 600 /etc/postfix/sasl/sasl_passwd
postmap /etc/postfix/sasl/sasl_passwd

postconf -e "relayhost = ${RELAY}"
postconf -e "defer_transports ="

systemctl reload postfix

# Test send
echo "Sending test email..."
echo "Subject: OpsPocket relay test via ${PROVIDER}

If you receive this, ${PROVIDER} relay is working." | \
  sendmail -f noreply@opspocket.com findgriff@gmail.com

echo "✓ relay configured via ${PROVIDER}. Test email queued — check mail.log in 30s."
