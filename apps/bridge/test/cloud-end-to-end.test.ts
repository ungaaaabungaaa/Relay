import assert from "node:assert/strict";
import { generateKeyPairSync, sign } from "node:crypto";
import { describe, it } from "node:test";
import {
  decryptRelayEnvelope,
  deriveRelayRootKey,
  encryptRelayEnvelope,
  generateAgreementKeyPair,
  type RelayTunnelEnvelope,
} from "../../../packages/cloud-protocol/src/index.ts";
import { HibernatingTunnelRouter } from "../../cloud/src/tunnel-router.ts";
import { CloudTunnelAdapter } from "../src/cloud/cloud-tunnel-adapter.ts";
import { canonicalRequest } from "../src/security/authentication.ts";
import { InMemorySecurityStore } from "../src/security/store.ts";
import { createRequestHandler } from "../src/server.ts";
import { WorkspacePolicy } from "../src/workspaces/workspace-policy.ts";

class TestSocket {
  readonly messages: string[] = [];

  send(message: string) {
    this.messages.push(message);
  }

  close() {}
}

describe("encrypted watch-to-Codex path", () => {
  it("routes ciphertext through cloud and authorizes only after Mac decryption", async () => {
    const macAgreement = await generateAgreementKeyPair();
    const watchAgreement = await generateAgreementKeyPair();
    const pairingNonce = new Uint8Array(32).fill(8);
    const macRoot = await deriveRelayRootKey(
      macAgreement.privateKey,
      watchAgreement.publicKey,
      pairingNonce,
    );
    const watchRoot = await deriveRelayRootKey(
      watchAgreement.privateKey,
      macAgreement.publicKey,
      pairingNonce,
    );
    const signing = generateKeyPairSync("ec", { namedCurve: "prime256v1" });
    const store = new InMemorySecurityStore();
    store.addDevice(
      "watch-1",
      signing.publicKey.export({ type: "spki", format: "pem" }).toString(),
    );
    const handler = createRequestHandler({
      store,
      adapter: {
        listTasks: async () => ({
          data: [{ id: "task-1", title: "Build Relay" }],
          nextCursor: null,
        }),
        readTask: async () => ({}),
        listModels: async () => [],
        approvals: () => [],
        questions: () => [],
      },
      workspacePolicy: new WorkspacePolicy([]),
    });
    const bridge = new CloudTunnelAdapter({
      hostId: "host-1",
      keyForDevice: async () => macRoot,
      loadReplayState: async () => ({}),
      saveReplayState: async () => {},
      handler,
      now: () => 10_000,
    });

    const timestamp = Date.now();
    const signed = {
      deviceId: "watch-1",
      method: "GET",
      path: "/v1/tasks",
      body: new Uint8Array(),
      timestamp,
      nonce: "watch-request-nonce-1",
    };
    const signature = sign(
      "sha256",
      Buffer.from(canonicalRequest(signed)),
      signing.privateKey,
    ).toString("base64");
    const requestEnvelope = await encryptRelayEnvelope(
      {
        version: 1,
        messageId: "request-1",
        accountId: "account-1",
        hostId: "host-1",
        senderId: "watch-1",
        recipientId: "host-1",
        sentAt: 9_900,
        sequence: 1,
      },
      {
        kind: "request",
        body: {
          method: "GET",
          path: "/v1/tasks",
          headers: {
            "x-relay-device": "watch-1",
            "x-relay-timestamp": String(timestamp),
            "x-relay-nonce": signed.nonce,
            "x-relay-signature": signature,
          },
          body: "",
        },
      },
      watchRoot,
    );

    const cloud = new HibernatingTunnelRouter();
    const hostSocket = new TestSocket();
    const watchSocket = new TestSocket();
    cloud.connect(
      {
        accountId: "account-1",
        hostId: "host-1",
        peerId: "host-1",
        role: "host",
      },
      hostSocket,
    );
    cloud.connect(
      {
        accountId: "account-1",
        hostId: "host-1",
        peerId: "watch-1",
        role: "device",
      },
      watchSocket,
    );

    assert.equal(cloud.route(requestEnvelope), "delivered");
    const cloudDelivered = JSON.parse(
      hostSocket.messages[0]!,
    ) as RelayTunnelEnvelope;
    assert.equal(cloudDelivered.ciphertext, requestEnvelope.ciphertext);

    const responseEnvelope = await bridge.receive(cloudDelivered);
    assert.equal(cloud.route(responseEnvelope), "delivered");
    const watchResponse = JSON.parse(
      watchSocket.messages[0]!,
    ) as RelayTunnelEnvelope;
    const decrypted = await decryptRelayEnvelope(watchResponse, watchRoot);
    assert.equal(decrypted.kind, "response");
    const response = decrypted.body as {
      status: number;
      body: string;
    };
    assert.equal(response.status, 200);
    assert.deepEqual(JSON.parse(response.body), {
      data: [{ id: "task-1", title: "Build Relay" }],
      nextCursor: null,
    });
  });
});
