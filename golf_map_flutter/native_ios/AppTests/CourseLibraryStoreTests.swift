import Foundation
import GolfCore
import Testing
@testable import GolfMap

@MainActor
@Suite("Course library")
struct CourseLibraryStoreTests {
    let defaults = UserDefaults(suiteName: "course-library-tests-\(UUID().uuidString)")!

    @Test func favoritesPersistAndStopAtFive() {
        let store = CourseLibraryStore(defaults: defaults)
        for index in 1...5 { #expect(store.toggleFavorite("Course \(index)") == .added) }
        #expect(store.toggleFavorite("Course 6") == .limitReached)
        #expect(store.favorites.first == "Course 5")

        #expect(store.toggleFavorite("Course 3") == .removed)
        #expect(CourseLibraryStore(defaults: defaults).favorites == ["Course 5", "Course 4", "Course 2", "Course 1"])
    }

    @Test func visitsRankBehindSavedRounds() throws {
        let store = CourseLibraryStore(defaults: defaults)
        for _ in 0..<3 { store.recordVisit("Olmos Basin Golf Course") }
        store.recordVisit("  ")
        let saved = SavedRound(
            id: "1",
            courseName: "Brackenridge Golf Course",
            playedAt: DartDate(date: Date(), isUTC: false),
            scores: ["1": 4]
        )

        let ranked = store.commonlyVisited(savedRounds: [saved])
        #expect(ranked.map(\.courseName) == ["Brackenridge Golf Course", "Olmos Basin Golf Course"])
        #expect(CourseLibraryStore(defaults: defaults).visitCounts == ["Olmos Basin Golf Course": 3])
    }

    @Test func userCourseSaveReplacesRowsWithTheSameName() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "user-courses-\(UUID().uuidString).json")
        let store = UserCourseStore(url: url)
        let row = { (id: String, course: String) in
            JSONValue.object(["id": .string(id), "course_name": .string(course), "feature_type": .string("green")])
        }

        try store.save(course: "Backyard", rows: [row("a", "Backyard"), row("b", "Backyard")])
        try store.save(course: "Park", rows: [row("c", "Park")])
        try store.save(course: " Backyard ", rows: [row("d", "Backyard")])
        #expect(try store.rows().compactMap { $0["id"]?.dartString } == ["c", "d"])
        #expect(try store.courseNames() == ["Backyard", "Park"])

        try store.delete(course: "Park")
        #expect(try store.courseNames() == ["Backyard"])
    }
}
