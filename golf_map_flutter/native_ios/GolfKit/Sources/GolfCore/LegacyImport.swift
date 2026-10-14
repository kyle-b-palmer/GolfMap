import Foundation

/// A value read from the Flutter `SharedPreferences` store.
public enum LegacyValue: Sendable, Hashable, Codable {
    case string(String)
    case bool(Bool)
    case int(Int)
    case double(Double)

    var string: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    var bool: Bool? {
        if case .bool(let value) = self { return value }
        return nil
    }
}

/// The Flutter app's preference values, keyed by logical key (without the plugin's `flutter.` prefix).
public struct LegacySnapshot: Sendable, Hashable, Codable {
    /// Prefix the `shared_preferences` iOS plugin adds to every key in `UserDefaults.standard`.
    public static let keyPrefix = "flutter."

    public static let roundsKey = "saved_golf_rounds"
    public static let userCoursesKey = "user_traced_course_features_v1"
    public static let favoritesKey = "favorite_courses"
    public static let visitCountsKey = "course_visit_counts"
    public static let visitBootstrappedKey = "course_visit_bootstrapped"
    public static let clubBagKey = "club_bag_json"

    public var values: [String: LegacyValue]

    public init(values: [String: LegacyValue]) {
        self.values = values
    }

    /// Keeps only plugin-prefixed keys and strips the prefix.
    public init(prefixedValues: [String: LegacyValue]) {
        var values: [String: LegacyValue] = [:]
        for (key, value) in prefixedValues where key.hasPrefix(Self.keyPrefix) {
            values[String(key.dropFirst(Self.keyPrefix.count))] = value
        }
        self.values = values
    }

    public var isEmpty: Bool { values.isEmpty }

    func string(_ key: String) -> String? { values[key]?.string }
    func bool(_ key: String) -> Bool? { values[key]?.bool }
}

public enum HealthWorkoutMode: String, Sendable, Hashable, Codable, CaseIterable {
    case always
    case ask
    case never

    public init(storage: String?) {
        switch storage {
        case "ask": self = .ask
        case "never": self = .never
        default: self = .always
        }
    }
}

/// Display and interaction preferences, with Flutter's defaults.
public struct LegacyPreferences: Sendable, Hashable, Codable {
    public var showScoreTarget = true
    public var idealLineEnabled = true
    public var mapOverlayEnabled = true
    public var autoAdvanceHole = true
    public var showShotDispersion = false
    public var healthWorkoutMode = HealthWorkoutMode.always
    public var startHealthWorkoutWithRound = true
    public var gpsSimulationEnabled = false

    public init() {}

    init(_ snapshot: LegacySnapshot) {
        showScoreTarget = snapshot.bool("show_score_target") ?? true
        idealLineEnabled = snapshot.bool("ideal_line_enabled") ?? true
        mapOverlayEnabled = snapshot.bool("map_overlay_enabled") ?? true
        autoAdvanceHole = snapshot.bool("auto_advance_hole") ?? true
        showShotDispersion = snapshot.bool("show_shot_dispersion") ?? false
        if let mode = snapshot.string("health_workout_mode") {
            healthWorkoutMode = HealthWorkoutMode(storage: mode)
        } else if snapshot.values["health_workout_enabled"] != nil {
            healthWorkoutMode = (snapshot.bool("health_workout_enabled") ?? true) ? .always : .never
        }
        startHealthWorkoutWithRound = snapshot.bool("start_health_workout_with_round") ?? true
        gpsSimulationEnabled = snapshot.bool("gps_sim_mode_enabled") ?? false
    }
}

/// A legacy entry that couldn't be decoded. The original payload is kept so nothing is lost.
public struct LegacyCorruptRecord: Sendable, Hashable, Codable {
    public var key: String
    /// Position in the stored list, or nil when the whole value was unreadable.
    public var index: Int?
    public var reason: String
    public var payload: String
}

public struct LegacyImport: Sendable {
    /// Newest first, like the Flutter list.
    public var rounds: [SavedRound]
    /// Valid traced-course rows, unchanged from storage.
    public var userCourseRows: [JSONValue]
    public var favorites: [String]
    public var visitCounts: [String: Int]
    /// The stored bag, or nil when the user never edited it.
    public var clubBag: [ClubDistance]?
    public var preferences: LegacyPreferences
    public var corrupt: [LegacyCorruptRecord]
    public var issues: [String]

    public var userCourseNames: [String] {
        Set(userCourseRows.compactMap { $0.objectValue?["course_name"]?.dartString }
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty })
            .sorted()
    }

    /// Decodes every legacy key. Never throws: unreadable values become corrupt records.
    public init(_ snapshot: LegacySnapshot, timeZone: TimeZone = .current) {
        var corrupt: [LegacyCorruptRecord] = []
        var issues: [String] = []

        rounds = Self.decodeRounds(snapshot.string(LegacySnapshot.roundsKey), timeZone: timeZone, corrupt: &corrupt, issues: &issues)
        userCourseRows = Self.decodeCourseRows(snapshot.string(LegacySnapshot.userCoursesKey), corrupt: &corrupt)
        favorites = Self.decodeFavorites(snapshot.string(LegacySnapshot.favoritesKey), corrupt: &corrupt)

        var counts = Self.decodeVisitCounts(snapshot.string(LegacySnapshot.visitCountsKey), corrupt: &corrupt)
        // Flutter replaces the counts with saved-round counts the first time it reads them.
        if snapshot.bool(LegacySnapshot.visitBootstrappedKey) != true, !rounds.isEmpty {
            counts = [:]
            for round in rounds {
                let name = round.courseName.trimmingCharacters(in: .whitespaces)
                if !name.isEmpty { counts[name, default: 0] += 1 }
            }
        }
        visitCounts = counts

        if let bag = snapshot.string(LegacySnapshot.clubBagKey), !bag.isEmpty {
            clubBag = ClubDistance.decodeBag(bag)
        } else {
            clubBag = nil
        }
        preferences = LegacyPreferences(snapshot)
        self.corrupt = corrupt
        self.issues = issues
    }

    private static func decodeRounds(
        _ raw: String?,
        timeZone: TimeZone,
        corrupt: inout [LegacyCorruptRecord],
        issues: inout [String]
    ) -> [SavedRound] {
        let key = LegacySnapshot.roundsKey
        guard let raw, !raw.isEmpty else { return [] }
        guard let items = (try? JSONValue.parse(Data(raw.utf8)))?.arrayValue else {
            corrupt.append(LegacyCorruptRecord(key: key, index: nil, reason: "Not a JSON list", payload: raw))
            return []
        }
        var rounds: [SavedRound] = []
        var seen: Set<String> = []
        for (index, item) in items.enumerated() {
            do {
                let round = try SavedRound.legacy(item, timeZone: timeZone)
                if seen.insert(round.id).inserted {
                    rounds.append(round)
                } else {
                    issues.append("Duplicate round \(round.id) at position \(index) was skipped")
                }
            } catch {
                corrupt.append(LegacyCorruptRecord(key: key, index: index, reason: String(describing: error), payload: item.compactText))
            }
        }
        return stableSorted(rounds) { $0.playedAt.date > $1.playedAt.date }
    }

    private static func decodeCourseRows(_ raw: String?, corrupt: inout [LegacyCorruptRecord]) -> [JSONValue] {
        let key = LegacySnapshot.userCoursesKey
        guard let raw, !raw.isEmpty else { return [] }
        guard let items = (try? JSONValue.parse(Data(raw.utf8)))?.arrayValue else {
            corrupt.append(LegacyCorruptRecord(key: key, index: nil, reason: "Not a JSON list", payload: raw))
            return []
        }
        var rows: [JSONValue] = []
        for (index, item) in items.enumerated() {
            do {
                _ = try FeatureRowDecoder.decodeRow(item, index: index)
                rows.append(item)
            } catch {
                corrupt.append(LegacyCorruptRecord(key: key, index: index, reason: String(describing: error), payload: item.compactText))
            }
        }
        return rows
    }

    private static func decodeFavorites(_ raw: String?, corrupt: inout [LegacyCorruptRecord]) -> [String] {
        guard let raw, !raw.isEmpty else { return [] }
        guard let items = (try? JSONValue.parse(Data(raw.utf8)))?.arrayValue else {
            corrupt.append(LegacyCorruptRecord(key: LegacySnapshot.favoritesKey, index: nil, reason: "Not a JSON list", payload: raw))
            return []
        }
        return items.compactMap { $0.dartString?.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    private static func decodeVisitCounts(_ raw: String?, corrupt: inout [LegacyCorruptRecord]) -> [String: Int] {
        guard let raw, !raw.isEmpty else { return [:] }
        guard let object = (try? JSONValue.parse(Data(raw.utf8)))?.objectValue else {
            corrupt.append(LegacyCorruptRecord(key: LegacySnapshot.visitCountsKey, index: nil, reason: "Not a JSON object", payload: raw))
            return [:]
        }
        var counts: [String: Int] = [:]
        for (course, value) in object {
            // Flutter discards every count when any one is not a number.
            guard let count = value.truncatedInt else {
                corrupt.append(LegacyCorruptRecord(key: LegacySnapshot.visitCountsKey, index: nil, reason: "Non-numeric count for \(course)", payload: raw))
                return [:]
            }
            counts[course] = count
        }
        return counts
    }
}

extension JSONValue {
    var compactText: String {
        (try? encoded()).map { String(decoding: $0, as: UTF8.self) } ?? String(describing: self)
    }
}
