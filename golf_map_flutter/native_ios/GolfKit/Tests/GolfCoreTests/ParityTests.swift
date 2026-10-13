import Foundation
import Testing
@testable import GolfCore

/// Compares the Swift port with outputs exported from the Flutter app (see test/parity in the Flutter project).
@Suite("Flutter parity")
struct ParityTests {
    let features = Fixtures.features
    let parity = Fixtures.parity

    @Test func bundledAssetDecodes() {
        #expect(features.count == 820)
        let polygons = features.filter { if case .polygon = $0.geometry { return true }; return false }
        let lines = features.filter { if case .lineString = $0.geometry { return true }; return false }
        #expect(polygons.count == 704)
        #expect(lines.count == 116)
        #expect(features.filter { $0.holeNumber == nil }.count == 60)
    }

    @Test func courseCatalogMatches() throws {
        let catalog = CourseCatalog.build(features)
        let expected = try #require(parity["courses"]?.arrayValue)
        #expect(catalog.count == expected.count)
        for (entry, exp) in zip(catalog, expected) {
            #expect(entry.name == exp["name"]?.stringValue)
            #expect(entry.state == exp["state"]?.stringValue)
            #expect(entry.stateCode == exp["stateCode"]?.stringValue)
            #expect(entry.city == exp["city"]?.stringValue, "\(entry.name)")
            #expect(abs(entry.latitude - (exp["latitude"]?.numberValue ?? 0)) < 1e-9)
            #expect(abs(entry.longitude - (exp["longitude"]?.numberValue ?? 0)) < 1e-9)
            let courseFeatures = features.filter { $0.matchesCourse(entry.name) }
            #expect(courseFeatures.count == exp["featureCount"]?.truncatedInt)
            #expect(CourseCatalog.holes(features, course: entry.name) == exp["holes"]?.arrayValue?.compactMap(\.stringValue))
        }
    }

    @Test func holeCalculationsMatch() throws {
        let holes = try #require(parity["holes"]?.arrayValue)
        #expect(holes.count == 90)
        var yardageMismatches: [String] = []
        var pointCount = 0

        for exp in holes {
            let course = exp["course"]!.stringValue!
            let hole = exp["hole"]!.stringValue!
            let label = "\(course) #\(hole)"
            let holeFeatures = HoleGeometry.features(features, course: course, hole: hole)
            #expect(holeFeatures.count == exp["featureCount"]?.truncatedInt, "\(label)")

            let stats = CourseCatalog.stats(features, course: course, hole: hole)
            #expect(stats?.par == exp["par"]?.truncatedInt, "\(label) par")
            #expect(stats?.handicap == exp["handicap"]?.truncatedInt, "\(label) handicap")

            #expect(close(HoleGeometry.greenCenter(holeFeatures), exp["greenCenter"]?.coordinate), "\(label) green")
            #expect(close(HoleGeometry.longestTee(holeFeatures), exp["longestTee"]?.coordinate), "\(label) tee")

            if let orientation = exp["orientation"]?.objectValue {
                let actual = try #require(HoleGeometry.orientation(holeFeatures))
                #expect(close(actual.tee, orientation["tee"]?.coordinate), "\(label) orientation tee")
                #expect(close(actual.green, orientation["green"]?.coordinate), "\(label) orientation green")
                let rotation = GeoMath.mapRotation(tee: actual.tee, green: actual.green)
                #expect(abs(rotation - orientation["mapRotation"]!.numberValue!) < 1e-6, "\(label) rotation")
            } else {
                #expect(HoleGeometry.orientation(holeFeatures) == nil)
            }

            let tees = HoleGeometry.teeOptions(holeFeatures)
            let expectedTees = exp["tees"]!.arrayValue!
            #expect(tees.count == expectedTees.count, "\(label) tee count")
            for (tee, expTee) in zip(tees, expectedTees) {
                #expect(tee.label == expTee["label"]?.stringValue)
                #expect(tee.featureID?.jsonValue.isEquivalent(to: expTee["featureId"]!) == true, "\(label) tee id")
                #expect(close(tee.point, expTee["point"]?.coordinate))
                #expect(HoleGeometry.holeYardage(holeFeatures, teeID: tee.featureID) == expTee["holeYards"]?.truncatedInt, "\(label) tee yards")
            }

            let ring = HoleGeometry.encirclementRing(features, course: course, hole: hole)
            let expRing = exp["encirclement"]!
            #expect(ring.count == expRing["count"]?.truncatedInt, "\(label) ring")
            for (index, sample) in zip([0, 18, 36, 54], expRing["samples"]!.arrayValue!) where index < ring.count {
                #expect(close(ring[index], sample.coordinate, tolerance: 1e-9), "\(label) ring sample \(index)")
            }

            let planned: [PlannedShotSegment]
            if let tee = HoleGeometry.longestTee(holeFeatures), let green = HoleGeometry.greenCenter(holeFeatures) {
                planned = HoleGeometry.plannedShots(start: tee, green: green, holeFeatures)
            } else {
                planned = []
            }
            let expPlanned = exp["plannedShots"]!.arrayValue!
            #expect(planned.count == expPlanned.count, "\(label) planned count")
            for (segment, expSegment) in zip(planned, expPlanned) {
                #expect(segment.yards == expSegment["yards"]?.truncatedInt, "\(label) planned yards")
                #expect(segment.carryYards == expSegment["carryYards"]?.truncatedInt)
                #expect(close(segment.to, expSegment["to"]?.coordinate, tolerance: 1e-9), "\(label) planned target")
            }

            for point in exp["points"]!.arrayValue! {
                pointCount += 1
                let p = point["point"]!.coordinate!
                let pointLabel = "\(label) \(point["label"]!.stringValue!)"
                let green = HoleGeometry.greenYardages(from: p, holeFeatures)
                let expGreen = point["green"]!.arrayValue!.compactMap(\.truncatedInt)
                if [green.front, green.middle, green.back] != expGreen {
                    yardageMismatches.append("\(pointLabel) green \([green.front, green.middle, green.back]) vs \(expGreen)")
                }
                #expect(close(HoleGeometry.backOfGreen(from: p, holeFeatures), point["backOfGreen"]?.coordinate), "\(pointLabel) back")

                let bunkers = HoleGeometry.bunkerDistances(from: p, holeFeatures)
                let expBunkers = point["bunkers"]!.arrayValue!
                if bunkers.map(\.yards) != expBunkers.compactMap({ $0["yards"]?.truncatedInt })
                    || bunkers.map(\.label) != expBunkers.compactMap({ $0["label"]?.stringValue }) {
                    yardageMismatches.append("\(pointLabel) bunkers \(bunkers.map { "\($0.label)=\($0.yards)" })")
                }

                #expect(HoleGeometry.isNearHole(p, holeFeatures) == point["nearHole"]?.bool, "\(pointLabel) near")
                #expect(HoleGeometry.isOnTeeBox(p, holeFeatures) == point["onTeeBox"]?.bool, "\(pointLabel) tee box")
                #expect(HoleGeometry.isPointInFairway(p, holeFeatures) == point["inFairway"]?.bool, "\(pointLabel) fairway")
                #expect(HoleGeometry.isPointInGreen(p, holeFeatures) == point["inGreen"]?.bool, "\(pointLabel) green")
                #expect(HoleGeometry.isPointInEncirclement(p, features, course: course, hole: hole) == point["inEncirclement"]?.bool, "\(pointLabel) encirclement")
                #expect(HoleGeometry.isGpsWithinPlayArea(p, features, course: course, hole: hole) == point["gpsInPlayArea"]?.bool, "\(pointLabel) play area")
                let outside = HoleGeometry.distanceOutsideEncirclementMeters(p, features, course: course, hole: hole)
                #expect(abs(outside - point["outsideEncirclementMeters"]!.numberValue!) < 1e-6, "\(pointLabel) outside")
            }
        }

        #expect(pointCount == 983)
        #expect(yardageMismatches.isEmpty, "\(yardageMismatches.count) yardage mismatches: \(yardageMismatches.prefix(10))")
    }

    @Test func clubSuggestionsMatch() throws {
        let noDriver = Array(ClubDistance.defaultBag.dropFirst())
        for exp in try #require(parity["clubSuggestions"]?.arrayValue) {
            let yards = exp["yards"]!.truncatedInt!
            let bag = exp["bag"]?.stringValue == "noDriver" ? noDriver : ClubDistance.defaultBag
            let suggestion = ClubAdvisor.suggest(yards: yards, clubs: bag, allowDriver: exp["allowDriver"]!.bool!)
            #expect(suggestion?.club == exp["club"]?.stringValue, "\(yards)")
            #expect(suggestion?.alternateClub == exp["alternate"]?.stringValue, "\(yards) alternate")
        }
    }

    @Test func playsLikeMatches() throws {
        for exp in try #require(parity["playsLike"]?.arrayValue) {
            let actual = PlaysLike.yards(
                actual: exp["actual"]!.truncatedInt!,
                temperatureF: exp["temperatureF"]?.numberValue,
                windMph: exp["windMph"]?.numberValue,
                windDirectionDeg: exp["windDirectionDeg"]?.numberValue,
                shotBearingDeg: exp["shotBearingDeg"]?.numberValue,
                elevationFeet: exp["elevationFeet"]?.numberValue
            )
            #expect(actual == exp["expected"]?.truncatedInt, "\(exp)")
        }
    }

    @Test func legacySavedRoundsDecode() throws {
        var rounds: [SavedRound] = []
        for exp in try #require(parity["savedRounds"]?.arrayValue) {
            let name = exp["name"]!.stringValue!
            let round = try SavedRound.legacy(exp["input"]!)
            rounds.append(round)
            #expect(round.legacyJSON().isEquivalent(to: exp["expected"]!), "\(name): \(round.legacyJSON())")
            #expect(round.playedAt.isUTC == exp["playedAtIsUtc"]?.bool, "\(name) utc")
            #expect(round.totalStrokes == exp["totalStrokes"]?.truncatedInt)
            #expect(round.totalPutts == exp["totalPutts"]?.truncatedInt)
            #expect(round.holesScored == exp["holesScored"]?.truncatedInt)
            #expect(round.totalPinnedShots == exp["totalPinnedShots"]?.truncatedInt)
        }

        let dispersion = ShotDispersion.points(rounds: rounds, courseName: "Brackenridge Golf Course", hole: "1")
        let expected = try #require(parity["dispersionBrackenridgeHole1"]?.arrayValue)
        #expect(dispersion.count == expected.count)
        for (point, exp) in zip(dispersion, expected) {
            #expect(point.latitude == exp["latitude"]?.numberValue)
            #expect(point.longitude == exp["longitude"]?.numberValue)
            #expect(point.weight == exp["weight"]?.numberValue)
        }
    }
}
