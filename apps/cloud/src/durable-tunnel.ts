import type { RelayTunnelEnvelope } from "../../../packages/cloud-protocol/src/index.ts";
import {
  HibernatingTunnelRouter,
  type TunnelPeer,
  type TunnelSocket,
} from "./tunnel-router.ts";

type DurableSocket = TunnelSocket & {
  serializeAttachment(value: unknown): void;
  deserializeAttachment(): unknown;
};

function isTunnelPeer(value: unknown): value is TunnelPeer {
  if (!value || typeof value !== "object") return false;
  const peer = value as Partial<TunnelPeer>;
  return (
    typeof peer.accountId === "string" &&
    typeof peer.hostId === "string" &&
    typeof peer.peerId === "string" &&
    (peer.role === "host" || peer.role === "device")
  );
}

export class DurableTunnelSession {
  readonly #router = new HibernatingTunnelRouter();
  readonly #peers = new Map<DurableSocket, TunnelPeer>();

  constructor(existingSockets: DurableSocket[]) {
    for (const socket of existingSockets) {
      const peer = socket.deserializeAttachment();
      if (!isTunnelPeer(peer)) {
        socket.close(4002, "Invalid session");
        continue;
      }
      this.#peers.set(socket, peer);
      this.#router.connect(peer, socket);
    }
  }

  accept(peer: TunnelPeer, socket: DurableSocket): void {
    socket.serializeAttachment(peer);
    this.#peers.set(socket, peer);
    this.#router.connect(peer, socket);
  }

  message(socket: DurableSocket, value: string | ArrayBuffer): void {
    try {
      if (typeof value !== "string") throw new Error("Binary messages unsupported");
      const envelope = JSON.parse(value) as RelayTunnelEnvelope;
      if (
        !envelope ||
        envelope.version !== 1 ||
        typeof envelope.ciphertext !== "string" ||
        typeof envelope.nonce !== "string"
      ) {
        throw new Error("Invalid envelope");
      }
      this.#router.route(envelope);
    } catch {
      const peer = this.#peers.get(socket);
      if (peer) this.#router.disconnect(peer.peerId, socket);
      this.#peers.delete(socket);
      socket.close(4002, "Invalid message");
    }
  }

  close(socket: DurableSocket): void {
    const peer = this.#peers.get(socket);
    if (!peer) return;
    this.#router.disconnect(peer.peerId, socket);
    this.#peers.delete(socket);
  }

  revoke(peerId: string): void {
    this.#router.revoke(peerId);
  }
}
