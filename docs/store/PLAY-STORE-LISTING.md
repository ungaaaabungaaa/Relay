# Google Play closed-beta listing

This is the source copy for the first Wear OS closed-test listing. The owner
must review it in the Play Console against the final signed AAB, declarations,
screenshots, and production policy URLs before submission.

## Identity

- App name: **Relay for Codex**
- Package: `com.relayforcodex.wear`
- Category: Productivity
- Supported devices: Wear OS 3/API 30 or newer only
- Support: `support@relayforcodex.com`
- Privacy URL: `https://relayforcodex.com/privacy`
- Account deletion URL: `https://relayforcodex.com/account/delete`

## Short description

Review and steer Codex from a Wear OS watch.

## Full description

Relay for Codex lets invited beta users follow Codex tasks, answer questions,
review approval requests, and start work from a Wear OS watch.

Codex continues to run on your own Apple-silicon Mac. Relay Cloud only routes
end-to-end encrypted messages between an approved watch and that Mac. It cannot
decrypt prompts, commands, repository paths, approvals, task output, or voice
recordings. Codex and OpenAI credentials remain on the Mac.

Pairing uses a short code, fingerprints on both devices, and explicit approval
from Relay for Mac. You choose the workspace folders the watch may access.
Risky approvals keep the exact command and consequence visible and require a
press-and-hold.

The Mac must be awake, online, running Codex, and connected through Relay for
Mac. When it is offline, the watch shows stale cached summaries and disables
actions. Relay does not queue commands for later. No Tailscale, port forwarding,
ADB, Android phone companion, advertising, or product analytics are required.

This free beta is invite-only. It requires Relay for Mac, a beta invitation,
and access to the Google Play closed-test track.

## Play data-safety working declarations

These are implementation-derived answers, not a substitute for completing the
current Play Console questionnaire.

- Account email: collected for invite-only sign-in, encrypted at rest, not sold.
- Device/app metadata: collected for pairing, compatibility, security, and
  device management; deleted with the account.
- App activity/Codex content: end-to-end encrypted in transit through Relay
  Cloud and not readable by the service.
- Microphone: optional hold-to-record input; encrypted to the user's Mac,
  bounded to 30 seconds/2 MiB, reviewed as text before sending.
- Diagnostics: bounded redacted operational metadata retained for seven days.
- Advertising and product analytics: none.
- Account deletion: available in Relay for Mac and at the deletion URL above.
- Encryption in transit: HTTPS/WSS outside the E2EE tunnel; AES-256-GCM inside.

## Required visual assets

- Wear OS launcher icon and feature graphic using final production branding.
- Screenshots from at least one round and one square/small-screen policy layout.
- Include pairing, inbox, approval consequence, Live Monitoring, offline state,
  and device/settings screens.
- Do not use mock task data that resembles a real person's repository, email,
  credential, pairing code, or command history.
