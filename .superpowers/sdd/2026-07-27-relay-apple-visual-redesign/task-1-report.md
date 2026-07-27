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
