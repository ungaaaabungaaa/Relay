import {
  RelayReplayWindow,
  decryptRelayEnvelope,
  encryptRelayEnvelope,
  type RelayInnerMessage,
  type RelayTunnelEnvelope,
} from "../../../../packages/cloud-protocol/src/index.ts";

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

  constructor(options: CloudTunnelAdapterOptions) {
    this.#options = options;
  }

  get queuedActionCount(): number {
    return 0;
  }

  async receive(envelope: RelayTunnelEnvelope): Promise<RelayTunnelEnvelope> {
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
    const requestMessage = parseTunnelRequest(
      await decryptRelayEnvelope(envelope, key),
    );
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
    const persistedOutgoing = this.#options.loadOutgoingSequences
      ? await this.#options.loadOutgoingSequences()
      : Object.fromEntries(this.#outgoingSequence);
    const outgoingSequence = (persistedOutgoing[envelope.senderId] ?? 0) + 1;
    persistedOutgoing[envelope.senderId] = outgoingSequence;
    if (this.#options.saveOutgoingSequences) {
      await this.#options.saveOutgoingSequences(persistedOutgoing);
    } else {
      this.#outgoingSequence.set(envelope.senderId, outgoingSequence);
    }

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
}
