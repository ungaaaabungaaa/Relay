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

const AUTH_ERROR = "Authentication failed";

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
