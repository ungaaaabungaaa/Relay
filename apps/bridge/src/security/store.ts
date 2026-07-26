import { randomUUID } from "node:crypto";

export type StoredDevice = {
  id: string;
  name: string;
  publicKey: string;
  metadata?: DeviceMetadata;
  revokedAt: number | null;
  createdAt: number;
};

export type DeviceMetadata = {
  platform: "wear-os" | "watch-os";
  manufacturer: string;
  model: string;
  osVersion: string;
  appVersion: string;
  screenShape: "round" | "square";
};

export type StoredPendingPairing = {
  id: string;
  pollTokenHash: string;
  expiresAt: number;
  name: string;
  publicKey: string;
  metadata: DeviceMetadata;
};

export type StoredPairingSession = {
  id: string;
  tokenHash: string;
  codeHash: string;
  origin: string;
  macName: string;
  macFingerprint: string;
  expiresAt: number;
  state: "active" | "pending" | "approved" | "denied";
  pending?: StoredPendingPairing;
  approvedDeviceId?: string;
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
  addDevice(
    publicId: string,
    publicKey: string,
    name?: string,
    now?: number,
    metadata?: DeviceMetadata,
  ): StoredDevice;
  getDevice(id: string): StoredDevice | undefined;
  consumeNonce(deviceId: string, nonce: string, now?: number): boolean;
  revokeDevice(id: string, now?: number): void;
  savePairingCode(code: string, expiresAt: number): void;
  consumePairingCode(code: string): PairingCode | undefined;
  replacePairingSession(session: StoredPairingSession): void;
  updatePairingSession(session: StoredPairingSession): void;
  getPairingSessionByTokenHash(tokenHash: string): StoredPairingSession | undefined;
  listPairingSessions(): StoredPairingSession[];
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
  loadCloudSequenceState(kind: "incoming" | "outgoing"): Record<string, number>;
  saveCloudSequenceState(
    kind: "incoming" | "outgoing",
    state: Record<string, number>,
  ): void;
}

export class InMemorySecurityStore {
  readonly devices = new Map<string, StoredDevice>();
  readonly nonces = new Set<string>();
  readonly codes = new Map<string, PairingCode>();
  readonly pairingSessions = new Map<string, StoredPairingSession>();
  readonly actions = new Map<string, StoredActionResult>();
  readonly auditEvents: AuditEvent[] = [];
  readonly cloudSequenceState = new Map<string, Record<string, number>>();

  addDevice(
    publicId: string,
    publicKey: string,
    name = "Relay Watch",
    now = Date.now(),
    metadata?: DeviceMetadata,
  ) {
    const device = {
      id: publicId || randomUUID(),
      name,
      publicKey,
      ...(metadata ? { metadata } : {}),
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

  replacePairingSession(session: StoredPairingSession) {
    this.pairingSessions.clear();
    this.pairingSessions.set(session.id, structuredClone(session));
  }

  updatePairingSession(session: StoredPairingSession) {
    this.pairingSessions.set(session.id, structuredClone(session));
  }

  getPairingSessionByTokenHash(tokenHash: string) {
    const session = [...this.pairingSessions.values()].find(
      (candidate) => candidate.tokenHash === tokenHash,
    );
    return session ? structuredClone(session) : undefined;
  }

  listPairingSessions() {
    return [...this.pairingSessions.values()].map((session) =>
      structuredClone(session)
    );
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

  loadCloudSequenceState(kind: "incoming" | "outgoing") {
    return structuredClone(this.cloudSequenceState.get(kind) ?? {});
  }

  saveCloudSequenceState(
    kind: "incoming" | "outgoing",
    state: Record<string, number>,
  ) {
    this.cloudSequenceState.set(kind, structuredClone(state));
  }
}
