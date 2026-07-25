#!/usr/bin/env node

import { createHash } from "node:crypto";
import { readFile, writeFile } from "node:fs/promises";
import { basename, join, resolve } from "node:path";
import { pathToFileURL } from "node:url";

function option(args, name) {
  const index = args.indexOf(name);
  if (index < 0 || !args[index + 1]) {
    throw new Error(`missing required option ${name}`);
  }
  return args[index + 1];
}

async function artifact(directory, version, name, architecture, signed) {
  if (basename(name) !== name) {
    throw new Error("release artifact names must be plain filenames");
  }
  const data = await readFile(join(directory, name));
  return {
    name,
    version,
    architecture,
    sha256: createHash("sha256").update(data).digest("hex"),
    signed,
  };
}

export async function createReleasePayload({
  artifactsDirectory,
  tag,
  watchVersionCode,
  codexMinimumVersion,
  codexMaximumVersion,
}) {
  if (!/^v\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?$/.test(tag)) {
    throw new Error("tag must look like v1.2.3");
  }
  const version = tag.slice(1);
  const artifactDefinitions = [
    ["Relay.dmg", "arm64", true],
    ["relay-wear.apk", "universal", true],
    ["relay-bridge-arm64", "arm64", true],
    [`Relay-${version}.tar.gz`, "source", false],
    ["LICENSE", "text", false],
    ["NOTICE", "text", false],
    ["THIRD_PARTY_NOTICES.md", "text", false],
    ["COMPATIBILITY.md", "text", false],
  ];
  const artifacts = await Promise.all(
    artifactDefinitions.map(([name, architecture, signed]) =>
      artifact(
        resolve(artifactsDirectory),
        version,
        name,
        architecture,
        signed,
      )),
  );
  return {
    schemaVersion: 1,
    tag,
    version,
    license: "Apache-2.0",
    mac: {
      version,
      artifact: "Relay.dmg",
      architecture: "arm64",
    },
    watch: {
      versionName: version,
      versionCode: Number(watchVersionCode),
      artifact: "relay-wear.apk",
      minimumWearOS: 3,
    },
    codex: {
      minimumVersion: codexMinimumVersion,
      maximumVersion: codexMaximumVersion,
    },
    artifacts,
  };
}

async function main() {
  const args = process.argv.slice(2);
  const payload = await createReleasePayload({
    artifactsDirectory: option(args, "--artifacts"),
    tag: option(args, "--tag"),
    watchVersionCode: option(args, "--watch-version-code"),
    codexMinimumVersion: option(args, "--codex-min"),
    codexMaximumVersion: option(args, "--codex-max"),
  });
  if (!Number.isSafeInteger(payload.watch.versionCode) || payload.watch.versionCode < 1) {
    throw new Error("watch version code must be a positive integer");
  }
  const output = resolve(option(args, "--output"));
  await writeFile(output, `${JSON.stringify(payload, null, 2)}\n`, {
    mode: 0o600,
  });
  process.stdout.write(`Created unsigned release payload for ${payload.tag}.\n`);
}

if (
  process.argv[1]
  && import.meta.url === pathToFileURL(resolve(process.argv[1])).href
) {
  main().catch((error) => {
    process.stderr.write(`Manifest creation failed: ${error.message}\n`);
    process.exitCode = 1;
  });
}
