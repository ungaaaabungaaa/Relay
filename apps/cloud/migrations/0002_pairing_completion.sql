ALTER TABLE pairing_requests ADD COLUMN poll_token_hash TEXT;
ALTER TABLE pairing_requests ADD COLUMN approved_device_id TEXT;
ALTER TABLE pairing_requests ADD COLUMN approved_payload_json TEXT;

CREATE UNIQUE INDEX pairing_requests_poll_token
  ON pairing_requests(poll_token_hash)
  WHERE poll_token_hash IS NOT NULL;

