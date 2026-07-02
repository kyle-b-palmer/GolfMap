import Foundation

/// Writes a compact snapshot for watch Smart Stack / complications.
enum GolfRoundWidgetSnapshot {
    private static let key = "golf_watch_complication_snapshot"
    private static let appGroupId = GolfRoundSharedState.appGroupId

    struct Payload: Codable {
        var courseName: String
        var hole: String
        var yardsToGreen: Int
        var holeScore: Int
        var totalScore: Int
        var updatedAt: Date
    }

    static func save(from state: GolfRoundSharedState, yardsToGreen: Int?) {
        guard let defaults = UserDefaults(suiteName: appGroupId) else { return }
        let payload = Payload(
            courseName: state.courseName,
            hole: state.selectedHole,
            yardsToGreen: yardsToGreen ?? state.yardsToGreen,
            holeScore: state.currentHoleScore,
            totalScore: state.totalScore,
            updatedAt: Date()
        )
        guard let data = try? JSONEncoder().encode(payload) else { return }
        defaults.set(data, forKey: key)
    }

    static func load() -> Payload? {
        guard let defaults = UserDefaults(suiteName: appGroupId),
              let data = defaults.data(forKey: key) else {
            return nil
        }
        return try? JSONDecoder().decode(Payload.self, from: data)
    }

    static func clear() {
        UserDefaults(suiteName: appGroupId)?.removeObject(forKey: key)
    }
}
