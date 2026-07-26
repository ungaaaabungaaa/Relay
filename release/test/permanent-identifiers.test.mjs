import assert from "node:assert/strict";
import { access, readFile } from "node:fs/promises";
import test from "node:test";

test("consumer builds use permanent Apple product identifiers", async () => {
  const [watchProject, macPackaging] = await Promise.all([
    readFile(
      new URL("../../apple-watch/RelayWatch.xcodeproj/project.pbxproj", import.meta.url),
      "utf8",
    ),
    readFile(new URL("../../scripts/package-mac-app.sh", import.meta.url), "utf8"),
  ]);

  assert.match(watchProject, /PRODUCT_BUNDLE_IDENTIFIER = com\.relayforcodex\.watch;/);
  assert.match(watchProject, /WATCHOS_DEPLOYMENT_TARGET = 10\.0;/);
  assert.match(macPackaging, /com\.relayforcodex\.mac/);
  assert.doesNotMatch(macPackaging, /NSBonjourServices/);
  assert.doesNotMatch(macPackaging, /NSLocalNetworkUsageDescription/);

  for (const path of ["../../wear", "../../gradle", "../../gradlew", "../../preview"]) {
    await assert.rejects(access(new URL(path, import.meta.url)), { code: "ENOENT" });
  }
});
