#!/usr/bin/env node

import { spawnSync } from "node:child_process";
import { resolve } from "node:path";

const args = process.argv.slice(2);
const apkIndex = args.indexOf("--apk");
if (apkIndex < 0 || !args[apkIndex + 1]) {
  throw new Error("usage: node scripts/scan-apk-secrets.mjs --apk PATH");
}

const apkPath = resolve(args[apkIndex + 1]);
const result = spawnSync("unzip", ["-p", apkPath], {
  encoding: "latin1",
  maxBuffer: 256 * 1024 * 1024,
});
if (result.status !== 0) {
  throw new Error(`could not inspect APK: ${result.stderr.trim()}`);
}

const forbidden = [
  { label: "OpenAI-style secret key", pattern: /\bsk-[A-Za-z0-9_-]{20,}\b/ },
  { label: "PEM private key", pattern: /-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----/ },
  { label: "Relay admin token assignment", pattern: /CODEWATCH_ADMIN_TOKEN=[^\u0000\s]{16,}/ },
  { label: "release private key assignment", pattern: /RELAY_RELEASE_PRIVATE_KEY_BASE64=[A-Za-z0-9+/=]{32,}/ },
];
for (const { label, pattern } of forbidden) {
  if (pattern.test(result.stdout)) {
    throw new Error(`APK secret scan found ${label}`);
  }
}

process.stdout.write(`APK secret scan passed: ${apkPath}\n`);
