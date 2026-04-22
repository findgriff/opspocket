#!/usr/bin/env python3
"""Pluggable email backend for OpsPocket Cloud.

Selection order:
  1. Resend API key at /etc/opspocket/email-resend-key  (preferred)
  2. SMTP config at   /etc/opspocket/email-smtp.conf
  3. Neither → log '[email] NO BACKEND' and return False. Service does
     NOT crash; this lets us validate the rest of the flow end-to-end
     while the ops team finishes picking an email provider.

SMTP config file format (INI-ish, simple key=value):
  host=smtp.example.com
  port=587
  user=hello@opspocket.com
  pass=...
  from=OpsPocket <hello@opspocket.com>
  starttls=1

Resend key file: just the raw API key, single line.
"""

from __future__ import annotations

import base64
import json
import logging
import pathlib
import smtplib
import ssl
import urllib.request
import urllib.error
from email.message import EmailMessage
from typing import Optional

log = logging.getLogger("opspocket-email")

RESEND_KEY_FILE = pathlib.Path("/etc/opspocket/email-resend-key")
SMTP_CONF_FILE = pathlib.Path("/etc/opspocket/email-smtp.conf")
DEFAULT_FROM = "OpsPocket <hello@mail.opspocket.com>"
DEFAULT_REPLY_TO = "hello@opspocket.com"


def _read_smtp_conf() -> Optional[dict]:
    if not SMTP_CONF_FILE.exists():
        return None
    conf = {}
    for line in SMTP_CONF_FILE.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, v = line.split("=", 1)
        conf[k.strip()] = v.strip()
    return conf


def _send_resend(key: str, to: str, subject: str, text: str, html: Optional[str]) -> bool:
    body = {
        "from": DEFAULT_FROM,
        "to": [to],
        "subject": subject,
        "reply_to": DEFAULT_REPLY_TO,
        "text": text,
    }
    if html:
        body["html"] = html
    req = urllib.request.Request(
        "https://api.resend.com/emails",
        data=json.dumps(body).encode(),
        headers={
            "Authorization": f"Bearer {key}",
            "Content-Type": "application/json",
            "User-Agent": "opspocket-backend/1.0",
            "Accept": "application/json",
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=20) as r:
            log.info("[email] resend OK status=%s to=%s", r.status, to)
            return True
    except urllib.error.HTTPError as e:
        log.error("[email] resend HTTP %s: %s", e.code, e.read().decode(errors="replace"))
    except Exception as e:
        log.error("[email] resend error: %s", e)
    return False


def _send_smtp(conf: dict, to: str, subject: str, text: str, html: Optional[str]) -> bool:
    msg = EmailMessage()
    msg["Subject"] = subject
    msg["From"] = conf.get("from") or DEFAULT_FROM
    msg["To"] = to
    msg.set_content(text)
    if html:
        msg.add_alternative(html, subtype="html")
    host = conf.get("host")
    port = int(conf.get("port", "587"))
    user = conf.get("user")
    pw = conf.get("pass")
    use_starttls = conf.get("starttls", "1") in ("1", "true", "yes")
    try:
        with smtplib.SMTP(host, port, timeout=20) as s:
            s.ehlo()
            if use_starttls:
                s.starttls(context=ssl.create_default_context())
                s.ehlo()
            if user and pw:
                s.login(user, pw)
            s.send_message(msg)
        log.info("[email] smtp OK host=%s to=%s", host, to)
        return True
    except Exception as e:
        log.error("[email] smtp error: %s", e)
        return False


def send_email(*, to: str, subject: str, text: str, html: Optional[str] = None) -> bool:
    """Returns True on success, False on failure or no backend."""
    # Prefer Resend if configured.
    try:
        key = RESEND_KEY_FILE.read_text().strip() if RESEND_KEY_FILE.exists() else None
    except Exception:
        key = None
    if key:
        return _send_resend(key, to, subject, text, html)

    conf = _read_smtp_conf()
    if conf and conf.get("host"):
        return _send_smtp(conf, to, subject, text, html)

    log.warning("[email] NO BACKEND — would have sent to=%s subject=%r", to, subject)
    log.info("[email] NO BACKEND — text body preview:\n%s", text[:500])
    return False
