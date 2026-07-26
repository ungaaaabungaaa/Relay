#!/usr/bin/env node

import {
  createHash,
  createPublicKey,
  verify,
} from "node:crypto";
import { access, readFile } from "node:fs/promises";
import { basename, join, resolve } from "node:path";
import { pathToFileURL } from "node:url";

const ED25519_SPKI_PREFIX = Buffer.from("302a300506032b6570032100", "hex");
const SHA256_PATTERN = /^[a-f0-9]{64}$/;
const SEMVER_CORE_IDENTIFIER = "(?:0|[1-9][0-9]*)";
const SEMVER_PRERELEASE_IDENTIFIER =
  "(?:0|[1-9][0-9]*|[0-9A-Za-z-]*[A-Za-z-][0-9A-Za-z-]*)";
const RELEASE_VERSION_SOURCE =
  `${SEMVER_CORE_IDENTIFIER}\\.${SEMVER_CORE_IDENTIFIER}`
  + `\\.${SEMVER_CORE_IDENTIFIER}`
  + `(?:-${SEMVER_PRERELEASE_IDENTIFIER}`
  + `(?:\\.${SEMVER_PRERELEASE_IDENTIFIER})*)?`;
export const RELEASE_VERSION_PATTERN = new RegExp(`^${RELEASE_VERSION_SOURCE}$`);
export const RELEASE_TAG_PATTERN = new RegExp(`^v${RELEASE_VERSION_SOURCE}$`);
const CODEX_RANGE_PATTERN = /^\d+\.\d+\.(?:\d+|x)$/;
const RELEASE_MANIFEST_PROPERTIES = new Set(["payload", "signature"]);
const RELEASE_PAYLOAD_PROPERTIES = new Set([
  "schemaVersion",
  "tag",
  "version",
  "license",
  "mac",
  "codex",
  "artifacts",
]);
const RELEASE_MAC_PROPERTIES = new Set([
  "version",
  "artifact",
  "architecture",
]);
const RELEASE_CODEX_PROPERTIES = new Set([
  "minimumVersion",
  "maximumVersion",
]);
const RELEASE_ARTIFACT_PROPERTIES = new Set([
  "name",
  "version",
  "architecture",
  "sha256",
  "signed",
]);

export function canonicalizeManifestPayload(payload) {
  return JSON.stringify(sortRecursively(payload));
}

export async function verifyRelease({
  manifest,
  manifestPath,
  artifactsDirectory,
  expectedTag,
  publicKey,
}) {
  const providedManifest = manifest
    ?? JSON.parse(await readFile(manifestPath, "utf8"));
  const loadedManifest = snapshotReleaseManifest(providedManifest);
  assertRawReleaseShape(loadedManifest);
  const trustedPublicKey = normalizePublicKey(publicKey);
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
      if (name === "Relay.dmg") {
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
  if (entries.size !== requiredArtifacts.size) {
    throw new Error("release must contain exactly six artifacts");
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

  return payload;
}

function assertReleaseShape(payload, expectedTag) {
  if (payload.schemaVersion !== 2) {
    throw new Error("unsupported release schema version");
  }
  if (
    typeof payload.version !== "string"
    || !RELEASE_VERSION_PATTERN.test(payload.version)
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

function assertRawReleaseShape(manifest) {
  assertExactOwnProperties(
    manifest,
    RELEASE_MANIFEST_PROPERTIES,
    "release manifest",
  );
  const payload = manifest.payload;
  assertExactOwnProperties(
    payload,
    RELEASE_PAYLOAD_PROPERTIES,
    "release payload",
  );
  assertExactOwnProperties(
    payload.mac,
    RELEASE_MAC_PROPERTIES,
    "Mac release metadata",
  );
  assertExactOwnProperties(
    payload.codex,
    RELEASE_CODEX_PROPERTIES,
    "Codex compatibility metadata",
  );
  if (!Array.isArray(payload.artifacts)) {
    throw new Error("release artifacts must be an array");
  }
  for (const artifact of payload.artifacts) {
    assertExactOwnProperties(
      artifact,
      RELEASE_ARTIFACT_PROPERTIES,
      "release artifact",
    );
  }
}

function assertExactOwnProperties(value, expectedProperties, label) {
  assertObject(value, label);
  const ownProperties = Object.keys(value);
  const unsupportedProperty = ownProperties.find(
    (property) => !expectedProperties.has(property),
  );
  if (unsupportedProperty) {
    throw new Error(`unsupported ${label} property ${unsupportedProperty}`);
  }
  const missingProperty = [...expectedProperties].find(
    (property) => (
      !Object.hasOwn(value, property)
      || !ownProperties.includes(property)
    ),
  );
  if (missingProperty) {
    throw new Error(`${label} property ${missingProperty} is missing`);
  }
}

function snapshotReleaseManifest(manifest) {
  try {
    // Capture each own value once so accessors cannot swap the signed payload.
    return snapshotJSONValue(manifest, new Set());
  } catch {
    throw new Error("release manifest must contain only plain JSON data");
  }
}

function snapshotJSONValue(value, ancestors) {
  if (
    value === null
    || typeof value === "string"
    || typeof value === "boolean"
  ) {
    return value;
  }
  if (typeof value === "number" && Number.isFinite(value)) {
    return value;
  }
  if (!value || typeof value !== "object" || ancestors.has(value)) {
    throw new Error("value is not plain JSON data");
  }

  ancestors.add(value);
  try {
    const descriptors = Object.getOwnPropertyDescriptors(value);
    if (Array.isArray(value)) {
      return snapshotJSONArray(descriptors, ancestors);
    }
    const snapshot = {};
    for (const property of Reflect.ownKeys(descriptors)) {
      const descriptor = descriptors[property];
      if (
        typeof property !== "string"
        || !descriptor.enumerable
        || !Object.hasOwn(descriptor, "value")
      ) {
        throw new Error("object properties must be enumerable data properties");
      }
      Object.defineProperty(snapshot, property, {
        configurable: true,
        enumerable: true,
        value: snapshotJSONValue(descriptor.value, ancestors),
        writable: true,
      });
    }
    return snapshot;
  } finally {
    ancestors.delete(value);
  }
}

function snapshotJSONArray(descriptors, ancestors) {
  const lengthDescriptor = descriptors.length;
  if (
    !lengthDescriptor
    || !Object.hasOwn(lengthDescriptor, "value")
    || !Number.isSafeInteger(lengthDescriptor.value)
    || lengthDescriptor.value < 0
  ) {
    throw new Error("array length must be a data property");
  }

  const length = lengthDescriptor.value;
  const ownProperties = Reflect.ownKeys(descriptors);
  if (
    ownProperties.length !== length + 1
    || ownProperties.some((property) => (
      typeof property !== "string"
      || (
        property !== "length"
        && !isArrayIndex(property, length)
      )
    ))
  ) {
    throw new Error("arrays must be dense and contain no custom properties");
  }

  const snapshot = [];
  for (let index = 0; index < length; index += 1) {
    const descriptor = descriptors[String(index)];
    if (
      !descriptor
      || !descriptor.enumerable
      || !Object.hasOwn(descriptor, "value")
    ) {
      throw new Error("array elements must be enumerable data properties");
    }
    snapshot.push(snapshotJSONValue(descriptor.value, ancestors));
  }
  return snapshot;
}

function isArrayIndex(property, length) {
  if (!/^(?:0|[1-9][0-9]*)$/.test(property)) {
    return false;
  }
  const index = Number(property);
  return Number.isSafeInteger(index) && index < length;
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
