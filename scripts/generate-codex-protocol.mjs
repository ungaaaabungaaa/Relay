import { mkdirSync, rmSync, writeFileSync } from "node:fs";
import { spawnSync } from "node:child_process";
import { resolve } from "node:path";

const output = resolve("packages/codex-protocol/generated");
rmSync(output, { recursive: true, force: true });
mkdirSync(output, { recursive: true });

const generated = spawnSync(
  "codex",
  ["app-server", "generate-ts", "--experimental", "--out", output],
  { encoding: "utf8" },
);

if (generated.status !== 0) {
  process.stderr.write(generated.stderr);
  process.exit(generated.status ?? 1);
}

const version = spawnSync("codex", ["--version"], { encoding: "utf8" });
if (version.status !== 0) {
  process.stderr.write(version.stderr);
  process.exit(version.status ?? 1);
}

writeFileSync(
  resolve(output, "relay-generation.json"),
  `${JSON.stringify({ codexVersion: version.stdout.trim() }, null, 2)}\n`,
);
console.log(`Generated Codex protocol bindings in ${output}`);
