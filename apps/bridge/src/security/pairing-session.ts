import {
  createHash,
  createPublicKey,
  randomBytes,
  randomUUID,
  timingSafeEqual,
} from "node:crypto";
import type {
  DeviceMetadata,
  SecurityStore,
  StoredPairingSession,
  StoredDevice,
  StoredPendingPairing,
} from "./store.ts";

const CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
const SESSION_TTL_MS = 300_000;
const PENDING_TTL_MS = 120_000;
const RATE_WINDOW_MS = 300_000;

export type PairingSessionInput = {
  origin: string;
  macName: string;
  macFingerprint: string;
};

export type PairingSubmission = {
  code: string;
  name: string;
  publicKey: string;
  metadata: DeviceMetadata;
};

export type PendingPairingSummary = {
  id: string;
  name: string;
  fingerprint: string;
  metadata: DeviceMetadata;
  expiresAt: number;
};

type PairingSessionDependencies = {
  now?: () => number;
  randomBytes?: (size: number) => Buffer;
  randomUUID?: () => string;
};

function digest(value: string) {
  return createHash("sha256").update(value).digest("hex");
}

function equalDigest(left: string, right: string) {
  const actual = Buffer.from(left, "hex");
  const expected = Buffer.from(right, "hex");
  return actual.length === expected.length && timingSafeEqual(actual, expected);
}

function pairingUnavailable(): never {
  throw new Error("pairing unavailable");
}

export class PairingSessionService {
  private readonly store: SecurityStore;
  private readonly now: () => number;
  private readonly bytes: (size: number) => Buffer;
  private readonly uuid: () => string;
  private readonly sourceAttempts = new Map<string, number[]>();
  private globalAttempts: number[] = [];

  constructor(
    store: SecurityStore,
    dependencies: PairingSessionDependencies = {},
  ) {
    this.store = store;
    this.now = dependencies.now ?? Date.now;
    this.bytes = dependencies.randomBytes ?? randomBytes;
    this.uuid = dependencies.randomUUID ?? randomUUID;
  }

  create(input: PairingSessionInput) {
    const origin = new URL(input.origin);
    if (origin.protocol !== "https:" || !origin.hostname) {
      throw new Error("pairing origin must use HTTPS");
    }
    const discoveryToken = this.bytes(16).toString("hex");
    const code = Array.from(this.bytes(6), (value) =>
      CODE_ALPHABET[value % CODE_ALPHABET.length]
    ).join("");
    const id = this.uuid();
    const expiresAt = this.now() + SESSION_TTL_MS;
    const session: StoredPairingSession = {
      ...input,
      origin: origin.origin,
      id,
      tokenHash: digest(discoveryToken),
      codeHash: digest(code),
      expiresAt,
      state: "active",
    };
    this.store.replacePairingSession(session);
    return {
      id,
      discoveryToken,
      code,
      expiresAt,
      macFingerprint: input.macFingerprint,
      origin: origin.origin,
    };
  }

  discover(discoveryToken: string) {
    const session = this.sessionForToken(discoveryToken);
    this.requireAvailable(session, ["active", "pending"]);
    return {
      macName: session.macName,
      macFingerprint: session.macFingerprint,
      apiVersion: 1,
      expiresAt: session.expiresAt,
    };
  }

  submit(
    discoveryToken: string,
    source: string,
    submission: PairingSubmission,
  ) {
    const session = this.sessionForToken(discoveryToken);
    this.requireAvailable(session, ["active"]);
    this.recordSourceAttempt(source);
    if (!equalDigest(digest(submission.code), session.codeHash)) {
      return pairingUnavailable();
    }
    if (
      !submission.name.trim() ||
      submission.name.length > 120 ||
      !this.validMetadata(submission.metadata)
    ) {
      return pairingUnavailable();
    }
    try {
      createPublicKey(submission.publicKey);
    } catch {
      return pairingUnavailable();
    }
    const pollToken = this.bytes(16).toString("hex");
    const pending: StoredPendingPairing = {
      name: submission.name.trim(),
      publicKey: submission.publicKey,
      metadata: submission.metadata,
      id: this.uuid(),
      pollTokenHash: digest(pollToken),
      expiresAt: Math.min(session.expiresAt, this.now() + PENDING_TTL_MS),
    };
    session.pending = pending;
    session.state = "pending";
    this.store.updatePairingSession(session);
    return {
      pairingId: pending.id,
      pollToken,
      expiresAt: pending.expiresAt,
    };
  }

  listPending(): PendingPairingSummary[] {
    const now = this.now();
    return this.store.listPairingSessions().flatMap((session) => {
      const pending = session.pending;
      if (
        session.state !== "pending" ||
        !pending ||
        pending.expiresAt < now ||
        session.expiresAt < now
      ) {
        return [];
      }
      const fingerprint = digest(pending.publicKey);
      return [{
        id: pending.id,
        name: pending.name,
        fingerprint:
          fingerprint.match(/.{1,4}/g)?.slice(0, 8).join(":") ?? fingerprint,
        metadata: pending.metadata,
        expiresAt: pending.expiresAt,
      }];
    });
  }

  approve(pairingId: string): StoredDevice {
    const session = this.sessionForPairing(pairingId);
    this.requireAvailable(session, ["pending"]);
    const pending = session.pending;
    if (!pending || pending.expiresAt < this.now()) {
      return pairingUnavailable();
    }
    const device = this.store.addDevice(
      this.uuid(),
      pending.publicKey,
      pending.name,
      this.now(),
      pending.metadata,
    );
    session.approvedDeviceId = device.id;
    session.state = "approved";
    this.store.updatePairingSession(session);
    return device;
  }

  deny(pairingId: string) {
    const session = this.sessionForPairing(pairingId);
    this.requireAvailable(session, ["pending"]);
    session.state = "denied";
    this.store.updatePairingSession(session);
  }

  poll(discoveryToken: string, pollToken: string) {
    const session = this.sessionForToken(discoveryToken);
    const pending = session.pending;
    if (
      !pending ||
      !equalDigest(digest(pollToken), pending.pollTokenHash) ||
      session.expiresAt < this.now() ||
      pending.expiresAt < this.now()
    ) {
      return pairingUnavailable();
    }
    if (session.state === "approved" && session.approvedDeviceId) {
      return {
        state: "approved" as const,
        deviceId: session.approvedDeviceId,
        origin: session.origin,
        apiVersion: 1,
      };
    }
    if (session.state === "denied") {
      return { state: "denied" as const };
    }
    if (session.state !== "pending") {
      return pairingUnavailable();
    }
    return { state: "pending" as const };
  }

  private sessionForToken(discoveryToken: string) {
    const tokenHash = digest(discoveryToken);
    const session = this.store.getPairingSessionByTokenHash(tokenHash);
    return session ?? pairingUnavailable();
  }

  private sessionForPairing(pairingId: string) {
    const session = this.store.listPairingSessions().find(
      (candidate) => candidate.pending?.id === pairingId,
    );
    return session ?? pairingUnavailable();
  }

  private requireAvailable(
    session: StoredPairingSession,
    states: StoredPairingSession["state"][],
  ) {
    if (session.expiresAt < this.now() || !states.includes(session.state)) {
      return pairingUnavailable();
    }
  }

  private recordSourceAttempt(source: string) {
    const cutoff = this.now() - RATE_WINDOW_MS;
    const attempts = (this.sourceAttempts.get(source) ?? []).filter(
      (attempt) => attempt > cutoff,
    );
    this.globalAttempts = this.globalAttempts.filter(
      (attempt) => attempt > cutoff,
    );
    if (attempts.length >= 5 || this.globalAttempts.length >= 30) {
      return pairingUnavailable();
    }
    attempts.push(this.now());
    this.globalAttempts.push(this.now());
    this.sourceAttempts.set(source, attempts);
  }

  private validMetadata(metadata: DeviceMetadata) {
    return (
      (metadata.platform === "wear-os" || metadata.platform === "watch-os") &&
      (metadata.screenShape === "round" || metadata.screenShape === "square") &&
      [
        metadata.manufacturer,
        metadata.model,
        metadata.osVersion,
        metadata.appVersion,
      ].every((value) => value.trim().length > 0 && value.length <= 120)
    );
  }
}
