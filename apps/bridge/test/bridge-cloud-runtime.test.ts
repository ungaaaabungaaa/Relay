import assert from "node:assert/strict";
import { generateKeyPairSync, sign } from "node:crypto";
import { describe, it } from "node:test";
import {
  decryptRelayEnvelope,
  encryptRelayEnvelope,
} from "../../../packages/cloud-protocol/src/index.ts";
import { BridgeCloudRuntime } from "../src/cloud/bridge-cloud-runtime.ts";
import { canonicalRequest } from "../src/security/authentication.ts";
import { InMemorySecurityStore } from "../src/security/store.ts";

describe("bridge cloud runtime", () => {
  it("registers an approved watch in memory and processes its encrypted request", async () => {
    const rootBytes = new Uint8Array(32).fill(9);
    const rootKey = await crypto.subtle.importKey(
      "raw",
      rootBytes,
      "AES-GCM",
      false,
      ["encrypt", "decrypt"],
    );
    const signing = generateKeyPairSync("ec", { namedCurve: "prime256v1" });
    const store = new InMemorySecurityStore();
    const runtime = new BridgeCloudRuntime({
      store,
      handler: async () => Response.json({ data: [{ id: "task-1" }] }),
      now: () => 2_000,
    });
    await runtime.registerDevice({
      hostId: "host-1",
      deviceId: "watch-1",
      name: "Watch6",
      signingPublicKey: signing.publicKey
        .export({ type: "spki", format: "pem" })
        .toString(),
      rootKey: Buffer.from(rootBytes).toString("base64url"),
      metadata: {
        platform: "wear-os",
        manufacturer: "Samsung",
        model: "Watch6",
        osVersion: "5",
        appVersion: "1",
        screenShape: "round",
      },
    });

    const timestamp = Date.now();
    const signed = {
      deviceId: "watch-1",
      method: "GET",
      path: "/v1/tasks",
      body: new Uint8Array(),
      timestamp,
      nonce: "cloud-runtime-nonce",
    };
    const signature = sign(
      "sha256",
      Buffer.from(canonicalRequest(signed)),
      signing.privateKey,
    ).toString("base64");
    const envelope = await encryptRelayEnvelope(
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
          headers: {
            "x-relay-device": "watch-1",
            "x-relay-timestamp": String(timestamp),
            "x-relay-nonce": signed.nonce,
            "x-relay-signature": signature,
          },
          body: "",
        },
      },
      rootKey,
    );

    const response = await runtime.receive(envelope);
    assert.equal(store.getDevice("watch-1")?.metadata?.model, "Watch6");
    const inner = await decryptRelayEnvelope(response, rootKey);
    assert.equal(inner.kind, "response");
    assert.equal((inner.body as { status: number }).status, 200);
  });
});
