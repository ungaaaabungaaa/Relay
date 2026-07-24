import { homedir } from "node:os";
import { delimiter, join } from "node:path";
import { parseArgs } from "node:util";
import { CodexAdapter } from "./codex/adapter.ts";
import { PairingService } from "./security/pairing.ts";
import { createRelayServer } from "./server.ts";
import { SqliteStore } from "./store/sqlite-store.ts";
import { WorkspacePolicy } from "./workspaces/workspace-policy.ts";

const dataDir =
  process.env.CODEWATCH_DATA_DIR ??
  join(homedir(), "Library", "Application Support", "Relay");
const store = new SqliteStore(join(dataDir, "relay.sqlite"));
const workspacePolicy = new WorkspacePolicy(
  (process.env.CODEWATCH_WORKSPACE_ROOTS ?? "")
    .split(delimiter)
    .map((root) => root.trim())
    .filter(Boolean),
);
const { positionals } = parseArgs({ allowPositionals: true });
const command = positionals[0] ?? "help";

if (command === "serve") {
  const adapter = new CodexAdapter();
  await adapter.start();
  const server = createRelayServer({
    store,
    adapter,
    workspacePolicy,
    eventHub: adapter.events,
  });
  const host = process.env.CODEWATCH_BIND_HOST ?? "127.0.0.1";
  const port = Number(process.env.CODEWATCH_PORT ?? "43117");
  server.listen(port, host, () => {
    console.log(`Relay bridge listening on http://${host}:${port}`);
  });
  const shutdown = () => {
    server.close();
    adapter.stop();
  };
  process.on("SIGINT", shutdown);
  process.on("SIGTERM", shutdown);
} else if (command === "pair") {
  console.log(new PairingService(store).createCode());
} else if (command === "devices") {
  for (const device of store.listDevices()) {
    console.log(
      `${device.id}\t${device.name}\t${device.revokedAt ? "revoked" : "active"}`,
    );
  }
} else if (command === "revoke") {
  const id = positionals[1];
  if (!id) throw new Error("Usage: node apps/bridge/src/cli.ts revoke DEVICE_ID");
  store.revokeDevice(id);
  console.log(`Revoked ${id}`);
} else {
  console.log("Relay bridge commands: serve | pair | devices | revoke DEVICE_ID");
}
