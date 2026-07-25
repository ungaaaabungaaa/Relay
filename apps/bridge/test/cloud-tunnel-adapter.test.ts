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
