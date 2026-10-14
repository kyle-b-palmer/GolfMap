import Foundation
import GolfCore

/// Sync protocol versions. Version 1 payloads have no event IDs; version 2 adds them as optional keys.
public enum SyncProtocol {
    public static let current = 2
    public static let pinMatchYards = 3
    public static let undoProximityYards = 25
}

/// A pin or undo request exchanged between phone, Watch, and Live Activity.
public struct GolfRoundGpsPin: Codable, Hashable, Sendable {
    public let hole: String
    public let latitude: Double
    public let longitude: Double
    public var pinKind: String?
    /// Links this GPS pin to a Plotter-compatible IMU session transferred separately.
    public var imuSessionId: String?
    /// Version 2: identity of the pin. On an undo entry, the identity of the pin being undone.
    public var eventId: String?

    public init(
        hole: String,
        latitude: Double,
        longitude: Double,
        pinKind: String? = nil,
        imuSessionId: String? = nil,
        eventId: String? = UUID().uuidString
    ) {
        self.hole = hole
        self.latitude = latitude
        self.longitude = longitude
        self.pinKind = pinKind
        self.imuSessionId = imuSessionId
        self.eventId = eventId
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hole = try container.decode(String.self, forKey: .hole)
        latitude = try container.decode(Double.self, forKey: .latitude)
        longitude = try container.decode(Double.self, forKey: .longitude)
        pinKind = try container.decodeIfPresent(String.self, forKey: .pinKind)
        imuSessionId = try container.decodeIfPresent(String.self, forKey: .imuSessionId)
        eventId = try container.decodeIfPresent(String.self, forKey: .eventId)
    }

    public var coordinate: Coordinate { Coordinate(latitude: latitude, longitude: longitude) }
    public var isLostBall: Bool { pinKind == "lostBall" }

    public func yards(to other: GolfRoundGpsPin) -> Int {
        GeoMath.yardsBetween(coordinate, other.coordinate)
    }

    /// Same pin: matching event IDs when both have one, otherwise the same hole within 3 yards (version 1).
    public func refersToSamePin(as other: GolfRoundGpsPin) -> Bool {
        guard hole == other.hole else { return false }
        if let eventId, let otherId = other.eventId { return eventId == otherId }
        return yards(to: other) < SyncProtocol.pinMatchYards
    }

    /// Version 1 rule: an undo cancels a pin on the same hole within 25 yards.
    public func isNearby(_ other: GolfRoundGpsPin) -> Bool {
        hole == other.hole && yards(to: other) < SyncProtocol.undoProximityYards
    }
}

/// Round snapshot shared through the App Group (phone and Live Activity) and WatchConnectivity.
/// Scores, putts, pars, and handicaps are keyed by hole number.
public struct GolfRoundSharedState: Codable, Hashable, Sendable {
    public var holes: [String]
    public var selectedHole: String
    public var scores: [String: Int]
    public var putts: [String: Int]
    public var pars: [String: Int]
    public var handicaps: [String: Int]
    public var courseName: String
    public var yardsToGreen: Int
    public var revision: Int
    public var pendingGpsPins: [GolfRoundGpsPin]
    public var pendingGpsPinUndos: [GolfRoundGpsPin]
    public var greenLatitude: Double
    public var greenLongitude: Double
    public var gpsRefreshRevision: Int
    public var sessionId: String
    /// Absent in version 1 payloads.
    public var protocolVersion: Int?

    public static let appGroupId = "group.com.golfmapapp.golfMapFlutter"
    public static let phoneStorageKey = "golf_round_shared_state"
    public static let watchStorageKey = "golf_round_watch_state"
    public static let activeSessionIdKey = "golf_round_active_session_id"
    public static let hostActiveKey = "golf_round_host_active"
    public static let activityId = "golf-round-live"
    public static let changedNotification = "com.golfmapapp.golfMapFlutter.roundStateChanged"

    public init(
        holes: [String] = [],
        selectedHole: String = "1",
        scores: [String: Int] = [:],
        putts: [String: Int] = [:],
        pars: [String: Int] = [:],
        handicaps: [String: Int] = [:],
        courseName: String = "",
        yardsToGreen: Int = -1,
        revision: Int = 0,
        pendingGpsPins: [GolfRoundGpsPin] = [],
        pendingGpsPinUndos: [GolfRoundGpsPin] = [],
        greenLatitude: Double = 0,
        greenLongitude: Double = 0,
        gpsRefreshRevision: Int = 0,
        sessionId: String = "",
        protocolVersion: Int? = SyncProtocol.current
    ) {
        self.holes = holes
        self.selectedHole = selectedHole
        self.scores = scores
        self.putts = putts
        self.pars = pars
        self.handicaps = handicaps
        self.courseName = courseName
        self.yardsToGreen = yardsToGreen
        self.revision = revision
        self.pendingGpsPins = pendingGpsPins
        self.pendingGpsPinUndos = pendingGpsPinUndos
        self.greenLatitude = greenLatitude
        self.greenLongitude = greenLongitude
        self.gpsRefreshRevision = gpsRefreshRevision
        self.sessionId = sessionId
        self.protocolVersion = protocolVersion
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        holes = try c.decode([String].self, forKey: .holes)
        selectedHole = try c.decode(String.self, forKey: .selectedHole)
        scores = try c.decode([String: Int].self, forKey: .scores)
        putts = try c.decodeIfPresent([String: Int].self, forKey: .putts) ?? [:]
        pars = try c.decode([String: Int].self, forKey: .pars)
        handicaps = try c.decodeIfPresent([String: Int].self, forKey: .handicaps) ?? [:]
        courseName = try c.decode(String.self, forKey: .courseName)
        yardsToGreen = try c.decode(Int.self, forKey: .yardsToGreen)
        revision = try c.decode(Int.self, forKey: .revision)
        pendingGpsPins = try c.decodeIfPresent([GolfRoundGpsPin].self, forKey: .pendingGpsPins) ?? []
        pendingGpsPinUndos = try c.decodeIfPresent([GolfRoundGpsPin].self, forKey: .pendingGpsPinUndos) ?? []
        greenLatitude = try c.decodeIfPresent(Double.self, forKey: .greenLatitude) ?? 0
        greenLongitude = try c.decodeIfPresent(Double.self, forKey: .greenLongitude) ?? 0
        gpsRefreshRevision = try c.decodeIfPresent(Int.self, forKey: .gpsRefreshRevision) ?? 0
        sessionId = try c.decodeIfPresent(String.self, forKey: .sessionId) ?? ""
        protocolVersion = try c.decodeIfPresent(Int.self, forKey: .protocolVersion)
    }

    public var isActiveRound: Bool {
        !holes.isEmpty && !courseName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public var greenCoordinate: Coordinate? {
        greenLatitude == 0 && greenLongitude == 0 ? nil : Coordinate(latitude: greenLatitude, longitude: greenLongitude)
    }

    public var currentPar: Int { pars[selectedHole] ?? 0 }
    public var currentHandicap: Int { handicaps[selectedHole] ?? 0 }
    public var currentHoleScore: Int { scores[selectedHole] ?? 0 }
    public var currentHolePutts: Int { putts[selectedHole] ?? 0 }
    public var totalScore: Int { holes.reduce(0) { $0 + (scores[$1] ?? 0) } }
    public var totalPutts: Int { holes.reduce(0) { $0 + (putts[$1] ?? 0) } }

    public var relativeToPar: Int {
        holes.reduce(0) { sum, hole in
            let score = scores[hole] ?? 0, par = pars[hole] ?? 0
            guard score > 0, par > 0 else { return sum }
            return sum + (score - par)
        }
    }

    public func dictionaryPayload() -> [String: Any] {
        guard let data = try? JSONEncoder().encode(self),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return object
    }

    public static func fromDictionary(_ dictionary: [String: Any]) -> GolfRoundSharedState? {
        guard JSONSerialization.isValidJSONObject(dictionary),
              let data = try? JSONSerialization.data(withJSONObject: dictionary) else { return nil }
        return try? JSONDecoder().decode(GolfRoundSharedState.self, from: data)
    }
}

/// WatchConnectivity message shapes.
public enum WatchMessage {
    public static let roundStateType = "roundState"
    public static let sessionResetType = "sessionReset"
    public static let requestRoundStateType = "requestRoundState"

    public static func roundState(_ state: GolfRoundSharedState) -> [String: Any] {
        [
            "type": roundStateType,
            "revision": state.revision,
            "sessionId": state.sessionId,
            "state": state.dictionaryPayload(),
        ]
    }

    public static func sessionReset(sessionId: String) -> [String: Any] {
        ["type": sessionResetType, "sessionId": sessionId]
    }

    public static func decodeState(_ payload: [String: Any]) -> GolfRoundSharedState? {
        if let nested = payload["state"] as? [String: Any] {
            return GolfRoundSharedState.fromDictionary(nested)
        }
        return GolfRoundSharedState.fromDictionary(payload)
    }
}
