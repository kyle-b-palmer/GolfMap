# GolfMap: full migration to native iOS and SwiftUI

Prepared October 13, 2026. **Planning only; no refactor is implemented by this document.**

## Goal and saved baseline

Replace the Flutter phone app with an iOS app written in Swift, using SwiftUI for the interface and native Apple frameworks for maps, location, Watch communication, Live Activities, and health integration. Improve readability and interaction on the golf course while preserving the existing app's capabilities and user data.

The current Flutter app is saved on GitHub `main` at [checkpoint d6914c5](https://github.com/kyle-b-palmer/GolfMap/commit/d6914c5ed5882cd8937b03a57d00036bbfeeed27). That checkpoint includes the previously uncommitted app changes, including course tracing/import and Watch swing/IMU work. It is a source backup, not a claim that those changes passed functional testing. The neighboring `GPS_Parser` and `GolfCourseAPI` folders are separate untracked projects and are outside this app checkpoint.

This migration covers the complete phone app and its Apple companions. Android, web, Windows, Linux, and macOS are outside the new product scope. Retain their existing source in the Flutter baseline until native cutover is complete. Backend replacement, accounts, subscriptions, and new product features are separate work.

## What exists today

The phone uses Flutter Material 3 with custom dark panels. On iOS, a native Apple Maps background is synchronized to a Flutter map that owns golf overlays and interaction. Watch screens and Live Activity views already use SwiftUI.

| Area | Existing capabilities that must be accounted for | Native destination |
| --- | --- | --- |
| Home and course catalog | Search by state/city/course, grouped catalog, five favorites, commonly visited courses, saved rounds, traced courses, loading/error/retry states | SwiftUI home, searchable course list, round history, settings |
| Playing a round | Course/hole/tee selection, par and handicap, scoring, putts, score targets, hole locking, save/reopen/delete rounds | Round session model, golf screen, scorecard and saved-round detail |
| Map and yardage | Course polygons, hole lines, tee-to-green orientation, GPS position, front/middle/back distances, signed bunker-edge distances, ideal lines, map background toggle, green close-up/target-flag behavior | Native map scene and shared geometry services |
| Shots and planning | Shot pins, lost-ball pins, measurement chains, select/drag/delete/undo, club aim, shot direction, historical dispersion, GPS simulation | Round commands and native map annotations/gestures |
| Club bag and weather | Editable carry distances, club suggestions and alternatives, driver eligibility, wind/temperature/elevation adjustments, cached weather | Swift models, club-bag editor, weather and recommendation services |
| Course editor | Pan/draw/walk/edit modes, vertex insert/drag/delete/undo, feature copy/move between holes, hole geometry/metadata, bundled/Supabase/OSM import and ranking, local save/delete, shared database upload, GeoJSON export | Native course editor, import and repository services |
| Sharing | Scorecard and round-recap images, statistics, system share flow | SwiftUI image rendering and iOS share sheet |
| Apple Watch | Score/putt/hole sync, local GPS yardage, swing detection, GPS pin/undo transfer, IMU session transfer, workout/runtime behavior, complications | Reuse existing Swift implementation and adapt phone integration |
| Live Activities | Lock-screen/Dynamic Island yardage and scoring, interactive intents, shared state, lifecycle cleanup | Direct ActivityKit and existing WidgetKit/App Intents code |
| Apple Health | Optional golf workout, availability/authorization, start/end preferences and modes | Native HealthKit service |

Source anchors: `lib/screens/`, `lib/widgets/`, `lib/services/`, `lib/models/`, `lib/utils/geo_utils.dart`, `ios/GolfMapWatch/`, `ios/GolfMapWatchWidget/`, `ios/GolfRoundWidget/`, and `ios/Runner/`.

`gps_to_green_screen.dart` is reachable from the round screen's map action panel. Preserve its green close-up, live GPS distance, draggable target flag, hole switching, and target reset as a native screen or sheet.

## Product and UI direction

1. **Make yardage the primary information.** Show a large middle distance with clearly labeled front/back values, visible GPS status, and readable units. Keep score and hole context immediately available.
2. **Give the map room.** Keep common actions reachable with one hand. Put secondary settings, simulation, and detailed statistics in sheets or menus. Make editing and playing distinct modes so a drag has a clear purpose.
3. **Use native conventions.** Use system navigation, search, sheets, alerts, menus, controls, SF Symbols, and semantic text styles. Retain the green golf identity, with a consistent palette and spacing scale.
4. **Design for outdoor use.** Check contrast in sunlight, large text, VoiceOver labels, Reduce Motion, and touch targets of at least 44 points. Evaluate light/dark appearance rather than assuming the existing dark palette is always best.
5. **Review complete flows.** Compare home, active round, scorecard, saved-round review, club editing, and course tracing on an iPhone. A language change alone does not establish better visual design or faster rendering.

First design deliverable: reviewable layouts and interaction states for home and an active round, followed by the editor and secondary screens. These are a gate for later implementation, not deliverables added by this planning change.

## Proposed native architecture

Create a separate native Xcode project under `native_ios/` within this app directory. Keep Flutter runnable during migration. A checked-in XcodeGen `project.yml` can describe the phone, Watch app, Live Activity extension, Watch complication extension, and test targets; XcodeGen is available in the current development environment. Document generation/build steps and pin the tool version in CI.

Use these boundaries:

- **GolfCore:** Codable data models, round commands, scoring, yardage/geometry, course matching, club recommendations, weather adjustments, and compatibility decoding. Keep calculations independent of views and device services.
- **Persistence and repositories:** Bundled/local/remote courses, saved rounds, settings, legacy import, and network clients. Use versioned Codable storage for substantial local records and UserDefaults for small preferences; avoid introducing SwiftData as an additional migration in the first release.
- **RoundCoordinator:** The phone's observable session state and orchestration of location, save/load, Watch events, widget changes, and activity/workout lifecycle. Keep business logic out of SwiftUI view bodies.
- **Apple services:** CoreLocation, WatchConnectivity, ActivityKit/WidgetKit/App Intents, HealthKit, CoreMotion on Watch, image rendering/sharing, and URLSession.
- **SwiftUI features:** Home/course browser, round/map, scorecard/history, club bag, course editor, and settings. Wrap UIKit components where native interaction requires them.

MapKit supports SwiftUI maps, annotations, and camera control. Start with a focused feasibility test of selection, drag, hit testing, camera rotation, polygon overlays, and drawing before choosing between SwiftUI `Map` and an `MKMapView` wrapped in SwiftUI. The phone can be fully native Swift while using either renderer. [Apple: MapKit for SwiftUI](https://developer.apple.com/documentation/mapkit/mapkit-for-swiftui)

The course-only mode currently promises offline geometry without map tiles. Prove that behavior explicitly: evaluate a local replacement tile layer or a dedicated native course renderer with the same geometry/camera model. Do not make offline course display depend on Apple Maps cache availability. Apple Maps remains the online/background option; confirm whether any OSM background mode is still needed for the iOS product.

### App identity and supported versions

Preserve these production identifiers and the current signing team when testing an upgrade and shipping the replacement:

| Target/container | Existing identifier |
| --- | --- |
| iPhone | `com.golfmapapp.golfMapFlutter` |
| Apple Watch | `com.golfmapapp.golfMapFlutter.watchkitapp` |
| Watch complication | `com.golfmapapp.golfMapFlutter.watchkitapp.widget` |
| Live Activity extension | `com.golfmapapp.golfMapFlutter.GolfRoundWidget` |
| App Group | `group.com.golfmapapp.golfMapFlutter` |

The historical word `Flutter` in these identifiers does not require a Flutter runtime. Keeping identity is essential to testing replacement installs, retaining the phone sandbox, and retaining shared-container/companion relationships. App Groups share limited preferences through a suite-specific UserDefaults store. [Apple: configuring app groups](https://developer.apple.com/documentation/xcode/configuring-app-groups)

Current project settings use iOS 13 for the phone, iOS 18.2 for the Live Activity extension, and watchOS 10 for the Watch targets. **Proposed native minimum: iOS 18.2 and watchOS 10.** This would raise the phone's declared minimum and is a product decision to settle in Phase 0. If older iPhones must remain supported, define the lower minimum, availability guards, and reduced-feature behavior before choosing APIs. Test both the chosen minimum and the latest supported OS.

Replace `FLUTTER_BUILD_*`, `Generated.xcconfig`, Flutter scene/startup code, plugin registration, Flutter framework/package references, and Flutter build phases with native version/build settings and lifecycle code. Preserve icons, relevant permission strings, background capabilities, extension embedding, HealthKit/App Group entitlements, and companion metadata. An archive must contain the Watch app and extensions and no Flutter runtime.

For side-by-side UI experiments, a temporary development bundle family may be used. It cannot validate production data migration. Upgrade tests must install the native build over a seeded Flutter build with the same production identity and compatible signing, without uninstalling first.

## Data preservation and compatibility

The bundled course asset contains 820 rows across five courses: 704 Polygon geometries and 116 LineStrings. Decode the existing asset directly initially. Preserve longitude/latitude coordinate order, polygon rings/closure, optional par/handicap, null hole numbers, mixed numeric/string identifiers, `geom` supplied as an object or JSON string, and imported feature types such as water hazards and cart paths. Support imported MultiPolygon geometry as well. Preserve current hole-stat fallbacks and course matching rules rather than substituting blanket defaults.

The app uses the legacy SharedPreferences API. The installed plugin uses the `flutter.` key prefix and writes to iOS `UserDefaults.standard`; no prefix override was found in the app. Verify against a seeded installed build before shipping an importer.

| Logical legacy key(s) | Data to retain |
| --- | --- |
| `saved_golf_rounds` | IDs, dates, course names, scores, putts, shot pins, measurement chains, locked holes |
| `user_traced_course_features_v1` | Locally traced/imported course geometry and metadata |
| `favorite_courses` | Favorite order and five-course limit |
| `course_visit_counts`, `course_visit_bootstrapped` | Visit ranking and bootstrap status |
| `club_bag_json` | User-edited club names and carry distances |
| `show_score_target`, `ideal_line_enabled`, `map_overlay_enabled`, `auto_advance_hole`, `show_shot_dispersion`, `gps_sim_mode_enabled` | Display and interaction preferences |
| `health_workout_mode`, `health_workout_enabled`, `start_health_workout_with_round` | Current and legacy workout preferences |

Implement an idempotent importer in Phase 2:

1. Read the legacy keys from the existing phone defaults domain, including the verified physical prefix. Snapshot their original values before importing.
2. Decode current and older record variants. Support ISO dates with optional fractional seconds, absent putts/pins/chains, legacy `yardsFromTee`, missing shot origins, default shot type, and legacy locked-hole inference. Retain IDs and ordering.
3. Write the versioned native representation without deleting or rewriting original legacy data. Report corrupt entries and retain their original payload rather than silently replacing everything with an empty collection.
4. Verify record counts, round totals, course shapes, preferences, and representative values before recording migration completion. Retrying after interruption must not duplicate records.
5. Seed a real Flutter installation, update it with the native app, and verify the saved history and traced courses in the UI. Test fresh installs and partial/corrupt legacy stores too.

Maintain the current Supabase `golf_features` row contract and bundled-data-first behavior. Use URLSession REST clients or a deliberately chosen Swift SDK behind the repository interface. Preserve database/bundled/OSM course import, normalization, result ranking, coordinate handling, and useful network error states. Keep existing publishable configuration; this migration does not introduce privileged server credentials into the app.

Current upload obtains a maximum ID, deletes the course, then inserts rows. Characterize conflicts and partial failure; plan a separately reviewed server transaction/server-generated-ID change if reliability requires it. A UI port should not silently change backend ownership or overwrite rules.

Saved history currently omits some in-progress state, including active hole, selected tee, target score, and club aim. Reliable unfinished-round restoration is a proposed enhancement. Specify its fields and lifecycle in Phase 0 so it is distinguishable from required saved-round compatibility.

## Phone, Watch, and widget state

Reuse the existing Watch SwiftUI screens, Watch GPS, swing detection/IMU models, runtime session, connectivity client, complications, and Live Activity attributes/views/intents where possible.

Extract shared round models and storage from `ios/GolfRoundWidget/LiveActivityShared.swift` into a native shared module or shared target sources. Preserve `sessionId`, revisions, selected hole, score/putt/par/handicap dictionaries, green coordinate, refresh revision, pending GPS pins/undos, and the existing Watch payload shape during the first parity release.

Replace the Flutter notification in `WatchConnectivityBridge.swift` with a native event delivery interface. Extract HealthKit logic from `HealthWorkoutBridge.swift`. Replace `live_activities` plugin calls and plugin-specific defaults payload setup with direct ActivityKit request/update/end handling. ActivityKit provides these lifecycle operations directly. [Apple: displaying live data with Live Activities](https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities)

Define mutation rules explicitly: session isolation, replay/duplicate detection, pin/undo acknowledgement, and handling concurrent score/hole changes from phone, Watch, and App Intents. Preserve the wire protocol first; if it cannot handle a demonstrated conflict safely, version the change and define old/new phone-Watch compatibility. An actor serializes work within the phone process but does not, by itself, serialize widget-process writes to shared UserDefaults. Choose and test a cross-process reconciliation strategy.

Define lifecycle behavior for app foreground/background/relaunch, offline Watch/reconnection, expired or dismissed Live Activities, and intentional round ending. Current termination/dismissal cleanup can clear shared state; decide how that relates to the proposed round restoration feature. Ending an activity should not accidentally discard a round the product intends to resume. Stop workouts and round location services once, according to that explicit policy.

## Implementation phases and completion gates

The phases below are future work. Each ends with a pushed commit/PR and a demonstrable completion gate.

### Phase 0 — establish behavior and decisions

Capture the current app's flows on device; produce a feature checklist and representative screenshots. Decide minimum OS, main-screen design, offline rendering, unfinished-round behavior, and upload semantics. Build fixtures from bundled courses and synthetic legacy saves, without committing personal location/workout data. Existing `test/widget_test.dart` is a placeholder, so current tests do not prove parity.

**Gate:** agreed feature inventory, screen direction, release/device matrix, and fixtures with expected outputs. Record existing defects separately from intentional product behavior.

### Phase 1 — native project and map feasibility

Create the native project/targets, signing/capabilities/version configuration, shared-module structure, CI simulator build, and basic shell. Reuse assets. Prove native map rotation, overlays, coordinate conversion, hit testing, pin dragging, editor drawing, and offline course-only rendering on one bundled hole. Show the proposed yardage/control layout.

**Gate:** phone/Watch/extensions build; a native app launches; the map experiment works without a Flutter engine and establishes the renderer decision. Confirm embedding in an archive before proceeding to release work.

### Phase 2 — models, calculations, repositories, and legacy import

Port course/round/shot/chain/club models, parsing, geometry, catalog grouping/city lookup, hole statistics, scoring, club suggestion, and weather adjustment functions. Implement storage/import and fixture-based repository clients. Port weather caching/timeout/fallback rules; continue displaying raw yardage when weather is unavailable.

**Gate:** all five bundled courses load with expected feature counts; legacy fixtures migrate without loss or duplication; score/stat results match fixtures; fixed-coordinate yardage matches the baseline within one displayed yard, with differences investigated. Do not use outdoor GPS variability as a calculation test.

### Phase 3 — home, saved rounds, and club bag

Implement native course browsing/search/grouping, favorites/visits, start-round selection, saved-round lists/detail/delete, club editing, and settings. Connect migrated storage. Build clear loading, empty, error, and retry states.

**Gate:** a migrated saved round opens correctly; a user's traced course is discoverable; favorites, visit ranking, clubs, and settings survive relaunch. Verify large text and VoiceOver navigation on these flows.

### Phase 4 — complete on-course experience

Implement the round coordinator, hole/tee selection, score/putt controls, target scores, lock/advance rules, save/reopen, and CoreLocation. Add front/middle/back and bunker yardage, ideal lines/direction, pins/lost balls, measurement chains and all drag/select/delete/undo actions, club aim/suggestions, weather, dispersion, GPS simulation, and green close-up with a draggable/resettable target flag. Preserve background location use and distinguish denied, reduced-accuracy, stale, and unavailable location from a valid fix.

**Gate:** complete and reopen a round with matching scores, putts, pins, chains, and locks; updating a saved round retains its ID/date. Verify partial-round totals, selected tee/driver eligibility, signed bunker distances, pin reordering and neighboring-segment recalculation. Test score/pin coupling: lost-ball pins add one stroke, ordinary phone pin additions do not, and current deletion of any pinned shot subtracts a nonzero stroke. Characterize that asymmetry and cross-device undo before choosing native commands. Saving currently locks every course hole, including unscored holes; retain it or document an accepted change. Current automatic advancement requires more than 12 seconds inside the green; test GPS jitter, manual navigation, final-hole behavior, and re-entry. Exercise multiple holes and tees, undo, GPS loss, phone background/resume, offline mode, and simulation on device. Review the screen in sunlight and with large text. Measure interaction responsiveness and battery use against the Flutter baseline.

### Phase 5 — Watch, Live Activities, Health, and sharing

Connect native state to existing Watch and widget code; implement native ActivityKit and HealthKit services. Retain swing detection, GPS pin/undo handling, IMU transfer, complications, optional workout behavior, and update timing. Render scorecard/recap images with accurate statistics and present the system share sheet.

**Gate:** score and change holes from phone, Watch, and Live Activity; reconcile duplicates/out-of-order events; reconnect an offline Watch; test background/relaunch/session end and activity dismissal. Verify IMU transfers and swing undo on paired hardware, workout permission denial and start/end behavior, complications, and exported image readability.

### Phase 6 — complete course tracing and import/upload

Implement hole-by-hole editor workflows: pan/draw/walk/edit modes, course name/hole count, par/handicap, tee/fairway/green/bunker tools, polygon completion, vertex insertion/drag/deletion, point/shape selection and edits, feature copy/move between holes, undo/delete, local save/reopen, editing an existing course, and playback in the golf screen. Preserve imported extra feature types. Implement database/bundled/OSM search/load, clone/rename, duplicate handling, upload/error flows, and GeoJSON export through native file/share presentation.

**Gate:** create a course, reopen/edit it, play a round on it, and verify serialized geometry. Confirm rotated/zoomed vertex drags, walk capture, edit cancellation, overwrite handling, and export/import round trips. Import from each source and test bad/incomplete geometry and network failures. Exercise upload against designated test records, verify row counts/geometry, and test failure recovery before using real shared courses.

### Phase 7 — upgrade validation, release, and cutover

Run the complete feature checklist, automated calculation/storage/reconciliation tests, focused UI smoke tests, release/archive checks, and a seeded Flutter-to-native upgrade on paired iPhone/Watch hardware. Conduct an outdoor round with location, Watch swing detection, background behavior, and battery measurements. Fix material regressions and review the final UI.

**Gate:** every required capability has evidence of parity, imported data is retained, same-identity upgrade works, Watch/extensions are embedded, and the release archive has no Flutter dependency. Distribute a native beta for review before production rollout. Replace the default app/build instructions only after acceptance; retire Flutter/cross-platform build machinery in a dedicated cleanup change while keeping the checkpoint/history recoverable.

Phases 3 and the Phase 6 editor can proceed in parallel after models and map primitives stabilize. Apple integration extraction can begin after the shared-state contract is fixed, but final integration depends on the complete round coordinator. The map, data importer, and three-surface synchronization are the main sources of schedule uncertainty; estimate the remaining migration after those experiments rather than promising a rewrite duration now.

## Verification and known questions

Automate the highest-risk contracts: legacy parsing/idempotent import, geospatial calculations, score totals, club/weather rules, course serialization, and session/revision/duplicate reconciliation. Use focused UI tests for start/play/save/reopen and course edit/save. Simulator success does not establish GPS, Watch connectivity, Health permissions, swing detection, battery performance, or upgrade correctness on paired hardware.

Several behaviors need characterization before porting: dispersion bucketing currently includes raw latitude in its key; the recap's “longest drive” calculation can consider shots beyond the first shot; the editor replaces a same-hole/same-type draft shape even though imports can contain multiple bunkers/tees; and the first manual shot can use its own endpoint as origin when no user location exists. Treat corrections as explicit, fixture-backed behavior changes instead of accidental differences introduced by rewriting.

Decisions to resolve when implementation is authorized: minimum iOS version; accepted layouts; native offline renderer; active-round restoration policy; background GPS/Health ownership across phone and Watch; phone-Watch protocol compatibility across staggered updates; and whether upload transaction improvements are part of the first native release.

## GitHub workflow and completion definition

- The saved Flutter checkpoint is on `main`. This document lives on `codex/ios-swiftui-migration-plan` for review; app implementation is unchanged by that branch.
- When implementation is requested, start native work from the accepted checkpoint/plan on a `codex/ios-swiftui` branch. Commit and push each completed work unit, including tests and build configuration, with PRs organized around the phase gates above.
- Keep the Flutter build available while the native replacement is incomplete. Use checkpoint `d6914c5` to restore the original source. Source rollback is distinct from user-data rollback; retained legacy values and versioned storage need their own tested recovery path.
- GitHub preserves committed source and bundled assets. Device-saved rounds, app preferences, remote database records, and Health data require their own preservation mechanisms; pushing source does not back them up.
- The migration is complete when a standalone native release replaces the existing iOS app, retains data and Apple companions, passes the entire feature/upgrade checklist, and has an accepted UI. A prototype or a successful simulator build alone does not meet that definition.
