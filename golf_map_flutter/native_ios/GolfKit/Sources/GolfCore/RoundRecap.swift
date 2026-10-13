import Foundation

/// Figures for the shared scorecard and round recap images.
public struct RoundRecap: Sendable, Equatable {
    public struct Line: Sendable, Equatable {
        public var hole: String
        public var par: Int
        public var score: Int
        public var putts: Int
    }

    public var courseName: String
    public var playedAt: Date
    public var lines: [Line]
    public var totalScore: Int
    public var coursePar: Int
    public var relativeToPar: Int
    public var trackedShots: Int
    public var longestDriveYards: Int?
    /// "Hole 7 (-1)" or "Hole 3 (par)"; nil when every scored hole was over par.
    public var bestHole: String?

    public init(_ round: RoundState) {
        courseName = round.courseName
        playedAt = round.playedAt.date
        lines = round.holes.map { Line(hole: $0, par: round.par($0), score: round.score($0), putts: round.putts($0)) }
        totalScore = round.totalScore
        coursePar = round.coursePar
        relativeToPar = round.totalRelativeToPar
        trackedShots = round.pinnedShots.values.reduce(0) { $0 + $1.count }
        longestDriveYards = Self.longestDrive(round.pinnedShots)
        bestHole = Self.bestHoleVsPar(lines)
    }

    /// Longest tracked shot, ignoring lost balls.
    static func longestDrive(_ pins: [String: [PinnedShot]]) -> Int? {
        let best = pins.values.joined().filter { $0.pinType != .lostBall }.compactMap(\.shotYards).max() ?? 0
        return best > 0 ? best : nil
    }

    /// The first hole, in playing order, with the lowest score against par, if it's par or better.
    static func bestHoleVsPar(_ lines: [Line]) -> String? {
        var best: (hole: String, delta: Int)?
        for line in lines where line.score > 0 && line.par > 0 {
            let delta = line.score - line.par
            if delta < best?.delta ?? .max { best = (line.hole, delta) }
        }
        guard let best, best.delta <= 0 else { return nil }
        return "Hole \(best.hole) (\(best.delta == 0 ? "par" : "\(best.delta)"))"
    }
}
