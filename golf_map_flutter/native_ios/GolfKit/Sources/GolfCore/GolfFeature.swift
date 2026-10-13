import Foundation

public struct GolfFeature: Hashable, Sendable, Identifiable {
    public var id: FeatureID?
    public var featureType: String?
    public var holeNumber: String?
    public var name: String?
    public var par: Int?
    public var handicap: Int?
    public var courseName: String?
    public var geometry: Geometry

    public init(
        id: FeatureID?,
        featureType: String?,
        holeNumber: String?,
        name: String?,
        par: Int?,
        handicap: Int?,
        courseName: String?,
        geometry: Geometry
    ) {
        self.id = id
        self.featureType = featureType
        self.holeNumber = holeNumber
        self.name = name
        self.par = par
        self.handicap = handicap
        self.courseName = courseName
        self.geometry = geometry
    }

    public func matchesCourse(_ course: String?) -> Bool {
        guard let course, let courseName else { return false }
        return courseName.trimmingCharacters(in: .whitespacesAndNewlines)
            == course.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func matchesHole(_ hole: String) -> Bool {
        holeNumber == hole
    }

    public func isActive(course: String?, hole: String) -> Bool {
        matchesCourse(course) && matchesHole(hole)
    }

    public func isType(_ type: String) -> Bool { featureType == type }

    /// Row shape shared by the bundled asset, Supabase `golf_features`, and local traced courses.
    public var row: JSONValue {
        var object: [String: JSONValue] = [
            "feature_type": featureType.map(JSONValue.string) ?? .null,
            "hole_number": holeNumber.map(JSONValue.string) ?? .null,
            "name": name.map(JSONValue.string) ?? .null,
            "course_name": courseName.map(JSONValue.string) ?? .null,
            "geom": geometry.json,
        ]
        object["id"] = id?.jsonValue ?? .null
        if let par { object["par"] = .int(par) }
        if let handicap { object["handicap"] = .int(handicap) }
        return .object(object)
    }

    public var geoJSONFeature: JSONValue {
        .object([
            "type": .string("Feature"),
            "id": id?.jsonValue ?? .null,
            "properties": .object([
                "feature_type": featureType.map(JSONValue.string) ?? .null,
                "hole_number": holeNumber.map(JSONValue.string) ?? .null,
                "name": name.map(JSONValue.string) ?? .null,
                "par": par.map(JSONValue.int) ?? .null,
                "handicap": handicap.map(JSONValue.int) ?? .null,
                "course_name": courseName.map(JSONValue.string) ?? .null,
            ]),
            "geometry": geometry.json,
        ])
    }
}

public enum FeatureRowDecodingError: Error, Equatable {
    case notAnArray
    case invalidRow(index: Int, reason: String)
}

public enum FeatureRowDecoder {
    /// Decodes rows; `geom` may be an object or a JSON string, and the string `"null"` hole number is nil.
    public static func decode(_ data: Data) throws -> [GolfFeature] {
        guard let rows = try JSONValue.parse(data).arrayValue else {
            throw FeatureRowDecodingError.notAnArray
        }
        return try rows.enumerated().map { index, row in
            try decodeRow(row, index: index)
        }
    }

    public static func decodeRow(_ row: JSONValue, index: Int = 0) throws -> GolfFeature {
        guard let object = row.objectValue else {
            throw FeatureRowDecodingError.invalidRow(index: index, reason: "row is not an object")
        }
        var geometryJSON = object["geom"] ?? .null
        if case .string(let text) = geometryJSON {
            geometryJSON = (try? JSONValue.parse(Data(text.utf8))) ?? .null
        }
        guard let geometry = Geometry(json: geometryJSON) else {
            throw FeatureRowDecodingError.invalidRow(index: index, reason: "missing geometry")
        }

        var holeNumber = object["hole_number"]?.dartString
        if holeNumber?.lowercased() == "null" { holeNumber = nil }

        return GolfFeature(
            id: FeatureID(json: object["id"]),
            featureType: object["feature_type"]?.stringValue,
            holeNumber: holeNumber,
            name: object["name"]?.stringValue,
            par: object["par"]?.lenientInt,
            handicap: object["handicap"]?.lenientInt,
            courseName: object["course_name"]?.stringValue,
            geometry: geometry
        )
    }
}
