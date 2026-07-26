# App Store listing draft

The owner must compare this draft with the signed candidate and current App
Store Connect forms before submission. Do not submit it while destination
actions or the physical Apple Watch matrix remain incomplete.

## Identity

- App name: **Relay for Codex**
- Subtitle: **Codex tasks on Apple Watch**
- Bundle ID: `com.relayforcodex.watch`
- Category: Productivity
- Operating system: watchOS 10 or newer
- Required companion service: Relay Mac on an Apple-silicon Mac running macOS
  14 or newer
- Support: `support@relayforcodex.com`
- Privacy URL: `https://relayforcodex.com/privacy`
- Account deletion URL: `https://relayforcodex.com/account/delete`

## Promotional copy

Review and steer Codex from Apple Watch.

Use this sentence in Promotional Text or the description after the release
owner verifies real destination actions on the submitted build.

## Full description draft

Relay for Codex is an independent Apple Watch app for an approved Relay Mac.
Codex runs on the user's Apple-silicon Mac. Relay Cloud carries end-to-end
encrypted envelopes between that Mac and the paired Apple Watch and cannot
decrypt task content.

The current source implements cloud pairing, fingerprint comparison, Keychain
identities, encrypted requests, revocation state, and destination route shells.
The release owner must connect and verify approvals, questions, instructions,
tasks, reviewed voice, pushed events, and reconnect behavior before using
consumer copy that promises those actions.

The Mac must stay awake, online, and running Relay and Codex. Relay must block
mutations while stale or offline and must not queue actions for later.

## Privacy summary

- Relay uses the invited email for account access. It encrypts email at rest and
  keeps a separate keyed lookup hash.
- Relay Cloud stores account and device routing metadata plus hashed
  credentials. Operational metadata expires after seven days.
- The Apple Watch and Mac use end-to-end encryption for task content. Relay
  Cloud cannot decrypt Codex prompts, commands, repository paths, approvals,
  task output, or voice recordings.
- Relay contains no advertising SDK and no product analytics.
- Optional recorded voice remains encrypted to the Mac. The user reviews the
  transcript before Relay sends text to Codex.
- The user can revoke an Apple Watch, use Emergency Stop, sign out, or delete
  the Relay account. Account deletion removes cloud account and device metadata
  and leaves local Codex tasks and repositories in place.

## Asset checklist

- [ ] Capture screenshots from a physical Apple Watch after real destination
      actions work against the signed candidate.
- [ ] Include pairing, task, approval consequence, offline, revocation, and
      settings states supported by the submitted build.
- [ ] Cover the physical case sizes selected for the compatibility matrix.
- [ ] Use a temporary workspace with synthetic task data and no credentials,
      account identifiers, pairing values, commands, private paths, or audio.
- [ ] Match the submitted App Store build, app icon, version, privacy answers,
      and support URLs.
