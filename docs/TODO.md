# Relay public-beta scoreboard

## Implemented and locally verified

- [x] Cloudflare Worker, D1 migrations, hibernating Durable Object router,
      staging/production configuration, and deploy workflow
- [x] Invite-only passwordless email sessions, PKCE, magic links, access
      tokens, refresh rotation/reuse defense, logout, and account deletion
- [x] Encrypted email storage and hashed account/device credentials
- [x] P-256 ECDH, HKDF-SHA256, AES-256-GCM envelopes, shared Mac/Wear vectors,
      replay state, and authenticated routing metadata
- [x] Native Mac outbound tunnel, Keychain identities, reconnect, device
      management, workspace policy, Emergency Stop, and Login Item
- [x] Wear OS cloud code entry, fingerprint confirmation, approval polling,
      API-30 secure fallback, encrypted requests, revoked/offline states, round
      and square layouts, and reviewed voice transport
- [x] Loopback bridge authorization, signed inner requests, idempotent
      mutations, Codex adapter, workspace boundaries, and redacted audit data
- [x] Google Play application ID and signed APK/AAB-capable Gradle release setup
- [x] Sparkle 2, hardened Mac packaging, signed manifest, notarization workflow,
      and advanced GitHub APK fallback
- [x] Consumer Mac app no longer contains Tailscale, Funnel, Platform Tools,
      Wireless ADB, or a bundled APK
- [x] Native Apple Watch project foundation for Phase 2
- [x] HTML UI preview and README screen boards

## Code work still open

- [x] Production invite-administration command and protected operator workflow
- [ ] True pushed cloud event stream for Live Monitoring; the current cloud
      build uses safe foreground/periodic snapshot refresh
- [ ] 128 KiB chunked voice transfer for the full 2 MiB protocol limit
- [ ] Finish Apple Watch cloud transport and physical TestFlight flow
- [ ] Complete store listing assets, reviewer instructions, privacy/terms copy,
      and production support pages

## Owner and external launch gates

- [ ] Acquire and verify `relayforcodex.com` and permanent store names
- [ ] Organization-owned Cloudflare, Resend, Apple Developer, and Google Play
      accounts
- [ ] Configure D1 IDs, DNS, verified sending domain, protected GitHub
      environments, and production Worker secrets
- [ ] Store Apple, Android, Sparkle, release-manifest, JWT, PII-encryption,
      email-HMAC, and cloud-admin signing material outside Git
- [ ] External review of authentication, pairing, and cryptography
- [ ] Seven-day five-user dogfood and 24-hour reconnect test
- [ ] Google Play closed test with the required continuous testers
- [ ] Three physical Wear OS devices across two OEMs, including Wear OS 3,
      small/large screens, and a Wi-Fi-to-LTE transition
- [ ] Normal and Live Monitoring battery observations
- [ ] Account deletion, Emergency Stop, key rotation, and D1 restore drill
- [ ] Notarized DMG installation on a clean Apple-silicon Mac
- [ ] Publish `v0.2.0-beta.1` only after every beta gate has evidence

Local green tests prove the code checkpoint. They do not prove Cloudflare or
store deployment, physical hardware behavior, notarization credentials, or
review approval.
