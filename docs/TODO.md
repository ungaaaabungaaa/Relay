# Relay local test and release checklist

Relay is a zero-user prototype. Source completion is not physical-device or
distribution proof.

## Automated local checks

- [x] `pnpm test` — every Node package test passes, including bridge/cloud
      integration, encrypted Apple journeys, replay, voice, and lifecycle cases.
- [x] `pnpm typecheck` — all TypeScript workspaces typecheck.
- [x] `pnpm build:bridge-sea` — the arm64 bridge single-executable artifact builds.
- [x] `pnpm smoke:bridge-sea` — the built bridge passes its launch smoke check.
- [x] `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift test --disable-sandbox --package-path mac`
      — every RelayCore and RelayMac test passes.
- [x] `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift test --disable-sandbox --package-path apple-watch`
      — every Watch transport, pairing, feature, and voice lifecycle test passes.
- [x] `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer scripts/check-watchos-source.sh`
      — the app sources typecheck for both supported watchOS architectures.
- [x] Unsigned generic watchOS build — Xcode completed the `RelayWatch` Debug
      build with `CODE_SIGNING_ALLOWED=NO` for `generic/platform=watchOS` and
      produced the app binary and compiled asset catalog.
- [x] Unsigned Watch simulator build — Xcode completed the `RelayWatch` Debug
      build with `CODE_SIGNING_ALLOWED=NO` for Series 11 (46mm), watchOS 26.0,
      destination `18534BA8-F531-45AF-AE90-B2407C119455`, using fresh derived
      data at `/private/tmp/relay-watch-ufo-series11`.

## Solo private-beta visual checklist

- [ ] Inspect both rendered app icons: the Mac app in Finder/Dock and the Watch
      app in the Watch app grid.
- [ ] Launch the Mac app and inspect the UFO menu-bar mark in both light and
      dark menu bars; verify the dashboard hierarchy, spacing, and contrast.
- [ ] Inspect Watch pairing on the smallest supported display: UFO mark, title,
      instruction, six-character field, Find Mac button, fingerprints, and
      errors must remain readable and tappable without clipping.
- [ ] Check the Watch screens at the largest supported Dynamic Type size;
      navigate pairing, inbox, approvals, questions, tasks, compose, and voice
      to confirm scrolling and controls do not overlap or clip.
- [ ] Enable VoiceOver and confirm meaningful labels and order for the UFO mark,
      pairing actions, status, warnings, destructive actions, and voice controls.
- [ ] Record screenshots or observations for any clipping, contrast, truncation,
      or tap-target issue before admitting a private-beta build.

## Interactive local or staging checks

- [ ] Launch the Mac app and confirm the bridge binds admin/watch interfaces to
      loopback, finds the signed-in Codex app-server, and passes its self-test.
- [ ] Sign in through the invite/PKCE flow against TLS staging; verify diagnostics
      show only the environment name and a truthful tunnel phase.
- [ ] Pair a Watch client, compare both fingerprints, interrupt the tunnel, and
      verify the Mac recovers only the active unexpired pending request.
- [ ] Exercise normal and dangerous approvals, deny, questions, instruction,
      steer, stop, new-task validation, duplicate taps, and pushed refresh.
- [ ] Prove offline and stale views allow review but block every mutation without
      queueing it for reconnect.
- [ ] Record, stop, transcribe, edit, send, and cancel voice; verify temporary
      audio and transcript cleanup after success, failure, inactivity, and loss.
- [ ] Confirm Watch revocation, Emergency Stop, and Relay Cloud account deletion
      require explicit scope confirmation and preserve local Codex work.
- [ ] Exercise Sparkle current, available, cancellation, and redacted-failure UI.

## Apple distribution and physical-device checks

- [ ] Select organization-owned Apple signing identities and validate the
      supported watch-only packaging structure in the current Xcode/App Store toolchain.
- [ ] Create and inspect a pre-signing watchOS archive.
- [ ] Create a signed watchOS archive from the reviewed commit.
- [ ] Upload to App Store Connect and complete TestFlight processing.
- [ ] Test pairing, Wi-Fi/cellular transitions, Mac sleep/wake, bridge restart,
      reconnect, actions, voice, revocation, and update preservation on physical Watches.
- [ ] Record VoiceOver, large text, labels, touch targets, haptics, case-size,
      watchOS-version, and battery evidence.
- [ ] Complete TestFlight review, App Store metadata/privacy declarations, App
      Store review, and organization-controlled release.
- [ ] Sign, notarize, staple, and install the Mac disk image on a clean Apple-silicon Mac.

## Ownership or security review gates

- [ ] External review covers authentication, pairing, cryptography, replay,
      idempotency, workspace containment, voice cleanup, revocation, and deletion.
- [ ] A staging incident and D1 recovery drill is completed; the production plan
      is reviewed without destructive production testing.
- [ ] The publisher legal entity and owners for Apple Developer, Cloudflare,
      Resend, support mail, DNS, signing keys, secrets, and release approval are recorded.
- [ ] Legal approval covers privacy, terms, retention, support, invite operation,
      transcription disclosure, and App Store declarations.

The release remains closed while any required unchecked gate lacks reviewed evidence.
