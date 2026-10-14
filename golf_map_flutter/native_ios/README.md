# Native iOS (SwiftUI)

The SwiftUI rewrite described in `docs/IOS_SWIFTUI_MIGRATION_PLAN.md`. It ships under the existing bundle IDs and App Group, so it replaces the Flutter app on install.

## Layout

- `GolfKit/`: Swift package shared by every target.
  - `GolfCore`: course data, geometry, the round engine. Must match Flutter exactly; see the parity tests.
  - `GolfSync`: the shared round-state format (protocol v2), the App Group store, and Watch messages.
  - `GolfDesign`: color tokens, type, GPS status, and reusable controls, with previews.
- `App/`: the iPhone and iPad app.
- `AppTests/`: app-level tests hosted by the app.
- `LiveActivity/`: the widget extension with the round Live Activity and its intents.
- `Watch/` and `WatchWidget/`: the watchOS app and its complications.
- `project.yml`: the XcodeGen spec. `GolfMap.xcodeproj` is generated and not committed.

## Build

Requires Xcode 26 and XcodeGen (`brew install xcodegen`).

```sh
cd native_ios
xcodegen generate
open GolfMap.xcodeproj
```

From the command line:

```sh
# Package tests (macOS host)
(cd GolfKit && swift test)

# App and package tests on a simulator
xcodebuild -project GolfMap.xcodeproj -scheme GolfMap \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO test

# UI smoke tests: play, save, reopen, and restore a round; drag map points; trace, edit, and play a course
xcodebuild -project GolfMap.xcodeproj -scheme GolfMapUITests \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO test

# Watch app
xcodebuild -project GolfMap.xcodeproj -scheme GolfMapWatch \
  -destination 'generic/platform=watchOS Simulator' \
  -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO build

# Release archive (unsigned), then check what it embeds
xcodebuild -project GolfMap.xcodeproj -scheme GolfMap -configuration Release \
  -destination 'generic/platform=iOS' -archivePath /tmp/GolfMap.xcarchive \
  CODE_SIGNING_ALLOWED=NO archive
```

The UI tests launch Debug builds with `-GolfMapUITestReset`, which deletes the app's Application Support folder and its preferences before anything loads, so each test starts from an empty install. Don't pass it to a build with data you want to keep.

## Parity fixtures

`GolfKit/Tests/GolfCoreTests/Fixtures/parity_v1.json` is generated from the Flutter code:

```sh
flutter test test/parity/export_parity_fixtures_test.dart
```

Regenerate it only when a Flutter behavior change is intended, and fix the matching Swift code in the same change.

## Screenshots in the simulator

Debug builds read two persistent defaults on launch:

- `GolfMapOpenCourse` opens that course's round in place of Home.
- `GolfMapHomeRoute` opens `settings`, `clubBag`, `latestRound` (the newest saved round's scorecard), `trace` (a new course in the editor), or `edit:<course>` (that course in the editor).
- `GolfMapRoundRoute` set to `green` opens the green close-up once the round is showing.

Use defaults rather than launch arguments, because the round's background location session can relaunch the app without arguments. Write them into the app container's plist. `defaults write <bundle id>` inside the simulator creates a separate domain outside the container; the app still reads it, but it survives reinstalls and the UI-test reset, so a stray value there keeps redirecting launches. Clear it with `xcrun simctl spawn <device> defaults delete com.golfmapapp.golfMapFlutter`.

```sh
prefs="$(xcrun simctl get_app_container <device> com.golfmapapp.golfMapFlutter data)/Library/Preferences/com.golfmapapp.golfMapFlutter"
xcrun simctl spawn <device> defaults write "$prefs" GolfMapOpenCourse "Brackenridge Golf Course"
xcrun simctl location <device> set 29.451549,-98.476608
xcrun simctl launch --terminate-running-process <device> com.golfmapapp.golfMapFlutter
xcrun simctl spawn <device> defaults delete "$prefs" GolfMapOpenCourse
```

`scripts/seed_legacy_round.sh <device>` writes a Flutter-format saved round and clears the import marker, so the next launch exercises the Flutter data import.
