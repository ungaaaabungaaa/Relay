import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { readFile } from "node:fs/promises";
import { DatabaseSync } from "node:sqlite";
import { describe, it } from "node:test";
import { emailLookupHash } from "../src/auth.ts";
import { D1CommandGateway } from "../src/d1-gateway.ts";
import { D1CloudRepository } from "../src/d1-repository.ts";
import { createWorker } from "../src/worker.ts";

const jwtSecret = new Uint8Array(32).fill(1);
const piiKey = new Uint8Array(32).fill(2);
const emailHmacKey = new Uint8Array(32).fill(3);

async function setup() {
  const database = new DatabaseSync(":memory:");
  database.exec(
    await readFile(
      new URL("../migrations/0001_initial.sql", import.meta.url),
      "utf8",
    ),
  );
  database.exec(
    await readFile(
      new URL("../migrations/0002_pairing_completion.sql", import.meta.url),
      "utf8",
    ),
  );
  const d1 = {
    prepare(sql: string) {
      const statement = database.prepare(sql);
      let values: unknown[] = [];
      const prepared = {
        bind(...bound: unknown[]) {
          values = bound;
          return prepared;
        },
        async run() {
          return statement.run(...values);
        },
        async first<T>() {
          return (statement.get(...values) as T | undefined) ?? null;
        },
        async all<T>() {
          return { results: statement.all(...values) as T[] };
        },
      };
      return prepared;
    },
  };
  const repo = new D1CloudRepository(d1, { now: () => 1_000 });
  await repo.createInvite({
    id: "invite-1",
    emailCiphertext: new TextEncoder().encode("encrypted-email"),
    emailLookupHash: await emailLookupHash("owner@example.com", emailHmacKey),
    expiresAt: 60_000,
  });
  const magicLinks: string[] = [];
  const hostNotifications: unknown[] = [];
  const gateway = new D1CommandGateway(repo, {
    jwtSecret,
    piiKey,
    emailHmacKey,
    publicOrigin: "https://relayforcodex.com",
    now: () => 1_000,
    sendMagicLink: async (_email, url) => {
      magicLinks.push(url);
    },
    notifyHost: async (_accountId, _hostId, message) => {
      hostNotifications.push(message);
    },
  });
  return {
    database,
    hostNotifications,
    magicLinks,
    worker: createWorker(gateway),
  };
}

async function json(
  worker: ReturnType<typeof createWorker>,
  path: string,
  init: RequestInit = {},
) {
  const response = await worker.fetch(
    new Request(`https://api.relayforcodex.com${path}`, {
      ...init,
      headers: {
        "content-type": "application/json",
        ...init.headers,
      },
    }),
  );
  return { response, body: await response.json() as Record<string, any> };
}

describe("D1-backed Worker flow", () => {
  it("runs invite login, host registration, pairing, and refresh reuse defense", async () => {
    const { database, hostNotifications, magicLinks, worker } = await setup();
    const verifier = "a-valid-pkce-verifier-with-at-least-forty-three-characters";
    const challenge = createHash("sha256").update(verifier).digest("base64url");

    const login = await json(worker, "/cloud/v1/auth/device-sessions", {
      method: "POST",
      body: JSON.stringify({
        email: "owner@example.com",
        pkceChallenge: challenge,
        pkceMethod: "S256",
      }),
    });
    assert.equal(login.response.status, 200);
    assert.equal(magicLinks.length, 1);

    const pending = await json(
      worker,
      `/cloud/v1/auth/device-sessions/${login.body.id}/token`,
      {
        method: "POST",
        body: JSON.stringify({ pkceVerifier: verifier }),
      },
    );
    assert.equal(pending.response.status, 202);

    const verification = await worker.fetch(new Request(magicLinks[0]!));
    assert.equal(verification.status, 200);

    const token = await json(
      worker,
      `/cloud/v1/auth/device-sessions/${login.body.id}/token`,
      {
        method: "POST",
        body: JSON.stringify({ pkceVerifier: verifier }),
      },
    );
    assert.equal(token.response.status, 200);
    assert.equal(typeof token.body.accessToken, "string");

    const host = await json(worker, "/cloud/v1/hosts", {
      method: "POST",
      headers: { authorization: `Bearer ${token.body.accessToken}` },
      body: JSON.stringify({
        name: "Owner Mac",
        signingPublicKey: "mac-signing-key",
        agreementPublicKey: "mac-agreement-key",
      }),
    });
    assert.equal(host.response.status, 200);

    const pairing = await json(
      worker,
      `/cloud/v1/hosts/${host.body.id}/pairing-sessions`,
      {
        method: "POST",
        headers: { authorization: `Bearer ${token.body.accessToken}` },
        body: JSON.stringify({ macFingerprint: "MAC FP" }),
      },
    );
    assert.match(pairing.body.code, /^[A-Z0-9]{6}$/);

    const request = await json(
      worker,
      `/cloud/v1/pairing-sessions/${pairing.body.code}/requests`,
      {
        method: "POST",
        body: JSON.stringify({
          fingerprint: "WATCH FP",
          signingPublicKey: "watch-signing-key",
          agreementPublicKey: "watch-agreement-key",
          metadata: { platform: "wear", model: "Watch6" },
        }),
      },
    );
    assert.equal(request.response.status, 200);
    assert.equal(typeof request.body.pollToken, "string");
    assert.deepEqual(hostNotifications, [
      {
        type: "pairing_request",
        requestId: request.body.id,
        fingerprint: "WATCH FP",
        signingPublicKey: "watch-signing-key",
        agreementPublicKey: "watch-agreement-key",
        expiresAt: 121_000,
        metadata: { platform: "wear", model: "Watch6" },
      },
    ]);

    const pairingPending = await json(
      worker,
      `/cloud/v1/pairing-requests/${request.body.id}`,
      {
        method: "GET",
        headers: { authorization: `Pairing ${request.body.pollToken}` },
      },
    );
    assert.equal(pairingPending.response.status, 200);
    assert.deepEqual(pairingPending.body, { status: "pending" });

    const approvedPayload = {
      version: 1,
      nonce: "pairing-payload-nonce",
      ciphertext: "opaque-e2ee-device-credential",
    };
    const deviceCredentialHash = createHash("sha256")
      .update("mac-generated-watch-credential")
      .digest("base64url");

    const approval = await json(
      worker,
      `/cloud/v1/pairing-sessions/${pairing.body.token}/approve`,
      {
        method: "POST",
        headers: { authorization: `Bearer ${token.body.accessToken}` },
        body: JSON.stringify({
          requestId: request.body.id,
          deviceId: "device-1",
          credentialHash: deviceCredentialHash,
          approvedPayload,
        }),
      },
    );
    assert.equal(approval.response.status, 200);
    assert.deepEqual(approval.body, {
      id: "device-1",
      hostId: host.body.id,
      sessionNonce: pairing.body.sessionNonce,
    });
    assert.equal(JSON.stringify(approval.body).includes("credential"), false);

    const completed = await json(
      worker,
      `/cloud/v1/pairing-requests/${request.body.id}`,
      {
        method: "GET",
        headers: { authorization: `Pairing ${request.body.pollToken}` },
      },
    );
    assert.equal(completed.response.status, 200);
    assert.deepEqual(completed.body, {
      status: "approved",
      payload: approvedPayload,
    });
    assert.equal(
      database.prepare("SELECT COUNT(*) AS count FROM devices").get()?.count,
      1,
    );
    assert.equal(
      database
        .prepare("SELECT credential_hash FROM devices WHERE id = ?")
        .get("device-1")?.credential_hash,
      deviceCredentialHash,
    );

    const emergency = await json(worker, "/cloud/v1/emergency-stop", {
      method: "POST",
      headers: { authorization: `Bearer ${token.body.accessToken}` },
      body: "{}",
    });
    assert.equal(emergency.response.status, 200);
    assert.equal(emergency.body.hostId, host.body.id);
    assert.equal(typeof emergency.body.hostCredential, "string");
    assert.equal(
      database.prepare("SELECT revoked_at FROM devices WHERE id = ?")
        .get("device-1")?.revoked_at,
      1_000,
    );
    assert.equal(
      database.prepare("SELECT credential_hash FROM hosts WHERE id = ?")
        .get(host.body.id)?.credential_hash,
      createHash("sha256")
        .update(emergency.body.hostCredential)
        .digest("base64url"),
    );

    const refreshed = await json(worker, "/cloud/v1/auth/refresh", {
      method: "POST",
      body: JSON.stringify({ refreshToken: token.body.refreshToken }),
    });
    assert.equal(refreshed.response.status, 200);
    const reuse = await json(worker, "/cloud/v1/auth/refresh", {
      method: "POST",
      body: JSON.stringify({ refreshToken: token.body.refreshToken }),
    });
    assert.equal(reuse.response.status, 401);
    const familyKilled = await json(worker, "/cloud/v1/auth/refresh", {
      method: "POST",
      body: JSON.stringify({ refreshToken: refreshed.body.refreshToken }),
    });
    assert.equal(familyKilled.response.status, 401);
  });
});
