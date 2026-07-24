import { randomUUID } from "node:crypto";

export type StoredDevice = {
  id: string;
  name: string;
  publicKey: string;
  revokedAt: number | null;
  createdAt: number;
};

export type PairingCode = { expiresAt: number; used: boolean };

export type StoredActionResult = {
  action: string;
  target: string | null;
  status: "pending" | "succeeded" | "failed";
  responseJson: string | null;
};

export type AuditEvent = {
  deviceId: string | null;
  action: string;
  target: string | null;
  result: string;
};

export interface SecurityStore {
  addDevice(publicId: string, publicKey: string, name?: string, now?: number): StoredDevice;
  getDevice(id: string): StoredDevice | undefined;
  consumeNonce(deviceId: string, nonce: string, now?: number): boolean;
  revokeDevice(id: string, now?: number): void;
  savePairingCode(code: string, expiresAt: number): void;
  consumePairingCode(code: string): PairingCode | undefined;
  listDevices(): StoredDevice[];
  getActionResult(deviceId: string, idempotencyKey: string): StoredActionResult | undefined;
  claimAction(
    deviceId: string,
    idempotencyKey: string,
    action: string,
    target: string | null,
  ): boolean;
  finishAction(
    deviceId: string,
    idempotencyKey: string,
    status: "succeeded" | "failed",
    responseJson: string | null,
  ): void;
  audit(deviceId: string | null, action: string, target: string | null, result: string): void;
}

export class InMemorySecurityStore {
  readonly devices = new Map<string, StoredDevice>();
  readonly nonces = new Set<string>();
  readonly codes = new Map<string, PairingCode>();
  readonly actions = new Map<string, StoredActionResult>();
  readonly auditEvents: AuditEvent[] = [];

  addDevice(publicId: string, publicKey: string, name = "Relay Watch", now = Date.now()) {
    const device = {
      id: publicId || randomUUID(),
      name,
      publicKey,
      revokedAt: null,
      createdAt: now,
    };
    this.devices.set(device.id, device);
    return device;
  }

  getDevice(id: string) {
    return this.devices.get(id);
  }

  consumeNonce(deviceId: string, nonce: string) {
    const key = `${deviceId}:${nonce}`;
    if (this.nonces.has(key)) return false;
    this.nonces.add(key);
    return true;
  }

  revokeDevice(id: string, now = Date.now()) {
    const device = this.devices.get(id);
    if (device) device.revokedAt = now;
  }

  savePairingCode(code: string, expiresAt: number) {
    this.codes.set(code, { expiresAt, used: false });
  }

  consumePairingCode(code: string) {
    const stored = this.codes.get(code);
    if (!stored || stored.used) return undefined;
    stored.used = true;
    return stored;
  }

  listDevices() {
    return [...this.devices.values()].sort(
      (left, right) => right.createdAt - left.createdAt,
    );
  }

  getActionResult(deviceId: string, idempotencyKey: string) {
    return this.actions.get(`${deviceId}:${idempotencyKey}`);
  }

  claimAction(
    deviceId: string,
    idempotencyKey: string,
    action: string,
    target: string | null,
  ) {
    const key = `${deviceId}:${idempotencyKey}`;
    if (this.actions.has(key)) return false;
    this.actions.set(key, {
      action,
      target,
      status: "pending",
      responseJson: null,
    });
    return true;
  }

  finishAction(
    deviceId: string,
    idempotencyKey: string,
    status: "succeeded" | "failed",
    responseJson: string | null,
  ) {
    const key = `${deviceId}:${idempotencyKey}`;
    const existing = this.actions.get(key);
    if (!existing) return;
    this.actions.set(key, { ...existing, status, responseJson });
  }

  audit(
    deviceId: string | null,
    action: string,
    target: string | null,
    result: string,
  ) {
    this.auditEvents.push({ deviceId, action, target, result });
  }
}
