import { resolveTunnelPeer } from "./cloud-runtime.ts";
import { D1CommandGateway } from "./d1-gateway.ts";
import { D1CloudRepository } from "./d1-repository.ts";
import { DurableTunnelSession } from "./durable-tunnel.ts";
import { purgeExpiredCloudData } from "./purge.ts";
import { createResendMagicLinkSender } from "./resend.ts";
import { createWorker } from "./worker.ts";

type DurableObjectId = unknown;
type DurableObjectStub = {
  fetch(request: Request): Promise<Response>;
};
type DurableObjectNamespace = {
  idFromName(name: string): DurableObjectId;
  get(id: DurableObjectId): DurableObjectStub;
};
type DurableObjectState = {
  getWebSockets(): DurableWebSocket[];
  acceptWebSocket(socket: DurableWebSocket): void;
};
type DurableWebSocket = WebSocket & {
  serializeAttachment(value: unknown): void;
  deserializeAttachment(): unknown;
};
type WebSocketPairInstance = {
  0: WebSocket;
  1: DurableWebSocket;
};

declare const WebSocketPair: {
  new (): WebSocketPairInstance;
};

type CloudEnvironment = {
  DB: ConstructorParameters<typeof D1CloudRepository>[0];
  ACCOUNT_TUNNEL: DurableObjectNamespace;
  JWT_SECRET: string;
  PII_ENCRYPTION_KEY: string;
  EMAIL_HMAC_KEY: string;
  RESEND_API_KEY: string;
  RESEND_FROM: string;
  PUBLIC_ORIGIN: string;
};

function secret(value: string): Uint8Array {
  const bytes = Buffer.from(value, "base64url");
  if (bytes.byteLength !== 32) throw new Error("Invalid Worker secret");
  return new Uint8Array(bytes);
}

function jsonError(status: number, code: string, message: string): Response {
  return Response.json(
    { error: { code, message } },
    {
      status,
      headers: {
        "cache-control": "no-store",
        "x-content-type-options": "nosniff",
      },
    },
  );
}

async function connectTunnel(
  request: Request,
  environment: CloudEnvironment,
  repository: D1CloudRepository,
): Promise<Response> {
  try {
    const peer = await resolveTunnelPeer(request, repository);
    const objectId = environment.ACCOUNT_TUNNEL.idFromName(peer.accountId);
    const stub = environment.ACCOUNT_TUNNEL.get(objectId);
    return stub.fetch(
      new Request("https://relay.internal/connect", {
        headers: {
          upgrade: "websocket",
          "x-relay-peer": JSON.stringify(peer),
        },
      }),
    );
  } catch (error) {
    if (
      error instanceof Error &&
      error.message === "WebSocket upgrade required"
    ) {
      return jsonError(426, "upgrade_required", "WebSocket upgrade required");
    }
    return jsonError(
      401,
      "authentication_failed",
      "Authentication failed",
    );
  }
}

function runtime(environment: CloudEnvironment) {
  const repository = new D1CloudRepository(environment.DB);
  const gateway = new D1CommandGateway(repository, {
    jwtSecret: secret(environment.JWT_SECRET),
    piiKey: secret(environment.PII_ENCRYPTION_KEY),
    emailHmacKey: secret(environment.EMAIL_HMAC_KEY),
    publicOrigin: environment.PUBLIC_ORIGIN,
    sendMagicLink: createResendMagicLinkSender({
      apiKey: environment.RESEND_API_KEY,
      from: environment.RESEND_FROM,
    }),
    notifyHost: async (accountId, hostId, message) => {
      const objectId = environment.ACCOUNT_TUNNEL.idFromName(accountId);
      const response = await environment.ACCOUNT_TUNNEL.get(objectId).fetch(
        new Request("https://relay.internal/control", {
          method: "POST",
          headers: { "content-type": "application/json" },
          body: JSON.stringify({ hostId, message }),
        }),
      );
      if (!response.ok) throw new Error("Host notification failed");
    },
    emergencyStopTunnels: async (accountId, hostId, deviceIds) => {
      const objectId = environment.ACCOUNT_TUNNEL.idFromName(accountId);
      const response = await environment.ACCOUNT_TUNNEL.get(objectId).fetch(
        new Request("https://relay.internal/emergency-stop", {
          method: "POST",
          headers: { "content-type": "application/json" },
          body: JSON.stringify({ hostId, deviceIds }),
        }),
      );
      if (!response.ok) throw new Error("Emergency stop notification failed");
    },
    revokeTunnelPeer: async (accountId, deviceId) => {
      const objectId = environment.ACCOUNT_TUNNEL.idFromName(accountId);
      const response = await environment.ACCOUNT_TUNNEL.get(objectId).fetch(
        new Request("https://relay.internal/revoke", {
          method: "POST",
          headers: { "content-type": "application/json" },
          body: JSON.stringify({ deviceId }),
        }),
      );
      if (!response.ok) throw new Error("Device revocation notification failed");
    },
  });
  return { repository, worker: createWorker(gateway) };
}

export default {
  async fetch(
    request: Request,
    environment: CloudEnvironment,
  ): Promise<Response> {
    const { repository, worker } = runtime(environment);
    const path = new URL(request.url).pathname;
    if (
      path === "/cloud/v1/connect/host" ||
      path === "/cloud/v1/connect/device"
    ) {
      return connectTunnel(request, environment, repository);
    }
    return worker.fetch(request);
  },

  async scheduled(
    _controller: unknown,
    environment: CloudEnvironment,
  ): Promise<void> {
    await purgeExpiredCloudData(environment.DB);
  },
};

export class AccountTunnel {
  readonly #state: DurableObjectState;
  readonly #session: DurableTunnelSession;

  constructor(state: DurableObjectState) {
    this.#state = state;
    this.#session = new DurableTunnelSession(state.getWebSockets());
  }

  async fetch(request: Request): Promise<Response> {
    const url = new URL(request.url);
    if (request.method === "POST" && url.pathname === "/control") {
      try {
        const raw = await request.text();
        if (new TextEncoder().encode(raw).byteLength > 16_384) {
          throw new Error("Invalid control message");
        }
        const control = JSON.parse(raw) as {
          hostId?: unknown;
          message?: unknown;
        };
        if (
          typeof control.hostId !== "string" ||
          !control.message ||
          typeof control.message !== "object" ||
          !["pairing_request", "device_revoked", "emergency_stop"].includes(
            String((control.message as { type?: unknown }).type),
          )
        ) {
          throw new Error("Invalid control message");
        }
        return Response.json({
          status: this.#session.sendControl(
            control.hostId,
            control.message as Record<string, unknown>,
          ),
        });
      } catch {
        return jsonError(400, "invalid_control", "Invalid control message");
      }
    }
    if (request.method === "POST" && url.pathname === "/emergency-stop") {
      try {
        const raw = await request.text();
        if (new TextEncoder().encode(raw).byteLength > 16_384) {
          throw new Error("Invalid emergency stop");
        }
        const command = JSON.parse(raw) as {
          hostId?: unknown;
          deviceIds?: unknown;
        };
        if (
          typeof command.hostId !== "string" ||
          !Array.isArray(command.deviceIds) ||
          command.deviceIds.some((id) => typeof id !== "string")
        ) {
          throw new Error("Invalid emergency stop");
        }
        this.#session.emergencyStop(
          command.hostId,
          command.deviceIds as string[],
        );
        return Response.json({ ok: true });
      } catch {
        return jsonError(400, "invalid_control", "Invalid control message");
      }
    }
    if (request.method === "POST" && url.pathname === "/revoke") {
      try {
        const raw = await request.text();
        if (new TextEncoder().encode(raw).byteLength > 4_096) {
          throw new Error("Invalid revocation");
        }
        const command = JSON.parse(raw) as { deviceId?: unknown };
        if (typeof command.deviceId !== "string") {
          throw new Error("Invalid revocation");
        }
        this.#session.revoke(command.deviceId);
        return Response.json({ ok: true });
      } catch {
        return jsonError(400, "invalid_control", "Invalid control message");
      }
    }
    if (request.headers.get("upgrade")?.toLowerCase() !== "websocket") {
      return jsonError(426, "upgrade_required", "WebSocket upgrade required");
    }
    let peer: unknown;
    try {
      peer = JSON.parse(request.headers.get("x-relay-peer") ?? "");
    } catch {
      return jsonError(
        401,
        "authentication_failed",
        "Authentication failed",
      );
    }
    if (
      !peer ||
      typeof peer !== "object" ||
      typeof (peer as { accountId?: unknown }).accountId !== "string" ||
      typeof (peer as { hostId?: unknown }).hostId !== "string" ||
      typeof (peer as { peerId?: unknown }).peerId !== "string" ||
      !["host", "device"].includes(
        String((peer as { role?: unknown }).role),
      )
    ) {
      return jsonError(
        401,
        "authentication_failed",
        "Authentication failed",
      );
    }

    const pair = new WebSocketPair();
    const client = pair[0];
    const server = pair[1];
    this.#state.acceptWebSocket(server);
    this.#session.accept(
      peer as {
        accountId: string;
        hostId: string;
        peerId: string;
        role: "host" | "device";
      },
      server,
    );
    return new Response(null, {
      status: 101,
      webSocket: client,
    } as ResponseInit);
  }

  webSocketMessage(
    socket: DurableWebSocket,
    message: string | ArrayBuffer,
  ): void {
    this.#session.message(socket, message);
  }

  webSocketClose(socket: DurableWebSocket): void {
    this.#session.close(socket);
  }

  webSocketError(socket: DurableWebSocket): void {
    this.#session.close(socket);
  }
}
