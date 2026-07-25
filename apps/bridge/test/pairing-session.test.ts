import assert from "node:assert/strict";
import { generateKeyPairSync } from "node:crypto";
import { describe, it } from "node:test";
import { PairingSessionService } from "../src/security/pairing-session.ts";
import { InMemorySecurityStore } from "../src/security/store.ts";

const metadata = {
  platform: "wear-os",
  manufacturer: "Google",
  model: "Pixel Watch",
  osVersion: "4",
  appVersion: "0.2.0",
  screenShape: "round",
} as const;

describe("secure pairing sessions", () => {
  it("does not activate a watch until the Mac approves its pending fingerprint", () => {
    let now = 1_000;
    const store = new InMemorySecurityStore();
    const service = new PairingSessionService(store, { now: () => now });
    const session = service.create({
      origin: "https://relay.example.ts.net",
      macName: "Studio Mac",
      macFingerprint: "ABCD:1234",
    });
    const { publicKey } = generateKeyPairSync("ec", {
      namedCurve: "prime256v1",
    });

    assert.deepEqual(service.discover(session.discoveryToken), {
      macName: "Studio Mac",
      macFingerprint: "ABCD:1234",
      apiVersion: 1,
      expiresAt: 301_000,
    });

    const pending = service.submit(
      session.discoveryToken,
      "192.0.2.10",
      {
        code: session.code,
        name: "Pixel Watch",
        publicKey: publicKey.export({ type: "spki", format: "pem" }).toString(),
        metadata,
      },
    );

    assert.equal(store.listDevices().length, 0);
    assert.equal(service.poll(session.discoveryToken, pending.pollToken).state, "pending");
    assert.deepEqual(service.listPending().map((item) => ({
      id: item.id,
      name: item.name,
      metadata: item.metadata,
    })), [{
      id: pending.pairingId,
      name: "Pixel Watch",
      metadata,
    }]);

    const approved = service.approve(pending.pairingId);
    assert.equal(approved.name, "Pixel Watch");
    assert.deepEqual(approved.metadata, metadata);
    assert.equal(store.listDevices().length, 1);
    assert.deepEqual(service.poll(session.discoveryToken, pending.pollToken), {
      state: "approved",
      deviceId: approved.id,
      origin: "https://relay.example.ts.net",
      apiVersion: 1,
    });

    now += 1;
    assert.throws(
      () =>
        service.submit(session.discoveryToken, "192.0.2.10", {
          code: session.code,
          name: "Another watch",
          publicKey: "PUBLIC",
          metadata,
        }),
      /pairing unavailable/,
    );
  });

  it("expires discovery and pending approval without creating a device", () => {
    let now = 10_000;
    const store = new InMemorySecurityStore();
    const service = new PairingSessionService(store, { now: () => now });
    const session = service.create({
      origin: "https://relay.example.ts.net",
      macName: "Studio Mac",
      macFingerprint: "ABCD:1234",
    });

    now = session.expiresAt + 1;
    assert.throws(
      () => service.discover(session.discoveryToken),
      /pairing unavailable/,
    );
    assert.equal(store.listDevices().length, 0);
  });

  it("blocks a source after five attempts without revealing whether a code was correct", () => {
    const store = new InMemorySecurityStore();
    const service = new PairingSessionService(store, { now: () => 1_000 });
    const { publicKey } = generateKeyPairSync("ec", {
      namedCurve: "prime256v1",
    });
    const publicKeyPem = publicKey.export({
      type: "spki",
      format: "pem",
    }).toString();
    const session = service.create({
      origin: "https://relay.example.ts.net",
      macName: "Studio Mac",
      macFingerprint: "ABCD:1234",
    });

    for (let attempt = 0; attempt < 5; attempt += 1) {
      assert.throws(
        () =>
          service.submit(session.discoveryToken, "192.0.2.10", {
            code: "WRONG2",
            name: "Pixel Watch",
            publicKey: publicKeyPem,
            metadata,
          }),
        /pairing unavailable/,
      );
    }

    assert.throws(
      () =>
        service.submit(session.discoveryToken, "192.0.2.10", {
          code: session.code,
          name: "Pixel Watch",
          publicKey: publicKeyPem,
          metadata,
        }),
      /pairing unavailable/,
    );
  });

  it("blocks all pairing after thirty attempts in the five-minute window", () => {
    const service = new PairingSessionService(
      new InMemorySecurityStore(),
      { now: () => 1_000 },
    );
    const { publicKey } = generateKeyPairSync("ec", {
      namedCurve: "prime256v1",
    });
    const publicKeyPem = publicKey.export({
      type: "spki",
      format: "pem",
    }).toString();
    const session = service.create({
      origin: "https://relay.example.ts.net",
      macName: "Studio Mac",
      macFingerprint: "ABCD:1234",
    });

    for (let source = 0; source < 6; source += 1) {
      for (let attempt = 0; attempt < 5; attempt += 1) {
        assert.throws(
          () =>
            service.submit(
              session.discoveryToken,
              `192.0.2.${source + 1}`,
              {
                code: "WRONG2",
                name: "Pixel Watch",
                publicKey: publicKeyPem,
                metadata,
              },
            ),
          /pairing unavailable/,
        );
      }
    }

    assert.throws(
      () =>
        service.submit(session.discoveryToken, "192.0.2.100", {
          code: session.code,
          name: "Pixel Watch",
          publicKey: publicKeyPem,
          metadata,
        }),
      /pairing unavailable/,
    );
  });
});
