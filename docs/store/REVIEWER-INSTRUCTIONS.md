# Google Play reviewer instructions

Relay for Codex is a watch client for a Mac application. The reviewer needs a
time-limited invited account, the matching notarized Relay Mac beta, Codex on an
Apple-silicon Mac, and a Wear OS 3+ watch. Put credentials and private download
links only in the Play Console reviewer fields, never in this repository.

## Review setup

1. Install the supplied Relay Mac build on an Apple-silicon Mac running macOS
   14 or newer.
2. Confirm Codex is installed and can run a harmless task in a temporary test
   repository.
3. Sign in to Relay for Mac with the reviewer invitation email and its
   single-use browser magic link.
4. Install `com.relayforcodex.wear` from the closed-test track.
5. In Relay for Mac, start pairing and enter the six-character code on the
   watch.
6. Compare the fingerprints on both devices, confirm on the watch, and approve
   on the Mac.
7. Allow only the temporary test repository as a workspace.

## Suggested review path

- Open the inbox and a task summary on the watch.
- Start a harmless task in the allowed temporary workspace.
- Trigger a low-risk question and answer it from the watch.
- Inspect an approval showing the exact command, folder, reason, and
  consequence; verify risky actions require press-and-hold.
- Enable Live Monitoring briefly and observe encrypted event updates.
- Disconnect Relay for Mac; verify cached content becomes stale and all
  mutations are disabled rather than queued.
- Reconnect, revoke the watch, and verify it enters the revoked state.
- Pair again only if needed, then exercise Emergency Stop on the Mac.
- Open the in-app account deletion control and the public deletion page.

## Reviewer notes

- Relay Cloud does not run Codex and cannot decrypt the task content.
- The Mac must remain awake and online; a phone companion is not required.
- The microphone feature is optional, hold-to-record, size/time bounded,
  encrypted to the Mac, and requires transcript review before sending.
- No payment, subscription, advertising, analytics, public signup, or
  background offline-action queue exists in this beta.
- Support contact: `support@relayforcodex.com`.

Before submission, the owner must verify the reviewer invitation, production
Worker, magic-link delivery, Mac download, support mailbox, and policy URLs from
a clean reviewer account.
