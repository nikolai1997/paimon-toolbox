#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "usage: $0 <PaimonToolboxWidgetsExtension.appex> [debug|release] [CODESIGN_IDENTITY]" >&2
  exit 2
fi

EXTENSION_BUNDLE_INPUT="$1"
if [[ "$EXTENSION_BUNDLE_INPUT" = /* ]]; then
  EXTENSION_BUNDLE="$EXTENSION_BUNDLE_INPUT"
else
  EXTENSION_BUNDLE="$PWD/$EXTENSION_BUNDLE_INPUT"
fi
CONFIGURATION_INPUT="${2:-debug}"
CONFIGURATION="$(printf '%s' "$CONFIGURATION_INPUT" | tr '[:upper:]' '[:lower:]')"
case "$CONFIGURATION" in
  debug)
    SWIFT_OPTIMIZATION="-Onone"
    ;;
  release)
    SWIFT_OPTIMIZATION="-O"
    ;;
  *)
    CONFIGURATION="debug"
    SWIFT_OPTIMIZATION="-Onone"
    ;;
esac

EXTENSION_NAME="PaimonToolboxWidgetsExtension"
DISPLAY_NAME="派蒙工具箱"
BUNDLE_ID="com.nikolai.paimon-toolbox.widgets"
MIN_SYSTEM_VERSION="14.0"
EXTENSION_ENTITLEMENTS="Entitlements/PaimonToolboxWidgetsExtension.entitlements"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EXTENSION_MACOS="$EXTENSION_BUNDLE/Contents/MacOS"
EXTENSION_CONTENTS="$EXTENSION_BUNDLE/Contents"
EXTENSION_INFO_PLIST="$EXTENSION_CONTENTS/Info.plist"
CODESIGN_IDENTITY="${3:-${CODESIGN_IDENTITY:--}}"

cd "$ROOT_DIR"

export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-/private/tmp/paimon-toolbox-clang-cache}"
mkdir -p "$CLANG_MODULE_CACHE_PATH"

SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
ARCH="${ARCH:-$(uname -m)}"
TARGET="$ARCH-apple-macos$MIN_SYSTEM_VERSION"

compile_widget_binary() {
  mkdir -p "$EXTENSION_MACOS"

  xcrun swiftc \
    -parse-as-library \
    -application-extension \
    -target "$TARGET" \
    -sdk "$SDK_PATH" \
    "$SWIFT_OPTIMIZATION" \
    -D WIDGET_EXTENSION_BUNDLE_BUILD \
    Models/WidgetSnapshot.swift \
    Services/WidgetSnapshotStore.swift \
    Support/AppPaths.swift \
    Support/WidgetTimelineReloader.swift \
    Views/Widgets/ToolboxWidgetViews.swift \
    Widgets/PaimonToolboxWidgets.swift \
    -o "$EXTENSION_MACOS/$EXTENSION_NAME"
}

write_extension_info_plist() {
  cat >"$EXTENSION_INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>zh_CN</string>
  <key>CFBundleDisplayName</key>
  <string>$DISPLAY_NAME</string>
  <key>CFBundleExecutable</key>
  <string>$EXTENSION_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>$DISPLAY_NAME Widget</string>
  <key>CFBundlePackageType</key>
  <string>XPC!</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.1</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>NSExtension</key>
  <dict>
    <key>NSExtensionPointIdentifier</key>
    <string>com.apple.widgetkit-extension</string>
  </dict>
</dict>
</plist>
PLIST
}

clean_bundle_metadata() {
  xattr -cr "$EXTENSION_BUNDLE" 2>/dev/null || true
  find "$EXTENSION_BUNDLE" \
    -exec xattr -d com.apple.FinderInfo {} \; \
    -exec xattr -d 'com.apple.fileprovider.fpfs#P' {} \; \
    2>/dev/null || true
}

sign_widget_extension() {
  codesign --force --sign "$CODESIGN_IDENTITY" --entitlements "$EXTENSION_ENTITLEMENTS" "$EXTENSION_BUNDLE"
  codesign --verify --strict "$EXTENSION_BUNDLE"
}

rm -rf "$EXTENSION_BUNDLE"
compile_widget_binary
write_extension_info_plist
clean_bundle_metadata
sign_widget_extension

echo "$EXTENSION_BUNDLE"
