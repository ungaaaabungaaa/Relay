import type { RelayTunnelEnvelope } from "../../../../packages/cloud-protocol/src/index.ts";
import type {
  DeviceMetadata,
  SecurityStore,
} from "../security/store.ts";
import { CloudTunnelAdapter } from "./cloud-tunnel-adapter.ts";

type BridgeCloudRuntimeOptions = {
  store: SecurityStore;
  handler(request: Request): Promise<Response>;
  now?: () => number;
};

type CloudDeviceRegistration = {
  hostId: string;
  deviceId: string;
  name: string;
  signingPublicKey: string;
  rootKey: string;
  metadata: DeviceMetadata;
};

export class BridgeCloudRuntime {
  readonly #options: BridgeCloudRuntimeOptions;
  readonly #rootKeys = new Map<string, CryptoKey>();
  readonly #adapters = new Map<string, CloudTunnelAdapter>();

  constructor(options: BridgeCloudRuntimeOptions) {
    this.#options = options;
  }

  async registerDevice(input: CloudDeviceRegistration): Promise<void> {
    const rootKeyBytes = Buffer.from(input.rootKey, "base64url");
    if (rootKeyBytes.byteLength !== 32) {
      throw new Error("Invalid Relay cloud root key");
    }
    const rootKey = await crypto.subtle.importKey(
      "raw",
      rootKeyBytes,
      "AES-GCM",
      false,
      ["encrypt", "decrypt"],
    );
    this.#rootKeys.set(input.deviceId, rootKey);
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
  ): Promise<RelayTunnelEnvelope> {
    const adapter = this.#adapters.get(envelope.hostId);
    if (!adapter) throw new Error("Unknown Relay cloud host");
    return adapter.receive(envelope);
  }
}
