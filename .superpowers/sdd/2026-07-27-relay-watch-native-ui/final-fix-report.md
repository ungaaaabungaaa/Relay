# Relay Watch native UI final fix report

Date: 2026-07-28
Branch: `codex/watch-native-ui`
Starting commit: `e45918f`
Push: not performed

## Result

This fix wave addresses all seven final-review findings. It changes Watch UI
presentation and pure Watch presentation helpers. It does not change Relay
Cloud envelopes, pairing credentials, bridge authorization, replay handling,
idempotency, offline mutation guards, voice limits, or the Xcode scheme and
workspace.

## Finding 1: explicit instruction route authority

Root cause: `RelayTaskPresentation.instructionTask` returned an explicit route
task when present, but a stale non-nil route ID fell through to selected-task
and running-task fallback.

RED:

```text
explicitInstructionRouteRejectsAStaleTaskWithoutRunningFallback
Expectation failed: target was RelayTask(id: "running", ...), expected nil
```

GREEN:

```text
explicitInstructionRouteRejectsAStaleTaskWithoutRunningFallback passed
```

The resolver now returns the match result for every non-nil route ID. A stale
explicit ID returns nil. The instruction view sees no task and keeps Send
disabled. Selection and running-task fallback remain available for a nil route
ID.

## Finding 2: compact and adaptive fixed surfaces

Root cause: each Material tile imposed a 64-point minimum and then added 16
points of padding. Two grid rows consumed at least 168 points before headings.
More rendered a fixed grid, and pairing stacked its content without a fallback.

RED:

```text
compactMaterialGridKeepsTwoRowsBelowOneHundredPoints
error: cannot find RelayCompactLayout in scope

Task 5 connects Watch utility flows and haptics
Assertion failed: RelayMoreViews.swift did not contain RelayAdaptiveContainer
```

GREEN:

```text
compactMaterialGridKeepsTwoRowsBelowOneHundredPoints passed
Task 5 connects Watch utility flows and haptics passed
```

The tile now uses caption and caption2 text, one point of internal spacing, no
outer content padding, and a 44-point minimum tap height. The pure layout
contract computes a two-row grid minimum of 92 points, including the four-point
row gap. All Clear drops its extra explanatory line. More and pairing code entry
now use `RelayAdaptiveContainer`, so content scrolls when text or the available
height exceeds the compact form. Pairing combines the Relay mark and title in
one row, uses six-point spacing, and shows a short Watch identity label. The
full Watch fingerprint remains in its VoiceOver label and on the exact
fingerprint comparison screen.

## Finding 3: task row and summary context

Root cause: task rows rendered text without a state symbol or time context.
The task summary omitted latest-activity status and kept no full-path
accessibility value.

RED:

```text
error: RelayTaskSummary has no member latestActivityStatus
error: RelayTaskSummary has no member workspaceAccessibilityLabel
error: RelayTaskPresentation has no member row
```

GREEN:

```text
taskRowsUseStateSpecificSymbolsAndShortTimeContext passed
activeTaskSummaryUsesOnlyTheLatestActivity passed
cachedTaskSummaryRemainsReviewableWithoutDetail passed
```

Rows now map idle, running, error, and offline to distinct SF Symbols and show a
short relative update value such as `Running · 2m ago`. The summary keeps the
workspace basename on screen, exposes `Workspace <full path>` to VoiceOver,
and renders the latest activity title and status.

## Finding 4: status strip text

Root cause: `RelayStatusStrip` replaced the connection title with `error` and
forced one line.

RED:

```text
error: cannot find RelayStatusPresentation in scope
```

GREEN:

```text
offlineStatusKeepsLiteralStateAndExposesTheFullErrorSeparately passed
```

`RelayStatusPresentation` now derives connection title, symbol, detail, and
tone. Offline and stale snapshots keep the literal
`Mac offline · cached data`. The strip renders the full error in a separate
multiline `Text` with vertical fixed sizing. It has no one-line limit.

## Finding 5: question action hint

Root cause: the same VoiceOver hint claimed to send an answer on both the local
advance action and final submission.

RED:

```text
error: RelayQuestionProgress has no member actionHint
```

GREEN:

```text
questionActionHintDistinguishesLocalAdvanceFromFinalSubmission passed
```

Intermediate steps now say `Advances locally without sending an answer`. The
final action keeps `Sends only the selected Mac-provided answers to Codex`.

## Finding 6: new-task validation and copy

Root cause: workspace-step gating accepted every non-empty path. The view used
`Start task` instead of the approved final label.

RED:

```text
error: extra argument folders in call
error: cannot find RelayNewTaskPresentation in scope
```

GREEN:

```text
newTaskFlowAdvancesOnlyWithValidStepData passed
newTaskDraftRejectsWorkspaceRemovedFromCurrentAllowedFolders passed
newTaskDraftUsesAdvertisedDefaultModelAndEffort passed
newTaskRequiresAdvertisedFolderModelEffortAndPrompt passed
```

Draft workspace gating now requires an exact path match in the current
bridge-advertised folder list. The existing feature layer still validates the
folder, model, effort, and prompt before mutation. Default selection still
chooses the advertised default model, its default effort, and the first allowed
folder. The final label is `Start reviewed task`.

## Finding 7: contract coverage

The contract suite now covers:

- stale explicit instruction routes with selected and running fallback candidates;
- current allowed-folder membership and bridge default model/effort selection;
- four task-state symbols, relative time context, latest activity status, and
  the full workspace accessibility label;
- the 44-point tile floor and 92-point two-row grid minimum;
- adaptive More and pairing wiring;
- offline status title/error separation and multiline status wiring;
- progress-dependent question hints and the final new-task label.

The tests exercise pure presentation behavior where the package can compile it.
Source contracts connect excluded SwiftUI views to those helpers and the
adaptive containers.

## Verification

### Watch

```text
Focused RelayWatchContractTests: 30 passed, 0 failed
Full apple-watch Swift package: 69 passed, 0 failed
Watch project contract: 17 passed, 0 failed
check-watchos-source.sh: passed for arm64_32 and arm64 on watchOS 10+
Unsigned generic watchOS Xcode build: BUILD SUCCEEDED
```

Commands:

```sh
CLANG_MODULE_CACHE_PATH=/private/tmp/relay-watch-final-clang \
SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/relay-watch-final-swiftpm \
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcrun swift test --disable-sandbox \
  --scratch-path /private/tmp/relay-watch-final-build \
  --package-path apple-watch --filter RelayWatchContractTests

CLANG_MODULE_CACHE_PATH=/private/tmp/relay-watch-final-verification-clang \
SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/relay-watch-final-verification-swiftpm \
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcrun swift test --disable-sandbox \
  --scratch-path /private/tmp/relay-watch-final-verification-build \
  --package-path apple-watch

RELAY_WATCH_MODULE_CACHE=/private/tmp/relay-watch-final-source-cache \
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
scripts/check-watchos-source.sh

node --test apple-watch/test/project.test.mjs

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -project apple-watch/RelayWatch.xcodeproj \
  -scheme RelayWatch -configuration Debug \
  -destination 'generic/platform=watchOS' \
  -derivedDataPath /private/tmp/relay-watch-final-generic-unsandboxed \
  CODE_SIGNING_ALLOWED=NO build
```

The sandboxed Xcode attempt failed in `actool` because CoreSimulatorService was
blocked. The same unsigned command passed outside the sandbox.

### Bridge, TypeScript, and Mac

```text
Bridge tests outside the loopback-restricted sandbox: 78 passed, 0 failed
TypeScript syntax and erasable-type check: passed
Mac Swift package: 59 passed, 0 failed
Mac Swift build: passed
git diff --check: passed
```

Commands:

```sh
node --test apps/bridge/test/*.test.ts
node scripts/check-types.mjs

CLANG_MODULE_CACHE_PATH=/private/tmp/relay-mac-final-clang \
SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/relay-mac-final-swiftpm \
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcrun swift test --disable-sandbox --package-path mac \
  --scratch-path ../../mac/.build

CLANG_MODULE_CACHE_PATH=/private/tmp/relay-mac-final-clang \
SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/relay-mac-final-swiftpm \
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcrun swift build --disable-sandbox --package-path mac \
  --scratch-path ../../mac/.build

git diff --check
```

The sandboxed bridge run passed 74 tests and failed four WebSocket cases with
`listen EPERM: operation not permitted 127.0.0.1`. The same command passed
78/78 outside the sandbox.

The worktree has a partial pnpm store without package links. These wrapper
commands attempted dependency repair and reached the unavailable registry:

```sh
NODE_PATH=/Users/syedabdulmuqeeth/Developer/SandBox/codewatch/node_modules/.pnpm/node_modules \
  pnpm --filter @relay/bridge test
pnpm typecheck
```

Both emitted `ERR_PNPM_META_FETCH_FAIL` or `ENOTFOUND`. I stopped their pnpm
processes and did not retry or install packages. The direct Node commands above
used the existing parent checkout dependencies and passed.

## Remaining validation gates

- A physical Apple Watch or an installed simulator must confirm 40 mm, 44 mm,
  and 46 mm rendering, Crown behavior, Dynamic Type, and VoiceOver order.
- Signing, TestFlight, App Store, cellular, sleep/wake, and battery checks remain
  outside this code-level fix wave.

The source and geometry checks support the compact-layout claim. They do not
constitute device interaction evidence.
