import assert from "node:assert/strict";
import { generateKeyPairSync } from "node:crypto";
import { it } from "node:test";
import { createAdminRequestHandler } from "../src/admin/admin-server.ts";
import { PairingSessionService } from "../src/security/pairing-session.ts";
import { InMemorySecurityStore } from "../src/security/store.ts";
import { createRequestHandler } from "../src/server.ts";
import { WorkspacePolicy } from "../src/workspaces/workspace-policy.ts";

const ADMIN_TOKEN = "relay-admin-token-that-is-at-least-32-bytes-long";

function authorized(path: string, init: RequestInit = {}) {
  return new Request(`http://127.0.0.1${path}`, {
    ...init,
    headers: {
      authorization: `Bearer ${ADMIN_TOKEN}`,
      "content-type": "application/json",
      ...init.headers,
    },
  });
}

it("exposes pairing metadata only through a token and activates only after admin approval", async () => {
  const store = new InMemorySecurityStore();
  const pairingSessions = new PairingSessionService(store, {
    now: () => 10_000,
  });
  const workspacePolicy = new WorkspacePolicy([]);
  const admin = createAdminRequestHandler({
    token: ADMIN_TOKEN,
    store,
    pairingSessions,
    workspacePolicy,
    adminBindHost: "127.0.0.1",
    watchBindHost: "127.0.0.1",
    watchPort: 43117,
    codexStatus: () => "ready",
    voiceConfigured: false,
    shutdown: () => {},
  });
  const watch = createRequestHandler({
    store,
    pairingSessions,
    pairingSource: () => "198.51.100.10",
    adapter: {
      listTasks: async () => ({ data: [], nextCursor: null }),
      readTask: async () => ({}),
      listModels: async () => [],
      approvals: () => [],
      questions: () => [],
    },
    workspacePolicy,
  });

  const createdResponse = await admin(
    authorized("/v1/pairing-sessions", {
      method: "POST",
      body: JSON.stringify({
        origin: "https://relay.example.ts.net",
        macName: "Studio Mac",
        macFingerprint: "ABCD:1234",
      }),
    }),
  );
  assert.equal(createdResponse.status, 201);
  const created = await createdResponse.json();
  assert.match(created.code, /^[A-Z2-9]{6}$/);
  assert.match(created.discoveryToken, /^[a-f0-9]{32}$/);

  const hidden = await watch(
    new Request("https://relay.example.ts.net/v1/pairing-sessions/wrong"),
  );
  assert.equal(hidden.status, 404);
  assert.deepEqual(await hidden.json(), { error: "not found" });

  const discovered = await watch(
    new Request(
      `https://relay.example.ts.net/v1/pairing-sessions/${created.discoveryToken}`,
    ),
  );
  assert.equal(discovered.status, 200);
  assert.deepEqual(await discovered.json(), {
    macName: "Studio Mac",
    macFingerprint: "ABCD:1234",
    apiVersion: 1,
    expiresAt: 310_000,
  });

  const { publicKey } = generateKeyPairSync("ec", {
    namedCurve: "prime256v1",
  });
  const submitted = await watch(
    new Request(
      `https://relay.example.ts.net/v1/pairing-sessions/${created.discoveryToken}`,
      {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({
          code: created.code,
          name: "Pixel Watch",
          publicKey: publicKey.export({
            type: "spki",
            format: "pem",
          }).toString(),
          metadata: {
            platform: "wear-os",
            manufacturer: "Google",
            model: "Pixel Watch",
            osVersion: "4",
            appVersion: "0.2.0",
            screenShape: "round",
          },
        }),
      },
    ),
  );
  assert.equal(submitted.status, 202);
  const pending = await submitted.json();

  const pendingStatus = await watch(
    new Request(
      `https://relay.example.ts.net/v1/pairing-sessions/${created.discoveryToken}/status?pollToken=${pending.pollToken}`,
    ),
  );
  assert.deepEqual(await pendingStatus.json(), { state: "pending" });

  const pendingAdmin = await admin(
    authorized("/v1/pairing-sessions/pending"),
  );
  const pendingDevices = (await pendingAdmin.json()).pairings;
  assert.equal(pendingDevices[0].id, pending.pairingId);
  assert.equal(pendingDevices[0].metadata.model, "Pixel Watch");
  assert.equal("publicKey" in pendingDevices[0], false);

  const approval = await admin(
    authorized(`/v1/pairing-sessions/${pending.pairingId}/approve`, {
      method: "POST",
    }),
  );
  assert.equal(approval.status, 200);

  const approvedStatus = await watch(
    new Request(
      `https://relay.example.ts.net/v1/pairing-sessions/${created.discoveryToken}/status?pollToken=${pending.pollToken}`,
    ),
  );
  const approved = await approvedStatus.json();
  assert.equal(approved.state, "approved");
  assert.equal(approved.origin, "https://relay.example.ts.net");
  assert.equal(store.getDevice(approved.deviceId)?.metadata?.platform, "wear-os");
});
