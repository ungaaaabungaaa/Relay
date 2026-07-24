import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { readCodexVersion } from "../src/index.ts";

describe("readCodexVersion", () => {
  it("extracts the semantic version from Codex CLI output", () => {
    assert.deepEqual(readCodexVersion("codex-cli 0.144.5"), {
      raw: "codex-cli 0.144.5",
      semver: "0.144.5",
    });
  });

  it("rejects output without a semantic version", () => {
    assert.throws(
      () => readCodexVersion("codex-cli unknown"),
      "Unsupported Codex version output",
    );
  });
});
