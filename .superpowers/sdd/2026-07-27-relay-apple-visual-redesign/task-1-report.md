# Task 1 report: brand contract and reusable glyphs

## Changed files

- `apple-watch/test/project.test.mjs`: added Task 1 source-contract coverage and explicit Task 3/4 pending wiring checks.
- `mac/Sources/RelayMac/RelayBrand.swift`: added template-safe `RelayUFOGlyph` and larger `RelayBrandMark`.
- `apple-watch/RelayWatch/RelayWatchStyle.swift`: added `RelayWatchStyle` semantic tokens and `RelayWatchMark`.
- `mac/Sources/RelayMac/Components.swift`: changed the accent to `Color.accentColor`, replaced custom warning/destructive RGB values with semantic system colors, and moved panels to thin material.

## RED evidence

`node --test apple-watch/test/project.test.mjs` failed as intended before implementation because `mac/Sources/RelayMac/RelayBrand.swift` did not exist. The Task 1 contract test was the sole failure.

## GREEN evidence

- `node --test apple-watch/test/project.test.mjs`: 8 passed, 0 failed, 3 explicitly skipped for Tasks 3 and 4.
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift test --package-path mac --scratch-path /private/tmp/relay-mac-task1-tests`: 48 tests passed.
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swiftc -typecheck -target arm64-apple-watchos10.0 -sdk "$(DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun --sdk watchos --show-sdk-path)" apple-watch/RelayWatch/RelayWatchStyle.swift`: passed.
- `git diff --check -- <Task 1 files>`: passed.

## Commit

Implementation: `f522e06eb11fdd5dde993c87f9b7fd86ce73b28c` (`feat: add Relay UFO brand primitives`).

## Self-review

The primitives use only simple SwiftUI geometry and semantic foreground/background styles. No state, pairing, encryption, cloud, or Codex behavior changed. Later-task tests are intentionally skipped rather than made falsely green.

## Concerns

`RelayWatchStyle.swift` is not yet consumed by the Watch root or listed in the Xcode project source phase; Task 4 owns the root wiring and should add target membership when it consumes the file. The pre-existing user Xcode scheme/workspace and plan/spec documents remain unstaged.

## Fix round 1: Watch system-blue token

The original Watch token used `Color.accentColor`, which resolves to the existing green Watch AccentColor asset (`red 0.384`, `green 0.906`, `blue 0.565`). The token now uses `Color.blue` directly, so it is not coupled to that asset. The asset was intentionally not changed because no Task 1 code consumes it.

### RED evidence

`node --test apple-watch/test/project.test.mjs` failed as intended after the source contract changed to require `static let accent = Color.blue` and reject `Color.accentColor`. The sole failure named the existing `static let accent = Color.accentColor` line.

### GREEN evidence

- `node --test apple-watch/test/project.test.mjs`: 8 passed, 0 failed, 3 explicitly skipped for Tasks 3 and 4.
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swiftc -typecheck -target arm64-apple-watchos10.0 -sdk <watchOS SDK> apple-watch/RelayWatch/RelayWatchStyle.swift`: passed.

### Fix commit

Implementation: `e17a2461aad7fb0ae4fd03ac331493d2c2e7496f` (`fix: use system blue for Watch accent`).
