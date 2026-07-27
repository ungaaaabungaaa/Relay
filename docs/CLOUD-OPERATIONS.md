# Relay Cloud operations runbook

This runbook covers staging/production deployment, secret handling, rollback,
and D1 recovery. Run production commands only from the protected GitHub
environment with a second reviewer. Never paste returned credentials,
bookmarks, account data, or SQL exports into an issue or build log.

## Environment ownership

Maintain separate staging and production Workers, D1 databases, domains,
Resend domains/keys, and secrets. Configure these GitHub environment secrets:

- `CLOUDFLARE_ACCOUNT_ID` and a least-privilege `CLOUDFLARE_API_TOKEN`;
- `JWT_SECRET`, `PII_ENCRYPTION_KEY`, `EMAIL_HMAC_KEY`, and
  `RATE_LIMIT_HMAC_KEY` as independent random 32-byte base64url values;
- `RESEND_API_KEY` and `CLOUD_ADMIN_CREDENTIAL`.

Configure the D1 ID/name and API/public hosts as protected environment
variables. The deploy workflow renders its Wrangler config and secret bundle
inside the ephemeral runner, applies migrations, deploys with
`--secrets-file`, and deletes the temporary bundle in an `always()` step.

## Pre-deploy check

1. Confirm the target environment and required reviewer.
2. Confirm the D1 database location is Asia Pacific and belongs to that target.
3. Run the Cloud package tests and dry build.
4. Record the current D1 Time Travel bookmark in the private change record:

   ```bash
   pnpm --filter @relay/cloud exec wrangler d1 time-travel info \
     RELAY_DATABASE_NAME --timestamp 2026-07-26T00:00:00Z --json
   ```

5. Deploy staging first and complete sign-in, host registration, pairing,
   encrypted request, revocation, and account-deletion smoke tests.

Use a reachable TLS staging origin for physical Apple Watch tests. The Mac and
Watch derive matching `https://` and `wss://` endpoints from the same debug-only
origin. Plaintext is accepted only on loopback and cannot be used from a
physical Watch. Release builds reject origin overrides.

During pairing, disconnect and reconnect the Mac tunnel once. Confirm the Mac
recovers only pending, unexpired requests for its authenticated account, host,
and active unconsumed session. The recovery response must contain public keys,
limited device metadata, request ID, and expiry only—never a pairing code, poll
token, watch credential, approved payload, or E2EE root key.

The timestamp above is an example; use the actual UTC instant immediately
before the change. Cloudflare documents the current commands in its
[Wrangler D1 reference](https://developers.cloudflare.com/d1/wrangler-commands/).

## Recovery drill

Use a staging-only test account. Create a bookmark, add a uniquely named test
invite/device record through supported APIs, restore to the earlier bookmark,
and verify the test record is gone while pre-bookmark rows remain. Do not
perform a production restore merely to prove the drill.

```bash
pnpm --filter @relay/cloud exec wrangler d1 time-travel restore \
  RELAY_DATABASE_NAME --bookmark PRIVATE_BOOKMARK --json
```

Save the returned `previous_bookmark` privately: Cloudflare exposes it so an
operator can undo an accidental restore. Time Travel availability depends on
the Cloudflare plan and retention window; check the current
[D1 Time Travel documentation](https://developers.cloudflare.com/d1/reference/time-travel/)
before each drill.

After restore, run read-only count/integrity queries, verify one invited login,
pairing, revocation, and deletion flow, then record pass/fail without PII. The
public-beta gate requires a successful staging drill and a reviewed production
recovery plan; it does not require destructive production testing.

## Export and incident evidence

For a private encrypted operational backup or investigation, Cloudflare also
supports `wrangler d1 export --remote`. Exports contain encrypted email and
security metadata and must still be treated as confidential, access-controlled,
retention-limited data. Never add an export to Git, release assets, CI artifacts,
or ordinary support tickets. Follow Cloudflare's current
[D1 import/export guide](https://developers.cloudflare.com/d1/best-practices/import-export-data/).

## Broken deployment

- Stop beta invitations and use Emergency Stop for affected accounts.
- Preserve redacted evidence and the deployed commit SHA.
- Prefer a forward code fix and higher application version.
- Restore D1 only for confirmed data corruption with reviewer approval and a
  known-good bookmark.
- Never overwrite a published Git tag or release asset.
