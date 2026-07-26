import type { AuthenticatedTunnelPeer } from "./d1-repository.ts";

const AUTH_ERROR = "Authentication failed";

type TunnelCredentialRepository = {
  authenticateHost(
    hostId: string,
    credentialHash: string,
  ): Promise<AuthenticatedTunnelPeer>;
  authenticateDevice(
    deviceId: string,
    credentialHash: string,
  ): Promise<AuthenticatedTunnelPeer>;
};

function bearerCredential(request: Request): string {
  const authorization = request.headers.get("authorization");
  if (!authorization?.startsWith("Bearer ")) throw new Error(AUTH_ERROR);
  const credential = authorization.slice(7);
  if (credential.length < 16) throw new Error(AUTH_ERROR);
  return credential;
}

async function sha256(value: string): Promise<string> {
  return Buffer.from(
    await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value)),
  ).toString("base64url");
}

export async function resolveTunnelPeer(
  request: Request,
  repository: TunnelCredentialRepository,
): Promise<AuthenticatedTunnelPeer> {
  if (request.headers.get("upgrade")?.toLowerCase() !== "websocket") {
    throw new Error("WebSocket upgrade required");
  }
  const path = new URL(request.url).pathname;
  const credentialHash = await sha256(bearerCredential(request));
  if (path === "/cloud/v1/connect/host") {
    const hostId = request.headers.get("x-relay-host-id");
    if (!hostId) throw new Error(AUTH_ERROR);
    return repository.authenticateHost(hostId, credentialHash);
  }
  if (path === "/cloud/v1/connect/device") {
    const deviceId = request.headers.get("x-relay-device-id");
    if (!deviceId) throw new Error(AUTH_ERROR);
    return repository.authenticateDevice(deviceId, credentialHash);
  }
  throw new Error(AUTH_ERROR);
}
