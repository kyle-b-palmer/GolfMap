# Phase 0 baseline

This records the behavior the native app must reproduce, the defects found while porting the calculations, and the Phase 0 items that still need a device. The plan is in [`../IOS_SWIFTUI_MIGRATION_PLAN.md`](../IOS_SWIFTUI_MIGRATION_PLAN.md).

## Status

| Gate item | Status |
| --- | --- |
| Parity fixtures | Done. `test/parity/export_parity_fixtures_test.dart` writes `native_ios/GolfKit/Tests/GolfCoreTests/Fixtures/parity_v1.json`. |
| Swift parity | Done for calculations. Every exported value matches exactly, including 983 sample points across 90 holes. |
| Feature inventory | Done (below). |
| Decisions | Proposed defaults adopted (below). Upgrade consequences (iOS 18.2 minimum, portrait-only iPhone) are listed in the release checklist. |
| Screenshots of current flows | Pending. Needs the Flutter build on a physical iPhone. |
| Baseline measurements | Pending. Needs a physical iPhone and a walked or simulated route. |
| Wireframes | The active-round layout in the plan is the working direction. Validate it outdoors with the Phase 1 slice. |

Regenerate fixtures after changing any Dart calculation:

```sh
cd golf_map_flutter
flutter test test/parity/export_parity_fixtures_test.dart
cd native_ios/GolfKit && swift test
```

## Fixture coverage

- **Course data:** bundled asset row decoding (820 rows), catalog grouping, nearest-city lookup, hole ordering, and hole stats.
- **Per hole:** green center, longest tee, tee options with yardages, orientation and map rotation, encirclement ring, and planned shots.
- **Per sample point:** green front/middle/back, back of green, signed bunker distances, near-hole, on tee box, in fairway, in green, in encirclement, GPS within play area, and distance outside the encirclement. Points are each tee, four points along the tee-to-green line, ±35 m off the midpoint, 20 m behind the green, and 2 km away.
- **Clubs and weather:** suggestions for −5 to 280 yards with and without the driver, plus a bag without a driver. Plays-like distances across a wind/temperature/elevation grid.
- **Saved rounds:** four legacy shapes (modern, pins without locks, scores only, empty lock list) and dispersion for one hole.

Scoring, pins, and undo are covered by `RoundEngineTests`, which encode the Flutter rules directly rather than through fixtures.

## Feature inventory

Each item must exist natively, or be explicitly dropped, before cutover. All of them exist in the native app; [`RELEASE_CHECKLIST.md`](RELEASE_CHECKLIST.md) lists the evidence for each and what still needs hardware.

**Home and catalog**
- [x] Search by state, city, and course name
- [x] Courses grouped by state and city
- [x] Up to five favorites
- [x] Commonly visited courses
- [x] Saved rounds list with open, reopen, and delete
- [x] Locally traced courses
- [x] Loading, error, and retry states

**Round setup and scoring**
- [x] Course, hole, and tee selection; preferred tee remembered
- [x] Par and handicap display
- [x] Score and putt entry with clamps (score 0–99, putts 0–9)
- [x] Total score, relative to par, current relative to par
- [x] Score target with strokes remaining
- [x] Hole locking, lock all on save
- [x] Auto-advance after more than 12 s on the green
- [x] Save, reopen, and delete rounds

**Map and yardage**
- [x] Course polygons and hole lines
- [x] Tee-to-green rotation
- [x] GPS position and play-area check (45 m)
- [x] Green front, middle, and back
- [x] Signed bunker-edge distances
- [x] Planned shots and ideal line
- [x] Map background toggle
- [x] Green close-up with draggable target flag (`gps_to_green_screen.dart`)
- [x] GPS simulation (developer only)

**Shots and planning**
- [x] Shot pins from GPS and from the map
- [x] Lost-ball pins (adds a stroke)
- [x] Select, drag, delete (subtracts a stroke), and undo
- [x] Measurement chains
- [x] Club aim and shot direction
- [x] Historical shot dispersion

**Club bag and weather**
- [x] Editable carry distances; default 13-club bag
- [x] Club suggestion with alternate club and driver eligibility
- [x] Wind, temperature, and elevation adjustments; cached weather with fallback to raw yardage

**Course editor**
- [x] Pan, draw, walk, and edit modes
- [x] Vertex insert, drag, delete, and undo
- [x] Copy or move features between holes
- [x] Hole geometry and metadata editing
- [x] Import from bundled data, Supabase, and OSM, with ranking
- [x] Local save and delete; shared database upload; GeoJSON export

**Sharing**
- [x] Scorecard and round-recap images with statistics
- [x] System share sheet

**Apple Watch**
- [x] Score, putt, and hole sync
- [x] Local GPS yardage
- [x] Swing detection and IMU session transfer
- [x] GPS pin and undo transfer
- [x] Workout runtime session
- [x] Complications

**Live Activities**
- [x] Lock Screen and Dynamic Island yardage and score
- [x] Interactive intents
- [x] Lifecycle cleanup when a round ends

**Apple Health**
- [x] Optional golf workout with availability and authorization checks
- [x] Start and end preferences

## Decisions

| Question | Decision for now |
| --- | --- |
| Minimum OS | iOS 18.2, watchOS 10 |
| Main-screen design | Active-round layout from the plan: header, yardage dock, selection bar, placement banner. The dock is a custom bottom panel rather than a system sheet, because a presented sheet blocks other presentations such as the End Round dialog. |
| Hole framing | Measure where the tee and green land after the first camera guess and correct, so the hole fits whatever space the dock leaves (dock size changes with Dynamic Type) |
| Offline rendering | Course overlays must render without map tiles |
| Unfinished round | Persist after every action. At launch, reopen it automatically if it changed in the last 12 hours; older rounds wait behind Resume on Home |
| Saving a round | Locks every course hole, including unscored ones, as Flutter does. Reopening a saved round keeps its ID and date and replaces the saved file |
| Score target | Flutter kept it in screen state, so it reset when the round reopened. The port stores it in the round (`nil` follows course par) |
| Watch protocol v2 | Additive: optional `eventId` and `protocolVersion`; v1 peers fall back to proximity matching |
| GPS simulation | Hidden behind Developer settings |
| Upload semantics | Same replace as Flutter (delete the course's rows, insert with IDs after the current maximum), but the deleted rows are read first and put back if the insert fails |
| Live Activity | Created on the first round update and ended when the round screen closes, as Flutter did; it returns when the round reopens. Updates that only change the yardage are throttled to one every 5 seconds |
| Health workout | One setting (Always, Ask each round, Never). A workout starts once per round session and never for a reopened round, then ends when the round is saved or discarded |
| Sharing | Scorecard and recap images render with `ImageRenderer` at 3x. Saving a round shows the recap with share buttons; saved rounds and the in-round scorecard share too |

## Existing defects

These are current behavior, not intended product rules. The port reproduces them so the fixtures match; fix each one deliberately and update its fixture when doing so.

1. **Front of green uses every green on the hole.** Estes Park hole 1 shows the front 22 yards from the tee while the middle is 487.
2. **Feature IDs are not unique.** Some rows share IDs such as `way/-1`, and tee lookup takes the first match.
3. **Missing par and handicap.** 386 of the 820 bundled rows have neither.
4. **Wrong city.** Estes Park is labeled Denver by the nearest-city lookup.
5. **Score merges use the maximum.** Watch and phone merges take the higher score, so a lowered score can be lost.
6. **Proximity matching.** Watch deduplication and undo match pins by distance (25 yards), so two nearby lost balls can undo the wrong pin. Protocol v2 event IDs fix this when both sides are native.
7. **Watch reads its own App Group.** `loadPhoneAppGroupState` on the Watch reads the Watch container, which never contains phone data.
8. **Lost-ball stroke is unclamped.** A phone lost-ball pin adds a stroke without the 99 limit.
9. **Non-numeric hole labels.** Flutter `holesForCourse` would crash on them; the Swift port sorts them after numeric holes.
10. **Altitude is dropped** when parsing geometry.
11. **Dispersion never groups nearby shots.** The bucket key includes the raw latitude, so shots only merge when their latitudes are identical and the 8-yard grid has no effect.
12. **Watch swing detection didn't compile.** On the checkpoint the swing detector's callback passed an IMU session that `GolfRoundWatchViewModel` didn't accept. The native Watch target saves the session and passes its ID to `recordDetectedSwing`.

13. **Wind direction is reversed in plays-like.** Open-Meteo reports the direction wind blows from, but the formula treats it as the direction it blows toward: a north wind shortens a northbound shot. The port reproduces this (see `WeatherTests`); fix it in both places together.
14. **Club suggestion can target the last pin.** Once a hole has a tracked shot, Flutter measures the suggestion from the player to that pin. After Mark Shot the player is standing on it, so the suggestion collapses. The port always targets the middle of the green.

Fixed in the port (no fixture depends on them):

- An identified remote undo whose pin was already gone fell back to proximity and could delete a different pin. It now matches by event ID only.
- Auto-advance on the final green wrapped to hole 1 after 12 seconds, moving a player who was still putting out. It now stops on the final hole; the Next button still wraps.
- Without a location fix, Flutter's measurement chain never measured its segments, so every segment read zero. The port measures from the selected tee until a fix arrives. With a fix, it measures from the player as Flutter does.
- Flutter had two health controls: a home-screen "Apple Health workout" toggle that decided for rounds started from home, and the Always/Ask/Never mode that only applied elsewhere. The port keeps the mode only; a Flutter user who had the home toggle off imports as Never.
- Flutter ended the health workout whenever the round screen closed, so glancing at the course list cut a workout short and it didn't restart. The port keeps it running until the round is saved or discarded.
- Drawing a tee or bunker deleted every other tee or bunker on that hole, although holes have several and imports keep them. Only greens and fairways replace; moving or copying follows the same rule (Flutter already exempted bunkers there).
- The editor's Par and Hcp fields only took effect when a green was drawn, so changing par on an imported hole did nothing. They now update the hole's greens directly.
- Renaming a new course kept the old name on features traced before the rename, so the save filed them under the old name and the GeoJSON export left them out. Every feature now takes the current name.
- An OpenStreetMap search failure failed the whole course search, hiding database and built-in matches. It's now reported only when nothing else matched.
- Closing the editor discarded unsaved work without asking; it now confirms. Saving the course with a shape edit in progress asks to save or discard that edit first.
- Flutter drew the ideal line from the player whenever they were within 1,200 yards of any point on the hole, so a player on another hole got a long line across the course. The port hides it when the player is more than 1,000 yards from the green; yardages and measuring still work out to Flutter's 1,200.
- Flutter's "map overlay" setting (Map under course) is gone. Off, it covered the map with a plain background polygon, and after a hole change that polygon could draw over the course, leaving a green screen with only the flag. The map is now Satellite or Map, one choice; the imported Flutter value is ignored.
- A hole's score starts at its par instead of 0, and Submit score keeps it (par if untouched), locks the hole, and moves to the next hole. An untouched hole still counts as unscored in totals. A lost ball on an unscored hole counts from par.
- A locked hole only rejected pins while it was the hole on screen, so a Watch or Live Activity pin could still land on an earlier locked hole. Locked holes now reject pins and remote undo from any source.
- The native targets' entitlements files were empty because XcodeGen regenerates them from `project.yml`; the App Group and HealthKit entitlements now live there, matching Flutter's targets.

## Pending device work

- Screenshots of every flow above in the Flutter build.
- Cold launch to course list, hole switch time, and battery drain over a fixed route, on one named iPhone model.
- Outdoor review of the Phase 1 yardage dock.
- Paired Watch checks for sync, pin transfer, and complications. The phone session only sends when a Watch is paired with the app installed, so the simulator never exercises it.
- Live Activity content on device: the simulator confirms the activity starts (`liveactivitiesd` logs "Created activity"), but unsigned simulator builds have no App Group, so the widget can't read hole, score, or yardage. Check the Lock Screen and Dynamic Island on a signed device build, including the score buttons and the end of the activity when the round is saved.
- Course editor on device: freehand drawing with one finger while pinching to zoom (a pinch can add a stray point; Undo removes it), dragging vertices at several zoom levels, and Walk mode outdoors. Then trace a course, save it, reopen it, and play a round on it.
- Upload against designated test records once Supabase is restored: replace a test course, check row counts and geometry in the table, and force an insert failure to confirm the old rows come back. The stubbed tests cover the request sequence and the restore.
- HealthKit on device: the permission prompt, a golf workout appearing in Health after saving, and the Ask prompt. Simulator builds aren't signed with the HealthKit entitlement.
- Supabase: `xycsxghpvylyquigzdje.supabase.co` did not resolve on 2026-10-13 (likely a paused project). The bundled data covers every current course, but the remote fallback and course uploads need the project restored before they can be checked live.
- Seed a Flutter install with saved rounds, traced courses, and settings, then install the native build over it and check the import in the UI. In the simulator, `scripts/seed_legacy_round.sh` has confirmed a Flutter-format round imports and opens on the scorecard; the device check still needs a real Flutter install.
- Map dragging on device: measure points, the club target, the green close-up flag, and editor vertices. Drags used to be gestures on the map annotations, which never received them (the UI tests caught this). They're now recognized on the map, which finds the point under the finger and stops panning until release. The simulator UI tests confirm the measure point, flag, and vertex follow the finger while the map holds still; check by hand at several zoom levels and rotations.
- Offline rendering: in Airplane Mode on a course whose tiles were never cached, confirm the course shapes, pins, and yardages still show over the blank map.
- Location states on device: deny access, turn off Precise Location, and walk out of coverage to confirm the dock's Searching, Approximate, GPS lost, and Location off states and their recovery text. Auto-advance (more than 12 seconds inside the green) needs an outdoor check for jitter at the green edge and on the last hole.
