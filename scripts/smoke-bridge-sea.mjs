import assert from "node:assert/strict";
import { randomBytes } from "node:crypto";
import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { resolve } from "node:path";
import { spawn } from "node:child_process";
import { createInterface } from "node:readline";

const binary = resolve(process.argv[2] ?? "dist/relay-bridge-arm64");
const temporary = await mkdtemp(`${tmpdir()}/relay-sea-smoke-`);
const token = randomBytes(32).toString("base64url");
const environment = {
  ...process.env,
  CODEWATCH_DATA_DIR: temporary,
  CODEWATCH_WORKSPACE_ROOTS: temporary,
  CODEWATCH_ADMIN_TOKEN: token,
  CODEWATCH_BIND_HOST: "127.0.0.1",
  CODEWATCH_ADMIN_HOST: "127.0.0.1",
  CODEWATCH_PORT: "0",
  CODEWATCH_ADMIN_PORT: "0",
};
delete environment.OPENAI_API_KEY;

const child = spawn(binary, ["serve"], {
  env: environment,
  stdio: ["ignore", "pipe", "pipe"],
});
let stderr = "";
child.stderr.setEncoding("utf8");
child.stderr.on("data", (chunk) => {
  stderr += chunk;
});

const ports = new Promise((resolvePorts, reject) => {
  let watchPort;
  let adminPort;
  const lines = createInterface({ input: child.stdout });
  lines.on("line", (line) => {
    const watch = line.match(/Relay bridge listening on http:\/\/127\.0\.0\.1:(\d+)/);
    const admin = line.match(/Relay admin listening on http:\/\/127\.0\.0\.1:(\d+)/);
    if (watch?.[1]) watchPort = Number(watch[1]);
    if (admin?.[1]) adminPort = Number(admin[1]);
    if (watchPort && adminPort) resolvePorts({ watchPort, adminPort });
  });
  child.once("exit", (code) => {
    reject(new Error(`bridge exited before startup (${code}): ${stderr.trim()}`));
  });
  child.once("error", reject);
});

async function withTimeout(promise, milliseconds, label) {
  let timer;
  try {
    return await Promise.race([
      promise,
      new Promise((_, reject) => {
        timer = setTimeout(
          () => reject(new Error(`${label} timed out`)),
          milliseconds,
        );
      }),
    ]);
  } finally {
    clearTimeout(timer);
  }
}

try {
  const { watchPort, adminPort } = await withTimeout(
    ports,
    20_000,
    "bridge startup",
  );
  const watchResponse = await fetch(`http://127.0.0.1:${watchPort}/health`);
  assert.equal(watchResponse.status, 200);
  const watchHealth = await watchResponse.json();
  assert.deepEqual(watchHealth, { ok: true, service: "relay" });
  assert.equal(JSON.stringify(watchHealth).includes(temporary), false);

  const unauthorized = await fetch(
    `http://127.0.0.1:${adminPort}/v1/status`,
  );
  assert.equal(unauthorized.status, 401);
  assert.deepEqual(await unauthorized.json(), { error: "unauthorized" });

  const authorization = { authorization: `Bearer ${token}` };
  const adminResponse = await fetch(
    `http://127.0.0.1:${adminPort}/health`,
    { headers: authorization },
  );
  assert.equal(adminResponse.status, 200);
  assert.deepEqual(await adminResponse.json(), {
    ok: true,
    service: "relay-admin",
  });

  const shutdown = await fetch(
    `http://127.0.0.1:${adminPort}/v1/shutdown`,
    { method: "POST", headers: authorization },
  );
  assert.equal(shutdown.status, 202);
  await withTimeout(
    new Promise((resolveExit, reject) => {
      child.once("exit", (code, signal) => {
        if (code === 0 || signal === "SIGTERM") resolveExit();
        else reject(new Error(`bridge stopped with exit code ${code}`));
      });
    }),
    10_000,
    "bridge shutdown",
  );
  console.log("Relay bridge SEA smoke test passed");
} finally {
  if (child.exitCode === null && child.signalCode === null) child.kill("SIGTERM");
  await rm(temporary, { recursive: true, force: true });
}
