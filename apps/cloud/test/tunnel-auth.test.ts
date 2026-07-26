import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { resolveTunnelPeer } from "../src/cloud-runtime.ts";

describe("cloud WebSocket authentication", () => {
  it("authenticates host and device upgrades without putting credentials in URLs", async () => {
    const calls: Array<{ role: string; id: string; hash: string }> = [];
    const repository = {
      async authenticateHost(id: string, hash: string) {
        calls.push({ role: "host", id, hash });
        return {
          accountId: "account-1",
          hostId: id,
          peerId: id,
          role: "host" as const,
        };
      },
      async authenticateDevice(id: string, hash: string) {
        calls.push({ role: "device", id, hash });
        return {
          accountId: "account-1",
          hostId: "host-1",
          peerId: id,
          role: "device" as const,
        };
      },
    };

    const host = await resolveTunnelPeer(
      new Request("https://api.relayforcodex.com/cloud/v1/connect/host", {
        headers: {
          upgrade: "websocket",
          authorization: "Bearer host-secret-with-entropy",
          "x-relay-host-id": "host-1",
        },
      }),
      repository,
    );
    const device = await resolveTunnelPeer(
      new Request("https://api.relayforcodex.com/cloud/v1/connect/device", {
        headers: {
          upgrade: "websocket",
          authorization: "Bearer watch-secret-with-entropy",
          "x-relay-device-id": "watch-1",
        },
      }),
      repository,
    );

    assert.equal(host.role, "host");
    assert.equal(device.role, "device");
    assert.equal(calls[0]?.id, "host-1");
    assert.notEqual(calls[0]?.hash, "host-secret-with-entropy");
    assert.notEqual(calls[1]?.hash, "watch-secret-with-entropy");
  });

  it("rejects ordinary HTTP, URL credentials, and unknown tunnel paths", async () => {
    const repository = {
      async authenticateHost() {
        throw new Error("must not run");
      },
      async authenticateDevice() {
        throw new Error("must not run");
      },
    };
    await assert.rejects(
      resolveTunnelPeer(
        new Request(
          "https://api.relayforcodex.com/cloud/v1/connect/host?credential=secret",
        ),
        repository,
      ),
      /websocket upgrade required/i,
    );
    await assert.rejects(
      resolveTunnelPeer(
        new Request("https://api.relayforcodex.com/cloud/v1/connect/other", {
          headers: {
            upgrade: "websocket",
            authorization: "Bearer secret",
            "x-relay-host-id": "host-1",
          },
        }),
        repository,
      ),
      /authentication failed/i,
    );
  });
});
