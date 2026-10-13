import Foundation
import GolfCore

/// Read access to the Supabase `golf_features` table over PostgREST, with the app's publishable key.
/// Upload and replace arrive with the course editor in Phase 6.
struct CourseRemoteClient: Sendable {
    struct Configuration: Sendable {
        var baseURL: URL
        var publishableKey: String

        static let app = Configuration(
            baseURL: URL(string: "https://xycsxghpvylyquigzdje.supabase.co")!,
            publishableKey: "sb_publishable_cp2hvysVtLbO_7ke0uk5NQ_CvBN4AoB"
        )
    }

    enum Failure: Error, Equatable {
        case status(Int)
        case notAList
    }

    static let featureColumns = "id,feature_type,hole_number,name,geom,par,handicap,course_name"
    static let pageSize = 1000

    var configuration: Configuration = .app
    var session: URLSession = .shared

    /// Every row, paged so the server's row cap can't silently truncate the result.
    func allFeatures() async throws -> [GolfFeature] {
        var rows: [JSONValue] = []
        while true {
            let page = try await rowsPage(filters: [], offset: rows.count)
            rows += page
            if page.count < Self.pageSize { break }
        }
        return try FeatureRowDecoder.decode(JSONValue.array(rows).encoded())
    }

    func features(forCourse name: String) async throws -> [GolfFeature] {
        let course = name.trimmingCharacters(in: .whitespaces)
        guard !course.isEmpty else { return [] }
        var rows: [JSONValue] = []
        while true {
            let page = try await rowsPage(filters: [URLQueryItem(name: "course_name", value: "eq.\(course)")], offset: rows.count)
            rows += page
            if page.count < Self.pageSize { break }
        }
        return try FeatureRowDecoder.decode(JSONValue.array(rows).encoded())
    }

    /// Trimmed, unique, sorted names, as Flutter lists them.
    func courseNames() async throws -> [String] {
        var names: Set<String> = []
        var offset = 0
        while true {
            let page = try await get(columns: "course_name", filters: [], offset: offset)
            for row in page {
                if let name = row["course_name"]?.dartString?.trimmingCharacters(in: .whitespaces), !name.isEmpty {
                    names.insert(name)
                }
            }
            offset += page.count
            if page.count < Self.pageSize { break }
        }
        return names.sorted()
    }

    private func rowsPage(filters: [URLQueryItem], offset: Int) async throws -> [JSONValue] {
        try await get(columns: Self.featureColumns, filters: filters, offset: offset)
    }

    private func get(columns: String, filters: [URLQueryItem], offset: Int) async throws -> [JSONValue] {
        var components = URLComponents(url: configuration.baseURL.appending(path: "rest/v1/golf_features"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "select", value: columns)] + filters + [
            URLQueryItem(name: "order", value: "id.asc"),
            URLQueryItem(name: "limit", value: String(Self.pageSize)),
            URLQueryItem(name: "offset", value: String(offset)),
        ]
        // URLComponents leaves "+" alone, which servers read as a space.
        components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        var request = URLRequest(url: components.url!, timeoutInterval: 30)
        request.setValue(configuration.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(configuration.publishableKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw Failure.status(status) }
        guard let rows = try JSONValue.parse(data).arrayValue else { throw Failure.notAList }
        return rows
    }
}
