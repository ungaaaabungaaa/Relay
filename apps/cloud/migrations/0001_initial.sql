PRAGMA foreign_keys = ON;

CREATE TABLE accounts (
  id TEXT PRIMARY KEY,
  email_ciphertext BLOB NOT NULL,
  email_lookup_hash TEXT NOT NULL UNIQUE,
  created_at INTEGER NOT NULL,
  deleted_at INTEGER
);

CREATE TABLE invites (
  id TEXT PRIMARY KEY,
  email_ciphertext BLOB NOT NULL,
  email_lookup_hash TEXT NOT NULL UNIQUE,
  created_at INTEGER NOT NULL,
  expires_at INTEGER NOT NULL,
  consumed_at INTEGER
);

CREATE TABLE device_login_sessions (
  id TEXT PRIMARY KEY,
  email_lookup_hash TEXT NOT NULL,
  pkce_challenge TEXT NOT NULL,
  magic_link_hash TEXT,
  status TEXT NOT NULL CHECK (status IN ('pending', 'verified', 'consumed', 'revoked')),
  created_at INTEGER NOT NULL,
  expires_at INTEGER NOT NULL
);

CREATE TABLE refresh_tokens (
  id TEXT PRIMARY KEY,
  account_id TEXT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  family_id TEXT NOT NULL,
  token_hash TEXT NOT NULL UNIQUE,
  created_at INTEGER NOT NULL,
  expires_at INTEGER NOT NULL,
  consumed_at INTEGER,
  revoked_at INTEGER
);

CREATE TABLE hosts (
  id TEXT PRIMARY KEY,
  account_id TEXT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  credential_hash TEXT NOT NULL,
  signing_public_key TEXT,
  agreement_public_key TEXT,
  created_at INTEGER NOT NULL,
  last_seen_at INTEGER,
  revoked_at INTEGER
);

CREATE UNIQUE INDEX one_active_host_per_account
  ON hosts(account_id) WHERE revoked_at IS NULL;

CREATE TABLE devices (
  id TEXT PRIMARY KEY,
  account_id TEXT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  host_id TEXT NOT NULL REFERENCES hosts(id) ON DELETE CASCADE,
  credential_hash TEXT NOT NULL,
  signing_public_key TEXT NOT NULL,
  agreement_public_key TEXT NOT NULL,
  metadata_json TEXT NOT NULL DEFAULT '{}',
  created_at INTEGER NOT NULL,
  last_seen_at INTEGER,
  revoked_at INTEGER
);

CREATE INDEX devices_by_host ON devices(host_id, revoked_at);

CREATE TABLE pairing_sessions (
  token_hash TEXT PRIMARY KEY,
  code_hash TEXT NOT NULL,
  account_id TEXT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  host_id TEXT NOT NULL REFERENCES hosts(id) ON DELETE CASCADE,
  session_nonce TEXT NOT NULL,
  mac_fingerprint TEXT NOT NULL DEFAULT '',
  attempt_count INTEGER NOT NULL DEFAULT 0,
  created_at INTEGER NOT NULL,
  expires_at INTEGER NOT NULL,
  consumed_at INTEGER
);

CREATE INDEX pairing_sessions_expiry ON pairing_sessions(expires_at);

CREATE TABLE pairing_requests (
  id TEXT PRIMARY KEY,
  pairing_token_hash TEXT NOT NULL REFERENCES pairing_sessions(token_hash) ON DELETE CASCADE,
  request_fingerprint_hash TEXT NOT NULL,
  signing_public_key TEXT NOT NULL,
  agreement_public_key TEXT NOT NULL,
  metadata_json TEXT NOT NULL DEFAULT '{}',
  status TEXT NOT NULL CHECK (status IN ('pending', 'approved', 'denied', 'expired')),
  created_at INTEGER NOT NULL,
  expires_at INTEGER NOT NULL,
  resolved_at INTEGER
);

CREATE TABLE audit_metadata (
  id TEXT PRIMARY KEY,
  account_id TEXT,
  action TEXT NOT NULL,
  actor_kind TEXT NOT NULL,
  outcome TEXT NOT NULL,
  request_size INTEGER,
  response_size INTEGER,
  created_at INTEGER NOT NULL,
  expires_at INTEGER NOT NULL
);

CREATE INDEX audit_metadata_expiry ON audit_metadata(expires_at);
CREATE INDEX refresh_tokens_expiry ON refresh_tokens(expires_at);
CREATE INDEX device_login_sessions_expiry ON device_login_sessions(expires_at);
