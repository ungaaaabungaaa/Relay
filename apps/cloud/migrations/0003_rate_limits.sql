CREATE TABLE rate_limits (
  scope_hash TEXT NOT NULL,
  window_started_at INTEGER NOT NULL,
  attempt_count INTEGER NOT NULL DEFAULT 0,
  expires_at INTEGER NOT NULL,
  PRIMARY KEY (scope_hash, window_started_at)
);

CREATE INDEX rate_limits_expiry ON rate_limits(expires_at);
