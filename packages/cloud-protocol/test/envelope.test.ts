import assert from "node:assert/strict";
import { describe, it } from "node:test";
import {
  RelayReplayWindow,
  decodePublicKey,
  decryptRelayEnvelope,
  deriveRelayRootKey,
  encodePublicKey,
  encryptRelayEnvelope,
  generateAgreementKeyPair,
  validateVoiceTransfer,
} from "../src/index.ts";

const routing = {
  version: 1 as const,
  messageId: "msg_01",
  accountId: "acct_01",
  hostId: "host_01",
  senderId: "watch_01",
  recipientId: "host_01",
  sentAt: 1_800_000_000_000,
  sequence: 7,
};

describe("Relay cloud encryption", () => {
  it("derives the same root key on the Mac and watch", async () => {
    const mac = await generateAgreementKeyPair();
    const watch = await generateAgreementKeyPair();
    const salt = new Uint8Array(32).fill(9);

    const macRoot = await deriveRelayRootKey(
      mac.privateKey,
      await decodePublicKey(await encodePublicKey(watch.publicKey)),
      salt,
    );
    const watchRoot = await deriveRelayRootKey(
      watch.privateKey,
      await decodePublicKey(await encodePublicKey(mac.publicKey)),
      salt,
    );

    const nonce = new Uint8Array(12).fill(4);
    const encrypted = await encryptRelayEnvelope(
      routing,
      { kind: "request", body: { method: "GET", path: "/v1/tasks" } },
      macRoot,
      nonce,
    );
    assert.deepEqual(await decryptRelayEnvelope(encrypted, watchRoot), {
      kind: "request",
      body: { method: "GET", path: "/v1/tasks" },
    });
  });

  it("rejects any modified authenticated routing field", async () => {
    const mac = await generateAgreementKeyPair();
    const watch = await generateAgreementKeyPair();
    const root = await deriveRelayRootKey(
      mac.privateKey,
      watch.publicKey,
      new Uint8Array(32).fill(3),
    );
    const encrypted = await encryptRelayEnvelope(
      routing,
      { kind: "control", body: { type: "heartbeat" } },
      root,
      new Uint8Array(12).fill(8),
    );

    await assert.rejects(
      decryptRelayEnvelope({ ...encrypted, recipientId: "attacker" }, root),
      /authentication failed/i,
    );
  });

  it("rejects duplicate and out-of-order sequence numbers across reconnects", () => {
    const firstConnection = new RelayReplayWindow({ watch_01: 41 });
    firstConnection.accept("watch_01", 42);
    assert.deepEqual(firstConnection.snapshot(), { watch_01: 42 });

    const reconnected = new RelayReplayWindow(firstConnection.snapshot());
    assert.throws(() => reconnected.accept("watch_01", 42), /replay/i);
    assert.throws(() => reconnected.accept("watch_01", 40), /replay/i);
    reconnected.accept("watch_01", 43);
  });
});

describe("voice transfer limits", () => {
  it("accepts ordered chunks within the 2 MiB and 30 second limits", () => {
    assert.doesNotThrow(() =>
      validateVoiceTransfer([
        { index: 0, byteLength: 131_072, recordedAtMs: 0 },
        { index: 1, byteLength: 131_072, recordedAtMs: 29_000 },
      ]),
    );
  });

  it("rejects oversized, unordered, or overlong transfers", () => {
    assert.throws(
      () =>
        validateVoiceTransfer([
          { index: 0, byteLength: 131_073, recordedAtMs: 0 },
        ]),
      /chunk/i,
    );
    assert.throws(
      () =>
        validateVoiceTransfer([
          { index: 1, byteLength: 1, recordedAtMs: 0 },
        ]),
      /order/i,
    );
    assert.throws(
      () =>
        validateVoiceTransfer([
          { index: 0, byteLength: 1, recordedAtMs: 0 },
          { index: 1, byteLength: 1, recordedAtMs: 30_001 },
        ]),
      /duration/i,
    );
  });
});
