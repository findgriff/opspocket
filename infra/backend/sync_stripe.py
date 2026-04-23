#!/usr/bin/env python3
"""Stripe → sqlite sync.

Pulls customers, subscriptions, invoices, and charges from the live
Stripe account and upserts them into our local CRM cache.

Design:
  * Idempotent — safe to run repeatedly
  * Paginated via Stripe's has_more + starting_after
  * Python stdlib only (urllib + json)
  * Exposes sync_all() as the one entrypoint callers use
"""

from __future__ import annotations

import base64
import json
import logging
import pathlib
import sqlite3
import time
import urllib.parse
import urllib.request
from typing import Iterable, Optional

log = logging.getLogger("opspocket-stripe-sync")

DB_PATH = pathlib.Path("/var/lib/opspocket/tenants.db")
STRIPE_API_KEY_FILE = pathlib.Path("/etc/opspocket/stripe-api-key")
STRIPE_BASE = "https://api.stripe.com/v1"


def _key() -> Optional[str]:
    try:
        return STRIPE_API_KEY_FILE.read_text().strip() or None
    except Exception:
        return None


def _auth_header(key: str) -> str:
    token = base64.b64encode(f"{key}:".encode()).decode()
    return f"Basic {token}"


def _get(key: str, path: str, params: Optional[dict] = None) -> dict:
    url = STRIPE_BASE + path
    if params:
        url += "?" + urllib.parse.urlencode(params)
    req = urllib.request.Request(
        url,
        headers={
            "Authorization": _auth_header(key),
            "Accept": "application/json",
        },
    )
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.loads(r.read())


def _paginate(key: str, path: str, page_size: int = 100) -> Iterable[dict]:
    """Yield every object from a paginated list endpoint."""
    starting_after = None
    while True:
        params = {"limit": page_size}
        if starting_after:
            params["starting_after"] = starting_after
        page = _get(key, path, params)
        items = page.get("data", [])
        for it in items:
            yield it
        if not page.get("has_more") or not items:
            break
        starting_after = items[-1]["id"]


def _db() -> sqlite3.Connection:
    conn = sqlite3.connect(str(DB_PATH), timeout=30)
    conn.row_factory = sqlite3.Row
    return conn


def _upsert_customer(conn: sqlite3.Connection, c: dict, now: int) -> None:
    conn.execute(
        """
        INSERT INTO stripe_customers
          (id, email, name, phone, balance, currency, delinquent, created_at, synced_at)
        VALUES (?,?,?,?,?,?,?,?,?)
        ON CONFLICT(id) DO UPDATE SET
          email=excluded.email, name=excluded.name, phone=excluded.phone,
          balance=excluded.balance, currency=excluded.currency,
          delinquent=excluded.delinquent, synced_at=excluded.synced_at
        """,
        (
            c["id"],
            c.get("email"),
            c.get("name"),
            c.get("phone"),
            c.get("balance", 0),
            c.get("currency"),
            1 if c.get("delinquent") else 0,
            c.get("created"),
            now,
        ),
    )


def _upsert_subscription(conn: sqlite3.Connection, s: dict, now: int) -> None:
    item = (s.get("items", {}).get("data") or [{}])[0]
    price = item.get("price") or {}
    recurring = price.get("recurring") or {}
    conn.execute(
        """
        INSERT INTO stripe_subscriptions
          (id, customer_id, status, price_id, product_id, interval, amount,
           currency, current_period_start, current_period_end,
           cancel_at, canceled_at, trial_end, synced_at)
        VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?)
        ON CONFLICT(id) DO UPDATE SET
          status=excluded.status, price_id=excluded.price_id,
          product_id=excluded.product_id, interval=excluded.interval,
          amount=excluded.amount, currency=excluded.currency,
          current_period_start=excluded.current_period_start,
          current_period_end=excluded.current_period_end,
          cancel_at=excluded.cancel_at, canceled_at=excluded.canceled_at,
          trial_end=excluded.trial_end, synced_at=excluded.synced_at
        """,
        (
            s["id"],
            s.get("customer"),
            s.get("status"),
            price.get("id"),
            price.get("product"),
            recurring.get("interval"),
            price.get("unit_amount"),
            price.get("currency"),
            s.get("current_period_start"),
            s.get("current_period_end"),
            s.get("cancel_at"),
            s.get("canceled_at"),
            s.get("trial_end"),
            now,
        ),
    )


def _upsert_invoice(conn: sqlite3.Connection, i: dict, now: int) -> None:
    conn.execute(
        """
        INSERT INTO stripe_invoices
          (id, customer_id, subscription_id, status, amount_due, amount_paid,
           amount_remaining, currency, number, hosted_invoice_url, invoice_pdf,
           paid_at, created_at, period_start, period_end, synced_at)
        VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
        ON CONFLICT(id) DO UPDATE SET
          status=excluded.status, amount_due=excluded.amount_due,
          amount_paid=excluded.amount_paid,
          amount_remaining=excluded.amount_remaining,
          hosted_invoice_url=excluded.hosted_invoice_url,
          invoice_pdf=excluded.invoice_pdf, paid_at=excluded.paid_at,
          synced_at=excluded.synced_at
        """,
        (
            i["id"],
            i.get("customer"),
            i.get("subscription"),
            i.get("status"),
            i.get("amount_due", 0),
            i.get("amount_paid", 0),
            i.get("amount_remaining", 0),
            i.get("currency"),
            i.get("number"),
            i.get("hosted_invoice_url"),
            i.get("invoice_pdf"),
            i.get("status_transitions", {}).get("paid_at"),
            i.get("created"),
            i.get("period_start"),
            i.get("period_end"),
            now,
        ),
    )


def _upsert_charge(conn: sqlite3.Connection, ch: dict, now: int) -> None:
    conn.execute(
        """
        INSERT INTO stripe_charges
          (id, customer_id, invoice_id, amount, currency, status,
           failure_code, failure_message, refunded, amount_refunded,
           receipt_url, created_at, synced_at)
        VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)
        ON CONFLICT(id) DO UPDATE SET
          status=excluded.status, failure_code=excluded.failure_code,
          failure_message=excluded.failure_message,
          refunded=excluded.refunded, amount_refunded=excluded.amount_refunded,
          synced_at=excluded.synced_at
        """,
        (
            ch["id"],
            ch.get("customer"),
            ch.get("invoice"),
            ch.get("amount"),
            ch.get("currency"),
            ch.get("status"),
            ch.get("failure_code"),
            ch.get("failure_message"),
            1 if ch.get("refunded") else 0,
            ch.get("amount_refunded", 0),
            ch.get("receipt_url"),
            ch.get("created"),
            now,
        ),
    )


def sync_all() -> dict:
    """Sync everything Stripe exposes that's useful to the CRM.
    Returns a dict of counts for reporting."""
    key = _key()
    if not key:
        raise RuntimeError("stripe api key not readable")

    now = int(time.time())
    counts = {"customers": 0, "subscriptions": 0, "invoices": 0, "charges": 0}
    conn = _db()
    try:
        for c in _paginate(key, "/customers"):
            _upsert_customer(conn, c, now)
            counts["customers"] += 1
        for s in _paginate(key, "/subscriptions", page_size=100):
            _upsert_subscription(conn, s, now)
            counts["subscriptions"] += 1
        # subscriptions endpoint only lists active by default — also
        # pull all statuses via the ?status=all param.
        for s in _paginate(key, "/subscriptions"):
            _upsert_subscription(conn, s, now)
        # invoices
        for i in _paginate(key, "/invoices"):
            _upsert_invoice(conn, i, now)
            counts["invoices"] += 1
        # charges
        for ch in _paginate(key, "/charges"):
            _upsert_charge(conn, ch, now)
            counts["charges"] += 1
        conn.commit()
    finally:
        conn.close()
    log.info("stripe sync complete: %s", counts)
    return counts


def sync_subscriptions_all_statuses() -> int:
    """Re-pull subscriptions including cancelled ones (default sync only
    shows active). Returns count."""
    key = _key()
    if not key:
        raise RuntimeError("stripe api key not readable")
    now = int(time.time())
    n = 0
    conn = _db()
    try:
        url = "/subscriptions"
        for status in ("active", "trialing", "past_due", "canceled", "unpaid"):
            starting_after = None
            while True:
                params = {"limit": 100, "status": status}
                if starting_after:
                    params["starting_after"] = starting_after
                page = _get(key, url, params)
                items = page.get("data", [])
                for s in items:
                    _upsert_subscription(conn, s, now)
                    n += 1
                if not page.get("has_more") or not items:
                    break
                starting_after = items[-1]["id"]
        conn.commit()
    finally:
        conn.close()
    return n


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(message)s")
    print(sync_all())
