import Foundation

public struct GreenYardages: Hashable, Sendable, Codable {
    public var front: Int
    public var middle: Int
    public var back: Int

    public init(front: Int, middle: Int, back: Int) {
        self.front = front
        self.middle = middle
        self.back = back
    }

    public static let zero = GreenYardages(front: 0, middle: 0, back: 0)
}

public struct BunkerDistance: Hashable, Sendable {
    public var label: String
    /// Positive when the bunker edge is ahead toward the green, negative when behind.
    public var yards: Int
    public var point: Coordinate?
}

public struct TeeOption: Hashable, Sendable {
    public var featureID: FeatureID?
    public var point: Coordinate
    public var label: String
}

public struct HoleOrientation: Hashable, Sendable {
    public var tee: Coordinate
    public var green: Coordinate
}

public struct PlannedShotSegment: Hashable, Sendable {
    public var shotNumber: Int
    public var from: Coordinate
    public var to: Coordinate
    public var yards: Int
    public var carryYards: Int?
    public var carryPoint: Coordinate?
}

/// Hole-level calculations. `holeFeatures` are features already filtered to one course and hole.
public enum HoleGeometry {
    public static let maxPlannedShotYards = 250
    public static let maxFollowUpPlannedShotYards = 200

    public static func features(_ features: [GolfFeature], course: String?, hole: String) -> [GolfFeature] {
        features.filter { $0.isActive(course: course, hole: hole) }
    }

    // MARK: Green and tees

    /// Centroid of the green with the most vertices (first wins ties).
    public static func greenCenter(_ holeFeatures: [GolfFeature]) -> Coordinate? {
        var primary: GolfFeature?
        var largest = 0
        for green in holeFeatures where green.isType("green") {
            let count = green.geometry.allPoints.count
            if count > largest {
                largest = count
                primary = green
            }
        }
        return primary?.geometry.centroid
    }

    public static func orientation(_ features: [GolfFeature]) -> HoleOrientation? {
        let teePoints = features.filter { $0.isType("tee") }.compactMap(\.geometry.representativePoint)
        let greenPoints = features.filter { $0.isType("green") }.compactMap(\.geometry.representativePoint)

        func minDistance(_ point: Coordinate, _ targets: [Coordinate]) -> Double {
            targets.map { GeoMath.distanceMeters(point, $0) }.min() ?? .infinity
        }

        for hole in features where hole.isType("hole") {
            let line = hole.geometry.allPoints
            guard line.count >= 2, let start = line.first, let end = line.last else { continue }
            if !teePoints.isEmpty {
                let startNearTee = minDistance(start, teePoints) <= minDistance(end, teePoints)
                return HoleOrientation(tee: startNearTee ? start : end, green: startNearTee ? end : start)
            }
            if !greenPoints.isEmpty {
                let startNearGreen = minDistance(start, greenPoints) <= minDistance(end, greenPoints)
                return HoleOrientation(tee: startNearGreen ? end : start, green: startNearGreen ? start : end)
            }
            return HoleOrientation(tee: start, green: end)
        }

        guard let firstTee = teePoints.first, let firstGreen = greenPoints.first else { return nil }
        var best = HoleOrientation(tee: firstTee, green: firstGreen)
        var bestSeparation = 0.0
        for tee in teePoints {
            for green in greenPoints {
                let separation = GeoMath.distanceMeters(tee, green)
                if separation > bestSeparation {
                    bestSeparation = separation
                    best = HoleOrientation(tee: tee, green: green)
                }
            }
        }
        return best
    }

    /// Back tee: the tee farthest from the green.
    public static func longestTee(_ holeFeatures: [GolfFeature]) -> Coordinate? {
        let green = greenCenter(holeFeatures)
        let teePoints = holeFeatures.filter { $0.isType("tee") }.compactMap(\.geometry.representativePoint)
        guard let first = teePoints.first else { return orientation(holeFeatures)?.tee }
        guard let green else { return first }
        var farthest = first
        var farthestMeters = 0.0
        for tee in teePoints {
            let meters = GeoMath.distanceMeters(tee, green)
            if meters > farthestMeters {
                farthestMeters = meters
                farthest = tee
            }
        }
        return farthest
    }

    static func teeLabels(_ count: Int) -> [String] {
        switch count {
        case 1: return ["Tee"]
        case 2: return ["Back", "Front"]
        case 3: return ["Back", "Middle", "Front"]
        default: return (0..<count).map { "Tee \($0 + 1)" }
        }
    }

    /// Tees ordered farthest-first and labeled Back/Middle/Front.
    public static func teeOptions(_ holeFeatures: [GolfFeature]) -> [TeeOption] {
        let green = greenCenter(holeFeatures)
        var ranked: [(id: FeatureID?, point: Coordinate, distance: Double, order: Int)] = []
        for tee in holeFeatures where tee.isType("tee") {
            guard let point = tee.geometry.representativePoint else { continue }
            let distance = green.map { GeoMath.distanceMeters(point, $0) } ?? 0
            ranked.append((tee.id, point, distance, ranked.count))
        }
        ranked.sort { $0.distance != $1.distance ? $0.distance > $1.distance : $0.order < $1.order }
        let labels = teeLabels(ranked.count)
        return ranked.enumerated().map { index, tee in
            TeeOption(featureID: tee.id, point: tee.point, label: labels[index])
        }
    }

    /// First tee with this ID; IDs are not unique in OSM-derived data.
    public static func teePoint(_ holeFeatures: [GolfFeature], id: FeatureID?) -> Coordinate? {
        holeFeatures.first { $0.id == id && $0.isType("tee") }?.geometry.representativePoint
    }

    public static func teeOption(_ holeFeatures: [GolfFeature], label: String) -> TeeOption? {
        teeOptions(holeFeatures).first { $0.label == label }
    }

    public static func holeYardage(_ holeFeatures: [GolfFeature], teeID: FeatureID?) -> Int? {
        guard let tee = teePoint(holeFeatures, id: teeID), let green = greenCenter(holeFeatures) else { return nil }
        return GeoMath.yardsBetween(tee, green)
    }

    // MARK: Yardages

    static func ringSegments(_ ring: [Coordinate]) -> [(Coordinate, Coordinate)] {
        guard ring.count >= 2 else { return [] }
        let limit = ring.first == ring.last ? ring.count - 1 : ring.count
        return (0..<limit).map { (ring[$0], ring[($0 + 1) % ring.count]) }
    }

    static func greenBoundarySamples(_ holeFeatures: [GolfFeature]) -> [Coordinate] {
        var points: [Coordinate] = []
        for green in holeFeatures where green.isType("green") {
            for ring in green.geometry.rings where !ring.isEmpty {
                points.append(contentsOf: ring)
                let limit = ring.count > 1 && ring.first == ring.last ? ring.count - 1 : ring.count
                for i in 0..<limit {
                    let a = ring[i], b = ring[(i + 1) % ring.count]
                    points.append(Coordinate(
                        latitude: (a.latitude + b.latitude) / 2,
                        longitude: (a.longitude + b.longitude) / 2
                    ))
                }
            }
        }
        return points
    }

    /// Nearest edge of any green on the hole (not only the primary green).
    static func frontOfGreenMeters(_ from: Coordinate, _ holeFeatures: [GolfFeature]) -> Double {
        var minMeters = Double.infinity
        for green in holeFeatures where green.isType("green") {
            for ring in green.geometry.rings {
                for (a, b) in ringSegments(ring) {
                    minMeters = min(minMeters, GeoMath.distanceToSegmentMeters(from, a, b))
                }
            }
        }
        return minMeters.isFinite ? minMeters : 0
    }

    /// Back edge of the green along the approach from `from`.
    public static func backOfGreen(from: Coordinate, _ holeFeatures: [GolfFeature]) -> Coordinate? {
        guard let center = greenCenter(holeFeatures) else { return nil }
        let approach = GeoMath.bearing(from, center)
        var back: Coordinate?
        var maxAlong = -Double.infinity
        for point in greenBoundarySamples(holeFeatures) {
            let distance = GeoMath.distanceMeters(from, point)
            let along = distance * cos(GeoMath.bearingDifferenceRadians(approach, GeoMath.bearing(from, point)))
            if along > maxAlong {
                maxAlong = along
                back = point
            }
        }
        return back
    }

    public static func greenYardages(from: Coordinate, _ holeFeatures: [GolfFeature]) -> GreenYardages {
        guard let center = greenCenter(holeFeatures) else { return .zero }
        let front = GeoMath.yards(meters: frontOfGreenMeters(from, holeFeatures))
        let middle = GeoMath.yardsBetween(from, center)
        let backMeters = backOfGreen(from: from, holeFeatures).map { GeoMath.distanceMeters(from, $0) } ?? 0
        return GreenYardages(front: front, middle: middle, back: GeoMath.yards(meters: backMeters))
    }

    static func distanceToFeatureEdgeMeters(_ from: Coordinate, _ geometry: Geometry) -> Double {
        let rings = geometry.rings
        if rings.isEmpty {
            guard let point = geometry.representativePoint else { return .infinity }
            return GeoMath.distanceMeters(from, point)
        }
        var minMeters = Double.infinity
        for ring in rings {
            for (a, b) in ringSegments(ring) {
                minMeters = min(minMeters, GeoMath.distanceToSegmentMeters(from, a, b))
            }
        }
        return minMeters
    }

    /// Signed bunker-edge distances, nearest first.
    public static func bunkerDistances(from: Coordinate, _ holeFeatures: [GolfFeature]) -> [BunkerDistance] {
        guard let green = greenCenter(holeFeatures) else { return [] }
        let bunkers = holeFeatures.filter { $0.isType("bunker") }
        var results: [(BunkerDistance, Int)] = []

        for (index, bunker) in bunkers.enumerated() {
            let edge = distanceToFeatureEdgeMeters(from, bunker.geometry)
            var meters = edge.isFinite ? edge : 0
            if edge.isFinite, let bunkerPoint = bunker.geometry.representativePoint {
                let approach = GeoMath.bearing(from, green)
                let toBunker = GeoMath.bearing(from, bunkerPoint)
                let along = GeoMath.distanceMeters(from, bunkerPoint)
                    * cos(GeoMath.bearingDifferenceRadians(approach, toBunker))
                meters = along >= 0 ? edge : -edge
            }
            let trimmed = bunker.name?.trimmingCharacters(in: .whitespacesAndNewlines)
            let label = (trimmed?.isEmpty == false) ? trimmed! : "Bunker \(index + 1)"
            let point = bunker.geometry.representativePoint
            results.append((BunkerDistance(label: label, yards: GeoMath.signedYards(meters: meters), point: point), index))
        }

        return results.sorted {
            abs($0.0.yards) != abs($1.0.yards) ? abs($0.0.yards) < abs($1.0.yards) : $0.1 < $1.1
        }.map(\.0)
    }

    // MARK: Position tests

    public static func isPoint(_ point: Coordinate, in feature: GolfFeature) -> Bool {
        feature.geometry.rings.contains { $0.count >= 3 && GeoMath.isPoint(point, inRing: $0) }
    }

    public static func isPointInFairway(_ point: Coordinate, _ holeFeatures: [GolfFeature]) -> Bool {
        holeFeatures.contains { $0.isType("fairway") && isPoint(point, in: $0) }
    }

    public static func isPointInGreen(_ point: Coordinate, _ holeFeatures: [GolfFeature]) -> Bool {
        holeFeatures.contains { $0.isType("green") && isPoint(point, in: $0) }
    }

    /// Inside a tee polygon or within 25 yards of a tee marker.
    public static func isOnTeeBox(_ user: Coordinate, _ holeFeatures: [GolfFeature]) -> Bool {
        if holeFeatures.contains(where: { $0.isType("tee") && isPoint(user, in: $0) }) { return true }
        return teeOptions(holeFeatures).contains { GeoMath.yardsBetween(user, $0.point) <= 25 }
    }

    /// Within `maxYards` of any vertex on the hole.
    public static func isNearHole(_ user: Coordinate, _ holeFeatures: [GolfFeature], maxYards: Double = 1200) -> Bool {
        let maxMeters = maxYards / GeoMath.yardsPerMeter
        var nearest = Double.infinity
        for feature in holeFeatures {
            for point in feature.geometry.allPoints {
                nearest = min(nearest, GeoMath.distanceMeters(user, point))
            }
        }
        return nearest <= maxMeters
    }

    public static func shotOrigin(user: Coordinate?, _ holeFeatures: [GolfFeature]) -> Coordinate? {
        guard let user, isNearHole(user, holeFeatures) else { return nil }
        return user
    }

    // MARK: Encirclement (play area and camera framing)

    public static func encirclementRing(_ features: [GolfFeature], course: String?, hole: String) -> [Coordinate] {
        ellipseRing(features, course: course, hole: hole, alongPad: 10, lateralPad: 8)
    }

    public static func cameraFocusRing(_ features: [GolfFeature], course: String?, hole: String, tight: Bool = false) -> [Coordinate] {
        ellipseRing(features, course: course, hole: hole, alongPad: tight ? 2 : 4, lateralPad: tight ? 1 : 2)
    }

    static func ellipseRing(
        _ features: [GolfFeature],
        course: String?,
        hole: String,
        alongPad: Double,
        lateralPad: Double
    ) -> [Coordinate] {
        let holeFeatures = Self.features(features, course: course, hole: hole)
        var points: [Coordinate] = []
        for type in ["tee", "fairway", "green", "bunker"] {
            for feature in holeFeatures where feature.isType(type) {
                points.append(contentsOf: feature.geometry.allPoints)
            }
        }
        guard points.count >= 2 else { return [] }

        guard let green = greenCenter(holeFeatures), let tee = longestTee(holeFeatures) else {
            let hull = GeoMath.convexHull(points)
            return hull.count >= 3 ? hull : []
        }

        let axisBearing = GeoMath.bearing(tee, green)
        let axisCenter = Coordinate(
            latitude: (tee.latitude + green.latitude) / 2,
            longitude: (tee.longitude + green.longitude) / 2
        )

        var minAlong = Double.infinity, maxAlong = -Double.infinity, maxLateral = 0.0
        for point in points {
            let distance = GeoMath.distanceMeters(axisCenter, point)
            let diff = GeoMath.bearingDifferenceRadians(axisBearing, GeoMath.bearing(axisCenter, point))
            let along = distance * cos(diff)
            let lateral = distance * abs(sin(diff))
            minAlong = min(minAlong, along)
            maxAlong = max(maxAlong, along)
            maxLateral = max(maxLateral, lateral)
        }

        let semiMajor = (maxAlong - minAlong) / 2 + alongPad
        let semiMinor = maxLateral + lateralPad
        let center = GeoMath.destination(from: axisCenter, bearing: axisBearing, meters: (minAlong + maxAlong) / 2)
        if semiMajor < 15 || semiMinor < 10 { return [] }

        let steps = 72
        return (0...steps).map { i in
            let theta = 2 * Double.pi * Double(i) / Double(steps)
            let onAxis = GeoMath.destination(from: center, bearing: axisBearing, meters: semiMajor * cos(theta))
            return GeoMath.destination(from: onAxis, bearing: axisBearing + 90, meters: semiMinor * sin(theta))
        }
    }

    public static func distanceOutsideEncirclementMeters(
        _ point: Coordinate,
        _ features: [GolfFeature],
        course: String?,
        hole: String
    ) -> Double {
        let ring = encirclementRing(features, course: course, hole: hole)
        if ring.count < 3 || GeoMath.isPoint(point, inRing: ring) { return 0 }
        var minDistance = Double.infinity
        for i in 0..<ring.count {
            let d = GeoMath.alongTrackDistanceToSegmentMeters(point, ring[i], ring[(i + 1) % ring.count])
            minDistance = min(minDistance, d)
        }
        return minDistance
    }

    public static func isPointInEncirclement(_ point: Coordinate, _ features: [GolfFeature], course: String?, hole: String) -> Bool {
        let ring = encirclementRing(features, course: course, hole: hole)
        if ring.count < 3 { return true }
        return GeoMath.isPoint(point, inRing: ring)
    }

    /// GPS is usable when inside the hole oval or no more than `significantOutsideMeters` outside it.
    public static func isGpsWithinPlayArea(
        _ user: Coordinate,
        _ features: [GolfFeature],
        course: String?,
        hole: String,
        significantOutsideMeters: Double = 45
    ) -> Bool {
        let ring = encirclementRing(features, course: course, hole: hole)
        if ring.count < 3 {
            return isNearHole(user, Self.features(features, course: course, hole: hole))
        }
        return distanceOutsideEncirclementMeters(user, features, course: course, hole: hole) <= significantOutsideMeters
    }

    // MARK: Planned shots

    static func fairwayCenter(
        from: Coordinate,
        approach: Double,
        along targetAlong: Double,
        _ holeFeatures: [GolfFeature]
    ) -> Coordinate? {
        let onLine = GeoMath.destination(from: from, bearing: approach, meters: targetAlong)

        func edge(_ bearing: Double) -> Coordinate? {
            var edge: Coordinate?
            var lateral = 0.0
            while lateral <= 100 {
                let point = GeoMath.destination(from: onLine, bearing: bearing, meters: lateral)
                if isPointInFairway(point, holeFeatures) {
                    edge = point
                } else if edge != nil {
                    break
                }
                lateral += 2
            }
            return edge
        }

        let plus = edge(approach + 90)
        let minus = edge(approach - 90)
        if let plus, let minus {
            return Coordinate(latitude: (plus.latitude + minus.latitude) / 2, longitude: (plus.longitude + minus.longitude) / 2)
        }
        if let plus { return plus }
        if let minus { return minus }
        if isPointInFairway(onLine, holeFeatures) { return onLine }
        return nil
    }

    public static func optimalFairwayLanding(
        from: Coordinate,
        green: Coordinate,
        _ holeFeatures: [GolfFeature],
        maxShotYards: Int = maxPlannedShotYards
    ) -> Coordinate? {
        let maxMeters = Double(maxShotYards) / GeoMath.yardsPerMeter
        let toGreen = GeoMath.distanceMeters(from, green)
        if toGreen < 8 { return nil }

        let approach = GeoMath.bearing(from, green)
        let cap = min(maxMeters, toGreen)

        if toGreen <= maxMeters, isPointInGreen(green, holeFeatures) || isPointInFairway(green, holeFeatures) {
            return green
        }

        var targetAlong = cap
        while targetAlong >= 15 {
            defer { targetAlong -= 8 }
            guard let center = fairwayCenter(from: from, approach: approach, along: targetAlong, holeFeatures) else { continue }
            if !isPointInFairway(center, holeFeatures) && !isPointInGreen(center, holeFeatures) { continue }
            if GeoMath.distanceMeters(from, center) > maxMeters + 2 { continue }
            let along = GeoMath.distanceMeters(from, center)
                * cos(GeoMath.bearingDifferenceRadians(approach, GeoMath.bearing(from, center)))
            if along <= 0 { continue }
            return center
        }

        let fallback = GeoMath.destination(from: from, bearing: approach, meters: cap)
        if isPointInFairway(fallback, holeFeatures) || isPointInGreen(fallback, holeFeatures) {
            return fallback
        }
        return fairwayCenter(from: from, approach: approach, along: cap * 0.85, holeFeatures) ?? fallback
    }

    public static func plannedShots(start: Coordinate, green: Coordinate, _ holeFeatures: [GolfFeature]) -> [PlannedShotSegment] {
        var segments: [PlannedShotSegment] = []
        var current = start
        var shotNumber = 1

        for _ in 0..<6 {
            if GeoMath.distanceMeters(current, green) < 10 { break }
            let maxYards = shotNumber == 1 ? maxPlannedShotYards : maxFollowUpPlannedShotYards
            guard let target = optimalFairwayLanding(from: current, green: green, holeFeatures, maxShotYards: maxYards) else { break }

            let yards = GeoMath.yardsBetween(current, target)
            if !segments.isEmpty && yards < 18 { break }

            let bearing = GeoMath.bearing(current, target)
            let carryMeters = GeoMath.distanceMeters(current, target) * (shotNumber == 1 ? 0.88 : 0.85)
            segments.append(PlannedShotSegment(
                shotNumber: shotNumber,
                from: current,
                to: target,
                yards: yards,
                carryYards: GeoMath.yards(meters: carryMeters),
                carryPoint: GeoMath.destination(from: current, bearing: bearing, meters: carryMeters)
            ))
            shotNumber += 1

            if GeoMath.distanceMeters(target, green) < 12 { break }
            current = target
        }
        return segments
    }

    // MARK: Editor helpers

    /// Index after the start vertex of the polygon edge nearest `point`.
    public static func insertIndex(onRing vertices: [Coordinate], for point: Coordinate) -> Int {
        if vertices.isEmpty { return 0 }
        if vertices.count == 1 { return 1 }
        var bestEdge = 0
        var bestDistance = Double.infinity
        for index in vertices.indices {
            let d = GeoMath.alongTrackDistanceToSegmentMeters(point, vertices[index], vertices[(index + 1) % vertices.count])
            if d < bestDistance {
                bestDistance = d
                bestEdge = index
            }
        }
        return bestEdge + 1
    }

    /// Outline rings for a hole: fairway rings, or a convex hull of fairway/green/tee points.
    public static func boundaryRings(_ features: [GolfFeature], course: String?, hole: String, activeOnly: Bool) -> [[Coordinate]] {
        var rings: [[Coordinate]] = []
        for fairway in features where fairway.isType("fairway") {
            if activeOnly && !fairway.isActive(course: course, hole: hole) { continue }
            rings.append(contentsOf: fairway.geometry.rings.filter { $0.count >= 3 })
        }
        if !rings.isEmpty { return rings }
        var points: [Coordinate] = []
        for type in ["fairway", "green", "tee"] {
            for feature in features where feature.isType(type) {
                if activeOnly && !feature.isActive(course: course, hole: hole) { continue }
                points.append(contentsOf: feature.geometry.allPoints)
            }
        }
        let hull = GeoMath.convexHull(points)
        return hull.count >= 3 ? [hull] : []
    }
}
