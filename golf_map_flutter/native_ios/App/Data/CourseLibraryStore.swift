import Foundation
import GolfCore
import Observation

/// Favorites and visit counts, kept in `UserDefaults` under the native settings keys.
@Observable
@MainActor
final class CourseLibraryStore {
    private(set) var favorites: [String]
    private(set) var visitCounts: [String: Int]

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        favorites = defaults.stringArray(forKey: SettingsKey.favoriteCourses) ?? []
        visitCounts = (defaults.dictionary(forKey: SettingsKey.courseVisitCounts) as? [String: Int]) ?? [:]
    }

    /// Re-reads values written outside the store, such as by the legacy import.
    func reload() {
        favorites = defaults.stringArray(forKey: SettingsKey.favoriteCourses) ?? []
        visitCounts = (defaults.dictionary(forKey: SettingsKey.courseVisitCounts) as? [String: Int]) ?? [:]
    }

    func isFavorite(_ course: String) -> Bool { favorites.contains(course) }

    @discardableResult
    func toggleFavorite(_ course: String) -> FavoriteCourses.ToggleResult {
        let result = FavoriteCourses.toggle(course, in: &favorites)
        defaults.set(favorites, forKey: SettingsKey.favoriteCourses)
        return result
    }

    func recordVisit(_ course: String) {
        let name = course.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        visitCounts[name, default: 0] += 1
        defaults.set(visitCounts, forKey: SettingsKey.courseVisitCounts)
    }

    func commonlyVisited(savedRounds: [SavedRound]) -> [CommonlyVisitedEntry] {
        CommonlyVisitedEntry.rank(savedRounds: savedRounds, visitCounts: visitCounts)
    }
}
