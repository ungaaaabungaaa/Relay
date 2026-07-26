# Relay privacy policy beta draft

This file mirrors the product behavior and `/privacy` Worker page. It is a
technical draft for owner/legal review, not a claim that legal review or the
production publication step is complete.

Relay is local-first. Codex and OpenAI credentials stay on the user's Mac. An
approved watch and Mac derive an end-to-end encryption key during fingerprint
pairing. Relay Cloud routes ciphertext and cannot decrypt Codex prompts,
commands, repository paths, approvals, task output, or voice recordings.

Relay processes the invited email address, account and device identifiers,
app/device compatibility metadata, hashed credentials, and limited operational
security and size outcomes. Email is encrypted at rest and indexed using a
separate keyed hash. Private keys and per-watch root keys are never stored in
Relay Cloud.

Operational metadata expires after seven days. Expired login, refresh,
pairing, rate-limit, and audit records are purged automatically. Relay includes
no advertising SDK and no product analytics, and it does not log plaintext
Codex content. Cloudflare provides cloud routing/storage and Resend delivers
single-use sign-in email.

Optional voice input is time/size bounded and end-to-end encrypted to the Mac.
The user reviews the transcript before it is sent to Codex. A separately
configured transcription provider may process that recording from the Mac
under the provider account selected by the user.

Users can revoke a watch, invoke Emergency Stop, sign out, or delete the Relay
account from the Mac app. Account deletion revokes hosts and watches and
removes cloud account/device metadata. It does not delete local Codex tasks or
repositories.

Privacy and deletion questions: `support@relayforcodex.com`. Do not email
credentials, magic links, pairing codes, prompts, commands, repository paths,
task output, or audio.
