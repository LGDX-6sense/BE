#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_URL="${1:-http://192.168.0.13:8000}"
DEVICE_ID="${2:-}"

cd "$SCRIPT_DIR"

echo "Using backend: $BASE_URL"
flutter pub get

pushd ios >/dev/null
pod install
popd >/dev/null

if [[ -n "$DEVICE_ID" ]]; then
  flutter run -d "$DEVICE_ID" --dart-define=DEFAULT_BASE_URL="$BASE_URL"
else
  flutter run --dart-define=DEFAULT_BASE_URL="$BASE_URL"
fi
