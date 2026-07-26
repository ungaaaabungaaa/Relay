import assert from "node:assert/strict";
import { test } from "node:test";
import { createResendMagicLinkSender } from "../src/resend.ts";

test("Resend adapter sends only the invited email and single-use URL", async () => {
  const calls: Array<{ url: string; init: RequestInit }> = [];
  const send = createResendMagicLinkSender({
    apiKey: "resend-secret",
    from: "Relay <sign-in@relayforcodex.com>",
    fetch: async (input, init) => {
      calls.push({ url: String(input), init: init ?? {} });
      return new Response(JSON.stringify({ id: "email-1" }), { status: 200 });
    },
  });

  await send(
    "owner@example.com",
    "https://relayforcodex.com/cloud/v1/auth/verify?token=single-use",
  );

  assert.equal(calls[0]?.url, "https://api.resend.com/emails");
  assert.equal(
    new Headers(calls[0]?.init.headers).get("authorization"),
    "Bearer resend-secret",
  );
  const body = JSON.parse(String(calls[0]?.init.body));
  assert.deepEqual(body.to, ["owner@example.com"]);
  assert.match(body.html, /single-use/);
  assert.doesNotMatch(body.html, /resend-secret/);
});

test("Resend adapter returns a generic error without response contents", async () => {
  const send = createResendMagicLinkSender({
    apiKey: "resend-secret",
    from: "Relay <sign-in@relayforcodex.com>",
    fetch: async () =>
      new Response("provider leaked detail", { status: 500 }),
  });

  await assert.rejects(
    send("owner@example.com", "https://relayforcodex.com/verify"),
    (error: Error) =>
      error.message === "Email delivery failed" &&
      !error.message.includes("provider"),
  );
});
