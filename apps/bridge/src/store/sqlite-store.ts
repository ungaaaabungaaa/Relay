import { mkdirSync } from "node:fs";
import { dirname } from "node:path";
import { DatabaseSync } from "node:sqlite";
import type {
  DeviceMetadata,
  PairingCode,
  SecurityStore,
  StoredDevice,
  StoredPairingSession,
} from "../security/store.ts";

export class SqliteStore implements SecurityStore {
  private readonly db: DatabaseSync;

  constructor(path: string) {
    mkdirSync(dirname(path), { recursive: true, mode: 0o700 });
    this.db = new DatabaseSync(path);
    this.db.exec(`
      PRAGMA journal_mode = WAL;
      CREATE TABLE IF NOT EXISTS devices (
        id TEXT PRIMARY KEY, name TEXT NOT NULL, public_key TEXT NOT NULL,
        created_at INTEGER NOT NULL, revoked_at INTEGER, metadata_json TEXT
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
      CREATE TABLE IF NOT EXISTS action_results (
        device_id TEXT NOT NULL, idempotency_key TEXT NOT NULL,
        action TEXT NOT NULL, target TEXT, status TEXT NOT NULL,
        response_json TEXT, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL,
        PRIMARY KEY (device_id, idempotency_key)
      );
      CREATE TABLE IF NOT EXISTS pairing_sessions (
        id TEXT PRIMARY KEY, token_hash TEXT NOT NULL UNIQUE,
        session_json TEXT NOT NULL
      );
    `);
    const deviceColumns = this.db
      .prepare("PRAGMA table_info(devices)")
      .all() as Array<{ name: string }>;
    if (!deviceColumns.some((column) => column.name === "metadata_json")) {
      this.db.exec("ALTER TABLE devices ADD COLUMN metadata_json TEXT");
    }
  }

  addDevice(
    id: string,
    publicKey: string,
    name = "Relay Watch",
    now = Date.now(),
    metadata?: DeviceMetadata,
  ) {
    this.db
      .prepare(
        "INSERT INTO devices(id,name,public_key,created_at,metadata_json) VALUES(?,?,?,?,?)",
      )
      .run(id, name, publicKey, now, metadata ? JSON.stringify(metadata) : null);
    return {
      id,
      name,
      publicKey,
      ...(metadata ? { metadata } : {}),
      createdAt: now,
      revokedAt: null,
    };
  }

  getDevice(id: string): StoredDevice | undefined {
    const row = this.db
      .prepare(
        "SELECT id,name,public_key,created_at,revoked_at,metadata_json FROM devices WHERE id=?",
      )
      .get(id) as
      | {
          id: string;
          name: string;
          public_key: string;
          created_at: number;
          revoked_at: number | null;
          metadata_json: string | null;
        }
      | undefined;
    return row
      ? {
          id: row.id,
          name: row.name,
          publicKey: row.public_key,
          ...(row.metadata_json
            ? { metadata: JSON.parse(row.metadata_json) as DeviceMetadata }
            : {}),
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

  replacePairingSession(session: StoredPairingSession) {
    this.db.exec("BEGIN IMMEDIATE");
    try {
      this.db.exec("DELETE FROM pairing_sessions");
      this.db
        .prepare(
          "INSERT INTO pairing_sessions(id,token_hash,session_json) VALUES(?,?,?)",
        )
        .run(session.id, session.tokenHash, JSON.stringify(session));
      this.db.exec("COMMIT");
    } catch (error) {
      this.db.exec("ROLLBACK");
      throw error;
    }
  }

  updatePairingSession(session: StoredPairingSession) {
    this.db
      .prepare(
        "UPDATE pairing_sessions SET token_hash=?,session_json=? WHERE id=?",
      )
      .run(session.tokenHash, JSON.stringify(session), session.id);
  }

  getPairingSessionByTokenHash(tokenHash: string) {
    const row = this.db
      .prepare(
        "SELECT session_json FROM pairing_sessions WHERE token_hash=?",
      )
      .get(tokenHash) as { session_json: string } | undefined;
    return row
      ? JSON.parse(row.session_json) as StoredPairingSession
      : undefined;
  }

  listPairingSessions() {
    const rows = this.db
      .prepare("SELECT session_json FROM pairing_sessions")
      .all() as Array<{ session_json: string }>;
    return rows.map(
      (row) => JSON.parse(row.session_json) as StoredPairingSession,
    );
  }

  getActionResult(deviceId: string, idempotencyKey: string) {
    const row = this.db
      .prepare(
        `SELECT action,target,status,response_json FROM action_results
         WHERE device_id=? AND idempotency_key=?`,
      )
      .get(deviceId, idempotencyKey) as
      | {
          action: string;
          target: string | null;
          status: "pending" | "succeeded" | "failed";
          response_json: string | null;
        }
      | undefined;
    return row
      ? {
          action: row.action,
          target: row.target,
          status: row.status,
          responseJson: row.response_json,
        }
      : undefined;
  }

  claimAction(
    deviceId: string,
    idempotencyKey: string,
    action: string,
    target: string | null,
  ) {
    const now = Date.now();
    try {
      this.db
        .prepare(
          `INSERT INTO action_results(
            device_id,idempotency_key,action,target,status,response_json,created_at,updated_at
          ) VALUES(?,?,?,?,?,?,?,?)`,
        )
        .run(
          deviceId,
          idempotencyKey,
          action,
          target,
          "pending",
          null,
          now,
          now,
        );
      return true;
    } catch {
      return false;
    }
  }

  finishAction(
    deviceId: string,
    idempotencyKey: string,
    status: "succeeded" | "failed",
    responseJson: string | null,
  ) {
    this.db
      .prepare(
        `UPDATE action_results SET status=?,response_json=?,updated_at=?
         WHERE device_id=? AND idempotency_key=?`,
      )
      .run(status, responseJson, Date.now(), deviceId, idempotencyKey);
  }

  audit(deviceId: string | null, action: string, target: string | null, result: string) {
    this.db
      .prepare("INSERT INTO audit(device_id,action,target,result,created_at) VALUES(?,?,?,?,?)")
      .run(deviceId, action, target, result, Date.now());
  }

  listDevices(): StoredDevice[] {
    const rows = this.db
      .prepare(
        "SELECT id,name,public_key,created_at,revoked_at,metadata_json FROM devices ORDER BY created_at DESC",
      )
      .all() as Array<{
      id: string;
      name: string;
      public_key: string;
      created_at: number;
      revoked_at: number | null;
      metadata_json: string | null;
    }>;
    return rows.map((row) => ({
      id: row.id,
      name: row.name,
      publicKey: row.public_key,
      ...(row.metadata_json
        ? { metadata: JSON.parse(row.metadata_json) as DeviceMetadata }
        : {}),
      createdAt: row.created_at,
      revokedAt: row.revoked_at,
    }));
  }
}
