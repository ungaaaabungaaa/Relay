import type { RelayTunnelEnvelope } from "../../../../packages/cloud-protocol/src/index.ts";
import type {
  DeviceMetadata,
  SecurityStore,
} from "../security/store.ts";
import type { EventHub, RelayEvent } from "../events/event-hub.ts";
import { CloudTunnelAdapter } from "./cloud-tunnel-adapter.ts";

type BridgeCloudRuntimeOptions = {
  store: SecurityStore;
  eventHub: EventHub;
  handler(request: Request): Promise<Response>;
  now?: () => number;
};

type CloudDeviceRegistration = {
  accountId: string;
  hostId: string;
  deviceId: string;
  name: string;
  signingPublicKey: string;
  rootKey: string | CryptoKey;
  metadata: DeviceMetadata;
};

export class BridgeCloudRuntime {
  readonly #options: BridgeCloudRuntimeOptions;
  readonly #rootKeys = new Map<string, CryptoKey>();
  readonly #adapters = new Map<string, CloudTunnelAdapter>();
  readonly #registrations = new Map<string, CloudDeviceRegistration>();
  readonly #pendingEvents: RelayTunnelEnvelope[] = [];
  readonly #unsubscribe: () => void;
  #outgoingWork: Promise<void> = Promise.resolve();
  #closed = false;

  constructor(options: BridgeCloudRuntimeOptions) {
    this.#options = options;
    this.#unsubscribe = options.eventHub.subscribe((event) => {
      void this.#appendOutgoing(() => this.#enqueueEvent(event)).catch(() => {});
    });
  }

  async registerDevice(input: CloudDeviceRegistration): Promise<void> {
    if (this.#closed) throw new Error("Relay cloud runtime is closed");
    const rootKey = typeof input.rootKey === "string"
      ? await this.#importRootKey(input.rootKey)
      : input.rootKey;
    if (
      rootKey.algorithm.name !== "AES-GCM" ||
      !rootKey.usages.includes("encrypt") ||
      !rootKey.usages.includes("decrypt")
    ) {
      throw new Error("Invalid Relay cloud root key");
    }
    this.#rootKeys.set(input.deviceId, rootKey);
    this.#registrations.set(input.deviceId, structuredClone(input));
    this.#options.store.addDevice(
      input.deviceId,
      input.signingPublicKey,
      input.name,
      Date.now(),
      input.metadata,
    );
    if (!this.#adapters.has(input.hostId)) {
      this.#adapters.set(
        input.hostId,
        new CloudTunnelAdapter({
          hostId: input.hostId,
          keyForDevice: async (deviceId) => {
            const key = this.#rootKeys.get(deviceId);
            if (!key) throw new Error("Unknown Relay cloud device");
            return key;
          },
          loadReplayState: async () =>
            this.#options.store.loadCloudSequenceState("incoming"),
          saveReplayState: async (state) => {
            this.#options.store.saveCloudSequenceState("incoming", state);
          },
          loadOutgoingSequences: async () =>
            this.#options.store.loadCloudSequenceState("outgoing"),
          saveOutgoingSequences: async (state) => {
            this.#options.store.saveCloudSequenceState("outgoing", state);
          },
          handler: this.#options.handler,
          ...(this.#options.now ? { now: this.#options.now } : {}),
        }),
      );
    }
  }

  async receive(
    envelope: RelayTunnelEnvelope,
  ): Promise<void> {
    if (this.#closed) throw new Error("Relay cloud runtime is closed");
    const adapter = this.#adapters.get(envelope.hostId);
    if (!adapter) throw new Error("Unknown Relay cloud host");
    await this.#appendOutgoing(async () => {
      const response = await adapter.receive(envelope);
      if (response) this.#pendingEvents.push(response);
      this.#trimPendingEvents();
    });
  }

  async drainEvents(limit = 100): Promise<RelayTunnelEnvelope[]> {
    await this.#outgoingWork;
    const now = (this.#options.now ?? Date.now)();
    while (
      this.#pendingEvents[0] &&
      now - this.#pendingEvents[0].sentAt > 5 * 60_000
    ) {
      this.#pendingEvents.shift();
    }
    const count = Math.max(0, Math.min(limit, 100));
    return this.#pendingEvents.splice(0, count);
  }

  async removeDevice(deviceId: string): Promise<void> {
    if (this.#closed) return;
    await this.#appendOutgoing(async () => {
      const registration = this.#registrations.get(deviceId);
      if (!registration) return;
      const adapter = this.#adapters.get(registration.hostId);
      await adapter?.removeDevice(deviceId);
      this.#options.store.revokeDevice(deviceId);
      this.#rootKeys.delete(deviceId);
      this.#registrations.delete(deviceId);
      for (let index = this.#pendingEvents.length - 1; index >= 0; index -= 1) {
        const envelope = this.#pendingEvents[index]!;
        if (
          envelope.senderId === deviceId ||
          envelope.recipientId === deviceId
        ) {
          this.#pendingEvents.splice(index, 1);
        }
      }
      const hostStillRegistered = [...this.#registrations.values()].some(
        (candidate) => candidate.hostId === registration.hostId,
      );
      if (!hostStillRegistered && adapter) {
        await adapter.close();
        this.#adapters.delete(registration.hostId);
      }
    });
  }

  async close(): Promise<void> {
    if (this.#closed) return;
    this.#closed = true;
    this.#unsubscribe();
    await this.#outgoingWork;
    await Promise.all(
      [...this.#adapters.values()].map((adapter) => adapter.close()),
    );
    this.#pendingEvents.splice(0);
    this.#rootKeys.clear();
    this.#registrations.clear();
    this.#adapters.clear();
  }

  async #enqueueEvent(event: RelayEvent): Promise<void> {
    for (const registration of this.#registrations.values()) {
      const adapter = this.#adapters.get(registration.hostId);
      if (!adapter) continue;
      this.#pendingEvents.push(
        await adapter.pushEvent({
          accountId: registration.accountId,
          deviceId: registration.deviceId,
          event,
        }),
      );
    }
    this.#trimPendingEvents();
  }

  #appendOutgoing(work: () => Promise<void>): Promise<void> {
    const appended = this.#outgoingWork.then(work);
    this.#outgoingWork = appended.catch(() => {});
    return appended;
  }

  #trimPendingEvents(): void {
    while (this.#pendingEvents.length > 500) this.#pendingEvents.shift();
  }

  async #importRootKey(encoded: string): Promise<CryptoKey> {
    const rootKeyBytes = Buffer.from(encoded, "base64url");
    if (rootKeyBytes.byteLength !== 32) {
      throw new Error("Invalid Relay cloud root key");
    }
    return crypto.subtle.importKey(
      "raw",
      rootKeyBytes,
      "AES-GCM",
      false,
      ["encrypt", "decrypt"],
    );
  }
}
