#!/usr/bin/env python3
"""Lifecycle automation — runs on Stripe webhook events.

Two jobs:
  1. Refresh the local Stripe cache for whatever customer the event
     mentions, so the admin + customer UIs are always fresh without
     manual sync button clicks.
  2. Fire the right transactional email based on event type:
        invoice.payment_failed        → recover-payment email
        invoice.payment_succeeded     → (optional receipt — Stripe sends
                                          its own by default; we skip)
        customer.subscription.trial_will_end → trial-ending email
        customer.subscription.updated (cancel_at set) → cancel-confirmed
        customer.subscription.deleted → subscription-ended email

Safe to run from a background thread — the webhook has already
returned 200 by the time this executes.
"""

from __future__ import annotations

import json
import logging
import pathlib
import sqlite3
import time
import urllib.error
import urllib.parse
import urllib.request
from typing import Optional

log = logging.getLogger("opspocket-lifecycle")

DB_PATH = pathlib.Path("/var/lib/opspocket/tenants.db")
STRIPE_API_KEY_FILE = pathlib.Path("/etc/opspocket/stripe-api-key")
SUPPORT_EMAIL = "hello@opspocket.com"
DOMAIN_ROOT = "opspocket.com"


def _db() -> sqlite3.Connection:
    conn = sqlite3.connect(str(DB_PATH), timeout=20)
    conn.row_factory = sqlite3.Row
    return conn


def _extract_customer_id(event: dict) -> Optional[str]:
    obj = (event.get("data") or {}).get("object") or {}
    return (
        obj.get("customer")
        or obj.get("customer_id")
        or (obj.get("customer_details") or {}).get("id")
    )


def _extract_subscription_id(event: dict) -> Optional[str]:
    obj = (event.get("data") or {}).get("object") or {}
    return obj.get("subscription") or (obj.get("id") if obj.get("object") == "subscription" else None)


# ── Targeted Stripe refresh (one customer, not full sync) ────────────

def refresh_stripe_for_customer(customer_id: str) -> dict:
    """Pull just this customer's Stripe data — customer, subs, invoices,
    charges. Fast (≈1 s for 3 API calls). Much better than full sync_all
    which iterates every object on the account."""
    if not customer_id:
        return {}
    try:
        import sync_stripe  # type: ignore
    except Exception as e:
        log.error("sync_stripe not importable: %s", e)
        return {"error": str(e)}

    key = sync_stripe._key()
    if not key:
        return {"error": "no stripe key"}

    import time as _t
    now = int(_t.time())
    counts = {"subs": 0, "invoices": 0, "charges": 0}

    conn = _db()
    try:
        # Customer itself
        try:
            c = sync_stripe._get(key, f"/customers/{customer_id}")
            sync_stripe._upsert_customer(conn, c, now)
        except Exception as e:
            log.warning("customer fetch failed: %s", e)

        # Subscriptions for this customer
        try:
            page = sync_stripe._get(
                key, "/subscriptions",
                {"customer": customer_id, "status": "all", "limit": 20},
            )
            for s in page.get("data", []):
                sync_stripe._upsert_subscription(conn, s, now)
                counts["subs"] += 1
        except Exception as e:
            log.warning("sub fetch failed: %s", e)

        # Invoices
        try:
            page = sync_stripe._get(
                key, "/invoices", {"customer": customer_id, "limit": 20},
            )
            for inv in page.get("data", []):
                sync_stripe._upsert_invoice(conn, inv, now)
                counts["invoices"] += 1
        except Exception as e:
            log.warning("invoice fetch failed: %s", e)

        # Charges
        try:
            page = sync_stripe._get(
                key, "/charges", {"customer": customer_id, "limit": 20},
            )
            for ch in page.get("data", []):
                sync_stripe._upsert_charge(conn, ch, now)
                counts["charges"] += 1
        except Exception as e:
            log.warning("charge fetch failed: %s", e)

        conn.commit()
    finally:
        conn.close()
    log.info("refresh_stripe_for_customer %s → %s", customer_id, counts)
    return counts


# ── Lifecycle email dispatcher ───────────────────────────────────────

def _send(to: str, subject: str, text: str, html: str) -> bool:
    try:
        from email_sender import send_email  # type: ignore
    except Exception as e:
        log.error("email_sender import failed: %s", e)
        return False
    return send_email(to=to, subject=subject, text=text, html=html)


def _tenant_for_customer(conn: sqlite3.Connection, customer_id: str) -> Optional[dict]:
    row = conn.execute(
        "SELECT * FROM tenants WHERE stripe_customer_id=? LIMIT 1",
        (customer_id,),
    ).fetchone()
    return dict(row) if row else None


def _email_for_customer_id(conn: sqlite3.Connection, customer_id: str) -> Optional[str]:
    t = _tenant_for_customer(conn, customer_id)
    if t:
        return t.get("customer_email")
    # Fall back to the cached Stripe customer row
    row = conn.execute(
        "SELECT email FROM stripe_customers WHERE id=?",
        (customer_id,),
    ).fetchone()
    return row["email"] if row else None


# ─── Templates ─────────────────────────────────────────────────

def _payment_failed_email(email: str, tenant: Optional[dict],
                           invoice: dict) -> bool:
    amount = (invoice.get("amount_due") or 0) / 100
    currency = (invoice.get("currency") or "gbp").upper()
    hosted = invoice.get("hosted_invoice_url") or f"https://{DOMAIN_ROOT}/account"
    tier = (tenant or {}).get("tier", "").capitalize() or "OpsPocket"
    subject = f"Action needed — payment failed for your {tier} subscription"
    text = (
        f"Hi,\n\n"
        f"We weren't able to charge your card for {currency} {amount:.2f} on "
        f"your {tier} OpsPocket subscription.\n\n"
        f"Stripe retries automatically over the next 7 days. If the retry "
        f"still fails, your service will be paused.\n\n"
        f"Fix it in under a minute:\n"
        f"  {hosted}\n\n"
        f"Or manage your card at {_portal_link(tenant)}\n\n"
        f"Questions? Reply to this email.\n\n— OpsPocket"
    )
    html = (
        f"<div style=\"font-family:-apple-system,sans-serif;max-width:520px;"
        f"margin:0 auto;padding:32px;background:#0b0b0d;color:#eee;"
        f"border-radius:12px\">"
        f"<div style=\"background:rgba(255,59,31,0.12);border:1px solid rgba(255,59,31,0.3);"
        f"border-radius:8px;padding:16px;margin-bottom:24px\">"
        f"<strong style=\"color:#ff6a4d\">⚠ Payment failed</strong><br>"
        f"<span style=\"font-size:14px;color:#aaa\">{currency} {amount:.2f} on your {tier} subscription</span>"
        f"</div>"
        f"<p>Stripe retries automatically over the next 7 days. If the "
        f"retry still fails, your service will be paused.</p>"
        f"<p style=\"margin:24px 0\"><a href=\"{hosted}\" style=\"display:inline-block;"
        f"background:#e24a3b;color:#fff;padding:12px 22px;border-radius:8px;"
        f"text-decoration:none;font-weight:600\">Fix payment →</a></p>"
        f"<p style=\"color:#999;font-size:13px\">Questions? Reply to this email.</p>"
        f"</div>"
    )
    return _send(email, subject, text, html)


def _trial_ending_email(email: str, tenant: Optional[dict],
                        sub: dict) -> bool:
    import time as _t
    days_left = 0
    trial_end = sub.get("trial_end")
    if trial_end:
        days_left = max(0, (trial_end - int(_t.time())) // 86400)
    tier = (tenant or {}).get("tier", "").capitalize() or "OpsPocket"
    subject = f"Your {tier} trial ends in {days_left} day{'s' if days_left != 1 else ''}"
    portal = _portal_link(tenant)
    text = (
        f"Hi,\n\n"
        f"Your OpsPocket {tier} free trial ends in {days_left} day"
        f"{'s' if days_left != 1 else ''}.\n\n"
        f"Nothing to do — billing starts automatically on the trial's "
        f"end date. If you want to change plan or cancel, here's your "
        f"account:\n\n  {portal}\n\n"
        f"Still exploring? Our docs: https://{DOMAIN_ROOT}/blog\n"
        f"Questions? Reply to this email.\n\n— OpsPocket"
    )
    html = (
        f"<div style=\"font-family:-apple-system,sans-serif;max-width:520px;"
        f"margin:0 auto;padding:32px;background:#0b0b0d;color:#eee;"
        f"border-radius:12px\">"
        f"<h1 style=\"font-size:22px;margin:0 0 10px\">Trial ending in {days_left} day"
        f"{'s' if days_left != 1 else ''}</h1>"
        f"<p style=\"color:#aaa\">Nothing to do — billing starts automatically. "
        f"Change plan or cancel anytime:</p>"
        f"<p style=\"margin:24px 0\"><a href=\"{portal}\" style=\"display:inline-block;"
        f"background:transparent;color:#57e3ff;border:1px solid #333;padding:12px 22px;"
        f"border-radius:8px;text-decoration:none;font-weight:600\">Manage account →</a></p>"
        f"</div>"
    )
    return _send(email, subject, text, html)


def _subscription_ended_email(email: str, tenant: Optional[dict]) -> bool:
    tier = (tenant or {}).get("tier", "").capitalize() or "OpsPocket"
    subject = f"Your {tier} subscription has ended"
    text = (
        f"Hi,\n\n"
        f"Your OpsPocket {tier} subscription has ended. Your server will be "
        f"paused shortly. Data is preserved for 7 days in case you change "
        f"your mind.\n\n"
        f"Come back anytime: https://{DOMAIN_ROOT}/cloud\n\n"
        f"If you cancelled by mistake or have feedback, reply to this "
        f"email — we read every message.\n\n— OpsPocket"
    )
    html = (
        f"<div style=\"font-family:-apple-system,sans-serif;max-width:520px;"
        f"margin:0 auto;padding:32px;background:#0b0b0d;color:#eee;"
        f"border-radius:12px\">"
        f"<h1 style=\"font-size:20px;margin:0 0 10px\">Subscription ended</h1>"
        f"<p style=\"color:#aaa\">Your {tier} server will be paused. Data "
        f"preserved for 7 days.</p>"
        f"<p style=\"margin:24px 0\"><a href=\"https://{DOMAIN_ROOT}/cloud\" "
        f"style=\"color:#57e3ff\">Back to OpsPocket →</a></p>"
        f"<p style=\"color:#999;font-size:13px\">Reply to this email with "
        f"feedback — it goes straight to the founder.</p>"
        f"</div>"
    )
    return _send(email, subject, text, html)


def _portal_link(tenant: Optional[dict]) -> str:
    # We could issue a Stripe billing portal session here, but that
    # requires the customer to be signed-in already. Send them to
    # /account — they'll magic-link in and find the portal button.
    return f"https://{DOMAIN_ROOT}/account"


# ── Event dispatch ───────────────────────────────────────────────

def dispatch(event: dict) -> None:
    etype = event.get("type", "")
    obj = (event.get("data") or {}).get("object") or {}
    conn = _db()
    try:
        customer_id = _extract_customer_id(event)
        email = _email_for_customer_id(conn, customer_id) if customer_id else None

        if etype == "invoice.payment_failed" and email:
            tenant = _tenant_for_customer(conn, customer_id)
            sent = _payment_failed_email(email, tenant, obj)
            log.info("lifecycle: payment_failed → %s (sent=%s)", email, sent)
        elif etype == "customer.subscription.trial_will_end" and email:
            tenant = _tenant_for_customer(conn, customer_id)
            sent = _trial_ending_email(email, tenant, obj)
            log.info("lifecycle: trial_will_end → %s (sent=%s)", email, sent)
        elif etype == "customer.subscription.deleted" and email:
            tenant = _tenant_for_customer(conn, customer_id)
            sent = _subscription_ended_email(email, tenant)
            log.info("lifecycle: subscription.deleted → %s (sent=%s)", email, sent)
        # Other types: just sync, no email.
    finally:
        conn.close()


def run(event: dict) -> None:
    """Background entrypoint — called from app.py's webhook handler."""
    try:
        cid = _extract_customer_id(event)
        if cid:
            refresh_stripe_for_customer(cid)
        dispatch(event)
    except Exception as e:
        log.exception("lifecycle.run failed: %s", e)
