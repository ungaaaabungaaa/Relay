import { createHash, createPublicKey, verify } from "node:crypto";
import type { SecurityStore } from "./store.ts";

export type SignedRequestBase = {
  deviceId: string;
  method: string;
  path: string;
  body: Uint8Array;
  timestamp: number;
  nonce: string;
};

export function canonicalRequest(input: SignedRequestBase): string {
  const digest = createHash("sha256").update(input.body).digest("hex");
  return [
    input.deviceId,
    input.method.toUpperCase(),
    input.path,
    digest,
    String(input.timestamp),
    input.nonce,
  ].join("\n");
}

export function verifyRequest(
  store: SecurityStore,
  input: SignedRequestBase & { signature: string },
  now = Date.now(),
): string {
  if (Math.abs(now - input.timestamp) > 120_000) {
    throw new Error("stale request");
  }
  if (input.nonce.length < 16) throw new Error("invalid nonce");
  const device = store.getDevice(input.deviceId);
  if (!device || device.revokedAt !== null) throw new Error("unknown or revoked device");
  const valid = verify(
    null,
    Buffer.from(canonicalRequest(input)),
    createPublicKey(device.publicKey),
    Buffer.from(input.signature, "base64"),
  );
  if (!valid) throw new Error("invalid signature");
  if (!store.consumeNonce(device.id, input.nonce)) throw new Error("replayed nonce");
  return device.id;
}
