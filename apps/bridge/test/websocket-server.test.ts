import assert from "node:assert/strict";
import { generateKeyPairSync, sign } from "node:crypto";
import { describe, it } from "node:test";
import WebSocket from "ws";
import { EventHub } from "../src/events/event-hub.ts";
import { canonicalRequest } from "../src/security/authentication.ts";
import { InMemorySecurityStore } from "../src/security/store.ts";
import { createRelayServer } from "../src/server.ts";
import { WorkspacePolicy } from "../src/workspaces/workspace-policy.ts";

const fakeAdapter = {
  listTasks: async () => ({ data: [], nextCursor: null }),
  readTask: async () => ({}),
  listModels: async () => [],
  approvals: () => [],
  questions: () => [],
};

describe("authenticated event WebSocket", () => {
  it("replays retained events and then delivers live events", async (context) => {
    const { publicKey, privateKey } = generateKeyPairSync("ed25519");
    const store = new InMemorySecurityStore();
    store.addDevice(
      "watch",
      publicKey.export({ type: "spki", format: "pem" }).toString(),
    );
    const events = new EventHub();
    events.publish("task.updated", { id: "one" });
    events.publish("task.updated", { id: "two" });
    const server = createRelayServer({
      store,
      adapter: fakeAdapter,
      workspacePolicy: new WorkspacePolicy([]),
      eventHub: events,
    });
    await listen(server);
    context.after(() => closeServer(server));
    const address = server.address();
    assert.ok(address && typeof address !== "string");

    const path = "/v1/events?after=0";
    const timestamp = Date.now();
    const nonce = "websocket-replay-nonce";
    const signature = sign(
      null,
      Buffer.from(
        canonicalRequest({
          deviceId: "watch",
          method: "GET",
          path,
          body: new Uint8Array(),
          timestamp,
          nonce,
        }),
      ),
      privateKey,
    ).toString("base64");
    const socket = new WebSocket(
      `ws://127.0.0.1:${address.port}${path}`,
      {
        headers: {
          "x-relay-device": "watch",
          "x-relay-timestamp": String(timestamp),
          "x-relay-nonce": nonce,
          "x-relay-signature": signature,
        },
      },
    );
    context.after(() => socket.close());

    const received = await new Promise<Array<{ id: number }>>(
      (resolve, reject) => {
        const messages: Array<{ id: number }> = [];
        const timer = setTimeout(
          () => reject(new Error("timed out waiting for WebSocket events")),
          2_000,
        );
        socket.on("error", reject);
        socket.on("message", (payload) => {
          messages.push(JSON.parse(payload.toString()) as { id: number });
          if (messages.length === 2) {
            events.publish("task.updated", { id: "three" });
          }
          if (messages.length === 3) {
            clearTimeout(timer);
            resolve(messages);
          }
        });
      },
    );

    assert.deepEqual(
      received.map((event) => event.id),
      [1, 2, 3],
    );
  });

  it("rejects an unauthenticated WebSocket before sending event data", async (context) => {
    const server = createRelayServer({
      store: new InMemorySecurityStore(),
      adapter: fakeAdapter,
      workspacePolicy: new WorkspacePolicy([]),
      eventHub: new EventHub(),
    });
    await listen(server);
    context.after(() => closeServer(server));
    const address = server.address();
    assert.ok(address && typeof address !== "string");

    const status = await new Promise<number>((resolve, reject) => {
      const socket = new WebSocket(
        `ws://127.0.0.1:${address.port}/v1/events?after=0`,
      );
      socket.on("unexpected-response", (_request, response) => {
        resolve(response.statusCode ?? 0);
      });
      socket.on("open", () => reject(new Error("unauthenticated socket opened")));
      socket.on("error", () => {});
    });

    assert.equal(status, 401);
  });

  it("rejects stale, replayed, and revoked signed upgrades", async (context) => {
    const { publicKey, privateKey } = generateKeyPairSync("ed25519");
    const store = new InMemorySecurityStore();
    store.addDevice(
      "watch",
      publicKey.export({ type: "spki", format: "pem" }).toString(),
    );
    const server = createRelayServer({
      store,
      adapter: fakeAdapter,
      workspacePolicy: new WorkspacePolicy([]),
      eventHub: new EventHub(),
    });
    await listen(server);
    context.after(() => closeServer(server));
    const address = server.address();
    assert.ok(address && typeof address !== "string");

    const path = "/v1/events?after=0";
    const baseUrl = `ws://127.0.0.1:${address.port}${path}`;
    const replayTimestamp = Date.now();
    const replayNonce = "websocket-replay-auth-nonce";
    const first = new WebSocket(baseUrl, {
      headers: signedHeaders(
        privateKey,
        path,
        replayTimestamp,
        replayNonce,
      ),
    });
    await new Promise<void>((resolve, reject) => {
      first.once("open", resolve);
      first.once("error", reject);
    });
    first.terminate();

    assert.equal(
      await rejectedStatus(
        new WebSocket(baseUrl, {
          headers: signedHeaders(
            privateKey,
            path,
            replayTimestamp,
            replayNonce,
          ),
        }),
      ),
      401,
    );
    assert.equal(
      await rejectedStatus(
        new WebSocket(baseUrl, {
          headers: signedHeaders(
            privateKey,
            path,
            Date.now() - 121_000,
            "websocket-stale-auth-nonce",
          ),
        }),
      ),
      401,
    );

    store.revokeDevice("watch");
    assert.equal(
      await rejectedStatus(
        new WebSocket(baseUrl, {
          headers: signedHeaders(
            privateKey,
            path,
            Date.now(),
            "websocket-revoked-auth-nonce",
          ),
        }),
      ),
      401,
    );
  });
});

function listen(server: ReturnType<typeof createRelayServer>) {
  return new Promise<void>((resolve, reject) => {
    server.once("error", reject);
    server.listen(0, "127.0.0.1", () => resolve());
  });
}

function closeServer(server: ReturnType<typeof createRelayServer>) {
  return new Promise<void>((resolve) => {
    server.close(() => resolve());
  });
}

function signedHeaders(
  privateKey: ReturnType<typeof generateKeyPairSync>["privateKey"],
  path: string,
  timestamp: number,
  nonce: string,
) {
  const signature = sign(
    null,
    Buffer.from(
      canonicalRequest({
        deviceId: "watch",
        method: "GET",
        path,
        body: new Uint8Array(),
        timestamp,
        nonce,
      }),
    ),
    privateKey,
  ).toString("base64");
  return {
    "x-relay-device": "watch",
    "x-relay-timestamp": String(timestamp),
    "x-relay-nonce": nonce,
    "x-relay-signature": signature,
  };
}

function rejectedStatus(socket: WebSocket) {
  return new Promise<number>((resolve, reject) => {
    socket.once("unexpected-response", (_request, response) => {
      response.resume();
      resolve(response.statusCode ?? 0);
    });
    socket.once("open", () => reject(new Error("rejected socket opened")));
    socket.once("error", () => {});
  });
}
