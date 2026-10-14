#!/bin/zsh
# Checks a GolfMap .xcarchive for release: same bundle IDs as the Flutter app, Watch app and both extensions
# embedded, one version across every bundle, and nothing from Flutter. Usage: scripts/check_archive.sh <xcarchive>
set -euo pipefail

archive=${1:?path to GolfMap.xcarchive}
app="$archive/Products/Applications/GolfMap.app"
failures=0

fail() { print -u2 "FAIL: $1"; failures=$((failures + 1)); }
plist() { /usr/libexec/PlistBuddy -c "Print :$2" "$1/Info.plist" 2>/dev/null || true; }

[[ -d $app ]] || { print -u2 "No GolfMap.app in $archive"; exit 1; }

typeset -A expected=(
  "$app" com.golfmapapp.golfMapFlutter
  "$app/PlugIns/GolfRoundWidgetExtension.appex" com.golfmapapp.golfMapFlutter.GolfRoundWidget
  "$app/Watch/GolfMapWatch.app" com.golfmapapp.golfMapFlutter.watchkitapp
  "$app/Watch/GolfMapWatch.app/PlugIns/GolfMapWatchWidgetExtension.appex" com.golfmapapp.golfMapFlutter.watchkitapp.widget
)

version=$(plist "$app" CFBundleShortVersionString)
build=$(plist "$app" CFBundleVersion)
for bundle id in "${(@kv)expected}"; do
  name=${bundle#$app/}
  if [[ ! -d $bundle ]]; then
    fail "missing ${name}"
    continue
  fi
  [[ $(plist "$bundle" CFBundleIdentifier) == "$id" ]] || fail "$name has bundle ID $(plist "$bundle" CFBundleIdentifier), expected $id"
  [[ $(plist "$bundle" CFBundleShortVersionString) == "$version" && $(plist "$bundle" CFBundleVersion) == "$build" ]] \
    || fail "$name version differs from the app's $version ($build)"
done

[[ $(plist "$app/Watch/GolfMapWatch.app" WKCompanionAppBundleIdentifier) == com.golfmapapp.golfMapFlutter ]] \
  || fail "Watch app isn't paired with com.golfmapapp.golfMapFlutter"
[[ $(plist "$app" NSSupportsLiveActivities) == true ]] || fail "NSSupportsLiveActivities is off"

if find "$app" -iname "*flutter*" ! -iname "*golfMapFlutter*" | grep -q .; then
  fail "Flutter files in the archive: $(find "$app" -iname '*flutter*' ! -iname '*golfMapFlutter*' | head -3)"
fi
if find "$app" -type f -perm -u+x -exec otool -L {} \; 2>/dev/null | grep -i "flutter.framework" | grep -q .; then
  fail "a binary links Flutter.framework"
fi

if (( failures )); then
  print -u2 "$failures problem(s) in $archive"
  exit 1
fi
print "Archive OK: GolfMap $version ($build) with Live Activity, Watch app, and Watch complications; no Flutter."
