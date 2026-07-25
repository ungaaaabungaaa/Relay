import { createHash, randomBytes, randomUUID } from "node:crypto";
import type { RelayTunnelEnvelope } from "../../../packages/cloud-protocol/src/index.ts";

type Account = { id: string; email: string; createdAt: number };
type Host = {
  id: string;
  accountId: string;
  name: string;
  credential: string;
  revoked: boolean;
};
type Device = {
  id: string;
  accountId: string;
  hostId: string;
  name: string;
  credential: string;
  revoked: boolean;
  metadata?: Record<string, unknown>;
};
type Invite = { email: string; used: boolean; createdAt: number };
type DeviceLogin = {
  id: string;
  email: string;
  pkceChallenge: string;
  status: "pending" | "verified" | "consumed";
  expiresAt: number;
};
type PairingRequest = {
  id: string;
  publicKey: string;
  fingerprint: string;
  metadata: Record<string, unknown>;
  status: "pending" | "approved" | "denied";
};
type PairingSession = {
  token: string;
  code: string;
  accountId: string;
  hostId: string;
  expiresAt: number;
  requests: Map<string, PairingRequest>;
};

export class InMemoryCloudStore {
  readonly accounts = new Map<string, Account>();
  readonly invites = new Map<string, Invite>();
  readonly deviceLogins = new Map<string, DeviceLogin>();
  readonly hosts = new Map<string, Host>();
  readonly devices = new Map<string, Device>();
  readonly pairings = new Map<string, PairingSession>();
}

type ServiceOptions = {
  now?: () => number;
  adminCredential?: string;
};

const GENERIC_AUTH_ERROR = "Authentication failed";
const GENERIC_PAIRING_ERROR = "Pairing failed";

function opaqueCredential(): string {
  return randomBytes(32).toString("base64url");
}

function normalizeEmail(email: string): string {
  return email.trim().toLowerCase();
}

function pairingCode(): string {
  const alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
  const bytes = randomBytes(6);
  return Array.from(bytes, (byte) => alphabet[byte % alphabet.length]).join("");
}

export class RelayCloudService {
  readonly store: InMemoryCloudStore;
  readonly #now: () => number;
  readonly #adminCredentialHash: string;

  constructor(
    store: InMemoryCloudStore,
    options: ServiceOptions = {},
  ) {
    this.store = store;
    this.#now = options.now ?? Date.now;
    this.#adminCredentialHash = createHash("sha256")
      .update(options.adminCredential ?? "admin-secret")
      .digest("hex");
  }

  async createInvite(email: string, adminCredential: string): Promise<void> {
    const supplied = createHash("sha256").update(adminCredential).digest("hex");
    if (supplied !== this.#adminCredentialHash) throw new Error(GENERIC_AUTH_ERROR);
    const normalized = normalizeEmail(email);
    this.store.invites.set(normalized, {
      email: normalized,
      used: false,
      createdAt: this.#now(),
    });
  }

  async startDeviceLogin(input: {
    email: string;
    pkceChallenge: string;
  }): Promise<DeviceLogin> {
    const email = normalizeEmail(input.email);
    const invite = this.store.invites.get(email);
    if (!invite || invite.used || input.pkceChallenge.length < 8) {
      throw new Error(GENERIC_AUTH_ERROR);
    }
    const login: DeviceLogin = {
      id: randomUUID(),
      email,
      pkceChallenge: input.pkceChallenge,
      status: "pending",
      expiresAt: this.#now() + 10 * 60_000,
    };
    this.store.deviceLogins.set(login.id, login);
    return login;
  }

  async createTestAccount(email: string): Promise<Account> {
    const normalized = normalizeEmail(email);
    const account: Account = {
      id: randomUUID(),
      email: normalized,
      createdAt: this.#now(),
    };
    this.store.accounts.set(account.id, account);
    return account;
  }

  async registerHost(accountId: string, name: string): Promise<Host> {
    this.#requireAccount(accountId);
    if ([...this.store.hosts.values()].some((host) => host.accountId === accountId && !host.revoked)) {
      throw new Error("Host limit reached");
    }
    const host: Host = {
      id: randomUUID(),
      accountId,
      name,
      credential: opaqueCredential(),
      revoked: false,
    };
    this.store.hosts.set(host.id, host);
    return structuredClone(host);
  }

  async createTestDevice(
    accountId: string,
    hostId: string,
    name: string,
    metadata?: Record<string, unknown>,
  ): Promise<Device> {
    const host = this.#requireHost(accountId, hostId);
    const devices = [...this.store.devices.values()].filter(
      (device) => device.hostId === host.id && !device.revoked,
    );
    if (devices.length >= 3) throw new Error("Device limit reached");
    const device: Device = {
      id: randomUUID(),
      accountId,
      hostId,
      name,
      credential: opaqueCredential(),
      revoked: false,
      metadata,
    };
    this.store.devices.set(device.id, device);
    return structuredClone(device);
  }

  async getDevice(deviceId: string): Promise<Device | undefined> {
    const device = this.store.devices.get(deviceId);
    return device ? structuredClone(device) : undefined;
  }

  async createPairingSession(
    accountId: string,
    hostId: string,
  ): Promise<{ token: string; code: string; expiresAt: number }> {
    this.#requireHost(accountId, hostId);
    const token = opaqueCredential();
    const session: PairingSession = {
      token,
      code: pairingCode(),
      accountId,
      hostId,
      expiresAt: this.#now() + 5 * 60_000,
      requests: new Map(),
    };
    this.store.pairings.set(token, session);
    return { token, code: session.code, expiresAt: session.expiresAt };
  }

  async requestPairing(
    token: string,
    input: {
      publicKey: string;
      fingerprint: string;
      metadata: Record<string, unknown>;
    },
  ): Promise<PairingRequest> {
    const session = this.store.pairings.get(token);
    if (!session || session.expiresAt < this.#now()) {
      this.store.pairings.delete(token);
      throw new Error(GENERIC_PAIRING_ERROR);
    }
    const request: PairingRequest = {
      id: randomUUID(),
      publicKey: input.publicKey,
      fingerprint: input.fingerprint,
      metadata: input.metadata,
      status: "pending",
    };
    session.requests.set(request.id, request);
    return request;
  }

  async approvePairing(
    accountId: string,
    hostId: string,
    token: string,
    requestId: string,
  ): Promise<Device> {
    const { session, request } = this.#requirePairing(
      accountId,
      hostId,
      token,
      requestId,
    );
    request.status = "approved";
    const device = await this.createTestDevice(
      accountId,
      hostId,
      String(request.metadata.model ?? request.metadata.platform ?? "Watch"),
      request.metadata,
    );
    this.store.pairings.delete(session.token);
    return device;
  }

  async denyPairing(
    accountId: string,
    hostId: string,
    token: string,
    requestId: string,
  ): Promise<void> {
    const { session, request } = this.#requirePairing(
      accountId,
      hostId,
      token,
      requestId,
    );
    request.status = "denied";
    this.store.pairings.delete(session.token);
  }

  async route(
    accountId: string,
    senderId: string,
    envelope: RelayTunnelEnvelope,
  ): Promise<RelayTunnelEnvelope> {
    if (envelope.accountId !== accountId || envelope.senderId !== senderId) {
      throw new Error(GENERIC_AUTH_ERROR);
    }
    const host = this.store.hosts.get(envelope.hostId);
    if (!host || host.accountId !== accountId || host.revoked) {
      throw new Error(GENERIC_AUTH_ERROR);
    }
    const senderIsHost = senderId === host.id;
    const senderDevice = this.store.devices.get(senderId);
    if (
      !senderIsHost &&
      (!senderDevice ||
        senderDevice.accountId !== accountId ||
        senderDevice.hostId !== host.id ||
        senderDevice.revoked)
    ) {
      throw new Error(GENERIC_AUTH_ERROR);
    }
    const validRecipient =
      envelope.recipientId === host.id ||
      [...this.store.devices.values()].some(
        (device) =>
          device.id === envelope.recipientId &&
          device.accountId === accountId &&
          device.hostId === host.id &&
          !device.revoked,
      );
    if (!validRecipient) throw new Error(GENERIC_AUTH_ERROR);
    return structuredClone(envelope);
  }

  async emergencyStop(
    accountId: string,
    hostId: string,
  ): Promise<{ hostCredential: string; revokedDeviceIds: string[] }> {
    const host = this.#requireHost(accountId, hostId);
    host.credential = opaqueCredential();
    const revokedDeviceIds: string[] = [];
    for (const device of this.store.devices.values()) {
      if (device.hostId === hostId && !device.revoked) {
        device.revoked = true;
        revokedDeviceIds.push(device.id);
      }
    }
    return { hostCredential: host.credential, revokedDeviceIds };
  }

  async deleteAccount(accountId: string): Promise<void> {
    this.#requireAccount(accountId);
    for (const [id, host] of this.store.hosts) {
      if (host.accountId === accountId) this.store.hosts.delete(id);
    }
    for (const [id, device] of this.store.devices) {
      if (device.accountId === accountId) this.store.devices.delete(id);
    }
    for (const [token, pairing] of this.store.pairings) {
      if (pairing.accountId === accountId) this.store.pairings.delete(token);
    }
    this.store.accounts.delete(accountId);
  }

  #requireAccount(accountId: string): Account {
    const account = this.store.accounts.get(accountId);
    if (!account) throw new Error(GENERIC_AUTH_ERROR);
    return account;
  }

  #requireHost(accountId: string, hostId: string): Host {
    this.#requireAccount(accountId);
    const host = this.store.hosts.get(hostId);
    if (!host || host.accountId !== accountId || host.revoked) {
      throw new Error(GENERIC_AUTH_ERROR);
    }
    return host;
  }

  #requirePairing(
    accountId: string,
    hostId: string,
    token: string,
    requestId: string,
  ): { session: PairingSession; request: PairingRequest } {
    this.#requireHost(accountId, hostId);
    const session = this.store.pairings.get(token);
    const request = session?.requests.get(requestId);
    if (
      !session ||
      !request ||
      session.accountId !== accountId ||
      session.hostId !== hostId ||
      session.expiresAt < this.#now() ||
      request.status !== "pending"
    ) {
      throw new Error(GENERIC_PAIRING_ERROR);
    }
    return { session, request };
  }
}
