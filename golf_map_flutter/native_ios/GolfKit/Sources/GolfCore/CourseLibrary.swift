import Foundation

/// Starred courses: newest first, at most five, as in the Flutter home screen.
public enum FavoriteCourses {
    public static let limit = 5

    public enum ToggleResult: Equatable, Sendable {
        case added
        case removed
        case limitReached
    }

    public static func toggle(_ course: String, in favorites: inout [String]) -> ToggleResult {
        let name = course.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return .limitReached }
        if let index = favorites.firstIndex(of: name) {
            favorites.remove(at: index)
            return .removed
        }
        guard favorites.count < limit else { return .limitReached }
        favorites.insert(name, at: 0)
        return .added
    }
}

public struct CommonlyVisitedEntry: Hashable, Sendable, Identifiable {
    public var courseName: String
    public var savedRoundCount: Int
    public var viewCount: Int

    public var id: String { courseName }

    public var countLabel: String {
        if savedRoundCount > 0 {
            return savedRoundCount == 1 ? "1 saved round" : "\(savedRoundCount) saved rounds"
        }
        return viewCount == 1 ? "Viewed once" : "Viewed \(viewCount) times"
    }

    /// Ranked by saved rounds, then views, then name; two entries by default.
    public static func rank(savedRounds: [SavedRound], visitCounts: [String: Int], limit: Int = 2) -> [CommonlyVisitedEntry] {
        var saved: [String: Int] = [:]
        for round in savedRounds {
            let name = round.courseName.trimmingCharacters(in: .whitespaces)
            if !name.isEmpty { saved[name, default: 0] += 1 }
        }
        let names = Set(saved.keys).union(visitCounts.keys)
        let entries = names
            .map { CommonlyVisitedEntry(courseName: $0, savedRoundCount: saved[$0] ?? 0, viewCount: visitCounts[$0] ?? 0) }
            .filter { $0.savedRoundCount > 0 || $0.viewCount > 0 }
            .sorted {
                if $0.savedRoundCount != $1.savedRoundCount { return $0.savedRoundCount > $1.savedRoundCount }
                if $0.viewCount != $1.viewCount { return $0.viewCount > $1.viewCount }
                return dartLess($0.courseName, $1.courseName)
            }
        return Array(entries.prefix(limit))
    }
}

public enum ClubBagRules {
    public static let carryRange = 1...400

    public struct Row: Hashable, Sendable, Identifiable {
        public var id = UUID()
        public var name: String
        public var yards: String

        public init(name: String, yards: String) {
            self.name = name
            self.yards = yards
        }

        public init(_ club: ClubDistance) {
            self.init(name: club.name, yards: String(club.carryYards))
        }

        var isBlank: Bool {
            name.trimmingCharacters(in: .whitespaces).isEmpty && (Int(yards.trimmingCharacters(in: .whitespaces)) ?? 0) == 0
        }

        public var isValid: Bool {
            isBlank || (!name.trimmingCharacters(in: .whitespaces).isEmpty
                && Int(yards.trimmingCharacters(in: .whitespaces)).map(carryRange.contains) == true)
        }
    }

    /// Upper-cased names, blank rows dropped, longest carry first. Nil when any row is incomplete or nothing is left.
    public static func clubs(from rows: [Row]) -> [ClubDistance]? {
        var clubs: [ClubDistance] = []
        for row in rows where !row.isBlank {
            guard row.isValid, let yards = Int(row.yards.trimmingCharacters(in: .whitespaces)) else { return nil }
            clubs.append(ClubDistance(name: row.name.trimmingCharacters(in: .whitespaces).uppercased(), carryYards: yards))
        }
        guard !clubs.isEmpty else { return nil }
        return stableSorted(clubs) { $0.carryYards > $1.carryYards }
    }
}
