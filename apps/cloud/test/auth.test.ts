import assert from "node:assert/strict";
import { describe, it } from "node:test";
import {
  InMemoryTokenStore,
  RelayAuthTokens,
  decryptEmail,
  encryptEmail,
  emailLookupHash,
} from "../src/auth.ts";

const secrets = {
  jwtSecret: new Uint8Array(32).fill(1),
  piiKey: new Uint8Array(32).fill(2),
  emailHmacKey: new Uint8Array(32).fill(3),
};

describe("email privacy", () => {
  it("encrypts normalized email and creates a separate deterministic lookup hash", async () => {
    const first = await encryptEmail(" Owner@Example.COM ", secrets.piiKey);
    const second = await encryptEmail("owner@example.com", secrets.piiKey);
    assert.notEqual(first, second);
    assert.doesNotMatch(first, /owner|example/i);
    assert.equal(await decryptEmail(first, secrets.piiKey), "owner@example.com");
    assert.equal(
      await emailLookupHash(" Owner@Example.COM ", secrets.emailHmacKey),
      await emailLookupHash("owner@example.com", secrets.emailHmacKey),
    );
  });
});

describe("rotating refresh tokens", () => {
  it("issues a 15-minute access token and a 30-day refresh token", async () => {
    const auth = new RelayAuthTokens(new InMemoryTokenStore(), secrets, {
      now: () => 1_000,
    });
    const issued = await auth.issue("account-1", "mac-1");
    const claims = await auth.verifyAccessToken(issued.accessToken);

    assert.equal(claims.accountId, "account-1");
    assert.equal(claims.hostId, "mac-1");
    assert.equal(claims.expiresAt, 1_000 + 15 * 60_000);
    assert.equal(issued.refreshExpiresAt, 1_000 + 30 * 24 * 60 * 60_000);
  });

  it("rotates refresh tokens and revokes the family when an old token is reused", async () => {
    let now = 1_000;
    const store = new InMemoryTokenStore();
    const auth = new RelayAuthTokens(store, secrets, { now: () => now });
    const first = await auth.issue("account-1", "mac-1");
    now += 1_000;
    const second = await auth.refresh(first.refreshToken);

    await assert.rejects(auth.refresh(first.refreshToken), /authentication failed/i);
    await assert.rejects(auth.refresh(second.refreshToken), /authentication failed/i);
    assert.equal(store.activeFamilyCount(), 0);
  });

  it("logout revokes only the current refresh family", async () => {
    const store = new InMemoryTokenStore();
    const auth = new RelayAuthTokens(store, secrets, { now: () => 1_000 });
    const first = await auth.issue("account-1", "mac-1");
    const second = await auth.issue("account-1", "mac-1");

    await auth.logout(first.refreshToken);
    await assert.rejects(auth.refresh(first.refreshToken), /authentication failed/i);
    assert.ok((await auth.refresh(second.refreshToken)).accessToken);
  });
});
