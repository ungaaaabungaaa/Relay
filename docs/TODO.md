# Relay release gates

## Completed source and toolchain cut

- [x] Keep Relay Cloud, the Apple-silicon Mac app and bridge, and the independent
      watchOS 10+ target.
- [x] Remove the retired client source, build inputs, release artifacts, active
      documentation, and store material.
- [x] Use permanent Apple product identifiers and a schema version 2 Mac release
      manifest with six artifacts.
- [x] Run Apple Watch Swift, source, and unsigned generic watchOS build checks in
      the GitHub release workflow.

Relay remains a zero-user prototype. These checks establish the repository
shape. They do not prove archive packaging, signed distribution, or physical
Apple Watch behavior.

## Product behavior gates

- [ ] Connect real Apple Watch destination actions for approvals, questions,
      instructions, task controls, and new tasks.
- [ ] Connect pushed encrypted events to destination state.
- [ ] Complete reviewed voice recording, transcript edit, send, and cancel
      behavior.
- [ ] Prove reconnect behavior after network loss, Mac sleep, Mac wake, bridge
      restart, and cloud tunnel replacement.
- [ ] Prove stale and offline mutation blocking with no queued action.
- [ ] Prove revocation, local cache removal, Emergency Stop, and account
      deletion on the release candidate.

## Apple distribution gates

- [ ] Add or validate Apple's supported watch-only packaging structure. The
      current project has one `RelayWatch` target with `SKIP_INSTALL = YES` and
      has not produced an App Store-distributable archive.
- [ ] Add or validate the non-executable iOS wrapper target if current Xcode and
      App Store tooling require it. Keep it as a packaging stub with no iPhone
      companion product.
- [ ] Create a pre-signing archive and inspect the products, embedded watch app,
      bundle identifiers, metadata, entitlements, install settings, and absence
      of an iOS executable before TestFlight upload or App Store review.
- [ ] Create a signed watchOS archive from the reviewed commit.
- [ ] Upload the archive and complete TestFlight processing.
- [ ] Run the full signed-build test through TestFlight.
- [ ] Complete App Store metadata, privacy declarations, reviewer access, and
      App Store review.
- [ ] Release an approved App Store build under the organization-owned account.

## Physical evidence gates

- [ ] Complete the physical-device matrix across selected Apple Watch models,
      case sizes, watchOS versions, and Wi-Fi or cellular paths.
- [ ] Record accessibility evidence for VoiceOver, large text, touch targets,
      labels, and haptics.
- [ ] Record normal-use and active-update battery observations.
- [ ] Prove pairing and working-state preservation across a TestFlight update.

## Mac and security gates

- [ ] Install the signed and notarized Mac disk image on a clean Apple-silicon
      Mac with no development checkout.
- [ ] Complete an external review of authentication, pairing, cryptography,
      replay handling, workspace containment, revocation, and deletion.
- [ ] Complete a production incident drill for Emergency Stop, credential
      rotation, account deletion, and D1 recovery.

## Ownership gates

- [ ] Confirm the publisher legal entity, Apple Developer account owner,
      Cloudflare owner, Resend owner, support mailbox owner, signing-key
      custodians, and release approvers.
- [ ] Obtain legal approval for privacy, terms, retention, support, and App Store
      declarations.
- [ ] Verify production DNS, email delivery, policy URLs, cloud secrets, and
      invite administration under organization control.

The release stays closed while any required gate lacks reviewed evidence.
