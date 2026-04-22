# Blocked: Customer Account Dashboard (#7) + SaaS Admin Panel (#8)

**Date:** 2026-04-22
**Status:** Analysis / deferred — cannot meaningfully begin until upstream dependencies land.

Both tasks were approved for autonomous execution but cannot be meaningfully built until tasks #4 (Stripe integration), #5 (signup orchestrator), and #6 (welcome email) are in place. This doc captures what's needed, why they're blocked, and what to build first when it's unblocked.

---

## #7 — Customer account dashboard (`opspocket.com/account`)

### What it is

Web UI where a paying Cloud customer logs in and can:

- See their VPS status (IP, tier, renewal date, last payment)
- Change the Control-UI basic-auth password
- Download a snapshot / request manual backup
- Upgrade / downgrade tier (Starter → Pro, Pro → Agency, etc.)
- Cancel subscription (triggers `destroy-tenant.sh` with notice)
- Contact support

### Why it's blocked

The dashboard is a front end that **queries a backend for customer-specific state**. That state today doesn't exist anywhere queryable:

| Data the dashboard would show | Lives where today? | Available? |
|---|---|---|
| Customer identity | Stripe Customer (task #4) | ❌ no Stripe |
| Subscription / tier / renewal | Stripe Subscription | ❌ no Stripe |
| Tenant VPS metadata | `infra/tenants.json` on Mac | ❌ not a queryable API |
| Payment history | Stripe invoices | ❌ no Stripe |
| Auth (login) | — | ❌ no auth layer yet |

There is no way to build a useful dashboard without first standing up:

1. **An auth mechanism** — Stripe Customer Portal gives us 80 % of this for free (magic-link login with email). Practical default.
2. **A backend API** that reads tenant state from `infra/tenants.json` (or better, a proper tenants table — SQLite or Postgres).
3. **Stripe webhooks** so the dashboard reflects real-time subscription state.

### What to build first (unblock)

1. **Stripe integration** (#4) — paid Cloud signups, Checkout, webhooks → `tenants` row.
2. **Signup orchestrator** (#5) — webhook handler provisions VPS + sends email.
3. **Tenants store** (new) — Postgres / SQLite on dev box. `tenants` table with `customer_id, email, tier, server_id, domain, created_at, status`.

Once those exist, `/account` becomes ~2 days of straightforward Next.js (or Flask) + Stripe Customer Portal embed.

### Recommended stack when unblocked

- **Backend:** Python FastAPI on dev box behind Caddy (127.0.0.1:5200), reads tenants table, Stripe SDK
- **Frontend:** add a `/account` section to the existing hand-rolled HTML site (matches the rest; no framework tax). Or if we pick up Next.js for the product surface, use it here.
- **Auth:** Stripe Customer Portal magic-link → session cookie

### Scope preview

- `GET /account/status` — returns tenant JSON
- `GET /account/invoices` — proxies Stripe customer invoices
- `POST /account/change-password` — generates new Control-UI basic-auth hash, SSHs into tenant box and updates Caddyfile
- `POST /account/upgrade` — Stripe subscription update + Hetzner `rescale` API call

---

## #8 — SaaS admin panel (you, the founder)

### What it is

Internal web UI where you see + manage every tenant:

- Table of all customer boxes: email, domain, tier, created, status, health
- One-click "open SSH", "run install-openclaw.sh again", "snapshot now"
- Billing health per tenant (from Stripe)
- Usage per tenant (CPU/RAM via Hetzner API)
- Push announcements / maintenance windows

### Why it's blocked

Same root issue as #7 — the admin panel is a UI over a tenants database. Today's state:

| Data | Where | Queryable? |
|---|---|---|
| Active tenants | `infra/tenants.json` on Mac (sparse; only set by `provision-tenant.sh`) | ❌ |
| Billing state | Stripe | ❌ no integration |
| VPS metrics | Hetzner API + in-box agents | ⚠️ API works, no UI |
| Outstanding support tickets | — | ❌ no ticketing |

### The orchestrator is a prerequisite

The admin panel's most valuable actions (provision, re-install, snapshot, destroy) need to be HTTP endpoints. Today they're shell scripts (`provision-tenant.sh`, `destroy-tenant.sh`, `hetzner-snapshot.sh`). The orchestrator service (task #5) wraps those in an HTTP API — the admin panel sits on top of it.

### Smallest useful first version (after orchestrator exists)

A single Python/FastAPI app behind basic-auth that:

1. Reads all tenants from the tenants table
2. For each, shows: domain, tier, server_id, IP, status (from Hetzner `/servers/{id}`), last snapshot age
3. Provides "Snapshot now", "Open in Hetzner console", "Destroy" buttons
4. Lives at `admin.opspocket.com`, protected by Caddy basic_auth (you only)

That's ~1 day of work once the orchestrator + tenants table exist.

---

## What IS possible today without #4/#5/#6

The following pieces can be built now and be useful:

- ✅ **Uptime Kuma** monitoring — done this session at `status.opspocket.com`
- ✅ **Hetzner snapshots** — done this session (daily timer + provision-time post-install snapshot)
- ✅ **`destroy-tenant.sh`** — done this session; handles teardown when a customer cancels (awaiting the orchestrator to call it)
- ✅ **Migration tooling + docs** — done

When Stripe + orchestrator land, a minimum viable admin UI + account UI can both land within ~1 week of that.

---

## Decision

**Defer #7 and #8** until #4/#5/#6 are in place. Track here so future-you can pick up without re-analysis.
