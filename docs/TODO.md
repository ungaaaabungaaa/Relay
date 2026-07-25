# Relay progress

This is the short release scoreboard. The detailed engineering record is in
`docs/superpowers/plans/2026-07-25-relay-public-release.md`.

## Implemented and locally verified

- [x] Codex protocol adapter and capability mapping
- [x] Localhost-only bridge and separate authenticated admin API
- [x] Device pairing, signatures, timestamp checks, nonce replay rejection,
      revocation, rate limits, and generic unauthorized responses
- [x] Tokenized Bonjour pairing sessions, hashed codes and tokens, pending Mac
      approval, pairing metadata, expiry, and global/source throttles
- [x] Idempotent approvals, questions, instructions, steering, stop, and new
      task
- [x] Canonical approved-workspace boundaries
- [x] Resumable WebSocket events and snapshot fallback
- [x] Reviewed voice transcription with temporary-audio cleanup
- [x] Complete native watch screen map and safer approval policy
- [x] Visible, time-limited, battery-aware Live Monitoring
- [x] Native Apple silicon Mac menu app and dashboard
- [x] Verified Platform Tools download, Wireless ADB wizard, and APK installer
- [x] Tailscale preflight, Funnel controls, and Emergency Stop
- [x] Official Tailscale browser login with cancellation and timeout
- [x] Resumable nine-step Mac setup and off-by-default Login Item
- [x] Wear OS 3/API 30 policy and round/square layouts
- [x] Sparkle 2, signed stable/beta appcast workflow, version-aware APK install,
      production icon, and hardened DMG packaging
- [x] Independent watchOS 10 source target and Xcode project foundation
- [x] Self-contained arm64 bridge sidecar
- [x] Apache 2.0 license, third-party notices, compatibility and release docs
- [x] Node, Wear OS, Swift, secret-scan, package, manifest, and GitHub workflow
      gates
- [x] Clickable HTML UI preview

## External release gates

- [ ] Finish Samsung setup on the reset Galaxy Watch6
- [ ] Pair the Watch6 over Wireless ADB
- [ ] Run `connectedDebugAndroidTest` on the physical watch
- [ ] Complete every physical-device matrix row
- [ ] Install and sign in to Tailscale on the Mac
- [ ] Test Funnel from a second Wi-Fi network and LTE when available
- [ ] Complete a one-hour battery observation in normal and Live Monitoring
      modes
- [ ] Configure protected Apple Developer ID, notarization, Android signing,
      Relay manifest Ed25519, and Sparkle Ed25519 material in GitHub
- [ ] Install the notarized DMG on a clean Apple silicon Mac
- [ ] Tag and publish the first verified GitHub Release
- [x] Type-check the Apple Watch target against the watchOS 10+ SDK in CI
- [ ] Sign and run the Apple Watch target, then complete the
      physical/TestFlight Phase 2 matrix

## Release rule

Do not call version 1 released, open the final release pull request, or publish
a `v*` tag until every external gate above is checked with evidence. Local
green tests prove the code checkpoint; they do not prove the physical watch,
public network, Apple notarization account, or clean-machine experience.
