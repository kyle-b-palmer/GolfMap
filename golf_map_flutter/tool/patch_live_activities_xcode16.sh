#!/bin/bash
# live_activities 2.4.9 uses a trailing comma in a Swift function call.
# Xcode 16.0–16.2 (Swift 6.0.x) rejects that syntax. Run after `flutter pub get`.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PATTERN='s/result: result,)/result: result)/g'

patch_file() {
  local file="$1"
  if [[ -f "$file" ]]; then
    sed -i '' "$PATTERN" "$file"
    echo "Patched: $file"
  fi
}

patch_file "$HOME/.pub-cache/hosted/pub.dev/live_activities-2.4.9/ios/live_activities/Sources/live_activities/LiveActivitiesPlugin.swift"
patch_file "$ROOT/ios/Flutter/ephemeral/Packages/.packages/live_activities-2.4.9/Sources/live_activities/LiveActivitiesPlugin.swift"

echo "live_activities Xcode 16.2 patch applied."
