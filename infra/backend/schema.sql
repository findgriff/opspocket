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
