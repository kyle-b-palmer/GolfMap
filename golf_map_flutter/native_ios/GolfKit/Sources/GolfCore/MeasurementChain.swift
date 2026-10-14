import Foundation

/// Tap-to-measure points on a hole. Each segment runs from the previous point, the first from the player.
public enum MeasurementChain {
    /// Appends a point. Its segment is filled in by `recalculated` once an origin is known.
    public static func adding(_ point: Coordinate, to chain: [MeasurementChainPoint]) -> [MeasurementChainPoint] {
        chain + [MeasurementChainPoint(latitude: point.latitude, longitude: point.longitude, segmentYards: 0, shotNumber: chain.count + 1)]
    }

    /// Re-measures every segment from `origin`. Without an origin the chain is unchanged, as in Flutter.
    public static func recalculated(_ chain: [MeasurementChainPoint], origin: Coordinate?) -> [MeasurementChainPoint] {
        guard let origin, !chain.isEmpty else { return chain }
        var previous = origin
        return chain.enumerated().map { index, point in
            defer { previous = point.coordinate }
            return MeasurementChainPoint(
                latitude: point.latitude,
                longitude: point.longitude,
                segmentYards: GeoMath.yardsBetween(previous, point.coordinate),
                shotNumber: index + 1
            )
        }
    }

    public static func moving(_ chain: [MeasurementChainPoint], index: Int, to point: Coordinate) -> [MeasurementChainPoint] {
        guard chain.indices.contains(index) else { return chain }
        var updated = chain
        updated[index].latitude = point.latitude
        updated[index].longitude = point.longitude
        return updated
    }

    public static func removing(_ chain: [MeasurementChainPoint], index: Int) -> [MeasurementChainPoint] {
        guard chain.indices.contains(index) else { return chain }
        var updated = chain
        updated.remove(at: index)
        return updated
    }

    /// Flutter's save step: chain points become shot pins unless a pin is already within 3 yards.
    public static func mergedIntoPins(_ chain: [MeasurementChainPoint], pins: [PinnedShot], holeFeatures: [GolfFeature]) -> [PinnedShot] {
        var pins = pins
        let hasGreen = HoleGeometry.greenCenter(holeFeatures) != nil
        for point in chain {
            let candidate = point.coordinate
            if pins.contains(where: { GeoMath.yardsBetween($0.coordinate, candidate) < 3 }) { continue }
            let from = pins.last?.coordinate ?? candidate
            pins.append(PinnedShot(
                id: UUID().uuidString,
                shotNumber: pins.count + 1,
                latitude: candidate.latitude,
                longitude: candidate.longitude,
                fromLatitude: from.latitude,
                fromLongitude: from.longitude,
                shotYards: pins.isEmpty && point.segmentYards <= 0 ? nil : point.segmentYards,
                yardsToPin: hasGreen ? HoleGeometry.greenYardages(from: candidate, holeFeatures).middle : nil
            ))
        }
        return pins
    }
}

extension RoundState {
    /// The round as saved, with each hole's measurement chain merged into its pins as Flutter does.
    public func savedRound(features: [GolfFeature]) -> SavedRound {
        var saved = savedRound()
        for (hole, chain) in saved.measurementChains {
            let holeFeatures = HoleGeometry.features(features, course: courseName, hole: hole)
            let merged = MeasurementChain.mergedIntoPins(chain, pins: sortedPins(hole), holeFeatures: holeFeatures)
            if !merged.isEmpty { saved.pinnedShots[hole] = merged }
        }
        return saved
    }
}
