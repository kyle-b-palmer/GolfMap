import Foundation

public struct HoleStats: Hashable, Sendable {
    public var par: Int
    public var handicap: Int

    public init(par: Int, handicap: Int) {
        self.par = par
        self.handicap = handicap
    }
}

public struct CourseCatalogEntry: Hashable, Sendable, Identifiable {
    public var name: String
    public var state: String
    public var stateCode: String
    public var city: String
    public var latitude: Double
    public var longitude: Double

    public var id: String { name }
    public var locationLabel: String { "\(city), \(state)" }
    public var coordinate: Coordinate { Coordinate(latitude: latitude, longitude: longitude) }

    public func matches(query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if q.isEmpty { return true }
        return [name, city, state, stateCode].contains { $0.lowercased().contains(q) }
    }
}

public struct CourseCatalogGroup: Hashable, Sendable, Identifiable {
    public var state: String
    public var cities: [(city: String, courses: [CourseCatalogEntry])]
    public var id: String { state }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.state == rhs.state && lhs.cities.map(\.city) == rhs.cities.map(\.city)
            && lhs.cities.map(\.courses) == rhs.cities.map(\.courses)
    }

    public func hash(into hasher: inout Hasher) { hasher.combine(state) }
}

/// Dart `String.compareTo`: UTF-16 code unit order.
@inline(__always)
func dartLess(_ a: String, _ b: String) -> Bool {
    a.utf16.lexicographicallyPrecedes(b.utf16)
}

public enum CourseCatalog {
    public static func nearestCity(latitude: Double, longitude: Double) -> USCity {
        let point = Coordinate(latitude: latitude, longitude: longitude)
        var closest = USCity.all[0]
        var closestMeters = Double.infinity
        for city in USCity.all {
            let meters = GeoMath.distanceMeters(point, Coordinate(latitude: city.latitude, longitude: city.longitude))
            if meters < closestMeters {
                closestMeters = meters
                closest = city
            }
        }
        return closest
    }

    /// One entry per trimmed course name, located at the mean of feature centroids.
    public static func build(_ features: [GolfFeature]) -> [CourseCatalogEntry] {
        var order: [String] = []
        var byCourse: [String: [GolfFeature]] = [:]
        for feature in features {
            guard let name = feature.courseName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else { continue }
            if byCourse[name] == nil { order.append(name) }
            byCourse[name, default: []].append(feature)
        }

        var entries: [CourseCatalogEntry] = []
        for name in order {
            let centroids = byCourse[name]!.compactMap(\.geometry.centroid)
            guard !centroids.isEmpty else { continue }
            let latitude = centroids.map(\.latitude).reduce(0, +) / Double(centroids.count)
            let longitude = centroids.map(\.longitude).reduce(0, +) / Double(centroids.count)
            let city = nearestCity(latitude: latitude, longitude: longitude)
            entries.append(CourseCatalogEntry(
                name: name,
                state: city.state,
                stateCode: city.stateCode,
                city: city.name,
                latitude: latitude,
                longitude: longitude
            ))
        }

        return entries.sorted { a, b in
            if a.state != b.state { return dartLess(a.state, b.state) }
            if a.city != b.city { return dartLess(a.city, b.city) }
            return dartLess(a.name, b.name)
        }
    }

    public static func grouped(_ entries: [CourseCatalogEntry]) -> [CourseCatalogGroup] {
        var tree: [String: [String: [CourseCatalogEntry]]] = [:]
        for entry in entries {
            tree[entry.state, default: [:]][entry.city, default: []].append(entry)
        }
        return tree.keys.sorted(by: dartLess).map { state in
            let cities = tree[state]!
            return CourseCatalogGroup(
                state: state,
                cities: cities.keys.sorted(by: dartLess).map { city in
                    (city, cities[city]!.sorted { dartLess($0.name, $1.name) })
                }
            )
        }
    }

    /// Hole numbers for a course, numerically ordered; non-numeric labels sort after numbers.
    public static func holes(_ features: [GolfFeature], course: String) -> [String] {
        let holes = Set(features.filter { $0.matchesCourse(course) }.compactMap(\.holeNumber))
        return holes.sorted { a, b in
            switch (Int(a), Int(b)) {
            case let (x?, y?): return x != y ? x < y : dartLess(a, b)
            case (.some, nil): return true
            case (nil, .some): return false
            case (nil, nil): return dartLess(a, b)
            }
        }
    }

    /// Par/handicap from the first feature that has a par, otherwise the first feature (missing values are 0).
    public static func stats(_ features: [GolfFeature], course: String, hole: String) -> HoleStats? {
        let holeFeatures = features.filter { $0.matchesCourse(course) && $0.matchesHole(hole) }
        guard let first = holeFeatures.first else { return nil }
        let stat = holeFeatures.first { $0.par != nil } ?? first
        return HoleStats(par: stat.par ?? 0, handicap: stat.handicap ?? 0)
    }

    public static func courseNames(_ features: [GolfFeature]) -> [String] {
        build(features).map(\.name)
    }
}
