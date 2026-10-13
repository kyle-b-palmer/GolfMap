import Foundation
import GolfCore
import Observation
import os

/// Bundled course data. Remote and traced courses join this in Phase 6.
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

    private static let logger = Logger(subsystem: "com.golfmapapp.golfMapFlutter", category: "courses")

    func load() async {
        guard state != .loading, state != .loaded else { return }
        state = .loading
        let started = ContinuousClock.now
        do {
            let decoded = try await Task.detached(priority: .userInitiated) {
                guard let url = Bundle.main.url(forResource: "san_antonio_courses", withExtension: "json") else {
                    throw CocoaError(.fileNoSuchFile)
                }
                let features = try FeatureRowDecoder.decode(Data(contentsOf: url))
                return (features, CourseCatalog.build(features))
            }.value
            features = decoded.0
            catalog = decoded.1
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
}
