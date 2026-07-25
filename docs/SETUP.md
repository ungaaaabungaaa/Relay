# Set up Relay

There are two paths below. Use the first one after a verified GitHub Release is
published. Use the developer path today.

## What you need

- an Apple silicon Mac: M1 or newer;
- macOS 14 or newer;
- Codex installed, signed in, and able to open a task;
- Tailscale on the Mac; its free plan is enough;
- a Wear OS 3+ watch;
- Wi-Fi shared by the Mac and watch for the one-time install.

A reset Bluetooth/Wi-Fi Galaxy Watch6 normally needs the Galaxy Wearable app on
a compatible Android phone to finish Samsung's initial setup. Relay itself
does not require the phone after that.

Do not install an Android emulator, create an Android Virtual Device, or
download a Wear OS system image.

## Easy install from GitHub Release

This route becomes available only after the repository publishes a notarized
release.

1. Open the repository's **Releases** page.
2. Download `Relay.dmg` and `SHA256SUMS`.
3. Verify the checksum:

   ```bash
   shasum -a 256 -c SHA256SUMS
   ```

4. Open `Relay.dmg` and drag Relay to Applications.
5. Open Relay. macOS should accept the Developer ID and notarization without a
   security override.
6. Open the Relay dashboard from the menu-bar icon.
7. Install Tailscale from its official Mac download. Relay opens Tailscale's
   browser sign-in and checks status for up to two minutes.
8. In **Setup**, choose **Install verified tools**. Relay downloads only the
   pinned official Android Platform Tools archive; it does not install Android
   Studio or an emulator.
9. On the watch, enable Developer Options and Wireless Debugging using the
   steps below.
10. In **Watches**, pair, connect, and install Relay.
11. Start secure pairing in the Mac app. Relay opens a temporary,
    security-checked Funnel endpoint for pairing. The watch discovers it over
    Bonjour.
12. Compare the Mac fingerprint, enter the six-character code, then compare
    the watch fingerprint before you approve it on the Mac. Relay closes the
    temporary pairing endpoint after approval, denial, or session expiry.
13. Add only the Mac workspace folders you want the watch to browse.
14. In **Remote Access**, run checks, then enable permanent access.
15. Test once with the watch on a different Wi-Fi network.
16. Turn Wireless Debugging off on the watch.

Remote Access is deliberately last. The bridge stays private until the local
security self-test passes.

## Prepare the physical watch

1. Open **Settings → About watch → Software information**.
2. Tap **Software version** five times.
3. Go back and open **Developer options**.
4. Enable **ADB debugging** and **Wireless debugging**.
5. If available, enable **Turn off automatic Wi-Fi** while installing.
6. Open **Wireless debugging → Pair new device**.
7. Keep the watch on this page while Relay searches.

The pairing port and connection port are different and may change whenever
Wireless Debugging restarts.

## Developer setup today

Current local development uses Android Studio only for its bundled Java and SDK.
No emulator is used.

### 1. Open the project

Open the repository root in Android Studio and allow Gradle to sync. Confirm
these SDK pieces in **Settings → Languages & Frameworks → Android SDK**:

- Android SDK Platform 36.1;
- Android SDK Build Tools 36.0.0;
- Android SDK Platform-Tools.

### 2. Build and run the Mac app

From the repository root:

```bash
corepack enable
pnpm install --frozen-lockfile
pnpm build:bridge-sea
export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
xcrun swift run --package-path mac RelayMac
```

Relay creates a random 32-byte admin token and stores it in macOS Keychain. The
app starts one local bridge process, checks Codex, and never prints the token.

### 3. Pair the watch over Wireless ADB

You can use the Relay Watches screen or Android Studio's Terminal:

```bash
export ANDROID_HOME="${ANDROID_HOME:-$HOME/Library/Android/sdk}"
ADB="$ANDROID_HOME/platform-tools/adb"
"$ADB" pair WATCH_IP:PAIRING_PORT
"$ADB" connect WATCH_IP:CONNECTION_PORT
"$ADB" devices
```

Enter the six-digit Wireless ADB code. `"$ADB" devices` must list exactly the
watch you intend to use.

### 4. Install the debug APK

```bash
export JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"
export ANDROID_HOME="${ANDROID_HOME:-$HOME/Library/Android/sdk}"
ADB="$ANDROID_HOME/platform-tools/adb"
./gradlew :wear:installDebug
"$ADB" shell am start -n dev.ungaaaabungaaa.relay/.MainActivity
```

For the safe local development loop, keep the bridge on localhost and forward
the watch-local port through ADB:

```bash
"$ADB" reverse tcp:43117 tcp:43117
```

The watch can then use `http://127.0.0.1:43117` without exposing the bridge.
The release APK disables cleartext networking and uses the HTTPS Funnel origin.

### 5. Manual bridge fallback

Normally the Mac app manages the bridge. For bridge-only development:

```bash
export CODEWATCH_ADMIN_TOKEN="$(openssl rand -base64 32)"
export CODEWATCH_BIND_HOST=127.0.0.1
export CODEWATCH_ADMIN_HOST=127.0.0.1
node apps/bridge/src/cli.ts serve
```

Use the Mac app for release-style pairing. The old unrestricted `/v1/pair`
route remains available for debug migration and will be removed after both
watch clients use session pairing. Do not paste the admin token into source,
`.env` files, issues, or logs.

## Optional reviewed voice

The watch's built-in keyboard/dictation works without an OpenAI key. For
hold-to-record transcription:

1. Open **Voice** in the Mac dashboard.
2. Paste the OpenAI key there.
3. Relay stores it in Keychain.
4. Test one recording and verify the transcript before sending.

Audio is temporary, is deleted after transcription or failure, and is never
sent to Codex automatically.

## Turn on remote access

Install and sign in to the official Tailscale Mac app. Relay runs:

```bash
tailscale status --json
TAILSCALE_BE_CLI=1 tailscale funnel --bg http://127.0.0.1:43117
tailscale funnel status --json
```

Funnel is public internet ingress, but it forwards only to the localhost
bridge. Relay still requires the watch's device signature on every private
request.

Emergency Stop disables Funnel and closes watch access while leaving Codex
tasks running. It does not silently revoke the watch; revocation is a separate
deliberate action.

## Daily use

- Keep the Mac awake, online, and running Relay and Codex.
- Keep Tailscale connected for remote networks.
- Start Live Monitoring only when you want visible real-time background
  updates; it ends after four hours or on low battery.
- If the Mac is offline, cached watch data is marked stale and controls are
  disabled. Relay does not queue actions to run later.
