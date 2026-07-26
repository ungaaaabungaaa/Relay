import assert from "node:assert/strict";
import { execFile } from "node:child_process";
import { mkdtemp, readFile, rm, stat } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { promisify } from "node:util";
import { test } from "node:test";

const execute = promisify(execFile);

test("renders every Worker secret into a private silent deployment file", async () => {
  const directory = await mkdtemp(join(tmpdir(), "relay-cloud-secrets-"));
  const output = join(directory, "worker-secrets.json");
  const secrets = {
    JWT_SECRET: "jwt-secret-value",
    PII_ENCRYPTION_KEY: "pii-secret-value",
    EMAIL_HMAC_KEY: "email-secret-value",
    RATE_LIMIT_HMAC_KEY: "rate-secret-value",
    RESEND_API_KEY: "resend-secret-value",
    CLOUD_ADMIN_CREDENTIAL: "admin-secret-value",
  };
  try {
    const result = await execute(
      process.execPath,
      [
        new URL("../scripts/render-worker-secrets.mjs", import.meta.url)
          .pathname,
        output,
      ],
      { env: { ...process.env, ...secrets } },
    );
    assert.equal(result.stdout, "");
    assert.equal(result.stderr, "");
    assert.deepEqual(JSON.parse(await readFile(output, "utf8")), secrets);
    assert.equal((await stat(output)).mode & 0o077, 0);
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
});
