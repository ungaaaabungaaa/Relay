import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { DatabaseSync } from "node:sqlite";
import { describe, it } from "node:test";
import { D1CloudRepository } from "../src/d1-repository.ts";

function repository(now = 1_000) {
  const database = new DatabaseSync(":memory:");
  return readFile(
    new URL("../migrations/0001_initial.sql", import.meta.url),
    "utf8",
  ).then((migration) => {
    database.exec(migration);
    return readFile(
      new URL("../migrations/0002_pairing_completion.sql", import.meta.url),
      "utf8",
    ).then((pairingMigration) => {
      database.exec(pairingMigration);
      const d1 = {
        prepare(sql: string) {
          const statement = database.prepare(sql);
          let values: unknown[] = [];
          const prepared = {
            bind(...bound: unknown[]) {
              values = bound;
              return prepared;
            },
            async run() {
              return statement.run(...values);
            },
            async first<T>() {
              return (statement.get(...values) as T | undefined) ?? null;
            },
            async all<T>() {
              return { results: statement.all(...values) as T[] };
            },
          };
          return prepared;
        },
      };
      return { database, repo: new D1CloudRepository(d1, { now: () => now }) };
    });
  });
}

describe("D1 cloud repository", () => {
  it("atomically consumes an invite once and creates one account", async () => {
    const { repo } = await repository();
    await repo.createInvite({
      id: "invite-1",
      emailCiphertext: new Uint8Array([1, 2, 3]),
      emailLookupHash: "email-hash",
      expiresAt: 5_000,
    });

    const account = await repo.consumeInvite({
      accountId: "account-1",
      emailLookupHash: "email-hash",
    });
    assert.equal(account.id, "account-1");
    await assert.rejects(
      repo.consumeInvite({
        accountId: "account-2",
        emailLookupHash: "email-hash",
      }),
      /authentication failed/i,
    );
  });

  it("enforces one active host and three active watches per beta account", async () => {
    const { repo } = await repository();
    await repo.createTestAccount("account-1");
    await repo.createHost({
      id: "host-1",
      accountId: "account-1",
      name: "Mac",
      credentialHash: "host-credential",
    });
    await assert.rejects(
      repo.createHost({
        id: "host-2",
        accountId: "account-1",
        name: "Other Mac",
        credentialHash: "other",
      }),
      /host limit/i,
    );
    for (let index = 1; index <= 3; index += 1) {
      await repo.createDevice({
        id: `watch-${index}`,
        accountId: "account-1",
        hostId: "host-1",
        credentialHash: `credential-${index}`,
        signingPublicKey: `signing-${index}`,
        agreementPublicKey: `agreement-${index}`,
        metadata: { model: `Watch ${index}` },
      });
    }
    await assert.rejects(
      repo.createDevice({
        id: "watch-4",
        accountId: "account-1",
        hostId: "host-1",
        credentialHash: "credential-4",
        signingPublicKey: "signing-4",
        agreementPublicKey: "agreement-4",
        metadata: {},
      }),
      /device limit/i,
    );
  });

  it("account deletion cascades through every host and watch record", async () => {
    const { repo, database } = await repository();
    await repo.createTestAccount("account-1");
    await repo.createHost({
      id: "host-1",
      accountId: "account-1",
      name: "Mac",
      credentialHash: "host-credential",
    });
    await repo.createDevice({
      id: "watch-1",
      accountId: "account-1",
      hostId: "host-1",
      credentialHash: "watch-credential",
      signingPublicKey: "signing",
      agreementPublicKey: "agreement",
      metadata: {},
    });

    await repo.deleteAccount("account-1");
    assert.equal(database.prepare("SELECT COUNT(*) AS count FROM accounts").get()?.count, 0);
    assert.equal(database.prepare("SELECT COUNT(*) AS count FROM hosts").get()?.count, 0);
    assert.equal(database.prepare("SELECT COUNT(*) AS count FROM devices").get()?.count, 0);
  });
});
