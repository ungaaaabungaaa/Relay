import { spawnSync } from "node:child_process";
import {
  chmod,
  copyFile,
  mkdir,
  rm,
  writeFile,
} from "node:fs/promises";
import { resolve } from "node:path";
import process from "node:process";
import { build } from "esbuild";

if (process.platform !== "darwin" || process.arch !== "arm64") {
  throw new Error("Relay bridge releases are built only on Apple silicon Macs");
}

const root = resolve(import.meta.dirname, "..");
const outputDirectory = resolve(root, "dist");
const bundlePath = resolve(outputDirectory, "relay-bridge.cjs");
const blobPath = resolve(outputDirectory, "relay-bridge.blob");
const configPath = resolve(outputDirectory, "relay-bridge-sea.json");
const executablePath = resolve(outputDirectory, "relay-bridge-arm64");
const postjectPath = resolve(root, "node_modules", ".bin", "postject");

function run(command, arguments_) {
  const result = spawnSync(command, arguments_, {
    cwd: root,
    encoding: "utf8",
    stdio: ["ignore", "pipe", "pipe"],
  });
  if (result.status !== 0) {
    const detail = [result.stdout, result.stderr].filter(Boolean).join("\n").trim();
    throw new Error(
      `${command} ${arguments_.join(" ")} failed${detail ? `: ${detail}` : ""}`,
    );
  }
}

await rm(outputDirectory, { recursive: true, force: true });
await mkdir(outputDirectory, { recursive: true, mode: 0o755 });
await build({
  entryPoints: [resolve(root, "apps/bridge/src/cli.ts")],
  outfile: bundlePath,
  bundle: true,
  platform: "node",
  format: "cjs",
  target: "node24",
  sourcemap: false,
  minify: false,
  legalComments: "none",
});
await writeFile(
  configPath,
  `${JSON.stringify(
    {
      main: bundlePath,
      output: blobPath,
      disableExperimentalSEAWarning: true,
      useSnapshot: false,
      useCodeCache: false,
    },
    null,
    2,
  )}\n`,
  { mode: 0o600 },
);
run(process.execPath, ["--experimental-sea-config", configPath]);
await copyFile(process.execPath, executablePath);
await chmod(executablePath, 0o755);
run("/usr/bin/codesign", ["--remove-signature", executablePath]);
run(postjectPath, [
  executablePath,
  "NODE_SEA_BLOB",
  blobPath,
  "--sentinel-fuse",
  "NODE_SEA_FUSE_fce680ab2cc467b6e072b8b5df1996b2",
  "--macho-segment-name",
  "NODE_SEA",
]);
run("/usr/bin/codesign", ["--force", "--sign", "-", executablePath]);
run("/usr/bin/codesign", ["--verify", "--verbose=2", executablePath]);

console.log(`Built ${executablePath}`);
