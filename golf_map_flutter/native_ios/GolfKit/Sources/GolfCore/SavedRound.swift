import Foundation

public enum PinType: String, Hashable, Sendable, Codable {
    case shot
    case lostBall

    public var label: String { self == .shot ? "shot" : "lost ball" }

    public init(storage: String?) {
        self = storage == "lostBall" ? .lostBall : .shot
    }
}

public struct PinnedShot: Hashable, Sendable, Codable, Identifiable {
    /// Stable identity used by undo and cross-device sync. Legacy pins receive a deterministic ID on import.
    public var id: String
    public var shotNumber: Int
    public var latitude: Double
    public var longitude: Double
    public var fromLatitude: Double
    public var fromLongitude: Double
    public var teeLabel: String?
    /// Length of this shot segment (from the tee or the previous pin).
    public var shotYards: Int?
    public var yardsToPin: Int?
    public var pinType: PinType

    public init(
        id: String = UUID().uuidString,
        shotNumber: Int,
        latitude: Double,
        longitude: Double,
        fromLatitude: Double,
        fromLongitude: Double,
        teeLabel: String? = nil,
        shotYards: Int? = nil,
        yardsToPin: Int? = nil,
        pinType: PinType = .shot
    ) {
        self.id = id
        self.shotNumber = shotNumber
        self.latitude = latitude
        self.longitude = longitude
        self.fromLatitude = fromLatitude
        self.fromLongitude = fromLongitude
        self.teeLabel = teeLabel
        self.shotYards = shotYards
        self.yardsToPin = yardsToPin
        self.pinType = pinType
    }

    public var coordinate: Coordinate { Coordinate(latitude: latitude, longitude: longitude) }
    public var origin: Coordinate { Coordinate(latitude: fromLatitude, longitude: fromLongitude) }

    /// Legacy decoding: missing origin falls back to the pin, `yardsFromTee` maps to `shotYards`.
    static func legacy(_ json: JSONValue, fallbackID: String) -> PinnedShot? {
        guard let object = json.objectValue,
              let shotNumber = object["shotNumber"]?.truncatedInt,
              let lat = object["latitude"]?.numberValue,
              let lng = object["longitude"]?.numberValue else { return nil }
        return PinnedShot(
            id: object["id"]?.stringValue ?? fallbackID,
            shotNumber: shotNumber,
            latitude: lat,
            longitude: lng,
            fromLatitude: object["fromLatitude"]?.numberValue ?? lat,
            fromLongitude: object["fromLongitude"]?.numberValue ?? lng,
            teeLabel: object["teeLabel"]?.stringValue,
            shotYards: object["shotYards"]?.truncatedInt ?? object["yardsFromTee"]?.truncatedInt,
            yardsToPin: object["yardsToPin"]?.truncatedInt,
            pinType: PinType(storage: object["pinType"]?.stringValue)
        )
    }

    /// Flutter-compatible JSON (no `id`, default pin type omitted).
    var legacyJSON: JSONValue {
        var object: [String: JSONValue] = [
            "shotNumber": .int(shotNumber),
            "latitude": .double(latitude),
            "longitude": .double(longitude),
            "fromLatitude": .double(fromLatitude),
            "fromLongitude": .double(fromLongitude),
        ]
        if let teeLabel { object["teeLabel"] = .string(teeLabel) }
        if let shotYards { object["shotYards"] = .int(shotYards) }
        if let yardsToPin { object["yardsToPin"] = .int(yardsToPin) }
        if pinType != .shot { object["pinType"] = .string(pinType.rawValue) }
        return .object(object)
    }
}

public struct MeasurementChainPoint: Hashable, Sendable, Codable {
    public var latitude: Double
    public var longitude: Double
    public var segmentYards: Int
    public var shotNumber: Int

    public init(latitude: Double, longitude: Double, segmentYards: Int, shotNumber: Int) {
        self.latitude = latitude
        self.longitude = longitude
        self.segmentYards = segmentYards
        self.shotNumber = shotNumber
    }

    public var coordinate: Coordinate { Coordinate(latitude: latitude, longitude: longitude) }

    static func legacy(_ json: JSONValue) -> MeasurementChainPoint? {
        guard let object = json.objectValue,
              let lat = object["latitude"]?.numberValue,
              let lng = object["longitude"]?.numberValue,
              let segment = object["segmentYards"]?.truncatedInt,
              let shot = object["shotNumber"]?.truncatedInt else { return nil }
        return MeasurementChainPoint(latitude: lat, longitude: lng, segmentYards: segment, shotNumber: shot)
    }

    var legacyJSON: JSONValue {
        .object([
            "latitude": .double(latitude),
            "longitude": .double(longitude),
            "segmentYards": .int(segmentYards),
            "shotNumber": .int(shotNumber),
        ])
    }
}

public struct SavedRound: Hashable, Sendable, Codable, Identifiable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var id: String
    public var courseName: String
    public var playedAt: DartDate
    public var scores: [String: Int]
    public var putts: [String: Int]
    public var pinnedShots: [String: [PinnedShot]]
    public var measurementChains: [String: [MeasurementChainPoint]]
    public var lockedHoles: Set<String>

    public init(
        id: String,
        courseName: String,
        playedAt: DartDate,
        scores: [String: Int],
        putts: [String: Int] = [:],
        pinnedShots: [String: [PinnedShot]] = [:],
        measurementChains: [String: [MeasurementChainPoint]] = [:],
        lockedHoles: Set<String> = []
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.id = id
        self.courseName = courseName
        self.playedAt = playedAt
        self.scores = scores
        self.putts = putts
        self.pinnedShots = pinnedShots
        self.measurementChains = measurementChains
        self.lockedHoles = lockedHoles
    }

    public var totalStrokes: Int { scores.values.reduce(0, +) }
    public var totalPutts: Int { putts.values.reduce(0, +) }
    public var holesScored: Int { scores.values.filter { $0 > 0 }.count }

    /// Pinned shots, or chain points when a round has no pins.
    public var totalPinnedShots: Int {
        let pins = pinnedShots.values.reduce(0) { $0 + $1.count }
        if pins > 0 { return pins }
        return measurementChains.values.reduce(0) { $0 + $1.count }
    }

    public enum LegacyDecodingError: Error, Equatable {
        case notAnObject
        case missingField(String)
        case invalidDate(String)
    }

    /// Decodes one record from the Flutter `saved_golf_rounds` list.
    /// Malformed shot/chain entries are skipped, matching the Flutter app.
    public static func legacy(_ json: JSONValue, timeZone: TimeZone = .current) throws -> SavedRound {
        guard let object = json.objectValue else { throw LegacyDecodingError.notAnObject }
        guard let id = object["id"]?.stringValue else { throw LegacyDecodingError.missingField("id") }
        guard let courseName = object["courseName"]?.stringValue else { throw LegacyDecodingError.missingField("courseName") }
        guard let playedText = object["playedAt"]?.stringValue else { throw LegacyDecodingError.missingField("playedAt") }
        guard let playedAt = DartDate.parse(playedText, timeZone: timeZone) else { throw LegacyDecodingError.invalidDate(playedText) }

        func intMap(_ value: JSONValue?) -> [String: Int] {
            var result: [String: Int] = [:]
            for (key, value) in value?.objectValue ?? [:] {
                if let number = value.truncatedInt { result[key] = number }
            }
            return result
        }

        var pins: [String: [PinnedShot]] = [:]
        for (hole, list) in object["pinnedShots"]?.objectValue ?? [:] {
            guard let items = list.arrayValue else { continue }
            let parsed = items.enumerated().compactMap { index, item in
                PinnedShot.legacy(item, fallbackID: "\(id)-\(hole)-\(index)")
            }
            pins[hole] = stableSorted(parsed) { $0.shotNumber < $1.shotNumber }
        }

        var chains: [String: [MeasurementChainPoint]] = [:]
        for (hole, list) in object["measurementChains"]?.objectValue ?? [:] {
            guard let items = list.arrayValue else { continue }
            chains[hole] = stableSorted(items.compactMap(MeasurementChainPoint.legacy)) { $0.shotNumber < $1.shotNumber }
        }

        let scores = intMap(object["scores"])
        let locked: Set<String>
        if let list = object["lockedHoles"]?.arrayValue {
            locked = Set(list.compactMap(\.dartString))
        } else {
            let inferred = Set(pins.keys).union(chains.keys)
            locked = inferred.isEmpty ? Set(scores.keys) : inferred
        }

        return SavedRound(
            id: id,
            courseName: courseName,
            playedAt: playedAt,
            scores: scores,
            putts: intMap(object["putts"]),
            pinnedShots: pins,
            measurementChains: chains,
            lockedHoles: locked
        )
    }

    /// Flutter-compatible representation, used for export and parity checks.
    public func legacyJSON(timeZone: TimeZone = .current) -> JSONValue {
        .object([
            "id": .string(id),
            "courseName": .string(courseName),
            "playedAt": .string(playedAt.iso8601String(timeZone: timeZone)),
            "scores": .object(scores.mapValues(JSONValue.int)),
            "putts": .object(putts.mapValues(JSONValue.int)),
            "pinnedShots": .object(pinnedShots.mapValues { .array($0.map(\.legacyJSON)) }),
            "measurementChains": .object(measurementChains.mapValues { .array($0.map(\.legacyJSON)) }),
            "lockedHoles": .array(lockedHoles.sorted(by: dartLess).map(JSONValue.string)),
        ])
    }
}

func stableSorted<T>(_ items: [T], by less: (T, T) -> Bool) -> [T] {
    items.enumerated().sorted { a, b in
        if less(a.element, b.element) { return true }
        if less(b.element, a.element) { return false }
        return a.offset < b.offset
    }.map(\.element)
}
