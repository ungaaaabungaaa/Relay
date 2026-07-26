type D1Result = {
  changes?: number | bigint;
  meta?: { changes?: number };
};

type D1Prepared = {
  bind(...values: unknown[]): D1Prepared;
  run(): Promise<D1Result>;
  first<T>(): Promise<T | null>;
  all<T>(): Promise<{ results: T[] }>;
};

type D1DatabaseLike = {
  prepare(sql: string): D1Prepared;
};

type RepositoryOptions = { now?: () => number };
export type AuthenticatedTunnelPeer = {
  accountId: string;
  hostId: string;
  peerId: string;
  role: "host" | "device";
};

const AUTH_ERROR = "Authentication failed";
const PAIRING_ERROR = "Pairing failed";

function changeCount(result: D1Result): number {
  return Number(result.meta?.changes ?? result.changes ?? 0);
}

export class D1CloudRepository {
  readonly database: D1DatabaseLike;
  readonly #now: () => number;

  constructor(
    database: D1DatabaseLike,
    options: RepositoryOptions = {},
  ) {
    this.database = database;
    this.#now = options.now ?? Date.now;
  }

  async createInvite(input: {
    id: string;
    emailCiphertext: Uint8Array;
    emailLookupHash: string;
    expiresAt: number;
  }): Promise<void> {
    await this.database
      .prepare(
        `INSERT INTO invites
          (id, email_ciphertext, email_lookup_hash, created_at, expires_at)
         VALUES (?, ?, ?, ?, ?)`,
      )
      .bind(
        input.id,
        input.emailCiphertext,
        input.emailLookupHash,
        this.#now(),
        input.expiresAt,
      )
      .run();
  }

  async consumeInvite(input: {
    accountId: string;
    emailLookupHash: string;
  }): Promise<{ id: string }> {
    const now = this.#now();
    const invite = await this.database
      .prepare(
        `UPDATE invites
         SET consumed_at = ?
         WHERE email_lookup_hash = ?
           AND consumed_at IS NULL
           AND expires_at > ?
         RETURNING email_ciphertext`,
      )
      .bind(now, input.emailLookupHash, now)
      .first<{ email_ciphertext: Uint8Array }>();
    if (!invite) throw new Error(AUTH_ERROR);
    try {
      await this.database
        .prepare(
          `INSERT INTO accounts
            (id, email_ciphertext, email_lookup_hash, created_at)
           VALUES (?, ?, ?, ?)`,
        )
        .bind(
          input.accountId,
          invite.email_ciphertext,
          input.emailLookupHash,
          now,
        )
        .run();
      return { id: input.accountId };
    } catch {
      throw new Error(AUTH_ERROR);
    }
  }

  async createDeviceLoginSession(input: {
    id: string;
    emailLookupHash: string;
    pkceChallenge: string;
    expiresAt: number;
  }): Promise<void> {
    const now = this.#now();
    const result = await this.database
      .prepare(
        `INSERT INTO device_login_sessions
          (id, email_lookup_hash, pkce_challenge, status, created_at, expires_at)
         SELECT ?, ?, ?, 'pending', ?, ?
         WHERE EXISTS (
           SELECT 1 FROM invites
           WHERE email_lookup_hash = ?
             AND consumed_at IS NULL
             AND expires_at > ?
         )`,
      )
      .bind(
        input.id,
        input.emailLookupHash,
        input.pkceChallenge,
        now,
        input.expiresAt,
        input.emailLookupHash,
        now,
      )
      .run();
    if (changeCount(result) !== 1) throw new Error(AUTH_ERROR);
  }

  async setDeviceLoginMagicLink(
    sessionId: string,
    magicLinkHash: string,
  ): Promise<void> {
    const now = this.#now();
    const result = await this.database
      .prepare(
        `UPDATE device_login_sessions
         SET magic_link_hash = ?
         WHERE id = ? AND status = 'pending' AND expires_at > ?`,
      )
      .bind(magicLinkHash, sessionId, now)
      .run();
    if (changeCount(result) !== 1) throw new Error(AUTH_ERROR);
  }

  async verifyDeviceLoginMagicLink(
    sessionId: string,
    magicLinkHash: string,
  ): Promise<void> {
    const now = this.#now();
    const result = await this.database
      .prepare(
        `UPDATE device_login_sessions
         SET status = 'verified', magic_link_hash = NULL
         WHERE id = ?
           AND status = 'pending'
           AND magic_link_hash = ?
           AND expires_at > ?`,
      )
      .bind(sessionId, magicLinkHash, now)
      .run();
    if (changeCount(result) !== 1) throw new Error(AUTH_ERROR);
  }

  async consumeDeviceLogin(input: {
    sessionId: string;
    accountId: string;
    pkceChallenge: string;
  }): Promise<{ id: string }> {
    const now = this.#now();
    const account = await this.database
      .prepare(
        `INSERT INTO accounts
          (id, email_ciphertext, email_lookup_hash, created_at)
         SELECT ?, invite.email_ciphertext, invite.email_lookup_hash, ?
         FROM device_login_sessions AS login
         JOIN invites AS invite
           ON invite.email_lookup_hash = login.email_lookup_hash
         WHERE login.id = ?
           AND login.status = 'verified'
           AND login.pkce_challenge = ?
           AND login.expires_at > ?
           AND invite.consumed_at IS NULL
           AND invite.expires_at > ?
         RETURNING id, email_lookup_hash`,
      )
      .bind(
        input.accountId,
        now,
        input.sessionId,
        input.pkceChallenge,
        now,
        now,
      )
      .first<{ id: string; email_lookup_hash: string }>();
    if (!account) throw new Error(AUTH_ERROR);

    const loginResult = await this.database
      .prepare(
        `UPDATE device_login_sessions
         SET status = 'consumed'
         WHERE id = ? AND status = 'verified'`,
      )
      .bind(input.sessionId)
      .run();
    const inviteResult = await this.database
      .prepare(
        `UPDATE invites SET consumed_at = ?
         WHERE email_lookup_hash = ? AND consumed_at IS NULL`,
      )
      .bind(now, account.email_lookup_hash)
      .run();
    if (
      changeCount(loginResult) !== 1 ||
      changeCount(inviteResult) !== 1
    ) {
      await this.database
        .prepare("DELETE FROM accounts WHERE id = ?")
        .bind(input.accountId)
        .run();
      throw new Error(AUTH_ERROR);
    }
    return { id: account.id };
  }

  async getDeviceLoginStatus(
    sessionId: string,
  ): Promise<"pending" | "verified" | "consumed"> {
    const record = await this.database
      .prepare(
        `SELECT status FROM device_login_sessions
         WHERE id = ? AND expires_at > ?`,
      )
      .bind(sessionId, this.#now())
      .first<{ status: "pending" | "verified" | "consumed" | "revoked" }>();
    if (!record || record.status === "revoked") throw new Error(AUTH_ERROR);
    return record.status;
  }

  async createRefreshToken(input: {
    id: string;
    accountId: string;
    familyId: string;
    tokenHash: string;
    expiresAt: number;
  }): Promise<void> {
    try {
      await this.database
        .prepare(
          `INSERT INTO refresh_tokens
            (id, account_id, family_id, token_hash, created_at, expires_at)
           VALUES (?, ?, ?, ?, ?, ?)`,
        )
        .bind(
          input.id,
          input.accountId,
          input.familyId,
          input.tokenHash,
          this.#now(),
          input.expiresAt,
        )
        .run();
    } catch {
      throw new Error(AUTH_ERROR);
    }
  }

  async rotateRefreshToken(
    tokenHash: string,
    replacement: {
      id: string;
      tokenHash: string;
      expiresAt: number;
    },
  ): Promise<{ accountId: string; familyId: string }> {
    const now = this.#now();
    const record = await this.database
      .prepare(
        `SELECT account_id, family_id, expires_at, consumed_at, revoked_at
         FROM refresh_tokens WHERE token_hash = ?`,
      )
      .bind(tokenHash)
      .first<{
        account_id: string;
        family_id: string;
        expires_at: number;
        consumed_at: number | null;
        revoked_at: number | null;
      }>();
    if (!record) throw new Error(AUTH_ERROR);
    if (record.consumed_at !== null) {
      await this.revokeRefreshFamily(record.family_id);
      throw new Error(AUTH_ERROR);
    }
    if (record.revoked_at !== null || record.expires_at <= now) {
      throw new Error(AUTH_ERROR);
    }

    const consumed = await this.database
      .prepare(
        `UPDATE refresh_tokens SET consumed_at = ?
         WHERE token_hash = ? AND consumed_at IS NULL AND revoked_at IS NULL`,
      )
      .bind(now, tokenHash)
      .run();
    if (changeCount(consumed) !== 1) {
      await this.revokeRefreshFamily(record.family_id);
      throw new Error(AUTH_ERROR);
    }
    try {
      await this.createRefreshToken({
        ...replacement,
        accountId: record.account_id,
        familyId: record.family_id,
      });
    } catch {
      await this.revokeRefreshFamily(record.family_id);
      throw new Error(AUTH_ERROR);
    }
    return {
      accountId: record.account_id,
      familyId: record.family_id,
    };
  }

  async revokeRefreshFamily(familyId: string): Promise<void> {
    await this.database
      .prepare(
        `UPDATE refresh_tokens SET revoked_at = ?
         WHERE family_id = ? AND revoked_at IS NULL`,
      )
      .bind(this.#now(), familyId)
      .run();
  }

  async revokeRefreshFamilyForTokenHash(tokenHash: string): Promise<void> {
    const record = await this.database
      .prepare(
        "SELECT family_id FROM refresh_tokens WHERE token_hash = ?",
      )
      .bind(tokenHash)
      .first<{ family_id: string }>();
    if (!record) throw new Error(AUTH_ERROR);
    await this.revokeRefreshFamily(record.family_id);
  }

  async isRefreshFamilyActive(familyId: string): Promise<boolean> {
    const record = await this.database
      .prepare(
        `SELECT 1 AS active FROM refresh_tokens
         WHERE family_id = ?
           AND consumed_at IS NULL
           AND revoked_at IS NULL
           AND expires_at > ?
         LIMIT 1`,
      )
      .bind(familyId, this.#now())
      .first<{ active: number }>();
    return record?.active === 1;
  }

  async createTestAccount(accountId: string): Promise<void> {
    await this.database
      .prepare(
        `INSERT INTO accounts
          (id, email_ciphertext, email_lookup_hash, created_at)
         VALUES (?, ?, ?, ?)`,
      )
      .bind(
        accountId,
        new Uint8Array([0]),
        `test-${accountId}`,
        this.#now(),
      )
      .run();
  }

  async createHost(input: {
    id: string;
    accountId: string;
    name: string;
    credentialHash: string;
    signingPublicKey?: string;
    agreementPublicKey?: string;
  }): Promise<void> {
    try {
      await this.database
        .prepare(
          `INSERT INTO hosts
            (id, account_id, name, credential_hash, signing_public_key,
             agreement_public_key, created_at)
           VALUES (?, ?, ?, ?, ?, ?, ?)`,
        )
        .bind(
          input.id,
          input.accountId,
          input.name,
          input.credentialHash,
          input.signingPublicKey ?? null,
          input.agreementPublicKey ?? null,
          this.#now(),
        )
        .run();
    } catch {
      throw new Error("Host limit reached");
    }
  }

  async authenticateHost(
    hostId: string,
    credentialHash: string,
  ): Promise<AuthenticatedTunnelPeer> {
    const host = await this.database
      .prepare(
        `SELECT account_id FROM hosts
         WHERE id = ?
           AND credential_hash = ?
           AND revoked_at IS NULL`,
      )
      .bind(hostId, credentialHash)
      .first<{ account_id: string }>();
    if (!host) throw new Error(AUTH_ERROR);
    return {
      accountId: host.account_id,
      hostId,
      peerId: hostId,
      role: "host",
    };
  }

  async createDevice(input: {
    id: string;
    accountId: string;
    hostId: string;
    credentialHash: string;
    signingPublicKey: string;
    agreementPublicKey: string;
    metadata: Record<string, unknown>;
  }): Promise<void> {
    const result = await this.database
      .prepare(
        `INSERT INTO devices
          (id, account_id, host_id, credential_hash, signing_public_key,
           agreement_public_key, metadata_json, created_at)
         SELECT ?, ?, ?, ?, ?, ?, ?, ?
         WHERE EXISTS (
           SELECT 1 FROM hosts
           WHERE id = ? AND account_id = ? AND revoked_at IS NULL
         )
         AND (
           SELECT COUNT(*) FROM devices
           WHERE host_id = ? AND revoked_at IS NULL
         ) < 3`,
      )
      .bind(
        input.id,
        input.accountId,
        input.hostId,
        input.credentialHash,
        input.signingPublicKey,
        input.agreementPublicKey,
        JSON.stringify(input.metadata),
        this.#now(),
        input.hostId,
        input.accountId,
        input.hostId,
      )
      .run();
    if (changeCount(result) !== 1) throw new Error("Device limit reached");
  }

  async authenticateDevice(
    deviceId: string,
    credentialHash: string,
  ): Promise<AuthenticatedTunnelPeer> {
    const device = await this.database
      .prepare(
        `SELECT account_id, host_id FROM devices
         WHERE id = ?
           AND credential_hash = ?
           AND revoked_at IS NULL`,
      )
      .bind(deviceId, credentialHash)
      .first<{ account_id: string; host_id: string }>();
    if (!device) throw new Error(AUTH_ERROR);
    return {
      accountId: device.account_id,
      hostId: device.host_id,
      peerId: deviceId,
      role: "device",
    };
  }

  async createPairingSession(input: {
    tokenHash: string;
    codeHash: string;
    accountId: string;
    hostId: string;
    sessionNonce: string;
    macFingerprint?: string;
    expiresAt: number;
  }): Promise<void> {
    const now = this.#now();
    const result = await this.database
      .prepare(
        `INSERT INTO pairing_sessions
          (token_hash, code_hash, account_id, host_id, session_nonce,
           mac_fingerprint, created_at, expires_at)
         SELECT ?, ?, ?, ?, ?, ?, ?, ?
         WHERE EXISTS (
           SELECT 1 FROM hosts
           WHERE id = ? AND account_id = ? AND revoked_at IS NULL
         )`,
      )
      .bind(
        input.tokenHash,
        input.codeHash,
        input.accountId,
        input.hostId,
        input.sessionNonce,
        input.macFingerprint ?? "",
        now,
        input.expiresAt,
        input.hostId,
        input.accountId,
      )
      .run();
    if (changeCount(result) !== 1) throw new Error(PAIRING_ERROR);
  }

  async getPairingContext(tokenHash: string): Promise<{
    accountId: string;
    hostId: string;
    sessionNonce: string;
    macFingerprint: string;
    hostAgreementPublicKey: string;
  }> {
    const record = await this.database
      .prepare(
        `SELECT session.account_id, session.host_id, session.session_nonce,
                session.mac_fingerprint, host.agreement_public_key
         FROM pairing_sessions AS session
         JOIN hosts AS host ON host.id = session.host_id
         WHERE session.token_hash = ?
           AND session.consumed_at IS NULL
           AND session.expires_at > ?
           AND host.revoked_at IS NULL`,
      )
      .bind(tokenHash, this.#now())
      .first<{
        account_id: string;
        host_id: string;
        session_nonce: string;
        mac_fingerprint: string;
        agreement_public_key: string | null;
      }>();
    if (!record || !record.agreement_public_key) {
      throw new Error(PAIRING_ERROR);
    }
    return {
      accountId: record.account_id,
      hostId: record.host_id,
      sessionNonce: record.session_nonce,
      macFingerprint: record.mac_fingerprint,
      hostAgreementPublicKey: record.agreement_public_key,
    };
  }

  async resolvePairingTokenHash(codeHash: string): Promise<string> {
    const record = await this.database
      .prepare(
        `SELECT token_hash FROM pairing_sessions
         WHERE code_hash = ?
           AND consumed_at IS NULL
           AND expires_at > ?`,
      )
      .bind(codeHash, this.#now())
      .first<{ token_hash: string }>();
    if (!record) throw new Error(PAIRING_ERROR);
    return record.token_hash;
  }

  async createPairingRequest(input: {
    id: string;
    tokenHash: string;
    requestFingerprintHash: string;
    signingPublicKey: string;
    agreementPublicKey: string;
    metadata: Record<string, unknown>;
    expiresAt: number;
  }): Promise<void> {
    const now = this.#now();
    const result = await this.database
      .prepare(
        `INSERT INTO pairing_requests
          (id, pairing_token_hash, request_fingerprint_hash,
           signing_public_key, agreement_public_key, metadata_json,
           status, created_at, expires_at)
         SELECT ?, ?, ?, ?, ?, ?, 'pending', ?, ?
         WHERE EXISTS (
           SELECT 1 FROM pairing_sessions
           WHERE token_hash = ?
             AND consumed_at IS NULL
             AND expires_at > ?
         )`,
      )
      .bind(
        input.id,
        input.tokenHash,
        input.requestFingerprintHash,
        input.signingPublicKey,
        input.agreementPublicKey,
        JSON.stringify(input.metadata),
        now,
        input.expiresAt,
        input.tokenHash,
        now,
      )
      .run();
    if (changeCount(result) !== 1) throw new Error(PAIRING_ERROR);
  }

  async approvePairing(input: {
    accountId: string;
    hostId: string;
    tokenHash: string;
    requestId: string;
    deviceId: string;
    credentialHash: string;
  }): Promise<{ deviceId: string; sessionNonce: string }> {
    const now = this.#now();
    const pairing = await this.database
      .prepare(
        `SELECT session.session_nonce, request.signing_public_key,
                request.agreement_public_key, request.metadata_json
         FROM pairing_sessions AS session
         JOIN pairing_requests AS request
           ON request.pairing_token_hash = session.token_hash
         WHERE session.token_hash = ?
           AND session.account_id = ?
           AND session.host_id = ?
           AND session.consumed_at IS NULL
           AND session.expires_at > ?
           AND request.id = ?
           AND request.status = 'pending'
           AND request.expires_at > ?`,
      )
      .bind(
        input.tokenHash,
        input.accountId,
        input.hostId,
        now,
        input.requestId,
        now,
      )
      .first<{
        session_nonce: string;
        signing_public_key: string;
        agreement_public_key: string;
        metadata_json: string;
      }>();
    if (!pairing) throw new Error(PAIRING_ERROR);

    try {
      await this.createDevice({
        id: input.deviceId,
        accountId: input.accountId,
        hostId: input.hostId,
        credentialHash: input.credentialHash,
        signingPublicKey: pairing.signing_public_key,
        agreementPublicKey: pairing.agreement_public_key,
        metadata: JSON.parse(pairing.metadata_json) as Record<string, unknown>,
      });
    } catch {
      throw new Error(PAIRING_ERROR);
    }
    const requestResult = await this.database
      .prepare(
        `UPDATE pairing_requests
         SET status = 'approved', resolved_at = ?
         WHERE id = ? AND status = 'pending'`,
      )
      .bind(now, input.requestId)
      .run();
    const sessionResult = await this.database
      .prepare(
        `UPDATE pairing_sessions SET consumed_at = ?
         WHERE token_hash = ? AND consumed_at IS NULL`,
      )
      .bind(now, input.tokenHash)
      .run();
    if (
      changeCount(requestResult) !== 1 ||
      changeCount(sessionResult) !== 1
    ) {
      await this.database
        .prepare("DELETE FROM devices WHERE id = ?")
        .bind(input.deviceId)
        .run();
      throw new Error(PAIRING_ERROR);
    }
    return {
      deviceId: input.deviceId,
      sessionNonce: pairing.session_nonce,
    };
  }

  async denyPairing(input: {
    accountId: string;
    hostId: string;
    tokenHash: string;
    requestId: string;
  }): Promise<void> {
    const now = this.#now();
    const request = await this.database
      .prepare(
        `UPDATE pairing_requests
         SET status = 'denied', resolved_at = ?
         WHERE id = ?
           AND status = 'pending'
           AND EXISTS (
             SELECT 1 FROM pairing_sessions
             WHERE token_hash = ?
               AND account_id = ?
               AND host_id = ?
               AND consumed_at IS NULL
               AND expires_at > ?
           )`,
      )
      .bind(
        now,
        input.requestId,
        input.tokenHash,
        input.accountId,
        input.hostId,
        now,
      )
      .run();
    if (changeCount(request) !== 1) throw new Error(PAIRING_ERROR);
    await this.database
      .prepare(
        `UPDATE pairing_sessions SET consumed_at = ?
         WHERE token_hash = ? AND consumed_at IS NULL`,
      )
      .bind(now, input.tokenHash)
      .run();
  }

  async revokeDevice(
    accountId: string,
    deviceId: string,
  ): Promise<void> {
    const result = await this.database
      .prepare(
        `UPDATE devices SET revoked_at = ?
         WHERE id = ? AND account_id = ? AND revoked_at IS NULL`,
      )
      .bind(this.#now(), deviceId, accountId)
      .run();
    if (changeCount(result) !== 1) throw new Error(AUTH_ERROR);
  }

  async deleteAccount(accountId: string): Promise<void> {
    const result = await this.database
      .prepare("DELETE FROM accounts WHERE id = ?")
      .bind(accountId)
      .run();
    if (changeCount(result) !== 1) throw new Error(AUTH_ERROR);
  }
}
