# Set up Relay

The public-beta flow uses Codex, one Mac app, and one Wear OS app. It does not
use Tailscale, ADB, developer mode, port forwarding, or an Android emulator.

## What you need

- an Apple-silicon Mac running macOS 14 or newer;
- Codex installed, signed in, and able to run a task;
- an invite to the Relay beta;
- a Wear OS 3/API 30 or newer watch;
- Wi-Fi or LTE on the watch;
- the Mac awake and online while using Relay.

A Samsung watch may need Galaxy Wearable on an Android phone to complete the
manufacturer's initial setup. Relay itself has no required phone companion.

## Beta user flow

1. Download the notarized `Relay.dmg` from the matching GitHub Release.
2. Drag Relay to Applications and open it.
3. Relay verifies its embedded bridge and the local Codex installation.
4. Enter the invited email address. Relay opens the official browser page and
   sends a single-use magic link through Resend.
5. Open the link. The Mac receives short-lived access and rotating refresh
   credentials through PKCE; the refresh token stays in macOS Keychain.
6. Install **Relay for Wear OS** from the Google Play closed-test link.
7. On the Mac, choose **Start secure pairing**. A six-character code is valid
   for five minutes.
8. Enter that code on the watch. Compare the Mac fingerprint on both devices.
9. Confirm the fingerprint on the watch, then approve the watch fingerprint on
   the Mac within two minutes.
10. Choose the Mac workspace folders that the watch may browse.
11. Optionally enable **Start Relay at login**.

The watch then works over normal Wi-Fi or LTE. If the Mac disconnects, cached
summaries become stale and every approval or mutation is disabled. Relay never
queues an action to run later.

## Daily use

- Keep Relay, Codex, and the Mac awake and online.
- Use the watch for tasks, approvals, questions, instructions, and new tasks.
- Risky approvals require a press-and-hold and show the exact command, folder,
  reason, and consequence.
- System keyboard/dictation needs no OpenAI key.
- Optional hold-to-record transcription uses an OpenAI key stored only in the
  Mac Keychain and always shows a transcript review before sending.

## Lost watch or suspected compromise

- Revoke one watch from **Watches** to close its tunnel immediately.
- Use **Emergency Stop** to revoke all watches, rotate the Mac host credential,
  disconnect cloud tunnels, and stop the bridge. Existing Codex tasks continue
  on the Mac.
- Use **Delete Relay Account** to remove the account and device metadata and
  clear Relay Cloud keys from the Mac. Codex repositories stay untouched.

## Developer setup

Android Studio is needed only for Java, Android SDK tools, building, and
installing a debug build on a physical watch. Do not install an emulator.

```bash
corepack enable
pnpm install --frozen-lockfile
pnpm build:bridge-sea

export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
xcrun swift run --package-path mac RelayMac

export JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"
export ANDROID_HOME="$HOME/Library/Android/sdk"
./gradlew :wear:assembleDebug
```

For physical debug installation only, follow
[PHYSICAL-WATCH-TEST.md](PHYSICAL-WATCH-TEST.md). Release builds always use
Relay Cloud HTTPS/WSS; manual origins and the legacy loopback path are debug
recovery features.

## Cloud maintainer setup

Production launch additionally needs organization-owned Cloudflare and Resend
accounts, the `relayforcodex.com` zone, D1 IDs, Worker secrets, protected GitHub
environments, and verified email sending. See [RELEASE.md](RELEASE.md) and
[TODO.md](TODO.md). Never commit credentials or paste magic links into logs.

The Worker secrets are `JWT_SECRET`, `PII_ENCRYPTION_KEY`, `EMAIL_HMAC_KEY`,
`RATE_LIMIT_HMAC_KEY`, `RESEND_API_KEY`, and `CLOUD_ADMIN_CREDENTIAL`. The first
four are independent 32-byte base64url values. The rate-limit key hashes network
sources before D1 sees them and must not be reused for email lookup. The
cloud-admin credential is also stored in the
protected GitHub `production` environment, alongside a secret
`BETA_INVITE_EMAILS` list containing at most 25 comma- or newline-separated
addresses. Set the non-secret `RELAY_API_ORIGIN` environment variable, require
an environment reviewer, and manually run **Relay Cloud beta invites**. The
workflow sends one address at a time and logs only the final count; D1 stores
encrypted email bytes plus a separate HMAC lookup.
