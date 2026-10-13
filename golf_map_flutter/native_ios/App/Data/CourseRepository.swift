import Foundation
import GolfCore
import Observation
import os

/// Bundled courses plus courses the user traced or imported. Remote courses join this in Phase 6.
@Observable
@MainActor
final class CourseRepository {
    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    private(set) var state: LoadState = .idle
    private(set) var features: [GolfFeature] = []
    private(set) var catalog: [CourseCatalogEntry] = []
    private(set) var userCourseNames: [String] = []

    /// Traced-course rows in the bundled row format, appended after the bundled features like Flutter.
    nonisolated static let defaultUserCoursesURL = URL.applicationSupportDirectory
        .appending(path: "Courses/user-courses.json")

    private let userCoursesURL: URL
    private let bundledURL: URL?
    private let remote: CourseRemoteClient
    private nonisolated static let logger = Logger(subsystem: "com.golfmapapp.golfMapFlutter", category: "courses")

    init(
        userCoursesURL: URL = CourseRepository.defaultUserCoursesURL,
        bundledURL: URL? = Bundle.main.url(forResource: "san_antonio_courses", withExtension: "json"),
        remote: CourseRemoteClient = CourseRemoteClient()
    ) {
        self.userCoursesURL = userCoursesURL
        self.bundledURL = bundledURL
        self.remote = remote
    }

    func load() async {
        guard state != .loading, state != .loaded else { return }
        state = .loading
        let started = ContinuousClock.now
        let userCoursesURL = userCoursesURL
        let bundledURL = bundledURL
        let remote = remote
        do {
            let decoded = try await Task.detached(priority: .userInitiated) {
                let bundled = try await Self.loadSourceFeatures(bundledURL: bundledURL, remote: remote)
                let user = Self.loadUserFeatures(at: userCoursesURL)
                let features = bundled + user
                let userNames = Set(user.compactMap(\.courseName).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty })
                return (features, CourseCatalog.build(features), userNames.sorted())
            }.value
            features = decoded.0
            catalog = decoded.1
            userCourseNames = decoded.2
            state = .loaded
            Self.logger.info("Loaded \(decoded.0.count) features, \(decoded.1.count) courses in \(ContinuousClock.now - started)")
        } catch {
            state = .failed(error.localizedDescription)
            Self.logger.error("Course load failed: \(error.localizedDescription)")
        }
    }

    func features(for course: String) -> [GolfFeature] {
        features.filter { $0.matchesCourse(course) }
    }

    func entry(named name: String) -> CourseCatalogEntry? {
        catalog.first { $0.name == name }
    }

    /// Bundled data first; Supabase only when the asset is missing or unreadable, as in Flutter.
    private nonisolated static func loadSourceFeatures(bundledURL: URL?, remote: CourseRemoteClient) async throws -> [GolfFeature] {
        do {
            guard let bundledURL else { throw CocoaError(.fileNoSuchFile) }
            return try FeatureRowDecoder.decode(Data(contentsOf: bundledURL))
        } catch {
            logger.error("Bundled courses unavailable (\(error.localizedDescription)); loading from Supabase")
            return try await remote.allFeatures()
        }
    }

    /// A damaged user file shouldn't hide the bundled courses.
    private nonisolated static func loadUserFeatures(at url: URL) -> [GolfFeature] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        do {
            return try FeatureRowDecoder.decode(data)
        } catch {
            logger.error("Traced courses unreadable: \(error.localizedDescription)")
            return []
        }
    }
}
