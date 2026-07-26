import { readFile, writeFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const outputPath = process.argv[2];
if (!outputPath) {
  throw new Error("Usage: render-wrangler-config.mjs OUTPUT_PATH");
}

const required = (name) => {
  const value = process.env[name]?.trim();
  if (!value) throw new Error(`Missing ${name}`);
  return value;
};

const environmentName = required("RELAY_CLOUD_ENV");
if (!["staging", "production"].includes(environmentName)) {
  throw new Error("RELAY_CLOUD_ENV must be staging or production");
}
const databaseId = required("RELAY_CLOUDFLARE_D1_DATABASE_ID");
if (!/^[a-f0-9-]{32,36}$/i.test(databaseId)) {
  throw new Error("Invalid RELAY_CLOUDFLARE_D1_DATABASE_ID");
}
const databaseName = required("RELAY_CLOUDFLARE_D1_DATABASE_NAME");
const apiHost = required("RELAY_API_HOST");
const publicHost = required("RELAY_PUBLIC_HOST");
const appDirectory = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const base = JSON.parse(
  await readFile(resolve(appDirectory, "wrangler.jsonc"), "utf8"),
);

delete base.$schema;
base.name = environmentName === "production"
  ? "relay-cloud"
  : `relay-cloud-${environmentName}`;
base.main = resolve(appDirectory, "src/index.ts");
base.vars.PUBLIC_ORIGIN = `https://${publicHost}`;
base.d1_databases = [
  {
    binding: "DB",
    database_name: databaseName,
    database_id: databaseId,
    migrations_dir: resolve(appDirectory, "migrations"),
  },
];
base.routes = [
  { pattern: apiHost, custom_domain: true },
  { pattern: publicHost, custom_domain: true },
];

await writeFile(outputPath, `${JSON.stringify(base, null, 2)}\n`, {
  mode: 0o600,
});
