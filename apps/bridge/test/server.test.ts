import assert from "node:assert/strict";
import { generateKeyPairSync, sign } from "node:crypto";
import { describe, it } from "node:test";
import { canonicalRequest } from "../src/security/authentication.ts";
import { InMemorySecurityStore } from "../src/security/store.ts";
import { createRequestHandler } from "../src/server.ts";

const fakeAdapter = {
  listTasks: async () => ({ data: [{ id: "secret-task" }], nextCursor: null }),
  readTask: async () => ({}),
  listModels: async () => [],
  approvals: () => [],
  questions: () => [],
};

describe("bridge API", () => {
  it("returns a metadata-free health response", async () => {
    const handler = createRequestHandler({
      store: new InMemorySecurityStore(),
      adapter: fakeAdapter,
    });
    const response = await handler(new Request("http://localhost/health"));
    assert.equal(response.status, 200);
    assert.deepEqual(await response.json(), { ok: true, service: "relay" });
  });

  it("rejects unauthenticated task access", async () => {
    const handler = createRequestHandler({
      store: new InMemorySecurityStore(),
      adapter: fakeAdapter,
    });
    const response = await handler(new Request("http://localhost/v1/tasks"));
    assert.equal(response.status, 401);
    assert.deepEqual(await response.json(), { error: "unauthorized" });
  });

  it("returns tasks to a correctly signed device", async () => {
    const { publicKey, privateKey } = generateKeyPairSync("ed25519");
    const store = new InMemorySecurityStore();
    store.addDevice("watch", publicKey.export({ type: "spki", format: "pem" }).toString());
    const timestamp = Date.now();
    const signed = {
      deviceId: "watch",
      method: "GET",
      path: "/v1/tasks",
      body: new Uint8Array(),
      timestamp,
      nonce: "signed-nonce-1234",
    };
    const signature = sign(null, Buffer.from(canonicalRequest(signed)), privateKey).toString("base64");
    const handler = createRequestHandler({ store, adapter: fakeAdapter });
    const response = await handler(
      new Request("http://localhost/v1/tasks", {
        headers: {
          "x-relay-device": "watch",
          "x-relay-timestamp": String(timestamp),
          "x-relay-nonce": signed.nonce,
          "x-relay-signature": signature,
        },
      }),
    );
    assert.equal(response.status, 200);
    assert.equal((await response.json()).data[0].id, "secret-task");
  });
});
