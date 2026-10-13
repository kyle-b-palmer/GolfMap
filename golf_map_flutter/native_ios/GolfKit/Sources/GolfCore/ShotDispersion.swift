import Foundation

public struct DispersionPoint: Hashable, Sendable {
    public var latitude: Double
    public var longitude: Double
    public var weight: Double
}

public enum ShotDispersion {
    /// Groups historical (non lost-ball) pins on a hole into grid buckets.
    ///
    /// The Flutter bucket key also includes the raw latitude, so shots only merge when their
    /// latitudes are identical. That behavior is preserved until it is deliberately changed.
    public static func points(rounds: [SavedRound], courseName: String, hole: String, gridYards: Int = 8) -> [DispersionPoint] {
        var shots: [PinnedShot] = []
        for round in rounds where round.courseName == courseName {
            shots.append(contentsOf: (round.pinnedShots[hole] ?? []).filter { $0.pinType != .lostBall })
        }
        guard !shots.isEmpty else { return [] }

        let gridMeters = Double(gridYards) / GeoMath.yardsPerMeter
        var order: [String] = []
        var buckets: [String: [PinnedShot]] = [:]
        for shot in shots {
            let latBucket = Int((shot.latitude / (gridMeters / 111320)).rounded())
            let lngBucket = Int((shot.longitude / (gridMeters / 111320)).rounded())
            let key = "\(latBucket):\(lngBucket):\(shot.latitude)"
            if buckets[key] == nil { order.append(key) }
            buckets[key, default: []].append(shot)
        }

        return order.map { key in
            let group = buckets[key]!
            return DispersionPoint(
                latitude: group.map(\.latitude).reduce(0, +) / Double(group.count),
                longitude: group.map(\.longitude).reduce(0, +) / Double(group.count),
                weight: Double(group.count)
            )
        }
    }
}
