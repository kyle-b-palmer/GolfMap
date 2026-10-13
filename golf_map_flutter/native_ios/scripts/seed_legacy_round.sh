#!/bin/zsh
# Writes a Flutter-format saved round into an installed simulator app's defaults and clears the native import
# marker, so the next launch runs the legacy migration against it. Usage: scripts/seed_legacy_round.sh <simulator id>
#
# `simctl spawn defaults write <bundle id>` doesn't reach a sandboxed app's preferences, so this writes the
# container's plist by path. The app must not be running.
set -euo pipefail

sim=${1:?simulator id}
bundle=com.golfmapapp.golfMapFlutter
prefs="$(xcrun simctl get_app_container "$sim" "$bundle" data)/Library/Preferences/$bundle"

rounds='[{"id":"1728830000000","courseName":"Brackenridge Golf Course","playedAt":"2026-10-11T08:15:00.000",
"scores":{"1":4,"2":3,"3":6,"4":5,"5":2,"6":4,"7":5,"8":4,"9":7,"10":4,"11":4,"12":3,"13":5,"14":4,"15":6,"16":3,"17":4,"18":5},
"putts":{"1":2,"2":1,"3":2,"4":2,"5":1,"6":2,"7":2,"8":2,"9":3,"10":2,"11":2,"12":2,"13":1,"14":2,"15":2,"16":2,"17":2,"18":2},
"pinnedShots":{"1":[{"shotNumber":1,"latitude":29.4521,"longitude":-98.4766,"yardsFromTee":231}]}}]'

xcrun simctl terminate "$sim" "$bundle" 2>/dev/null || true
xcrun simctl spawn "$sim" defaults write "$prefs" flutter.saved_golf_rounds -string "$rounds"
xcrun simctl spawn "$sim" defaults delete "$prefs" legacyImport.v1.completedAt 2>/dev/null || true
