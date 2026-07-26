import assert from "node:assert/strict";
import { describe, it } from "node:test";
import {
  decryptRelayEnvelope,
  deriveRelayRootKey,
  encryptRelayEnvelope,
  generateAgreementKeyPair,
} from "../../../packages/cloud-protocol/src/index.ts";
import { CloudTunnelAdapter } from "../src/cloud/cloud-tunnel-adapter.ts";

async function fixture() {
  const mac = await generateAgreementKeyPair();
  const watch = await generateAgreementKeyPair();
  const salt = new Uint8Array(32).fill(7);
  const root = await deriveRelayRootKey(mac.privateKey, watch.publicKey, salt);
  const watchRoot = await deriveRelayRootKey(watch.privateKey, mac.publicKey, salt);
  return { root, watchRoot };
}

describe("bridge cloud tunnel adapter", () => {
  it("decrypts an HTTP-style request and returns an encrypted response", async () => {
    const { root, watchRoot } = await fixture();
    const handled: Request[] = [];
    const adapter = new CloudTunnelAdapter({
      hostId: "host-1",
      keyForDevice: async () => root,
      loadReplayState: async () => ({}),
      saveReplayState: async () => {},
      handler: async (request) => {
        handled.push(request);
        return Response.json({ tasks: ["task-1"] });
      },
      now: () => 2_000,
    });
    const incoming = await encryptRelayEnvelope(
      {
        version: 1,
        messageId: "request-1",
        accountId: "account-1",
        hostId: "host-1",
        senderId: "watch-1",
        recipientId: "host-1",
        sentAt: 1_900,
        sequence: 1,
      },
      {
        kind: "request",
        body: {
          method: "GET",
          path: "/v1/tasks",
          headers: { "x-relay-device": "watch-1" },
          body: "",
        },
      },
      watchRoot,
      new Uint8Array(12).fill(4),
    );

    const outgoing = await adapter.receive(incoming);
    assert.equal(handled[0]?.url, "http://relay.internal/v1/tasks");
    assert.equal(outgoing.senderId, "host-1");
    assert.equal(outgoing.recipientId, "watch-1");
    assert.equal(outgoing.sequence, 1);
    assert.deepEqual(await decryptRelayEnvelope(outgoing, watchRoot), {
      kind: "response",
      body: {
        requestId: "request-1",
        status: 200,
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ tasks: ["task-1"] }),
      },
    });
  });

  it("decodes authenticated base64 voice bodies before bridge handling", async () => {
    const { watchRoot } = await fixture();
    let received = new Uint8Array();
    const adapter = new CloudTunnelAdapter({
      hostId: "host-1",
      keyForDevice: async () => watchRoot,
      loadReplayState: async () => ({}),
      saveReplayState: async () => {},
      handler: async (request) => {
        received = new Uint8Array(await request.arrayBuffer());
        return Response.json({ transcript: "hello" });
      },
      now: () => 2_000,
    });
    const incoming = await encryptRelayEnvelope(
      {
        version: 1,
        messageId: "voice-1",
        accountId: "account-1",
        hostId: "host-1",
        senderId: "watch-1",
        recipientId: "host-1",
        sentAt: 1_900,
        sequence: 1,
      },
      {
        kind: "request",
        body: {
          method: "POST",
          path: "/v1/transcribe?durationMs=1000",
          headers: {
            "content-type": "audio/mp4",
            "x-relay-body-encoding": "base64",
          },
          body: Buffer.from([0, 1, 2, 255]).toString("base64"),
        },
      },
      watchRoot,
    );

    await adapter.receive(incoming);
    assert.deepEqual(received, new Uint8Array([0, 1, 2, 255]));
  });

  it("assembles ordered encrypted voice chunks only on the Mac", async () => {
    const { watchRoot } = await fixture();
    let received = new Uint8Array();
    const adapter = new CloudTunnelAdapter({
      hostId: "host-1",
      keyForDevice: async () => watchRoot,
      loadReplayState: async () => ({}),
      saveReplayState: async () => {},
      handler: async (request) => {
        received = new Uint8Array(await request.arrayBuffer());
        return Response.json({ transcript: "chunked hello" });
      },
      now: () => 2_000,
    });
    const chunk = async (index: number, data: Uint8Array) =>
      encryptRelayEnvelope(
        {
          version: 1,
          messageId: `voice-${index}`,
          accountId: "account-1",
          hostId: "host-1",
          senderId: "watch-1",
          recipientId: "host-1",
          sentAt: 1_900,
          sequence: index + 1,
        },
        {
          kind: "voice",
          body: {
            transferId: "transfer-1",
            index,
            totalChunks: 2,
            recordedAtMs: index * 1_000,
            durationMs: 1_000,
            method: "POST",
            path: "/v1/transcribe?durationMs=1000",
            headers: {
              "content-type": "audio/mp4",
              "x-relay-device": "watch-1",
              "x-relay-signature": "signed-full-audio",
            },
            data: Buffer.from(data).toString("base64"),
          },
        },
        watchRoot,
      );

    assert.equal(await adapter.receive(await chunk(0, new Uint8Array([1, 2]))), null);
    const response = await adapter.receive(
      await chunk(1, new Uint8Array([3, 4, 5])),
    );
    assert.ok(response);
    assert.deepEqual(received, new Uint8Array([1, 2, 3, 4, 5]));
    assert.equal(
      (await decryptRelayEnvelope(response, watchRoot)).kind,
      "response",
    );
  });

  it("rejects out-of-order voice chunks and keeps no partial action", async () => {
    const { watchRoot } = await fixture();
    const adapter = new CloudTunnelAdapter({
      hostId: "host-1",
      keyForDevice: async () => watchRoot,
      loadReplayState: async () => ({}),
      saveReplayState: async () => {},
      handler: async () => Response.json({ ok: true }),
      now: () => 2_000,
    });
    const invalid = await encryptRelayEnvelope(
      {
        version: 1,
        messageId: "voice-1",
        accountId: "account-1",
        hostId: "host-1",
        senderId: "watch-1",
        recipientId: "host-1",
        sentAt: 1_900,
        sequence: 1,
      },
      {
        kind: "voice",
        body: {
          transferId: "transfer-1",
          index: 1,
          totalChunks: 2,
          recordedAtMs: 1_000,
          durationMs: 1_000,
          method: "POST",
          path: "/v1/transcribe?durationMs=1000",
          headers: { "content-type": "audio/mp4" },
          data: Buffer.from([1]).toString("base64"),
        },
      },
      watchRoot,
    );

    await assert.rejects(adapter.receive(invalid), /voice chunk order/i);
    assert.equal(adapter.pendingVoiceTransferCount, 0);
    assert.equal(adapter.queuedActionCount, 0);
  });

  it("clears partial voice and persisted device sequences on removal and close", async () => {
    const { watchRoot } = await fixture();
    let replay = { "watch-1": 1, "watch-2": 2 };
    let outgoing = { "watch-1": 3, "watch-2": 4 };
    const adapter = new CloudTunnelAdapter({
      hostId: "host-1",
      keyForDevice: async () => watchRoot,
      loadReplayState: async () => replay,
      saveReplayState: async (state) => {
        replay = state as typeof replay;
      },
      loadOutgoingSequences: async () => outgoing,
      saveOutgoingSequences: async (state) => {
        outgoing = state as typeof outgoing;
      },
      handler: async () => Response.json({ ok: true }),
      now: () => 2_000,
    });
    const firstChunk = await encryptRelayEnvelope(
      {
        version: 1,
        messageId: "voice-partial",
        accountId: "account-1",
        hostId: "host-1",
        senderId: "watch-1",
        recipientId: "host-1",
        sentAt: 1_900,
        sequence: 2,
      },
      {
        kind: "voice",
        body: {
          transferId: "partial-transfer",
          index: 0,
          totalChunks: 2,
          recordedAtMs: 0,
          durationMs: 1_000,
          method: "POST",
          path: "/v1/transcribe?durationMs=1000",
          headers: { "content-type": "audio/mp4" },
          data: Buffer.from([1]).toString("base64"),
        },
      },
      watchRoot,
    );

    assert.equal(await adapter.receive(firstChunk), null);
    assert.equal(adapter.pendingVoiceTransferCount, 1);
    await adapter.removeDevice("watch-1");
    assert.equal(adapter.pendingVoiceTransferCount, 0);
    assert.deepEqual(replay, { "watch-2": 2 });
    assert.deepEqual(outgoing, { "watch-2": 4 });
    await adapter.close();
    assert.equal(adapter.pendingVoiceTransferCount, 0);
  });

  it("persists replay state and rejects duplicate delivery after restart", async () => {
    const { watchRoot } = await fixture();
    let persisted: Record<string, number> = {};
    const options = {
      hostId: "host-1",
      keyForDevice: async () => watchRoot,
      loadReplayState: async () => persisted,
      saveReplayState: async (state: Record<string, number>) => {
        persisted = state;
      },
      handler: async () => Response.json({ ok: true }),
      now: () => 2_000,
    };
    const incoming = await encryptRelayEnvelope(
      {
        version: 1,
        messageId: "request-1",
        accountId: "account-1",
        hostId: "host-1",
        senderId: "watch-1",
        recipientId: "host-1",
        sentAt: 1_900,
        sequence: 9,
      },
      {
        kind: "request",
        body: { method: "GET", path: "/v1/tasks", headers: {}, body: "" },
      },
      watchRoot,
    );
    await new CloudTunnelAdapter(options).receive(incoming);
    await assert.rejects(
      new CloudTunnelAdapter(options).receive(incoming),
      /replay/i,
    );
  });

  it("persists host response sequence across bridge restarts", async () => {
    const { watchRoot } = await fixture();
    let replay: Record<string, number> = {};
    let outgoing: Record<string, number> = {};
    const options = {
      hostId: "host-1",
      keyForDevice: async () => watchRoot,
      loadReplayState: async () => replay,
      saveReplayState: async (state: Record<string, number>) => {
        replay = state;
      },
      loadOutgoingSequences: async () => outgoing,
      saveOutgoingSequences: async (state: Record<string, number>) => {
        outgoing = state;
      },
      handler: async () => Response.json({ ok: true }),
      now: () => 2_000,
    };
    const request = async (sequence: number) => encryptRelayEnvelope(
      {
        version: 1,
        messageId: `request-${sequence}`,
        accountId: "account-1",
        hostId: "host-1",
        senderId: "watch-1",
        recipientId: "host-1",
        sentAt: 1_900,
        sequence,
      },
      {
        kind: "request",
        body: { method: "GET", path: "/v1/tasks", headers: {}, body: "" },
      },
      watchRoot,
    );

    assert.equal(
      (await new CloudTunnelAdapter(options).receive(await request(1))).sequence,
      1,
    );
    assert.equal(
      (await new CloudTunnelAdapter(options).receive(await request(2))).sequence,
      2,
    );
  });

  it("encrypts pushed events with the same persisted host sequence", async () => {
    const { watchRoot } = await fixture();
    let outgoing: Record<string, number> = { "watch-1": 4 };
    const adapter = new CloudTunnelAdapter({
      hostId: "host-1",
      keyForDevice: async () => watchRoot,
      loadReplayState: async () => ({}),
      saveReplayState: async () => {},
      loadOutgoingSequences: async () => outgoing,
      saveOutgoingSequences: async (state) => {
        outgoing = state;
      },
      handler: async () => Response.json({ ok: true }),
      now: () => 2_000,
    });

    const pushed = await adapter.pushEvent({
      accountId: "account-1",
      deviceId: "watch-1",
      event: {
        id: 12,
        type: "task.updated",
        data: { threadId: "thread-1" },
        createdAt: 1_990,
      },
    });

    assert.equal(pushed.sequence, 5);
    assert.deepEqual(await decryptRelayEnvelope(pushed, watchRoot), {
      kind: "event",
      body: {
        id: 12,
        type: "task.updated",
        data: { threadId: "thread-1" },
        createdAt: 1_990,
      },
    });
  });

  it("rejects stale envelopes and never queues actions while disconnected", async () => {
    const { watchRoot } = await fixture();
    const adapter = new CloudTunnelAdapter({
      hostId: "host-1",
      keyForDevice: async () => watchRoot,
      loadReplayState: async () => ({}),
      saveReplayState: async () => {},
      handler: async () => Response.json({ ok: true }),
      now: () => 10 * 60_000,
    });
    const stale = await encryptRelayEnvelope(
      {
        version: 1,
        messageId: "old",
        accountId: "account-1",
        hostId: "host-1",
        senderId: "watch-1",
        recipientId: "host-1",
        sentAt: 1,
        sequence: 1,
      },
      {
        kind: "request",
        body: { method: "POST", path: "/v1/tasks", headers: {}, body: "{}" },
      },
      watchRoot,
    );
    await assert.rejects(adapter.receive(stale), /stale/i);
    assert.equal(adapter.queuedActionCount, 0);
  });
});
