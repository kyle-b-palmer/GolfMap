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

# Watch app
xcodebuild -project GolfMap.xcodeproj -scheme GolfMapWatch \
  -destination 'generic/platform=watchOS Simulator' \
  -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO build
```

## Parity fixtures

`GolfKit/Tests/GolfCoreTests/Fixtures/parity_v1.json` is generated from the Flutter code:

```sh
flutter test test/parity/export_parity_fixtures_test.dart
```

Regenerate it only when a Flutter behavior change is intended, and fix the matching Swift code in the same change.

## Screenshots in the simulator

Debug builds open a course's round directly when the `GolfMapOpenCourse` default is set. Use a persistent default rather than a launch argument, because the round's background location session can relaunch the app without arguments.

```sh
xcrun simctl spawn <device> defaults write com.golfmapapp.golfMapFlutter GolfMapOpenCourse "Brackenridge Golf Course"
xcrun simctl location <device> set 29.451549,-98.476608
xcrun simctl launch --terminate-running-process <device> com.golfmapapp.golfMapFlutter
xcrun simctl spawn <device> defaults delete com.golfmapapp.golfMapFlutter GolfMapOpenCourse
```
