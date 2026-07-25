const textEncoder = new TextEncoder();
const textDecoder = new TextDecoder();

export const RELAY_E2EE_VERSION = 1;
export const RELAY_E2EE_INFO = "relay-e2ee-v1";
export const RELAY_VOICE_CHUNK_BYTES = 128 * 1024;
export const RELAY_VOICE_MAX_BYTES = 2 * 1024 * 1024;
export const RELAY_VOICE_MAX_DURATION_MS = 30_000;

export type RelayRoutingFields = {
  version: 1;
  messageId: string;
  accountId: string;
  hostId: string;
  senderId: string;
  recipientId: string;
  sentAt: number;
  sequence: number;
};

export type RelayTunnelEnvelope = RelayRoutingFields & {
  nonce: string;
  ciphertext: string;
};

export type RelayInnerMessage = {
  kind: "request" | "response" | "event" | "control" | "voice";
  body: unknown;
};

function base64UrlEncode(value: ArrayBuffer | Uint8Array): string {
  const bytes = value instanceof Uint8Array ? value : new Uint8Array(value);
  return Buffer.from(bytes).toString("base64url");
}

function base64UrlDecode(value: string): Uint8Array {
  return new Uint8Array(Buffer.from(value, "base64url"));
}

function assertRoutingFields(fields: RelayRoutingFields): void {
  if (fields.version !== RELAY_E2EE_VERSION) {
    throw new Error("Unsupported Relay encryption version");
  }
  for (const [name, value] of Object.entries(fields)) {
    if (name === "version" || name === "sentAt" || name === "sequence") continue;
    if (typeof value !== "string" || value.length === 0 || value.length > 256) {
      throw new Error(`Invalid Relay routing field: ${name}`);
    }
  }
  if (!Number.isSafeInteger(fields.sentAt) || fields.sentAt < 0) {
    throw new Error("Invalid Relay sentAt");
  }
  if (!Number.isSafeInteger(fields.sequence) || fields.sequence < 1) {
    throw new Error("Invalid Relay sequence");
  }
}

export function canonicalRelayAAD(fields: RelayRoutingFields): Uint8Array {
  assertRoutingFields(fields);
  return textEncoder.encode(
    JSON.stringify({
      version: fields.version,
      messageId: fields.messageId,
      accountId: fields.accountId,
      hostId: fields.hostId,
      senderId: fields.senderId,
      recipientId: fields.recipientId,
      sentAt: fields.sentAt,
      sequence: fields.sequence,
    }),
  );
}

export async function generateAgreementKeyPair(): Promise<CryptoKeyPair> {
  return crypto.subtle.generateKey(
    { name: "ECDH", namedCurve: "P-256" },
    false,
    ["deriveBits"],
  );
}

export async function encodePublicKey(key: CryptoKey): Promise<string> {
  return base64UrlEncode(await crypto.subtle.exportKey("raw", key));
}

export async function decodePublicKey(encoded: string): Promise<CryptoKey> {
  return crypto.subtle.importKey(
    "raw",
    base64UrlDecode(encoded),
    { name: "ECDH", namedCurve: "P-256" },
    true,
    [],
  );
}

export async function deriveRelayRootKey(
  privateKey: CryptoKey,
  peerPublicKey: CryptoKey,
  pairingSessionNonce: Uint8Array,
): Promise<CryptoKey> {
  if (pairingSessionNonce.byteLength < 16) {
    throw new Error("Pairing session nonce must be at least 128 bits");
  }
  const sharedSecret = await crypto.subtle.deriveBits(
    { name: "ECDH", public: peerPublicKey },
    privateKey,
    256,
  );
  const hkdfKey = await crypto.subtle.importKey(
    "raw",
    sharedSecret,
    "HKDF",
    false,
    ["deriveKey"],
  );
  return crypto.subtle.deriveKey(
    {
      name: "HKDF",
      hash: "SHA-256",
      salt: pairingSessionNonce,
      info: textEncoder.encode(RELAY_E2EE_INFO),
    },
    hkdfKey,
    { name: "AES-GCM", length: 256 },
    false,
    ["encrypt", "decrypt"],
  );
}

export async function encryptRelayEnvelope(
  routing: RelayRoutingFields,
  inner: RelayInnerMessage,
  rootKey: CryptoKey,
  suppliedNonce?: Uint8Array,
): Promise<RelayTunnelEnvelope> {
  const nonce = suppliedNonce ?? crypto.getRandomValues(new Uint8Array(12));
  if (nonce.byteLength !== 12) {
    throw new Error("Relay AES-GCM nonce must be 96 bits");
  }
  const ciphertext = await crypto.subtle.encrypt(
    {
      name: "AES-GCM",
      iv: nonce,
      additionalData: canonicalRelayAAD(routing),
      tagLength: 128,
    },
    rootKey,
    textEncoder.encode(JSON.stringify(inner)),
  );
  return {
    ...routing,
    nonce: base64UrlEncode(nonce),
    ciphertext: base64UrlEncode(ciphertext),
  };
}

export async function decryptRelayEnvelope(
  envelope: RelayTunnelEnvelope,
  rootKey: CryptoKey,
): Promise<RelayInnerMessage> {
  const { nonce, ciphertext, ...routing } = envelope;
  try {
    const plaintext = await crypto.subtle.decrypt(
      {
        name: "AES-GCM",
        iv: base64UrlDecode(nonce),
        additionalData: canonicalRelayAAD(routing),
        tagLength: 128,
      },
      rootKey,
      base64UrlDecode(ciphertext),
    );
    const inner = JSON.parse(textDecoder.decode(plaintext)) as RelayInnerMessage;
    if (
      !inner ||
      !["request", "response", "event", "control", "voice"].includes(inner.kind)
    ) {
      throw new Error("Invalid inner message");
    }
    return inner;
  } catch {
    throw new Error("Relay envelope authentication failed");
  }
}

export class RelayReplayWindow {
  readonly #highestSequence: Map<string, number>;

  constructor(snapshot: Record<string, number> = {}) {
    this.#highestSequence = new Map(Object.entries(snapshot));
  }

  accept(senderId: string, sequence: number): void {
    if (!Number.isSafeInteger(sequence) || sequence < 1) {
      throw new Error("Invalid Relay sequence");
    }
    const highest = this.#highestSequence.get(senderId) ?? 0;
    if (sequence <= highest) {
      throw new Error("Relay replay rejected");
    }
    this.#highestSequence.set(senderId, sequence);
  }

  snapshot(): Record<string, number> {
    return Object.fromEntries(this.#highestSequence);
  }
}

export type RelayVoiceChunk = {
  index: number;
  byteLength: number;
  recordedAtMs: number;
};

export function validateVoiceTransfer(chunks: RelayVoiceChunk[]): void {
  let totalBytes = 0;
  let previousTime = 0;
  for (let index = 0; index < chunks.length; index += 1) {
    const chunk = chunks[index]!;
    if (chunk.index !== index) throw new Error("Voice chunk order is invalid");
    if (
      !Number.isSafeInteger(chunk.byteLength) ||
      chunk.byteLength < 1 ||
      chunk.byteLength > RELAY_VOICE_CHUNK_BYTES
    ) {
      throw new Error("Voice chunk exceeds the 128 KiB limit");
    }
    if (
      !Number.isFinite(chunk.recordedAtMs) ||
      chunk.recordedAtMs < previousTime
    ) {
      throw new Error("Voice chunk timestamps are invalid");
    }
    totalBytes += chunk.byteLength;
    previousTime = chunk.recordedAtMs;
  }
  if (totalBytes > RELAY_VOICE_MAX_BYTES) {
    throw new Error("Voice transfer exceeds the 2 MiB limit");
  }
  if (chunks.length > 0 && previousTime - chunks[0]!.recordedAtMs > RELAY_VOICE_MAX_DURATION_MS) {
    throw new Error("Voice duration exceeds the 30 second limit");
  }
}
