import Foundation
import Testing
@testable import GolfCore

@Suite("Legacy import")
struct LegacyImportTests {
    /// Every saved-round variant exported from the Flutter fixtures, as Flutter would store them.
    private var fixtureRoundsText: String {
        let inputs = (Fixtures.parity["savedRounds"]?.arrayValue ?? []).compactMap { $0["input"] }
        return JSONValue.array(inputs).compactText
    }

    @Test func emptyStoreImportsNothing() {
        let result = LegacyImport(LegacySnapshot(values: [:]))
        #expect(result.rounds.isEmpty)
        #expect(result.userCourseRows.isEmpty)
        #expect(result.clubBag == nil)
        #expect(result.corrupt.isEmpty)
        #expect(result.preferences == LegacyPreferences())
    }

    @Test func onlyPluginPrefixedKeysAreRead() {
        let snapshot = LegacySnapshot(prefixedValues: [
            "flutter.auto_advance_hole": .bool(false),
            "auto_advance_hole": .bool(true),
            "AppleLanguages": .string("en"),
        ])
        #expect(snapshot.values == ["auto_advance_hole": .bool(false)])
        #expect(LegacyImport(snapshot).preferences.autoAdvanceHole == false)
    }

    @Test func fixtureRoundsImportWithoutLoss() throws {
        let expected = try #require(Fixtures.parity["savedRounds"]?.arrayValue)
        let result = LegacyImport(LegacySnapshot(values: [LegacySnapshot.roundsKey: .string(fixtureRoundsText)]))
        #expect(result.corrupt.isEmpty)
        #expect(result.rounds.count == Set(expected.compactMap { $0["input"]?["id"]?.stringValue }).count)
        for round in result.rounds {
            let fixture = try #require(expected.first { $0["input"]?["id"]?.stringValue == round.id })
            #expect(round.totalStrokes == fixture["totalStrokes"]?.truncatedInt)
            #expect(round.legacyJSON().isEquivalent(to: fixture["expected"]!), "\(round.id)")
        }
        let dates = result.rounds.map(\.playedAt.date)
        #expect(dates == dates.sorted(by: >))
    }

    @Test func importIsDeterministic() {
        let snapshot = LegacySnapshot(values: [LegacySnapshot.roundsKey: .string(fixtureRoundsText)])
        let first = LegacyImport(snapshot)
        let second = LegacyImport(snapshot)
        #expect(first.rounds == second.rounds)
        let pinIDs = first.rounds.flatMap { $0.pinnedShots.values.flatMap { $0.map(\.id) } }
        #expect(Set(pinIDs).count == pinIDs.count)
    }

    @Test func corruptRoundsKeepTheirPayload() {
        let rounds = """
        [{"id":"good","courseName":"Brackenridge Golf Course","playedAt":"2025-03-01T09:30:00.000","scores":{"1":5}},
         {"id":"no-date","courseName":"Brackenridge Golf Course","scores":{"1":4}},
         "not a round",
         {"id":"good","courseName":"Duplicate","playedAt":"2025-03-02T09:30:00.000","scores":{}}]
        """
        let result = LegacyImport(LegacySnapshot(values: [LegacySnapshot.roundsKey: .string(rounds)]))
        #expect(result.rounds.map(\.id) == ["good"])
        #expect(result.rounds.first?.courseName == "Brackenridge Golf Course")
        #expect(result.corrupt.map(\.index) == [1, 2])
        #expect(result.corrupt[0].payload.contains("no-date"))
        #expect(result.issues.count == 1)
    }

    @Test func unreadableListIsRetainedWhole() {
        let result = LegacyImport(LegacySnapshot(values: [LegacySnapshot.roundsKey: .string("[{\"id\":")]))
        #expect(result.rounds.isEmpty)
        #expect(result.corrupt == [LegacyCorruptRecord(key: LegacySnapshot.roundsKey, index: nil, reason: "Not a JSON list", payload: "[{\"id\":")])
    }

    @Test func tracedCoursesKeepValidRowsVerbatim() {
        let rows = """
        [{"id":"user-1","feature_type":"green","hole_number":"1","course_name":"My Course",
          "geom":{"type":"Polygon","coordinates":[[[-98.1,29.1],[-98.1,29.2],[-98.2,29.2],[-98.1,29.1]]]}},
         {"id":"user-2","feature_type":"tee","hole_number":"1","course_name":"My Course",
          "geom":"{not json"}]
        """
        let result = LegacyImport(LegacySnapshot(values: [LegacySnapshot.userCoursesKey: .string(rows)]))
        #expect(result.userCourseRows.count == 1)
        #expect(result.userCourseRows.first?["id"]?.stringValue == "user-1")
        #expect(result.userCourseNames == ["My Course"])
        #expect(result.corrupt.map(\.index) == [1])
    }

    @Test func favoritesAndVisitCountsFollowFlutterRules() {
        let result = LegacyImport(LegacySnapshot(values: [
            LegacySnapshot.favoritesKey: .string(#"[" Brackenridge Golf Course ","",42]"#),
            LegacySnapshot.visitCountsKey: .string(#"{"Yaupon Golf Course":3,"Olmos Basin Golf Course":2.0}"#),
            LegacySnapshot.visitBootstrappedKey: .bool(true),
        ]))
        #expect(result.favorites == ["Brackenridge Golf Course", "42"])
        #expect(result.visitCounts == ["Yaupon Golf Course": 3, "Olmos Basin Golf Course": 2])
    }

    @Test func visitCountsBootstrapFromRoundsWhenFlutterHadNot() {
        let result = LegacyImport(LegacySnapshot(values: [
            LegacySnapshot.roundsKey: .string(fixtureRoundsText),
            LegacySnapshot.visitCountsKey: .string(#"{"Somewhere":9}"#),
        ]))
        #expect(result.visitCounts["Somewhere"] == nil)
        #expect(result.visitCounts.values.reduce(0, +) == result.rounds.count)
    }

    @Test func clubBagIsKeptOnlyWhenEdited() {
        let edited = LegacyImport(LegacySnapshot(values: [
            LegacySnapshot.clubBagKey: .string(#"[{"name":"DR","carryYards":250},{"name":"7I","carryYards":160}]"#),
        ]))
        #expect(edited.clubBag == [ClubDistance(name: "DR", carryYards: 250), ClubDistance(name: "7I", carryYards: 160)])
        #expect(LegacyImport(LegacySnapshot(values: [:])).clubBag == nil)
    }

    @Test func healthModeFallsBackToTheOlderToggle() {
        func mode(_ values: [String: LegacyValue]) -> HealthWorkoutMode {
            LegacyImport(LegacySnapshot(values: values)).preferences.healthWorkoutMode
        }
        #expect(mode([:]) == .always)
        #expect(mode(["health_workout_enabled": .bool(false)]) == .never)
        #expect(mode(["health_workout_mode": .string("ask"), "health_workout_enabled": .bool(false)]) == .ask)
        #expect(mode(["health_workout_mode": .string("unknown")]) == .always)
    }
}
