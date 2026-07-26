# Physical Apple Watch release test

Source checks and unsigned builds do not prove behavior on a physical watch.
Record each result from the release candidate and retain secret-free evidence.

Do not put account names, email addresses, credentials, pairing codes,
fingerprints, task text, commands, workspace paths, repository content, or
audio in the evidence.

## Test setup

- Use an Apple-silicon Mac on macOS 14 or newer with the candidate Relay Mac
  build and a working Codex installation.
- Use a physical Apple Watch on watchOS 10 or newer.
- Use a temporary repository with no private data.
- Test the signed candidate that will enter TestFlight or App Store review.

## Pending evidence matrix

| Test | Result | Evidence |
| --- | --- | --- |
| Xcode install to a paired physical Apple Watch | Pending | |
| Signed TestFlight install on the same release candidate | Pending | |
| Six-character code pairing and matching Mac fingerprint on both devices | Pending | |
| Watch fingerprint approval on the Mac and scoped credential receipt | Pending | |
| Wi-Fi connection and transition to cellular where the model supports it | Pending | |
| Recovery after Mac sleep, wake, network loss, and Relay restart | Pending | |
| Normal approval and dangerous approval confirmation | Pending | |
| Question response from the Apple Watch | Pending | |
| Instruction sent to an existing task | Pending | |
| Existing-task list, detail, and stop controls | Pending | |
| New task in an approved temporary workspace | Pending | |
| Recorded voice, transcript review, edit, send, and cancel paths | Pending | |
| Watch revocation closes access and removes cached credentials | Pending | |
| Stale and offline states block each mutation and queue no action | Pending | |
| Accessibility labels, large text, VoiceOver, touch targets, and haptics | Pending | |
| One-hour normal-use battery observation | Pending | |
| One-hour active-update battery observation | Pending | |
| TestFlight update preserves pairing and working state | Pending | |
| App Store update preservation on an approved release build | Pending | |
| Emergency Stop revokes watch access while Codex tasks remain on the Mac | Pending | |

## Acceptance notes

Record the Apple Watch model, case size, watchOS version, Mac model, macOS
version, Relay versions, network path, result, and evidence location. Add a
model to [COMPATIBILITY.md](COMPATIBILITY.md) after a maintainer reviews the
evidence.

The release remains blocked while any row is pending or failed. A source test,
Swift package test, unsigned generic build, or preview screen cannot replace a
signed physical-device run.
