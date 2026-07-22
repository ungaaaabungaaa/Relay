# Physical Watch Development Setup

This guide uses the Galaxy Watch6 itself for development. Do not create an Android Virtual Device and do not download Wear OS emulator system images.

## 1. Mac prerequisites

Current machine inventory on 2026-07-22:

- macOS 26.5.2
- Node.js 24.18.0: installed
- pnpm 11.13.0: installed
- Codex CLI 0.144.5: installed
- Android Studio: not installed
- Android platform tools (`adb`): not installed
- Tailscale CLI: not installed

### Install Android Studio without an emulator

- [ ] Download the current stable Android Studio for Apple silicon from the Android developer website.
- [ ] Drag Android Studio into `/Applications` and open it.
- [ ] In the Setup Wizard, choose **Custom** if it offers to install emulator images.
- [ ] Install the Android SDK, SDK Platform Tools, and the SDK platform selected by the project.
- [ ] Do **not** install an Android Emulator, Wear OS system image, or create an AVD.
- [ ] In Android Studio, open **Settings → Languages & Frameworks → Android SDK → SDK Tools** and confirm **Android SDK Platform-Tools** is installed.
- [ ] Use Android Studio's bundled JDK for Gradle. No separate Java installation is required.

After installation, verify from Android Studio's Terminal:

```bash
adb version
```

### Install Tailscale on the Mac

- [ ] Install an official macOS Tailscale variant that provides the CLI and supports Funnel.
- [ ] Sign in and connect the Mac to your tailnet.
- [ ] Confirm `tailscale status` works.
- [ ] Enable MagicDNS and HTTPS when prompted by the Funnel command.
- [ ] Do not enable Funnel until the bridge authentication tests pass.

Tailscale Funnel is public internet ingress. It is acceptable here only because the bridge listens on localhost and independently authenticates every watch request.

## 2. Prepare the Galaxy Watch6

- [ ] Connect the watch and Mac to the same Wi-Fi for development deployment.
- [ ] On the watch, open **Settings → About watch → Software information**.
- [ ] Tap **Software version** five times to enable Developer options.
- [ ] Open **Settings → Developer options**.
- [ ] Enable **ADB debugging**.
- [ ] Enable **Wireless debugging**.
- [ ] Enable **Turn off automatic Wi-Fi** while actively developing, if shown.
- [ ] Open **Wireless debugging → Pair new device** and note the pairing IP, pairing port, and pairing code.

The watch exposes separate pairing and connection ports. They can change when wireless debugging restarts.

From Android Studio's Terminal:

```bash
adb pair WATCH_IP:PAIRING_PORT
adb connect WATCH_IP:CONNECTION_PORT
adb devices
```

Enter the watch pairing code when requested. `adb devices` should list one connected device.

## 3. Open and deploy Relay

These steps become active after the Wear OS module is implemented:

- [ ] Open the repository root in Android Studio.
- [ ] Allow Gradle to sync using Android Studio's bundled JDK.
- [ ] Select the physical Galaxy Watch6 as the run target.
- [ ] Run the `wear` configuration.
- [ ] Accept the install/debug prompt on the watch if shown.
- [ ] Confirm the pairing screen renders without clipped controls.

Command-line deployment will also be available:

```bash
./gradlew :wear:installDebug
adb shell am start -n dev.ungaaaabungaaa.relay/.MainActivity
```

## 4. Configure the Mac bridge

The bridge will use environment variables loaded by its launch agent. Never commit their values.

```text
OPENAI_API_KEY=
CODEWATCH_BIND_HOST=127.0.0.1
CODEWATCH_PORT=43117
CODEWATCH_DATA_DIR=
CODEWATCH_FUNNEL_ORIGIN=
```

- [ ] Create the bridge data directory with Mac-user-only permissions.
- [ ] Add `OPENAI_API_KEY` to the macOS Keychain-backed bridge configuration.
- [ ] Start the Codex app and confirm the target tasks are visible.
- [ ] Start the bridge on `127.0.0.1:43117`.
- [ ] Run the local bridge health check.
- [ ] Generate a short-lived watch pairing code.
- [ ] Enter it on the watch and confirm the paired device appears locally.

## 5. Enable remote Wi-Fi access

Only do this after local pairing, authorization, replay protection, and rate-limit tests pass.

```bash
tailscale funnel --bg 43117
tailscale funnel status
```

- [ ] Record the generated `https://…ts.net` origin in the watch configuration during pairing.
- [ ] Turn off ADB debugging after installation if active debugging is not needed.
- [ ] Put the watch on a different Wi-Fi network and confirm it reconnects.
- [ ] Confirm an unpaired HTTP client receives no task metadata.
- [ ] Confirm the Mac bridge becomes unavailable when the Mac sleeps.

To disable public ingress:

```bash
tailscale funnel 43117 off
```

## 6. Daily use requirements

- The watch must have working Wi-Fi.
- The Mac must be powered on, awake, online, signed into Tailscale, and running both Codex and the bridge.
- The OpenAI API key and account must have access to speech transcription.
- A sleeping or offline Mac is shown as offline; Relay does not silently queue approvals.

## Disk-space policy

- No emulator or virtual device.
- No Wear OS system images.
- Build only the physical-watch debug APK during development.
- Periodically remove local Gradle build outputs with the repository cleanup task once it exists.
- Keep Gradle caches shared rather than vendoring dependencies into the repository.

