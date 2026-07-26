import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { HibernatingTunnelRouter } from "../src/tunnel-router.ts";

class TestSocket {
  readonly messages: string[] = [];
  closed?: { code: number; reason: string };

  send(message: string) {
    this.messages.push(message);
  }

  close(code: number, reason: string) {
    this.closed = { code, reason };
  }
}

const envelope = {
  version: 1 as const,
  messageId: "message-1",
  accountId: "account-1",
  hostId: "host-1",
  senderId: "watch-1",
  recipientId: "host-1",
  sentAt: 1_000,
  sequence: 1,
  nonce: "opaque-nonce",
  ciphertext: "opaque-ciphertext",
};

describe("hibernating tunnel routing", () => {
  it("routes ciphertext unchanged and cannot inspect the inner message", () => {
    const router = new HibernatingTunnelRouter();
    const host = new TestSocket();
    const watch = new TestSocket();
    router.connect(
      { accountId: "account-1", hostId: "host-1", peerId: "host-1", role: "host" },
      host,
    );
    router.connect(
      { accountId: "account-1", hostId: "host-1", peerId: "watch-1", role: "device" },
      watch,
    );

    assert.equal(router.route(envelope), "delivered");
    assert.deepEqual(host.messages, [JSON.stringify(envelope)]);
  });

  it("rejects cross-account, cross-host, and spoofed-sender envelopes", () => {
    const router = new HibernatingTunnelRouter();
    router.connect(
      { accountId: "account-1", hostId: "host-1", peerId: "watch-1", role: "device" },
      new TestSocket(),
    );

    assert.throws(
      () => router.route({ ...envelope, accountId: "account-2" }),
      /authentication failed/i,
    );
    assert.throws(
      () => router.route({ ...envelope, hostId: "host-2" }),
      /authentication failed/i,
    );
    assert.throws(
      () => router.route({ ...envelope, senderId: "watch-2" }),
      /authentication failed/i,
    );
  });

  it("does not queue actions while the Mac is offline", () => {
    const router = new HibernatingTunnelRouter();
    const watch = new TestSocket();
    router.connect(
      { accountId: "account-1", hostId: "host-1", peerId: "watch-1", role: "device" },
      watch,
    );

    assert.equal(router.route(envelope), "offline");
    assert.equal(router.queuedMessageCount, 0);
    assert.deepEqual(JSON.parse(watch.messages[0] ?? "{}"), {
      type: "host_offline",
      hostId: "host-1",
    });
  });

  it("closes a revoked device immediately", () => {
    const router = new HibernatingTunnelRouter();
    const watch = new TestSocket();
    router.connect(
      { accountId: "account-1", hostId: "host-1", peerId: "watch-1", role: "device" },
      watch,
    );

    router.revoke("watch-1");
    assert.deepEqual(watch.closed, { code: 4003, reason: "Device revoked" });
    assert.throws(() => router.route(envelope), /authentication failed/i);
  });

  it("disconnects a rotated host without permanently blocking reconnection", () => {
    const router = new HibernatingTunnelRouter();
    const first = new TestSocket();
    const replacement = new TestSocket();
    const host = {
      accountId: "account-1",
      hostId: "host-1",
      peerId: "host-1",
      role: "host" as const,
    };
    router.connect(host, first);

    router.terminate("host-1", 4004, "Emergency stop");
    assert.deepEqual(first.closed, { code: 4004, reason: "Emergency stop" });
    router.connect(host, replacement);

    assert.equal(router.sendControl("host-1", { type: "pairing_request" }), "delivered");
  });

  it("delivers pairing control metadata only to the connected host", () => {
    const router = new HibernatingTunnelRouter();
    const host = new TestSocket();
    const watch = new TestSocket();
    router.connect(
      { accountId: "account-1", hostId: "host-1", peerId: "host-1", role: "host" },
      host,
    );
    router.connect(
      { accountId: "account-1", hostId: "host-1", peerId: "watch-1", role: "device" },
      watch,
    );

    assert.equal(
      router.sendControl("host-1", {
        type: "pairing_request",
        requestId: "request-1",
      }),
      "delivered",
    );
    assert.deepEqual(JSON.parse(host.messages[0] ?? "{}"), {
      type: "pairing_request",
      requestId: "request-1",
    });
    assert.equal(watch.messages.length, 0);
    assert.equal(
      router.sendControl("offline-host", { type: "pairing_request" }),
      "offline",
    );
  });
});
