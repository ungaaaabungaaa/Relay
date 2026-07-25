import assert from "node:assert/strict";
import { test } from "node:test";
import { DurableTunnelSession } from "../src/durable-tunnel.ts";

class DurableSocket {
  readonly messages: string[] = [];
  attachment?: unknown;
  closed?: number;

  send(value: string) {
    this.messages.push(value);
  }

  close(code: number) {
    this.closed = code;
  }

  serializeAttachment(value: unknown) {
    this.attachment = structuredClone(value);
  }

  deserializeAttachment() {
    return structuredClone(this.attachment);
  }
}

test("Durable Object socket attachments restore routing after hibernation", () => {
  const host = new DurableSocket();
  const watch = new DurableSocket();
  const first = new DurableTunnelSession([]);
  first.accept(
    { accountId: "account-1", hostId: "host-1", peerId: "host-1", role: "host" },
    host,
  );
  first.accept(
    { accountId: "account-1", hostId: "host-1", peerId: "watch-1", role: "device" },
    watch,
  );

  const restored = new DurableTunnelSession([host, watch]);
  restored.message(
    watch,
    JSON.stringify({
      version: 1,
      messageId: "message-1",
      accountId: "account-1",
      hostId: "host-1",
      senderId: "watch-1",
      recipientId: "host-1",
      sentAt: 1_000,
      sequence: 1,
      nonce: "opaque",
      ciphertext: "opaque",
    }),
  );

  assert.equal(host.messages.length, 1);
  assert.equal(JSON.parse(host.messages[0] ?? "{}").ciphertext, "opaque");
});

test("malformed socket messages close only the offending peer", () => {
  const watch = new DurableSocket();
  const session = new DurableTunnelSession([]);
  session.accept(
    { accountId: "account-1", hostId: "host-1", peerId: "watch-1", role: "device" },
    watch,
  );

  session.message(watch, "not-json");
  assert.equal(watch.closed, 4002);
});
