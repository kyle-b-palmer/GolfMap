import Foundation

public struct ClubDistance: Hashable, Sendable, Codable, Identifiable {
    public var name: String
    public var carryYards: Int

    public var id: String { name }

    public init(name: String, carryYards: Int) {
        self.name = name
        self.carryYards = carryYards
    }

    public static let defaultBag: [ClubDistance] = [
        ClubDistance(name: "DR", carryYards: 235),
        ClubDistance(name: "3W", carryYards: 215),
        ClubDistance(name: "5W", carryYards: 200),
        ClubDistance(name: "4H", carryYards: 190),
        ClubDistance(name: "5I", carryYards: 175),
        ClubDistance(name: "6I", carryYards: 165),
        ClubDistance(name: "7I", carryYards: 155),
        ClubDistance(name: "8I", carryYards: 145),
        ClubDistance(name: "9I", carryYards: 135),
        ClubDistance(name: "PW", carryYards: 120),
        ClubDistance(name: "GW", carryYards: 105),
        ClubDistance(name: "SW", carryYards: 90),
        ClubDistance(name: "LW", carryYards: 75),
    ]

    /// Decodes the legacy `club_bag_json` value; invalid or empty input yields the default bag.
    public static func decodeBag(_ json: String?) -> [ClubDistance] {
        guard let json, !json.isEmpty,
              let array = (try? JSONValue.parse(Data(json.utf8)))?.arrayValue else {
            return defaultBag
        }
        var clubs: [ClubDistance] = []
        for item in array {
            guard let object = item.objectValue,
                  let name = object["name"]?.stringValue,
                  let carry = object["carryYards"]?.truncatedInt else {
                if item.objectValue != nil { return defaultBag }
                continue
            }
            clubs.append(ClubDistance(name: name, carryYards: carry))
        }
        return clubs.isEmpty ? defaultBag : clubs
    }

    public static func encodeBag(_ clubs: [ClubDistance]) -> String {
        let data = (try? JSONEncoder().encode(clubs)) ?? Data("[]".utf8)
        return String(decoding: data, as: UTF8.self)
    }
}

public struct ClubSuggestion: Hashable, Sendable {
    public var club: String
    public var targetYards: Int
    public var alternateClub: String?
}

public enum ClubAdvisor {
    public static func isDriver(_ name: String) -> Bool {
        ["DR", "DRIVER", "1W", "D"].contains(name.trimmingCharacters(in: .whitespacesAndNewlines).uppercased())
    }

    /// Nearest carry distance; suggests the next club up/down when the target is well outside it.
    public static func suggest(yards: Int, clubs: [ClubDistance], allowDriver: Bool = true) -> ClubSuggestion? {
        guard yards > 0 else { return nil }
        let bag = clubs.isEmpty ? ClubDistance.defaultBag : clubs
        let eligible = allowDriver ? bag : bag.filter { !isDriver($0.name) }
        guard !eligible.isEmpty else { return nil }

        var best: ClubDistance?
        var bestDiff = 9999
        for club in eligible {
            let diff = abs(club.carryYards - yards)
            if diff < bestDiff {
                bestDiff = diff
                best = club
            }
        }
        guard let best else { return nil }

        var alternate: String?
        if yards > best.carryYards + 8 {
            alternate = eligible.filter { $0.carryYards > best.carryYards }
                .reduce(nil as ClubDistance?) { prev, c in prev == nil || c.carryYards < prev!.carryYards ? c : prev }?.name
        } else if yards < best.carryYards - 12 {
            alternate = eligible.filter { $0.carryYards < best.carryYards }
                .reduce(nil as ClubDistance?) { prev, c in prev == nil || c.carryYards > prev!.carryYards ? c : prev }?.name
        }
        return ClubSuggestion(club: best.name, targetYards: yards, alternateClub: alternate)
    }
}

public struct WeatherConditions: Hashable, Sendable, Codable {
    public var temperatureF: Double?
    public var windMph: Double?
    public var windDirectionDeg: Double?
    public var elevationFeet: Double?

    public init(temperatureF: Double? = nil, windMph: Double? = nil, windDirectionDeg: Double? = nil, elevationFeet: Double? = nil) {
        self.temperatureF = temperatureF
        self.windMph = windMph
        self.windDirectionDeg = windDirectionDeg
        self.elevationFeet = elevationFeet
    }
}

public enum PlaysLike {
    /// Temperature, elevation, and head/tail wind adjustment, clamped to 1...999.
    public static func yards(
        actual: Int,
        temperatureF: Double? = nil,
        windMph: Double? = nil,
        windDirectionDeg: Double? = nil,
        shotBearingDeg: Double? = nil,
        elevationFeet: Double? = nil
    ) -> Int {
        var adjusted = Double(actual)
        if let temperatureF { adjusted += (70 - temperatureF) / 10 }
        if let elevationFeet { adjusted *= 1 - (elevationFeet / 1000) * 0.005 }
        if let windMph, windMph > 2, let windDirectionDeg, let shotBearingDeg {
            let head = -(windMph * cos(windDirectionDeg * .pi / 180 - shotBearingDeg * .pi / 180))
            adjusted += head * 0.8
        }
        return min(max(Int(adjusted.rounded()), 1), 999)
    }

    public static func yards(actual: Int, weather: WeatherConditions?, shotBearingDeg: Double?) -> Int {
        yards(
            actual: actual,
            temperatureF: weather?.temperatureF,
            windMph: weather?.windMph,
            windDirectionDeg: weather?.windDirectionDeg,
            shotBearingDeg: shotBearingDeg,
            elevationFeet: weather?.elevationFeet
        )
    }
}
