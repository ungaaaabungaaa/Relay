import type { RelayTunnelEnvelope } from "../../../packages/cloud-protocol/src/index.ts";

export type TunnelPeer = {
  accountId: string;
  hostId: string;
  peerId: string;
  role: "host" | "device";
};

export type TunnelSocket = {
  send(message: string): void;
  close(code: number, reason: string): void;
};

type ConnectedPeer = TunnelPeer & { socket: TunnelSocket };

const AUTH_ERROR = "Authentication failed";

export class HibernatingTunnelRouter {
  readonly #peers = new Map<string, ConnectedPeer>();
  readonly #revoked = new Set<string>();

  get queuedMessageCount(): number {
    return 0;
  }

  connect(peer: TunnelPeer, socket: TunnelSocket): void {
    if (this.#revoked.has(peer.peerId)) {
      socket.close(4003, "Device revoked");
      return;
    }
    const existing = this.#peers.get(peer.peerId);
    existing?.socket.close(4001, "Reconnected");
    this.#peers.set(peer.peerId, { ...peer, socket });
  }

  disconnect(peerId: string, socket?: TunnelSocket): void {
    const existing = this.#peers.get(peerId);
    if (!existing || (socket && existing.socket !== socket)) return;
    this.#peers.delete(peerId);
    if (existing.role === "host") {
      for (const peer of this.#peers.values()) {
        if (
          peer.role === "device" &&
          peer.accountId === existing.accountId &&
          peer.hostId === existing.hostId
        ) {
          peer.socket.send(
            JSON.stringify({ type: "host_offline", hostId: existing.hostId }),
          );
        }
      }
    }
  }

  route(envelope: RelayTunnelEnvelope): "delivered" | "offline" {
    const sender = this.#peers.get(envelope.senderId);
    if (
      !sender ||
      this.#revoked.has(envelope.senderId) ||
      sender.accountId !== envelope.accountId ||
      sender.hostId !== envelope.hostId ||
      (sender.role === "host" && sender.peerId !== envelope.hostId)
    ) {
      throw new Error(AUTH_ERROR);
    }
    const recipient = this.#peers.get(envelope.recipientId);
    if (
      recipient &&
      recipient.accountId === sender.accountId &&
      recipient.hostId === sender.hostId &&
      !this.#revoked.has(recipient.peerId)
    ) {
      recipient.socket.send(JSON.stringify(envelope));
      return "delivered";
    }
    if (sender.role === "device") {
      sender.socket.send(
        JSON.stringify({ type: "host_offline", hostId: sender.hostId }),
      );
    }
    return "offline";
  }

  sendControl(
    hostId: string,
    message: Record<string, unknown>,
  ): "delivered" | "offline" {
    const host = this.#peers.get(hostId);
    if (
      !host ||
      host.role !== "host" ||
      host.peerId !== host.hostId ||
      this.#revoked.has(host.peerId)
    ) {
      return "offline";
    }
    host.socket.send(JSON.stringify(message));
    return "delivered";
  }

  revoke(peerId: string): void {
    this.#revoked.add(peerId);
    const connected = this.#peers.get(peerId);
    if (connected) {
      connected.socket.close(4003, "Device revoked");
      this.#peers.delete(peerId);
    }
  }

  terminate(peerId: string, code: number, reason: string): void {
    const connected = this.#peers.get(peerId);
    if (!connected) return;
    connected.socket.close(code, reason);
    this.disconnect(peerId, connected.socket);
  }
}
