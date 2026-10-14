import Foundation

public enum CourseImportSource: String, Sendable, Hashable {
    case database, bundled, openStreetMap

    public var label: String {
        switch self {
        case .database: "Database"
        case .bundled: "Built-in"
        case .openStreetMap: "OpenStreetMap"
        }
    }

    var priority: Int {
        switch self {
        case .database: 0
        case .bundled: 1
        case .openStreetMap: 2
        }
    }
}

public struct OSMBounds: Sendable, Hashable {
    public var south, west, north, east: Double

    public init(south: Double, west: Double, north: Double, east: Double) {
        self.south = south
        self.west = west
        self.north = north
        self.east = east
    }
}

public struct OSMCourseSummary: Sendable, Hashable {
    public var osmType: String
    public var osmID: Int
    public var name: String
    public var displayName: String?
    public var center: Coordinate
    public var bounds: OSMBounds?
}

public struct CourseImportMatch: Sendable, Hashable, Identifiable {
    public var name: String
    public var source: CourseImportSource
    public var osm: OSMCourseSummary?
    public var subtitle: String?

    public var id: String { "\(source.rawValue):\(name.lowercased())" }

    public init(name: String, source: CourseImportSource, osm: OSMCourseSummary? = nil, subtitle: String? = nil) {
        self.name = name
        self.source = source
        self.osm = osm
        self.subtitle = subtitle
    }
}

/// Flutter's `CourseImportService` matching and ordering.
public enum CourseImportRanking {
    static let stopWords: Set<String> = ["the", "a", "an", "golf", "course", "club", "links", "country", "at", "of"]

    /// Database and built-in names that match, plus every OSM result, deduplicated by source and name,
    /// nearest OSM results first when the player's position is known.
    public static func matches(
        query: String,
        databaseNames: [String],
        bundledNames: [String],
        osm: [OSMCourseSummary],
        near location: Coordinate?
    ) -> [CourseImportMatch] {
        let queryLower = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !queryLower.isEmpty else { return [] }
        var seen: Set<String> = []
        var matches: [CourseImportMatch] = []
        func add(_ match: CourseImportMatch) {
            let key = "\(match.source.rawValue):\(match.name.trimmingCharacters(in: .whitespaces).lowercased())"
            guard !key.hasSuffix(":"), seen.insert(key).inserted else { return }
            matches.append(match)
        }
        for name in databaseNames where nameMatches(name, queryLower) {
            add(CourseImportMatch(name: name, source: .database, subtitle: "Shared database · edit and re-upload"))
        }
        for name in bundledNames where nameMatches(name, queryLower) {
            add(CourseImportMatch(name: name, source: .bundled, subtitle: "Built-in course data"))
        }
        for course in osm {
            add(CourseImportMatch(name: course.name, source: .openStreetMap, osm: course, subtitle: course.displayName))
        }

        return matches.sorted { a, b in
            if let location {
                let da = a.osm.map { GeoMath.distanceMeters(location, $0.center) }
                let db = b.osm.map { GeoMath.distanceMeters(location, $0.center) }
                switch (da, db) {
                case let (da?, db?) where da != db: return da < db
                case (.some, nil): return true
                case (nil, .some): return false
                default: break
                }
            }
            let sa = matchScore(a.name, queryLower), sb = matchScore(b.name, queryLower)
            if sa != sb { return sa > sb }
            if a.source.priority != b.source.priority { return a.source.priority < b.source.priority }
            return a.name < b.name
        }
    }

    static func tokens(_ text: String) -> [String] {
        text.split(whereSeparator: \.isWhitespace).map(String.init).filter { $0.count > 2 && !stopWords.contains($0) }
    }

    static func nameMatches(_ name: String, _ queryLower: String) -> Bool {
        let nameLower = name.trimmingCharacters(in: .whitespaces).lowercased()
        guard !nameLower.isEmpty else { return false }
        if nameLower == queryLower || nameLower.contains(queryLower) || queryLower.contains(nameLower) { return true }
        let queryTokens = tokens(queryLower)
        return queryTokens.isEmpty || queryTokens.allSatisfy(nameLower.contains)
    }

    static func matchScore(_ name: String, _ queryLower: String) -> Int {
        let nameLower = name.trimmingCharacters(in: .whitespaces).lowercased()
        if nameLower == queryLower { return 100 }
        if nameLower.hasPrefix(queryLower) { return 80 }
        if nameLower.contains(queryLower) { return 60 }
        let queryTokens = tokens(queryLower)
        if !queryTokens.isEmpty, queryTokens.allSatisfy(nameLower.contains) { return 50 }
        return 20
    }

    /// Copies features under a new course name with fresh local IDs.
    public static func clone(_ features: [GolfFeature], as courseName: String, now: Date = .now) -> [GolfFeature] {
        let name = courseName.trimmingCharacters(in: .whitespaces)
        let stamp = Int(now.timeIntervalSince1970 * 1000)
        return features.enumerated().map { index, feature in
            var copy = feature
            copy.id = .string("user-\(stamp)-\(index)")
            copy.courseName = name
            return copy
        }
    }
}

/// Request building and response parsing for Nominatim and Overpass, as Flutter's `OsmGolfCourseService`.
public enum OSMCourseParser {
    static let stopWords = CourseImportRanking.stopWords

    /// The query as typed, then golf/club/course variants; searching stops at the first that finds anything.
    public static func searchQueries(_ raw: String) -> [String] {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        let lower = trimmed.lowercased()
        var queries: [String] = []
        func add(_ value: String) {
            let cleaned = value.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            guard !cleaned.isEmpty, !queries.contains(where: { $0.lowercased() == cleaned.lowercased() }) else { return }
            queries.append(cleaned)
        }
        add(trimmed)
        if !lower.contains("golf") { add("\(trimmed) golf") }
        if !lower.contains("club") { add(lower.contains("golf") ? "\(trimmed) Club" : "\(trimmed) Golf Club") }
        if !lower.contains("course") { add(lower.contains("golf") ? "\(trimmed) Course" : "\(trimmed) Golf Course") }
        let meaningful = trimmed.split(whereSeparator: \.isWhitespace).map(String.init).filter { !stopWords.contains($0.lowercased()) }
        if !meaningful.isEmpty {
            add("\(meaningful.joined(separator: " ")) Golf Club")
            add("\(meaningful.joined(separator: " ")) Golf Course")
        }
        return queries
    }

    /// Case-insensitive Overpass regex of the meaningful words in order, or nil if there are none.
    public static func overpassNamePattern(_ raw: String) -> String? {
        let special = Set(#".\+*?[]^$(){}=!<>|:-"#)
        let tokens = raw.split(whereSeparator: \.isWhitespace).map(String.init)
            .filter { !stopWords.contains($0.lowercased()) }
            .map { token in token.map { special.contains($0) ? "\\\($0)" : String($0) }.joined() }
            .filter { !$0.isEmpty }
        return tokens.isEmpty ? nil : tokens.joined(separator: ".*")
    }

    public static func viewbox(around center: Coordinate, radiusKm: Double) -> OSMBounds {
        let latDelta = radiusKm / 111
        let lonDelta = radiusKm / (111 * min(max(abs(cos(center.latitude * .pi / 180)), 0.2), 1))
        return OSMBounds(south: center.latitude - latDelta, west: center.longitude - lonDelta, north: center.latitude + latDelta, east: center.longitude + lonDelta)
    }

    /// Golf courses only: drops quarries, disc golf, and land-use areas that Nominatim ranks highly.
    public static func isGolfCourse(_ item: JSONValue) -> Bool {
        let type = item["type"]?.dartString
        let category = item["category"]?.dartString ?? item["class"]?.dartString
        if type == "golf_course", category == nil || category == "leisure" || category?.isEmpty == true { return true }
        if type == "disc_golf_course" || type == "quarry" || category == "landuse" { return false }
        let haystack = "\(item["name"]?.dartString ?? "") \(item["display_name"]?.dartString ?? "")".lowercased()
        guard haystack.contains("golf"), !haystack.contains("disc golf") else { return false }
        return type == "golf_course" || category == "leisure"
    }

    public static func summary(nominatim item: JSONValue) -> OSMCourseSummary? {
        guard let name = item["name"]?.dartString?.trimmingCharacters(in: .whitespaces), !name.isEmpty,
              let lat = item["lat"]?.dartString.flatMap(Double.init), let lon = item["lon"]?.dartString.flatMap(Double.init) else { return nil }
        var bounds: OSMBounds?
        if let box = item["boundingbox"]?.arrayValue?.compactMap({ $0.dartString.flatMap(Double.init) }), box.count >= 4 {
            bounds = OSMBounds(south: box[0], west: box[2], north: box[1], east: box[3])
        }
        return OSMCourseSummary(
            osmType: item["osm_type"]?.dartString ?? "way",
            osmID: item["osm_id"]?.lenientInt ?? 0,
            name: name,
            displayName: item["display_name"]?.dartString,
            center: Coordinate(latitude: lat, longitude: lon),
            bounds: bounds
        )
    }

    public static func summary(overpass element: JSONValue) -> OSMCourseSummary? {
        guard let name = element["tags"]?["name"]?.dartString?.trimmingCharacters(in: .whitespaces), !name.isEmpty else { return nil }
        var bounds: OSMBounds?
        if let b = element["bounds"], let s = b["minlat"]?.numberValue, let w = b["minlon"]?.numberValue,
           let n = b["maxlat"]?.numberValue, let e = b["maxlon"]?.numberValue {
            bounds = OSMBounds(south: s, west: w, north: n, east: e)
        }
        let center: Coordinate
        if let lat = element["center"]?["lat"]?.numberValue, let lon = element["center"]?["lon"]?.numberValue {
            center = Coordinate(latitude: lat, longitude: lon)
        } else if let bounds {
            center = Coordinate(latitude: (bounds.north + bounds.south) / 2, longitude: (bounds.east + bounds.west) / 2)
        } else {
            return nil
        }
        return OSMCourseSummary(
            osmType: element["type"]?.dartString ?? "way",
            osmID: element["id"]?.truncatedInt ?? 0,
            name: name,
            displayName: nil,
            center: center,
            bounds: bounds
        )
    }

    /// Overpass query for a course's tees, fairways, greens, bunkers, and hole lines, padded so edge
    /// features aren't clipped. Without bounds it searches 1.2 km around the course's center.
    public static func featureQuery(for course: OSMCourseSummary) -> String {
        let area: String
        if let b = course.bounds {
            area = "(\(b.south - 0.0015),\(b.west - 0.0015),\(b.north + 0.0015),\(b.east + 0.0015))"
        } else {
            area = "(around:1200,\(course.center.latitude),\(course.center.longitude))"
        }
        return """
        [out:json][timeout:25];
        (
          way["golf"~"^(tee|teeing_ground|fairway|green|bunker|sand_trap|hole)$"]\(area);
          relation["type"="multipolygon"]["golf"~"^(tee|teeing_ground|fairway|green|bunker|sand_trap)$"]\(area);
        );
        out geom tags;
        """
    }

    public static func nearbyNameQuery(pattern: String, near center: Coordinate, radiusMeters: Int = 120_000) -> String {
        let around = "(around:\(radiusMeters),\(center.latitude),\(center.longitude))"
        return """
        [out:json][timeout:20];
        (
          way["leisure"="golf_course"]["name"~\(pattern),i]\(around);
          relation["leisure"="golf_course"]["name"~\(pattern),i]\(around);
        );
        out center tags bb;
        """
    }

    static func featureType(golfTag: String?) -> String? {
        switch golfTag {
        case "tee", "teeing_ground": "tee"
        case "fairway", "rough": "fairway"
        case "green": "green"
        case "bunker", "sand_trap": "bunker"
        default: nil
        }
    }

    static func holeNumber(_ tags: JSONValue?) -> String? {
        for key in ["ref", "hole", "hole_number"] {
            if let value = tags?[key]?.dartString?.trimmingCharacters(in: .whitespaces), !value.isEmpty { return value }
        }
        return nil
    }

    static func points(_ element: JSONValue) -> [Coordinate] {
        (element["geometry"]?.arrayValue ?? []).compactMap { point in
            guard let lat = point["lat"]?.numberValue, let lon = point["lon"]?.numberValue else { return nil }
            return Coordinate(latitude: lat, longitude: lon)
        }
    }

    /// Features from Overpass `out geom` elements. Untagged features join the hole whose line is nearest,
    /// and greens take par from their hole line. Multipolygon relations carry no top-level geometry, so
    /// Flutter skipped them; so does this.
    public static func features(from elements: [JSONValue], courseName: String) -> [GolfFeature] {
        var anchors: [(hole: String, point: Coordinate)] = []
        var holePar: [String: Int] = [:]
        for element in elements where element["tags"]?["golf"]?.dartString == "hole" {
            let line = points(element)
            guard let hole = holeNumber(element["tags"]), !line.isEmpty else { continue }
            let center = Coordinate(
                latitude: line.map(\.latitude).reduce(0, +) / Double(line.count),
                longitude: line.map(\.longitude).reduce(0, +) / Double(line.count)
            )
            anchors.removeAll { $0.hole == hole }
            anchors.append((hole, center))
            if let par = element["tags"]?["par"]?.lenientInt { holePar[hole] = par }
        }

        var features: [GolfFeature] = []
        for element in elements {
            let tags = element["tags"]
            guard tags?["golf"]?.dartString != "hole", let type = featureType(golfTag: tags?["golf"]?.dartString) else { continue }
            let ring = points(element)
            guard ring.count >= 3 else { continue }
            let geometry = Geometry.polygon(vertices: ring)

            var hole = holeNumber(tags)
            if hole == nil, let centroid = geometry.centroid {
                hole = anchors.min { GeoMath.distanceMeters(centroid, $0.point) < GeoMath.distanceMeters(centroid, $1.point) }?.hole
            }
            var par = tags?["par"]?.lenientInt
            if type == "green", par == nil, let hole { par = holePar[hole] }

            features.append(GolfFeature(
                id: .string("osm-\(element["type"]?.dartString ?? "way")-\(element["id"]?.dartString ?? "0")-\(features.count)"),
                featureType: type,
                holeNumber: hole,
                name: tags?["name"]?.dartString,
                par: par,
                handicap: (tags?["handicap"] ?? tags?["stroke"])?.lenientInt,
                courseName: courseName,
                geometry: geometry
            ))
        }
        return features
    }
}
