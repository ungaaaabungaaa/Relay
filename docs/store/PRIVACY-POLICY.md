# Relay privacy policy draft

This file mirrors Relay behavior and the `/privacy` Worker page. The owner and
legal reviewer must approve the final publisher identity, effective date,
contact details, and App Store declarations before publication.

Relay is local-first. Codex and OpenAI credentials stay on the user's Mac. An
approved Apple Watch and Mac derive an end-to-end encryption key during
fingerprint pairing. Relay Cloud routes ciphertext and cannot decrypt Codex
prompts, commands, repository paths, approvals, task output, or voice
recordings.

Relay processes the invited email address, account and device identifiers,
App Store build and device compatibility metadata, hashed credentials, and
limited operational security and size outcomes. Relay encrypts email at rest
and indexes it with a separate keyed hash. Relay Cloud does not store private
keys or per-watch E2EE root keys.

Operational metadata expires after seven days. Scheduled purge work removes
expired login, refresh, pairing, rate-limit, and audit records. Relay includes
no advertising SDK and no product analytics, and it does not log plaintext
Codex content. Cloudflare provides cloud routing and storage. Resend delivers
single-use sign-in email.

Optional voice input has time and size limits and stays end-to-end encrypted to
the Mac. The user reviews the transcript before Relay sends it to Codex. A
transcription provider configured on the Mac may process the recording under
the provider account selected by the user.

Users can revoke an Apple Watch, invoke Emergency Stop, sign out, or delete the
Relay account from the Mac app. Account deletion revokes hosts and watches and
removes cloud account and device metadata. It does not delete local Codex tasks
or repositories.

Privacy and deletion questions: `support@relayforcodex.com`. Do not email
credentials, sign-in links, pairing codes, fingerprints, prompts, commands,
repository paths, task output, or audio.
