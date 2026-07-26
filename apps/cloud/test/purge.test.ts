import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { purgeExpiredCloudData } from "../src/purge.ts";

test("hourly purge removes expired auth, pairing, and seven-day audit metadata", async () => {
  const database = new DatabaseSync(":memory:");
  database.exec(
    await readFile(new URL("../migrations/0001_initial.sql", import.meta.url), "utf8"),
  );
  database.exec(
    await readFile(
      new URL("../migrations/0002_pairing_completion.sql", import.meta.url),
      "utf8",
    ),
  );
  database.exec(`
    INSERT INTO device_login_sessions
      (id, email_lookup_hash, pkce_challenge, status, created_at, expires_at)
      VALUES ('old-login', 'email-1', 'challenge', 'pending', 1, 99),
             ('live-login', 'email-2', 'challenge', 'pending', 1, 101);
    INSERT INTO audit_metadata
      (id, action, actor_kind, outcome, created_at, expires_at)
      VALUES ('old-audit', 'connect', 'host', 'ok', 1, 99),
             ('live-audit', 'connect', 'host', 'ok', 1, 101);
  `);

  const d1 = {
    prepare(sql: string) {
      return {
        bind(...values: unknown[]) {
          return {
            async run() {
              database.prepare(sql).run(...values);
            },
          };
        },
      };
    },
  };
  await purgeExpiredCloudData(d1, 100);

  assert.deepEqual(
    database
      .prepare("SELECT id FROM device_login_sessions ORDER BY id")
      .all()
      .map((row) => row.id),
    ["live-login"],
  );
  assert.deepEqual(
    database
      .prepare("SELECT id FROM audit_metadata ORDER BY id")
      .all()
      .map((row) => row.id),
    ["live-audit"],
  );
});
