-- OpsPocket Cloud tenants DB.
-- Path on dev box: /var/lib/opspocket/tenants.db
-- Owner: root (service runs as root alongside opspocket-waitlist).

CREATE TABLE IF NOT EXISTS tenants (
  id TEXT PRIMARY KEY,             -- short hex like 'a1b2c3d4'
  customer_email TEXT NOT NULL,
  stripe_customer_id TEXT,         -- from Stripe customer
  stripe_subscription_id TEXT UNIQUE,
  tier TEXT NOT NULL,              -- starter / pro / agency
  interval TEXT NOT NULL,          -- month / year
  domain TEXT,                     -- t-<id>.opspocket.com
  hetzner_server_id INTEGER,
  hetzner_ip TEXT,
  status TEXT NOT NULL,            -- 'pending' / 'provisioning' / 'active' / 'failed' / 'cancelled'
  openclaw_password TEXT,          -- basic-auth pw for the Control UI (clawmine)
  gateway_token TEXT,              -- OpenClaw MCP gateway token
  created_at TEXT NOT NULL,
  last_status_change TEXT NOT NULL,
  notes TEXT
);

CREATE INDEX IF NOT EXISTS idx_tenants_status ON tenants(status);
CREATE INDEX IF NOT EXISTS idx_tenants_email  ON tenants(customer_email);

-- Webhook event log (for idempotency + audit).
CREATE TABLE IF NOT EXISTS stripe_events (
  id TEXT PRIMARY KEY,             -- evt_...
  type TEXT NOT NULL,
  received_at TEXT NOT NULL,
  payload TEXT NOT NULL
);

-- ── Customer self-service (magic-link login) ─────────────────────────
--
-- Customers log in by email → we email a one-time token → they click
-- the link → we set a session cookie. No passwords. 30-minute token
-- TTL, 30-day session TTL.

CREATE TABLE IF NOT EXISTS magic_tokens (
  token TEXT PRIMARY KEY,          -- URL-safe random 32 bytes
  email TEXT NOT NULL,
  issued_at INTEGER NOT NULL,      -- unix seconds
  used_at INTEGER                  -- null until consumed
);
CREATE INDEX IF NOT EXISTS idx_magic_tokens_email ON magic_tokens(email);

CREATE TABLE IF NOT EXISTS sessions (
  sid TEXT PRIMARY KEY,            -- URL-safe random 32 bytes
  email TEXT NOT NULL,
  issued_at INTEGER NOT NULL,
  expires_at INTEGER NOT NULL      -- unix seconds
);
CREATE INDEX IF NOT EXISTS idx_sessions_email ON sessions(email);
CREATE INDEX IF NOT EXISTS idx_sessions_expires ON sessions(expires_at);

-- ── App pairing (deep-link onboarding) ───────────────────────────────
--
-- Generated when a tenant hits 'active'. The welcome email embeds
-- opspocket://pair?code=<code>. The iOS app fetches /api/pair/<code>
-- exactly once and writes the creds straight into Keychain. 7-day TTL.

CREATE TABLE IF NOT EXISTS pair_codes (
  code TEXT PRIMARY KEY,           -- URL-safe random 12 chars
  tenant_id TEXT NOT NULL,
  issued_at INTEGER NOT NULL,
  expires_at INTEGER NOT NULL,
  used_at INTEGER,                 -- null until fetched
  FOREIGN KEY (tenant_id) REFERENCES tenants(id)
);
CREATE INDEX IF NOT EXISTS idx_pair_codes_tenant ON pair_codes(tenant_id);

-- ── CRM: company / account profile ────────────────────────────────
-- One row per customer email. Free-form fields the founder edits in
-- /admin, or the customer edits in /account.
CREATE TABLE IF NOT EXISTS customers (
  email TEXT PRIMARY KEY,          -- canonical key (lowercase)
  company_name TEXT,
  contact_name TEXT,
  job_title TEXT,
  phone TEXT,
  website TEXT,
  industry TEXT,
  billing_address TEXT,
  vat_number TEXT,
  country TEXT,
  lifecycle TEXT DEFAULT 'active', -- lead / trial / active / paused / churned
  health_score INTEGER,            -- 0-100, nullable
  tags TEXT,                       -- comma-separated
  account_owner TEXT,              -- 'craig', etc.
  lead_source TEXT,                -- waitlist / google / referral / etc
  notes TEXT,                      -- internal free-text
  consent_marketing INTEGER DEFAULT 0,  -- 0/1
  consent_updated_at TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_customers_lifecycle ON customers(lifecycle);

-- ── CRM: free-form notes + tasks (anchored to tenant OR customer) ──
CREATE TABLE IF NOT EXISTS crm_notes (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  tenant_id TEXT,                  -- optional
  customer_email TEXT,             -- optional (one of the two should be set)
  author TEXT NOT NULL,            -- 'craig' / admin name
  body TEXT NOT NULL,
  pinned INTEGER DEFAULT 0,
  created_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_crm_notes_tenant ON crm_notes(tenant_id);
CREATE INDEX IF NOT EXISTS idx_crm_notes_email ON crm_notes(customer_email);

CREATE TABLE IF NOT EXISTS crm_tasks (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  tenant_id TEXT,
  customer_email TEXT,
  title TEXT NOT NULL,
  due_at TEXT,
  status TEXT NOT NULL DEFAULT 'open',  -- open / done / cancelled
  priority TEXT NOT NULL DEFAULT 'normal',  -- low / normal / high
  assigned_to TEXT,
  created_at TEXT NOT NULL,
  completed_at TEXT
);
CREATE INDEX IF NOT EXISTS idx_crm_tasks_status ON crm_tasks(status);

-- ── Stripe snapshot cache (refreshable from API) ──────────────────
CREATE TABLE IF NOT EXISTS stripe_customers (
  id TEXT PRIMARY KEY,             -- cus_...
  email TEXT,
  name TEXT,
  phone TEXT,
  balance INTEGER,                 -- unpaid in minor units
  currency TEXT,
  delinquent INTEGER DEFAULT 0,
  created_at INTEGER,              -- unix from stripe
  synced_at INTEGER NOT NULL       -- unix when we last refreshed
);

CREATE TABLE IF NOT EXISTS stripe_subscriptions (
  id TEXT PRIMARY KEY,             -- sub_...
  customer_id TEXT NOT NULL,
  status TEXT NOT NULL,            -- active / trialing / canceled / past_due / unpaid
  price_id TEXT,
  product_id TEXT,
  interval TEXT,                   -- month / year
  amount INTEGER,                  -- minor units per interval
  currency TEXT,
  current_period_start INTEGER,
  current_period_end INTEGER,
  cancel_at INTEGER,
  canceled_at INTEGER,
  trial_end INTEGER,
  synced_at INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_stripe_subs_cust ON stripe_subscriptions(customer_id);
CREATE INDEX IF NOT EXISTS idx_stripe_subs_status ON stripe_subscriptions(status);

CREATE TABLE IF NOT EXISTS stripe_invoices (
  id TEXT PRIMARY KEY,             -- in_...
  customer_id TEXT,
  subscription_id TEXT,
  status TEXT,                     -- draft / open / paid / uncollectible / void
  amount_due INTEGER,
  amount_paid INTEGER,
  amount_remaining INTEGER,
  currency TEXT,
  number TEXT,
  hosted_invoice_url TEXT,
  invoice_pdf TEXT,
  paid_at INTEGER,
  created_at INTEGER,
  period_start INTEGER,
  period_end INTEGER,
  synced_at INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_stripe_invoices_cust ON stripe_invoices(customer_id);
CREATE INDEX IF NOT EXISTS idx_stripe_invoices_status ON stripe_invoices(status);

CREATE TABLE IF NOT EXISTS stripe_charges (
  id TEXT PRIMARY KEY,             -- ch_...
  customer_id TEXT,
  invoice_id TEXT,
  amount INTEGER,
  currency TEXT,
  status TEXT,                     -- succeeded / failed / pending
  failure_code TEXT,
  failure_message TEXT,
  refunded INTEGER DEFAULT 0,
  amount_refunded INTEGER DEFAULT 0,
  receipt_url TEXT,
  created_at INTEGER,
  synced_at INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_stripe_charges_cust ON stripe_charges(customer_id);
CREATE INDEX IF NOT EXISTS idx_stripe_charges_status ON stripe_charges(status);

-- ── Hetzner snapshot cache (live server state) ─────────────────────
CREATE TABLE IF NOT EXISTS hetzner_servers (
  id INTEGER PRIMARY KEY,          -- hetzner server id
  tenant_id TEXT,                  -- back-ref (FK soft — may be null for dev box)
  name TEXT,
  status TEXT,                     -- running / off / deleting / etc.
  server_type TEXT,                -- cpx22, cpx32, cx43…
  vcpus INTEGER,
  memory_gb INTEGER,
  disk_gb INTEGER,
  datacenter TEXT,                 -- nbg1, hel1, etc.
  ipv4 TEXT,
  ipv6 TEXT,
  created_at INTEGER,              -- unix from hetzner
  synced_at INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS hetzner_snapshots (
  id INTEGER PRIMARY KEY,          -- image id on hetzner
  server_id INTEGER,
  server_name TEXT,
  description TEXT,
  image_size_gb REAL,
  created_at INTEGER,
  synced_at INTEGER NOT NULL
);

-- ── Audit log — every admin mutation ───────────────────────────────
CREATE TABLE IF NOT EXISTS audit_log (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  actor TEXT NOT NULL,             -- 'craig' / admin username / 'system'
  action TEXT NOT NULL,            -- 'tenant.pause' / 'sub.cancel' / 'note.create'
  target_type TEXT,                -- 'tenant' / 'customer' / 'subscription' / 'system'
  target_id TEXT,
  detail TEXT,                     -- free-form or JSON
  ip TEXT,
  created_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_audit_actor ON audit_log(actor);
CREATE INDEX IF NOT EXISTS idx_audit_target ON audit_log(target_type, target_id);
CREATE INDEX IF NOT EXISTS idx_audit_created ON audit_log(created_at);

-- ── Usage / activity ───────────────────────────────────────────────
-- Simple counters per tenant + event log. Activity rows can come from
-- the tenant's OpenClaw box via SSH poller, from webhook events, or
-- from manual admin actions.
CREATE TABLE IF NOT EXISTS tenant_activity (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  tenant_id TEXT NOT NULL,
  kind TEXT NOT NULL,              -- 'login' / 'api_call' / 'skill_install' / 'agent_run'
  detail TEXT,
  ts TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_tenant_activity_tenant ON tenant_activity(tenant_id);
CREATE INDEX IF NOT EXISTS idx_tenant_activity_kind ON tenant_activity(kind);

-- ── Support tickets (lean) ─────────────────────────────────────────
CREATE TABLE IF NOT EXISTS support_tickets (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  tenant_id TEXT,
  customer_email TEXT NOT NULL,
  subject TEXT NOT NULL,
  body TEXT,
  status TEXT NOT NULL DEFAULT 'open',  -- open / in_progress / waiting / closed
  priority TEXT NOT NULL DEFAULT 'normal',
  assigned_to TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  closed_at TEXT
);
CREATE INDEX IF NOT EXISTS idx_support_tickets_status ON support_tickets(status);

-- ── Feature flags (per-tenant overrides) ───────────────────────────
CREATE TABLE IF NOT EXISTS feature_flags (
  tenant_id TEXT NOT NULL,
  flag TEXT NOT NULL,              -- 'beta.integrations' / 'agency.custom_model'
  enabled INTEGER NOT NULL DEFAULT 0,
  updated_at TEXT NOT NULL,
  PRIMARY KEY (tenant_id, flag)
);

-- ── Heartbeat secret lives on the tenant row ──────────────────────
-- We can't ALTER in CREATE IF NOT EXISTS, so we add the column below
-- (SQLite ADD COLUMN is idempotent via our migration helper in app.py).

-- ── Heartbeat latest state (one row per tenant) ────────────────────
-- Tenant boxes POST to /api/tenants/<id>/heartbeat every 60s with a
-- small JSON payload + HMAC-SHA256 signature using the tenant's
-- per-tenant heartbeat_secret. We upsert this row + append to history.
CREATE TABLE IF NOT EXISTS tenant_heartbeats (
  tenant_id TEXT PRIMARY KEY,
  received_at INTEGER NOT NULL,          -- unix seconds; freshness = now - received_at
  cpu_percent REAL,
  ram_percent REAL,
  disk_percent REAL,
  uptime_seconds INTEGER,
  load_1 REAL,
  load_5 REAL,
  load_15 REAL,
  openclaw_version TEXT,
  docker_containers INTEGER,
  docker_containers_running INTEGER,
  failed_services INTEGER,
  failed_service_names TEXT,             -- comma-joined
  tls_cert_days_left INTEGER,
  restart_loop_count INTEGER,            -- containers that restarted >2x in last 10 min
  raw_payload TEXT,                      -- full JSON for debugging
  FOREIGN KEY (tenant_id) REFERENCES tenants(id)
);

CREATE TABLE IF NOT EXISTS tenant_heartbeat_history (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  tenant_id TEXT NOT NULL,
  received_at INTEGER NOT NULL,
  cpu_percent REAL,
  ram_percent REAL,
  disk_percent REAL
);
CREATE INDEX IF NOT EXISTS idx_hb_hist_tenant ON tenant_heartbeat_history(tenant_id, received_at);

-- ── Hetzner metrics cache (hypervisor view) ────────────────────────
CREATE TABLE IF NOT EXISTS hetzner_metrics (
  server_id INTEGER NOT NULL,
  ts INTEGER NOT NULL,                   -- unix seconds
  cpu_percent REAL,
  net_in_bytes INTEGER,
  net_out_bytes INTEGER,
  PRIMARY KEY (server_id, ts)
);
CREATE INDEX IF NOT EXISTS idx_hz_metrics_ts ON hetzner_metrics(server_id, ts DESC);

-- Snapshot of current month's traffic for each server (cheap query).
CREATE TABLE IF NOT EXISTS hetzner_traffic (
  server_id INTEGER PRIMARY KEY,
  included_bytes INTEGER,                -- monthly included (e.g. 20 TB)
  outgoing_bytes INTEGER,
  ingoing_bytes INTEGER,
  synced_at INTEGER NOT NULL
);

-- ── GDPR / data subject requests ───────────────────────────────────
CREATE TABLE IF NOT EXISTS gdpr_requests (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  email TEXT NOT NULL,
  kind TEXT NOT NULL,              -- 'export' / 'delete'
  status TEXT NOT NULL DEFAULT 'pending',  -- pending / completed / rejected
  requested_at TEXT NOT NULL,
  completed_at TEXT,
  output_path TEXT                 -- path to the generated export if any
);
