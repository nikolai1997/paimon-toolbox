#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="$(<"$ROOT_DIR/VERSION")"
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Invalid app version in $ROOT_DIR/VERSION: $VERSION" >&2
  exit 1
fi

APP_NAME="PaimonToolbox"
DISPLAY_NAME="派蒙工具箱"
EXTENSION_NAME="PaimonToolboxWidgetsExtension"
EXTENSION_BUNDLE_NAME="PaimonToolboxWidgetsExtension.appex"
WIDGET_BUNDLE_ID="com.nikolai.paimon-toolbox.widgets"
APP_BUNDLE_ID="com.nikolai.paimon-toolbox"
LEGACY_APP_NAME="GenshinToolbox"
LEGACY_EXTENSION_NAME="GenshinToolboxWidgetsExtension"
LEGACY_EXTENSION_BUNDLE_NAME="GenshinToolboxWidgetsExtension.appex"
LEGACY_WIDGET_BUNDLE_ID="com.nikolai.genshin-toolbox.widgets"
LEGACY_APP_BUNDLE_ID="com.nikolai.genshin-toolbox"

DMG_PATH="$ROOT_DIR/dist/$APP_NAME-$VERSION.dmg"
INSTALL_DIR="${1:-/Applications}"
DEST_APP="$INSTALL_DIR/$APP_NAME.app"
LEGACY_APP="$INSTALL_DIR/$LEGACY_APP_NAME.app"
MOUNT_DIR="$(mktemp -d "${TMPDIR:-/tmp}/${APP_NAME}.install.XXXXXX")"
PACKAGE_SCRIPT="${PAIMON_INSTALL_PACKAGE_SCRIPT:-$ROOT_DIR/script/package_dmg.sh}"
LSREGISTER="${PAIMON_INSTALL_LSREGISTER:-/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister}"
VERIFY_DELAY="${PAIMON_INSTALL_VERIFY_DELAY:-2}"
INSTALL_WORK_DIR=""
STAGED_APP=""
BACKUP_APP=""
LEGACY_BACKUP_APP=""
DEST_REPLACED=0
LEGACY_MOVED=0
HAD_DEST_APP=0
HAD_LEGACY_APP=0
TRANSACTION_STARTED=0
INSTALL_COMMITTED=0

bundle_identifier() {
  plutil -extract CFBundleIdentifier raw "$1/Contents/Info.plist"
}

canonical_path() {
  local path="$1"
  printf '%s/%s\n' "$(cd "$(dirname "$path")" && pwd -P)" "$(basename "$path")"
}

stop_process() {
  local process_name="$1"
  local status
  if pkill -x "$process_name" >/dev/null 2>&1; then
    return 0
  else
    status=$?
  fi
  if [[ "$status" -ne 1 ]]; then
    echo "Failed to stop process: $process_name" >&2
    return "$status"
  fi
}

stop_new_processes() {
  local status=0
  stop_process "$APP_NAME" || status=1
  stop_process "$EXTENSION_NAME" || status=1
  return "$status"
}

verify_widget_registration() {
  local bundle_id="$1"
  local extension_path="$2"
  local label="$3"
  local expected_path
  local output
  expected_path="$(canonical_path "$extension_path")"
  if ! output="$(pluginkit -m -AD -v -i "$bundle_id" 2>&1)"; then
    echo "$output" >&2
    echo "$label widget registration query failed." >&2
    return 1
  fi
  if [[ "$output" == *"(no matches)"* || "$output" != *"$expected_path"* ]]; then
    echo "$output" >&2
    echo "$label widget registration verification failed." >&2
    return 1
  fi
  printf '%s\n' "$output"
}

verify_existing_app_identity() {
  local app_path="$1"
  local expected_bundle_id="$2"
  local label="$3"
  local actual_bundle_id
  if ! actual_bundle_id="$(bundle_identifier "$app_path")"; then
    echo "Unable to read $label bundle id at $app_path" >&2
    return 1
  fi
  if [[ "$actual_bundle_id" != "$expected_bundle_id" ]]; then
    echo "Refusing to replace $label with unexpected bundle id: $actual_bundle_id" >&2
    return 1
  fi
}

register_restored_app() {
  local app_path="$1"
  local app_bundle_id="$2"
  local extension_path="$3"
  local widget_bundle_id="$4"
  local label="$5"

  [[ -d "$app_path" ]] || return 1
  [[ "$(bundle_identifier "$app_path")" == "$app_bundle_id" ]] || return 1
  codesign --verify --deep --strict "$app_path" || return 1
  "$LSREGISTER" -f "$app_path" >/dev/null || return 1
  if [[ -d "$extension_path" ]]; then
    [[ "$(bundle_identifier "$extension_path")" == "$widget_bundle_id" ]] || return 1
    codesign --verify --strict "$extension_path" || return 1
    pluginkit -a "$extension_path" >/dev/null || return 1
    verify_widget_registration "$widget_bundle_id" "$extension_path" "$label" >/dev/null || return 1
  fi
}

restore_previous_install() {
  local status=0
  local current_extension="$DEST_APP/Contents/PlugIns/$EXTENSION_BUNDLE_NAME"
  local legacy_extension="$LEGACY_APP/Contents/PlugIns/$LEGACY_EXTENSION_BUNDLE_NAME"

  stop_new_processes || status=1

  if [[ "$DEST_REPLACED" -eq 1 && -e "$DEST_APP" ]]; then
    if ! mv "$DEST_APP" "$INSTALL_WORK_DIR/failed-install.app"; then
      echo "Failed to preserve the failed new app during recovery." >&2
      status=1
    fi
  fi

  if [[ "$HAD_DEST_APP" -eq 1 ]]; then
    if [[ -e "$BACKUP_APP" ]]; then
      if [[ -e "$DEST_APP" ]] || ! mv "$BACKUP_APP" "$DEST_APP"; then
        echo "Failed to restore the previous PaimonToolbox.app." >&2
        status=1
      fi
    fi
    if [[ ! -d "$DEST_APP" ]]; then
      status=1
    elif ! register_restored_app \
      "$DEST_APP" \
      "$APP_BUNDLE_ID" \
      "$current_extension" \
      "$WIDGET_BUNDLE_ID" \
      "Previous PaimonToolbox"; then
      echo "Failed to verify or register the restored PaimonToolbox.app." >&2
      status=1
    fi
  elif [[ -e "$DEST_APP" ]]; then
    echo "Failed to remove the new PaimonToolbox.app during recovery." >&2
    status=1
  fi

  if [[ "$LEGACY_MOVED" -eq 1 && -e "$LEGACY_BACKUP_APP" ]]; then
    if [[ -e "$LEGACY_APP" ]] || ! mv "$LEGACY_BACKUP_APP" "$LEGACY_APP"; then
      echo "Failed to restore the legacy GenshinToolbox.app." >&2
      status=1
    fi
  fi
  if [[ "$HAD_LEGACY_APP" -eq 1 ]]; then
    if [[ ! -d "$LEGACY_APP" ]]; then
      status=1
    elif ! register_restored_app \
      "$LEGACY_APP" \
      "$LEGACY_APP_BUNDLE_ID" \
      "$legacy_extension" \
      "$LEGACY_WIDGET_BUNDLE_ID" \
      "Legacy GenshinToolbox"; then
      echo "Failed to verify or register the restored GenshinToolbox.app." >&2
      status=1
    fi
  fi

  return "$status"
}

cleanup() {
  local exit_status=$?
  local recovery_status=0
  trap - EXIT
  set +e

  if [[ "$exit_status" -ne 0 && "$INSTALL_COMMITTED" -ne 1 && "$TRANSACTION_STARTED" -eq 1 ]]; then
    restore_previous_install
    recovery_status=$?
  fi

  hdiutil detach "$MOUNT_DIR" -quiet >/dev/null 2>&1 || true
  rm -rf "$MOUNT_DIR" >/dev/null 2>&1 || true

  if [[ -n "$INSTALL_WORK_DIR" ]]; then
    if [[ "$exit_status" -eq 0 || "$recovery_status" -eq 0 ]]; then
      if ! rm -rf "$INSTALL_WORK_DIR"; then
        echo "Failed to remove installer transaction directory: $INSTALL_WORK_DIR" >&2
        [[ "$exit_status" -ne 0 ]] || exit_status=1
      fi
    else
      echo "Installation recovery failed. Backup retained at: $INSTALL_WORK_DIR" >&2
    fi
  fi

  if [[ "$recovery_status" -ne 0 && "$exit_status" -eq 0 ]]; then
    exit_status=1
  fi
  exit "$exit_status"
}
trap cleanup EXIT

if [[ -z "$INSTALL_DIR" || "$INSTALL_DIR" == "/" ]]; then
  echo "Refusing to install into an unsafe directory: $INSTALL_DIR" >&2
  exit 2
fi

cd "$ROOT_DIR"

"$PACKAGE_SCRIPT" >/dev/null

mkdir -p "$INSTALL_DIR"
INSTALL_WORK_DIR="$(mktemp -d "$INSTALL_DIR/.${APP_NAME}.install.XXXXXX")"
STAGED_APP="$INSTALL_WORK_DIR/$APP_NAME.app"
BACKUP_APP="$INSTALL_WORK_DIR/$APP_NAME.previous.app"
LEGACY_BACKUP_APP="$INSTALL_WORK_DIR/$LEGACY_APP_NAME.previous.app"
hdiutil attach "$DMG_PATH" -mountpoint "$MOUNT_DIR" -nobrowse -quiet

ditto --noextattr --noqtn "$MOUNT_DIR/$APP_NAME.app" "$STAGED_APP"
xattr -cr "$STAGED_APP" 2>/dev/null || true
codesign --verify --deep --strict "$STAGED_APP"
STAGED_EXTENSION="$STAGED_APP/Contents/PlugIns/$EXTENSION_BUNDLE_NAME"
[[ -d "$STAGED_EXTENSION" ]]
codesign --verify --strict "$STAGED_EXTENSION"
[[ "$(bundle_identifier "$STAGED_APP")" == "$APP_BUNDLE_ID" ]]
[[ "$(bundle_identifier "$STAGED_EXTENSION")" == "$WIDGET_BUNDLE_ID" ]]
"$STAGED_APP/Contents/MacOS/$APP_NAME" --self-check
[[ -x "$LSREGISTER" ]]

if [[ -e "$DEST_APP" ]]; then
  verify_existing_app_identity "$DEST_APP" "$APP_BUNDLE_ID" "existing PaimonToolbox.app"
  HAD_DEST_APP=1
fi
if [[ -e "$LEGACY_APP" ]]; then
  verify_existing_app_identity "$LEGACY_APP" "$LEGACY_APP_BUNDLE_ID" "legacy GenshinToolbox.app"
  HAD_LEGACY_APP=1
fi

TRANSACTION_STARTED=1
stop_process "$APP_NAME"
stop_process "$EXTENSION_NAME"
stop_process "$LEGACY_APP_NAME"
stop_process "$LEGACY_EXTENSION_NAME"

if [[ "$HAD_DEST_APP" -eq 1 ]]; then
  mv "$DEST_APP" "$BACKUP_APP"
fi
mv "$STAGED_APP" "$DEST_APP"
DEST_REPLACED=1
codesign --verify --deep --strict "$DEST_APP"

"$LSREGISTER" -f "$DEST_APP" >/dev/null
CURRENT_EXTENSION="$DEST_APP/Contents/PlugIns/$EXTENSION_BUNDLE_NAME"
pluginkit -a "$CURRENT_EXTENSION" >/dev/null
open -n "$DEST_APP"

sleep "$VERIFY_DELAY"
PLUGIN_OUTPUT="$(verify_widget_registration "$WIDGET_BUNDLE_ID" "$CURRENT_EXTENSION" "Installed PaimonToolbox")"

while IFS= read -r plugin_path; do
  if [[ -n "$plugin_path" && "$plugin_path" != "$(canonical_path "$CURRENT_EXTENSION")" ]]; then
    pluginkit -r "$plugin_path" >/dev/null
  fi
done <<< "$(printf '%s\n' "$PLUGIN_OUTPUT" | awk -F '\t' '/PaimonToolboxWidgetsExtension\.appex/ { print $NF }')"

if [[ "$HAD_LEGACY_APP" -eq 1 ]]; then
  LEGACY_EXTENSION="$LEGACY_APP/Contents/PlugIns/$LEGACY_EXTENSION_BUNDLE_NAME"
  "$LSREGISTER" -u "$LEGACY_APP" >/dev/null
  if [[ -d "$LEGACY_EXTENSION" ]]; then
    pluginkit -r "$LEGACY_EXTENSION" >/dev/null
  fi
  mv "$LEGACY_APP" "$LEGACY_BACKUP_APP"
  LEGACY_MOVED=1
fi

INSTALL_COMMITTED=1
echo "Installed $DISPLAY_NAME to $DEST_APP"
echo "Widget extension:"
echo "$CURRENT_EXTENSION"
echo "$PLUGIN_OUTPUT"
