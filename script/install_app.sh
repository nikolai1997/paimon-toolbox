#!/usr/bin/env bash
set -euo pipefail

APP_NAME="PaimonToolbox"
DISPLAY_NAME="派蒙工具箱"
VERSION="0.1.0"
EXTENSION_NAME="PaimonToolboxWidgetsExtension"
EXTENSION_BUNDLE_NAME="PaimonToolboxWidgetsExtension.appex"
WIDGET_BUNDLE_ID="com.nikolai.paimon-toolbox.widgets"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DMG_PATH="$ROOT_DIR/dist/$APP_NAME-$VERSION.dmg"
INSTALL_DIR="${1:-/Applications}"
DEST_APP="$INSTALL_DIR/$APP_NAME.app"
MOUNT_DIR="$(mktemp -d "${TMPDIR:-/tmp}/${APP_NAME}.install.XXXXXX")"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

cleanup() {
  hdiutil detach "$MOUNT_DIR" -quiet >/dev/null 2>&1 || true
  rm -rf "$MOUNT_DIR" >/dev/null 2>&1 || true
}
trap cleanup EXIT

registered_widget_paths() {
  pluginkit -m -AD -v -i "$WIDGET_BUNDLE_ID" 2>/dev/null \
    | awk -F '\t' '/PaimonToolboxWidgetsExtension\.appex/ { print $NF }'
}

if [[ -z "$INSTALL_DIR" || "$INSTALL_DIR" == "/" ]]; then
  echo "Refusing to install into an unsafe directory: $INSTALL_DIR" >&2
  exit 2
fi

cd "$ROOT_DIR"

"$ROOT_DIR/script/package_dmg.sh" >/dev/null

mkdir -p "$INSTALL_DIR"
hdiutil attach "$DMG_PATH" -mountpoint "$MOUNT_DIR" -nobrowse -quiet

pkill -x "$APP_NAME" >/dev/null 2>&1 || true
pkill -x "$EXTENSION_NAME" >/dev/null 2>&1 || true

if [[ -e "$DEST_APP" ]]; then
  rm -rf "$DEST_APP"
fi

ditto --noextattr --noqtn "$MOUNT_DIR/$APP_NAME.app" "$DEST_APP"
xattr -cr "$DEST_APP" 2>/dev/null || true
codesign --verify --deep --strict "$DEST_APP"

if [[ -x "$LSREGISTER" ]]; then
  "$LSREGISTER" -f "$DEST_APP" >/dev/null 2>&1 || true
fi

CURRENT_EXTENSION="$DEST_APP/Contents/PlugIns/$EXTENSION_BUNDLE_NAME"
pluginkit -a "$CURRENT_EXTENSION" >/dev/null 2>&1 || true
while IFS= read -r PLUGIN_PATH; do
  if [[ -n "$PLUGIN_PATH" && "$PLUGIN_PATH" != "$CURRENT_EXTENSION" ]]; then
    pluginkit -r "$PLUGIN_PATH" >/dev/null 2>&1 || true
  fi
done < <(registered_widget_paths)
open -n "$DEST_APP"

sleep 2
echo "Installed $DISPLAY_NAME to $DEST_APP"
echo "Widget extension:"
echo "$CURRENT_EXTENSION"
PLUGIN_OUTPUT="$(pluginkit -m -AD -v -i "$WIDGET_BUNDLE_ID" 2>&1 || true)"
echo "$PLUGIN_OUTPUT"
if [[ "$PLUGIN_OUTPUT" == *"(no matches)"* ]]; then
  echo "Widget extension was not reported by PlugInKit yet. Reopen the app or sign with an Apple Development/Developer ID identity and rerun this script." >&2
fi
