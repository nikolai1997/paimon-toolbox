#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="PaimonToolbox"
BUNDLE_ID="com.nikolai.paimon-toolbox"
EXTENSION_NAME="PaimonToolboxWidgetsExtension"
WIDGET_BUNDLE_ID="com.nikolai.paimon-toolbox.widgets"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/$APP_NAME.xcodeproj"
DERIVED_DATA="${DERIVED_DATA:-${TMPDIR:-/tmp}/$APP_NAME.xcode-derived}"
CONFIGURATION="Debug"
APP_BUNDLE="$DERIVED_DATA/Build/Products/$CONFIGURATION/$APP_NAME.app"
APP_BINARY="$APP_BUNDLE/Contents/MacOS/$APP_NAME"
EXTENSION_BUNDLE="$APP_BUNDLE/Contents/PlugIns/$EXTENSION_NAME.appex"
APP_ENTITLEMENTS="$ROOT_DIR/Entitlements/$APP_NAME.entitlements"
EXTENSION_ENTITLEMENTS="$ROOT_DIR/Entitlements/$EXTENSION_NAME.entitlements"
CODESIGN_IDENTITY="${CODESIGN_IDENTITY:--}"

cd "$ROOT_DIR"

pkill -x "$APP_NAME" >/dev/null 2>&1 || true

clean_bundle_metadata() {
  local bundle="$1"
  xattr -cr "$bundle" 2>/dev/null || true
  find "$bundle" \
    -exec xattr -d com.apple.FinderInfo {} \; \
    -exec xattr -d 'com.apple.fileprovider.fpfs#P' {} \; \
    2>/dev/null || true
}

sign_app_bundle() {
  clean_bundle_metadata "$APP_BUNDLE"

  find "$APP_BUNDLE" -type f -name "*.dylib" -print0 | while IFS= read -r -d '' dylib; do
    codesign --force --sign "$CODESIGN_IDENTITY" "$dylib" >/dev/null
  done

  if [[ -d "$EXTENSION_BUNDLE" ]]; then
    codesign --force --sign "$CODESIGN_IDENTITY" --entitlements "$EXTENSION_ENTITLEMENTS" "$EXTENSION_BUNDLE" >/dev/null
  fi

  codesign --force --sign "$CODESIGN_IDENTITY" --entitlements "$APP_ENTITLEMENTS" "$APP_BUNDLE" >/dev/null
  codesign --verify --deep --strict "$APP_BUNDLE"
}

"$ROOT_DIR/script/generate_xcode_project.py" >/dev/null

xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$APP_NAME" \
  -configuration "$CONFIGURATION" \
  -derivedDataPath "$DERIVED_DATA" \
  CODE_SIGNING_ALLOWED=NO \
  build

sign_app_bundle

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

unregister_debug_widget() {
  if [[ -d "$EXTENSION_BUNDLE" ]]; then
    pluginkit -r "$EXTENSION_BUNDLE" >/dev/null 2>&1 || true
  fi
}

case "$MODE" in
  run)
    open_app
    sleep 1
    unregister_debug_widget
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    sleep 1
    unregister_debug_widget
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    sleep 1
    unregister_debug_widget
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    [[ -x "$APP_BINARY" ]]
    [[ -d "$EXTENSION_BUNDLE" ]]
    [[ "$(plutil -extract CFBundleIdentifier raw "$APP_BUNDLE/Contents/Info.plist")" == "$BUNDLE_ID" ]]
    [[ "$(plutil -extract CFBundleIdentifier raw "$EXTENSION_BUNDLE/Contents/Info.plist")" == "$WIDGET_BUNDLE_ID" ]]
    "$APP_BINARY" --self-check
    codesign --verify --deep --strict "$APP_BUNDLE"
    codesign --verify --strict "$EXTENSION_BUNDLE"
    pluginkit -a "$EXTENSION_BUNDLE" >/dev/null
    open_app
    sleep 2
    pgrep -x "$APP_NAME" >/dev/null
    PLUGIN_EXTENSION_PATH="$(cd "$(dirname "$EXTENSION_BUNDLE")" && pwd -P)/$(basename "$EXTENSION_BUNDLE")"
    PLUGIN_OUTPUT="$(pluginkit -m -AD -v -i "$WIDGET_BUNDLE_ID" 2>&1)"
    if [[ "$PLUGIN_OUTPUT" == *"(no matches)"* || "$PLUGIN_OUTPUT" != *"$PLUGIN_EXTENSION_PATH"* ]]; then
      echo "$PLUGIN_OUTPUT" >&2
      echo "Widget extension was not discovered by PlugInKit." >&2
      exit 1
    fi
    echo "$APP_NAME launched"
    echo "$PLUGIN_OUTPUT"
    echo "$APP_BUNDLE"
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
