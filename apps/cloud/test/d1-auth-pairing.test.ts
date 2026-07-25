import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { DatabaseSync } from "node:sqlite";
import { describe, it } from "node:test";
import { D1CloudRepository } from "../src/d1-repository.ts";

async function repository(now = 1_000) {
  const database = new DatabaseSync(":memory:");
  database.exec(
    await readFile(
      new URL("../migrations/0001_initial.sql", import.meta.url),
      "utf8",
    ),
  );
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
}

describe("D1 authentication and pairing state", () => {
  it("consumes a verified device-login and its invite exactly once", async () => {
    const { repo } = await repository();
    await repo.createInvite({
      id: "invite-1",
      emailCiphertext: new Uint8Array([4, 5, 6]),
      emailLookupHash: "email-hash",
      expiresAt: 10_000,
    });
    await repo.createDeviceLoginSession({
      id: "login-1",
      emailLookupHash: "email-hash",
      pkceChallenge: "pkce-challenge",
      expiresAt: 10_000,
    });
    await repo.setDeviceLoginMagicLink("login-1", "magic-hash");
    await repo.verifyDeviceLoginMagicLink("login-1", "magic-hash");

    const account = await repo.consumeDeviceLogin({
      sessionId: "login-1",
      accountId: "account-1",
      pkceChallenge: "pkce-challenge",
    });
    assert.equal(account.id, "account-1");
    await assert.rejects(
      repo.consumeDeviceLogin({
        sessionId: "login-1",
        accountId: "account-2",
        pkceChallenge: "pkce-challenge",
      }),
      /authentication failed/i,
    );
  });

  it("rotates refresh tokens and revokes the whole family on reuse", async () => {
    const { repo } = await repository();
    await repo.createTestAccount("account-1");
    await repo.createRefreshToken({
      id: "refresh-1",
      accountId: "account-1",
      familyId: "family-1",
      tokenHash: "old-hash",
      expiresAt: 10_000,
    });

    const rotated = await repo.rotateRefreshToken("old-hash", {
      id: "refresh-2",
      tokenHash: "new-hash",
      expiresAt: 20_000,
    });
    assert.deepEqual(rotated, {
      accountId: "account-1",
      familyId: "family-1",
    });

    await assert.rejects(
      repo.rotateRefreshToken("old-hash", {
        id: "refresh-3",
        tokenHash: "third-hash",
        expiresAt: 20_000,
      }),
      /authentication failed/i,
    );
    assert.equal(await repo.isRefreshFamilyActive("family-1"), false);
  });

  it("approves a live pairing once and creates the scoped watch", async () => {
    const { repo } = await repository();
    await repo.createTestAccount("account-1");
    await repo.createHost({
      id: "host-1",
      accountId: "account-1",
      name: "Mac",
      credentialHash: "host-credential",
    });
    await repo.createPairingSession({
      tokenHash: "pair-token-hash",
      codeHash: "pair-code-hash",
      accountId: "account-1",
      hostId: "host-1",
      sessionNonce: "pairing-nonce",
      expiresAt: 10_000,
    });
    await repo.createPairingRequest({
      id: "request-1",
      tokenHash: "pair-token-hash",
      requestFingerprintHash: "fingerprint-hash",
      signingPublicKey: "signing-public-key",
      agreementPublicKey: "agreement-public-key",
      metadata: { manufacturer: "Samsung", model: "Watch6" },
      expiresAt: 3_000,
    });

    const result = await repo.approvePairing({
      accountId: "account-1",
      hostId: "host-1",
      tokenHash: "pair-token-hash",
      requestId: "request-1",
      deviceId: "device-1",
      credentialHash: "device-credential-hash",
    });
    assert.equal(result.deviceId, "device-1");
    assert.equal(result.sessionNonce, "pairing-nonce");
    await assert.rejects(
      repo.approvePairing({
        accountId: "account-1",
        hostId: "host-1",
        tokenHash: "pair-token-hash",
        requestId: "request-1",
        deviceId: "device-2",
        credentialHash: "other",
      }),
      /pairing failed/i,
    );
  });

  it("rejects expired pairing requests and denial creates no watch", async () => {
    const { repo, database } = await repository();
    await repo.createTestAccount("account-1");
    await repo.createHost({
      id: "host-1",
      accountId: "account-1",
      name: "Mac",
      credentialHash: "host-credential",
    });
    await repo.createPairingSession({
      tokenHash: "pair-token-hash",
      codeHash: "pair-code-hash",
      accountId: "account-1",
      hostId: "host-1",
      sessionNonce: "pairing-nonce",
      expiresAt: 10_000,
    });
    await repo.createPairingRequest({
      id: "request-1",
      tokenHash: "pair-token-hash",
      requestFingerprintHash: "fingerprint-hash",
      signingPublicKey: "signing-public-key",
      agreementPublicKey: "agreement-public-key",
      metadata: {},
      expiresAt: 3_000,
    });
    await repo.denyPairing({
      accountId: "account-1",
      hostId: "host-1",
      tokenHash: "pair-token-hash",
      requestId: "request-1",
    });
    assert.equal(
      database.prepare("SELECT COUNT(*) AS count FROM devices").get()?.count,
      0,
    );

    const expired = await repository(5_000);
    await expired.repo.createTestAccount("account-2");
    await expired.repo.createHost({
      id: "host-2",
      accountId: "account-2",
      name: "Mac",
      credentialHash: "host-credential",
    });
    await expired.repo.createPairingSession({
      tokenHash: "expired-token",
      codeHash: "expired-code",
      accountId: "account-2",
      hostId: "host-2",
      sessionNonce: "nonce",
      expiresAt: 4_000,
    });
    await assert.rejects(
      expired.repo.createPairingRequest({
        id: "request-2",
        tokenHash: "expired-token",
        requestFingerprintHash: "fingerprint",
        signingPublicKey: "signing",
        agreementPublicKey: "agreement",
        metadata: {},
        expiresAt: 6_000,
      }),
      /pairing failed/i,
    );
  });
});
