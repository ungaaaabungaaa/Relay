import { randomUUID } from "node:crypto";

export type StoredDevice = {
  id: string;
  name: string;
  publicKey: string;
  revokedAt: number | null;
  createdAt: number;
};

export type PairingCode = { expiresAt: number; used: boolean };

export interface SecurityStore {
  addDevice(publicId: string, publicKey: string, name?: string, now?: number): StoredDevice;
  getDevice(id: string): StoredDevice | undefined;
  consumeNonce(deviceId: string, nonce: string, now?: number): boolean;
  revokeDevice(id: string, now?: number): void;
  savePairingCode(code: string, expiresAt: number): void;
  consumePairingCode(code: string): PairingCode | undefined;
}

export class InMemorySecurityStore {
  readonly devices = new Map<string, StoredDevice>();
  readonly nonces = new Set<string>();
  readonly codes = new Map<string, PairingCode>();

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
}
