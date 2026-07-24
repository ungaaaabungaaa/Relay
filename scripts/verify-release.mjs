#!/usr/bin/env node

import {
  createHash,
  createPublicKey,
  verify,
} from "node:crypto";
import { access, readFile } from "node:fs/promises";
import { basename, join, resolve } from "node:path";
import { pathToFileURL } from "node:url";
import { spawnSync } from "node:child_process";

const ED25519_SPKI_PREFIX = Buffer.from("302a300506032b6570032100", "hex");
const SHA256_PATTERN = /^[a-f0-9]{64}$/;
const VERSION_PATTERN = /^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?$/;
const CODEX_RANGE_PATTERN = /^\d+\.\d+\.(?:\d+|x)$/;

export function canonicalizeManifestPayload(payload) {
  return JSON.stringify(sortRecursively(payload));
}

export async function verifyRelease({
  manifest,
  manifestPath,
  artifactsDirectory,
  expectedTag,
  publicKey,
  verifyApkSignature = false,
}) {
  const loadedManifest = manifest
    ?? JSON.parse(await readFile(manifestPath, "utf8"));
  const trustedPublicKey = normalizePublicKey(publicKey);
  assertObject(loadedManifest, "release manifest");
  assertObject(loadedManifest.payload, "release payload");
  if (
    typeof loadedManifest.signature !== "string"
    || !verify(
      null,
      Buffer.from(canonicalizeManifestPayload(loadedManifest.payload)),
      trustedPublicKey,
      decodeBase64(loadedManifest.signature, "release signature"),
    )
  ) {
    throw new Error("invalid release signature");
  }

  const payload = loadedManifest.payload;
  assertReleaseShape(payload, expectedTag);
  const requiredArtifacts = new Map([
    ["Relay.dmg", { architecture: "arm64", signed: true }],
    ["relay-wear.apk", { architecture: "universal", signed: true }],
    ["relay-bridge-arm64", { architecture: "arm64", signed: true }],
    [`Relay-${payload.version}.tar.gz`, { architecture: "source", signed: false }],
    ["LICENSE", { architecture: "text", signed: false }],
    ["NOTICE", { architecture: "text", signed: false }],
    ["THIRD_PARTY_NOTICES.md", { architecture: "text", signed: false }],
    ["COMPATIBILITY.md", { architecture: "text", signed: false }],
  ]);
  const entries = new Map();
  for (const artifact of payload.artifacts) {
    assertObject(artifact, "artifact");
    if (
      typeof artifact.name !== "string"
      || basename(artifact.name) !== artifact.name
      || entries.has(artifact.name)
    ) {
      throw new Error("artifact names must be unique plain filenames");
    }
    if (artifact.version !== payload.version) {
      throw new Error(`${artifact.name} version does not match release`);
    }
    if (!SHA256_PATTERN.test(artifact.sha256)) {
      throw new Error(`${artifact.name} has an invalid SHA-256 digest`);
    }
    entries.set(artifact.name, artifact);
  }

  for (const [name, expected] of requiredArtifacts) {
    const artifact = entries.get(name);
    if (!artifact) {
      throw new Error(`required artifact ${name} is missing`);
    }
    if (artifact.architecture !== expected.architecture) {
      if (name === "Relay.dmg" || name === "relay-bridge-arm64") {
        throw new Error(`${name} must be Apple silicon arm64`);
      }
      throw new Error(`${name} has an unexpected architecture`);
    }
    if (artifact.signed !== expected.signed) {
      if (expected.signed) {
        throw new Error(`${name} must be signed`);
      }
      throw new Error(`${name} must not claim a code signature`);
    }
  }

  const artifactRoot = resolve(artifactsDirectory);
  for (const [name, artifact] of entries) {
    const file = join(artifactRoot, name);
    await access(file);
    const digest = createHash("sha256")
      .update(await readFile(file))
      .digest("hex");
    if (digest !== artifact.sha256) {
      throw new Error(`digest mismatch for ${name}`);
    }
  }

  if (verifyApkSignature) {
    verifyAndroidSignature(join(artifactRoot, payload.watch.artifact));
  }
  return payload;
}

function assertReleaseShape(payload, expectedTag) {
  if (
    payload.schemaVersion !== 1
    || typeof payload.version !== "string"
    || !VERSION_PATTERN.test(payload.version)
    || payload.tag !== `v${payload.version}`
    || payload.tag !== expectedTag
  ) {
    throw new Error("release tag does not match the expected tag and version");
  }
  if (payload.license !== "Apache-2.0") {
    throw new Error("release license must be Apache-2.0");
  }
  assertObject(payload.mac, "Mac release metadata");
  if (
    payload.mac.version !== payload.version
    || payload.mac.artifact !== "Relay.dmg"
  ) {
    throw new Error("Mac version or artifact does not match the release");
  }
  if (payload.mac.architecture !== "arm64") {
    throw new Error("Mac release must be Apple silicon arm64");
  }
  assertObject(payload.watch, "watch release metadata");
  if (
    payload.watch.versionName !== payload.version
    || payload.watch.artifact !== "relay-wear.apk"
    || !Number.isSafeInteger(payload.watch.versionCode)
    || payload.watch.versionCode < 1
    || payload.watch.minimumWearOS !== 4
  ) {
    throw new Error("watch version, version code, artifact, or Wear OS floor is invalid");
  }
  assertObject(payload.codex, "Codex compatibility metadata");
  if (
    !CODEX_RANGE_PATTERN.test(payload.codex.minimumVersion)
    || !CODEX_RANGE_PATTERN.test(payload.codex.maximumVersion)
  ) {
    throw new Error("Codex compatibility range is invalid");
  }
  if (!Array.isArray(payload.artifacts)) {
    throw new Error("release artifacts must be an array");
  }
}

function normalizePublicKey(publicKey) {
  if (publicKey && typeof publicKey === "object" && publicKey.type === "public") {
    return publicKey;
  }
  const raw = Buffer.isBuffer(publicKey)
    ? publicKey
    : decodeBase64(publicKey, "trusted release public key");
  if (raw.length !== 32) {
    throw new Error("trusted release public key must be a raw 32-byte Ed25519 key");
  }
  return createPublicKey({
    key: Buffer.concat([ED25519_SPKI_PREFIX, raw]),
    format: "der",
    type: "spki",
  });
}

function decodeBase64(value, label) {
  if (typeof value !== "string" || value.length === 0) {
    throw new Error(`${label} is missing`);
  }
  const decoded = Buffer.from(value, "base64");
  if (
    decoded.length === 0
    || decoded.toString("base64").replace(/=+$/, "")
      !== value.replace(/=+$/, "")
  ) {
    throw new Error(`${label} is not valid base64`);
  }
  return decoded;
}

function verifyAndroidSignature(apkPath) {
  const result = spawnSync(
    process.env.APKSIGNER_PATH ?? "apksigner",
    ["verify", "--verbose", "--print-certs", apkPath],
    { encoding: "utf8" },
  );
  if (result.status !== 0) {
    throw new Error("relay-wear.apk Android signature verification failed");
  }
}

function sortRecursively(value) {
  if (Array.isArray(value)) {
    return value.map(sortRecursively);
  }
  if (value && typeof value === "object") {
    return Object.fromEntries(
      Object.keys(value)
        .sort()
        .map((key) => [key, sortRecursively(value[key])]),
    );
  }
  return value;
}

function assertObject(value, label) {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new Error(`${label} must be an object`);
  }
}

function option(args, name) {
  const index = args.indexOf(name);
  if (index < 0 || !args[index + 1]) {
    throw new Error(`missing required option ${name}`);
  }
  return args[index + 1];
}

async function main() {
  const args = process.argv.slice(2);
  const manifestPath = option(args, "--manifest");
  const artifactsDirectory = option(args, "--artifacts");
  const expectedTag = option(args, "--tag");
  const publicKeyBase64 = process.env.RELAY_RELEASE_PUBLIC_KEY_BASE64
    ?? option(args, "--public-key-base64");
  const payload = await verifyRelease({
    manifestPath,
    artifactsDirectory,
    expectedTag,
    publicKey: publicKeyBase64,
    verifyApkSignature: args.includes("--verify-apk-signature"),
  });
  process.stdout.write(
    `Verified Relay ${payload.version} (${payload.artifacts.length} artifacts).\n`,
  );
}

if (
  process.argv[1]
  && import.meta.url === pathToFileURL(resolve(process.argv[1])).href
) {
  main().catch((error) => {
    process.stderr.write(`Release verification failed: ${error.message}\n`);
    process.exitCode = 1;
  });
}
