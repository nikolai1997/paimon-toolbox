#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "usage: $0 <AppBundle.app> [debug|release]" >&2
  exit 2
fi

APP_BUNDLE_INPUT="$1"
CONFIGURATION="${2:-debug}"
EXTENSION_NAME="PaimonToolboxWidgetsExtension"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ "$APP_BUNDLE_INPUT" = /* ]]; then
  APP_BUNDLE="$APP_BUNDLE_INPUT"
else
  APP_BUNDLE="$PWD/$APP_BUNDLE_INPUT"
fi

EXTENSION_BUNDLE="$APP_BUNDLE/Contents/PlugIns/$EXTENSION_NAME.appex"
CODESIGN_IDENTITY="${CODESIGN_IDENTITY:--}"

exec "$ROOT_DIR/script/build_widget_extension_bundle.sh" "$EXTENSION_BUNDLE" "$CONFIGURATION" "$CODESIGN_IDENTITY"
