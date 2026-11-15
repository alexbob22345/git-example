#!/usr/bin/env bash
# Builds the Linux release bundle named change_gui and plays a short chime.
set -euo pipefail
cd "$(dirname "$0")/.."
if ! command -v flutter >/dev/null 2>&1; then
  echo "flutter is not on PATH" >&2
  exit 1
fi
flutter build linux --dart-define="BUILD_DATE=$(date +%F)"
echo "Release bundle: build/linux/x64/release/bundle/change_gui"
python3 tool/play_done.py || true
