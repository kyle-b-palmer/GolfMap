import Foundation
import GolfCore

/// The Supabase `golf_features` table over PostgREST, with the app's publishable key.
struct CourseRemoteClient: Sendable {
    struct Configuration: Sendable {
        var baseURL: URL
        var publishableKey: String

        static let app = Configuration(
            baseURL: URL(string: "https://xycsxghpvylyquigzdje.supabase.co")!,
            publishableKey: "sb_publishable_cp2hvysVtLbO_7ke0uk5NQ_CvBN4AoB"
        )
    }

    enum Failure: Error, Equatable, LocalizedError {
        case status(Int)
        case notAList
        case nothingToUpload
        /// The insert failed after the old rows were deleted; `restored` says whether they were put back.
        case uploadFailed(restored: Bool)

        var errorDescription: String? {
            switch self {
            case .status(let code): "The course database returned an error (\(code))."
            case .notAList: "The course database sent an unexpected response."
            case .nothingToUpload: "Trace at least one feature before uploading."
            case .uploadFailed(true): "Upload failed. The course's previous data was restored."
            case .uploadFailed(false): "Upload failed, and the course's previous data couldn't be restored."
            }
        }
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

    /// Rows stored remotely under this exact name.
    func featureCount(forCourse name: String) async throws -> Int {
        try await rawRows(forCourse: name, columns: "id").count
    }

    /// Replaces every remote row for the course, as Flutter's upload did: delete, then insert with IDs after
    /// the current maximum. If the insert fails, the deleted rows are put back.
    func replaceCourse(_ name: String, with features: [GolfFeature]) async throws -> Int {
        let course = name.trimmingCharacters(in: .whitespaces)
        guard !course.isEmpty, !features.isEmpty else { throw Failure.nothingToUpload }

        let backup = try await rawRows(forCourse: course, columns: Self.featureColumns)
        var nextID = try await get(columns: "id", filters: [], order: "id.desc", limit: 1, offset: 0).first?["id"]?.truncatedInt ?? 0
        let inserts = features.map { feature -> JSONValue in
            nextID += 1
            var row: [String: JSONValue] = [
                "id": .int(nextID),
                "feature_type": feature.featureType.map(JSONValue.string) ?? .null,
                "hole_number": feature.holeNumber.map(JSONValue.string) ?? .null,
                "name": feature.name.map(JSONValue.string) ?? .null,
                "geom": feature.geometry.json,
                "course_name": .string(course),
            ]
            if let par = feature.par { row["par"] = .int(par) }
            if let handicap = feature.handicap { row["handicap"] = .int(handicap) }
            return .object(row)
        }

        let filter = [URLQueryItem(name: "course_name", value: "eq.\(course)")]
        _ = try await send(method: "DELETE", filters: filter, body: nil)
        do {
            _ = try await send(method: "POST", filters: [], body: .array(inserts))
        } catch {
            let restored = backup.isEmpty ? true : (try? await send(method: "POST", filters: [], body: .array(backup))) != nil
            throw Failure.uploadFailed(restored: restored)
        }
        return inserts.count
    }

    private func rawRows(forCourse name: String, columns: String) async throws -> [JSONValue] {
        let course = name.trimmingCharacters(in: .whitespaces)
        guard !course.isEmpty else { return [] }
        var rows: [JSONValue] = []
        while true {
            let page = try await get(columns: columns, filters: [URLQueryItem(name: "course_name", value: "eq.\(course)")], offset: rows.count)
            rows += page
            if page.count < Self.pageSize { break }
        }
        return rows
    }

    private func rowsPage(filters: [URLQueryItem], offset: Int) async throws -> [JSONValue] {
        try await get(columns: Self.featureColumns, filters: filters, offset: offset)
    }

    private func get(columns: String, filters: [URLQueryItem], order: String = "id.asc", limit: Int = CourseRemoteClient.pageSize, offset: Int) async throws -> [JSONValue] {
        let query = [URLQueryItem(name: "select", value: columns)] + filters + [
            URLQueryItem(name: "order", value: order),
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "offset", value: String(offset)),
        ]
        guard let rows = try JSONValue.parse(try await send(method: "GET", filters: query, body: nil)).arrayValue else { throw Failure.notAList }
        return rows
    }

    private func send(method: String, filters: [URLQueryItem], body: JSONValue?) async throws -> Data {
        var components = URLComponents(url: configuration.baseURL.appending(path: "rest/v1/golf_features"), resolvingAgainstBaseURL: false)!
        components.queryItems = filters.isEmpty ? nil : filters
        // URLComponents leaves "+" alone, which servers read as a space.
        components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        var request = URLRequest(url: components.url!, timeoutInterval: 30)
        request.httpMethod = method
        request.setValue(configuration.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(configuration.publishableKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpBody = try body.encoded()
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("return=minimal", forHTTPHeaderField: "Prefer")
        }

        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw Failure.status(status) }
        return data
    }
}
