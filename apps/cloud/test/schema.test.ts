import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { describe, it } from "node:test";

const migrationUrl = new URL("../migrations/0001_initial.sql", import.meta.url);
const rateLimitMigrationUrl = new URL(
  "../migrations/0003_rate_limits.sql",
  import.meta.url,
);

describe("Relay Cloud D1 schema", () => {
  it("contains every beta account, auth, host, device, pairing, and audit table", async () => {
    const sql = await readFile(migrationUrl, "utf8");
    for (const table of [
      "accounts",
      "invites",
      "device_login_sessions",
      "refresh_tokens",
      "hosts",
      "devices",
      "pairing_sessions",
      "pairing_requests",
      "audit_metadata",
    ]) {
      assert.match(sql, new RegExp(`CREATE TABLE ${table}\\b`, "i"));
    }
  });

  it("never stores plaintext emails, refresh tokens, or E2EE root keys", async () => {
    const sql = await readFile(migrationUrl, "utf8");
    assert.doesNotMatch(sql, /\bemail\s+TEXT/i);
    assert.doesNotMatch(sql, /\brefresh_token\s+TEXT/i);
    assert.doesNotMatch(sql, /root_key|private_key/i);
    assert.match(sql, /email_ciphertext\s+BLOB/i);
    assert.match(sql, /email_lookup_hash\s+TEXT/i);
    assert.match(sql, /token_hash\s+TEXT/i);
  });

  it("indexes expiry and seven-day purge paths", async () => {
    const sql = `${await readFile(migrationUrl, "utf8")}\n${await readFile(
      rateLimitMigrationUrl,
      "utf8",
    )}`;
    assert.match(sql, /audit_metadata_expiry/i);
    assert.match(sql, /pairing_sessions_expiry/i);
    assert.match(sql, /refresh_tokens_expiry/i);
    assert.match(sql, /CREATE TABLE rate_limits/i);
    assert.match(sql, /rate_limits_expiry/i);
    assert.doesNotMatch(sql, /\bip_address\b/i);
  });
});
