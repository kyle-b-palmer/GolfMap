import Foundation
import GolfCore

/// Golf course search (Nominatim, then Overpass by name nearby) and hole geometry (Overpass), as Flutter's
/// `OsmGolfCourseService`.
struct OSMClient: Sendable {
    enum Failure: Error, LocalizedError {
        case status(Int)
        case unreadable

        var errorDescription: String? {
            switch self {
            case .status(let code): "OpenStreetMap search failed (\(code)). Try again in a moment."
            case .unreadable: "OpenStreetMap sent an unexpected response."
            }
        }
    }

    static let userAgent = "SouthTexasGolfTracker/1.0 (course import)"
    static let nominatimURL = URL(string: "https://nominatim.openstreetmap.org/search")!
    static let overpassEndpoints = [
        "https://overpass.kumi.systems/api/interpreter",
        "https://overpass-api.de/api/interpreter",
        "https://maps.mail.ru/osm/tools/overpass/api/interpreter",
    ].compactMap(URL.init(string:))

    var session: URLSession = .shared

    /// Nearest first when the location is known, otherwise by name.
    func searchCourses(named query: String, near location: Coordinate?) async throws -> [OSMCourseSummary] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return [] }
        var summaries: [OSMCourseSummary] = []
        var seen: Set<String> = []
        func add(_ summary: OSMCourseSummary?) {
            guard let summary, seen.insert("\(summary.osmType):\(summary.osmID)").inserted else { return }
            summaries.append(summary)
        }

        let viewbox = location.map { OSMCourseParser.viewbox(around: $0, radiusKm: 120) }
        for variant in OSMCourseParser.searchQueries(trimmed) {
            for item in try await nominatim(variant, viewbox: viewbox) { add(OSMCourseParser.summary(nominatim: item)) }
            if !summaries.isEmpty { break }
        }
        if summaries.isEmpty, let location, let pattern = OSMCourseParser.overpassNamePattern(trimmed) {
            let elements = (try? await overpass(OSMCourseParser.nearbyNameQuery(pattern: pattern, near: location)))?["elements"]?.arrayValue ?? []
            elements.compactMap(OSMCourseParser.summary(overpass:)).sorted { $0.name < $1.name }.forEach(add)
        }

        if let location {
            return summaries.sorted { GeoMath.distanceMeters(location, $0.center) < GeoMath.distanceMeters(location, $1.center) }
        }
        return summaries.sorted { $0.name < $1.name }
    }

    func features(for course: OSMCourseSummary) async throws -> [GolfFeature] {
        let payload = try await overpass(OSMCourseParser.featureQuery(for: course))
        return OSMCourseParser.features(from: payload["elements"]?.arrayValue ?? [], courseName: course.name)
    }

    private func nominatim(_ query: String, viewbox: OSMBounds?) async throws -> [JSONValue] {
        var components = URLComponents(url: Self.nominatimURL, resolvingAgainstBaseURL: false)!
        var items = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "format", value: "jsonv2"),
            URLQueryItem(name: "limit", value: "8"),
            URLQueryItem(name: "dedupe", value: "1"),
            URLQueryItem(name: "addressdetails", value: "0"),
            URLQueryItem(name: "extratags", value: "0"),
            URLQueryItem(name: "namedetails", value: "0"),
            // US courses only; otherwise "Quarry Golf" ranks a rock quarry abroad above San Antonio's club.
            URLQueryItem(name: "countrycodes", value: "us"),
        ]
        if let viewbox {
            items.append(URLQueryItem(name: "viewbox", value: "\(viewbox.west),\(viewbox.north),\(viewbox.east),\(viewbox.south)"))
            items.append(URLQueryItem(name: "bounded", value: "0"))
        }
        components.queryItems = items
        components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        var request = URLRequest(url: components.url!, timeoutInterval: 12)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("en", forHTTPHeaderField: "Accept-Language")

        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw Failure.status(status) }
        return (try? JSONValue.parse(data).arrayValue)?.filter(OSMCourseParser.isGolfCourse) ?? []
    }

    /// Tries each public Overpass server in turn.
    private func overpass(_ query: String) async throws -> JSONValue {
        var lastError: Error = Failure.unreadable
        for endpoint in Self.overpassEndpoints {
            var request = URLRequest(url: endpoint, timeoutInterval: 20)
            request.httpMethod = "POST"
            request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.httpBody = Data("data=\(query.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "")".utf8)
            do {
                let (data, response) = try await session.data(for: request)
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                guard status == 200 else {
                    lastError = Failure.status(status)
                    continue
                }
                return try JSONValue.parse(data)
            } catch {
                lastError = error
            }
        }
        throw lastError
    }
}
