import Foundation
import Testing
@testable import GolfCore

@Suite("Course library")
struct CourseLibraryTests {
    @Test func favoritesAreNewestFirstAndCappedAtFive() {
        var favorites: [String] = []
        for name in ["A", "B", "C", "D", "E"] {
            #expect(FavoriteCourses.toggle(name, in: &favorites) == .added)
        }
        #expect(favorites == ["E", "D", "C", "B", "A"])
        #expect(FavoriteCourses.toggle("F", in: &favorites) == .limitReached)
        #expect(FavoriteCourses.toggle(" C ", in: &favorites) == .removed)
        #expect(FavoriteCourses.toggle("F", in: &favorites) == .added)
        #expect(favorites == ["F", "E", "D", "B", "A"])
        #expect(FavoriteCourses.toggle("  ", in: &favorites) == .limitReached)
    }

    @Test func commonlyVisitedPrefersSavedRoundsThenViews() {
        func round(_ course: String) -> SavedRound {
            SavedRound(id: UUID().uuidString, courseName: course, playedAt: DartDate(date: Date(), isUTC: false), scores: [:])
        }
        let rounds = [round("Yaupon"), round("Olmos"), round("Olmos")]
        let ranked = CommonlyVisitedEntry.rank(savedRounds: rounds, visitCounts: ["Brackenridge": 9, "Yaupon": 4], limit: 3)
        #expect(ranked.map(\.courseName) == ["Olmos", "Yaupon", "Brackenridge"])
        #expect(ranked.map(\.countLabel) == ["2 saved rounds", "1 saved round", "Viewed 9 times"])
        #expect(CommonlyVisitedEntry.rank(savedRounds: [], visitCounts: ["A": 1, "B": 1]).map(\.courseName) == ["A", "B"])
        #expect(CommonlyVisitedEntry.rank(savedRounds: [], visitCounts: ["A": 0]).isEmpty)
    }

    @Test func clubBagRowsFollowTheFlutterEditor() {
        typealias Row = ClubBagRules.Row
        let clubs = ClubBagRules.clubs(from: [Row(name: "pw", yards: "120"), Row(name: "", yards: ""), Row(name: "dr", yards: " 250 ")])
        #expect(clubs == [ClubDistance(name: "DR", carryYards: 250), ClubDistance(name: "PW", carryYards: 120)])
        #expect(ClubBagRules.clubs(from: [Row(name: "7I", yards: "0")]) == nil)
        #expect(ClubBagRules.clubs(from: [Row(name: "7I", yards: "401")]) == nil)
        #expect(ClubBagRules.clubs(from: [Row(name: "", yards: "150")]) == nil)
        #expect(ClubBagRules.clubs(from: [Row(name: "", yards: "")]) == nil)
        #expect(Row(name: "", yards: "0").isValid)
    }
}
