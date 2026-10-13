import Foundation
import Testing
@testable import GolfCore

@Suite("Measurement chain")
struct MeasurementChainTests {
    let tee = Coordinate(latitude: 29.4500, longitude: -98.4766)

    func north(_ meters: Double) -> Coordinate {
        GeoMath.destination(from: tee, bearing: 0, meters: meters)
    }

    @Test func segmentsRunFromThePlayerThroughEachPoint() {
        var chain = MeasurementChain.adding(north(100), to: [])
        chain = MeasurementChain.adding(north(250), to: chain)
        #expect(MeasurementChain.recalculated(chain, origin: nil) == chain, "no origin leaves the chain alone")

        chain = MeasurementChain.recalculated(chain, origin: tee)
        #expect(chain.map(\.segmentYards) == [109, 164])
        #expect(chain.map(\.shotNumber) == [1, 2])
    }

    @Test func movingOrDeletingRemeasuresNeighbors() {
        var chain = MeasurementChain.recalculated(
            MeasurementChain.adding(north(250), to: MeasurementChain.adding(north(100), to: [])),
            origin: tee
        )
        chain = MeasurementChain.recalculated(MeasurementChain.moving(chain, index: 0, to: north(150)), origin: tee)
        #expect(chain.map(\.segmentYards) == [164, 109])

        chain = MeasurementChain.recalculated(MeasurementChain.removing(chain, index: 0), origin: tee)
        #expect(chain.map(\.segmentYards) == [273])
        #expect(chain.map(\.shotNumber) == [1])
    }

    @Test func savingMergesChainPointsIntoPinsWithoutDuplicates() {
        let existing = PinnedShot(
            id: "gps",
            shotNumber: 1,
            latitude: north(100).latitude,
            longitude: north(100).longitude,
            fromLatitude: tee.latitude,
            fromLongitude: tee.longitude,
            shotYards: 109
        )
        let chain = MeasurementChain.recalculated(
            MeasurementChain.adding(north(220), to: MeasurementChain.adding(north(101), to: [])),
            origin: tee
        )
        let merged = MeasurementChain.mergedIntoPins(chain, pins: [existing], holeFeatures: [])
        #expect(merged.count == 2, "the point 1 m from the GPS pin is skipped")
        #expect(merged[1].shotNumber == 2)
        #expect(merged[1].origin == existing.coordinate)
        #expect(merged[1].shotYards == chain[1].segmentYards)
        #expect(merged[1].yardsToPin == nil, "no green on the hole")

        let firstOnly = MeasurementChain.mergedIntoPins(
            [MeasurementChainPoint(latitude: tee.latitude, longitude: tee.longitude, segmentYards: 0, shotNumber: 1)],
            pins: [],
            holeFeatures: []
        )
        #expect(firstOnly.first?.shotYards == nil)
        #expect(firstOnly.first?.origin == tee)
    }

    @Test func savedRoundIncludesMergedChains() {
        var state = RoundState.start(course: "Test", features: [], now: Date(timeIntervalSince1970: 0))
        state.holes = ["1"]
        state.measurementChains["1"] = MeasurementChain.recalculated(MeasurementChain.adding(north(150), to: []), origin: tee)
        let saved = state.savedRound(features: [])
        #expect(saved.pinnedShots["1"]?.count == 1)
        #expect(saved.measurementChains["1"]?.count == 1)
    }
}
