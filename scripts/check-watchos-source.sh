#!/bin/zsh

set -euo pipefail

relay_root=${0:A:h:h}
module_cache=${RELAY_WATCH_MODULE_CACHE:-${TMPDIR:-/tmp}/relay-watch-module-cache}

if ! watch_sdk=$(xcrun --sdk watchos --show-sdk-path 2>/dev/null); then
  bundled_xcode=/Applications/Xcode.app/Contents/Developer
  if [[ ! -d "${bundled_xcode}/Platforms/WatchOS.platform" ]]; then
    echo "A full Xcode installation with the watchOS SDK is required." >&2
    exit 1
  fi
  export DEVELOPER_DIR="${bundled_xcode}"
  watch_sdk=$(xcrun --sdk watchos --show-sdk-path)
fi

mkdir -p "${module_cache}"

source_files=(
  "${relay_root}/apple-watch/RelayWatch/RelayAPIClient.swift"
  "${relay_root}/apple-watch/RelayWatch/RelayApprovalView.swift"
  "${relay_root}/apple-watch/RelayWatch/RelayAudioRecorder.swift"
  "${relay_root}/apple-watch/RelayWatch/RelayComposeViews.swift"
  "${relay_root}/apple-watch/RelayWatch/RelayEndpoint.swift"
  "${relay_root}/apple-watch/RelayWatch/RelayEnvironment.swift"
  "${relay_root}/apple-watch/RelayWatch/RelayInboxViews.swift"
  "${relay_root}/apple-watch/RelayWatch/RelayWatchComponents.swift"
  "${relay_root}/apple-watch/RelayWatch/RelayWatchNavigation.swift"
  "${relay_root}/apple-watch/RelayWatch/RelayProtocol.swift"
  "${relay_root}/apple-watch/RelayWatch/RelayPairingState.swift"
  "${relay_root}/apple-watch/RelayWatch/RelayQuestionView.swift"
  "${relay_root}/apple-watch/RelayWatch/RelayReconnectPolicy.swift"
  "${relay_root}/apple-watch/RelayWatch/RelaySocket.swift"
  "${relay_root}/apple-watch/RelayWatch/RelayTaskViews.swift"
  "${relay_root}/apple-watch/RelayWatch/RelayWatchApp.swift"
  "${relay_root}/apple-watch/RelayWatch/RelayWatchModel.swift"
  "${relay_root}/apple-watch/RelayWatch/RelayWatchRootView.swift"
  "${relay_root}/apple-watch/RelayWatch/RelayWatchStyle.swift"
  "${relay_root}/apple-watch/RelayWatch/RelayWatchFeature.swift"
  "${relay_root}/apple-watch/RelayWatch/RelayWatchService.swift"
  "${relay_root}/apple-watch/RelayWatch/RelayWatchTypes.swift"
  "${relay_root}/apple-watch/RelayWatch/RelayVoiceLifecycle.swift"
  "${relay_root}/apple-watch/RelayWatch/RelayVoiceView.swift"
  "${relay_root}/apple-watch/RelayWatch/WatchIdentity.swift"
)

for architecture in arm64_32 arm64; do
  env CLANG_MODULE_CACHE_PATH="${module_cache}" \
    xcrun swiftc \
      -typecheck \
      -parse-as-library \
      -sdk "${watch_sdk}" \
      -target "${architecture}-apple-watchos10.0" \
      "${source_files[@]}"
done

echo "Apple Watch source type-check passed for watchOS 10+ architectures."
