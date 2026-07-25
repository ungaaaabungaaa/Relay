import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { describe, it } from "node:test";
import { InMemoryCloudStore, RelayCloudService } from "../src/service.ts";

function service() {
  const store = new InMemoryCloudStore();
  return { store, cloud: new RelayCloudService(store, { now: () => 1_000_000 }) };
}

describe("invite-only accounts", () => {
  it("creates an account only from an unused invited email", async () => {
    const { cloud } = service();
    await cloud.createInvite("owner@example.com", "admin-secret");

    const session = await cloud.startDeviceLogin({
      email: "owner@example.com",
      pkceChallenge: "challenge",
    });
    assert.equal(session.status, "pending");

    await assert.rejects(
      cloud.startDeviceLogin({
        email: "stranger@example.com",
        pkceChallenge: "challenge",
      }),
      /authentication failed/i,
    );
  });

  it("verifies a single-use magic link and exchanges only the matching PKCE verifier", async () => {
    const { cloud } = service();
    await cloud.createInvite("owner@example.com", "admin-secret");
    const verifier = "a-valid-pkce-verifier-with-at-least-forty-three-characters";
    const challenge = createHash("sha256")
      .update(verifier)
      .digest("base64url");
    const session = await cloud.startDeviceLogin({
      email: "owner@example.com",
      pkceChallenge: challenge,
    });
    const magicLink = await cloud.issueMagicLink(session.id);

    await cloud.verifyMagicLink(session.id, magicLink);
    await assert.rejects(
      cloud.verifyMagicLink(session.id, magicLink),
      /authentication failed/i,
    );
    await assert.rejects(
      cloud.exchangeDeviceLogin(session.id, "wrong-verifier"),
      /authentication failed/i,
    );
    const account = await cloud.exchangeDeviceLogin(session.id, verifier);
    assert.equal(account.email, "owner@example.com");
    await assert.rejects(
      cloud.exchangeDeviceLogin(session.id, verifier),
      /authentication failed/i,
    );
  });

  it("expires unverified device login sessions after ten minutes", async () => {
    let now = 1_000;
    const store = new InMemoryCloudStore();
    const cloud = new RelayCloudService(store, { now: () => now });
    await cloud.createInvite("owner@example.com", "admin-secret");
    const session = await cloud.startDeviceLogin({
      email: "owner@example.com",
      pkceChallenge: "a-valid-challenge",
    });
    const magicLink = await cloud.issueMagicLink(session.id);
    now += 10 * 60_000 + 1;

    await assert.rejects(
      cloud.verifyMagicLink(session.id, magicLink),
      /authentication failed/i,
    );
  });

  it("never returns whether an uninvited account exists", async () => {
    const { cloud } = service();
    const errors = await Promise.all(
      ["nobody@example.com", "also-nobody@example.com"].map(async (email) => {
        try {
          await cloud.startDeviceLogin({ email, pkceChallenge: "challenge" });
          return "";
        } catch (error) {
          return (error as Error).message;
        }
      }),
    );
    assert.deepEqual(errors, ["Authentication failed", "Authentication failed"]);
  });
});

describe("host and watch isolation", () => {
  it("allows one host and three devices, isolated to one account", async () => {
    const { cloud } = service();
    const accountA = await cloud.createTestAccount("a@example.com");
    const accountB = await cloud.createTestAccount("b@example.com");
    const host = await cloud.registerHost(accountA.id, "Mac");
    await assert.rejects(cloud.registerHost(accountA.id, "Other Mac"), /host limit/i);

    for (let index = 0; index < 3; index += 1) {
      await cloud.createTestDevice(accountA.id, host.id, `Watch ${index}`);
    }
    await assert.rejects(
      cloud.createTestDevice(accountA.id, host.id, "Fourth Watch"),
      /device limit/i,
    );
    await assert.rejects(
      cloud.createTestDevice(accountB.id, host.id, "Cross-account Watch"),
      /authentication failed/i,
    );
  });

  it("routes opaque ciphertext without inspecting the inner message", async () => {
    const { cloud } = service();
    const account = await cloud.createTestAccount("a@example.com");
    const host = await cloud.registerHost(account.id, "Mac");
    const device = await cloud.createTestDevice(account.id, host.id, "Watch");
    const envelope = {
      version: 1 as const,
      messageId: "message",
      accountId: account.id,
      hostId: host.id,
      senderId: device.id,
      recipientId: host.id,
      sentAt: 10,
      sequence: 1,
      nonce: "cloud-cannot-read-this",
      ciphertext: "still-opaque",
    };

    assert.deepEqual(await cloud.route(account.id, device.id, envelope), envelope);
    await assert.rejects(
      cloud.route("another-account", device.id, envelope),
      /authentication failed/i,
    );
  });
});

describe("cloud pairing", () => {
  it("expires codes, requires approval, and leaves no device after denial", async () => {
    let now = 2_000;
    const store = new InMemoryCloudStore();
    const cloud = new RelayCloudService(store, { now: () => now });
    const account = await cloud.createTestAccount("a@example.com");
    const host = await cloud.registerHost(account.id, "Mac");
    const pairing = await cloud.createPairingSession(account.id, host.id);
    assert.match(pairing.code, /^[A-Z0-9]{6}$/);

    const request = await cloud.requestPairing(pairing.token, {
      publicKey: "watch-public-key",
      fingerprint: "WATCH FP",
      metadata: { platform: "wear", model: "Pixel Watch" },
    });
    await cloud.denyPairing(account.id, host.id, pairing.token, request.id);
    assert.equal(store.devices.size, 0);

    const expired = await cloud.createPairingSession(account.id, host.id);
    now += 5 * 60_000 + 1;
    await assert.rejects(
      cloud.requestPairing(expired.token, {
        publicKey: "watch-public-key",
        fingerprint: "WATCH FP",
        metadata: { platform: "wear" },
      }),
      /pairing failed/i,
    );
  });
});

describe("account safety controls", () => {
  it("emergency stop revokes every watch and rotates the host credential", async () => {
    const { cloud } = service();
    const account = await cloud.createTestAccount("a@example.com");
    const host = await cloud.registerHost(account.id, "Mac");
    const device = await cloud.createTestDevice(account.id, host.id, "Watch");
    const result = await cloud.emergencyStop(account.id, host.id);

    assert.notEqual(result.hostCredential, host.credential);
    assert.equal(result.revokedDeviceIds[0], device.id);
    assert.equal((await cloud.getDevice(device.id))?.revoked, true);
  });

  it("deletes account PII and device metadata", async () => {
    const { cloud, store } = service();
    const account = await cloud.createTestAccount("delete@example.com");
    const host = await cloud.registerHost(account.id, "Mac");
    await cloud.createTestDevice(account.id, host.id, "Watch");

    await cloud.deleteAccount(account.id);
    assert.equal(store.accounts.size, 0);
    assert.equal(store.hosts.size, 0);
    assert.equal(store.devices.size, 0);
  });
});
