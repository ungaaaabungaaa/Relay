import { mkdirSync } from "node:fs";
import { dirname } from "node:path";
import { DatabaseSync } from "node:sqlite";
import type { PairingCode, SecurityStore, StoredDevice } from "../security/store.ts";

export class SqliteStore implements SecurityStore {
  private readonly db: DatabaseSync;

  constructor(path: string) {
    mkdirSync(dirname(path), { recursive: true, mode: 0o700 });
    this.db = new DatabaseSync(path);
    this.db.exec(`
      PRAGMA journal_mode = WAL;
      CREATE TABLE IF NOT EXISTS devices (
        id TEXT PRIMARY KEY, name TEXT NOT NULL, public_key TEXT NOT NULL,
        created_at INTEGER NOT NULL, revoked_at INTEGER
      );
      CREATE TABLE IF NOT EXISTS pairing_codes (
        code TEXT PRIMARY KEY, expires_at INTEGER NOT NULL, used INTEGER NOT NULL DEFAULT 0
      );
      CREATE TABLE IF NOT EXISTS nonces (
        device_id TEXT NOT NULL, nonce TEXT NOT NULL, created_at INTEGER NOT NULL,
        PRIMARY KEY (device_id, nonce)
      );
      CREATE TABLE IF NOT EXISTS audit (
        id INTEGER PRIMARY KEY AUTOINCREMENT, device_id TEXT, action TEXT NOT NULL,
        target TEXT, result TEXT NOT NULL, created_at INTEGER NOT NULL
      );
    `);
  }

  addDevice(id: string, publicKey: string, name = "Relay Watch", now = Date.now()) {
    this.db
      .prepare("INSERT INTO devices(id,name,public_key,created_at) VALUES(?,?,?,?)")
      .run(id, name, publicKey, now);
    return { id, name, publicKey, createdAt: now, revokedAt: null };
  }

  getDevice(id: string): StoredDevice | undefined {
    const row = this.db
      .prepare("SELECT id,name,public_key,created_at,revoked_at FROM devices WHERE id=?")
      .get(id) as
      | { id: string; name: string; public_key: string; created_at: number; revoked_at: number | null }
      | undefined;
    return row
      ? {
          id: row.id,
          name: row.name,
          publicKey: row.public_key,
          createdAt: row.created_at,
          revokedAt: row.revoked_at,
        }
      : undefined;
  }

  consumeNonce(deviceId: string, nonce: string, now = Date.now()) {
    try {
      this.db
        .prepare("INSERT INTO nonces(device_id,nonce,created_at) VALUES(?,?,?)")
        .run(deviceId, nonce, now);
      this.db.prepare("DELETE FROM nonces WHERE created_at < ?").run(now - 600_000);
      return true;
    } catch {
      return false;
    }
  }

  revokeDevice(id: string, now = Date.now()) {
    this.db.prepare("UPDATE devices SET revoked_at=? WHERE id=?").run(now, id);
  }

  savePairingCode(code: string, expiresAt: number) {
    this.db
      .prepare("INSERT OR REPLACE INTO pairing_codes(code,expires_at,used) VALUES(?,?,0)")
      .run(code, expiresAt);
  }

  consumePairingCode(code: string): PairingCode | undefined {
    this.db.exec("BEGIN IMMEDIATE");
    try {
      const row = this.db
        .prepare("SELECT expires_at,used FROM pairing_codes WHERE code=?")
        .get(code) as { expires_at: number; used: number } | undefined;
      if (!row || row.used) {
        this.db.exec("ROLLBACK");
        return undefined;
      }
      this.db.prepare("UPDATE pairing_codes SET used=1 WHERE code=?").run(code);
      this.db.exec("COMMIT");
      return { expiresAt: row.expires_at, used: false };
    } catch (error) {
      this.db.exec("ROLLBACK");
      throw error;
    }
  }

  audit(deviceId: string | null, action: string, target: string | null, result: string) {
    this.db
      .prepare("INSERT INTO audit(device_id,action,target,result,created_at) VALUES(?,?,?,?,?)")
      .run(deviceId, action, target, result, Date.now());
  }

  listDevices(): StoredDevice[] {
    const rows = this.db
      .prepare("SELECT id,name,public_key,created_at,revoked_at FROM devices ORDER BY created_at DESC")
      .all() as Array<{
      id: string;
      name: string;
      public_key: string;
      created_at: number;
      revoked_at: number | null;
    }>;
    return rows.map((row) => ({
      id: row.id,
      name: row.name,
      publicKey: row.public_key,
      createdAt: row.created_at,
      revokedAt: row.revoked_at,
    }));
  }
}
