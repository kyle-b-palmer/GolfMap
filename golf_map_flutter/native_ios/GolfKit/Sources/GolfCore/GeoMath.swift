import Foundation

/// Spherical math matching the Flutter app (turf 0.0.12) so yardages agree to the yard.
public enum GeoMath {
    /// turf's mean earth radius, used for distances and bearings.
    public static let earthRadiusMeters = 6371008.8
    /// Radius the Flutter app uses when projecting a point along a bearing.
    public static let projectionEarthRadiusMeters = 6378137.0
    public static let yardsPerMeter = 1.09361

    @inline(__always)
    static func radians(_ degrees: Double) -> Double {
        degrees.truncatingRemainder(dividingBy: 360) * .pi / 180
    }

    @inline(__always)
    static func degrees(_ radians: Double) -> Double {
        radians.truncatingRemainder(dividingBy: 2 * .pi) * 180 / .pi
    }

    /// Haversine distance in meters.
    public static func distanceMeters(_ from: Coordinate, _ to: Coordinate) -> Double {
        haversineRadians(from, to) * earthRadiusMeters
    }

    static func haversineRadians(_ from: Coordinate, _ to: Coordinate) -> Double {
        let dLat = radians(to.latitude - from.latitude)
        let dLon = radians(to.longitude - from.longitude)
        let lat1 = radians(from.latitude)
        let lat2 = radians(to.latitude)
        let a = pow(sin(dLat / 2), 2) + pow(sin(dLon / 2), 2) * cos(lat1) * cos(lat2)
        return 2 * atan2(sqrt(a), sqrt(1 - a))
    }

    /// Initial bearing in degrees, range (-180, 180].
    public static func bearing(_ from: Coordinate, _ to: Coordinate) -> Double {
        let lng1 = radians(from.longitude)
        let lng2 = radians(to.longitude)
        let lat1 = radians(from.latitude)
        let lat2 = radians(to.latitude)
        let a = sin(lng2 - lng1) * cos(lat2)
        let b = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(lng2 - lng1)
        return degrees(atan2(a, b))
    }

    public static func destination(from: Coordinate, bearing bearingDegrees: Double, meters: Double) -> Coordinate {
        let bearing = bearingDegrees * .pi / 180
        let lat1 = from.latitude * .pi / 180
        let lng1 = from.longitude * .pi / 180
        let angular = meters / projectionEarthRadiusMeters

        let lat2 = asin(sin(lat1) * cos(angular) + cos(lat1) * sin(angular) * cos(bearing))
        let lng2 = lng1 + atan2(
            sin(bearing) * sin(angular) * cos(lat1),
            cos(angular) - sin(lat1) * sin(lat2)
        )
        return Coordinate(latitude: lat2 * 180 / .pi, longitude: lng2 * 180 / .pi)
    }

    /// Rounded yards, half away from zero.
    public static func yards(meters: Double) -> Int {
        Int((meters * yardsPerMeter).rounded())
    }

    public static func signedYards(meters: Double) -> Int {
        let yards = Int((abs(meters) * yardsPerMeter).rounded())
        return meters < 0 ? -yards : yards
    }

    public static func yardsBetween(_ a: Coordinate, _ b: Coordinate) -> Int {
        yards(meters: distanceMeters(a, b))
    }

    /// Dart's `%` for doubles: result has the sign of a positive divisor.
    @inline(__always)
    static func positiveModulo(_ value: Double, _ divisor: Double) -> Double {
        let remainder = value.truncatingRemainder(dividingBy: divisor)
        return remainder < 0 ? remainder + divisor : remainder
    }

    static func bearingDifferenceRadians(_ fromBearing: Double, _ toBearing: Double) -> Double {
        var diff = positiveModulo(toBearing - fromBearing, 360)
        if diff > 180 { diff -= 360 }
        if diff < -180 { diff += 360 }
        return diff * .pi / 180
    }

    /// turf `pointToLineDistance` for one segment: closest point found in degree space, measured by haversine.
    public static func distanceToSegmentMeters(_ p: Coordinate, _ a: Coordinate, _ b: Coordinate) -> Double {
        let vx = b.longitude - a.longitude, vy = b.latitude - a.latitude
        let wx = p.longitude - a.longitude, wy = p.latitude - a.latitude
        let c1 = wx * vx + wy * vy
        let radiansDistance: Double
        if c1 <= 0 {
            radiansDistance = haversineRadians(p, a)
        } else {
            let c2 = vx * vx + vy * vy
            if c2 <= c1 {
                radiansDistance = haversineRadians(p, b)
            } else {
                let t = c1 / c2
                let projected = Coordinate(latitude: a.latitude + vy * t, longitude: a.longitude + vx * t)
                radiansDistance = haversineRadians(p, projected)
            }
        }
        let degreesFactor = earthRadiusMeters / 111325
        let inDegreeUnits = radiansDistance * degreesFactor
        return (inDegreeUnits / degreesFactor) * earthRadiusMeters
    }

    /// Bearing-decomposed distance from a point to a segment (the app's own helper).
    public static func alongTrackDistanceToSegmentMeters(_ p: Coordinate, _ a: Coordinate, _ b: Coordinate) -> Double {
        let ab = distanceMeters(a, b)
        if ab < 0.001 { return distanceMeters(p, a) }
        let ap = distanceMeters(a, p)
        let diff = bearingDifferenceRadians(bearing(a, b), bearing(a, p))
        let along = ap * cos(diff)
        if along <= 0 { return ap }
        if along >= ab { return distanceMeters(p, b) }
        return ap * abs(sin(diff))
    }

    public static func isPoint(_ point: Coordinate, inRing ring: [Coordinate]) -> Bool {
        var inside = false
        var j = ring.count - 1
        for i in 0..<ring.count {
            let yi = ring[i].latitude, yj = ring[j].latitude
            let xi = ring[i].longitude, xj = ring[j].longitude
            if (yi > point.latitude) != (yj > point.latitude),
               point.longitude < (xj - xi) * (point.latitude - yi) / (yj - yi) + xi {
                inside.toggle()
            }
            j = i
        }
        return inside
    }

    /// Map rotation so the tee is at the bottom and the green at the top.
    public static func mapRotation(tee: Coordinate, green: Coordinate) -> Double {
        positiveModulo(360 - bearing(tee, green), 360)
    }

    static func convexHull(_ input: [Coordinate]) -> [Coordinate] {
        guard input.count > 2 else { return input }
        let points = input.enumerated().sorted { lhs, rhs in
            if lhs.element.latitude != rhs.element.latitude { return lhs.element.latitude < rhs.element.latitude }
            if lhs.element.longitude != rhs.element.longitude { return lhs.element.longitude < rhs.element.longitude }
            return lhs.offset < rhs.offset
        }.map(\.element)

        func cross(_ o: Coordinate, _ a: Coordinate, _ b: Coordinate) -> Double {
            (a.longitude - o.longitude) * (b.latitude - o.latitude)
                - (a.latitude - o.latitude) * (b.longitude - o.longitude)
        }

        var lower: [Coordinate] = []
        for p in points {
            while lower.count >= 2, cross(lower[lower.count - 2], lower[lower.count - 1], p) <= 0 {
                lower.removeLast()
            }
            lower.append(p)
        }
        var upper: [Coordinate] = []
        for p in points.reversed() {
            while upper.count >= 2, cross(upper[upper.count - 2], upper[upper.count - 1], p) <= 0 {
                upper.removeLast()
            }
            upper.append(p)
        }
        lower.removeLast()
        upper.removeLast()
        return lower + upper
    }
}
