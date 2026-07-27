import assert from "node:assert/strict";
import { it } from "node:test";
import { createBridgeShutdown } from "../src/cli-lifecycle.ts";

it("closes the cloud runtime before the bridge resources during CLI shutdown", async () => {
  const calls: string[] = [];
  const shutdown = createBridgeShutdown({
    cloudRuntime: {
      close: async () => {
        calls.push("cloudRuntime.close");
      },
    },
    server: { close: () => calls.push("server.close") },
    adminServer: { close: () => calls.push("adminServer.close") },
    adapter: { stop: () => calls.push("adapter.stop") },
  });

  await Promise.all([shutdown(), shutdown()]);
  assert.deepEqual(calls, [
    "cloudRuntime.close",
    "server.close",
    "adminServer.close",
    "adapter.stop",
  ]);
});
