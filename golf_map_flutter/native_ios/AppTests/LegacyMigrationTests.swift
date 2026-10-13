import Foundation
import GolfCore
import Testing
@testable import GolfMap

@MainActor
@Suite("Legacy migration")
struct LegacyMigrationTests {
    let defaults: UserDefaults
    let folder: URL

    init() {
        let suite = "legacy-migration-tests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        folder = FileManager.default.temporaryDirectory.appending(path: suite)
    }

    var migration: LegacyMigration {
        LegacyMigration(
            defaults: defaults,
            directory: folder.appending(path: "Legacy"),
            userCoursesURL: folder.appending(path: "Courses/user-courses.json")
        )
    }

    func repository() -> RoundRepository { RoundRepository(directory: folder.appending(path: "Rounds")) }

    static let rounds = """
    [{"id":"1712000000000","courseName":"Brackenridge Golf Course","playedAt":"2025-04-01T08:15:00.000",
      "scores":{"1":5,"2":4},"putts":{"1":2},
      "pinnedShots":{"1":[{"shotNumber":1,"latitude":29.4521,"longitude":-98.4766,"yardsFromTee":231}]}},
     {"id":"older/../id","courseName":"Olmos Basin Golf Course","playedAt":"2024-11-20T15:00:00Z","scores":{"1":6}},
     {"id":"broken","courseName":"Yaupon Golf Course"}]
    """

    static let courses = """
    [{"id":"user-1","feature_type":"green","hole_number":"1","course_name":"Backyard Links",
      "geom":{"type":"Polygon","coordinates":[[[-98.1,29.1],[-98.1,29.2],[-98.2,29.2],[-98.1,29.1]]]}}]
    """

    func seedFlutterStore() {
        defaults.set(Self.rounds, forKey: "flutter.saved_golf_rounds")
        defaults.set(Self.courses, forKey: "flutter.user_traced_course_features_v1")
        defaults.set(#"[{"name":"DR","carryYards":260},{"name":"PW","carryYards":125}]"#, forKey: "flutter.club_bag_json")
        defaults.set(false, forKey: "flutter.auto_advance_hole")
        defaults.set(true, forKey: "flutter.show_shot_dispersion")
        defaults.set(false, forKey: "flutter.health_workout_enabled")
        defaults.set(#"["Yaupon Golf Course"]"#, forKey: "flutter.favorite_courses")
    }

    @Test func freshInstallCompletesWithNothingToImport() throws {
        let outcome = try #require(migration.runIfNeeded(rounds: repository()))
        #expect(outcome == LegacyMigration.Outcome(completed: true))
        #expect(migration.runIfNeeded(rounds: repository()) == nil)
    }

    @Test func importsRoundsCoursesAndSettings() throws {
        seedFlutterStore()
        let rounds = repository()
        let outcome = try #require(migration.runIfNeeded(rounds: rounds))

        #expect(outcome.completed)
        #expect(outcome.importedRounds == 2)
        #expect(outcome.corruptRecords == 1)
        #expect(rounds.savedRounds.map(\.id) == ["1712000000000", "older/../id"])
        #expect(rounds.savedRounds.first?.pinnedShots["1"]?.first?.shotYards == 231)
        #expect(repository().savedRounds.count == 2)

        let courseData = try Data(contentsOf: migration.userCoursesURL)
        #expect(try FeatureRowDecoder.decode(courseData).map(\.courseName) == ["Backyard Links"])
        let corrupt = try String(contentsOf: migration.directory.appending(path: "corrupt.json"), encoding: .utf8)
        #expect(corrupt.contains("broken"))

        #expect(defaults.bool(forKey: SettingsKey.autoAdvanceHoles) == false)
        #expect(defaults.bool(forKey: SettingsKey.showShotDispersion))
        #expect(defaults.string(forKey: SettingsKey.healthWorkoutMode) == "never")
        #expect(ClubDistance.decodeBag(defaults.string(forKey: SettingsKey.clubBag)).map(\.carryYards) == [260, 125])
        #expect(defaults.stringArray(forKey: SettingsKey.favoriteCourses) == ["Yaupon Golf Course"])
    }

    @Test func legacyValuesAreLeftUntouched() throws {
        seedFlutterStore()
        migration.runIfNeeded(rounds: repository())
        #expect(defaults.string(forKey: "flutter.saved_golf_rounds") == Self.rounds)
        #expect(defaults.object(forKey: "flutter.auto_advance_hole") as? Bool == false)
        #expect(FileManager.default.fileExists(atPath: migration.directory.appending(path: "snapshot.json").path))
    }

    @Test func retryAfterInterruptionDoesNotDuplicateOrOverwrite() throws {
        seedFlutterStore()
        migration.runIfNeeded(rounds: repository())

        // Simulate an import that stopped before recording completion, after the user changed a setting.
        defaults.removeObject(forKey: LegacyMigration.completedKey)
        defaults.set(true, forKey: SettingsKey.autoAdvanceHoles)

        let rounds = repository()
        let outcome = try #require(migration.runIfNeeded(rounds: rounds))
        #expect(outcome.completed)
        #expect(outcome.importedRounds == 0)
        #expect(rounds.savedRounds.count == 2)
        #expect(defaults.bool(forKey: SettingsKey.autoAdvanceHoles))
    }

    @Test func unreadableRoundListIsKeptAndStillCompletes() throws {
        defaults.set("[{\"id\":", forKey: "flutter.saved_golf_rounds")
        let outcome = try #require(migration.runIfNeeded(rounds: repository()))
        #expect(outcome.completed)
        #expect(outcome.corruptRecords == 1)
        let corrupt = try String(contentsOf: migration.directory.appending(path: "corrupt.json"), encoding: .utf8)
        #expect(corrupt.contains("Not a JSON list"))
    }
}
