# Relay security model

Relay gives an approved Apple Watch narrow control over Codex on one Mac. The
Mac remains the authorization boundary for Codex and workspace access.

## Default controls

- The bridge and private admin API bind to `127.0.0.1`.
- The Mac opens the outbound Relay Cloud tunnel. Relay exposes no public inbound
  Mac port.
- The Apple Watch can name paths within roots approved in the Mac app.
- Relay shows exact command, folder, reason, and consequence details before a
  dangerous approval.
- Stale and offline screens block mutations. Relay Cloud does not queue actions.
- Relay requires transcript review before sending voice-derived text to Codex.
- Signed requests, encrypted envelopes, replay sequences, and idempotency keys
  protect remote mutations.

## Apple Watch identities

The Apple Watch creates separate P-256 signing and key-agreement material.
`RelayWatchIdentity` manages the signing key through Security framework key
storage and Keychain access control. `RelayWatchAgreementIdentity` stores its
CryptoKit P-256 private-key material in Keychain with
`AfterFirstUnlockThisDeviceOnly` accessibility.

Relay does not describe both storage paths as one hardware-backed guarantee.
The watch stores no Codex credential, Mac password, repository contents, or raw
audio history.

## Pairing and encryption

1. The signed-in Mac creates a five-minute session and a six-character code.
2. The Apple Watch sends its signing and agreement public keys with limited
   device metadata.
3. The Mac and watch display fingerprints for comparison.
4. The Mac approves the pending watch request within the session limit.
5. Mac and watch derive the same root key through P-256 ECDH and HKDF-SHA256,
   using the pairing-session nonce.
6. The Mac hashes the scoped watch credential for Relay Cloud and encrypts the
   credential for the watch with AES-256-GCM.
7. The Apple Watch stores the approved cloud configuration and root material in
   Keychain.

Denial, expiry, or cancellation creates no active watch.

## Encrypted requests and replay protection

Relay authenticates the outer routing fields as AES-256-GCM additional data.
Each peer persists sequence state and rejects duplicate, out-of-order, stale,
or modified envelopes across restarts and reconnects.

The inner request includes the device ID, timestamp, nonce, body digest, P-256
signature, and idempotency key. The Mac checks those values after decryption
and before it asks the bridge to act. Cloud delivery grants no authorization.
A repeated mutation key returns the first result instead of running the action
twice.

## Relay Cloud boundary

Relay Cloud stores encrypted email, account and device routing metadata, and
hashed lookup, refresh, host, and watch credentials. It has no Mac or watch
private key and no E2EE root key. The service cannot decrypt Codex prompts,
commands, repository paths, approvals, task output, or voice recordings.

Relay Cloud retains bounded, redacted operational metadata for seven days and
then purges it. The service has no advertising SDK, product analytics, or
plaintext Codex-content logging.

## Workspaces and reviewed voice

The bridge canonicalizes approved paths, resolves symlinks, and rejects folder
traversal outside the selected roots. Folder browsing returns names and paths,
not repository file contents.

Optional recorded voice uses encrypted chunks with a 30-second and 2 MiB
limit. The Mac assembles the chunks and deletes temporary audio after success,
failure, or timeout. Relay must show editable transcript text before the user
sends it to Codex. The unfinished Apple Watch voice destination remains a
release gate.

## Revocation and deletion

- **Revoke** marks one Apple Watch as revoked, closes its cloud tunnel, and
  removes its Mac root material.
- **Emergency Stop** revokes watches, rotates the host credential, disconnects
  tunnels, clears watch root material, and stops the bridge. Codex tasks stay on
  the Mac.
- **Delete Relay Account** revokes sessions, removes cloud account and device
  metadata, and clears Relay Cloud credentials from the Mac. Local Codex tasks
  and repositories stay in place.

## Mac release integrity

The signed schema version 2 release manifest covers the Mac release. It binds
the arm64 `Relay.dmg`, source archive, `LICENSE`, `NOTICE`,
`THIRD_PARTY_NOTICES.md`, and `COMPATIBILITY.md` to their SHA-256 digests. The
GitHub workflow signs the Mac application, notarizes and staples the disk
image, verifies the manifest, and signs the Sparkle feed before publication.

Apple signs and distributes the watchOS archive through App Store Connect as a
separate release path. The current GitHub workflow performs watchOS source and
unsigned build checks; it does not upload a watch archive.

Report vulnerabilities through GitHub private vulnerability reporting when
the project enables it. Keep credentials, sign-in links, pairing codes,
fingerprints, task content, commands, paths, and audio out of reports.
