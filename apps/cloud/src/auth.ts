import { randomBytes, randomUUID, timingSafeEqual } from "node:crypto";

const encoder = new TextEncoder();
const decoder = new TextDecoder();
const ACCESS_TOKEN_LIFETIME_MS = 15 * 60_000;
const REFRESH_TOKEN_LIFETIME_MS = 30 * 24 * 60 * 60_000;
const AUTH_ERROR = "Authentication failed";

function normalizeEmail(email: string): string {
  return email.trim().toLowerCase();
}

function encode(value: ArrayBuffer | Uint8Array): string {
  const bytes = value instanceof Uint8Array ? value : new Uint8Array(value);
  return Buffer.from(bytes).toString("base64url");
}

function decode(value: string): Uint8Array {
  return new Uint8Array(Buffer.from(value, "base64url"));
}

async function importAesKey(bytes: Uint8Array): Promise<CryptoKey> {
  return crypto.subtle.importKey("raw", bytes, "AES-GCM", false, [
    "encrypt",
    "decrypt",
  ]);
}

async function importHmacKey(bytes: Uint8Array): Promise<CryptoKey> {
  return crypto.subtle.importKey(
    "raw",
    bytes,
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign", "verify"],
  );
}

export async function encryptEmail(
  email: string,
  piiKey: Uint8Array,
): Promise<string> {
  const nonce = randomBytes(12);
  const ciphertext = await crypto.subtle.encrypt(
    { name: "AES-GCM", iv: nonce },
    await importAesKey(piiKey),
    encoder.encode(normalizeEmail(email)),
  );
  return `${encode(nonce)}.${encode(ciphertext)}`;
}

export async function decryptEmail(
  encrypted: string,
  piiKey: Uint8Array,
): Promise<string> {
  const [nonce, ciphertext] = encrypted.split(".");
  if (!nonce || !ciphertext) throw new Error(AUTH_ERROR);
  try {
    return decoder.decode(
      await crypto.subtle.decrypt(
        { name: "AES-GCM", iv: decode(nonce) },
        await importAesKey(piiKey),
        decode(ciphertext),
      ),
    );
  } catch {
    throw new Error(AUTH_ERROR);
  }
}

export async function emailLookupHash(
  email: string,
  hmacKey: Uint8Array,
): Promise<string> {
  return encode(
    await crypto.subtle.sign(
      "HMAC",
      await importHmacKey(hmacKey),
      encoder.encode(normalizeEmail(email)),
    ),
  );
}

type RefreshRecord = {
  tokenHash: string;
  familyId: string;
  accountId: string;
  hostId: string;
  expiresAt: number;
  consumedAt?: number;
  revokedAt?: number;
};

export class InMemoryTokenStore {
  readonly #records = new Map<string, RefreshRecord>();

  put(record: RefreshRecord): void {
    this.#records.set(record.tokenHash, structuredClone(record));
  }

  get(tokenHash: string): RefreshRecord | undefined {
    const record = this.#records.get(tokenHash);
    return record ? structuredClone(record) : undefined;
  }

  consume(tokenHash: string, consumedAt: number): void {
    const record = this.#records.get(tokenHash);
    if (record) record.consumedAt = consumedAt;
  }

  revokeFamily(familyId: string, revokedAt: number): void {
    for (const record of this.#records.values()) {
      if (record.familyId === familyId) record.revokedAt = revokedAt;
    }
  }

  activeFamilyCount(): number {
    return new Set(
      [...this.#records.values()]
        .filter((record) => !record.revokedAt && !record.consumedAt)
        .map((record) => record.familyId),
    ).size;
  }
}

type TokenSecrets = {
  jwtSecret: Uint8Array;
  piiKey: Uint8Array;
  emailHmacKey: Uint8Array;
};

export type AccessClaims = {
  accountId: string;
  hostId: string;
  issuedAt: number;
  expiresAt: number;
  tokenId: string;
};

type IssuedTokens = {
  accessToken: string;
  accessExpiresAt: number;
  refreshToken: string;
  refreshExpiresAt: number;
};

export class RelayAuthTokens {
  readonly store: InMemoryTokenStore;
  readonly secrets: TokenSecrets;
  readonly #now: () => number;

  constructor(
    store: InMemoryTokenStore,
    secrets: TokenSecrets,
    options: { now?: () => number } = {},
  ) {
    this.store = store;
    this.secrets = secrets;
    this.#now = options.now ?? Date.now;
  }

  async issue(
    accountId: string,
    hostId: string,
    familyId = randomUUID(),
  ): Promise<IssuedTokens> {
    const now = this.#now();
    const refreshToken = `${randomUUID()}.${randomBytes(32).toString("base64url")}`;
    const refreshExpiresAt = now + REFRESH_TOKEN_LIFETIME_MS;
    this.store.put({
      tokenHash: await this.#hashToken(refreshToken),
      familyId,
      accountId,
      hostId,
      expiresAt: refreshExpiresAt,
    });
    const accessExpiresAt = now + ACCESS_TOKEN_LIFETIME_MS;
    return {
      accessToken: await this.#signAccessToken({
        accountId,
        hostId,
        issuedAt: now,
        expiresAt: accessExpiresAt,
        tokenId: randomUUID(),
      }),
      accessExpiresAt,
      refreshToken,
      refreshExpiresAt,
    };
  }

  async refresh(refreshToken: string): Promise<IssuedTokens> {
    const tokenHash = await this.#hashToken(refreshToken);
    const record = this.store.get(tokenHash);
    const now = this.#now();
    if (!record) throw new Error(AUTH_ERROR);
    if (record.consumedAt) {
      this.store.revokeFamily(record.familyId, now);
      throw new Error(AUTH_ERROR);
    }
    if (record.revokedAt || record.expiresAt <= now) throw new Error(AUTH_ERROR);
    this.store.consume(tokenHash, now);
    return this.issue(record.accountId, record.hostId, record.familyId);
  }

  async logout(refreshToken: string): Promise<void> {
    const record = this.store.get(await this.#hashToken(refreshToken));
    if (!record) throw new Error(AUTH_ERROR);
    this.store.revokeFamily(record.familyId, this.#now());
  }

  async verifyAccessToken(token: string): Promise<AccessClaims> {
    const [payload, signature] = token.split(".");
    if (!payload || !signature) throw new Error(AUTH_ERROR);
    const expected = new Uint8Array(
      await crypto.subtle.sign(
        "HMAC",
        await importHmacKey(this.secrets.jwtSecret),
        encoder.encode(payload),
      ),
    );
    const supplied = decode(signature);
    if (
      expected.byteLength !== supplied.byteLength ||
      !timingSafeEqual(expected, supplied)
    ) {
      throw new Error(AUTH_ERROR);
    }
    const claims = JSON.parse(decoder.decode(decode(payload))) as AccessClaims;
    if (claims.expiresAt <= this.#now()) throw new Error(AUTH_ERROR);
    return claims;
  }

  async #signAccessToken(claims: AccessClaims): Promise<string> {
    const payload = encode(encoder.encode(JSON.stringify(claims)));
    const signature = await crypto.subtle.sign(
      "HMAC",
      await importHmacKey(this.secrets.jwtSecret),
      encoder.encode(payload),
    );
    return `${payload}.${encode(signature)}`;
  }

  async #hashToken(token: string): Promise<string> {
    return encode(
      await crypto.subtle.digest("SHA-256", encoder.encode(token)),
    );
  }
}
