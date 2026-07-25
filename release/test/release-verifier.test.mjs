import {
  createHash,
  generateKeyPairSync,
  sign,
} from "node:crypto";
import {
  mkdtemp,
  mkdir,
  readFile,
  rm,
  writeFile,
} from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import assert from "node:assert/strict";

import {
  canonicalizeManifestPayload,
  verifyRelease,
} from "../../scripts/verify-release.mjs";

const VERSION = "1.2.3";
const TAG = `v${VERSION}`;

test("accepts a signed, internally consistent Apple silicon release", async () => {
  await withFixture(async ({ directory, manifest, publicKey }) => {
    const result = await verifyRelease({
      manifest,
      artifactsDirectory: directory,
      expectedTag: TAG,
      publicKey,
    });

    assert.equal(result.version, VERSION);
    assert.equal(result.mac.architecture, "arm64");
    assert.equal(result.watch.versionName, VERSION);
    assert.deepEqual(result.codex, {
      minimumVersion: "0.144.0",
      maximumVersion: "0.144.x",
    });
  });
});

test("rejects an artifact changed after the manifest was signed", async () => {
  await withFixture(async ({ directory, manifest, publicKey }) => {
    await writeFile(join(directory, "Relay.dmg"), "changed byte");

    await assert.rejects(
      verifyRelease({
        manifest,
        artifactsDirectory: directory,
        expectedTag: TAG,
        publicKey,
      }),
      /digest mismatch for Relay\.dmg/,
    );
  });
});

test("rejects a tag that does not match the release version", async () => {
  await withFixture(async ({ directory, manifest, publicKey }) => {
    await assert.rejects(
      verifyRelease({
        manifest,
        artifactsDirectory: directory,
        expectedTag: "v1.2.4",
        publicKey,
      }),
      /tag does not match/,
    );
  });
});

test("rejects an Intel Mac artifact", async () => {
  await withFixture(
    async ({ directory, manifest, publicKey }) => {
      await assert.rejects(
        verifyRelease({
          manifest,
          artifactsDirectory: directory,
          expectedTag: TAG,
          publicKey,
        }),
        /Apple silicon arm64/,
      );
    },
    (payload) => {
      payload.mac.architecture = "x86_64";
      payload.artifacts.find(({ name }) => name === "Relay.dmg").architecture =
        "x86_64";
    },
  );
});

test("rejects an APK that is not marked as signed", async () => {
  await withFixture(
    async ({ directory, manifest, publicKey }) => {
      await assert.rejects(
        verifyRelease({
          manifest,
          artifactsDirectory: directory,
          expectedTag: TAG,
          publicKey,
        }),
        /relay-wear\.apk must be signed/,
      );
    },
    (payload) => {
      payload.artifacts.find(
        ({ name }) => name === "relay-wear.apk",
      ).signed = false;
    },
  );
});

test("rejects a release missing the Apache license", async () => {
  await withFixture(
    async ({ directory, manifest, publicKey }) => {
      await assert.rejects(
        verifyRelease({
          manifest,
          artifactsDirectory: directory,
          expectedTag: TAG,
          publicKey,
        }),
        /required artifact LICENSE/,
      );
    },
    (payload) => {
      payload.artifacts = payload.artifacts.filter(
        ({ name }) => name !== "LICENSE",
      );
    },
  );
});

test("rejects a payload changed without a new signature", async () => {
  await withFixture(async ({ directory, manifest, publicKey }) => {
    manifest.payload.watch.versionName = "9.9.9";

    await assert.rejects(
      verifyRelease({
        manifest,
        artifactsDirectory: directory,
        expectedTag: TAG,
        publicKey,
      }),
      /invalid release signature/,
    );
  });
});

async function withFixture(assertion, mutate = () => {}) {
  const directory = await mkdtemp(join(tmpdir(), "relay-release-"));
  try {
    const files = new Map([
      ["Relay.dmg", "arm64 mac image"],
      ["relay-wear.apk", "signed watch package"],
      ["relay-bridge-arm64", "arm64 bridge"],
      [`Relay-${VERSION}.tar.gz`, "source archive"],
      ["LICENSE", "Apache License Version 2.0"],
      ["NOTICE", "Relay notices"],
      ["THIRD_PARTY_NOTICES.md", "Third-party notices"],
      ["COMPATIBILITY.md", "Compatibility matrix"],
    ]);
    await mkdir(directory, { recursive: true });
    for (const [name, contents] of files) {
      await writeFile(join(directory, name), contents);
    }

    const artifacts = [];
    for (const [name] of files) {
      artifacts.push({
        name,
        version: VERSION,
        architecture: architectureFor(name),
        sha256: sha256(await readFile(join(directory, name))),
        signed: name === "Relay.dmg"
          || name === "relay-wear.apk"
          || name === "relay-bridge-arm64",
      });
    }
    const payload = {
      schemaVersion: 1,
      tag: TAG,
      version: VERSION,
      license: "Apache-2.0",
      mac: {
        version: VERSION,
        artifact: "Relay.dmg",
        architecture: "arm64",
      },
      watch: {
        versionName: VERSION,
        versionCode: 10203,
        artifact: "relay-wear.apk",
        minimumWearOS: 3,
      },
      codex: {
        minimumVersion: "0.144.0",
        maximumVersion: "0.144.x",
      },
      artifacts,
    };
    mutate(payload);
    const { privateKey, publicKey } = generateKeyPairSync("ed25519");
    const signature = sign(
      null,
      Buffer.from(canonicalizeManifestPayload(payload)),
      privateKey,
    );
    const manifest = {
      payload,
      signature: signature.toString("base64"),
    };

    await assertion({ directory, manifest, publicKey });
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
}

function architectureFor(name) {
  if (name === "Relay.dmg" || name === "relay-bridge-arm64") {
    return "arm64";
  }
  if (name === "relay-wear.apk") {
    return "universal";
  }
  if (name.endsWith(".tar.gz")) {
    return "source";
  }
  return "text";
}

function sha256(data) {
  return createHash("sha256").update(data).digest("hex");
}
