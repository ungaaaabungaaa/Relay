type CommandGateway = {
  command(name: string, args: unknown, request: Request): Promise<unknown>;
};

const MAX_RELAY_BODY_BYTES = 2 * 1024 * 1024;

const staticCommands = new Map<string, string>([
  ["POST /cloud/v1/auth/device-sessions", "auth.deviceSessions.create"],
  ["POST /cloud/v1/auth/magic-links", "auth.magicLinks.create"],
  ["POST /cloud/v1/auth/refresh", "auth.refresh"],
  ["POST /cloud/v1/auth/logout", "auth.logout"],
  ["POST /cloud/v1/admin/invites", "admin.invites.create"],
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
    method: "GET",
    pattern: /^\/cloud\/v1\/pairing-requests\/([^/]+)$/,
    command: "pairingRequests.status",
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

function escapeHTML(value: string): string {
  return value.replace(/[&<>"']/g, (character) => ({
    "&": "&amp;",
    "<": "&lt;",
    ">": "&gt;",
    '"': "&quot;",
    "'": "&#39;",
  })[character] ?? character);
}

function publicPage(
  title: string,
  body: string,
  details: string[] = [],
): Response {
  const detailHTML = details
    .map((detail) => `<p>${escapeHTML(detail)}</p>`)
    .join("");
  return new Response(
    `<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width"><title>${escapeHTML(title)} · Relay</title><style>:root{color-scheme:dark}body{margin:0;background:#080a0b;color:#f5f7f8;font:16px/1.6 system-ui,sans-serif}main{max-width:680px;margin:auto;padding:64px 24px}h1{font-size:clamp(2rem,8vw,4rem);line-height:1;margin:0 0 24px;color:#62e790}p{color:#c8ced3}nav{display:flex;gap:16px;flex-wrap:wrap;margin-top:40px}a{color:#6eb7ff}</style><body><main><h1>${escapeHTML(title)}</h1><p>${escapeHTML(body)}</p>${detailHTML}<nav><a href="/privacy">Privacy</a><a href="/terms">Terms</a><a href="/support">Support</a><a href="/account/delete">Delete account</a></nav></main></body></html>`,
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
            "Relay Privacy",
            "Relay is local-first and uses end-to-end encrypted tunnels between each approved watch and its Mac. Relay Cloud routes ciphertext and cannot decrypt Codex prompts, commands, repository paths, approvals, task output, or voice recordings.",
            [
              "We process an invited email address, account and device identifiers, app/device compatibility metadata, hashed credentials, and limited security/size outcomes. Email is encrypted at rest and indexed with a separate keyed hash.",
              "Operational metadata expires after seven days. Expired login, pairing, refresh, rate-limit, and audit records are purged automatically. Relay has no product analytics, advertising SDK, or plaintext content logging.",
              "Cloudflare provides routing and storage, and Resend delivers one-time sign-in email. Optional transcription is configured by the user on the Mac and is not decrypted by Relay Cloud.",
              "Delete the account from Relay on the Mac to revoke its hosts and watches and remove account and device metadata. Codex credentials and repositories remain on the Mac.",
            ],
          );
        }
        if (url.pathname === "/terms") {
          return publicPage(
            "Relay Prototype Terms",
            "Relay is an unreleased, invite-gated prototype with zero users. Relay offers no public beta or production service. You supply and control the Mac, Codex installation, OpenAI access, network, repositories, and every approval.",
            [
              "Use Relay only with accounts, Macs, watches, repositories, and workspaces you are authorized to control. Do not bypass pairing, rate limits, revocation, store rules, or security review controls.",
              "Prototype software may disconnect, lose cached summaries, or contain defects. Keep source control and independent backups, review commands and consequences, and use Emergency Stop if a device is lost or behavior is unexpected.",
              "Relay may withdraw prototype access to protect users or the service. Apache License 2.0 covers published source code. Prototype access carries no uptime promise.",
            ],
          );
        }
        if (url.pathname === "/support") {
          return publicPage(
            "Relay Support",
            "The unreleased, invite-gated Relay prototype has zero users and offers no public beta or production service. Email support@relayforcodex.com for pairing, revocation, deletion, or accessibility help. Do not include credentials, magic links, pairing codes, prompts, repository paths, commands, task output, or audio.",
            [
              "For connection problems, keep the Mac awake, confirm Relay Cloud is connected, and use Refresh on the watch. The watch shows offline summaries in read-only mode.",
              "For a lost watch, revoke it from Relay on the Mac. For suspected compromise, use Emergency Stop and then contact support.",
              "Use GitHub private vulnerability reporting when available for security issues. Do not post security reports in public issues.",
            ],
          );
        }
        if (url.pathname === "/account/delete") {
          return publicPage(
            "Delete your account",
            "Open Relay on your Mac, choose Relay Cloud, then Delete Relay Account. The action revokes every host and watch and removes cloud account and device metadata.",
            [
              "If the Mac is unavailable, contact support@relayforcodex.com from the invited email address. Never send a refresh token, device credential, pairing code, or diagnostic containing private content.",
              "Deleting Relay does not delete local Codex tasks or repositories on the Mac.",
            ],
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
