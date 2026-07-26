import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

test("consumer builds use the permanent Relay product identifiers", async () => {
  const wear = await readFile(
    new URL("../../wear/build.gradle.kts", import.meta.url),
    "utf8",
  );
  const macPackaging = await readFile(
    new URL("../../scripts/package-mac-app.sh", import.meta.url),
    "utf8",
  );

  assert.match(wear, /applicationId = "com\.relayforcodex\.wear"/);
  assert.match(macPackaging, /com\.relayforcodex\.mac/);
  assert.doesNotMatch(wear, /applicationId = "dev\.ungaaaabungaaa\.relay"/);
  assert.doesNotMatch(macPackaging, /Resources\/relay-wear\.apk/);
  assert.doesNotMatch(macPackaging, /cp .*relay-wear\.apk/);
  assert.doesNotMatch(macPackaging, /NSBonjourServices/);
  assert.doesNotMatch(macPackaging, /NSLocalNetworkUsageDescription/);
});
