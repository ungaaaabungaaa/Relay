# Security Model

Relay grants the watch authority to control Codex as the logged-in Mac user. That includes approving destructive commands and broad filesystem access. This is intentionally powerful.

## User-selected policy

- Every approval type is available on the watch.
- Approvals are single-tap.
- No extra watch PIN or biometric confirmation is requested by Relay.
- All Mac folders readable by the bridge process can be browsed.

Anyone holding an unlocked, paired watch may therefore authorize destructive work. The UI must show the exact command, working directory, risk level, and declared capability before approval, but it does not add a second confirmation.

## Trust boundaries

### Watch

- Stores one non-exportable signing key in Android Keystore.
- Stores no OpenAI API key, Codex credential, repository content, or raw audio history.
- Caches only the minimum task metadata needed to render the current state and clearly marks stale data offline.

### Funnel

- Provides public TLS ingress to the Mac.
- Does not identify the watch, so the bridge must not trust Funnel headers as identity.
- Must forward only to a localhost-bound bridge.

### Mac bridge

- Authenticates every request cryptographically.
- Rejects replayed, expired, malformed, and rate-limited requests before loading private task data.
- Is the only component allowed to talk to Codex app-server and OpenAI.
- Redacts secrets from logs and never logs raw audio.

## Required controls

- Per-device public-key pairing and revocation.
- Five-minute pairing-code expiry and strict attempt limits.
- Signed request envelope containing method, canonical path, body digest, timestamp, and random nonce.
- Nonce replay cache and narrow clock-skew window.
- Short-lived authenticated WebSocket sessions.
- Idempotency keys for every state-changing action.
- Maximum audio duration and payload size.
- Audit rows for device, action, target task, decision, and result.
- Generic unauthenticated errors that reveal no Mac, task, model, or folder metadata.
- Emergency commands to revoke the watch and turn off Funnel.

## Emergency response

If the watch is lost or a credential might be compromised:

1. Disable Funnel.
2. Revoke the watch credential locally.
3. Review the bridge audit log.
4. Rotate the bridge pairing authority if compromise is suspected.
5. Re-enable Funnel only after a new watch pairing succeeds locally.

The implementation must expose these as explicit, documented commands before remote approvals are considered ready.

