# App Store reviewer instructions draft

Use these instructions after the signed candidate completes destination actions
and the physical Apple Watch matrix. Keep reviewer credentials, invited email
addresses, single-use links, TestFlight links, and private Mac download links in
App Store Connect reviewer fields. Treat those fields as secrets.

## Review setup

1. Install the supplied Relay Mac candidate on an Apple-silicon Mac running
   macOS 14 or newer.
2. Install Codex, sign in, and create a temporary test workspace with no private
   data.
3. Open Relay for Mac. Enter the invited reviewer email and use the single-use
   browser link to finish login.
4. Install `com.relayforcodex.watch` on a physical Apple Watch through the
   private TestFlight invitation.
5. In Relay for Mac, open **Watches** and create a six-character code.
6. Enter the code on the Apple Watch. Compare the Mac fingerprint on both
   devices, confirm it on the watch, and approve the watch fingerprint on the
   Mac.
7. Approve the temporary test workspace and no other folder.

## Safe review path

1. Start a harmless Codex task from the Mac in the approved temporary
   workspace.
2. Open the task on the Apple Watch and exercise the actions supported by the
   submitted build.
3. Review a safe approval and confirm that Relay keeps the command, folder,
   reason, and consequence visible.
4. Disconnect the Mac or watch network. Confirm stale or offline state blocks
   each mutation and queues no action.
5. Restore the connection, revoke the Apple Watch from the Mac, and confirm the
   watch loses access and clears its Relay credentials.
6. Pair the watch again if the remaining checks need it.
7. Use **Emergency Stop** on the Mac. Confirm remote watch access stops while
   the local Codex task remains on the Mac.
8. Open **Relay Cloud > Delete Relay Account** in the Mac app and review the
   confirmation. The public deletion path is
   `https://relayforcodex.com/account/delete`.

## Reviewer notes

- Relay Cloud routes encrypted envelopes and cannot decrypt task content.
- The Apple Watch contains no Codex login, Mac password, or repository files.
- The Mac must stay awake, online, and running Relay and Codex.
- Optional recorded voice requires transcript review before Relay sends text to
  Codex.
- Relay has no payment, subscription, advertising SDK, product analytics,
  public signup, or offline action queue.
- Support contact: `support@relayforcodex.com`.

Before submission, the owner must verify the invitation, TestFlight build, Mac
download, magic-link delivery, production cloud, support mailbox, policy URLs,
Emergency Stop, and deletion path from a clean reviewer account.
