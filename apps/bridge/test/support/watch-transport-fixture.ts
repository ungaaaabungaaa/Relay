import { generateKeyPairSync, sign } from "node:crypto";
import { mkdir, mkdtemp, realpath, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import {
  RelayReplayWindow,
  decryptRelayEnvelope,
  deriveRelayRootKey,
  encryptRelayEnvelope,
  generateAgreementKeyPair,
  type RelayInnerMessage,
  type RelayTunnelEnvelope,
} from "../../../../packages/cloud-protocol/src/index.ts";
import { BridgeCloudRuntime } from "../../src/cloud/bridge-cloud-runtime.ts";
import { EventHub, type RelayEvent } from "../../src/events/event-hub.ts";
import { canonicalRequest } from "../../src/security/authentication.ts";
import { InMemorySecurityStore } from "../../src/security/store.ts";
import type { Transcriber } from "../../src/transcription/transcriber.ts";
import { WorkspacePolicy } from "../../src/workspaces/workspace-policy.ts";
import { createRequestHandler } from "../../src/server.ts";
import type { FakeCodexAdapter } from "./fake-codex-adapter.ts";

export type WatchFixtureInput = {
  fakeCodex: FakeCodexAdapter;
  eventHub?: EventHub;
  transcriber?: Transcriber;
};

export type WatchRequestInput = {
  method: "GET" | "POST";
  path: string;
  body?: unknown;
  idempotencyKey?: string;
  sequence?: number;
};

export type WatchVoiceInput = {
  audio: Uint8Array;
  durationMs: number;
  chunkBytes?: number;
};

type WatchResponse = { status: number; body: unknown };

export class WatchTransportFixture {
  readonly workspaceRoot: string;
  readonly #temporaryRoot: string;
  readonly #store: InMemorySecurityStore;
  readonly #runtime: BridgeCloudRuntime;
  readonly #signingPrivateKey: ReturnType<
    typeof generateKeyPairSync
  >["privateKey"];
  readonly #rootKey: CryptoKey;
  readonly #now: number;
  readonly #events: RelayEvent[] = [];
  readonly #responseReplay = new RelayReplayWindow();
  #requestSequence = 0;
  #connected = true;
  #revoked = false;
  #closed = false;
  #cleanup: Promise<void> = Promise.resolve();

  private constructor(input: {
    workspaceRoot: string;
    temporaryRoot: string;
    store: InMemorySecurityStore;
    runtime: BridgeCloudRuntime;
    signingPrivateKey: ReturnType<typeof generateKeyPairSync>["privateKey"];
    rootKey: CryptoKey;
    now: number;
  }) {
    this.workspaceRoot = input.workspaceRoot;
    this.#temporaryRoot = input.temporaryRoot;
    this.#store = input.store;
    this.#runtime = input.runtime;
    this.#signingPrivateKey = input.signingPrivateKey;
    this.#rootKey = input.rootKey;
    this.#now = input.now;
  }

  static async create(input: WatchFixtureInput): Promise<WatchTransportFixture> {
    const temporaryRoot = await mkdtemp(join(tmpdir(), "relay-apple-client-"));
    const requestedWorkspaceRoot = join(temporaryRoot, "workspace");
    await mkdir(requestedWorkspaceRoot);
    const workspaceRoot = await realpath(requestedWorkspaceRoot);

    const signing = generateKeyPairSync("ec", { namedCurve: "prime256v1" });
    const macAgreement = await generateAgreementKeyPair();
    const watchAgreement = await generateAgreementKeyPair();
    const pairingNonce = crypto.getRandomValues(new Uint8Array(32));
    const [macRootKey, watchRootKey] = await Promise.all([
      deriveRelayRootKey(
        macAgreement.privateKey,
        watchAgreement.publicKey,
        pairingNonce,
      ),
      deriveRelayRootKey(
        watchAgreement.privateKey,
        macAgreement.publicKey,
        pairingNonce,
      ),
    ]);
    const store = new InMemorySecurityStore();
    const eventHub = input.eventHub ?? new EventHub();
    const now = Date.now();
    const handler = createRequestHandler({
      store,
      adapter: input.fakeCodex,
      workspacePolicy: new WorkspacePolicy([workspaceRoot]),
      transcriber: input.transcriber ?? {
        transcribe: async () => "Test transcript",
      },
      transcriptionTemporaryDirectory: join(temporaryRoot, "audio"),
    });
    const runtime = new BridgeCloudRuntime({
      store,
      eventHub,
      handler,
      now: () => now,
    });
    await runtime.registerDevice({
      accountId: "account-1",
      hostId: "host-1",
      deviceId: "watch-1",
      name: "Apple Watch",
      signingPublicKey: signing.publicKey
        .export({ type: "spki", format: "pem" })
        .toString(),
      rootKey: macRootKey,
      metadata: {
        platform: "watch-os",
        manufacturer: "Apple",
        model: "Apple Watch",
        osVersion: "10",
        appVersion: "0.2.0",
        screenShape: "rounded-rect",
      },
    });

    return new WatchTransportFixture({
      workspaceRoot,
      temporaryRoot,
      store,
      runtime,
      signingPrivateKey: signing.privateKey,
      rootKey: watchRootKey,
      now,
    });
  }

  async request(input: WatchRequestInput): Promise<WatchResponse> {
    await this.#assertAvailable();
    const body = input.body === undefined
      ? Buffer.alloc(0)
      : Buffer.from(JSON.stringify(input.body));
    const headers = this.#signedHeaders({
      method: input.method,
      path: input.path,
      body,
      idempotencyKey: input.idempotencyKey,
    });
    const messageId = crypto.randomUUID();
    await this.#runtime.receive(
      await encryptRelayEnvelope(
        this.#routing(messageId, input.sequence),
        {
          kind: "request",
          body: {
            method: input.method,
            path: input.path,
            headers,
            body: body.toString(),
          },
        },
        this.#rootKey,
      ),
    );
    return this.#drainResponse(messageId);
  }

  async sendVoice(input: WatchVoiceInput): Promise<WatchResponse> {
    await this.#assertAvailable();
    const audio = Buffer.from(input.audio);
    const chunkBytes = input.chunkBytes ?? 128 * 1024;
    if (!Number.isSafeInteger(chunkBytes) || chunkBytes < 1) {
      throw new Error("Invalid voice chunk size");
    }
    const chunks: Buffer[] = [];
    for (let offset = 0; offset < audio.byteLength; offset += chunkBytes) {
      chunks.push(audio.subarray(offset, offset + chunkBytes));
    }
    if (chunks.length === 0) throw new Error("Voice audio is empty");

    const path = `/v1/transcribe?durationMs=${input.durationMs}`;
    const signedHeaders = this.#signedHeaders({
      method: "POST",
      path,
      body: audio,
      idempotencyKey: `voice-${crypto.randomUUID()}`,
    });
    const transferId = `transfer-${crypto.randomUUID()}`;
    let finalMessageId = "";
    for (let index = 0; index < chunks.length; index += 1) {
      finalMessageId = crypto.randomUUID();
      const recordedAtMs = chunks.length === 1
        ? input.durationMs
        : Math.floor((index * input.durationMs) / (chunks.length - 1));
      await this.#runtime.receive(
        await encryptRelayEnvelope(
          this.#routing(finalMessageId),
          {
            kind: "voice",
            body: {
              transferId,
              index,
              totalChunks: chunks.length,
              recordedAtMs,
              durationMs: input.durationMs,
              method: "POST",
              path,
              headers: {
                ...signedHeaders,
                "content-type": "audio/mp4",
              },
              data: chunks[index]!.toString("base64"),
            },
          },
          this.#rootKey,
        ),
      );
    }
    return this.#drainResponse(finalMessageId);
  }

  async drainEvents(): Promise<RelayEvent[]> {
    await this.#consumeEnvelopes(await this.#runtime.drainEvents());
    return this.#events.splice(0);
  }

  disconnect(): void {
    this.#connected = false;
  }

  reconnect(): void {
    if (this.#closed || this.#revoked) return;
    this.#connected = true;
  }

  revoke(): void {
    if (this.#revoked || this.#closed) return;
    this.#revoked = true;
    this.#store.revokeDevice("watch-1", this.#now);
    this.#cleanup = this.#runtime.removeDevice("watch-1");
  }

  async close(): Promise<void> {
    if (this.#closed) return;
    this.#closed = true;
    this.#connected = false;
    await this.#cleanup;
    await this.#runtime.close();
    await rm(this.#temporaryRoot, { recursive: true, force: true });
  }

  async #assertAvailable(): Promise<void> {
    await this.#cleanup;
    if (this.#revoked) throw new Error("Relay Watch is revoked");
    if (!this.#connected || this.#closed) throw new Error("Relay Watch is offline");
  }

  #signedHeaders(input: {
    method: string;
    path: string;
    body: Uint8Array;
    idempotencyKey?: string;
  }): Record<string, string> {
    const nonce = crypto.randomUUID();
    const signature = sign(
      "sha256",
      Buffer.from(
        canonicalRequest({
          deviceId: "watch-1",
          method: input.method,
          path: input.path,
          body: input.body,
          timestamp: this.#now,
          nonce,
        }),
      ),
      this.#signingPrivateKey,
    ).toString("base64");
    return {
      ...(input.body.byteLength > 0
        ? { "content-type": "application/json" }
        : {}),
      ...(input.idempotencyKey
        ? { "idempotency-key": input.idempotencyKey }
        : {}),
      "x-relay-device": "watch-1",
      "x-relay-timestamp": String(this.#now),
      "x-relay-nonce": nonce,
      "x-relay-signature": signature,
    };
  }

  #routing(messageId: string, suppliedSequence?: number) {
    const sequence = suppliedSequence ?? this.#requestSequence + 1;
    this.#requestSequence = Math.max(this.#requestSequence, sequence);
    return {
      version: 1 as const,
      messageId,
      accountId: "account-1",
      hostId: "host-1",
      senderId: "watch-1",
      recipientId: "host-1",
      sentAt: this.#now,
      sequence,
    };
  }

  async #drainResponse(requestId: string): Promise<WatchResponse> {
    const messages = await this.#consumeEnvelopes(
      await this.#runtime.drainEvents(),
    );
    const response = messages.find((message) => {
      if (message.kind !== "response") return false;
      return (message.body as { requestId?: unknown }).requestId === requestId;
    });
    if (!response) throw new Error("Missing encrypted Relay response");
    const body = response.body as { status: number; body: string };
    return {
      status: body.status,
      body: body.body ? JSON.parse(body.body) : null,
    };
  }

  async #consumeEnvelopes(
    envelopes: RelayTunnelEnvelope[],
  ): Promise<RelayInnerMessage[]> {
    const messages: RelayInnerMessage[] = [];
    for (const envelope of envelopes) {
      this.#responseReplay.accept(envelope.senderId, envelope.sequence);
      const message = await decryptRelayEnvelope(envelope, this.#rootKey);
      messages.push(message);
      if (message.kind === "event") {
        this.#events.push(message.body as RelayEvent);
      }
    }
    return messages;
  }
}
