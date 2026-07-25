import assert from "node:assert/strict";
import { generateKeyPairSync } from "node:crypto";
import { readFile, mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { it } from "node:test";
import { PairingSessionService } from "../src/security/pairing-session.ts";
import { SqliteStore } from "../src/store/sqlite-store.ts";

it("persists only hashed pairing secrets and device metadata across bridge restarts", async (context) => {
  const temporary = await mkdtemp(join(tmpdir(), "relay-pairing-store-"));
  context.after(() => rm(temporary, { recursive: true, force: true }));
  const databasePath = join(temporary, "relay.sqlite");
  const now = 50_000;
  const first = new PairingSessionService(
    new SqliteStore(databasePath),
    { now: () => now },
  );
  const session = first.create({
    origin: "https://relay.example.ts.net",
    macName: "Studio Mac",
    macFingerprint: "ABCD:1234",
  });

  const restarted = new PairingSessionService(
    new SqliteStore(databasePath),
    { now: () => now + 1 },
  );
  assert.equal(
    restarted.discover(session.discoveryToken).macFingerprint,
    "ABCD:1234",
  );

  const { publicKey } = generateKeyPairSync("ec", {
    namedCurve: "prime256v1",
  });
  const pending = restarted.submit(
    session.discoveryToken,
    "192.0.2.10",
    {
      code: session.code,
      name: "Pixel Watch",
      publicKey: publicKey.export({ type: "spki", format: "pem" }).toString(),
      metadata: {
        platform: "wear-os",
        manufacturer: "Google",
        model: "Pixel Watch",
        osVersion: "4",
        appVersion: "0.2.0",
        screenShape: "round",
      },
    },
  );

  const approved = restarted.approve(pending.pairingId);
  const reopenedStore = new SqliteStore(databasePath);
  assert.deepEqual(reopenedStore.getDevice(approved.id)?.metadata, {
    platform: "wear-os",
    manufacturer: "Google",
    model: "Pixel Watch",
    osVersion: "4",
    appVersion: "0.2.0",
    screenShape: "round",
  });

  const databaseBytes = await readFile(databasePath);
  assert.equal(databaseBytes.includes(Buffer.from(session.discoveryToken)), false);
  assert.equal(databaseBytes.includes(Buffer.from(session.code)), false);
});
