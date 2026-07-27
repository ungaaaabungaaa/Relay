# Relay local test and release checklist

Relay is a zero-user prototype. Source completion is not physical-device or
distribution proof.

## Automated local checks

The following native-Watch checks were recorded from the `watch-native-ui`
release worktree on 2026-07-27. They are local source/build evidence, not a
device or distribution result.

- [ ] `pnpm --filter @relay/bridge test`, `pnpm test`, and `pnpm typecheck`
      — not re-run here: the isolated worktree has no installed Node packages,
      and package-registry egress was unavailable. Re-run after restoring the
      locked dependency cache or granting approved registry access.
- [ ] `pnpm build:bridge-sea` and `pnpm smoke:bridge-sea` — require the same
      Node dependency gate before they can be re-verified from this worktree.
- [ ] `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift test --disable-sandbox --package-path mac`
      and `xcrun swift build --disable-sandbox --package-path mac` — pending:
      the pinned Sparkle package is not cached in this worktree and GitHub
      access was unavailable. Re-run after resolving that dependency.
- [x] `node --test apple-watch/test/project.test.mjs` — 17 project/source
      contracts pass, including the native menu contract and complete source-
      checker coverage.
- [x] `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift test --disable-sandbox --package-path apple-watch`
      — 62 Watch transport, pairing, feature, voice-lifecycle, and source
      contract tests pass.
- [x] `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer scripts/check-watchos-source.sh`
      — the app sources typecheck for both supported watchOS architectures.
- [ ] Unsigned generic watchOS build — attempted with fresh derived data at
      `/private/tmp/relay-watch-native-generic`; Swift sources compiled, but
      `actool` could not complete because this Xcode installation has no
      available watch simulator runtime. Re-run after installing a runtime.
- [ ] Unsigned Watch simulator builds and inspection — `-showdestinations`
      reported only generic placeholders because CoreSimulatorService was
      unavailable. No 40 mm, 44 mm, or 46 mm result is recorded.

## Solo private-beta visual checklist

- [ ] Inspect both rendered app icons: the Mac app in Finder/Dock and the Watch
      app in the Watch app grid.
- [ ] Launch the Mac app and inspect the UFO beside the other menu-bar items in
      both light and dark menu bars. No dashboard window is expected. Exercise
      every root item and submenu, including all confirmation dialogs, and
      verify spacing, contrast, labels, and destructive-action wording.
- [ ] Inspect Watch pairing on the smallest supported display: UFO mark, title,
      instruction, six-character field, Find Mac button, fingerprints, and
      errors must remain readable and tappable without clipping.
- [ ] Check the Watch screens at the largest supported Dynamic Type size;
      navigate Pair with Mac, the pending `Needs you` queue, All clear,
      approvals, questions, tasks, instruction, New task, Voice, and More to
      confirm scrolling and controls do not overlap or clip.
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
