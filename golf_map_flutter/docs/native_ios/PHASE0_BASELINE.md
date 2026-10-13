# Phase 0 baseline

This records the behavior the native app must reproduce, the defects found while porting the calculations, and the Phase 0 items that still need a device. The plan is in [`../IOS_SWIFTUI_MIGRATION_PLAN.md`](../IOS_SWIFTUI_MIGRATION_PLAN.md).

## Status

| Gate item | Status |
| --- | --- |
| Parity fixtures | Done. `test/parity/export_parity_fixtures_test.dart` writes `native_ios/GolfKit/Tests/GolfCoreTests/Fixtures/parity_v1.json`. |
| Swift parity | Done for calculations. Every exported value matches exactly, including 983 sample points across 90 holes. |
| Feature inventory | Done (below). |
| Decisions | Proposed defaults adopted (below). Revisit before Phase 7. |
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

Each item must exist natively, or be explicitly dropped, before cutover.

**Home and catalog**
- [ ] Search by state, city, and course name
- [ ] Courses grouped by state and city
- [ ] Up to five favorites
- [ ] Commonly visited courses
- [ ] Saved rounds list with open, reopen, and delete
- [ ] Locally traced courses
- [ ] Loading, error, and retry states

**Round setup and scoring**
- [ ] Course, hole, and tee selection; preferred tee remembered
- [ ] Par and handicap display
- [ ] Score and putt entry with clamps (score 0–99, putts 0–9)
- [ ] Total score, relative to par, current relative to par
- [ ] Score target with strokes remaining
- [ ] Hole locking, lock all on save
- [ ] Auto-advance after more than 12 s on the green
- [ ] Save, reopen, and delete rounds

**Map and yardage**
- [ ] Course polygons and hole lines
- [ ] Tee-to-green rotation
- [ ] GPS position and play-area check (45 m)
- [ ] Green front, middle, and back
- [ ] Signed bunker-edge distances
- [ ] Planned shots and ideal line
- [ ] Map background toggle
- [ ] Green close-up with draggable target flag (`gps_to_green_screen.dart`)
- [ ] GPS simulation (developer only)

**Shots and planning**
- [ ] Shot pins from GPS and from the map
- [ ] Lost-ball pins (adds a stroke)
- [ ] Select, drag, delete (subtracts a stroke), and undo
- [ ] Measurement chains
- [ ] Club aim and shot direction
- [ ] Historical shot dispersion

**Club bag and weather**
- [ ] Editable carry distances; default 13-club bag
- [ ] Club suggestion with alternate club and driver eligibility
- [ ] Wind, temperature, and elevation adjustments; cached weather with fallback to raw yardage

**Course editor**
- [ ] Pan, draw, walk, and edit modes
- [ ] Vertex insert, drag, delete, and undo
- [ ] Copy or move features between holes
- [ ] Hole geometry and metadata editing
- [ ] Import from bundled data, Supabase, and OSM, with ranking
- [ ] Local save and delete; shared database upload; GeoJSON export

**Sharing**
- [ ] Scorecard and round-recap images with statistics
- [ ] System share sheet

**Apple Watch**
- [ ] Score, putt, and hole sync
- [ ] Local GPS yardage
- [ ] Swing detection and IMU session transfer
- [ ] GPS pin and undo transfer
- [ ] Workout runtime session
- [ ] Complications

**Live Activities**
- [ ] Lock Screen and Dynamic Island yardage and score
- [ ] Interactive intents
- [ ] Lifecycle cleanup when a round ends

**Apple Health**
- [ ] Optional golf workout with availability and authorization checks
- [ ] Start and end preferences

## Decisions

| Question | Decision for now |
| --- | --- |
| Minimum OS | iOS 18.2, watchOS 10 |
| Main-screen design | Active-round layout from the plan: header, yardage dock, selection bar, placement banner. The dock is a custom bottom panel rather than a system sheet, because a presented sheet blocks other presentations such as the End Round dialog. |
| Hole framing | Measure where the tee and green land after the first camera guess and correct, so the hole fits whatever space the dock leaves (dock size changes with Dynamic Type) |
| Offline rendering | Course overlays must render without map tiles |
| Unfinished round | Persist after every action and offer to resume on launch |
| Watch protocol v2 | Additive: optional `eventId` and `protocolVersion`; v1 peers fall back to proximity matching |
| GPS simulation | Hidden behind Developer settings |
| Upload semantics | Unchanged from Flutter until Phase 6 |

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

Fixed in the port (no fixture depends on them):

- An identified remote undo whose pin was already gone fell back to proximity and could delete a different pin. It now matches by event ID only.

## Pending device work

- Screenshots of every flow above in the Flutter build.
- Cold launch to course list, hole switch time, and battery drain over a fixed route, on one named iPhone model.
- Outdoor review of the Phase 1 yardage dock.
- Paired Watch checks for sync, pin transfer, and complications.
