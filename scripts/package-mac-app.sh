#!/bin/zsh

set -euo pipefail

repository_root=${0:A:h:h}
relay_version=${RELAY_VERSION:?Set RELAY_VERSION to a semantic version such as 1.0.0}
sign_identity=${RELAY_SIGN_IDENTITY:--}
release_public_key=${RELAY_RELEASE_PUBLIC_KEY_BASE64:-}
output_directory=${RELAY_OUTPUT_DIR:-"${repository_root}/release/out"}
apk_path=${RELAY_APK_PATH:-"${repository_root}/wear/build/outputs/apk/release/wear-release.apk"}
swift_scratch=${RELAY_SWIFT_SCRATCH:-"${repository_root}/.build-release"}
application_path="${output_directory}/Relay.app"
contents_path="${application_path}/Contents"
macos_path="${contents_path}/MacOS"
resources_path="${contents_path}/Resources"
disk_image_path="${output_directory}/Relay.dmg"
volume_root="${output_directory}/dmg-root"

if [[ $(uname -m) != arm64 ]]; then
  print -u2 "Relay releases must be packaged on Apple silicon."
  exit 1
fi

if [[ "${sign_identity}" != "-" && -z "${release_public_key}" ]]; then
  print -u2 "RELAY_RELEASE_PUBLIC_KEY_BASE64 is required for a signed release."
  exit 1
fi

for required_file in \
  "${repository_root}/dist/relay-bridge-arm64" \
  "${apk_path}" \
  "${repository_root}/LICENSE" \
  "${repository_root}/NOTICE" \
  "${repository_root}/THIRD_PARTY_NOTICES.md"
do
  if [[ ! -f "${required_file}" ]]; then
    print -u2 "Missing release input: ${required_file}"
    exit 1
  fi
done

rm -rf "${application_path}" "${volume_root}" "${disk_image_path}"
mkdir -p "${macos_path}" "${resources_path}" "${volume_root}"

swift build \
  --disable-sandbox \
  --package-path "${repository_root}/mac" \
  --scratch-path "${swift_scratch}" \
  --configuration release \
  --arch arm64
swift_binary_path=$(swift build \
  --disable-sandbox \
  --package-path "${repository_root}/mac" \
  --scratch-path "${swift_scratch}" \
  --configuration release \
  --arch arm64 \
  --show-bin-path)

cp "${swift_binary_path}/RelayMac" "${macos_path}/Relay"
cp "${repository_root}/dist/relay-bridge-arm64" "${resources_path}/relay-bridge-arm64"
cp "${apk_path}" "${resources_path}/relay-wear.apk"
cp "${repository_root}/LICENSE" "${resources_path}/LICENSE"
cp "${repository_root}/NOTICE" "${resources_path}/NOTICE"
cp "${repository_root}/THIRD_PARTY_NOTICES.md" "${resources_path}/THIRD_PARTY_NOTICES.md"
chmod 0755 "${macos_path}/Relay" "${resources_path}/relay-bridge-arm64"

/usr/libexec/PlistBuddy -c "Add :CFBundleDevelopmentRegion string en" "${contents_path}/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleExecutable string Relay" "${contents_path}/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string dev.ungaaaabungaaa.relay.mac" "${contents_path}/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleInfoDictionaryVersion string 6.0" "${contents_path}/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleName string Relay" "${contents_path}/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundlePackageType string APPL" "${contents_path}/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string ${relay_version}" "${contents_path}/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleVersion string ${relay_version}" "${contents_path}/Info.plist"
/usr/libexec/PlistBuddy -c "Add :LSMinimumSystemVersion string 14.0" "${contents_path}/Info.plist"
/usr/libexec/PlistBuddy -c "Add :LSUIElement bool true" "${contents_path}/Info.plist"
/usr/libexec/PlistBuddy -c "Add :NSMicrophoneUsageDescription string Relay records only while you hold the watch record control." "${contents_path}/Info.plist"
if [[ -n "${release_public_key}" ]]; then
  /usr/libexec/PlistBuddy -c "Add :RelayReleasePublicKey string ${release_public_key}" "${contents_path}/Info.plist"
fi

if [[ "${sign_identity}" == "-" ]]; then
  /usr/bin/codesign --force --sign - "${resources_path}/relay-bridge-arm64"
  /usr/bin/codesign --force --deep --sign - "${application_path}"
else
  /usr/bin/codesign \
    --force \
    --options runtime \
    --timestamp \
    --sign "${sign_identity}" \
    "${resources_path}/relay-bridge-arm64"
  /usr/bin/codesign \
    --force \
    --deep \
    --options runtime \
    --timestamp \
    --sign "${sign_identity}" \
    "${application_path}"
fi

/usr/bin/codesign --verify --deep --strict --verbose=2 "${application_path}"
for executable in "${macos_path}/Relay" "${resources_path}/relay-bridge-arm64"
do
  executable_description=$(/usr/bin/file "${executable}")
  if [[ "${executable_description}" != *arm64* || "${executable_description}" == *x86_64* ]]; then
    print -u2 "Release executable is not arm64-only: ${executable_description}"
    exit 1
  fi
done

cp -R "${application_path}" "${volume_root}/Relay.app"
ln -s /Applications "${volume_root}/Applications"
/usr/bin/hdiutil create \
  -volname Relay \
  -srcfolder "${volume_root}" \
  -ov \
  -format UDZO \
  "${disk_image_path}"

print "Packaged ${disk_image_path}"
