#!/usr/bin/env bash
# Build and install the iPhone app plus embedded Apple Watch companion.
#
# `flutter run` installs Runner.app to the phone but does not reliably sync the
# embedded Watch/GolfMapWatch.app to a paired Apple Watch. `xcodebuild install`
# also does not push to a physical device — this script uses devicectl to install.
#
# Debug builds include Runner.debug.dylib and crash when opened from the home
# screen without the Flutter debugger attached. Release is required for installs.
#
# Usage:
#   ./tool/install_ios_with_watch.sh              # first connected iPhone
#   ./tool/install_ios_with_watch.sh KP          # device name from `flutter devices`
#   ./tool/install_ios_with_watch.sh KP --debug    # for flutter run / Xcode Run only
#   ./tool/install_ios_with_watch.sh KP --clean    # clean Xcode build folder first

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

CONFIGURATION="Release"
DEVICE_NAME=""
WATCH_NAME=""
DO_CLEAN=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --release)
      CONFIGURATION="Release"
      shift
      ;;
    --debug)
      CONFIGURATION="Debug"
      shift
      ;;
    --clean)
      DO_CLEAN=1
      shift
      ;;
    --watch)
      shift
      WATCH_NAME="${1:-}"
      shift
      ;;
    *)
      if [[ -z "$DEVICE_NAME" ]]; then
        DEVICE_NAME="$1"
      elif [[ -z "$WATCH_NAME" ]]; then
        WATCH_NAME="$1"
      fi
      shift
      ;;
  esac
done

resolve_device_id() {
  local query="$1"
  flutter devices --machine 2>/dev/null | python3 -c "
import json, sys

query = sys.argv[1].strip()
devices = json.load(sys.stdin)
ios_devices = [
    d for d in devices
    if d.get('targetPlatform') == 'ios' and not d.get('emulator')
]

if not ios_devices:
    sys.exit(0)

if not query:
    print(ios_devices[0]['id'])
    sys.exit(0)

for d in ios_devices:
    if query.lower() == d.get('id', '').lower():
        print(d['id'])
        sys.exit(0)

for d in ios_devices:
    if d.get('name') == query:
        print(d['id'])
        sys.exit(0)

query_lower = query.lower()
for d in ios_devices:
    if d.get('name', '').lower() == query_lower:
        print(d['id'])
        sys.exit(0)

if len(ios_devices) == 1:
    print(ios_devices[0]['id'])
" "$query"
}

resolve_device_name() {
  local device_id="$1"
  flutter devices --machine 2>/dev/null | python3 -c "
import json, sys

device_id = sys.argv[1].strip().lower()
for d in json.load(sys.stdin):
    if d.get('id', '').lower() == device_id:
        print(d.get('name', device_id))
        sys.exit(0)
print(device_id)
" "$device_id"
}

resolve_core_device_id() {
  local flutter_device_id="$1"
  local device_name="$2"
  xcrun devicectl list devices --json-output - 2>/dev/null | python3 -c "
import json, sys

flutter_id = sys.argv[1].strip().lower()
device_name = sys.argv[2].strip().lower()
devices = json.load(sys.stdin).get('result', {}).get('devices', [])

for device in devices:
    props = device.get('hardwareProperties', {})
    udid = props.get('udid', '').lower()
    if udid and udid == flutter_id:
        print(device['identifier'])
        sys.exit(0)

for device in devices:
    props = device.get('deviceProperties', {})
    name = props.get('name', '').lower()
    platform = device.get('hardwareProperties', {}).get('platform', '')
    if platform == 'iOS' and name and name == device_name:
        print(device['identifier'])
        sys.exit(0)

for device in devices:
    platform = device.get('hardwareProperties', {}).get('platform', '')
    if platform == 'iOS' and device.get('connectionProperties', {}).get('tunnelState') == 'connected':
        print(device['identifier'])
        sys.exit(0)
" "$flutter_device_id" "$device_name" 2>/dev/null || true
}

resolve_watch_core_device_id() {
  local watch_name="${1:-}"
  xcrun devicectl list devices --json-output - 2>/dev/null | python3 -c "
import json, sys

watch_name = sys.argv[1].strip().lower()
devices = json.load(sys.stdin).get('result', {}).get('devices', [])

def watch_rank(device):
    platform = device.get('hardwareProperties', {}).get('platform', '')
    if platform != 'watchOS':
        return -1
    props = device.get('connectionProperties', {})
    tunnel = props.get('tunnelState', '')
    pairing = props.get('pairingState', '')
    if tunnel == 'connected':
        return 4
    if tunnel == 'connecting':
        return 3
    if pairing == 'paired':
        return 2
    if tunnel in ('', 'disconnected') and device.get('deviceProperties', {}).get('name'):
        return 1
    return 0

candidates = []
for device in devices:
    rank = watch_rank(device)
    if rank < 0:
        continue
    name = device.get('deviceProperties', {}).get('name', '').lower()
    if watch_name and name and watch_name not in name:
        continue
    candidates.append((rank, device))

if not candidates:
    sys.exit(0)

candidates.sort(key=lambda item: item[0], reverse=True)
print(candidates[0][1]['identifier'])
" "$watch_name" 2>/dev/null || true
}

wait_for_watch_device() {
  local watch_name="${1:-}"
  local attempts="${2:-20}"
  local device_id=""
  echo "==> Looking for paired Apple Watch (unlock watch, keep it near iPhone)..." >&2
  for ((i = 1; i <= attempts; i++)); do
    device_id="$(resolve_watch_core_device_id "$watch_name")"
    if [[ -n "$device_id" ]]; then
      echo "$device_id"
      return 0
    fi
    sleep 2
  done
  return 1
}

resolve_built_runner_app() {
  local device_id="$1"
  local configuration="$2"
  local build_number="$3"
  python3 -c "
import glob
import os
import subprocess
import sys

root = sys.argv[1]
configuration = sys.argv[2]
device_id = sys.argv[3]
build_number = sys.argv[4]

def exists(path: str) -> bool:
    return bool(path) and os.path.isdir(path)

candidates = []

try:
    result = subprocess.run(
        [
            'xcodebuild',
            '-workspace', os.path.join(root, 'ios/Runner.xcworkspace'),
            '-scheme', 'Runner',
            '-configuration', configuration,
            '-destination', f'id={device_id}',
            '-showBuildSettings',
            f'FLUTTER_BUILD_NUMBER={build_number}',
            f'CURRENT_PROJECT_VERSION={build_number}',
        ],
        capture_output=True,
        text=True,
        check=False,
    )
    settings = {}
    for line in result.stdout.splitlines():
        if ' = ' not in line:
            continue
        key, value = line.split(' = ', 1)
        settings[key.strip()] = value.strip()

    for key in ('TARGET_BUILD_DIR', 'BUILT_PRODUCTS_DIR'):
        base = settings.get(key, '')
        wrapper = settings.get('WRAPPER_NAME', '')
        if base and wrapper:
            candidates.append(os.path.join(base, wrapper))
except OSError:
    pass

candidates.extend([
    os.path.join(root, 'build/ios/iphoneos/Runner.app'),
    os.path.join(root, f'build/ios/{configuration}-iphoneos/Runner.app'),
    os.path.join(root, 'build/ios/Debug-iphoneos/Runner.app'),
    os.path.join(root, 'build/ios/Release-iphoneos/Runner.app'),
])
candidates.extend(sorted(glob.glob(os.path.join(root, 'build/ios/*iphoneos/Runner.app'))))
candidates.extend(sorted(glob.glob(os.path.expanduser(
    '~/Library/Developer/Xcode/DerivedData/Runner-*/Build/Products/*-iphoneos/Runner.app'
))))

seen = set()
best = ''
for path in candidates:
    if path in seen:
        continue
    seen.add(path)
    if not exists(path):
        continue
    watch_plist = os.path.join(path, 'Watch', 'GolfMapWatch.app', 'Info.plist')
    if os.path.isfile(watch_plist):
        print(path)
        sys.exit(0)
    if not best:
        best = path

if best:
    print(best)
" "$ROOT" "$configuration" "$device_id" "$build_number"
}

verify_runner_has_watch() {
  local runner_app="$1"
  local watch_app="$runner_app/Watch/GolfMapWatch.app"
  if [[ ! -d "$watch_app" ]]; then
    echo "ERROR: Watch app missing at $watch_app" >&2
    echo "Open ios/Runner.xcworkspace, use Runner scheme + iPhone destination, then rebuild." >&2
    exit 1
  fi
  local watch_version
  watch_version=$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$watch_app/Info.plist" 2>/dev/null || true)
  if [[ -z "$watch_version" ]]; then
    echo "ERROR: Embedded watch app is missing CFBundleVersion (watchOS will not update)." >&2
    exit 1
  fi
  echo "Embedded watch build version: $watch_version"
}

install_runner_app() {
  local core_device_id="$1"
  local runner_app="$2"
  echo "==> Installing iPhone app to $DEVICE_NAME via devicectl"
  xcrun devicectl device install app \
    --device "$core_device_id" \
    "$runner_app"
}

install_watch_app() {
  local watch_core_device_id="$1"
  local watch_app="$2"
  echo "==> Installing watch app via devicectl"
  xcrun devicectl device install app \
    --device "$watch_core_device_id" \
    "$watch_app"
}

DEVICE_ID="$(resolve_device_id "$DEVICE_NAME")"

if [[ -z "$DEVICE_ID" ]]; then
  if [[ -n "$DEVICE_NAME" ]]; then
    echo "Could not resolve device id for: $DEVICE_NAME" >&2
  else
    echo "No connected iPhone found. Plug in your phone and run: flutter devices" >&2
  fi
  exit 1
fi

if [[ -z "$DEVICE_NAME" ]]; then
  DEVICE_NAME="$(resolve_device_name "$DEVICE_ID")"
fi

CORE_DEVICE_ID="$(resolve_core_device_id "$DEVICE_ID" "$DEVICE_NAME")"
if [[ -z "$CORE_DEVICE_ID" ]]; then
  echo "ERROR: Could not resolve devicectl device id for $DEVICE_NAME ($DEVICE_ID)" >&2
  echo "Unlock your iPhone, trust this Mac, and ensure Developer Mode is enabled." >&2
  exit 1
fi

BUILD_NUMBER="$(date +%s)"

echo "==> Building Flutter ($CONFIGURATION) for $DEVICE_NAME ($DEVICE_ID)"
echo "==> Using build number $BUILD_NUMBER so the watch app can update"
if [[ "$CONFIGURATION" == "Release" ]]; then
  flutter build ios --release --build-number="$BUILD_NUMBER"
else
  flutter build ios --debug --build-number="$BUILD_NUMBER"
fi

cd ios

XCODE_ARGS=(
  -workspace Runner.xcworkspace
  -scheme Runner
  -configuration "$CONFIGURATION"
  -destination "id=$DEVICE_ID"
  -allowProvisioningUpdates
  "FLUTTER_BUILD_NUMBER=$BUILD_NUMBER"
  "CURRENT_PROJECT_VERSION=$BUILD_NUMBER"
)

if [[ "$DO_CLEAN" -eq 1 ]]; then
  echo "==> Cleaning Xcode build folder"
  xcodebuild "${XCODE_ARGS[@]}" clean
fi

echo "==> Building via Xcode (embeds Watch/GolfMapWatch.app)"
xcodebuild "${XCODE_ARGS[@]}" build

RUNNER_APP="$(resolve_built_runner_app "$DEVICE_ID" "$CONFIGURATION" "$BUILD_NUMBER")"
if [[ -z "$RUNNER_APP" || ! -d "$RUNNER_APP" ]]; then
  echo "ERROR: Could not locate built Runner.app after xcodebuild" >&2
  exit 1
fi

echo "==> Built app: $RUNNER_APP"
verify_runner_has_watch "$RUNNER_APP"

if [[ "$CONFIGURATION" == "Debug" && -f "$RUNNER_APP/Runner.debug.dylib" ]]; then
  echo "WARNING: Debug builds crash when opened from the home screen." >&2
  echo "         Use: flutter run -d $DEVICE_NAME" >&2
  echo "         Or re-run with --release for a standalone install." >&2
fi

install_runner_app "$CORE_DEVICE_ID" "$RUNNER_APP"

WATCH_APP="$RUNNER_APP/Watch/GolfMapWatch.app"
WATCH_CORE_DEVICE_ID="$(wait_for_watch_device "$WATCH_NAME" 20 || true)"
if [[ -n "$WATCH_CORE_DEVICE_ID" && -d "$WATCH_APP" ]]; then
  install_watch_app "$WATCH_CORE_DEVICE_ID" "$WATCH_APP"
else
  echo "==> Could not install directly to Apple Watch."
  echo "    Unlock your watch, keep it on your wrist near the iPhone, then run:"
  echo "      ./tool/install_ios_with_watch.sh $DEVICE_NAME"
  echo ""
  echo "    Or on iPhone: Watch app → General → scroll to South Texas Golf Tracker"
  echo "    → turn ON \"Show App on Apple Watch\"."
fi

xcrun devicectl device process launch --device "$CORE_DEVICE_ID" com.golfmapapp.golfMapFlutter 2>/dev/null || true

echo ""
echo "Done. South Texas Golf Tracker should now be on your iPhone."
if [[ -n "${WATCH_CORE_DEVICE_ID:-}" ]]; then
  echo "Watch app installed directly — open South Texas Golf Tracker on your watch."
else
  echo "Watch app was NOT installed automatically."
  echo "1. Unlock Apple Watch and keep it near your iPhone."
  echo "2. Re-run: ./tool/install_ios_with_watch.sh $DEVICE_NAME"
  echo "3. Or on iPhone: Watch app → find South Texas Golf Tracker → enable Show App on Apple Watch."
fi
