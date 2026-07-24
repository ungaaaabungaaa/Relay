# Relay release guide

This is the maintainer path for a GitHub-only public release. A tag must not be
created until the clean-Mac and physical Galaxy Watch6 checklist in
`docs/PHYSICAL-WATCH-TEST.md` is complete.

## What the workflow publishes

- notarized Apple silicon `Relay.dmg`;
- signed `relay-wear.apk`;
- signed arm64 `relay-bridge-arm64`;
- source archive for the exact tag;
- `SHA256SUMS` and Ed25519-signed `release-manifest.json`;
- Apache 2.0 license, notice, third-party notices, and compatibility matrix;
- generated GitHub release notes.

## One-time GitHub setup

Create an environment named `release`, enable required reviewers, and restrict
deployment branches to protected tags. Add these environment secrets:

| Secret | Purpose |
| --- | --- |
| `APPLE_SIGNING_IDENTITY` | Developer ID Application identity name |
| `APPLE_CERTIFICATE_BASE64` | Base64 PKCS#12 Developer ID certificate |
| `APPLE_CERTIFICATE_PASSWORD` | PKCS#12 password |
| `APPLE_ID` | Notarization account |
| `APPLE_APP_SPECIFIC_PASSWORD` | App-specific notarization password |
| `APPLE_TEAM_ID` | Apple developer team |
| `ANDROID_KEYSTORE_BASE64` | Base64 Android release keystore |
| `ANDROID_KEYSTORE_PASSWORD` | Android keystore password |
| `ANDROID_KEY_ALIAS` | Android signing alias |
| `ANDROID_KEY_PASSWORD` | Android key password |
| `RELAY_RELEASE_PRIVATE_KEY_BASE64` | Base64 PKCS#8 Ed25519 private key |

Add these non-secret repository or environment variables:

| Variable | Example |
| --- | --- |
| `RELAY_RELEASE_PUBLIC_KEY_BASE64` | Raw 32-byte Ed25519 public key in base64 |
| `RELAY_WATCH_VERSION_CODE` | `10000` |
| `CODEX_MIN_VERSION` | `0.144.0` |
| `CODEX_MAX_VERSION` | `0.144.x` |

Keep the Android key and update-signing private key in a separate encrypted
backup. Losing either key prevents safe upgrades. Never put a private key,
certificate password, OpenAI key, device key, or admin token in a GitHub issue,
workflow file, release asset, or diagnostic report.

## Before tagging

1. Start from a clean `main` commit with the quality workflow green.
2. Update the Wear version code. It must only increase.
3. Confirm the compatibility range against the installed Codex release.
4. Complete every physical-device row and record the evidence.
5. Install the locally packaged app on a clean Apple silicon Mac.
6. Confirm the update public key embedded by the build matches the configured
   GitHub variable.
7. Review `LICENSE`, `NOTICE`, and `THIRD_PARTY_NOTICES.md`.

## Publish

Create and push only a semantic `v*` tag:

```bash
git tag -s v1.0.0 -m "Relay 1.0.0"
git push origin v1.0.0
```

The release workflow uses the standard arm64 `macos-15` GitHub-hosted runner.
It imports signing material into a temporary keychain, runs the full automated
suite, signs the APK and nested Mac executables, notarizes and staples the DMG,
creates and signs the manifest, verifies every digest and signature, and then
creates the GitHub Release. The cleanup step deletes temporary signing files.

If any check fails, no GitHub Release is created.

## Verify the published result

On a separate Apple silicon Mac:

```bash
shasum -a 256 -c SHA256SUMS
spctl -a -vv -t install Relay.dmg
xcrun stapler validate Relay.dmg
apksigner verify --verbose --print-certs relay-wear.apk
```

Then run the manifest verifier using the trusted public key distributed
separately from the manifest:

```bash
node scripts/verify-release.mjs \
  --manifest release-manifest.json \
  --artifacts . \
  --tag v1.0.0 \
  --public-key-base64 "$RELAY_RELEASE_PUBLIC_KEY_BASE64" \
  --verify-apk-signature
```

Do not trust a public key supplied only inside the same release being checked.

## Rollback

Do not move or replace an existing tag. Mark a broken release as withdrawn,
explain the problem, and publish a higher version after the fix passes all
gates. Relay rejects downgrades, invalid signatures, changed bytes, and Intel
artifacts; a failed update preserves the previous installed app or APK.
