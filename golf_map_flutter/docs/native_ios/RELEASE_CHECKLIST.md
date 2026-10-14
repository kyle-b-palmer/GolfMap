# Release checklist

Status of the Phase 7 gate in [`../IOS_SWIFTUI_MIGRATION_PLAN.md`](../IOS_SWIFTUI_MIGRATION_PLAN.md). Every capability in the [feature inventory](PHASE0_BASELINE.md#feature-inventory) exists natively; this records the automated evidence for each and what still needs hardware. Simulator results don't establish GPS, Watch connectivity, Health, swing detection, battery, or upgrade behavior on paired devices.

Test names below are Swift Testing functions (`swift test` in `GolfKit`, scheme `GolfMap`) or UI tests (scheme `GolfMapUITests`). CI runs all of them, the Watch build, and the archive check on every push to `codex/ios-swiftui` (`.github/workflows/native-ios.yml`).

## Capabilities

**Home and catalog**

| Capability | Evidence | Still needs hardware |
| --- | --- | --- |
| Search, grouping by state and city | `courseCatalogMatches` (Flutter fixture); UI tests search before every round | — |
| Five favorites, commonly visited | `favoritesPersistAndStopAtFive`, `favoritesAreNewestFirstAndCappedAtFive`, `commonlyVisitedPrefersSavedRoundsThenViews`, `visitsRankBehindSavedRounds` | — |
| Saved rounds: open, reopen, delete | UI `testPlaySaveAndReopenRound`; `reopeningASavedRoundKeepsItsIdentityAndDate` | — |
| Traced courses on Home | UI `testTraceEditSaveAndPlayCourse` | — |
| Loading, error, retry | `repositoryFallsBackToSupabaseWithoutTheBundledAsset`, `serverErrorsSurface` | Live Supabase once restored |

**Round setup and scoring**

| Capability | Evidence | Still needs hardware |
| --- | --- | --- |
| Hole and tee selection, par and handicap | `holeCalculationsMatch` (983 sample points, 90 holes); UI tests move between holes | — |
| Score and putt clamps, totals, relative to par | `scoresAndPuttsAreClamped`, `totalsMatchFlutterRules`; UI steppers | — |
| Score target | `interruptedRoundRestoresFromDisk` keeps it through a restore | — |
| Lock all on save, reopen | `savingLocksEveryHoleAndKeepsIdentity`, `finishingSavesLockedRoundAndClearsShared`; UI checks the reopened hole is locked | — |
| Auto-advance after 12 s on the green | `autoAdvanceNeedsMoreThanTwelveSecondsOnGreen`, `autoAdvanceWaitsOnTheGreenAndStopsOnTheLastHole` | Outdoor jitter at the green edge and on the last hole |
| Restore an interrupted round | `interruptedRoundRestoresFromDisk`; UI `testInterruptedRoundRestoresAtLaunch` (kills and relaunches the app) | Relaunch by the background location session |

**Map and yardage**

| Capability | Evidence | Still needs hardware |
| --- | --- | --- |
| Front, middle, back; play area; rotation | `holeCalculationsMatch` | Outdoor dock review in sunlight and at large text |
| Signed bunker distances, planned shots, ideal line | `holeCalculationsMatch` | — |
| GPS states (searching, approximate, lost, off) | `gpsStatusClassification`, `gpsStatusOnlyAllowsCurrentPreciseFixes` | Deny access, turn off Precise Location, walk out of coverage |
| Satellite or map style | One choice in Layers and Settings | Airplane Mode on an uncached course: the course shapes still draw |
| Green close-up with draggable flag | UI `testGreenCloseUpFlagDrags` | Drag at several zooms and rotations |
| GPS simulation (Developer) | Settings and round menu | — |

**Shots and planning**

| Capability | Evidence | Still needs hardware |
| --- | --- | --- |
| Pins, lost ball, delete and renumber | `lostBallAddsStrokeButOrdinaryPinDoesNot`, `deletingAnyPinSubtractsAStrokeAndRenumbers`, `lockedHoleRejectsPinsAndDeletes` | Mark Shot from a real fix |
| Measurement chains | `segmentsRunFromThePlayerThroughEachPoint`, `movingOrDeletingRemeasuresNeighbors`, `savingMergesChainPointsIntoPinsWithoutDuplicates`; UI `testMeasurePointDragsWithoutPanningTheMap` | — |
| Club aim | `clubTargetNeedsAnUnlockedHole` | — |
| Dispersion | `legacySavedRoundsDecode` (Flutter dispersion fixture) | — |

**Club bag and weather**

| Capability | Evidence | Still needs hardware |
| --- | --- | --- |
| Carry distances, suggestions, driver eligibility | `clubSuggestionsMatch`, `clubBagRowsFollowTheFlutterEditor`, `driverNeedsTheTeeAndNoTrackedShots` | — |
| Plays-like with cached weather and fallback | `playsLikeMatches`, `cacheIsFreshFor15MinutesWithin500Meters`, `failuresFallBackToTheLastReading`, `noReadingMeansRawYardage` | — |

**Course editor**

| Capability | Evidence | Still needs hardware |
| --- | --- | --- |
| Draw (taps and freehand), commit, edit vertices | Course draft suite; UI `testTraceEditSaveAndPlayCourse` draws by tap and stroke and drags a vertex | Drawing while pinching; Walk mode outdoors |
| Move or copy between holes, par and handicap | `moveAndCopyBetweenHoles`, `greensReplaceAndCarryTheHoleParButBunkersAccumulate`, `holesStayInRangeAndShowTheirPar` | — |
| Save, reopen, play | `seedsFromBuiltInDataWhenTheDatabaseFailsThenSavesAndReopens`, `savingOverAnotherLocalCourseAsksFirst`; UI test saves, reopens, and starts a round on the traced course | — |
| Import from database, built-in, OpenStreetMap | Course import suite, `osmSearchFallsBackAcrossOverpassServers`; live Nominatim and Overpass queries checked on 2026-10-13 | Import on a phone network |
| Upload with restore on failure; GeoJSON export | `uploadReplacesRemoteRowsAndRestoresThemOnFailure`, `renamingStampsEveryFeatureAndExportsGeoJSON` | Upload against test records once Supabase is restored |

**Sharing**

| Capability | Evidence | Still needs hardware |
| --- | --- | --- |
| Scorecard and recap images | `bothCardsRenderAtThreeTimesScale`, Round recap suite | Readability on a phone; the share sheet's targets |

**Apple Watch, Live Activities, Health**

| Capability | Evidence | Still needs hardware |
| --- | --- | --- |
| Score, putt, hole, pin, and undo sync (protocol v2 with v1 fallback) | Sync protocol suite, `duplicateEventIDsAreIgnored`, `remoteUndoPrefersEventIDOverProximity`, `deletingPinPublishesIdentifiedUndo` | Paired Watch, including a v1 Watch build and reconnecting after offline |
| Watch GPS, swing detection, IMU transfer, runtime session, complications | Watch target builds in CI | Paired Watch on the course |
| Live Activity content and intents | `liveActivityEditsAreApplied`, `companionsFollowTheRound`; simulator logs show the activity starts | Signed build: Lock Screen, Dynamic Island, score buttons, end on save |
| Health workout (Always, Ask, Never) | `homeHealthToggleOffMeansNever`, `healthModeFallsBackToTheOlderToggle` | Permission prompt, denial, workout in Health after saving |

## Release and upgrade

| Gate | Status |
| --- | --- |
| Same identity as the Flutter app | Done. `com.golfmapapp.golfMapFlutter` with the same widget, Watch, and complication IDs, App Group, and HealthKit entitlement. |
| Upgrade version | Done. 2.0.0 (1), above Flutter's 1.0.0 (1). Raise the build number for each upload. |
| Watch and extensions embedded, no Flutter | Done. `scripts/check_archive.sh` passes on an unsigned Release archive and runs in CI. |
| Imported data retained | Legacy migration and legacy import suites; `scripts/seed_legacy_round.sh` in the simulator. Needs a real Flutter install upgraded in place. |
| Signed archive and TestFlight | Needs the team's signing identity and App Store Connect. |
| Launch time and battery against the Phase 0 baseline | Needs the Phase 0 measurements, which were never taken on device. |

Upgrade consequences to accept before release:

- The native app requires iOS 18.2. The Flutter app ran on iOS 13 and later, so players on older systems keep the Flutter version and stop receiving updates.
- iPhone layout is portrait only. Flutter also allowed landscape, which the round screen and dock weren't designed for. iPad keeps every orientation.

## Hardware sign-off

Run these on a paired iPhone and Apple Watch with a signed build:

1. Install the Flutter build, play and save rounds, trace a course, change settings, then install the native build over it. Check saved rounds, traced courses, favorites, club bag, and settings in the UI.
2. Play a round outdoors: dock legibility in sunlight and at large text, the four GPS states and their recovery, auto-advance on the green and on the last hole, Mark Shot, and the background location session.
3. Map gestures: measure point, club target, green flag, and editor vertices at several zoom levels and rotations; drawing while pinching; Walk mode.
4. Watch: score and hole sync both ways, GPS pins and undo, swing detection and IMU transfer, complications, reconnecting after the Watch is offline, and a v1 Watch build against the native phone.
5. Live Activity: Lock Screen and Dynamic Island content, score buttons reflected on the phone without opening it, ending when the round is saved, and a dismissed activity not discarding a restorable round.
6. Health: permission prompt, denial, Ask prompt, and a golf workout in Health after saving.
7. Offline: Airplane Mode on a course whose tiles were never cached; the course shapes, pins, and yardages should still show.
8. Measurements on one named iPhone model: cold launch to the course list, hole switch time, and battery over a fixed route, for both the Flutter and native builds.
9. Once the Supabase project is restored: remote fallback with the bundled asset removed, and upload against designated test records, including a forced insert failure.
