# App Store review and TestFlight rehearsal

Relay remains a zero-user prototype. Use these paths after the signed candidate
completes destination actions, archive validation, and the physical Apple Watch
matrix.

## TestFlight beta rehearsal

TestFlight distributes beta builds to internal and external testers. An
external beta build may enter TestFlight App Review before testers receive it.
That beta review and the tester rehearsal occur before App Store App Review.

1. Upload the validated candidate to App Store Connect and wait for TestFlight
   processing.
2. Add the beta description, contact information, and test focus in the
   TestFlight fields.
3. Submit the external build to TestFlight App Review when App Store Connect
   requires it.
4. Invite the approved tester group. Testers install the beta through
   TestFlight on a physical Apple Watch.
5. Give testers the private Mac build, Relay invite, temporary-workspace setup,
   and safe-task instructions through the controlled beta channel.
6. Run the review scenario below and record the physical evidence.

## App Store App Review

App Store reviewers evaluate the version submitted for App Store review. Do not
instruct an App Store reviewer to install the Apple Watch build through
TestFlight.

Select the validated Apple Watch build for the App Store version, then put the
review environment details in **App Review Information**. Keep these values in
App Store Connect and treat credentials and private links as secrets:

- private Relay Mac download URL and any access password;
- Relay invite or demo-account access, including the sign-in path;
- temporary workspace setup and a harmless Codex task;
- Mac-awake and network requirements;
- six-character pairing and fingerprint steps;
- revocation, offline, and Emergency Stop instructions;
- in-app account-deletion steps and
  `https://relayforcodex.com/account/delete`;
- special instructions needed to reach each submitted feature.

The reviewer launches the submitted App Store version through Apple's review
environment and uses the Mac build and account access from App Review
Information.

## Review scenario

1. Install the supplied Relay Mac candidate on an Apple-silicon Mac running
   macOS 14 or newer.
2. Install Codex, sign in, and create the documented temporary workspace.
3. Open Relay for Mac. Use the assigned Relay invite or demo account to finish
   sign-in.
4. Launch the submitted Apple Watch version for App Store App Review. Beta
   testers launch the approved TestFlight build.
5. In Relay for Mac, open **Watches** and create a six-character code.
6. Enter the code on the Apple Watch. Compare the Mac fingerprint on both
   devices, confirm it on the watch, and approve the watch fingerprint on the
   Mac.
7. Approve the temporary workspace and no other folder.
8. Start a harmless Codex task in that workspace. Exercise the actions in the
   submitted version.
9. Review a safe approval and confirm that Relay keeps the command, folder,
   reason, and consequence visible.
10. Disconnect the Mac or watch network. Confirm stale or offline state blocks
    each mutation and queues no action.
11. Restore the connection, revoke the Apple Watch from the Mac, and confirm the
    watch loses access and clears its Relay credentials.
12. Pair the watch again if the remaining checks need it. Use **Emergency
    Stop** on the Mac and confirm remote watch access stops while the local
    Codex task remains on the Mac.
13. Open **Relay Cloud > Delete Relay Account** and review the confirmation and
    public deletion path.

## Reviewer notes

- Relay Cloud routes encrypted envelopes and cannot decrypt task content.
- The Apple Watch contains no Codex login, Mac password, or repository files.
- The Mac must stay awake, online, and running Relay and Codex.
- Optional recorded voice requires transcript review before Relay sends text to
  Codex.
- Relay has no payment, subscription, advertising SDK, product analytics,
  public signup, or offline action queue.
- Support contact: `support@relayforcodex.com`.

Before either review path, the owner must verify the private Mac download,
invite or demo access, magic-link delivery, production cloud, support mailbox,
policy URLs, Emergency Stop, and deletion path from a clean account.
