# Physical Galaxy Watch6 release test

Relay uses a real watch for development and acceptance. Do not replace this
gate with an emulator run.

## Prepare a reset Watch6

A Bluetooth/Wi-Fi Galaxy Watch6 normally needs a compatible Android phone and
the Galaxy Wearable app to finish Samsung's initial setup. Availability of a
phone-free flow varies by LTE model, region, and carrier.

After setup:

1. Connect the Mac and watch to the same Wi-Fi.
2. On the watch, open **Settings → About watch → Software information**.
3. Tap **Software version** five times.
4. Open **Developer options**.
5. Enable **ADB debugging** and **Wireless debugging**.
6. Open **Wireless debugging → Pair new device**.

## Pair and install

This ADB path is for developer installation only. Beta acceptance must also use
the Google Play closed-test listing.

```bash
export JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"
export ANDROID_HOME="${ANDROID_HOME:-$HOME/Library/Android/sdk}"
ADB="$ANDROID_HOME/platform-tools/adb"
"$ADB" pair WATCH_IP:PAIRING_PORT
"$ADB" connect WATCH_IP:CONNECTION_PORT
"$ADB" devices
./gradlew :wear:installDebug
"$ADB" shell am start -n com.relayforcodex.wear/dev.ungaaaabungaaa.relay.MainActivity
```

The pairing and connection ports are different. Confirm `"$ADB" devices` lists
the expected watch before installing.

For local development only:

```bash
"$ADB" reverse tcp:43117 tcp:43117
```

After installation, create the five-minute Relay code in the Mac app, enter it
on the watch, compare the Mac identity, and confirm the watch appears in the
Mac Watches screen.

## Automated physical navigation

The instrumentation APK can be compiled without a device. Run it only after
the Watch6 appears in `"$ADB" devices`:

```bash
./gradlew :wear:connectedDebugAndroidTest
```

The test covers Home → Action inbox → Approval detail and verifies that the
exact command and working directory remain visible.

## Required physical matrix

Record the result and evidence without storing task text, commands, device
keys, pairing codes, account names, or cloud credentials.

| Test | Result | Evidence |
| --- | --- | --- |
| Fresh Play install and Play update preserving pairing | Pending | |
| Round safe areas, rotary input, default and large text | Pending | |
| Wi-Fi and LTE when available | Pending | |
| Foreground WebSocket events | Pending | |
| Visible Live Monitoring and periodic refresh | Pending | |
| Wi-Fi switching, Mac sleep, and bridge restart recovery | Pending | |
| Approve, deny, question, instruction, both voice modes, stop, new task | Pending | |
| Lost-watch revocation and cached-data removal | Pending | |
| One-hour normal and Live Monitoring battery observation | Pending | |
| Accessibility labels and haptic behavior | Pending | |

## Release acceptance

Version 1 remains blocked until all ten criteria pass:

1. A clean Apple silicon Mac installs the notarized DMG without a development
   toolchain.
2. The first-run wizard reaches healthy using only its plain-language steps.
3. A reset Galaxy Watch6 installs from the Play test track and pairs with the
   Mac's six-character cloud code.
4. The watch discovers an existing Codex task through Relay Cloud on Wi-Fi and
   LTE.
5. One normal and one dangerous approval use the correct confirmation policy.
6. Questions, instructions, both voice modes, steering, stopping, and new-task
   creation work end to end.
7. Workspace escape, replay, revocation, and unauthenticated metadata tests
   fail safely.
8. Live Monitoring state and battery cost are visible and documented.
9. Sparkle and Play updates preserve the previous app and watch pairing.
10. Tag, source, checksums, DMG, APK, license, notes, and compatibility data
    all agree.

Also confirm:

- an unsigned `/v1/tasks` request receives only
  `{"error":"unauthorized"}`;
- duplicate taps return the first result without repeating the Codex action;
- stale/offline state disables every mutation;
- audio is deleted after transcription failure as well as success;
- Emergency Stop disables remote access and leaves Codex tasks running.

Turn Wireless Debugging off after the run. Add other Wear OS 3+ devices to
`docs/COMPATIBILITY.md` only after a documented physical result.
