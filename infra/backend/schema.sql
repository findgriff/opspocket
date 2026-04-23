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
