-- Dedicated state store for the V2rayAG app Worker.
-- Subscription source URLs stay in the existing POOL KV namespace.
CREATE TABLE IF NOT EXISTS app_meta (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS pool_subscriptions (
  sub_id TEXT PRIMARY KEY,
  record_json TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS app_devices (
  device_hash TEXT PRIMARY KEY,
  record_json TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  active INTEGER NOT NULL CHECK (active IN (0, 1))
);

CREATE TABLE IF NOT EXISTS app_leases (
  lease_id TEXT PRIMARY KEY,
  sub_id TEXT NOT NULL,
  profile_id TEXT NOT NULL,
  device_hash TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  expires_at INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS app_leases_by_device ON app_leases(device_hash);
CREATE INDEX IF NOT EXISTS app_leases_by_sub ON app_leases(sub_id);
CREATE INDEX IF NOT EXISTS app_leases_by_expiry ON app_leases(expires_at);

CREATE TABLE IF NOT EXISTS pool_profiles (
  profile_id TEXT PRIMARY KEY,
  sub_id TEXT NOT NULL,
  uri TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS pool_profiles_by_sub ON pool_profiles(sub_id);

CREATE TABLE IF NOT EXISTS pool_subscription_state (
  sub_id TEXT PRIMARY KEY,
  state_json TEXT NOT NULL,
  checked_at INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS pool_refresh_locks (
  sub_id TEXT PRIMARY KEY,
  locked_until INTEGER NOT NULL
);
