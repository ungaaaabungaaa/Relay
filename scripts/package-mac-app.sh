#!/bin/zsh

set -euo pipefail

repository_root=${0:A:h:h}
relay_version=${RELAY_VERSION:?Set RELAY_VERSION to a semantic version such as 1.0.0}
sign_identity=${RELAY_SIGN_IDENTITY:--}
release_public_key=${RELAY_RELEASE_PUBLIC_KEY_BASE64:-}
sparkle_public_key=${RELAY_SPARKLE_PUBLIC_KEY:-}
sparkle_stable_feed=${RELAY_SPARKLE_STABLE_FEED_URL:-}
sparkle_beta_feed=${RELAY_SPARKLE_BETA_FEED_URL:-}
output_directory=${RELAY_OUTPUT_DIR:-"${repository_root}/release/out"}
swift_scratch=${RELAY_SWIFT_SCRATCH:-"${repository_root}/.build-release"}
application_path="${output_directory}/Relay.app"
contents_path="${application_path}/Contents"
macos_path="${contents_path}/MacOS"
resources_path="${contents_path}/Resources"
frameworks_path="${contents_path}/Frameworks"
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
if [[ "${sign_identity}" != "-" && ( -z "${sparkle_public_key}" || -z "${sparkle_stable_feed}" || -z "${sparkle_beta_feed}" ) ]]; then
  print -u2 "Sparkle public key and both HTTPS feed URLs are required for a signed release."
  exit 1
fi

for required_file in \
  "${repository_root}/dist/relay-bridge-arm64" \
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
mkdir -p "${macos_path}" "${resources_path}" "${frameworks_path}" "${volume_root}"

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
cp -R "${swift_binary_path}/Sparkle.framework" "${frameworks_path}/Sparkle.framework"
/usr/bin/install_name_tool -add_rpath \
  "@executable_path/../Frameworks" \
  "${macos_path}/Relay"
cp "${repository_root}/dist/relay-bridge-arm64" "${resources_path}/relay-bridge-arm64"
cp "${repository_root}/LICENSE" "${resources_path}/LICENSE"
cp "${repository_root}/NOTICE" "${resources_path}/NOTICE"
cp "${repository_root}/THIRD_PARTY_NOTICES.md" "${resources_path}/THIRD_PARTY_NOTICES.md"
printf '{"version":"%s","apiVersion":1}\n' \
  "${relay_version}" \
  > "${resources_path}/relay-release.json"
chmod 0755 "${macos_path}/Relay" "${resources_path}/relay-bridge-arm64"

asset_catalog_path="${output_directory}/RelayAssets.xcassets"
app_icon_set_path="${asset_catalog_path}/AppIcon.appiconset"
rm -rf "${asset_catalog_path}"
cp -R "${repository_root}/mac/Resources/AppIconTemplate.xcassets" "${asset_catalog_path}"
for size in 16 32 128 256 512
do
  /usr/bin/sips \
    -z "${size}" "${size}" \
    "${repository_root}/mac/Resources/AppIconSource.png" \
    --out "${app_icon_set_path}/icon_${size}x${size}.png" >/dev/null
  retina_size=$((size * 2))
  /usr/bin/sips \
    -z "${retina_size}" "${retina_size}" \
    "${repository_root}/mac/Resources/AppIconSource.png" \
    --out "${app_icon_set_path}/icon_${size}x${size}@2x.png" >/dev/null
done
xcrun actool \
  --compile "${resources_path}" \
  --platform macosx \
  --minimum-deployment-target 14.0 \
  --app-icon AppIcon \
  --output-partial-info-plist "${output_directory}/asset-info.plist" \
  "${asset_catalog_path}" >/dev/null
test -f "${resources_path}/AppIcon.icns"
rm -rf "${asset_catalog_path}" "${output_directory}/asset-info.plist"

/usr/libexec/PlistBuddy -c "Add :CFBundleDevelopmentRegion string en" "${contents_path}/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleExecutable string Relay" "${contents_path}/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string com.relayforcodex.mac" "${contents_path}/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleInfoDictionaryVersion string 6.0" "${contents_path}/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "${contents_path}/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleName string Relay" "${contents_path}/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundlePackageType string APPL" "${contents_path}/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string ${relay_version}" "${contents_path}/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleVersion string ${relay_version}" "${contents_path}/Info.plist"
/usr/libexec/PlistBuddy -c "Add :LSMinimumSystemVersion string 14.0" "${contents_path}/Info.plist"
/usr/libexec/PlistBuddy -c "Add :LSUIElement bool false" "${contents_path}/Info.plist"
/usr/libexec/PlistBuddy -c "Add :NSMicrophoneUsageDescription string Relay records only while you hold the watch record control." "${contents_path}/Info.plist"
if [[ -n "${release_public_key}" ]]; then
  /usr/libexec/PlistBuddy -c "Add :RelayReleasePublicKey string ${release_public_key}" "${contents_path}/Info.plist"
fi
if [[ -n "${sparkle_public_key}" ]]; then
  selected_feed="${sparkle_stable_feed}"
  if [[ "${relay_version}" == *-beta.* ]]; then
    selected_feed="${sparkle_beta_feed}"
  fi
  /usr/libexec/PlistBuddy -c "Add :SUPublicEDKey string ${sparkle_public_key}" "${contents_path}/Info.plist"
  /usr/libexec/PlistBuddy -c "Add :SUFeedURL string ${selected_feed}" "${contents_path}/Info.plist"
  /usr/libexec/PlistBuddy -c "Add :SUEnableAutomaticChecks bool true" "${contents_path}/Info.plist"
  /usr/libexec/PlistBuddy -c "Add :SUAllowsAutomaticUpdates bool true" "${contents_path}/Info.plist"
fi

if [[ "${sign_identity}" == "-" ]]; then
  /usr/bin/codesign --force --sign - "${resources_path}/relay-bridge-arm64"
  /usr/bin/codesign \
    --force \
    --deep \
    --entitlements "${repository_root}/mac/Relay.entitlements" \
    --sign - \
    "${application_path}"
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
    --entitlements "${repository_root}/mac/Relay.entitlements" \
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
