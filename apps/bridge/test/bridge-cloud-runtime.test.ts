import assert from "node:assert/strict";
import { generateKeyPairSync, sign } from "node:crypto";
import { describe, it } from "node:test";
import {
  decryptRelayEnvelope,
  encryptRelayEnvelope,
} from "../../../packages/cloud-protocol/src/index.ts";
import { BridgeCloudRuntime } from "../src/cloud/bridge-cloud-runtime.ts";
import { EventHub } from "../src/events/event-hub.ts";
import { canonicalRequest } from "../src/security/authentication.ts";
import { InMemorySecurityStore } from "../src/security/store.ts";

describe("bridge cloud runtime", () => {
  it("restores an existing active cloud device with the same signing key", async () => {
    const signing = generateKeyPairSync("ec", { namedCurve: "prime256v1" });
    const signingPublicKey = signing.publicKey
      .export({ type: "spki", format: "pem" })
      .toString();
    const store = new InMemorySecurityStore();
    store.addDevice("watch-existing", signingPublicKey, "Original Watch", 123, {
      platform: "watch-os",
      manufacturer: "Apple",
      model: "Apple Watch",
      osVersion: "10",
      appVersion: "0.1.0",
      screenShape: "rounded-rect",
    });
    const runtime = new BridgeCloudRuntime({
      store,
      eventHub: new EventHub(),
      handler: async () => Response.json({ ok: true }),
    });

    await runtime.registerDevice({
      accountId: "account-1",
      hostId: "host-1",
      deviceId: "watch-existing",
      name: "Restored Watch",
      signingPublicKey,
      rootKey: Buffer.alloc(32, 1).toString("base64url"),
      metadata: {
        platform: "watch-os",
        manufacturer: "Apple",
        model: "Apple Watch Ultra",
        osVersion: "11",
        appVersion: "0.2.0",
        screenShape: "rounded-rect",
      },
    });

    assert.equal(store.getDevice("watch-existing")?.createdAt, 123);
    assert.equal(store.getDevice("watch-existing")?.publicKey, signingPublicKey);
    assert.equal(store.getDevice("watch-existing")?.revokedAt, null);
    await runtime.close();
  });

  it("rejects restoration of a revoked cloud device ID", async () => {
    const signing = generateKeyPairSync("ec", { namedCurve: "prime256v1" });
    const signingPublicKey = signing.publicKey
      .export({ type: "spki", format: "pem" })
      .toString();
    const store = new InMemorySecurityStore();
    store.addDevice("watch-revoked", signingPublicKey, "Apple Watch", 123);
    store.revokeDevice("watch-revoked", 456);
    const runtime = new BridgeCloudRuntime({
      store,
      eventHub: new EventHub(),
      handler: async () => Response.json({ ok: true }),
    });

    await assert.rejects(
      runtime.registerDevice({
        accountId: "account-1",
        hostId: "host-1",
        deviceId: "watch-revoked",
        name: "Apple Watch",
        signingPublicKey,
        rootKey: Buffer.alloc(32, 2).toString("base64url"),
        metadata: {
          platform: "watch-os",
          manufacturer: "Apple",
          model: "Apple Watch",
          osVersion: "10",
          appVersion: "0.2.0",
          screenShape: "rounded-rect",
        },
      }),
      /revoked/i,
    );
    assert.equal(store.getDevice("watch-revoked")?.revokedAt, 456);
    await runtime.close();
  });

  it("rejects a cloud device revoked while root-key import is in flight", async () => {
    const signing = generateKeyPairSync("ec", { namedCurve: "prime256v1" });
    const signingPublicKey = signing.publicKey
      .export({ type: "spki", format: "pem" })
      .toString();
    const rootKey = await crypto.subtle.importKey(
      "raw",
      new Uint8Array(32).fill(7),
      "AES-GCM",
      false,
      ["encrypt", "decrypt"],
    );
    let releaseImport!: () => void;
    const importGate = new Promise<void>((resolve) => {
      releaseImport = resolve;
    });
    const store = new InMemorySecurityStore();
    store.addDevice("watch-revoked-during-import", signingPublicKey, "Apple Watch", 123);
    const runtime = new BridgeCloudRuntime({
      store,
      eventHub: new EventHub(),
      handler: async () => Response.json({ ok: true }),
      importRootKey: async () => {
        await importGate;
        return rootKey;
      },
    });

    const restoring = runtime.registerDevice({
      accountId: "account-1",
      hostId: "host-1",
      deviceId: "watch-revoked-during-import",
      name: "Apple Watch",
      signingPublicKey,
      rootKey: Buffer.alloc(32, 7).toString("base64url"),
      metadata: {
        platform: "watch-os",
        manufacturer: "Apple",
        model: "Apple Watch",
        osVersion: "10",
        appVersion: "0.2.0",
        screenShape: "rounded-rect",
      },
    });
    await Promise.resolve();
    store.revokeDevice("watch-revoked-during-import", 789);
    releaseImport();

    await assert.rejects(restoring, /revoked/i);
    assert.equal(store.getDevice("watch-revoked-during-import")?.revokedAt, 789);
    await runtime.close();
  });

  it("rejects restoration when a cloud device signing key changes", async () => {
    const original = generateKeyPairSync("ec", { namedCurve: "prime256v1" });
    const replacement = generateKeyPairSync("ec", { namedCurve: "prime256v1" });
    const originalPublicKey = original.publicKey
      .export({ type: "spki", format: "pem" })
      .toString();
    const replacementPublicKey = replacement.publicKey
      .export({ type: "spki", format: "pem" })
      .toString();
    const store = new InMemorySecurityStore();
    store.addDevice("watch-mismatch", originalPublicKey, "Apple Watch", 123);
    const runtime = new BridgeCloudRuntime({
      store,
      eventHub: new EventHub(),
      handler: async () => Response.json({ ok: true }),
    });

    await assert.rejects(
      runtime.registerDevice({
        accountId: "account-1",
        hostId: "host-1",
        deviceId: "watch-mismatch",
        name: "Apple Watch",
        signingPublicKey: replacementPublicKey,
        rootKey: Buffer.alloc(32, 3).toString("base64url"),
        metadata: {
          platform: "watch-os",
          manufacturer: "Apple",
          model: "Apple Watch",
          osVersion: "10",
          appVersion: "0.2.0",
          screenShape: "rounded-rect",
        },
      }),
      /signing key/i,
    );
    assert.equal(store.getDevice("watch-mismatch")?.publicKey, originalPublicKey);
    await runtime.close();
  });

  it("cannot resurrect a registration while close is waiting on key import", async () => {
    const rootKey = await crypto.subtle.importKey(
      "raw",
      new Uint8Array(32).fill(4),
      "AES-GCM",
      false,
      ["encrypt", "decrypt"],
    );
    let releaseImport!: () => void;
    let importCalls = 0;
    const importGate = new Promise<void>((resolve) => {
      releaseImport = resolve;
    });
    const store = new InMemorySecurityStore();
    const runtime = new BridgeCloudRuntime({
      store,
      eventHub: new EventHub(),
      handler: async () => Response.json({ ok: true }),
      importRootKey: async () => {
        importCalls += 1;
        await importGate;
        return rootKey;
      },
    });
    const signing = generateKeyPairSync("ec", { namedCurve: "prime256v1" });
    const registering = runtime.registerDevice({
      accountId: "account-1",
      hostId: "host-1",
      deviceId: "watch-racing-close",
      name: "Apple Watch",
      signingPublicKey: signing.publicKey
        .export({ type: "spki", format: "pem" })
        .toString(),
      rootKey: Buffer.alloc(32, 4).toString("base64url"),
      metadata: {
        platform: "watch-os",
        manufacturer: "Apple",
        model: "Apple Watch",
        osVersion: "10",
        appVersion: "0.2.0",
        screenShape: "rounded-rect",
      },
    });
    await Promise.resolve();
    assert.equal(importCalls, 1);
    const closing = runtime.close();
    releaseImport();

    await assert.rejects(registering, /closed/i);
    await closing;
    assert.equal(store.getDevice("watch-racing-close"), undefined);
  });

  it("serializes device removal after an in-flight registration", async () => {
    const rootKey = await crypto.subtle.importKey(
      "raw",
      new Uint8Array(32).fill(5),
      "AES-GCM",
      false,
      ["encrypt", "decrypt"],
    );
    let releaseImport!: () => void;
    let importCalls = 0;
    const importGate = new Promise<void>((resolve) => {
      releaseImport = resolve;
    });
    const store = new InMemorySecurityStore();
    const runtime = new BridgeCloudRuntime({
      store,
      eventHub: new EventHub(),
      handler: async () => Response.json({ ok: true }),
      importRootKey: async () => {
        importCalls += 1;
        await importGate;
        return rootKey;
      },
    });
    const signing = generateKeyPairSync("ec", { namedCurve: "prime256v1" });
    const registering = runtime.registerDevice({
      accountId: "account-1",
      hostId: "host-1",
      deviceId: "watch-racing-remove",
      name: "Apple Watch",
      signingPublicKey: signing.publicKey
        .export({ type: "spki", format: "pem" })
        .toString(),
      rootKey: Buffer.alloc(32, 5).toString("base64url"),
      metadata: {
        platform: "watch-os",
        manufacturer: "Apple",
        model: "Apple Watch",
        osVersion: "10",
        appVersion: "0.2.0",
        screenShape: "rounded-rect",
      },
    });
    await Promise.resolve();
    assert.equal(importCalls, 1);
    const removing = runtime.removeDevice("watch-racing-remove");
    releaseImport();

    await registering;
    await removing;
    assert.notEqual(store.getDevice("watch-racing-remove")?.revokedAt, null);
    const removedEnvelope = await encryptRelayEnvelope(
      {
        version: 1,
        messageId: "removed-racing-request",
        accountId: "account-1",
        hostId: "host-1",
        senderId: "watch-racing-remove",
        recipientId: "host-1",
        sentAt: Date.now(),
        sequence: 1,
      },
      {
        kind: "request",
        body: { method: "GET", path: "/v1/tasks", headers: {}, body: "" },
      },
      rootKey,
    );
    await assert.rejects(runtime.receive(removedEnvelope), /unknown/i);
    await runtime.close();
  });

  it("rejects an AES-128 CryptoKey registration", async () => {
    const rootKey = await crypto.subtle.importKey(
      "raw",
      new Uint8Array(16).fill(6),
      "AES-GCM",
      false,
      ["encrypt", "decrypt"],
    );
    const runtime = new BridgeCloudRuntime({
      store: new InMemorySecurityStore(),
      eventHub: new EventHub(),
      handler: async () => Response.json({ ok: true }),
    });
    const signing = generateKeyPairSync("ec", { namedCurve: "prime256v1" });
    await assert.rejects(
      runtime.registerDevice({
        accountId: "account-1",
        hostId: "host-1",
        deviceId: "watch-aes-128",
        name: "Apple Watch",
        signingPublicKey: signing.publicKey
          .export({ type: "spki", format: "pem" })
          .toString(),
        rootKey,
        metadata: {
          platform: "watch-os",
          manufacturer: "Apple",
          model: "Apple Watch",
          osVersion: "10",
          appVersion: "0.2.0",
          screenShape: "rounded-rect",
        },
      }),
      /root key/i,
    );
    await runtime.close();
  });

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
    const eventHub = new EventHub();
    const runtime = new BridgeCloudRuntime({
      store,
      eventHub,
      handler: async () => Response.json({ data: [{ id: "task-1" }] }),
      now: () => 2_000,
    });
    await runtime.registerDevice({
      accountId: "account-1",
      hostId: "host-1",
      deviceId: "watch-1",
      name: "Apple Watch",
      signingPublicKey: signing.publicKey
        .export({ type: "spki", format: "pem" })
        .toString(),
      rootKey: Buffer.from(rootBytes).toString("base64url"),
      metadata: {
        platform: "watch-os",
        manufacturer: "Apple",
        model: "Apple Watch",
        osVersion: "10",
        appVersion: "0.2.0",
        screenShape: "rounded-rect",
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

    await runtime.receive(envelope);
    assert.equal(store.getDevice("watch-1")?.metadata?.model, "Apple Watch");
    const [response] = await runtime.drainEvents();
    assert.ok(response);
    const inner = await decryptRelayEnvelope(response, rootKey);
    assert.equal(inner.kind, "response");
    assert.equal((inner.body as { status: number }).status, 200);

    eventHub.publish("task.updated", { threadId: "thread-1" });
    const [eventEnvelope] = await runtime.drainEvents();
    assert.ok(eventEnvelope);
    assert.equal(eventEnvelope.recipientId, "watch-1");
    const pushed = await decryptRelayEnvelope(eventEnvelope, rootKey);
    assert.equal(pushed.kind, "event");
    assert.equal((pushed.body as { type: string }).type, "task.updated");
    assert.equal(eventEnvelope.sequence, response.sequence + 1);
  });

  it("removes revoked device material and closes all runtime-owned state", async () => {
    const rootBytes = new Uint8Array(32).fill(8);
    const rootKey = await crypto.subtle.importKey(
      "raw",
      rootBytes,
      "AES-GCM",
      false,
      ["encrypt", "decrypt"],
    );
    const signing = generateKeyPairSync("ec", { namedCurve: "prime256v1" });
    const store = new InMemorySecurityStore();
    const eventHub = new EventHub();
    const runtime = new BridgeCloudRuntime({
      store,
      eventHub,
      handler: async () => Response.json({ ok: true }),
      now: () => 2_000,
    });
    await runtime.registerDevice({
      accountId: "account-1",
      hostId: "host-1",
      deviceId: "watch-1",
      name: "Apple Watch",
      signingPublicKey: signing.publicKey
        .export({ type: "spki", format: "pem" })
        .toString(),
      rootKey: Buffer.from(rootBytes).toString("base64url"),
      metadata: {
        platform: "watch-os",
        manufacturer: "Apple",
        model: "Apple Watch",
        osVersion: "10",
        appVersion: "0.2.0",
        screenShape: "rounded-rect",
      },
    });
    eventHub.publish("task.updated", { threadId: "task-1" });

    await runtime.removeDevice("watch-1");
    assert.notEqual(store.getDevice("watch-1")?.revokedAt, null);
    assert.deepEqual(await runtime.drainEvents(), []);

    const removedEnvelope = await encryptRelayEnvelope(
      {
        version: 1,
        messageId: "removed-request",
        accountId: "account-1",
        hostId: "host-1",
        senderId: "watch-1",
        recipientId: "host-1",
        sentAt: 1_900,
        sequence: 1,
      },
      {
        kind: "request",
        body: { method: "GET", path: "/v1/tasks", headers: {}, body: "" },
      },
      rootKey,
    );
    await assert.rejects(runtime.receive(removedEnvelope), /unknown/i);

    await runtime.close();
    eventHub.publish("task.updated", { threadId: "task-2" });
    assert.deepEqual(await runtime.drainEvents(), []);
    await assert.rejects(runtime.receive(removedEnvelope), /closed/i);
  });
});
