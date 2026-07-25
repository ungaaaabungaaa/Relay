type CommandGateway = {
  command(name: string, args: unknown, request: Request): Promise<unknown>;
};

const MAX_RELAY_BODY_BYTES = 2 * 1024 * 1024;

const staticCommands = new Map<string, string>([
  ["POST /cloud/v1/auth/device-sessions", "auth.deviceSessions.create"],
  ["POST /cloud/v1/auth/magic-links", "auth.magicLinks.create"],
  ["POST /cloud/v1/auth/refresh", "auth.refresh"],
  ["POST /cloud/v1/auth/logout", "auth.logout"],
  ["DELETE /cloud/v1/account", "account.delete"],
  ["POST /cloud/v1/hosts", "hosts.create"],
  ["POST /cloud/v1/relay", "relay.send"],
  ["POST /cloud/v1/emergency-stop", "emergencyStop"],
]);

const dynamicCommands: Array<{
  method: string;
  pattern: RegExp;
  command: string;
}> = [
  {
    method: "POST",
    pattern: /^\/cloud\/v1\/auth\/device-sessions\/([^/]+)\/token$/,
    command: "auth.deviceSessions.token",
  },
  {
    method: "POST",
    pattern: /^\/cloud\/v1\/hosts\/([^/]+)\/pairing-sessions$/,
    command: "pairingSessions.create",
  },
  {
    method: "POST",
    pattern: /^\/cloud\/v1\/pairing-sessions\/([^/]+)\/requests$/,
    command: "pairingSessions.request",
  },
  {
    method: "POST",
    pattern: /^\/cloud\/v1\/pairing-sessions\/([^/]+)\/approve$/,
    command: "pairingSessions.approve",
  },
  {
    method: "POST",
    pattern: /^\/cloud\/v1\/pairing-sessions\/([^/]+)\/deny$/,
    command: "pairingSessions.deny",
  },
  {
    method: "POST",
    pattern: /^\/cloud\/v1\/devices\/([^/]+)\/revoke$/,
    command: "devices.revoke",
  },
];

function json(value: unknown, status = 200): Response {
  return new Response(JSON.stringify(value), {
    status,
    headers: {
      "content-type": "application/json; charset=utf-8",
      "cache-control": "no-store",
      "x-content-type-options": "nosniff",
    },
  });
}

function publicPage(title: string, body: string): Response {
  return new Response(
    `<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width"><title>${title} · Relay</title><body><main><h1>${title}</h1><p>${body}</p></main></body></html>`,
    {
      headers: {
        "content-type": "text/html; charset=utf-8",
        "cache-control": "no-store",
        "content-security-policy":
          "default-src 'none'; style-src 'unsafe-inline'; form-action 'self'; base-uri 'none'",
        "x-content-type-options": "nosniff",
        "referrer-policy": "no-referrer",
      },
    },
  );
}

async function readJson(request: Request): Promise<unknown> {
  const declaredLength = Number(request.headers.get("content-length") ?? "0");
  if (declaredLength > MAX_RELAY_BODY_BYTES) throw new RangeError("Request too large");
  const raw = await request.text();
  if (new TextEncoder().encode(raw).byteLength > MAX_RELAY_BODY_BYTES) {
    throw new RangeError("Request too large");
  }
  if (raw.length === 0) return {};
  return JSON.parse(raw);
}

function routeCommand(method: string, path: string): {
  command: string;
  params: string[];
} | null {
  const exact = staticCommands.get(`${method} ${path}`);
  if (exact) return { command: exact, params: [] };
  for (const route of dynamicCommands) {
    if (route.method !== method) continue;
    const match = path.match(route.pattern);
    if (match) return { command: route.command, params: match.slice(1) };
  }
  return null;
}

export function createWorker(gateway: CommandGateway): {
  fetch(request: Request): Promise<Response>;
} {
  return {
    async fetch(request: Request): Promise<Response> {
      const url = new URL(request.url);
      if (request.method === "GET") {
        if (url.pathname === "/sign-in") {
          return publicPage(
            "Check your email",
            "Use the single-use sign-in link we sent, then return to Relay on your Mac.",
          );
        }
        if (url.pathname === "/privacy") {
          return publicPage(
            "Privacy",
            "Relay routes encrypted messages and retains limited operational metadata for seven days.",
          );
        }
        if (url.pathname === "/terms") {
          return publicPage("Terms", "Relay is provided as an invite-only public beta.");
        }
        if (url.pathname === "/support") {
          return publicPage("Support", "Contact the support address shown in the Relay application.");
        }
        if (url.pathname === "/account/delete") {
          return publicPage(
            "Delete your account",
            "Open Relay on your Mac and choose Delete Account to revoke all connected devices.",
          );
        }
        if (url.pathname === "/cloud/v1/auth/verify") {
          try {
            await gateway.command(
              "auth.magicLinks.verify",
              {
                body: {
                  session: url.searchParams.get("session"),
                  token: url.searchParams.get("token"),
                },
                params: [],
              },
              request,
            );
            return publicPage(
              "Sign-in verified",
              "Return to Relay on your Mac. This link can be used only once.",
            );
          } catch {
            return publicPage(
              "Sign-in failed",
              "This sign-in link is invalid or expired. Start again from Relay on your Mac.",
            );
          }
        }
        if (
          url.pathname === "/cloud/v1/connect/host" ||
          url.pathname === "/cloud/v1/connect/device"
        ) {
          return json(
            {
              error: {
                code: "upgrade_required",
                message: "WebSocket upgrade required",
              },
            },
            426,
          );
        }
      }

      const route = routeCommand(request.method, url.pathname);
      if (!route) {
        return json(
          { error: { code: "not_found", message: "Not found" } },
          404,
        );
      }

      try {
        const body = await readJson(request);
        const result = await gateway.command(
          route.command,
          { body, params: route.params },
          request,
        );
        return json(result);
      } catch (error) {
        if (
          typeof error === "object" &&
          error !== null &&
          "status" in error &&
          error.status === 202
        ) {
          return json({ status: "pending" }, 202);
        }
        if (error instanceof RangeError) {
          return json(
            { error: { code: "request_too_large", message: "Request too large" } },
            413,
          );
        }
        return json(
          {
            error: {
              code: "authentication_failed",
              message: "Authentication failed",
            },
          },
          401,
        );
      }
    },
  };
}
