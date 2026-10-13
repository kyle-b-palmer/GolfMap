import GolfCore
import SwiftUI

@main
struct GolfMapApp: App {
    @State private var courses = CourseRepository()
    @State private var location = LocationService()
    @State private var rounds = RoundRepository()

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environment(courses)
                .environment(location)
                .environment(rounds)
                .tint(.golfBrand)
                .task {
                    LegacyMigration().runIfNeeded(rounds: rounds)
                    await courses.load()
                }
        }
    }
}
