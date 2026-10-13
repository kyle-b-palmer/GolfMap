# GolfMap: full migration to native iOS and SwiftUI

Prepared October 13, 2026; revised the same day after a code-level review of the round screen, overlay widgets, and Apple companion targets. **Planning only; no refactor is implemented by this document.**

## Goal and saved baseline

Replace the Flutter phone app with an iOS app written in Swift, using SwiftUI for the interface and native Apple frameworks for maps, location, Watch communication, Live Activities, and health integration. Improve readability and interaction on the golf course while preserving the existing app's capabilities and user data.

The current Flutter app is saved on GitHub `main` at [checkpoint d6914c5](https://github.com/kyle-b-palmer/GolfMap/commit/d6914c5ed5882cd8937b03a57d00036bbfeeed27). That checkpoint includes the previously uncommitted app changes, including course tracing/import and Watch swing/IMU work. It is a source backup, not a claim that those changes passed functional testing. The neighboring `GPS_Parser` and `GolfCourseAPI` folders are separate untracked projects and are outside this app checkpoint.

This migration covers the complete phone app and its Apple companions. Android, web, Windows, Linux, and macOS are outside the new product scope. Retain their existing source in the Flutter baseline until native cutover is complete. Backend replacement, accounts, subscriptions, and new product features are separate work.

## What exists today

The phone uses Flutter Material 3 with custom dark panels. On iOS, a native Apple Maps background is synchronized to a Flutter map that owns golf overlays and interaction. Watch screens and Live Activity views already use SwiftUI.

| Area | Existing capabilities that must be accounted for | Native destination |
| --- | --- | --- |
| Home and course catalog | Search by state/city/course, grouped catalog, five favorites, commonly visited courses, saved rounds, traced courses, loading/error/retry states | SwiftUI home, searchable course list, round history, settings |
| Playing a round | Course/hole/tee selection, par and handicap, scoring, putts, score targets, hole locking, save/reopen/delete rounds | Round store, golf screen, scorecard and saved-round detail |
| Map and yardage | Course polygons, hole lines, tee-to-green orientation, GPS position, front/middle/back distances, signed bunker-edge distances, ideal lines, map background toggle, green close-up/target-flag behavior | Native map scene and shared geometry services |
| Shots and planning | Shot pins, lost-ball pins, measurement chains, select/drag/delete/undo, club aim, shot direction, historical dispersion, GPS simulation | Round actions and native map annotations/gestures |
| Club bag and weather | Editable carry distances, club suggestions and alternatives, driver eligibility, wind/temperature/elevation adjustments, cached weather | Swift models, club-bag editor, weather and recommendation services |
| Course editor | Pan/draw/walk/edit modes, vertex insert/drag/delete/undo, feature copy/move between holes, hole geometry/metadata, bundled/Supabase/OSM import and ranking, local save/delete, shared database upload, GeoJSON export | Native course editor, import and repository services |
| Sharing | Scorecard and round-recap images, statistics, system share flow | SwiftUI image rendering and iOS share sheet |
| Apple Watch | Score/putt/hole sync, local GPS yardage, swing detection, GPS pin/undo transfer, IMU session transfer, workout/runtime behavior, complications | Reuse existing Swift implementation and adapt phone integration |
| Live Activities | Lock-screen/Dynamic Island yardage and scoring, interactive intents, shared state, lifecycle cleanup | Direct ActivityKit and existing WidgetKit/App Intents code |
| Apple Health | Optional golf workout, availability/authorization, start/end preferences and modes | Native HealthKit service |

Source anchors: `lib/screens/`, `lib/widgets/`, `lib/services/`, `lib/models/`, `lib/utils/geo_utils.dart`, `ios/GolfMapWatch/`, `ios/GolfMapWatchWidget/`, `ios/GolfRoundWidget/`, and `ios/Runner/`.

`gps_to_green_screen.dart` is reachable from the round screen's map action panel. Preserve its green close-up, live GPS distance, draggable target flag, hole switching, and target reset as a native screen or sheet.

## Review findings that shape this plan

These were observed in the checkpoint source. They are reasons to change the design during the port, not just translate it.

### System

- **One screen owns the round.** `golf_map_screen.dart` is 3,077 lines with roughly 60 mutable state fields, 11 service instances, and 9 `GlobalKey`s used to measure overlay layout. Scoring, pins, GPS, weather, Live Activity sync, Health, and auto-advance logic are interleaved with view code. A line-by-line port would recreate the same coupling in SwiftUI.
- **Sync is polling.** While a round is active, the phone polls shared widget state every 300 ms and pushes GPS/Watch state every second (`golf_map_screen.dart`, `_startLiveActivityGpsTimer`). This costs battery and adds up to 300 ms latency to Live Activity score taps.
- **Shared models are duplicated.** `GolfRoundSharedState` and `GolfRoundGpsPin` are defined separately in `ios/GolfRoundWidget/LiveActivityShared.swift` and `ios/GolfMapWatch/GolfRoundWatchState.swift`, and have already diverged (only the Watch copy is `Equatable`). Each copy must be edited in lockstep today.
- **Events have no identity.** GPS pins carry hole, coordinates, kind, and an optional IMU session ID, but no event ID. The phone reconciles Watch undo requests against pins by hole and a 25-yard coordinate proximity. Duplicate delivery, two nearby shots, or out-of-order arrival can apply the wrong undo.
- **Location runs at maximum.** The round requests best accuracy with a 1 m distance filter for the whole round, regardless of whether the player is walking, stationary, or the app is backgrounded.
- **No automated safety net.** `test/widget_test.dart` is a placeholder, so no current test proves calculation, storage, or sync behavior.

### Visual and interaction

- **Yardage hierarchy is inverted.** The live GPS middle distance — the number a golfer most needs — renders at 13 pt inside a 52 pt-wide sidebar box, while PAR renders at 22 pt. Front/back labels are 8 pt.
- **Text is too small for outdoor use.** About 40% of literal font sizes in `lib/` are 11 pt or smaller, and 32 uses are 7–9 pt, often uppercase with letter spacing. All sizes are fixed, so Dynamic Type has no effect.
- **Secondary text lacks contrast.** Frequently used `#666666`/`#777777` labels measure about 3.3:1 against the dark panel color, below the 4.5:1 target for small text, and worse in direct sunlight.
- **Touch targets are small.** Sidebar icon buttons are about 52 × 36 pt, map action buttons about 38 × 38 pt, and the distance-sheet tee/pin/delete buttons about 28 pt tall — under the 44 pt minimum, while the user may be wearing a glove or walking.
- **Controls of different kinds share one rail.** The left rail can show up to 11 icon-only buttons in a scroll view: on-course actions (lock hole, club aim), map layers (Apple Maps, bunkers, dispersion), a preference (auto-advance), navigation (details, GPS to green), and a developer tool (GPS simulation, two buttons). Meaning is conveyed only by icon and tooltip, and tooltips are effectively unavailable on touch.
- **Selection relies on color alone.** Selected tees, active toggles, and selected shot rows differ mainly by tint.
- **No accessibility semantics.** There are no `Semantics` labels anywhere in `lib/`; map pins, yardages, and icon buttons are unlabeled for VoiceOver.
- **Screen sleeps mid-round.** Nothing keeps the display awake while the round screen is open.

## Product and UI direction

### Principles

1. **Yardage first.** The live middle distance is the largest element on the round screen, with front/back, plays-like, and suggested club beside it, plus a visible GPS quality indicator. Score and hole context stay one glance away.
2. **One place per kind of control.** On-course actions live in the bottom dock, map display options in one Layers menu, preferences in Settings, and test tools in a Developer section. Nothing is icon-only unless its meaning is universal (back, recenter, close), and every icon has an accessibility label.
3. **Explicit modes.** Playing, placing (aim point, simulated GPS), selecting (a pin or chain node), and editing (course tracing) each have a visible mode indicator and a contextual action bar with Done. A drag always has one clear meaning in the current mode.
4. **Native conventions.** System navigation, search, sheets with detents, menus, `confirmationDialog`, SF Symbols, semantic text styles, and haptics through `sensoryFeedback`. Keep the green golf identity through a small token set, not ad hoc hex values.
5. **Built for outdoor use.** Minimum 11 pt for any text and 17 pt for content text at default size. Text contrast at least 4.5:1, glyphs at least 3:1. 44 × 44 pt minimum hit areas. Support Dynamic Type through accessibility sizes, VoiceOver, Reduce Motion, Increase Contrast, and Bold Text. Keep the screen awake during an active round (with a setting to disable it).
6. **Review complete flows on a phone outside.** Compare home, active round, scorecard, saved-round review, club editing, and course tracing on an iPhone in sunlight. A language change alone does not establish better visual design or faster rendering.

### Proposed active-round layout

```text
┌────────────────────────────────────┐
│ ‹   Hole 7 ▾  Par 4 · Hcp 3     ⋯  │  header: hole menu, round menu
│     412 yd · Blue tees             │
│                                    │
│                                    │
│               map                  │
│                              [◎]   │  recenter
│                              [≋]   │  layers
│                                    │
│ ┌────────────────────────────────┐ │
│ │  148        F 139   B 157  ●GPS│ │  yardage dock (sheet, small detent)
│ │  plays 154 · 7 iron (or 6)     │ │
│ │  [ − ]   4   [ + ]   Putts 2   │ │
│ │  [        Mark shot         ]  │ │
│ └────────────────────────────────┘ │
└────────────────────────────────────┘
```

- **Header.** The hole title opens a hole grid; swipe on the header or use the dock to change holes. The `⋯` menu contains End Round (save/discard), Lock Hole, Scorecard, and Settings. Back and Save are no longer separate competing buttons.
- **Yardage dock.** A bottom sheet with detents that stays interactive with the map behind it. Small detent: middle distance at a large rounded, monospaced-digit size scaled with `@ScaledMetric`, front/back, plays-like, club, score/putt steppers, and Mark Shot. Medium detent: tees, bunkers, shot list, GPS to Green. This replaces the right-rail stat boxes, the details sheet tabs, and the bottom score panel.
- **Selection bar.** Selecting a pin or chain node swaps the dock's action row for "Shot 2 · 164 yd — Delete · Done", with haptic confirmation. This replaces the floating delete button.
- **Placement modes.** Club aim and simulated GPS show a banner ("Tap the map to set an aim point — Cancel"). Club aim may be set by long-press on the map; validate discoverability in the Phase 1 prototype.
- **GPS status.** Distinguish searching, reduced accuracy, stale (older than a threshold), denied, and simulated. Never show a GPS yardage as current when the fix is stale.

| Current control and location | Proposed home |
| --- | --- |
| Back and Save buttons (top bar) | Back plus End Round in the `⋯` menu, with Save/Discard confirmation |
| Hole picker (left rail), Next Hole (right rail) | Hole title menu, header swipe, and auto-advance |
| PAR, HCP, YDS stat boxes (right rail) | Header text |
| GPS front/middle/back, plays-like, club suggestion (right rail) | Yardage dock, primary row |
| Score panel (bottom) | Yardage dock steppers; full scorecard in a sheet |
| Lock hole (left rail) | `⋯` menu and scorecard |
| Club aim and clear aim (left rail) | Long-press or dock action with placement banner |
| Apple Maps layer, bunker distances, dispersion (left rail) | Layers menu |
| Auto-advance (left rail) | Settings |
| GPS test mode and placement (left rail) | Settings → Developer; hidden in App Store builds unless decided otherwise |
| Hole details, GPS to Green (left rail) | Dock medium detent and a green-flag action |
| Track shot, reset view (bottom left) | Mark Shot in the dock; recenter button |
| Delete selected pin (right rail) | Selection bar |

### Design system

Create a small `GolfDesign` layer in Phase 1 before building feature screens:

- **Color tokens** in the asset catalog with light, dark, and increased-contrast variants: fairway green (brand), measure blue, sand, hazard, destructive, surface/elevated surface, and primary/secondary text. Map overlays use solid or thick-material backgrounds for legibility over imagery.
- **Type ramp** based on semantic styles plus two custom display styles for yardage and score, all scaling with Dynamic Type and using monospaced digits so numbers do not shift as they change.
- **Spacing and shape**: a 4 pt spacing scale, a fixed set of corner radii, and a 44 pt minimum control size.
- **Components**: yardage readout, score stepper, GPS status badge, map control button, selection bar, placement banner, and empty/error states. Each has Xcode previews at default, accessibility-large, dark, light, and increased-contrast settings, which serve as the component gallery for design review.
- **Selection states** use shape or a symbol (checkmark, outline weight) in addition to color.

Apply the same tokens to the existing Watch, Live Activity, and complication views so the surfaces read as one product.

## Proposed native architecture

Create a separate native Xcode project under `native_ios/` within this app directory. Keep Flutter runnable during migration. A checked-in XcodeGen `project.yml` describes the phone, Watch app, Live Activity extension, Watch complication extension, and test targets; XcodeGen is available in the current development environment. Document generation/build steps and pin the tool version in CI. Use Swift 6 language mode with strict concurrency checking from the start, which is far cheaper than retrofitting later.

### Modules

Put shared code in one local Swift package, `native_ios/GolfKit`, consumed by every target. This removes the duplicated shared-state definitions and keeps Watch, widget, and phone on one wire format.

- **GolfCore** (phone, Watch, extensions): Codable data models, round state and actions, scoring, yardage/geometry, course matching, club recommendations, weather adjustments, and compatibility decoding. No UI or device-service imports, so it runs fast in unit tests.
- **GolfSync** (phone, Watch, extensions): shared round snapshot, event envelopes, protocol versioning, App Group storage, and cross-process change signaling.
- **GolfData** (phone): repositories for bundled/local/remote courses, saved rounds, settings, legacy import, and network clients.
- **GolfDesign** (phone, Watch, extensions): tokens and shared components described above.
- **App targets**: SwiftUI features — home/course browser, round/map, scorecard/history, club bag, course editor, and settings — plus Apple service adapters for CoreLocation, WatchConnectivity, ActivityKit/WidgetKit/App Intents, HealthKit, image rendering/sharing, and URLSession. Wrap UIKit components where native interaction requires them.

### Round state and actions

Model the round as a value type (`RoundState`) changed only through a closed set of actions (`RoundAction`: set score, add pin, move chain node, select hole, set aim, apply Watch event, and so on) by a pure function in GolfCore. An `@Observable`, main-actor `RoundStore` holds the current state, applies actions, and runs side effects (persist, sync, Live Activity update, Health) after each change.

This replaces the single 60-field screen object and gives four properties the current app lacks:

- Every rule (lost-ball stroke, lock, auto-advance) is unit-testable without a device or view.
- Phone, Watch, and App Intent changes all enter through the same action path, so conflict and duplicate handling live in one place.
- A uniform undo stack covers score, pin, chain, and aim changes instead of per-feature undo.
- The store can autosave after each action, which makes unfinished-round restoration nearly free (see decisions).

Views read derived values (current distances, totals, relative-to-par) from the store and send actions; they hold only transient UI state such as sheet detent and drag preview.

### Location

Use `CLLocationUpdate.liveUpdates` for the round and `CLBackgroundActivitySession` to keep updates while backgrounded. Request full accuracy while the round screen or a Live Activity is showing yardage, and relax the distance filter when movement is minimal or the app is backgrounded with no visible yardage. Publish a GPS quality value (accuracy radius, age, authorization, simulated) alongside each fix. Compare battery use per round against the Flutter baseline rather than assuming the native defaults are better.

### Map

MapKit supports SwiftUI maps, annotations, and camera control. Start with a focused feasibility test of selection, drag, hit testing, camera rotation, polygon overlays, and drawing before choosing between SwiftUI `Map` and an `MKMapView` wrapped in SwiftUI. The phone can be fully native Swift while using either renderer. [Apple: MapKit for SwiftUI](https://developer.apple.com/documentation/mapkit/mapkit-for-swiftui)

The course-only mode currently promises offline geometry without map tiles. Prove that behavior explicitly: evaluate a local replacement tile layer or a dedicated native course renderer with the same geometry/camera model. Do not make offline course display depend on Apple Maps cache availability. Apple Maps remains the online/background option; confirm whether any OSM background mode is still needed for the iOS product.

### Persistence

Store each saved round as its own versioned JSON file in Application Support with an index file, written atomically. Store traced courses as versioned GeoJSON-compatible files. Keep UserDefaults for small preferences and App Group defaults only for the cross-process round snapshot. This avoids rewriting one large blob for every change and isolates corruption to a single record. Do not introduce SwiftData as an additional migration in the first release.

### Observability

Use `os.Logger` with categories (location, sync, storage, map) and signposts around yardage computation, hole changes, and map overlay rebuilds. Subscribe to MetricKit for hang, launch, and energy diagnostics on TestFlight builds. Add a Developer settings screen with sync event log, GPS quality, and simulation controls, available in debug and TestFlight builds.

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

Current project settings use iOS 13 for the phone, iOS 18.2 for the Live Activity extension, and watchOS 10 for the Watch targets. **Proposed native minimum: iOS 18.2 and watchOS 10.** The architecture above depends on iOS 17+ APIs (Observation, `CLLocationUpdate`, `CLBackgroundActivitySession`, `sensoryFeedback`), so a lower minimum would require redesigning those pieces, not just adding availability guards. This would raise the phone's declared minimum and is a product decision to settle in Phase 0. Test both the chosen minimum and the latest supported OS.

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
2. Decode current and older record variants. Support ISO dates with optional fractional seconds, absent putts/pins/chains, legacy `yardsFromTee`, missing shot origins, default shot type, and legacy locked-hole inference. Retain IDs and ordering. Assign stable IDs to legacy pins that lack them, deterministically, so a retried import produces the same IDs.
3. Write the versioned native representation without deleting or rewriting original legacy data. Report corrupt entries and retain their original payload rather than silently replacing everything with an empty collection.
4. Verify record counts, round totals, course shapes, preferences, and representative values before recording migration completion. Retrying after interruption must not duplicate records.
5. Seed a real Flutter installation, update it with the native app, and verify the saved history and traced courses in the UI. Test fresh installs and partial/corrupt legacy stores too.

Maintain the current Supabase `golf_features` row contract and bundled-data-first behavior. Use URLSession REST clients or a deliberately chosen Swift SDK behind the repository interface. Preserve database/bundled/OSM course import, normalization, result ranking, coordinate handling, and useful network error states. Keep existing publishable configuration; this migration does not introduce privileged server credentials into the app.

Current upload obtains a maximum ID, deletes the course, then inserts rows. Characterize conflicts and partial failure; plan a separately reviewed server transaction/server-generated-ID change if reliability requires it. A UI port should not silently change backend ownership or overwrite rules.

Saved history currently omits some in-progress state, including active hole, selected tee, target score, and club aim. With the action-based store, autosaving the full `RoundState` after each action is a small addition. This plan recommends shipping unfinished-round restoration in the first native release; confirm in Phase 0 and keep it distinguishable from required saved-round compatibility.

## Phone, Watch, and widget state

Reuse the existing Watch SwiftUI screens, Watch GPS, swing detection/IMU models, runtime session, connectivity client, complications, and Live Activity attributes/views/intents where possible.

Move `GolfRoundSharedState`, `GolfRoundGpsPin`, and the IMU models into GolfSync, deleting the separate copies in `ios/GolfRoundWidget/LiveActivityShared.swift` and `ios/GolfMapWatch/GolfRoundWatchState.swift`. Preserve `sessionId`, revisions, selected hole, score/putt/par/handicap dictionaries, green coordinate, refresh revision, pending GPS pins/undos, and the existing Watch payload shape during the first parity release.

Replace the Flutter notification in `WatchConnectivityBridge.swift` with a native event delivery interface. Extract HealthKit logic from `HealthWorkoutBridge.swift`. Replace `live_activities` plugin calls and plugin-specific defaults payload setup with direct ActivityKit request/update/end handling. ActivityKit provides these lifecycle operations directly. [Apple: displaying live data with Live Activities](https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities)

### Event identity and protocol version

Add a protocol version field and give every cross-device event (score change, hole change, pin, undo, IMU session) an envelope: event ID (UUID), session ID, origin (phone, Watch, intent), and timestamp. Undo references the event ID of the pin it removes instead of matching coordinates within 25 yards. The phone keeps a bounded set of applied event IDs per session to drop duplicates and acknowledges applied IDs back to the Watch.

Ship this as protocol version 2. The native phone must still accept version 1 payloads (no IDs; fall back to today's proximity matching) until the Watch app installed alongside it is known to send version 2, because the phone and Watch may update at different times. Define which side wins for concurrent score/hole edits; the default proposal is last-writer-wins per hole field ordered by revision, with pins and undos as an append-only log that cannot conflict.

### Cross-process signaling

Replace the 300 ms and 1 s polling timers with change notifications. App Intents and the widget extension write the shared snapshot to the App Group, increment its revision, and post a Darwin notification; the phone observes it and reads only when the revision changed. The phone updates the Live Activity only when displayed content changes (yardage by at least one displayed unit, score, hole, or GPS status), because the system may throttle frequent Live Activity updates. An actor serializes work within the phone process but does not serialize widget-process writes to shared UserDefaults; use a revision compare-and-retry (or file coordination for a file-backed snapshot) and test concurrent writers.

### Lifecycle

Define lifecycle behavior for app foreground/background/relaunch, offline Watch/reconnection, expired or dismissed Live Activities, and intentional round ending. Current termination/dismissal cleanup can clear shared state; with round restoration, dismissing an activity must not discard a round the product intends to resume. Stop workouts and round location services once, according to that explicit policy.

## Implementation phases and completion gates

The phases below are future work. Each ends with a pushed commit/PR and a demonstrable completion gate. Each phase that adds UI also ends with a design review on a physical iPhone, including at least one accessibility text size and an outdoor check once the round screen exists.

### Phase 0 — establish behavior and decisions

Capture the current app's flows on device; produce a feature checklist and representative screenshots. Decide minimum OS, main-screen design, offline rendering, unfinished-round behavior, Watch protocol version 2 rollout, GPS simulation visibility, and upload semantics.

Build parity fixtures by running the existing Dart calculation code against bundled courses and synthetic inputs, and exporting expected outputs as JSON: green front/middle/back, signed bunker distances, plays-like adjustments, club suggestions, score totals/relative-to-par, hole stats, dispersion buckets, and legacy save decoding. The Swift tests in Phase 2 assert against these files. Do not commit personal location or workout data. Record baseline measurements on one device: cold launch to course list, hole switch time, and battery drain over a fixed simulated or walked route.

**Gate:** agreed feature inventory, screen direction (wireframes for home and active round based on the layout above), release/device matrix, exported parity fixtures, and baseline measurements. Record existing defects separately from intentional product behavior.

### Phase 1 — native project, design system, and map feasibility

Create the native project/targets, `GolfKit` package, signing/capabilities/version configuration, CI simulator build, and basic shell. Reuse assets. Build `GolfDesign` tokens and component previews. Prove native map rotation, overlays, coordinate conversion, hit testing, pin dragging, long-press placement, editor drawing, and offline course-only rendering on one bundled hole.

Build a thin playable slice on that hole: live GPS yardage dock, score stepper, and Mark Shot, using real location. Take it outside before committing to the layout.

**Gate:** phone/Watch/extensions build from shared GolfKit sources; a native app launches; the map experiment works without a Flutter engine and establishes the renderer decision; the yardage dock has been reviewed outdoors and at accessibility text sizes. Confirm embedding in an archive before proceeding to release work.

### Phase 2 — models, calculations, repositories, and legacy import

Port course/round/shot/chain/club models, parsing, geometry, catalog grouping/city lookup, hole statistics, scoring, club suggestion, and weather adjustment functions into GolfCore. Define `RoundState`, `RoundAction`, and the reducer. Implement storage/import and fixture-based repository clients. Port weather caching/timeout/fallback rules; continue displaying raw yardage when weather is unavailable.

**Gate:** all five bundled courses load with expected feature counts; legacy fixtures migrate without loss or duplication; all Phase 0 parity fixtures pass, with fixed-coordinate yardage within one displayed yard and any difference investigated. Do not use outdoor GPS variability as a calculation test.

### Phase 3 — home, saved rounds, and club bag

Implement native course browsing/search/grouping, favorites/visits, start-round selection, saved-round lists/detail/delete, club editing, and settings (including the Developer section). Connect migrated storage. Build clear loading, empty, error, and retry states using shared components.

**Gate:** a migrated saved round opens correctly; a user's traced course is discoverable; favorites, visit ranking, clubs, and settings survive relaunch. Verify large text and VoiceOver navigation on these flows.

### Phase 4a — core play loop

Implement `RoundStore`, the active-round layout, hole/tee selection, score/putt steppers, target scores, lock/advance rules, save/reopen, autosave/restore, keep-awake, CoreLocation with GPS quality states, front/middle/back distances, plays-like, club suggestion, and weather.

**Gate:** play, save, reopen, and restore an interrupted round with matching scores, putts, and locks; updating a saved round retains its ID/date. Verify partial-round totals and selected-tee/driver eligibility. Saving currently locks every course hole, including unscored holes; retain it or document an accepted change. Current automatic advancement requires more than 12 seconds inside the green; test GPS jitter, manual navigation, final-hole behavior, and re-entry. Distinguish denied, reduced-accuracy, stale, and unavailable location from a valid fix on device. Review the screen in sunlight and with large text.

### Phase 4b — shots, planning, and map tools

Add pins/lost balls, measurement chains with drag/select/delete/undo through the selection bar, club aim through the placement banner, bunker distances, ideal lines/direction, dispersion, the Layers menu, GPS simulation, and green close-up with a draggable/resettable target flag.

**Gate:** complete and reopen a round with matching pins and chains. Verify signed bunker distances, pin reordering, and neighboring-segment recalculation. Test score/pin coupling: lost-ball pins add one stroke, ordinary phone pin additions do not, and current deletion of any pinned shot subtracts a nonzero stroke. Characterize that asymmetry and cross-device undo before finalizing the actions. Exercise multiple holes and tees, undo, GPS loss, phone background/resume, offline mode, and simulation on device. Measure interaction responsiveness and battery use against the Phase 0 baseline.

### Phase 5 — Watch, Live Activities, Health, and sharing

Connect the round store to existing Watch and widget code through GolfSync; implement protocol version 2 with version 1 fallback, Darwin-notification signaling, native ActivityKit, and HealthKit services. Retain swing detection, GPS pin/undo handling, IMU transfer, complications, optional workout behavior, and update timing. Apply design tokens to Watch and Live Activity views. Render scorecard/recap images with accurate statistics and present the system share sheet.

**Gate:** score and change holes from phone, Watch, and Live Activity; Live Activity taps reflect on the phone without polling; reconcile duplicates/out-of-order events by event ID; pair a version 1 Watch build with the native phone and confirm fallback; reconnect an offline Watch; test background/relaunch/session end and activity dismissal without losing a restorable round. Verify IMU transfers and swing undo on paired hardware, workout permission denial and start/end behavior, complications, and exported image readability.

### Phase 6 — complete course tracing and import/upload

Implement hole-by-hole editor workflows: pan/draw/walk/edit modes (with a persistent mode indicator), course name/hole count, par/handicap, tee/fairway/green/bunker tools, polygon completion, vertex insertion/drag/deletion, point/shape selection and edits, feature copy/move between holes, undo/delete, local save/reopen, editing an existing course, and playback in the golf screen. Reuse the action/undo pattern from the round store for editor state. Preserve imported extra feature types. Implement database/bundled/OSM search/load, clone/rename, duplicate handling, upload/error flows, and GeoJSON export through native file/share presentation.

**Gate:** create a course, reopen/edit it, play a round on it, and verify serialized geometry. Confirm rotated/zoomed vertex drags, walk capture, edit cancellation, overwrite handling, and export/import round trips. Import from each source and test bad/incomplete geometry and network failures. Exercise upload against designated test records, verify row counts/geometry, and test failure recovery before using real shared courses.

### Phase 7 — upgrade validation, release, and cutover

Run the complete feature checklist, automated calculation/storage/reconciliation tests, focused UI smoke tests, release/archive checks, and a seeded Flutter-to-native upgrade on paired iPhone/Watch hardware. Conduct an outdoor round with location, Watch swing detection, background behavior, and battery measurements. Fix material regressions and review the final UI.

**Gate:** every required capability has evidence of parity, imported data is retained, same-identity upgrade works, Watch/extensions are embedded, the release archive has no Flutter dependency, and launch/battery measurements are no worse than the Phase 0 baseline. Distribute a native beta for review before production rollout. Replace the default app/build instructions only after acceptance; retire Flutter/cross-platform build machinery in a dedicated cleanup change while keeping the checkpoint/history recoverable.

Phase 3 and the Phase 6 editor can proceed in parallel after models and map primitives stabilize. GolfSync extraction can begin as soon as the event envelope is agreed, but final integration depends on the round store. The map, data importer, and three-surface synchronization are the main sources of schedule uncertainty; estimate the remaining migration after those experiments rather than promising a rewrite duration now.

## Verification and known questions

Automate the highest-risk contracts with Swift Testing: Dart-exported parity fixtures, legacy parsing/idempotent import, geospatial calculations, score totals, club/weather rules, course serialization, reducer rules (lost-ball stroke, lock, auto-advance, undo), and session/revision/duplicate reconciliation including version 1 fallback. Add rendering snapshot tests for the yardage dock, scorecard, and share images at default and accessibility text sizes in light and dark appearance. Use focused UI tests for start/play/save/reopen/restore and course edit/save. Simulator success does not establish GPS, Watch connectivity, Health permissions, swing detection, battery performance, or upgrade correctness on paired hardware.

Several behaviors need characterization before porting: dispersion bucketing currently includes raw latitude in its key; the recap's "longest drive" calculation can consider shots beyond the first shot; the editor replaces a same-hole/same-type draft shape even though imports can contain multiple bunkers/tees; and the first manual shot can use its own endpoint as origin when no user location exists. Treat corrections as explicit, fixture-backed behavior changes instead of accidental differences introduced by rewriting.

Decisions to resolve when implementation is authorized:

- Minimum iOS version (iOS 18.2 proposed; the architecture assumes iOS 17+ APIs).
- Accepted layouts, starting from the active-round wireframe above.
- Default appearance outdoors: dark only, light only, or system with a high-contrast option.
- Native offline renderer.
- Active-round restoration in the first release (recommended).
- GPS simulation visibility in App Store builds.
- Background GPS/Health ownership across phone and Watch.
- Protocol version 2 rollout and how long the phone accepts version 1.
- Whether upload transaction improvements are part of the first native release.

### Post-parity candidates (out of scope for the migration)

Recorded so they inform architecture without expanding the first release: detecting the course the player is standing on at round start, Home Screen and Lock Screen widgets for recent rounds, an App Intent/Siri shortcut to start a round at a favorite course, and round statistics trends across saved history.

## GitHub workflow and completion definition

- The saved Flutter checkpoint is on `main`. This document lives on `codex/ios-swiftui-migration-plan` for review; app implementation is unchanged by that branch.
- When implementation is requested, start native work from the accepted checkpoint/plan on a `codex/ios-swiftui` branch. Commit and push each completed work unit, including tests and build configuration, with PRs organized around the phase gates above.
- Keep the Flutter build available while the native replacement is incomplete. Use checkpoint `d6914c5` to restore the original source. Source rollback is distinct from user-data rollback; retained legacy values and versioned storage need their own tested recovery path.
- GitHub preserves committed source and bundled assets. Device-saved rounds, app preferences, remote database records, and Health data require their own preservation mechanisms; pushing source does not back them up.
- The migration is complete when a standalone native release replaces the existing iOS app, retains data and Apple companions, passes the entire feature/upgrade checklist, meets the Phase 0 performance baseline, and has an accepted UI. A prototype or a successful simulator build alone does not meet that definition.
