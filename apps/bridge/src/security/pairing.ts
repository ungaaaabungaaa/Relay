import { randomBytes, randomUUID } from "node:crypto";
import type { SecurityStore, StoredDevice } from "./store.ts";

const ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";

export class PairingService {
  private readonly store: SecurityStore;
  private readonly now: () => number;

  constructor(
    store: SecurityStore,
    now: () => number = Date.now,
  ) {
    this.store = store;
    this.now = now;
  }

  createCode(): string {
    const bytes = randomBytes(6);
    const code = Array.from(bytes, (value) => ALPHABET[value % ALPHABET.length]).join("");
    this.store.savePairingCode(code, this.now() + 300_000);
    return code;
  }

  exchange(
    code: string,
    name: string,
    publicKey: string,
    now = this.now(),
  ): StoredDevice {
    const stored = this.store.consumePairingCode(code);
    if (!stored) throw new Error("invalid pairing code");
    if (stored.expiresAt < now) throw new Error("expired pairing code");
    return this.store.addDevice(randomUUID(), publicKey, name, now);
  }
}
