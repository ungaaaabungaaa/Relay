# Relay Watch Native UI Design

**Date:** 2026-07-27  
**Status:** Approved visual direction; implementation contract

## Goal

Make Relay feel built for Apple Watch: quick to read, safe to act on, and easy
to operate with one or two taps. The app uses native watchOS navigation,
controls, materials, typography, haptics, and SF Symbols. It avoids scrolling
when the complete content fits while retaining vertical Crown scrolling for
long or unbounded content.

The redesign preserves the current Relay Cloud protocol, encryption, pairing
identity, Codex actions, workspace boundaries, offline mutation blocking, and
voice lifecycle.

## Platform rules

- Use `NavigationStack`, `NavigationLink`, `List`, `Section`, `Picker`,
  `TextField`, `Button`, `Toggle`, `ProgressView`, `confirmationDialog`,
  `ViewThatFits`, and system materials before custom controls.
- Use SF Symbols by name. Do not add an external icon library.
- Use the approved monochrome UFO only for Relay identity. System blue marks
  primary actions and selection. Orange marks attention. Red marks destructive
  actions.
- Extend content toward the screen edges and keep padding small. Place no more
  than two text buttons or three glyph buttons in one row.
- Keep each common interaction under one minute and the navigation hierarchy
  shallow.
- Let the Digital Crown scroll lists, timelines, and long adaptive content.
  Do not create custom scrolling gestures.

These rules follow Apple's current
[watchOS design](https://developer.apple.com/design/human-interface-guidelines/designing-for-watchos/),
[layout](https://developer.apple.com/design/human-interface-guidelines/layout),
and [scroll-view](https://developer.apple.com/design/human-interface-guidelines/scroll-views)
guidance.

## Navigation architecture

Replace the manual root-level screen switch and custom Back buttons with one
native `NavigationStack`. A typed, `Hashable` Watch route identifies approval,
question, task, activity, instruction, new-task, voice, history, settings, and
about destinations. Model events may select an entity and push the matching
route, but views do not assign arbitrary screen states.

Pairing, revoked, incompatible, live, and offline remain top-level connection
states. Pairing owns its short progression. Live and offline states enter the
same navigation stack so cached content stays reviewable while mutations remain
disabled.

## Home states

### Pending queue

The home screen is action-first. When approvals or questions are pending, show
up to two compact rows under **Needs you**. Each row includes an SF Symbol,
literal title, short context, and a navigation affordance. The screen never
approves, denies, or answers inline.

The bottom dock contains two fixed text controls: **Tasks** and **More**. When
more than two items wait, show the remaining count without adding rows. Keep the
bridge-provided order and preserve the existing approval and question data.

### All clear

When nothing needs attention, replace the queue with a Material 2×2 grid:

1. Tasks
2. New task
3. Voice
4. More

Each tile is a native `Button` with one SF Symbol, one short label, a restrained
system material, and a VoiceOver label. The grid fits without scrolling on the
40 mm Apple Watch SE display at the default text size.

### Offline

Show a concise **Mac offline · cached data** status at the top. Keep cached
approvals, questions, and tasks readable. Disable every mutation and never queue
work for reconnect. **Try again** performs a refresh. Color does not carry the
state alone.

## Approval review

Use an adaptive review screen. The first layout is a non-scrolling vertical
stack containing:

- approval kind and risk;
- exact command, file operation, or permission;
- workspace or target when supplied;
- literal consequence or risk reasons;
- Deny and Approve controls.

`ViewThatFits(in: .vertical)` selects a vertically scrolling version when the
exact content or Dynamic Type size does not fit. Never truncate a command,
target, reason, or consequence to avoid scrolling.

Normal approval keeps its confirmation dialog. Dangerous approval uses orange
attention treatment, a warning haptic when enabled, and the existing explicit
dangerous confirmation. Deny and Stop remain destructive actions.

## Questions

Show one question at a time. Each screen contains the progress label, exact
question, bridge-supplied options, selection indicator, and **Next question** or
**Send answer**. Relay stores selections while the user advances. The final
action remains disabled until every question has one valid answer.

Use the adaptive non-scrolling/scrolling container for long questions,
descriptions, large text, or more options. Do not use answer tiles because long
labels and descriptions need full-width rows.

## Tasks

### Task browser

Use a compact native `List`. Each row shows title, state, short time context,
and a state-specific SF Symbol. The list does not move when all rows fit and
uses normal Crown scrolling when more tasks exist.

### Active task summary

The default task destination is a non-scrolling glance summary with:

- running, idle, error, or offline state;
- task title and workspace display name;
- latest activity title and status;
- **Instruct** and **Stop** controls;
- **View full activity**.

Stop appears only for an active turn and keeps the destructive confirmation.
The complete workspace path remains available to VoiceOver or the detail view
without crowding the summary.

### Full activity

Use a separate native `List` for the unbounded activity timeline. Show title,
optional detail, and status for every real activity item. Crown scrolling is
expected on this screen.

## Instruction and new task

### Instruction

Show the selected task, a native text field, and one explicit **Send** action.
The system text-input sheet supplies dictation and Scribble. Relay sends only
the reviewed text. Empty or stale submissions stay disabled.

### New task

Split task creation into three native steps:

1. choose an allowed workspace;
2. choose a model and supported effort;
3. enter the prompt and review the complete selection.

Each step fits on one screen at normal sizes and uses the adaptive fallback for
large text. The final action says **Start reviewed task** and remains disabled
until every value passes the existing model validation.

## Voice

The voice flow uses focused, non-scrolling states:

1. select or confirm the destination;
2. idle with one record control;
3. recording with elapsed time, Stop & Transcribe, and Erase;
4. transcribing progress;
5. editable transcript review;
6. sending progress.

The transcript review uses adaptive scrolling for long text. Keep the existing
30-second limit, temporary-file cleanup, connection-loss handling, and rule
that only reviewed transcript text reaches Codex. Erase stays destructive.

## More, history, and settings

**More** uses the same Material 2×2 grid:

1. Voice
2. Refresh
3. History
4. Settings

History remains a native, scrollable list limited to the running Watch session.
It shows action type and succeeded, failed, or pending state without secret
content.

Settings contains Watch-local controls only:

- Haptics toggle, stored with `@AppStorage` and applied to Relay's success,
  failure, and warning feedback;
- Watch identity details;
- About Relay with installed version;
- confirmed **Forget this Watch** credential erasure.

## Pairing and problem states

Pairing code entry uses the monochrome UFO, **Pair with Mac**, one instruction,
the six-character field, and **Find Mac**. It does not scroll at normal text
sizes.

Fingerprint verification shows the exact Mac and Watch fingerprints in
monospaced text. It uses the adaptive fallback and keeps confirmation disabled
until the existing pairing state permits it. Waiting, denied, expired,
incompatible, revoked, and reconnecting states use native progress or
content-unavailable treatments with one recovery action.

## Reusable SwiftUI boundaries

Keep the implementation split into focused units:

- typed navigation and route mapping;
- home-state composition;
- adaptive fixed/scrolling container;
- connection and error status;
- Material action tile and two-control dock;
- risk presentation and confirmation boundaries;
- task status and activity rows;
- new-task step state;
- haptic preference.

Views render model state and send typed user intent. They do not call transport
objects, duplicate validation, or retain secrets. Pure presentation decisions
belong in testable helpers.

## Accessibility and display support

- The 40 mm Apple Watch SE 2 is the primary no-scroll acceptance display.
- Also verify 44 mm and 46 mm displays.
- Support Dynamic Type. Adaptive screens scroll before text clips or shrinks.
- Give every icon-only control a literal VoiceOver label and hint.
- Keep native tap targets and focus order.
- Pair every state color with a symbol and text.
- Honor Reduce Motion. Use only system navigation and progress animation.
- Let users disable Relay haptics without affecting system haptics.

## Security and behavior invariants

The redesign must not change these rules:

- Relay Cloud carries opaque end-to-end encrypted envelopes.
- Pairing requires code exchange and fingerprint confirmation on both devices.
- Cached offline content is review-only.
- Mutations require a fresh live connection and never queue for later.
- Dangerous approvals require the exact existing confirmation value.
- Workspace, model, effort, question-option, replay, and idempotency validation
  remain authoritative outside the view layer.
- Revocation and local forgetting erase Watch credentials and cached data.
- Voice sends reviewed transcript text, not the temporary audio file, to Codex.

## Verification contract

- Add pure tests for route mapping, home composition, pending limits, question
  progression, new-task steps, adaptive layout decisions, and haptic preference.
- Keep all existing Watch transport, pairing, mutation, stale-data, and voice
  tests passing.
- Run the Watch Swift package suite and `scripts/check-watchos-source.sh`.
- Build the Xcode project unsigned for a generic watchOS destination.
- Build and inspect 40 mm, 44 mm, and 46 mm simulator destinations where the
  installed Xcode runtime provides them.
- Capture the main states at default and largest practical Dynamic Type.
- Check VoiceOver order, labels, destructive confirmations, offline blocking,
  and no-scroll acceptance on the 40 mm display.
- Preserve the user's local Xcode scheme and workspace changes.

Physical Apple Watch, signing, TestFlight, App Store, cellular, sleep/wake, and
battery evidence remain separate release gates.

## Scope boundary

This work redesigns and restructures the Apple Watch client. It does not add an
iPhone app, complication, Smart Stack widget, notification action, Codex
plugin, new Relay Cloud endpoint, or new Codex capability.
