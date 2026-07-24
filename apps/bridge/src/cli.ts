import { homedir } from "node:os";
import { delimiter, join } from "node:path";
import { parseArgs } from "node:util";
import {
  assertLoopbackAdminHost,
  listenAdminServer,
} from "./admin/admin-server.ts";
import { CodexAdapter } from "./codex/adapter.ts";
import { PairingService } from "./security/pairing.ts";
import { createRelayServer } from "./server.ts";
import { SqliteStore } from "./store/sqlite-store.ts";
import { OpenAITranscriber } from "./transcription/openai-transcriber.ts";
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
const openAiApiKey = process.env.OPENAI_API_KEY?.trim();

if (command === "serve") {
  const adminToken = process.env.CODEWATCH_ADMIN_TOKEN?.trim();
  if (!adminToken) {
    throw new Error("CODEWATCH_ADMIN_TOKEN is required to start the bridge");
  }
  const host = process.env.CODEWATCH_BIND_HOST ?? "127.0.0.1";
  const adminHost = process.env.CODEWATCH_ADMIN_HOST ?? "127.0.0.1";
  assertLoopbackAdminHost(host);
  assertLoopbackAdminHost(adminHost);
  const port = Number(process.env.CODEWATCH_PORT ?? "43117");
  const adminPort = Number(process.env.CODEWATCH_ADMIN_PORT ?? "43118");
  const adapter = new CodexAdapter();
  let codexStatus: "starting" | "ready" | "unavailable" = "starting";
  void adapter.start().then(
    () => {
      codexStatus = "ready";
    },
    () => {
      codexStatus = "unavailable";
      console.error("Relay could not connect to Codex");
    },
  );
  const server = createRelayServer({
    store,
    adapter,
    workspacePolicy,
    eventHub: adapter.events,
    ...(openAiApiKey
      ? {
          transcriber: new OpenAITranscriber({ apiKey: openAiApiKey }),
          transcriptionTemporaryDirectory: join(dataDir, "transcription"),
        }
      : {}),
  });
  server.listen(port, host, () => {
    const address = server.address();
    const listeningPort =
      address && typeof address !== "string" ? address.port : port;
    console.log(`Relay bridge listening on http://${host}:${listeningPort}`);
  });
  let shuttingDown = false;
  const shutdown = () => {
    if (shuttingDown) return;
    shuttingDown = true;
    server.close();
    adminServer.close();
    adapter.stop();
  };
  const adminServer = listenAdminServer(
    {
      token: adminToken,
      store,
      workspacePolicy,
      adminBindHost: adminHost,
      watchBindHost: host,
      watchPort: port,
      codexStatus: () => codexStatus,
      voiceConfigured: Boolean(openAiApiKey),
      shutdown,
    },
    adminPort,
    adminHost,
    (address) => {
      console.log(
        `Relay admin listening on http://${adminHost}:${address.port}`,
      );
    },
  );
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
