#!/usr/bin/env bash
set -euo pipefail

APP_NAME="PaimonToolbox"
DISPLAY_NAME="派蒙工具箱"
VERSION="0.1.0"
EXTENSION_NAME="PaimonToolboxWidgetsExtension"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/$APP_NAME.xcodeproj"
DIST_DIR="$ROOT_DIR/dist"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/${APP_NAME}.package.XXXXXX")"
DERIVED_DATA="${DERIVED_DATA:-$WORK_DIR/DerivedData}"
RELEASE_DIR="$WORK_DIR/release"
APP_BUNDLE="$RELEASE_DIR/$APP_NAME.app"
EXTENSION_BUNDLE="$APP_BUNDLE/Contents/PlugIns/$EXTENSION_NAME.appex"
APP_BINARY="$APP_BUNDLE/Contents/MacOS/$APP_NAME"
APP_ENTITLEMENTS="$ROOT_DIR/Entitlements/$APP_NAME.entitlements"
EXTENSION_ENTITLEMENTS="$ROOT_DIR/Entitlements/$EXTENSION_NAME.entitlements"
CODESIGN_IDENTITY="${CODESIGN_IDENTITY:--}"
ARCH="${ARCH:-$(uname -m)}"
DMG_STAGING="$WORK_DIR/dmg-staging"
DMG_PATH="$DIST_DIR/$APP_NAME-$VERSION.dmg"
TMP_DMG_PATH="$WORK_DIR/$APP_NAME-$VERSION.dmg"

cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

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
    codesign --force --sign "$CODESIGN_IDENTITY" "$dylib"
  done

  if [[ -d "$EXTENSION_BUNDLE" ]]; then
    codesign --force --sign "$CODESIGN_IDENTITY" --entitlements "$EXTENSION_ENTITLEMENTS" "$EXTENSION_BUNDLE"
  fi

  codesign --force --sign "$CODESIGN_IDENTITY" --entitlements "$APP_ENTITLEMENTS" "$APP_BUNDLE"
  codesign --verify --deep --strict "$APP_BUNDLE"
}

cd "$ROOT_DIR"

"$ROOT_DIR/script/generate_xcode_project.py" >/dev/null

xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$APP_NAME" \
  -configuration Release \
  -destination "platform=macOS,arch=$ARCH" \
  -derivedDataPath "$DERIVED_DATA" \
  CODE_SIGNING_ALLOWED=NO \
  build

rm -rf "$DMG_PATH"
mkdir -p "$RELEASE_DIR" "$DMG_STAGING" "$DIST_DIR"
ditto --noextattr --noqtn "$DERIVED_DATA/Build/Products/Release/$APP_NAME.app" "$APP_BUNDLE"

"$APP_BINARY" --self-check
sign_app_bundle

ditto --noextattr --noqtn "$APP_BUNDLE" "$DMG_STAGING/$APP_NAME.app"
clean_bundle_metadata "$DMG_STAGING/$APP_NAME.app"
codesign --verify --deep --strict "$DMG_STAGING/$APP_NAME.app"
ln -s /Applications "$DMG_STAGING/Applications"

hdiutil create \
  -volname "$DISPLAY_NAME $VERSION" \
  -srcfolder "$DMG_STAGING" \
  -ov \
  -fs HFS+ \
  -format UDZO \
  "$TMP_DMG_PATH"

hdiutil verify "$TMP_DMG_PATH"
ditto --noextattr --noqtn "$TMP_DMG_PATH" "$DMG_PATH"
hdiutil verify "$DMG_PATH"
codesign --verify --deep --strict "$APP_BUNDLE"
echo "$DMG_PATH"
