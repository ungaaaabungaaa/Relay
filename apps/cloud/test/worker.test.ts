import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { createWorker } from "../src/worker.ts";

function env() {
  const calls: Array<{ name: string; args: unknown }> = [];
  return {
    calls,
    worker: createWorker({
      command: async (name, args) => {
        calls.push({ name, args });
        return { ok: true };
      },
    }),
  };
}

describe("Relay Cloud Worker routes", () => {
  it("serves privacy, terms, support, deletion, and magic-link verification pages", async () => {
    const { worker } = env();
    for (const path of [
      "/privacy",
      "/terms",
      "/support",
      "/account/delete",
      "/cloud/v1/auth/verify?token=redacted",
    ]) {
      const response = await worker.fetch(new Request(`https://relay.test${path}`));
      assert.equal(response.status, 200, path);
      assert.doesNotMatch(await response.text(), /redacted/);
    }
  });

  it("publishes substantive privacy, retention, support, and beta terms", async () => {
    const { worker } = env();
    const privacy = await worker.fetch(new Request("https://relay.test/privacy"));
    const privacyText = await privacy.text();
    assert.match(privacyText, /end-to-end encrypted/i);
    assert.match(privacyText, /seven days/i);
    assert.match(privacyText, /no product analytics/i);
    assert.match(privacyText, /delete/i);

    const terms = await worker.fetch(new Request("https://relay.test/terms"));
    assert.match(await terms.text(), /invite-only beta/i);

    const support = await worker.fetch(new Request("https://relay.test/support"));
    assert.match(await support.text(), /support@relayforcodex\.com/i);
    assert.match(
      support.headers.get("content-security-policy") ?? "",
      /default-src 'none'/,
    );
  });

  it("maps the beta API without exposing a public signup route", async () => {
    const { worker, calls } = env();
    const request = new Request("https://relay.test/cloud/v1/auth/device-sessions", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ email: "invited@example.com", pkceChallenge: "challenge" }),
    });
    assert.equal((await worker.fetch(request)).status, 200);
    assert.equal(calls[0]?.name, "auth.deviceSessions.create");

    const signup = await worker.fetch(
      new Request("https://relay.test/cloud/v1/signup", { method: "POST" }),
    );
    assert.equal(signup.status, 404);
  });

  it("maps invite creation only to the protected operator command", async () => {
    const { worker, calls } = env();
    const response = await worker.fetch(
      new Request("https://relay.test/cloud/v1/admin/invites", {
        method: "POST",
        headers: {
          authorization: "Admin opaque-operator-credential",
          "content-type": "application/json",
        },
        body: JSON.stringify({ email: "tester@example.com" }),
      }),
    );

    assert.equal(response.status, 200);
    assert.equal(calls.at(-1)?.name, "admin.invites.create");
  });

  it("returns generic errors and never echoes credentials or request bodies", async () => {
    const worker = createWorker({
      command: async () => {
        throw new Error("SQL included secret@example.com and bearer-token");
      },
    });
    const response = await worker.fetch(
      new Request("https://relay.test/cloud/v1/auth/refresh", {
        method: "POST",
        body: JSON.stringify({ refreshToken: "bearer-token" }),
      }),
    );
    assert.equal(response.status, 401);
    assert.deepEqual(await response.json(), {
      error: { code: "authentication_failed", message: "Authentication failed" },
    });
  });

  it("rejects oversized relay envelopes before reaching storage or routing", async () => {
    const { worker, calls } = env();
    const response = await worker.fetch(
      new Request("https://relay.test/cloud/v1/relay", {
        method: "POST",
        headers: {
          authorization: "Bearer opaque",
          "content-type": "application/json",
        },
        body: JSON.stringify({ ciphertext: "x".repeat(2 * 1024 * 1024 + 1) }),
      }),
    );
    assert.equal(response.status, 413);
    assert.equal(calls.length, 0);
  });
});
