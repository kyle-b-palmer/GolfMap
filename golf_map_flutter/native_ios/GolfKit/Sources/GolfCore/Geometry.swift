import Foundation

/// GeoJSON geometry with longitude/latitude coordinate order on the wire.
public enum Geometry: Hashable, Sendable {
    case point(Coordinate)
    case multiPoint([Coordinate])
    case lineString([Coordinate])
    case multiLineString([[Coordinate]])
    case polygon([[Coordinate]])
    case multiPolygon([[[Coordinate]]])
    case unsupported(type: String, coordinates: JSONValue)

    public var typeName: String {
        switch self {
        case .point: return "Point"
        case .multiPoint: return "MultiPoint"
        case .lineString: return "LineString"
        case .multiLineString: return "MultiLineString"
        case .polygon: return "Polygon"
        case .multiPolygon: return "MultiPolygon"
        case .unsupported(let type, _): return type
        }
    }

    /// Parses a GeoJSON object; drops `crs` and any altitude values.
    public init?(json: JSONValue) {
        guard let object = json.objectValue,
              let type = object["type"]?.stringValue else { return nil }
        let coordinates = object["coordinates"] ?? .null

        func position(_ value: JSONValue) -> Coordinate? {
            guard let array = value.arrayValue, array.count >= 2,
                  let lng = array[0].numberValue, let lat = array[1].numberValue else { return nil }
            return Coordinate(latitude: lat, longitude: lng)
        }
        func line(_ value: JSONValue) -> [Coordinate] {
            (value.arrayValue ?? []).compactMap(position)
        }
        func rings(_ value: JSONValue) -> [[Coordinate]] {
            (value.arrayValue ?? []).map(line)
        }

        switch type {
        case "Point":
            guard let point = position(coordinates) else {
                self = .unsupported(type: type, coordinates: coordinates)
                return
            }
            self = .point(point)
        case "MultiPoint": self = .multiPoint(line(coordinates))
        case "LineString": self = .lineString(line(coordinates))
        case "MultiLineString": self = .multiLineString(rings(coordinates))
        case "Polygon": self = .polygon(rings(coordinates))
        case "MultiPolygon": self = .multiPolygon((coordinates.arrayValue ?? []).map(rings))
        default: self = .unsupported(type: type, coordinates: coordinates)
        }
    }

    public var json: JSONValue {
        func position(_ c: Coordinate) -> JSONValue { .array([.double(c.longitude), .double(c.latitude)]) }
        func line(_ cs: [Coordinate]) -> JSONValue { .array(cs.map(position)) }
        func rings(_ rs: [[Coordinate]]) -> JSONValue { .array(rs.map(line)) }

        let coordinates: JSONValue
        switch self {
        case .point(let c): coordinates = position(c)
        case .multiPoint(let cs), .lineString(let cs): coordinates = line(cs)
        case .multiLineString(let rs), .polygon(let rs): coordinates = rings(rs)
        case .multiPolygon(let polys): coordinates = .array(polys.map(rings))
        case .unsupported(_, let raw): coordinates = raw
        }
        return .object(["type": .string(typeName), "coordinates": coordinates])
    }

    /// Every coordinate in document order, including ring closing points.
    public var allPoints: [Coordinate] {
        switch self {
        case .point(let c): return [c]
        case .multiPoint(let cs), .lineString(let cs): return cs
        case .multiLineString(let rs), .polygon(let rs): return rs.flatMap { $0 }
        case .multiPolygon(let polys): return polys.flatMap { $0.flatMap { $0 } }
        case .unsupported(_, let raw):
            var points: [Coordinate] = []
            Geometry.walk(raw) { points.append($0) }
            return points
        }
    }

    private static func walk(_ value: JSONValue, _ emit: (Coordinate) -> Void) {
        guard let array = value.arrayValue, !array.isEmpty else { return }
        if let lng = array[0].numberValue, array.count >= 2, let lat = array[1].numberValue {
            emit(Coordinate(latitude: lat, longitude: lng))
            return
        }
        for part in array { walk(part, emit) }
    }

    /// Polygon rings, or the outer ring of each MultiPolygon member.
    public var rings: [[Coordinate]] {
        switch self {
        case .polygon(let rs): return rs
        case .multiPolygon(let polys): return polys.compactMap { $0.first }
        default: return []
        }
    }

    public var lineStrings: [[Coordinate]] {
        if case .lineString(let cs) = self, cs.count >= 2 { return [cs] }
        return []
    }

    /// Mean of coordinates, excluding each polygon ring's last (closing) coordinate.
    public var centroid: Coordinate? {
        var latSum = 0.0, lngSum = 0.0, count = 0
        func add(_ c: Coordinate) { lngSum += c.longitude; latSum += c.latitude; count += 1 }
        switch self {
        case .point(let c): add(c)
        case .multiPoint(let cs), .lineString(let cs): cs.forEach(add)
        case .multiLineString(let rs): rs.forEach { $0.forEach(add) }
        case .polygon(let rs): rs.forEach { $0.dropLast().forEach(add) }
        case .multiPolygon(let polys): polys.forEach { $0.forEach { $0.dropLast().forEach(add) } }
        case .unsupported:
            let points = allPoints
            guard !points.isEmpty else { return nil }
            let lat = points.map(\.latitude).reduce(0, +) / Double(points.count)
            let lng = points.map(\.longitude).reduce(0, +) / Double(points.count)
            return Coordinate(latitude: lat, longitude: lng)
        }
        guard count > 0 else { return nil }
        return Coordinate(latitude: latSum / Double(count), longitude: lngSum / Double(count))
    }

    /// Representative point: Point itself, LineString midpoint, otherwise centroid.
    public var representativePoint: Coordinate? {
        if case .point(let c) = self { return c }
        let points = allPoints
        guard !points.isEmpty else { return nil }
        if case .lineString = self { return points[points.count / 2] }
        return centroid
    }

    public static func polygon(vertices: [Coordinate]) -> Geometry {
        var ring = vertices
        if let first = ring.first, let last = ring.last, first != last {
            ring.append(first)
        }
        return .polygon([ring])
    }

    /// Outer ring vertices without the closing duplicate point.
    public var editableVertices: [Coordinate] {
        guard var ring = rings.first else { return [] }
        if ring.count >= 2, let first = ring.first, let last = ring.last,
           abs(first.latitude - last.latitude) < 1e-7, abs(first.longitude - last.longitude) < 1e-7 {
            ring.removeLast()
        }
        return ring
    }
}
