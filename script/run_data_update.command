#!/bin/zsh
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR/.."
python3 script/update_remote_data.py \
  --source genshin-db \
  --gacha-source snap-metadata \
  --locale CHS \
  --manual-dir data/manual \
  --fetch-official-announcements \
  --public-dir data/public \
  --release-dir data/releases \
  "$@"
