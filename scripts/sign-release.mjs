#!/usr/bin/env node

import {
  createPrivateKey,
  sign,
} from "node:crypto";
import { readFile, writeFile } from "node:fs/promises";
import { resolve } from "node:path";

import { canonicalizeManifestPayload } from "./verify-release.mjs";

function option(args, name) {
  const index = args.indexOf(name);
  if (index < 0 || !args[index + 1]) {
    throw new Error(`missing required option ${name}`);
  }
  return args[index + 1];
}

async function main() {
  const args = process.argv.slice(2);
  const privateKeyBase64 = process.env.RELAY_RELEASE_PRIVATE_KEY_BASE64;
  if (!privateKeyBase64) {
    throw new Error("RELAY_RELEASE_PRIVATE_KEY_BASE64 is required");
  }
  const privateKey = createPrivateKey({
    key: Buffer.from(privateKeyBase64, "base64"),
    format: "der",
    type: "pkcs8",
  });
  if (privateKey.asymmetricKeyType !== "ed25519") {
    throw new Error("release key must be Ed25519");
  }
  const payload = JSON.parse(
    await readFile(resolve(option(args, "--payload")), "utf8"),
  );
  const signature = sign(
    null,
    Buffer.from(canonicalizeManifestPayload(payload)),
    privateKey,
  );
  const output = resolve(option(args, "--output"));
  await writeFile(
    output,
    `${JSON.stringify(
      { payload, signature: signature.toString("base64") },
      null,
      2,
    )}\n`,
    { mode: 0o644 },
  );
  process.stdout.write(`Signed release manifest for ${payload.tag}.\n`);
}

main().catch((error) => {
  process.stderr.write(`Manifest signing failed: ${error.message}\n`);
  process.exitCode = 1;
});
