import Foundation

/// Open-Meteo current conditions, the source the Flutter app uses.
public enum OpenMeteo {
    public static func currentConditionsURL(for point: Coordinate) -> URL {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(point.latitude)),
            URLQueryItem(name: "longitude", value: String(point.longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,wind_speed_10m,wind_direction_10m"),
            URLQueryItem(name: "temperature_unit", value: "fahrenheit"),
            URLQueryItem(name: "wind_speed_unit", value: "mph"),
            URLQueryItem(name: "timezone", value: "auto"),
        ]
        return components.url!
    }

    /// Nil unless temperature, wind speed, and wind direction are all present. Elevation arrives in meters.
    public static func parse(_ data: Data) -> WeatherConditions? {
        guard let object = (try? JSONValue.parse(data))?.objectValue,
              let current = object["current"]?.objectValue,
              let temperature = current["temperature_2m"]?.numberValue,
              let wind = current["wind_speed_10m"]?.numberValue,
              let direction = current["wind_direction_10m"]?.numberValue else { return nil }
        return WeatherConditions(
            temperatureF: temperature,
            windMph: wind,
            windDirectionDeg: direction,
            elevationFeet: object["elevation"]?.numberValue.map { $0 * 3.28084 }
        )
    }
}

/// Flutter's weather reuse rules: a reading is fresh for 15 minutes within 500 meters, and the last reading
/// (however old or far away) stands in when a fetch fails.
public struct WeatherCache: Sendable, Hashable {
    public static let freshness: TimeInterval = 15 * 60
    public static let radiusMeters: Double = 500

    public private(set) var conditions: WeatherConditions?
    public private(set) var point: Coordinate?
    public private(set) var fetchedAt: Date?

    public init() {}

    public func fresh(for point: Coordinate, now: Date) -> WeatherConditions? {
        guard let conditions, let cachedPoint = self.point, let fetchedAt,
              now.timeIntervalSince(fetchedAt) < Self.freshness,
              Self.distanceMeters(cachedPoint, point) < Self.radiusMeters else { return nil }
        return conditions
    }

    public mutating func store(_ conditions: WeatherConditions, for point: Coordinate, at date: Date) {
        self.conditions = conditions
        self.point = point
        fetchedAt = date
    }

    /// Haversine on the WGS 84 equatorial radius, as the Flutter weather service computes it.
    static func distanceMeters(_ a: Coordinate, _ b: Coordinate) -> Double {
        let earthRadius = 6_378_137.0
        let dLat = (b.latitude - a.latitude) * .pi / 180
        let dLng = (b.longitude - a.longitude) * .pi / 180
        let lat1 = a.latitude * .pi / 180
        let lat2 = b.latitude * .pi / 180
        let h = sin(dLat / 2) * sin(dLat / 2) + sin(dLng / 2) * sin(dLng / 2) * cos(lat1) * cos(lat2)
        return earthRadius * 2 * atan2(h.squareRoot(), (1 - h).squareRoot())
    }
}

/// Plays-like yardage to the middle of the green and the club for it.
public struct ShotAdvice: Hashable, Sendable {
    public var actualYards: Int
    public var playsLikeYards: Int
    public var suggestion: ClubSuggestion?

    /// Flutter shows the adjusted number only when it differs by two yards or more.
    public var showsPlaysLike: Bool { abs(playsLikeYards - actualYards) >= 2 }

    /// Driver is only offered from a tee box before any shot is tracked on the hole.
    public static func make(
        actualYards: Int?,
        origin: Coordinate,
        greenCenter: Coordinate?,
        weather: WeatherConditions?,
        clubs: [ClubDistance],
        onTeeBox: Bool,
        hasTrackedShots: Bool
    ) -> ShotAdvice? {
        guard let actualYards, actualYards > 0 else { return nil }
        let bearing = greenCenter.map { GeoMath.bearing(origin, $0) }
        let playsLike = PlaysLike.yards(actual: actualYards, weather: weather, shotBearingDeg: bearing)
        let suggestion = ClubAdvisor.suggest(yards: playsLike, clubs: clubs, allowDriver: onTeeBox && !hasTrackedShots)
        return ShotAdvice(actualYards: actualYards, playsLikeYards: playsLike, suggestion: suggestion)
    }
}
