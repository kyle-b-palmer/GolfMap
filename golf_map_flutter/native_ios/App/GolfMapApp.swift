import GolfCore
import SwiftUI

@main
struct GolfMapApp: App {
    @State private var courses: CourseRepository
    @State private var location: LocationService
    @State private var rounds: RoundRepository
    @State private var library: CourseLibraryStore

    init() {
        #if DEBUG
        UITestSupport.resetIfRequested()
        #endif
        _courses = State(initialValue: CourseRepository())
        _location = State(initialValue: LocationService())
        _rounds = State(initialValue: RoundRepository())
        _library = State(initialValue: CourseLibraryStore())
        PhoneWatchSession.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environment(courses)
                .environment(location)
                .environment(rounds)
                .environment(library)
                .tint(.golfBrand)
                .task {
                    if LegacyMigration().runIfNeeded(rounds: rounds) != nil { library.reload() }
                    await courses.load()
                }
        }
    }
}
