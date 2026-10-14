@testable import GolfCore
import Testing

@Suite("Round recap")
struct RoundRecapTests {
    func line(_ hole: String, par: Int, score: Int) -> RoundRecap.Line {
        RoundRecap.Line(hole: hole, par: par, score: score, putts: 0)
    }

    func shot(_ yards: Int?, _ type: PinType = .shot) -> PinnedShot {
        PinnedShot(shotNumber: 1, latitude: 0, longitude: 0, fromLatitude: 0, fromLongitude: 0, shotYards: yards, pinType: type)
    }

    @Test func longestDriveSkipsLostBalls() {
        #expect(RoundRecap.longestDrive(["1": [shot(240), shot(310, .lostBall)], "2": [shot(nil), shot(255)]]) == 255)
        #expect(RoundRecap.longestDrive(["1": [shot(nil)]]) == nil)
    }

    @Test func bestHoleIsTheFirstLowestAtParOrBetter() {
        #expect(RoundRecap.bestHoleVsPar([line("1", par: 4, score: 3), line("2", par: 5, score: 4)]) == "Hole 1 (-1)")
        #expect(RoundRecap.bestHoleVsPar([line("1", par: 4, score: 5), line("2", par: 3, score: 3)]) == "Hole 2 (par)")
        #expect(RoundRecap.bestHoleVsPar([line("1", par: 4, score: 6), line("2", par: 3, score: 0)]) == nil)
    }

    @Test func summarisesARound() {
        var round = RoundState.start(course: "Test", features: [])
        round.holes = ["1", "2"]
        round.pars = ["1": 4, "2": 3]
        round.scores = ["1": 5, "2": 2]
        round.pinnedShots = ["1": [shot(200), shot(120)]]
        let recap = RoundRecap(round)
        #expect(recap.totalScore == 7)
        #expect(recap.relativeToPar == 0)
        #expect(recap.trackedShots == 2)
        #expect(recap.longestDriveYards == 200)
        #expect(recap.bestHole == "Hole 2 (-1)")
    }
}
