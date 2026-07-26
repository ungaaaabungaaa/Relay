import { writeFile } from "node:fs/promises";

const outputPath = process.argv[2];
if (!outputPath) {
  throw new Error("Usage: render-worker-secrets.mjs OUTPUT_PATH");
}

const secretNames = [
  "JWT_SECRET",
  "PII_ENCRYPTION_KEY",
  "EMAIL_HMAC_KEY",
  "RATE_LIMIT_HMAC_KEY",
  "RESEND_API_KEY",
  "CLOUD_ADMIN_CREDENTIAL",
];

const secrets = Object.fromEntries(secretNames.map((name) => {
  const value = process.env[name]?.trim();
  if (!value) throw new Error(`Missing ${name}`);
  return [name, value];
}));

await writeFile(outputPath, `${JSON.stringify(secrets)}\n`, { mode: 0o600 });
