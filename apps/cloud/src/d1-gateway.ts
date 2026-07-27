import { randomBytes, randomUUID, timingSafeEqual } from "node:crypto";
import { emailLookupHash, encryptEmail } from "./auth.ts";
import { D1CloudRepository } from "./d1-repository.ts";

const encoder = new TextEncoder();
const decoder = new TextDecoder();
const AUTH_ERROR = "Authentication failed";
const PAIRING_ERROR = "Pairing failed";
const ACCESS_TOKEN_LIFETIME_MS = 15 * 60_000;
const REFRESH_TOKEN_LIFETIME_MS = 30 * 24 * 60 * 60_000;

type GatewayOptions = {
  adminCredential: string;
  jwtSecret: Uint8Array;
  piiKey: Uint8Array;
  emailHmacKey: Uint8Array;
  rateLimitHmacKey: Uint8Array;
  publicOrigin: string;
  now?: () => number;
  sendMagicLink(email: string, url: string): Promise<void>;
  notifyHost?(
    accountId: string,
    hostId: string,
    message: Record<string, unknown>,
  ): Promise<void>;
  emergencyStopTunnels?(
    accountId: string,
    hostId: string,
    deviceIds: string[],
  ): Promise<void>;
  revokeTunnelPeer?(accountId: string, deviceId: string): Promise<void>;
};

type AccessClaims = {
  accountId: string;
  issuedAt: number;
  expiresAt: number;
  tokenId: string;
};

export class PendingCommandError extends Error {
  readonly status = 202;
}

function encode(value: ArrayBuffer | Uint8Array): string {
  const bytes = value instanceof Uint8Array ? value : new Uint8Array(value);
  return Buffer.from(bytes).toString("base64url");
}

function decode(value: string): Uint8Array {
  return new Uint8Array(Buffer.from(value, "base64url"));
}

async function hmac(keyBytes: Uint8Array, value: string): Promise<string> {
  const key = await crypto.subtle.importKey(
    "raw",
    keyBytes,
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign", "verify"],
  );
  return encode(await crypto.subtle.sign("HMAC", key, encoder.encode(value)));
}

async function sha256(value: string): Promise<string> {
  return encode(await crypto.subtle.digest("SHA-256", encoder.encode(value)));
}

function credential(): string {
  return `${randomUUID()}.${randomBytes(32).toString("base64url")}`;
}

function pairingCode(): string {
  const alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
  return Array.from(
    randomBytes(6),
    (byte) => alphabet[byte % alphabet.length],
  ).join("");
}

function object(value: unknown): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new Error(AUTH_ERROR);
  }
  return value as Record<string, unknown>;
}

function requiredString(
  source: Record<string, unknown>,
  key: string,
): string {
  const value = source[key];
  if (typeof value !== "string" || value.length === 0) {
    throw new Error(AUTH_ERROR);
  }
  return value;
}

export class D1CommandGateway {
  readonly #repository: D1CloudRepository;
  readonly #options: GatewayOptions;
  readonly #now: () => number;

  constructor(repository: D1CloudRepository, options: GatewayOptions) {
    this.#repository = repository;
    this.#options = options;
    this.#now = options.now ?? Date.now;
  }

  async command(
    name: string,
    args: unknown,
    request: Request,
  ): Promise<unknown> {
    const requestSize = encoder.encode(JSON.stringify(args ?? null)).byteLength;
    try {
      const result = await this.#executeCommand(name, args, request);
      await this.#recordAudit(name, "ok", requestSize, result);
      return result;
    } catch (error) {
      await this.#recordAudit(
        name,
        error instanceof PendingCommandError ? "pending" : "denied",
        requestSize,
      );
      throw error;
    }
  }

  async #recordAudit(
    action: string,
    outcome: "ok" | "pending" | "denied",
    requestSize: number,
    response?: unknown,
  ): Promise<void> {
    const actorKind = action.startsWith("admin.")
      ? "admin"
      : action.startsWith("pairingSessions.request")
        || action.startsWith("pairingRequests.status")
        ? "watch"
        : action.startsWith("auth.")
          ? "anonymous"
          : "mac";
    try {
      await this.#repository.recordAudit({
        id: randomUUID(),
        action,
        actorKind,
        outcome,
        requestSize,
        responseSize: response === undefined
          ? 0
          : encoder.encode(JSON.stringify(response)).byteLength,
      });
    } catch {
      // Audit availability must never replay or block an already-run mutation.
    }
  }

  async #executeCommand(
    name: string,
    args: unknown,
    request: Request,
  ): Promise<unknown> {
    const parsed = object(args);
    const body = object(parsed.body);
    const params = Array.isArray(parsed.params)
      ? parsed.params.map(String)
      : [];
    switch (name) {
      case "auth.deviceSessions.create":
        return this.#startDeviceLogin(body);
      case "auth.deviceSessions.token":
        return this.#exchangeDeviceLogin(params[0], body);
      case "auth.magicLinks.verify":
        return this.#verifyMagicLink(body);
      case "auth.refresh":
        return this.#refresh(requiredString(body, "refreshToken"));
      case "auth.logout":
        await this.#repository.revokeRefreshFamilyForTokenHash(
          await sha256(requiredString(body, "refreshToken")),
        );
        return { ok: true };
      case "admin.invites.create":
        return this.#createInvite(request, body);
      case "hosts.create":
        return this.#createHost(await this.#authorize(request), body);
      case "pairingSessions.create":
        return this.#createPairing(
          await this.#authorize(request),
          params[0],
          body,
        );
      case "pairingSessions.request":
        return this.#requestPairing(params[0], body, request);
      case "pairingSessions.recoverRequests":
        return this.#recoverPendingPairings(
          await this.#authorize(request),
          params[0],
        );
      case "pairingRequests.status":
        return this.#pairingRequestStatus(params[0], request);
      case "pairingSessions.approve":
        return this.#approvePairing(
          await this.#authorize(request),
          params[0],
          body,
        );
      case "pairingSessions.deny":
        return this.#denyPairing(
          await this.#authorize(request),
          params[0],
          body,
        );
      case "devices.revoke":
        const revokeClaims = await this.#authorize(request);
        await this.#repository.revokeDevice(
          revokeClaims.accountId,
          params[0] ?? "",
        );
        await this.#options.revokeTunnelPeer?.(
          revokeClaims.accountId,
          params[0] ?? "",
        );
        return { ok: true };
      case "account.delete":
        await this.#repository.deleteAccount(
          (await this.#authorize(request)).accountId,
        );
        return { ok: true };
      case "emergencyStop":
        return this.#emergencyStop(await this.#authorize(request));
      default:
        throw new Error(AUTH_ERROR);
    }
  }

  async #createInvite(
    request: Request,
    body: Record<string, unknown>,
  ): Promise<{ ok: true }> {
    const authorization = request.headers.get("authorization");
    if (
      this.#options.adminCredential.length < 32 ||
      !authorization?.startsWith("Admin ")
    ) {
      throw new Error(AUTH_ERROR);
    }
    const supplied = Buffer.from(await sha256(authorization.slice(6)));
    const expected = Buffer.from(
      await sha256(this.#options.adminCredential),
    );
    if (
      supplied.byteLength !== expected.byteLength ||
      !timingSafeEqual(supplied, expected)
    ) {
      throw new Error(AUTH_ERROR);
    }

    const email = requiredString(body, "email").trim().toLowerCase();
    if (
      email.length > 320 ||
      !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)
    ) {
      throw new Error(AUTH_ERROR);
    }
    await this.#repository.createInvite({
      id: randomUUID(),
      emailCiphertext: encoder.encode(
        await encryptEmail(email, this.#options.piiKey),
      ),
      emailLookupHash: await emailLookupHash(
        email,
        this.#options.emailHmacKey,
      ),
      expiresAt: this.#now() + 30 * 24 * 60 * 60_000,
    });
    return { ok: true };
  }

  async #startDeviceLogin(
    body: Record<string, unknown>,
  ): Promise<unknown> {
    const email = requiredString(body, "email").trim().toLowerCase();
    const pkceChallenge = requiredString(body, "pkceChallenge");
    if (body.pkceMethod !== "S256" || pkceChallenge.length < 43) {
      throw new Error(AUTH_ERROR);
    }
    const sessionId = randomUUID();
    const expiresAt = this.#now() + 10 * 60_000;
    await this.#repository.createDeviceLoginSession({
      id: sessionId,
      emailLookupHash: await emailLookupHash(
        email,
        this.#options.emailHmacKey,
      ),
      pkceChallenge,
      expiresAt,
    });
    const magicToken = credential();
    await this.#repository.setDeviceLoginMagicLink(
      sessionId,
      await sha256(magicToken),
    );
    const link = new URL(
      "/cloud/v1/auth/verify",
      this.#options.publicOrigin,
    );
    link.searchParams.set("session", sessionId);
    link.searchParams.set("token", magicToken);
    await this.#options.sendMagicLink(email, link.toString());
    return {
      id: sessionId,
      verificationURL: new URL(
        `/sign-in?session=${encodeURIComponent(sessionId)}`,
        this.#options.publicOrigin,
      ).toString(),
      expiresAt,
    };
  }

  async #verifyMagicLink(
    body: Record<string, unknown>,
  ): Promise<{ ok: true }> {
    await this.#repository.verifyDeviceLoginMagicLink(
      requiredString(body, "session"),
      await sha256(requiredString(body, "token")),
    );
    return { ok: true };
  }

  async #exchangeDeviceLogin(
    sessionId: string | undefined,
    body: Record<string, unknown>,
  ): Promise<unknown> {
    if (!sessionId) throw new Error(AUTH_ERROR);
    const status = await this.#repository.getDeviceLoginStatus(sessionId);
    if (status === "pending") throw new PendingCommandError();
    if (status !== "verified") throw new Error(AUTH_ERROR);
    const verifier = requiredString(body, "pkceVerifier");
    const account = await this.#repository.consumeDeviceLogin({
      sessionId,
      accountId: randomUUID(),
      pkceChallenge: await sha256(verifier),
    });
    return this.#issueTokens(account.id, randomUUID());
  }

  async #issueTokens(
    accountId: string,
    familyId: string,
  ): Promise<unknown> {
    const now = this.#now();
    const refreshToken = credential();
    const refreshExpiresAt = now + REFRESH_TOKEN_LIFETIME_MS;
    await this.#repository.createRefreshToken({
      id: randomUUID(),
      accountId,
      familyId,
      tokenHash: await sha256(refreshToken),
      expiresAt: refreshExpiresAt,
    });
    const accessExpiresAt = now + ACCESS_TOKEN_LIFETIME_MS;
    return {
      accessToken: await this.#signAccess({
        accountId,
        issuedAt: now,
        expiresAt: accessExpiresAt,
        tokenId: randomUUID(),
      }),
      accessExpiresAt,
      refreshToken,
      refreshExpiresAt,
    };
  }

  async #refresh(refreshToken: string): Promise<unknown> {
    const replacement = credential();
    const refreshExpiresAt = this.#now() + REFRESH_TOKEN_LIFETIME_MS;
    const rotated = await this.#repository.rotateRefreshToken(
      await sha256(refreshToken),
      {
        id: randomUUID(),
        tokenHash: await sha256(replacement),
        expiresAt: refreshExpiresAt,
      },
    );
    const now = this.#now();
    const accessExpiresAt = now + ACCESS_TOKEN_LIFETIME_MS;
    return {
      accessToken: await this.#signAccess({
        accountId: rotated.accountId,
        issuedAt: now,
        expiresAt: accessExpiresAt,
        tokenId: randomUUID(),
      }),
      accessExpiresAt,
      refreshToken: replacement,
      refreshExpiresAt,
    };
  }

  async #createHost(
    claims: AccessClaims,
    body: Record<string, unknown>,
  ): Promise<unknown> {
    const rawCredential = credential();
    const hostId = randomUUID();
    await this.#repository.createHost({
      id: hostId,
      accountId: claims.accountId,
      name: requiredString(body, "name"),
      credentialHash: await sha256(rawCredential),
      signingPublicKey: requiredString(body, "signingPublicKey"),
      agreementPublicKey: requiredString(body, "agreementPublicKey"),
    });
    return { id: hostId, credential: rawCredential };
  }

  async #createPairing(
    claims: AccessClaims,
    hostId: string | undefined,
    body: Record<string, unknown>,
  ): Promise<unknown> {
    if (!hostId) throw new Error(PAIRING_ERROR);
    const token = credential();
    const code = pairingCode();
    const sessionNonce = randomBytes(32).toString("base64url");
    const expiresAt = this.#now() + 5 * 60_000;
    const macFingerprint = requiredString(body, "macFingerprint");
    await this.#repository.createPairingSession({
      tokenHash: await sha256(token),
      codeHash: await sha256(code),
      accountId: claims.accountId,
      hostId,
      sessionNonce,
      macFingerprint,
      expiresAt,
    });
    return {
      token,
      code,
      accountId: claims.accountId,
      expiresAt,
      sessionNonce,
      macFingerprint,
    };
  }

  async #pairingTokenHash(rawTokenOrCode: string | undefined): Promise<string> {
    if (!rawTokenOrCode) throw new Error(PAIRING_ERROR);
    const candidate = await sha256(rawTokenOrCode);
    try {
      await this.#repository.getPairingContext(candidate);
      return candidate;
    } catch {
      return this.#repository.resolvePairingTokenHash(
        await sha256(rawTokenOrCode.toUpperCase()),
      );
    }
  }

  async #requestPairing(
    rawTokenOrCode: string | undefined,
    body: Record<string, unknown>,
    request: Request,
  ): Promise<unknown> {
    const forwarded = request.headers.get("x-forwarded-for")
      ?.split(",", 1)[0]
      ?.trim();
    const source = request.headers.get("cf-connecting-ip")?.trim()
      || forwarded
      || "unknown";
    await this.#repository.consumeRateLimit(
      `pair-global:${await hmac(this.#options.rateLimitHmacKey, "global")}`,
      30,
      5 * 60_000,
    );
    await this.#repository.consumeRateLimit(
      `pair-source:${await hmac(this.#options.rateLimitHmacKey, source)}`,
      5,
      5 * 60_000,
    );
    const tokenHash = await this.#pairingTokenHash(rawTokenOrCode);
    await this.#repository.consumePairingAttempt(tokenHash, 5);
    const context = await this.#repository.getPairingContext(tokenHash);
    const requestId = randomUUID();
    const pollToken = credential();
    const expiresAt = this.#now() + 2 * 60_000;
    await this.#repository.createPairingRequest({
      id: requestId,
      tokenHash,
      pollTokenHash: await sha256(pollToken),
      requestFingerprintHash: await sha256(
        requiredString(body, "fingerprint"),
      ),
      signingPublicKey: requiredString(body, "signingPublicKey"),
      agreementPublicKey: requiredString(body, "agreementPublicKey"),
      metadata: object(body.metadata ?? {}),
      expiresAt,
    });
    await this.#options.notifyHost?.(
      context.accountId,
      context.hostId,
      {
        type: "pairing_request",
        requestId,
        fingerprint: requiredString(body, "fingerprint"),
        signingPublicKey: requiredString(body, "signingPublicKey"),
        agreementPublicKey: requiredString(body, "agreementPublicKey"),
        expiresAt,
        metadata: object(body.metadata ?? {}),
      },
    );
    return {
      id: requestId,
      pollToken,
      accountId: context.accountId,
      hostId: context.hostId,
      sessionNonce: context.sessionNonce,
      macFingerprint: context.macFingerprint,
      macAgreementPublicKey: context.hostAgreementPublicKey,
      expiresAt,
    };
  }

  async #approvePairing(
    claims: AccessClaims,
    rawToken: string | undefined,
    body: Record<string, unknown>,
  ): Promise<unknown> {
    const tokenHash = await this.#pairingTokenHash(rawToken);
    const context = await this.#repository.getPairingContext(tokenHash);
    if (context.accountId !== claims.accountId) throw new Error(PAIRING_ERROR);
    const deviceId = requiredString(body, "deviceId");
    const credentialHash = requiredString(body, "credentialHash");
    const approvedPayload = object(body.approvedPayload);
    if (
      approvedPayload.version !== 1 ||
      typeof approvedPayload.nonce !== "string" ||
      approvedPayload.nonce.length < 16 ||
      typeof approvedPayload.ciphertext !== "string" ||
      approvedPayload.ciphertext.length < 16 ||
      JSON.stringify(approvedPayload).length > 16_384
    ) {
      throw new Error(PAIRING_ERROR);
    }
    await this.#repository.approvePairing({
      accountId: claims.accountId,
      hostId: context.hostId,
      tokenHash,
      requestId: requiredString(body, "requestId"),
      deviceId,
      credentialHash,
      approvedPayload,
    });
    return {
      id: deviceId,
      hostId: context.hostId,
      sessionNonce: context.sessionNonce,
    };
  }

  async #recoverPendingPairings(
    claims: AccessClaims,
    rawToken: string | undefined,
  ): Promise<{ requests: unknown[] }> {
    const tokenHash = await this.#pairingTokenHash(rawToken);
    const context = await this.#repository.getPairingContext(tokenHash);
    if (context.accountId !== claims.accountId) throw new Error(PAIRING_ERROR);
    return {
      requests: await this.#repository.listPendingPairingRequests({
        accountId: claims.accountId,
        hostId: context.hostId,
        tokenHash,
      }),
    };
  }

  async #pairingRequestStatus(
    requestId: string | undefined,
    request: Request,
  ): Promise<unknown> {
    if (!requestId) throw new Error(PAIRING_ERROR);
    const authorization = request.headers.get("authorization");
    if (!authorization?.startsWith("Pairing ")) throw new Error(PAIRING_ERROR);
    return this.#repository.getPairingRequestStatus({
      requestId,
      pollTokenHash: await sha256(authorization.slice(8)),
    });
  }

  async #emergencyStop(claims: AccessClaims): Promise<unknown> {
    const hostCredential = credential();
    const stopped = await this.#repository.emergencyStop(
      claims.accountId,
      await sha256(hostCredential),
    );
    await this.#options.emergencyStopTunnels?.(
      claims.accountId,
      stopped.hostId,
      stopped.deviceIds,
    );
    return {
      hostId: stopped.hostId,
      hostCredential,
      revokedDeviceCount: stopped.deviceIds.length,
    };
  }

  async #denyPairing(
    claims: AccessClaims,
    rawToken: string | undefined,
    body: Record<string, unknown>,
  ): Promise<{ ok: true }> {
    const tokenHash = await this.#pairingTokenHash(rawToken);
    const context = await this.#repository.getPairingContext(tokenHash);
    if (context.accountId !== claims.accountId) throw new Error(PAIRING_ERROR);
    await this.#repository.denyPairing({
      accountId: claims.accountId,
      hostId: context.hostId,
      tokenHash,
      requestId: requiredString(body, "requestId"),
    });
    return { ok: true };
  }

  async #authorize(request: Request): Promise<AccessClaims> {
    const authorization = request.headers.get("authorization");
    if (!authorization?.startsWith("Bearer ")) throw new Error(AUTH_ERROR);
    return this.#verifyAccess(authorization.slice(7));
  }

  async #signAccess(claims: AccessClaims): Promise<string> {
    const payload = encode(encoder.encode(JSON.stringify(claims)));
    return `${payload}.${await hmac(this.#options.jwtSecret, payload)}`;
  }

  async #verifyAccess(token: string): Promise<AccessClaims> {
    const [payload, suppliedSignature] = token.split(".");
    if (!payload || !suppliedSignature) throw new Error(AUTH_ERROR);
    const expectedSignature = await hmac(this.#options.jwtSecret, payload);
    if (expectedSignature !== suppliedSignature) throw new Error(AUTH_ERROR);
    let claims: AccessClaims;
    try {
      claims = JSON.parse(decoder.decode(decode(payload))) as AccessClaims;
    } catch {
      throw new Error(AUTH_ERROR);
    }
    if (
      typeof claims.accountId !== "string" ||
      typeof claims.expiresAt !== "number" ||
      claims.expiresAt <= this.#now()
    ) {
      throw new Error(AUTH_ERROR);
    }
    return claims;
  }
}
