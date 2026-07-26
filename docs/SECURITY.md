# Relay security model

Relay gives a paired watch meaningful control over Codex. Safer behavior is the
default, not an optional mode.

## Default policy

- The bridge and private admin API bind only to `127.0.0.1`.
- The Mac opens an outbound Relay Cloud connection; there is no inbound public
  Mac port.
- The watch can browse only roots explicitly approved in the Mac app.
- Dangerous, destructive, elevated, or uncertain approvals require a
  press-and-hold and retain exact command/folder/consequence text.
- Stale or offline screens are read-only and never queue actions.
- Voice transcripts are reviewed before sending.
- Live Monitoring is visible, opt-in, time-limited, and battery-aware.

## Trust boundaries

### Watch

- Generates separate P-256 signing and key-agreement identities.
- Uses Android Keystore ECDH on API 31+.
- On API 30, encrypts a software P-256 private key with a non-exportable
  Android Keystore AES key.
- Stores the scoped cloud credential and E2EE root key only inside
  Keystore-protected encrypted storage.
- Stores no Codex/OpenAI credential, Mac password, repository content, or raw
  audio history.

### Relay Cloud

- Stores account and device routing metadata, encrypted email, and hashed
  refresh/host/watch credentials.
- Routes opaque encrypted envelopes through one hibernating Durable Object per
  account.
- Has no Mac/watch private key or E2EE root key and cannot decrypt Codex
  content.
- Applies account, host, device, IP, and pairing limits and returns generic
  authentication errors.
- Retains bounded operational metadata for seven days, then purges it.
- Does not queue actions while the Mac is offline.

### Mac and bridge

- Stores Mac identities, refresh token, host credential, and watch root keys in
  macOS Keychain.
- Authenticates and decrypts the outer envelope before applying the existing
  signed-request contract.
- Checks device ID, timestamp, nonce, body digest, signature, revocation, and
  idempotency after decryption. Cloud delivery is never authorization.
- Is the only component that talks to Codex and optional transcription.

## Pairing

1. The signed-in Mac creates a five-minute session and six-character code.
2. The watch sends its signing/agreement public keys and device metadata.
3. Both devices show fingerprints for comparison.
4. The Mac approves within two minutes.
5. Mac and watch derive the same root key with P-256 ECDH and HKDF-SHA256 using
   the pairing session nonce.
6. The Mac creates the watch credential, sends only its SHA-256 hash to D1, and
   encrypts the real credential for the watch with AES-256-GCM.
7. The watch polls with a separate high-entropy token and decrypts the payload.

Cloud stores only the short-lived opaque completion payload. Denial, expiry, or
cancellation creates no active watch.

## Encrypted requests and replay protection

Outer routing fields are canonical authenticated additional data. Each peer
persists monotonically increasing sequences, rejects replay across reconnects
and process restarts, and rejects stale or modified envelopes.

Inside the encrypted message, the watch retains the signed canonical request,
timestamp, random nonce, replay protection, revocation, and idempotency key.
A retry returns the first mutation result instead of acting twice.

## Workspaces and voice

Relay canonicalizes approved paths, resolves symlinks, and rejects traversal
outside allowed roots. It does not expose repository file contents through the
folder browser.

System input needs no OpenAI key. Optional recordings are capped at 30 seconds
and 2 MiB by protocol policy, authenticated inside the tunnel, deleted after
success/failure/timeout, and never sent to Codex without transcript review.

## Account controls

- **Revoke** marks one device revoked in D1, closes its connected tunnel, and
  removes its Mac root key.
- **Emergency Stop** revokes all watches, rotates the host credential,
  disconnects tunnels, clears watch root keys, and stops the bridge while
  leaving Codex tasks running.
- **Delete Relay Account** removes PII/device metadata, revokes all sessions,
  and clears Relay Cloud credentials from the Mac.

## Release integrity

Protected workflows build a signed Wear package and Apple-silicon Mac app,
verify the arm64 sidecar and package identifiers, sign the manifest and Sparkle
feed, notarize/staple the DMG, scan for secrets, and reject modified bytes,
wrong tags, downgrades, unsigned APK metadata, or missing license assets.

Published tags and assets are never silently replaced. A broken release is
withdrawn and replaced by a higher version.

Report vulnerabilities privately through GitHub private vulnerability
reporting when enabled. Never include real credentials, magic links, pairing
codes, prompts, commands, repository paths, or task output.
