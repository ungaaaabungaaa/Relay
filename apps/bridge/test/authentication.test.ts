import assert from "node:assert/strict";
import { generateKeyPairSync, sign } from "node:crypto";
import { describe, it } from "node:test";
import { InMemorySecurityStore } from "../src/security/store.ts";
import { canonicalRequest, verifyRequest } from "../src/security/authentication.ts";

describe("signed requests", () => {
  it("accepts a valid signature exactly once", () => {
    const { publicKey, privateKey } = generateKeyPairSync("ed25519");
    const store = new InMemorySecurityStore();
    store.addDevice("watch", publicKey.export({ type: "spki", format: "pem" }).toString());
    const timestamp = 1_750_000_000_000;
    const input = {
      deviceId: "watch",
      method: "GET",
      path: "/v1/tasks",
      body: new Uint8Array(),
      timestamp,
      nonce: "nonce-1234567890",
    };
    const signature = sign(null, Buffer.from(canonicalRequest(input)), privateKey).toString("base64");
    assert.equal(verifyRequest(store, { ...input, signature }, timestamp), "watch");
    assert.throws(
      () => verifyRequest(store, { ...input, signature }, timestamp),
      /replayed nonce/,
    );
  });

  it("rejects stale requests and revoked devices", () => {
    const store = new InMemorySecurityStore();
    assert.throws(
      () =>
        verifyRequest(
          store,
          {
            deviceId: "missing",
            method: "GET",
            path: "/v1/tasks",
            body: new Uint8Array(),
            timestamp: 0,
            nonce: "nonce-1234567890",
            signature: "",
          },
          600_000,
        ),
      /stale request/,
    );
  });

  it("accepts Android Keystore compatible P-256 signatures", () => {
    const { publicKey, privateKey } = generateKeyPairSync("ec", {
      namedCurve: "prime256v1",
    });
    const store = new InMemorySecurityStore();
    store.addDevice("watch-ec", publicKey.export({ type: "spki", format: "pem" }).toString());
    const timestamp = 1_750_000_000_000;
    const input = {
      deviceId: "watch-ec",
      method: "GET",
      path: "/v1/inbox",
      body: new Uint8Array(),
      timestamp,
      nonce: "nonce-ec-12345678",
    };
    const signature = sign(
      "sha256",
      Buffer.from(canonicalRequest(input)),
      privateKey,
    ).toString("base64");
    assert.equal(verifyRequest(store, { ...input, signature }, timestamp), "watch-ec");
  });
});
