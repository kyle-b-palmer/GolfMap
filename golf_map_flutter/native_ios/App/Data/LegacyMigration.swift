import Foundation
import GolfCore
import os

/// One-time import of the Flutter app's `SharedPreferences` data. Legacy values are never modified or deleted,
/// so a failed or interrupted import can simply run again on the next launch.
@MainActor
struct LegacyMigration {
    struct Outcome: Equatable {
        var importedRounds = 0
        var legacyRounds = 0
        var userCourseRows = 0
        var corruptRecords = 0
        var completed = false
    }

    static let completedKey = "legacyImport.v1.completedAt"

    let defaults: UserDefaults
    let directory: URL
    let userCoursesURL: URL

    private static let logger = Logger(subsystem: "com.golfmapapp.golfMapFlutter", category: "legacy-import")

    init(
        defaults: UserDefaults = .standard,
        directory: URL = URL.applicationSupportDirectory.appending(path: "Legacy", directoryHint: .isDirectory),
        userCoursesURL: URL = CourseRepository.defaultUserCoursesURL
    ) {
        self.defaults = defaults
        self.directory = directory
        self.userCoursesURL = userCoursesURL
    }

    var isComplete: Bool { defaults.object(forKey: Self.completedKey) != nil }

    /// Returns nil when an earlier launch already completed the import.
    @discardableResult
    func runIfNeeded(rounds: RoundRepository) -> Outcome? {
        guard !isComplete else { return nil }
        let snapshot = Self.snapshot(of: defaults)
        guard !snapshot.isEmpty else {
            markComplete()
            return Outcome(completed: true)
        }

        let result = LegacyImport(snapshot)
        var outcome = Outcome(
            legacyRounds: result.rounds.count,
            userCourseRows: result.userCourseRows.count,
            corruptRecords: result.corrupt.count
        )
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try writeIfMissing(snapshot, to: directory.appending(path: "snapshot.json"))
            if !result.corrupt.isEmpty {
                try write(result.corrupt, to: directory.appending(path: "corrupt.json"))
            }
            outcome.importedRounds = rounds.importLegacy(result.rounds)
            if !result.userCourseRows.isEmpty {
                try FileManager.default.createDirectory(at: userCoursesURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try writeIfMissing(JSONValue.array(result.userCourseRows), to: userCoursesURL)
            }
            applySettings(result)
        } catch {
            Self.logger.error("Legacy import failed: \(error.localizedDescription)")
            return outcome
        }

        let missingRounds = result.rounds.filter { !rounds.hasSavedRound(id: $0.id) }.count
        let coursesStored = result.userCourseRows.isEmpty || FileManager.default.fileExists(atPath: userCoursesURL.path)
        guard missingRounds == 0, coursesStored else {
            Self.logger.error("Legacy import incomplete: \(missingRounds) rounds missing, courses stored: \(coursesStored)")
            return outcome
        }
        for issue in result.issues { Self.logger.notice("Legacy import: \(issue)") }
        Self.logger.info("Legacy import done: \(outcome.importedRounds) of \(outcome.legacyRounds) rounds written, \(outcome.userCourseRows) course rows, \(outcome.corruptRecords) corrupt entries kept")
        markComplete()
        outcome.completed = true
        return outcome
    }

    /// Native settings already set (for example by a previous, interrupted import) win.
    private func applySettings(_ result: LegacyImport) {
        let preferences = result.preferences
        setIfAbsent(preferences.autoAdvanceHole, SettingsKey.autoAdvanceHoles)
        setIfAbsent(preferences.showScoreTarget, SettingsKey.showScoreTarget)
        setIfAbsent(preferences.idealLineEnabled, SettingsKey.idealLineEnabled)
        setIfAbsent(preferences.mapOverlayEnabled, SettingsKey.courseOverlaysEnabled)
        setIfAbsent(preferences.showShotDispersion, SettingsKey.showShotDispersion)
        // Flutter's home toggle overrode the mode for rounds started from home; native has the mode only.
        let healthMode = preferences.startHealthWorkoutWithRound ? preferences.healthWorkoutMode : .never
        setIfAbsent(healthMode.rawValue, SettingsKey.healthWorkoutMode)
        setIfAbsent(preferences.gpsSimulationEnabled, SettingsKey.gpsSimulationEnabled)
        if let bag = result.clubBag { setIfAbsent(ClubDistance.encodeBag(bag), SettingsKey.clubBag) }
        if !result.favorites.isEmpty { setIfAbsent(result.favorites, SettingsKey.favoriteCourses) }
        if !result.visitCounts.isEmpty { setIfAbsent(result.visitCounts, SettingsKey.courseVisitCounts) }
    }

    private func setIfAbsent(_ value: Any, _ key: String) {
        if defaults.object(forKey: key) == nil { defaults.set(value, forKey: key) }
    }

    private func markComplete() {
        defaults.set(Date(), forKey: Self.completedKey)
    }

    private func writeIfMissing<Value: Encodable>(_ value: Value, to url: URL) throws {
        guard !FileManager.default.fileExists(atPath: url.path) else { return }
        try write(value, to: url)
    }

    private func write<Value: Encodable>(_ value: Value, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(value).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    /// Reads the plugin-prefixed values. Booleans are stored as `CFBoolean`, which `NSNumber` alone can't tell apart from 0 and 1.
    static func snapshot(of defaults: UserDefaults) -> LegacySnapshot {
        var values: [String: LegacyValue] = [:]
        for (key, value) in defaults.dictionaryRepresentation() where key.hasPrefix(LegacySnapshot.keyPrefix) {
            switch value {
            case let string as String:
                values[key] = .string(string)
            case let number as NSNumber where CFGetTypeID(number) == CFBooleanGetTypeID():
                values[key] = .bool(number.boolValue)
            case let number as NSNumber:
                values[key] = CFNumberIsFloatType(number) ? .double(number.doubleValue) : .int(number.intValue)
            default:
                logger.notice("Skipping legacy key \(key) of unsupported type")
            }
        }
        return LegacySnapshot(prefixedValues: values)
    }
}
