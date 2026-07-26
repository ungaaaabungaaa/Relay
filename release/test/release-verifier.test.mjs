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
import { createReleasePayload } from "../../scripts/create-release-manifest.mjs";

const VERSION = "1.2.3";
const TAG = `v${VERSION}`;

test("accepts a signed, internally consistent Apple silicon release", async () => {
  await withFixture(async ({ directory, manifest, publicKey }) => {
    const generated = await createReleasePayload({
      artifactsDirectory: directory,
      tag: TAG,
      codexMinimumVersion: "0.144.0",
      codexMaximumVersion: "0.144.x",
    });
    const result = await verifyRelease({
      manifest,
      artifactsDirectory: directory,
      expectedTag: TAG,
      publicKey,
    });

    assert.equal(result.version, VERSION);
    assert.equal(result.mac.architecture, "arm64");
    assert.deepEqual(
      generated.artifacts.map(({ name }) => name),
      [
        "Relay.dmg",
        `Relay-${VERSION}.tar.gz`,
        "LICENSE",
        "NOTICE",
        "THIRD_PARTY_NOTICES.md",
        "COMPATIBILITY.md",
      ],
    );
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

test("rejects an unsigned Mac artifact", async () => {
  await withFixture(
    async ({ directory, manifest, publicKey }) => {
      await assert.rejects(
        verifyRelease({
          manifest,
          artifactsDirectory: directory,
          expectedTag: TAG,
          publicKey,
        }),
        /Relay\.dmg must be signed/,
      );
    },
    (payload) => {
      payload.artifacts.find(({ name }) => name === "Relay.dmg").signed =
        false;
    },
  );
});

test("rejects schema version 1", async () => {
  await withFixture(
    async ({ directory, manifest, publicKey }) => {
      await assert.rejects(
        verifyRelease({
          manifest,
          artifactsDirectory: directory,
          expectedTag: TAG,
          publicKey,
        }),
        /unsupported release schema version/,
      );
    },
    (payload) => {
      payload.schemaVersion = 1;
    },
  );
});

test("rejects a seventh release artifact", async () => {
  await withFixture(
    async ({ directory, manifest, publicKey }) => {
      await assert.rejects(
        verifyRelease({
          manifest,
          artifactsDirectory: directory,
          expectedTag: TAG,
          publicKey,
        }),
        /exactly six artifacts/,
      );
    },
    (payload) => {
      payload.artifacts.push({
        name: "unexpected.txt",
        version: VERSION,
        architecture: "text",
        sha256: "0".repeat(64),
        signed: false,
      });
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
    manifest.payload.mac.version = "9.9.9";

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
        signed: name === "Relay.dmg",
      });
    }
    const payload = {
      schemaVersion: 2,
      tag: TAG,
      version: VERSION,
      license: "Apache-2.0",
      mac: {
        version: VERSION,
        artifact: "Relay.dmg",
        architecture: "arm64",
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
  if (name === "Relay.dmg") {
    return "arm64";
  }
  if (name.endsWith(".tar.gz")) {
    return "source";
  }
  return "text";
}

function sha256(data) {
  return createHash("sha256").update(data).digest("hex");
}
