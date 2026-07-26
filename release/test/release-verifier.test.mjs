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
  RELEASE_TAG_PATTERN,
  RELEASE_VERSION_PATTERN,
  verifyRelease,
} from "../../scripts/verify-release.mjs";
import { createReleasePayload } from "../../scripts/create-release-manifest.mjs";

const VERSION = "1.2.3";
const TAG = `v${VERSION}`;
const REQUIRED_ARTIFACT_NAMES = [
  "Relay.dmg",
  `Relay-${VERSION}.tar.gz`,
  "LICENSE",
  "NOTICE",
  "THIRD_PARTY_NOTICES.md",
  "COMPATIBILITY.md",
];
const INVALID_RELEASE_VERSIONS = [
  "1.0",
  "1..0",
  "1.0.0.0",
  "1.nope.0",
  "01.0.0",
  "1.0.0-beta..1",
  "1.0.0-beta.01",
  "1.0.0-",
  "1.0.0+build",
];
const VALID_RELEASE_VERSIONS = [
  "0.0.0",
  "1.0.0",
  "1.0.0-0",
  "1.0.0-beta",
  "1.0.0-beta.10",
  "1.0.0-0alpha",
];

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
      REQUIRED_ARTIFACT_NAMES,
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

test("manifest creation rejects malformed release versions", async () => {
  await withFixture(async ({ directory }) => {
    for (const version of INVALID_RELEASE_VERSIONS) {
      await assert.rejects(
        createReleasePayload({
          artifactsDirectory: directory,
          tag: `v${version}`,
          codexMinimumVersion: "0.144.0",
          codexMaximumVersion: "0.144.x",
        }),
        /tag must use strict SemVer/,
      );
    }
  });
});

test("runtime and JSON Schema use the same strict release SemVer grammar", async () => {
  const schema = JSON.parse(
    await readFile(
      new URL("../release-manifest.schema.json", import.meta.url),
      "utf8",
    ),
  );
  const schemaVersionPattern = new RegExp(
    schema.$defs.releaseVersion.pattern,
  );
  const schemaTagPattern = new RegExp(schema.$defs.releaseTag.pattern);
  const schemaSourcePattern = new RegExp(
    schema.$defs.sourceArtifactName.pattern,
  );

  for (const version of VALID_RELEASE_VERSIONS) {
    assert.equal(RELEASE_VERSION_PATTERN.test(version), true, version);
    assert.equal(RELEASE_TAG_PATTERN.test(`v${version}`), true, version);
    assert.equal(schemaVersionPattern.test(version), true, version);
    assert.equal(schemaTagPattern.test(`v${version}`), true, version);
    assert.equal(
      schemaSourcePattern.test(`Relay-${version}.tar.gz`),
      true,
      version,
    );
  }
  for (const version of INVALID_RELEASE_VERSIONS) {
    assert.equal(RELEASE_VERSION_PATTERN.test(version), false, version);
    assert.equal(RELEASE_TAG_PATTERN.test(`v${version}`), false, version);
    assert.equal(schemaVersionPattern.test(version), false, version);
    assert.equal(schemaTagPattern.test(`v${version}`), false, version);
    assert.equal(
      schemaSourcePattern.test(`Relay-${version}.tar.gz`),
      false,
      version,
    );
  }
});

for (const version of INVALID_RELEASE_VERSIONS) {
  test(`release verification rejects malformed version ${version}`, async () => {
    await withFixture(
      async ({ directory, manifest, publicKey }) => {
        await assert.rejects(
          verifyRelease({
            manifest,
            artifactsDirectory: directory,
            expectedTag: `v${version}`,
            publicKey,
          }),
          /release tag does not match the expected tag and version/,
        );
      },
      (payload) => setPayloadVersion(payload, version),
    );
  });
}

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

test("rejects a signed payload containing the retired watch key", async () => {
  await withFixture(
    async ({ directory, manifest, publicKey }) => {
      await assert.rejects(
        verifyRelease({
          manifest,
          artifactsDirectory: directory,
          expectedTag: TAG,
          publicKey,
        }),
        /unsupported release payload property watch/,
      );
    },
    (payload) => {
      payload.watch = {
        artifact: "retired-watch-package",
      };
    },
  );
});

test("rejects an unsigned envelope property added after signing", async () => {
  await withFixture(async ({ directory, manifest, publicKey }) => {
    manifest.releaseChannel = "retired";

    await assert.rejects(
      verifyRelease({
        manifest,
        artifactsDirectory: directory,
        expectedTag: TAG,
        publicKey,
      }),
      /unsupported release manifest property releaseChannel/,
    );
  });
});

test("rejects an inherited required envelope property", async () => {
  await withFixture(async ({ directory, manifest, publicKey }) => {
    const inheritedSignatureManifest = Object.assign(
      Object.create({ signature: manifest.signature }),
      { payload: manifest.payload },
    );

    await assert.rejects(
      verifyRelease({
        manifest: inheritedSignatureManifest,
        artifactsDirectory: directory,
        expectedTag: TAG,
        publicKey,
      }),
      /release manifest property signature is missing/,
    );
  });
});

test("rejects accessor-backed manifests before signature verification", async () => {
  await withFixture(async ({ directory, manifest, publicKey }) => {
    const signedPayload = manifest.payload;
    const tamperedPayload = structuredClone(signedPayload);
    tamperedPayload.codex.minimumVersion = "9.9.9";
    let payloadReads = 0;
    const accessorManifest = { signature: manifest.signature };
    Object.defineProperty(accessorManifest, "payload", {
      enumerable: true,
      get() {
        payloadReads += 1;
        return payloadReads < 3 ? signedPayload : tamperedPayload;
      },
    });

    await assert.rejects(
      verifyRelease({
        manifest: accessorManifest,
        artifactsDirectory: directory,
        expectedTag: TAG,
        publicKey,
      }),
      /release manifest must contain only plain JSON data/,
    );
    assert.equal(payloadReads, 0);
  });
});

test("rejects a Mac property added after signing", async () => {
  await withFixture(async ({ directory, manifest, publicKey }) => {
    manifest.payload.mac.minimumSystemVersion = "14.0";

    await assert.rejects(
      verifyRelease({
        manifest,
        artifactsDirectory: directory,
        expectedTag: TAG,
        publicKey,
      }),
      /unsupported Mac release metadata property minimumSystemVersion/,
    );
  });
});

test("rejects a signed payload containing an unknown Codex property", async () => {
  await withFixture(
    async ({ directory, manifest, publicKey }) => {
      await assert.rejects(
        verifyRelease({
          manifest,
          artifactsDirectory: directory,
          expectedTag: TAG,
          publicKey,
        }),
        /unsupported Codex compatibility metadata property channel/,
      );
    },
    (payload) => {
      payload.codex.channel = "stable";
    },
  );
});

test("rejects a signed payload containing an unknown artifact property", async () => {
  await withFixture(
    async ({ directory, manifest, publicKey }) => {
      await assert.rejects(
        verifyRelease({
          manifest,
          artifactsDirectory: directory,
          expectedTag: TAG,
          publicKey,
        }),
        /unsupported release artifact property downloadURL/,
      );
    },
    (payload) => {
      payload.artifacts[0].downloadURL = "https://example.invalid/Relay.dmg";
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

test("rejects duplicate release artifact names", async () => {
  await withFixture(
    async ({ directory, manifest, publicKey }) => {
      await assert.rejects(
        verifyRelease({
          manifest,
          artifactsDirectory: directory,
          expectedTag: TAG,
          publicKey,
        }),
        /artifact names must be unique/,
      );
    },
    (payload) => {
      payload.artifacts[payload.artifacts.length - 1] = {
        ...payload.artifacts.find(({ name }) => name === "LICENSE"),
      };
    },
  );
});

test("rejects a wrong artifact name in a six-entry release", async () => {
  await withFixture(
    async ({ directory, manifest, publicKey }) => {
      await assert.rejects(
        verifyRelease({
          manifest,
          artifactsDirectory: directory,
          expectedTag: TAG,
          publicKey,
        }),
        /required artifact COMPATIBILITY\.md is missing/,
      );
    },
    (payload) => {
      payload.artifacts.find(
        ({ name }) => name === "COMPATIBILITY.md",
      ).name = "README.md";
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

function setPayloadVersion(payload, version) {
  payload.tag = `v${version}`;
  payload.version = version;
  payload.mac.version = version;
  for (const artifact of payload.artifacts) {
    artifact.version = version;
    if (artifact.name.endsWith(".tar.gz")) {
      artifact.name = `Relay-${version}.tar.gz`;
    }
  }
}
