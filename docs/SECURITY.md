# Relay security model

Relay gives a paired watch meaningful power over Codex. The safer public
defaults are part of the product, not optional advice.

## Default policy

- Remote Access is off until the local security self-test passes.
- The bridge and private admin API bind only to `127.0.0.1`.
- The watch can browse only roots explicitly approved in the Mac app.
- Deny and normal approval are one tap.
- Dangerous, destructive, elevated, or uncertain approval requires a
  1.5-second press-and-hold.
- Stale or offline screens are read-only and do not queue actions.
- Voice transcripts are reviewed before sending.
- Live Monitoring is visible, opt-in, time-limited, and battery-aware.

An advanced single-tap-all policy may be added later only with a warning on
both devices, device-specific storage, and audit visibility. It is not the
public default.

## Trust boundaries

### Watch

- Generates a non-exportable signing key in Android Keystore.
- Stores a device ID, bridge origin, connection preferences, last event
  sequence, and minimal stale summaries.
- Stores no Codex credential, OpenAI key, Mac password, repository contents, or
  raw audio history.
- Deletes the credential and private cache when unpaired or revoked.

### Tailscale Funnel

- Provides a public HTTPS route to one localhost port.
- Is transport, not watch identity.
- Its headers are never accepted as proof that a request came from the watch.
- Can be disabled independently without stopping Codex tasks.

### Mac bridge

- Authenticates the watch before loading private data.
- Checks device ID, timestamp, nonce, body digest, signature, and revocation.
- Applies deterministic risk and approved-workspace rules.
- Uses idempotency keys so repeated taps do not repeat actions.
- Is the only component that talks to Codex and optional OpenAI transcription.

### Private admin API

- Runs on a separate loopback port.
- Requires a random token of at least 32 bytes stored in macOS Keychain.
- Returns fingerprints and status, never admin tokens, OpenAI keys, or stored
  watch public keys.
- Produces generic errors that do not reveal secrets.

## Pairing

1. The Mac bridge creates a six-character code valid for five minutes.
2. The watch creates its Android Keystore signing key.
3. The watch submits the code and public key.
4. The Mac displays the watch identity and key fingerprint for confirmation.
5. The bridge stores the device public key and returns the device identity and
   configured remote origin.

Pairing has per-origin and global attempt limits. The code cannot be reused.

## Requests and replay protection

Every authenticated request includes the device ID, timestamp, random nonce,
body digest, and signature over the canonical method and path. The bridge
rejects an unknown or revoked device, stale timestamp, reused nonce, invalid
body digest, or invalid signature before processing the request.

Every state-changing request also includes an idempotency key. A retry returns
the original result instead of approving, steering, stopping, or creating
twice.

## Workspaces

Only folder names below approved roots are exposed. Relay canonicalizes paths,
checks symlinks, paginates listings, and rejects traversal outside a root. It
does not read file contents for the watch. macOS privacy permissions remain in
force.

## Voice

- Wear OS system input does not need an OpenAI key.
- Optional recording requests microphone permission just in time.
- The bridge enforces duration and payload limits.
- The OpenAI key stays in macOS Keychain.
- Audio is removed on success, provider failure, timeout, cancellation, and
  restart cleanup.
- A transcript is never automatically sent to Codex.

## Logs and local data

Logs redact credentials, authorization headers, prompts, command output, file
contents, audio, and Funnel origins. Audit records retain only the device,
action type, target, decision, time, risk class, and result.

Local storage contains paired-device public keys, revocation state, replay
nonces, idempotency results, bounded event metadata, workspace policy, task
aliases, and redacted audit rows. Repository files and complete Codex
conversations are not copied into Relay's database.

## Release integrity

Public releases are allowed only from `v*` tags in a protected GitHub
environment. The workflow:

- signs the Android APK with a protected stable key;
- signs every nested Mac executable with Developer ID;
- notarizes and staples the DMG;
- creates an Ed25519-signed manifest;
- binds the tag, versions, Codex range, filenames, architectures, and SHA-256
  digests together;
- rejects Intel builds, unsigned APK metadata, changed bytes, wrong tags,
  downgrades, and missing license assets.

The update public key must be trusted outside the release manifest. A failed
update preserves the previous working app or APK.

## Emergency response

If the watch is lost or a credential may be compromised:

1. Choose **Emergency Stop** on the Mac. Confirm Funnel and bridge shutdown
   results separately.
2. Revoke the lost watch in **Watches**.
3. Review the redacted audit history.
4. Re-pair only a watch you physically control.
5. Re-enable Funnel only after the local security self-test passes again.

If a release-signing key may be compromised, do not ship another tag. Remove
release access, preserve evidence, rotate the affected trust path, and publish
a clear incident notice.

Report vulnerabilities privately through GitHub's private vulnerability
reporting feature when enabled. Do not include real credentials or private
task content.
