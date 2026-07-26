# Relay release guide

Relay has two separate distribution paths. A Git tag can publish the Mac
release and Sparkle feeds. App Store Connect handles the Apple Watch archive.
Neither path proves the other one.

Relay remains a zero-user prototype. The project has not published a verified
public Mac release, TestFlight build, or App Store build from this checkpoint.

## 1. GitHub and Sparkle: Mac distribution

The `GitHub Release` workflow targets an arm64 Apple-silicon Mac and performs
these steps on a protected `release` environment:

1. verify the tag and release inputs;
2. run JavaScript, Mac Swift, Apple Watch Swift, source, and unsigned generic
   watchOS build checks;
3. build the arm64 bridge and Mac app;
4. sign the nested executables and Mac application;
5. create, notarize, staple, and verify `Relay.dmg`;
6. create and sign a schema version 2 release manifest;
7. create `SHA256SUMS`;
8. generate and verify the stable or beta Sparkle appcast;
9. upload the verified GitHub Release assets and publish the appcast through
   GitHub Pages.

### Schema version 2 manifest

The signed manifest contains six artifacts and rejects any other count:

1. `Relay.dmg`, signed, arm64;
2. `Relay-<version>.tar.gz`, source;
3. `LICENSE`;
4. `NOTICE`;
5. `THIRD_PARTY_NOTICES.md`;
6. `COMPATIBILITY.md`.

`SHA256SUMS` covers those release files plus `release-manifest.json`. The
workflow also publishes `appcast.xml` or `appcast-beta.xml`. The bridge stays
inside the Mac app and disk image.

### GitHub release secrets

Configure these eight secrets in the protected `release` environment. The
current workflow references no watch-distribution secret.

| Secret | Use |
| --- | --- |
| `APPLE_SIGNING_IDENTITY` | Developer ID Application identity name |
| `APPLE_CERTIFICATE_BASE64` | Base64 PKCS#12 Developer ID certificate |
| `APPLE_CERTIFICATE_PASSWORD` | PKCS#12 password |
| `APPLE_ID` | Notarization account |
| `APPLE_APP_SPECIFIC_PASSWORD` | Notarization app-specific password |
| `APPLE_TEAM_ID` | Apple developer team identifier |
| `RELAY_RELEASE_PRIVATE_KEY_BASE64` | PKCS#8 Ed25519 key for the release manifest |
| `SPARKLE_PRIVATE_KEY` | Ed25519 key for Sparkle appcasts |

Keep private keys and certificate material in an organization-owned secret
store with a recovery plan. Do not put them in source, issues, workflow logs,
release assets, or diagnostic archives.

## 2. App Store Connect: Apple Watch distribution

The Apple Watch release needs an App Store-distributable archive and a separate
signing path.

### Pre-signing packaging gate

The current Xcode project contains one `RelayWatch` application target. Debug
and Release both set `SKIP_INSTALL = YES`. That project can compile source, but
it has not produced an archive that proves App Store distribution readiness.

Before using production signing assets, maintainers must:

1. create or validate Apple's supported watch-only packaging structure with the
   current Xcode and App Store Connect toolchain;
2. add or validate the non-executable iOS wrapper target if the current tools
   require it for watch-only App Store packaging;
3. keep the wrapper as a packaging stub with no iOS executable or iPhone user
   experience, and ship no iPhone companion product;
4. confirm the root and watch bundle identifiers, target dependencies, archive
   scheme, and install settings against an Xcode-created watch-only template;
5. create an archive without production credentials and inspect its products,
   embedded watch app, metadata, entitlements, and absence of an iOS executable;
6. record the archive contents and resolve every Organizer validation error
   before signing, TestFlight upload, or App Store review.

After this gate passes, the release owner must:

1. select the production Apple developer team and App Store signing profile;
2. archive `com.relayforcodex.watch` from the exact reviewed commit;
3. validate and upload the archive to App Store Connect;
4. wait for TestFlight processing and complete export-compliance fields;
5. run the physical Apple Watch matrix against that processed build;
6. supply review credentials and private links through App Store Connect;
7. submit the build and metadata for App Store review;
8. release the approved version under the organization-owned account.

The current GitHub workflow validates Apple Watch Swift source and runs an
unsigned generic watchOS build. It does not create, inspect, sign, or upload an
App Store-distributable archive. Packaging, signing, TestFlight processing,
review, and release remain external gates.

## Before a release tag or upload

- Start from a clean reviewed commit with the full suite green.
- Complete the pre-signing packaging gate and retain the archive-content
  record.
- Complete every applicable row in
  [PHYSICAL-APPLE-WATCH-TEST.md](PHYSICAL-APPLE-WATCH-TEST.md).
- Confirm destination actions, pushed events, reviewed voice, and reconnect
  behavior on the signed Apple Watch candidate.
- Install the notarized Mac disk image on a clean Apple-silicon Mac.
- Confirm the Codex compatibility range and permanent bundle identifiers.
- Review `LICENSE`, `NOTICE`, `THIRD_PARTY_NOTICES.md`, store copy, and policy
  pages.
- Confirm production account ownership and private security-review signoff.

## Publish the Mac release

Create one signed semantic `v*` tag after the gates pass:

```bash
git tag -s v1.0.0 -m "Relay 1.0.0"
git push origin v1.0.0
```

The workflow creates no GitHub Release if a required check fails.

## Verify published Mac assets

On a separate Apple-silicon Mac:

```bash
shasum -a 256 -c SHA256SUMS
spctl -a -vv -t install Relay.dmg
xcrun stapler validate Relay.dmg
node scripts/verify-release.mjs \
  --manifest release-manifest.json \
  --artifacts . \
  --tag v1.0.0 \
  --public-key-base64 "$RELAY_RELEASE_PUBLIC_KEY_BASE64"
```

Distribute the trusted manifest public key outside the release that it
verifies.

## Withdraw a broken release

Do not move or replace a published tag or asset. Mark the release as withdrawn,
describe the problem without exposing private data, fix it on a new commit, and
publish a higher version after all gates pass again.
