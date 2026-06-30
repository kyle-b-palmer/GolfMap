#!/usr/bin/env bash
# Prepare Flutter iOS deps and open the correct Xcode workspace.
#
# IMPORTANT: Always use Runner.xcworkspace (not Runner.xcodeproj).
# Opening the .xcodeproj causes "Module 'apple_maps_flutter' not found".

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "==> flutter pub get"
flutter pub get

echo "==> pod install"
cd ios
pod install

echo "==> Opening Runner.xcworkspace"
open Runner.xcworkspace
