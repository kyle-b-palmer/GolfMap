import Foundation
import Testing
@testable import GolfCore

@Suite("Weather")
struct WeatherTests {
    let course = Coordinate(latitude: 29.4515, longitude: -98.4766)

    @Test func requestMatchesTheFlutterQuery() throws {
        let url = OpenMeteo.currentConditionsURL(for: course)
        let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        let query = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
        #expect(url.host() == "api.open-meteo.com")
        #expect(query["current"] == "temperature_2m,wind_speed_10m,wind_direction_10m")
        #expect(query["temperature_unit"] == "fahrenheit")
        #expect(query["wind_speed_unit"] == "mph")
        #expect(query["latitude"] == "29.4515")
    }

    @Test func parsesCurrentConditionsAndConvertsElevation() throws {
        let body = #"{"elevation":200.0,"current":{"temperature_2m":88.5,"wind_speed_10m":12,"wind_direction_10m":180}}"#
        let conditions = try #require(OpenMeteo.parse(Data(body.utf8)))
        #expect(conditions.temperatureF == 88.5)
        #expect(conditions.windMph == 12)
        #expect(conditions.windDirectionDeg == 180)
        #expect(abs((conditions.elevationFeet ?? 0) - 656.168) < 0.001)
    }

    @Test func incompleteResponsesAreRejected() {
        #expect(OpenMeteo.parse(Data(#"{"current":{"temperature_2m":70,"wind_speed_10m":5}}"#.utf8)) == nil)
        #expect(OpenMeteo.parse(Data(#"{"error":true}"#.utf8)) == nil)
        #expect(OpenMeteo.parse(Data("not json".utf8)) == nil)
    }

    @Test func cacheIsFreshFor15MinutesWithin500Meters() {
        var cache = WeatherCache()
        let start = Date(timeIntervalSince1970: 1_000_000)
        let conditions = WeatherConditions(temperatureF: 75, windMph: 4, windDirectionDeg: 90)
        #expect(cache.fresh(for: course, now: start) == nil)

        cache.store(conditions, for: course, at: start)
        let nearby = GeoMath.destination(from: course, bearing: 0, meters: 450)
        let far = GeoMath.destination(from: course, bearing: 0, meters: 550)
        #expect(cache.fresh(for: nearby, now: start.addingTimeInterval(14 * 60)) == conditions)
        #expect(cache.fresh(for: course, now: start.addingTimeInterval(15 * 60)) == nil)
        #expect(cache.fresh(for: far, now: start) == nil)
        #expect(cache.conditions == conditions)
    }

    @Test func playsLikeIsShownOnlyWhenItMovesTwoYards() throws {
        let green = GeoMath.destination(from: course, bearing: 0, meters: 140)
        func advice(_ weather: WeatherConditions?) throws -> ShotAdvice {
            try #require(ShotAdvice.make(
                actualYards: 153, origin: course, greenCenter: green, weather: weather,
                clubs: ClubDistance.defaultBag, onTeeBox: false, hasTrackedShots: false
            ))
        }
        let calm = try advice(nil)
        #expect(calm.playsLikeYards == 153)
        #expect(!calm.showsPlaysLike)
        #expect(calm.suggestion?.club == "7I")

        // Known defect kept for parity: Open-Meteo reports where wind comes from, so a south wind is a
        // tailwind for a northbound shot, yet the Flutter formula lengthens the shot.
        let southWind = try advice(WeatherConditions(temperatureF: 50, windMph: 20, windDirectionDeg: 180))
        #expect(southWind.playsLikeYards == PlaysLike.yards(actual: 153, temperatureF: 50, windMph: 20, windDirectionDeg: 180, shotBearingDeg: GeoMath.bearing(course, green)))
        #expect(southWind.playsLikeYards == 171)
        #expect(southWind.showsPlaysLike)
        #expect(southWind.suggestion?.club == "5I")
    }

    @Test func driverNeedsTheTeeAndNoTrackedShots() throws {
        func club(onTee: Bool, tracked: Bool) -> String? {
            ShotAdvice.make(
                actualYards: 240, origin: course, greenCenter: nil, weather: nil,
                clubs: ClubDistance.defaultBag, onTeeBox: onTee, hasTrackedShots: tracked
            )?.suggestion?.club
        }
        #expect(club(onTee: true, tracked: false) == "DR")
        #expect(club(onTee: true, tracked: true) == "3W")
        #expect(club(onTee: false, tracked: false) == "3W")
    }
}
