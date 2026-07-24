import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { PairingService } from "../src/security/pairing.ts";
import { InMemorySecurityStore } from "../src/security/store.ts";

describe("watch pairing", () => {
  it("creates a six-character code and consumes it once", () => {
    const store = new InMemorySecurityStore();
    const pairing = new PairingService(store, () => 1_000);
    const code = pairing.createCode();
    assert.match(code, /^[A-Z2-9]{6}$/);
    const device = pairing.exchange(code, "Watch6", "PUBLIC", 2_000);
    assert.equal(device.name, "Watch6");
    assert.throws(() => pairing.exchange(code, "Watch6", "PUBLIC", 2_001), /invalid pairing code/);
  });

  it("rejects an expired code", () => {
    const pairing = new PairingService(new InMemorySecurityStore(), () => 1_000);
    const code = pairing.createCode();
    assert.throws(() => pairing.exchange(code, "Watch6", "PUBLIC", 302_000), /expired pairing code/);
  });
});
