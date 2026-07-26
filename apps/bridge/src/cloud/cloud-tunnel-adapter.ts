import {
  RelayReplayWindow,
  decryptRelayEnvelope,
  encryptRelayEnvelope,
  type RelayInnerMessage,
  type RelayTunnelEnvelope,
} from "../../../../packages/cloud-protocol/src/index.ts";
import type { RelayEvent } from "../events/event-hub.ts";

type TunnelRequestBody = {
  method: string;
  path: string;
  headers: Record<string, string>;
  body: string;
};

type CloudTunnelAdapterOptions = {
  hostId: string;
  keyForDevice(deviceId: string): Promise<CryptoKey>;
  loadReplayState(): Promise<Record<string, number>>;
  saveReplayState(state: Record<string, number>): Promise<void>;
  loadOutgoingSequences?(): Promise<Record<string, number>>;
  saveOutgoingSequences?(state: Record<string, number>): Promise<void>;
  handler(request: Request): Promise<Response>;
  now?: () => number;
};

type PendingVoiceTransfer = {
  metadata: string;
  chunks: Buffer[];
  totalBytes: number;
  lastRecordedAtMs: number;
  timer: ReturnType<typeof setTimeout>;
  request: Omit<TunnelRequestBody, "body">;
};

const MAX_CLOCK_SKEW_MS = 5 * 60_000;

function parseTunnelRequest(inner: RelayInnerMessage): TunnelRequestBody {
  if (inner.kind !== "request" || typeof inner.body !== "object" || !inner.body) {
    throw new Error("Unsupported Relay tunnel message");
  }
  const body = inner.body as Partial<TunnelRequestBody>;
  if (
    typeof body.method !== "string" ||
    typeof body.path !== "string" ||
    !body.path.startsWith("/v1/") ||
    body.path.startsWith("//") ||
    typeof body.headers !== "object" ||
    !body.headers ||
    typeof body.body !== "string"
  ) {
    throw new Error("Invalid Relay tunnel request");
  }
  return {
    method: body.method.toUpperCase(),
    path: body.path,
    headers: body.headers as Record<string, string>,
    body: body.body,
  };
}

function responseHeaders(response: Response): Record<string, string> {
  const allowed = new Set(["content-type", "cache-control"]);
  return Object.fromEntries(
    [...response.headers.entries()].filter(([name]) => allowed.has(name)),
  );
}

export class CloudTunnelAdapter {
  readonly #options: CloudTunnelAdapterOptions;
  readonly #outgoingSequence = new Map<string, number>();
  #sequenceGate: Promise<void> = Promise.resolve();
  readonly #voiceTransfers = new Map<string, PendingVoiceTransfer>();

  constructor(options: CloudTunnelAdapterOptions) {
    this.#options = options;
  }

  get queuedActionCount(): number {
    return 0;
  }

  get pendingVoiceTransferCount(): number {
    return this.#voiceTransfers.size;
  }

  async receive(
    envelope: RelayTunnelEnvelope,
  ): Promise<RelayTunnelEnvelope | null> {
    if (
      envelope.hostId !== this.#options.hostId ||
      envelope.recipientId !== this.#options.hostId
    ) {
      throw new Error("Relay tunnel recipient mismatch");
    }
    const now = (this.#options.now ?? Date.now)();
    if (Math.abs(now - envelope.sentAt) > MAX_CLOCK_SKEW_MS) {
      throw new Error("Stale Relay tunnel message");
    }

    const replay = new RelayReplayWindow(await this.#options.loadReplayState());
    replay.accept(envelope.senderId, envelope.sequence);
    await this.#options.saveReplayState(replay.snapshot());

    const key = await this.#options.keyForDevice(envelope.senderId);
    const inner = await decryptRelayEnvelope(envelope, key);
    const requestMessage = inner.kind === "voice"
      ? this.#consumeVoiceChunk(envelope.senderId, inner.body)
      : parseTunnelRequest(inner);
    if (!requestMessage) return null;
    const decodedBody =
      requestMessage.headers["x-relay-body-encoding"] === "base64"
        ? Buffer.from(requestMessage.body, "base64")
        : requestMessage.body;
    const request = new Request(
      `http://relay.internal${requestMessage.path}`,
      {
        method: requestMessage.method,
        headers: requestMessage.headers,
        ...(!["GET", "HEAD"].includes(requestMessage.method) &&
        requestMessage.body.length > 0
          ? { body: decodedBody }
          : {}),
      },
    );
    const response = await this.#options.handler(request);
    const outgoingSequence = await this.#nextOutgoingSequence(
      envelope.senderId,
    );

    return encryptRelayEnvelope(
      {
        version: 1,
        messageId: crypto.randomUUID(),
        accountId: envelope.accountId,
        hostId: envelope.hostId,
        senderId: this.#options.hostId,
        recipientId: envelope.senderId,
        sentAt: now,
        sequence: outgoingSequence,
      },
      {
        kind: "response",
        body: {
          requestId: envelope.messageId,
          status: response.status,
          headers: responseHeaders(response),
          body: await response.text(),
        },
      },
      key,
    );
  }

  #consumeVoiceChunk(
    senderId: string,
    rawBody: unknown,
  ): TunnelRequestBody | null {
    if (!rawBody || typeof rawBody !== "object" || Array.isArray(rawBody)) {
      throw new Error("Invalid voice chunk");
    }
    const body = rawBody as Record<string, unknown>;
    const transferId = body.transferId;
    const index = body.index;
    const totalChunks = body.totalChunks;
    const recordedAtMs = body.recordedAtMs;
    const durationMs = body.durationMs;
    const method = body.method;
    const path = body.path;
    const headers = body.headers;
    const data = body.data;
    if (
      typeof transferId !== "string" ||
      transferId.length < 8 ||
      transferId.length > 128 ||
      !Number.isSafeInteger(index) ||
      !Number.isSafeInteger(totalChunks) ||
      (totalChunks as number) < 1 ||
      (totalChunks as number) > 16 ||
      (index as number) < 0 ||
      (index as number) >= (totalChunks as number) ||
      !Number.isSafeInteger(recordedAtMs) ||
      (recordedAtMs as number) < 0 ||
      !Number.isSafeInteger(durationMs) ||
      (durationMs as number) < 1 ||
      (durationMs as number) > 30_000 ||
      (recordedAtMs as number) > (durationMs as number) ||
      method !== "POST" ||
      typeof path !== "string" ||
      !path.startsWith("/v1/transcribe?durationMs=") ||
      !headers ||
      typeof headers !== "object" ||
      Array.isArray(headers) ||
      Object.values(headers).some((value) => typeof value !== "string") ||
      typeof data !== "string" ||
      data.length === 0 ||
      data.length % 4 !== 0 ||
      !/^[A-Za-z0-9+/]+={0,2}$/.test(data)
    ) {
      throw new Error("Invalid voice chunk");
    }

    const transferKey = `${senderId}:${transferId}`;
    try {
      const bytes = Buffer.from(data, "base64");
      if (
        bytes.byteLength < 1 ||
        bytes.byteLength > 128 * 1024 ||
        bytes.toString("base64") !== data
      ) {
        throw new Error("Voice chunk exceeds the 128 KiB limit");
      }
      const normalizedHeaders = headers as Record<string, string>;
      const metadata = JSON.stringify({
        totalChunks,
        durationMs,
        method,
        path,
        headers: normalizedHeaders,
      });
      let transfer = this.#voiceTransfers.get(transferKey);
      if (!transfer) {
        if (index !== 0) throw new Error("Voice chunk order is invalid");
        const timer = setTimeout(() => {
          this.#voiceTransfers.delete(transferKey);
        }, 30_000);
        timer.unref?.();
        transfer = {
          metadata,
          chunks: [],
          totalBytes: 0,
          lastRecordedAtMs: 0,
          timer,
          request: {
            method: "POST",
            path,
            headers: {
              ...normalizedHeaders,
              "x-relay-body-encoding": "base64",
            },
          },
        };
        this.#voiceTransfers.set(transferKey, transfer);
      }
      if (
        transfer.metadata !== metadata ||
        index !== transfer.chunks.length ||
        (recordedAtMs as number) < transfer.lastRecordedAtMs
      ) {
        throw new Error("Voice chunk order is invalid");
      }
      transfer.chunks.push(bytes);
      transfer.totalBytes += bytes.byteLength;
      transfer.lastRecordedAtMs = recordedAtMs as number;
      if (transfer.totalBytes > 2 * 1024 * 1024) {
        throw new Error("Voice transfer exceeds the 2 MiB limit");
      }
      if (index !== (totalChunks as number) - 1) return null;

      clearTimeout(transfer.timer);
      this.#voiceTransfers.delete(transferKey);
      return {
        ...transfer.request,
        body: Buffer.concat(transfer.chunks).toString("base64"),
      };
    } catch (error) {
      const transfer = this.#voiceTransfers.get(transferKey);
      if (transfer) clearTimeout(transfer.timer);
      this.#voiceTransfers.delete(transferKey);
      throw error;
    }
  }

  async pushEvent(input: {
    accountId: string;
    deviceId: string;
    event: RelayEvent;
  }): Promise<RelayTunnelEnvelope> {
    const now = (this.#options.now ?? Date.now)();
    const key = await this.#options.keyForDevice(input.deviceId);
    return encryptRelayEnvelope(
      {
        version: 1,
        messageId: crypto.randomUUID(),
        accountId: input.accountId,
        hostId: this.#options.hostId,
        senderId: this.#options.hostId,
        recipientId: input.deviceId,
        sentAt: now,
        sequence: await this.#nextOutgoingSequence(input.deviceId),
      },
      { kind: "event", body: input.event },
      key,
    );
  }

  async #nextOutgoingSequence(deviceId: string): Promise<number> {
    let next = 0;
    const update = this.#sequenceGate.then(async () => {
      const persisted = this.#options.loadOutgoingSequences
        ? await this.#options.loadOutgoingSequences()
        : Object.fromEntries(this.#outgoingSequence);
      next = (persisted[deviceId] ?? 0) + 1;
      persisted[deviceId] = next;
      if (this.#options.saveOutgoingSequences) {
        await this.#options.saveOutgoingSequences(persisted);
      } else {
        this.#outgoingSequence.set(deviceId, next);
      }
    });
    this.#sequenceGate = update.catch(() => {});
    await update;
    return next;
  }
}
