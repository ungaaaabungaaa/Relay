# Physical Galaxy Watch6 Test

Relay is developed against the real watch. No AVD or emulator image is needed.

## After a watch reset

Finish Samsung's initial setup before enabling developer options. A Bluetooth/Wi-Fi Galaxy Watch6 normally uses the Galaxy Wearable app on a compatible Android phone. Some Watch6 LTE variants expose a phone-free setup path; availability depends on model, region, and carrier.

## Pair wireless ADB

1. Connect the Mac and watch to the same Wi-Fi network.
2. On the watch, open **Settings → About watch → Software information**.
3. Tap **Software version** five times.
4. Open **Settings → Developer options**.
5. Enable **ADB debugging**, **Wireless debugging**, and **Turn off automatic Wi-Fi**.
6. Open **Wireless debugging → Pair new device**.
7. In Android Studio's Terminal, run:

```bash
adb pair WATCH_IP:PAIRING_PORT
adb connect WATCH_IP:CONNECTION_PORT
adb devices
```

The pairing and connection ports are different.

## Run Relay locally

From the repository root:

```bash
node apps/bridge/src/cli.ts serve
```

In a second terminal:

```bash
node apps/bridge/src/cli.ts pair
adb reverse tcp:43117 tcp:43117
./gradlew :wear:installDebug
adb shell am start -n dev.ungaaaabungaaa.relay/.MainActivity
```

Enter the six-character code on the watch. Keep the default bridge URL, `http://127.0.0.1:43117`; `adb reverse` securely carries that watch-local port to the Mac-local bridge.

## Run the physical UI navigation test

The instrumentation APK compiles without an emulator. After `adb devices` shows
the Galaxy Watch6 as connected, run:

```bash
./gradlew :wear:connectedDebugAndroidTest
```

`RelayNavigationTest` exercises Home → Action inbox → Approval detail and
verifies that the exact command and working directory remain visible. This gate
is pending until the reset Watch6 is paired over wireless ADB; do not replace it
with an emulator run.

## Acceptance pass

- Pairing succeeds once and the code cannot be reused.
- An unsigned request to `/v1/tasks` returns only `{"error":"unauthorized"}`.
- Inbox shows live approvals and questions.
- Approve and deny each resolve the matching Codex request once.
- Tasks reflect current Codex status.
- A text instruction reaches the selected task.
- Disconnecting Wi-Fi shows stale/offline state without queuing actions.
- Revoking the watch with `node apps/bridge/src/cli.ts revoke DEVICE_ID` blocks it immediately.

Turn off wireless debugging when development is finished.
