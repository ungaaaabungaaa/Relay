import { createHash, timingSafeEqual } from "node:crypto";
import {
  createServer,
  type IncomingMessage,
  type Server,
  type ServerResponse,
} from "node:http";
import type { AddressInfo } from "node:net";
import { PairingService } from "../security/pairing.ts";
import type { SecurityStore } from "../security/store.ts";
import {
  WorkspacePolicyError,
  type WorkspacePolicy,
} from "../workspaces/workspace-policy.ts";

type CodexStatus = "ready" | "starting" | "unavailable";

export type AdminServerOptions = {
  token: string;
  store: SecurityStore;
  workspacePolicy: WorkspacePolicy;
  adminBindHost: string;
  watchBindHost: string;
  watchPort: number;
  codexStatus: () => CodexStatus;
  voiceConfigured: boolean;
  shutdown: () => void;
};

const json = (body: unknown, status = 200) =>
  Response.json(body, {
    status,
    headers: { "cache-control": "no-store" },
  });

function assertStrongToken(token: string) {
  if (Buffer.byteLength(token, "utf8") < 32) {
    throw new Error("admin bearer token must contain at least 256-bit");
  }
}

function hasValidBearer(request: Request, token: string) {
  const actual = Buffer.from(request.headers.get("authorization") ?? "", "utf8");
  const expected = Buffer.from(`Bearer ${token}`, "utf8");
  return actual.length === expected.length && timingSafeEqual(actual, expected);
}

async function parseJson(request: Request) {
  const text = await request.text();
  if (text.length > 64_000) throw new Error("body too large");
  return text ? (JSON.parse(text) as Record<string, unknown>) : {};
}

function publicDevice(device: ReturnType<SecurityStore["listDevices"]>[number]) {
  const digest = createHash("sha256").update(device.publicKey).digest("hex");
  return {
    id: device.id,
    name: device.name,
    fingerprint: digest.match(/.{1,4}/g)?.slice(0, 8).join(":") ?? digest,
    createdAt: device.createdAt,
    revokedAt: device.revokedAt,
  };
}

export function assertLoopbackAdminHost(host: string) {
  if (host !== "127.0.0.1" && host !== "::1") {
    throw new Error("admin server must bind to a loopback address");
  }
}

export function createAdminRequestHandler(options: AdminServerOptions) {
  assertStrongToken(options.token);
  return async (request: Request): Promise<Response> => {
    if (!hasValidBearer(request, options.token)) {
      return json({ error: "unauthorized" }, 401);
    }

    const url = new URL(request.url);
    try {
      if (request.method === "GET" && url.pathname === "/health") {
        return json({ ok: true, service: "relay-admin" });
      }
      if (request.method === "GET" && url.pathname === "/v1/status") {
        return json({
          bridge: "running",
          codex: options.codexStatus(),
          watch: {
            host: options.watchBindHost,
            port: options.watchPort,
          },
          activeDevices: options.store
            .listDevices()
            .filter((device) => device.revokedAt === null).length,
        });
      }
      if (
        request.method === "POST" &&
        url.pathname === "/v1/security/self-test"
      ) {
        const checks = {
          adminLoopbackOnly:
            options.adminBindHost === "127.0.0.1" ||
            options.adminBindHost === "::1",
          watchLoopbackOnly:
            options.watchBindHost === "127.0.0.1" ||
            options.watchBindHost === "::1",
          strongAdminToken: Buffer.byteLength(options.token, "utf8") >= 32,
        };
        return json({
          ok: Object.values(checks).every(Boolean),
          checks,
        });
      }
      if (request.method === "POST" && url.pathname === "/v1/pairing-code") {
        const now = Date.now();
        const code = new PairingService(options.store, () => now).createCode();
        return json({ code, expiresAt: now + 300_000 }, 201);
      }
      if (request.method === "GET" && url.pathname === "/v1/devices") {
        return json({ devices: options.store.listDevices().map(publicDevice) });
      }
      const revoke = url.pathname.match(/^\/v1\/devices\/([^/]+)\/revoke$/);
      if (request.method === "POST" && revoke?.[1]) {
        const deviceId = decodeURIComponent(revoke[1]);
        if (!options.store.getDevice(deviceId)) {
          return json({ error: "not found" }, 404);
        }
        options.store.revokeDevice(deviceId);
        options.store.audit(null, "device.revoke", deviceId, "succeeded");
        return json({ ok: true });
      }
      if (request.method === "GET" && url.pathname === "/v1/workspaces") {
        return json({ roots: await options.workspacePolicy.roots() });
      }
      if (request.method === "PUT" && url.pathname === "/v1/workspaces") {
        const body = await parseJson(request);
        if (
          !Array.isArray(body.roots) ||
          body.roots.some((root) => typeof root !== "string")
        ) {
          return json({ error: "invalid request" }, 400);
        }
        const roots = await options.workspacePolicy.replaceRoots(body.roots);
        options.store.audit(null, "workspaces.replace", null, "succeeded");
        return json({ roots });
      }
      if (request.method === "GET" && url.pathname === "/v1/voice") {
        return json({
          configured: options.voiceConfigured,
          provider: options.voiceConfigured ? "openai" : null,
        });
      }
      if (request.method === "POST" && url.pathname === "/v1/shutdown") {
        setImmediate(options.shutdown);
        return json({ stopping: true }, 202);
      }
      return json({ error: "not found" }, 404);
    } catch (error) {
      if (error instanceof WorkspacePolicyError) {
        return json({ error: error.message }, 400);
      }
      return json({ error: "invalid request" }, 400);
    }
  };
}

async function nodeRequest(request: IncomingMessage, limit = 128_000) {
  const chunks: Buffer[] = [];
  let size = 0;
  for await (const chunk of request) {
    const buffer = Buffer.from(chunk);
    size += buffer.length;
    if (size > limit) throw new Error("body too large");
    chunks.push(buffer);
  }
  return new Request(
    `http://${request.headers.host ?? "127.0.0.1"}${request.url ?? "/"}`,
    {
      method: request.method,
      headers: request.headers as HeadersInit,
      ...(chunks.length ? { body: Buffer.concat(chunks), duplex: "half" } : {}),
    } as RequestInit,
  );
}

async function sendNodeResponse(response: Response, target: ServerResponse) {
  target.statusCode = response.status;
  response.headers.forEach((value, name) => target.setHeader(name, value));
  target.end(Buffer.from(await response.arrayBuffer()));
}

export function createAdminServer(options: AdminServerOptions): Server {
  const handler = createAdminRequestHandler(options);
  return createServer(async (request, response) => {
    try {
      await sendNodeResponse(await handler(await nodeRequest(request)), response);
    } catch {
      response.statusCode = 400;
      response.end(JSON.stringify({ error: "invalid request" }));
    }
  });
}

export function listenAdminServer(
  options: AdminServerOptions,
  port: number,
  host: string,
  onListening?: (address: AddressInfo) => void,
) {
  assertLoopbackAdminHost(host);
  const server = createAdminServer(options);
  server.listen(port, host, () => {
    const address = server.address();
    if (address && typeof address !== "string") onListening?.(address);
  });
  return server;
}
