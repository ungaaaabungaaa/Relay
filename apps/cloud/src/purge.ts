type D1RunResult = unknown;

type D1DatabaseLike = {
  prepare(sql: string): {
    bind(...values: unknown[]): {
      run(): Promise<D1RunResult>;
    };
  };
};

const EXPIRING_TABLES = [
  "device_login_sessions",
  "refresh_tokens",
  "pairing_sessions",
  "audit_metadata",
  "rate_limits",
] as const;

export async function purgeExpiredCloudData(
  database: D1DatabaseLike,
  now = Date.now(),
): Promise<void> {
  for (const table of EXPIRING_TABLES) {
    await database
      .prepare(`DELETE FROM ${table} WHERE expires_at <= ?`)
      .bind(now)
      .run();
  }
  await database
    .prepare(
      "DELETE FROM invites WHERE expires_at <= ? OR consumed_at IS NOT NULL",
    )
    .bind(now)
    .run();
}
