import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import test from "node:test";

test("rejects startup cleanly when the Codex executable is unavailable", async () => {
  const emptyPath = await mkdtemp(join(tmpdir(), "relay-empty-path-"));
  const clientModule = pathToFileURL(
    join(
      dirname(fileURLToPath(import.meta.url)),
      "..",
      "src",
      "codex",
      "client.ts",
    ),
  ).href;
  const script = `
    import { CodexRpcClient } from ${JSON.stringify(clientModule)};
    try {
      await new CodexRpcClient().start();
      throw new Error("startup unexpectedly succeeded");
    } catch (error) {
      if (!/Codex app-server could not start \\(ENOENT\\)/.test(error.message)) {
        throw error;
      }
      console.log("missing Codex handled");
    }
  `;

  try {
    const result = await new Promise<{
      code: number | null;
      signal: NodeJS.Signals | null;
      stdout: string;
      stderr: string;
    }>((resolve) => {
      const child = spawn(
        process.execPath,
        ["--input-type=module", "--experimental-strip-types", "--eval", script],
        {
          env: { ...process.env, PATH: emptyPath },
          stdio: ["ignore", "pipe", "pipe"],
        },
      );
      let stdout = "";
      let stderr = "";
      child.stdout.setEncoding("utf8");
      child.stderr.setEncoding("utf8");
      child.stdout.on("data", (chunk) => {
        stdout += chunk;
      });
      child.stderr.on("data", (chunk) => {
        stderr += chunk;
      });
      child.once("close", (code, signal) => {
        resolve({ code, signal, stdout, stderr });
      });
    });

    assert.equal(result.signal, null, result.stderr);
    assert.equal(result.code, 0, result.stderr);
    assert.match(result.stdout, /missing Codex handled/);
  } finally {
    await rm(emptyPath, { recursive: true, force: true });
  }
});
