import assert from "node:assert/strict";
import { generateKeyPairSync } from "node:crypto";
import { mkdtemp, realpath, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { describe, it } from "node:test";
import {
  assertLoopbackAdminHost,
  createAdminRequestHandler,
} from "../src/admin/admin-server.ts";
import { InMemorySecurityStore } from "../src/security/store.ts";
import { WorkspacePolicy } from "../src/workspaces/workspace-policy.ts";

const ADMIN_TOKEN = "relay-admin-token-that-is-at-least-32-bytes-long";

function authorized(path: string, init: RequestInit = {}) {
  return new Request(`http://127.0.0.1${path}`, {
    ...init,
    headers: {
      authorization: `Bearer ${ADMIN_TOKEN}`,
      ...init.headers,
    },
  });
}

function createOptions() {
  const store = new InMemorySecurityStore();
  const { publicKey } = generateKeyPairSync("ed25519");
  store.addDevice(
    "watch-1",
    publicKey.export({ type: "spki", format: "pem" }).toString(),
    "Galaxy Watch6",
    123,
  );
  const workspacePolicy = new WorkspacePolicy([]);
  let stopped = false;
  return {
    store,
    workspacePolicy,
    options: {
      token: ADMIN_TOKEN,
      store,
      workspacePolicy,
      adminBindHost: "127.0.0.1",
      watchBindHost: "127.0.0.1",
      watchPort: 43117,
      codexStatus: () => "ready" as const,
      voiceConfigured: true,
      shutdown: () => {
        stopped = true;
      },
    },
    wasStopped: () => stopped,
  };
}

describe("admin server", () => {
  it("returns a generic 401 without the 256-bit bearer token", async () => {
    const { options } = createOptions();
    const handler = createAdminRequestHandler(options);

    for (const authorization of [undefined, "Bearer wrong"]) {
      const response = await handler(
        new Request("http://127.0.0.1/v1/status", {
          headers: authorization ? { authorization } : {},
        }),
      );
      assert.equal(response.status, 401);
      assert.deepEqual(await response.json(), { error: "unauthorized" });
    }
    assert.throws(
      () => createAdminRequestHandler({ ...options, token: "too-short" }),
      /256-bit/,
    );
  });

  it("refuses every non-loopback admin bind address", () => {
    assert.doesNotThrow(() => assertLoopbackAdminHost("127.0.0.1"));
    assert.doesNotThrow(() => assertLoopbackAdminHost("::1"));
    for (const host of ["0.0.0.0", "::", "192.168.1.2", "relay.local"]) {
      assert.throws(() => assertLoopbackAdminHost(host), /loopback/);
    }
  });

  it("never reports a passing self-test for a non-loopback configuration", async () => {
    const { options } = createOptions();
    const handler = createAdminRequestHandler({
      ...options,
      adminBindHost: "0.0.0.0",
    });
    const response = await handler(
      authorized("/v1/security/self-test", { method: "POST" }),
    );
    assert.deepEqual(await response.json(), {
      ok: false,
      checks: {
        adminLoopbackOnly: false,
        watchLoopbackOnly: true,
        strongAdminToken: true,
      },
    });
  });

  it("provides focused operations without returning stored secrets", async () => {
    const { options, wasStopped } = createOptions();
    const handler = createAdminRequestHandler(options);

    const status = await (await handler(authorized("/v1/status"))).json();
    assert.deepEqual(status, {
      bridge: "running",
      codex: "ready",
      watch: { host: "127.0.0.1", port: 43117 },
      activeDevices: 1,
    });

    const devices = await (await handler(authorized("/v1/devices"))).json();
    assert.equal(devices.devices[0].name, "Galaxy Watch6");
    assert.equal("publicKey" in devices.devices[0], false);
    assert.equal(JSON.stringify(devices).includes("BEGIN PUBLIC KEY"), false);

    const voice = await (await handler(authorized("/v1/voice"))).json();
    assert.deepEqual(voice, { configured: true, provider: "openai" });
    assert.equal(JSON.stringify(voice).includes("apiKey"), false);

    const pairing = await (
      await handler(authorized("/v1/pairing-code", { method: "POST" }))
    ).json();
    assert.match(pairing.code, /^[A-Z2-9]{6}$/);
    assert.equal(typeof pairing.expiresAt, "number");

    const selfTest = await (
      await handler(authorized("/v1/security/self-test", { method: "POST" }))
    ).json();
    assert.equal(selfTest.ok, true);
    assert.deepEqual(selfTest.checks, {
      adminLoopbackOnly: true,
      watchLoopbackOnly: true,
      strongAdminToken: true,
    });

    const revoked = await handler(
      authorized("/v1/devices/watch-1/revoke", { method: "POST" }),
    );
    assert.equal(revoked.status, 200);
    assert.notEqual(options.store.getDevice("watch-1")?.revokedAt, null);

    const shutdown = await handler(
      authorized("/v1/shutdown", { method: "POST" }),
    );
    assert.equal(shutdown.status, 202);
    await new Promise((resolve) => setImmediate(resolve));
    assert.equal(wasStopped(), true);
  });

  it("replaces and reports only canonical approved workspace roots", async (context) => {
    const temporary = await mkdtemp(join(tmpdir(), "relay-admin-workspaces-"));
    context.after(() => rm(temporary, { recursive: true, force: true }));
    const canonical = await realpath(temporary);
    const { options } = createOptions();
    const handler = createAdminRequestHandler(options);

    const update = await handler(
      authorized("/v1/workspaces", {
        method: "PUT",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ roots: [temporary] }),
      }),
    );
    assert.equal(update.status, 200);
    assert.deepEqual(await update.json(), { roots: [canonical] });

    const read = await handler(authorized("/v1/workspaces"));
    assert.equal(read.status, 200);
    assert.deepEqual(await read.json(), { roots: [canonical] });
  });

  it("accepts cloud keys and drains encrypted events only through authenticated loopback admin", async () => {
    const { options } = createOptions();
    const registrations: unknown[] = [];
    const envelopes: unknown[] = [];
    const handler = createAdminRequestHandler({
      ...options,
      cloudRuntime: {
        registerDevice: async (input) => {
          registrations.push(input);
        },
        receive: async (envelope) => {
          envelopes.push(envelope);
        },
        drainEvents: async () => [
          {
            version: 1,
            messageId: "event-1",
            accountId: "account-1",
            hostId: "host-1",
            senderId: "host-1",
            recipientId: "watch-1",
            sentAt: 1_000,
            sequence: 3,
            nonce: "nonce",
            ciphertext: "ciphertext",
          },
        ],
      },
    });

    const registration = await handler(
      authorized("/v1/cloud/devices", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({
          accountId: "account-1",
          hostId: "host-1",
          deviceId: "watch-1",
          name: "Galaxy Watch6",
          signingPublicKey: "watch-signing-key",
          rootKey: Buffer.alloc(32, 7).toString("base64url"),
          metadata: {
            platform: "wear-os",
            manufacturer: "Samsung",
            model: "Watch6",
            osVersion: "5",
            appVersion: "1",
            screenShape: "round",
          },
        }),
      }),
    );
    assert.equal(registration.status, 200);
    assert.deepEqual(await registration.json(), { ok: true });
    assert.equal(registrations.length, 1);

    const events = await handler(authorized("/v1/cloud/events"));
    assert.equal(events.status, 200);
    assert.equal((await events.json()).envelopes[0].messageId, "event-1");

    const envelope = {
      version: 1,
      messageId: "message-1",
      accountId: "account-1",
      hostId: "host-1",
      senderId: "watch-1",
      recipientId: "host-1",
      sentAt: Date.now(),
      sequence: 1,
      nonce: "nonce",
      ciphertext: "ciphertext",
    };
    const processed = await handler(
      authorized("/v1/cloud/envelopes", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify(envelope),
      }),
    );
    assert.equal(processed.status, 200);
    assert.deepEqual(await processed.json(), { ok: true });
    assert.equal(envelopes.length, 1);
  });
});
