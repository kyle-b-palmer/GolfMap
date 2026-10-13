import Foundation
import Testing
@testable import GolfCore

/// Characterizes the Flutter round-screen rules carried into `RoundEngine`.
@Suite("Round engine")
struct RoundEngineTests {
    let tee = Coordinate(latitude: 29.4600, longitude: -98.4700)
    let fairway = Coordinate(latitude: 29.4620, longitude: -98.4700)

    func makeState() -> RoundState {
        RoundState(
            id: "r1",
            courseName: "Test",
            playedAt: DartDate(date: Date(timeIntervalSince1970: 0), isUTC: false),
            holes: ["1", "2", "3"],
            pars: ["1": 4, "2": 3, "3": 5],
            handicaps: [:]
        )
    }

    func run(_ actions: [RoundAction], from start: RoundState? = nil) -> RoundState {
        actions.reduce(start ?? makeState()) { RoundEngine.apply($1, to: $0).state }
    }

    @Test func scoresAndPuttsAreClamped() {
        let state = run([.setScore(hole: "1", strokes: 120), .setPutts(hole: "1", putts: 12), .adjustScore(hole: "2", delta: -3)])
        #expect(state.score("1") == 99)
        #expect(state.putts("1") == 9)
        #expect(state.score("2") == 0)
    }

    @Test func totalsMatchFlutterRules() {
        let state = run([.setScore(hole: "1", strokes: 5), .setScore(hole: "2", strokes: 3)])
        #expect(state.totalScore == 8)
        #expect(state.coursePar == 12)
        #expect(state.totalRelativeToPar == 1)
        #expect(state.currentRelativeToPar == 1)
        #expect(state.strokesRemainingForTarget == 4)
        #expect(state.holesToPlay == 2)
    }

    @Test func lostBallAddsStrokeButOrdinaryPinDoesNot() {
        var state = run([.addPin(hole: "1", point: fairway, source: .gps, userLocation: tee, yardsToPin: 100, teeLabel: nil)])
        #expect(state.score("1") == 0)
        #expect(state.currentPins.first?.shotYards == GeoMath.yardsBetween(tee, fairway))
        state = run([.addPin(hole: "1", point: fairway, source: .lostBall, userLocation: fairway, yardsToPin: nil, teeLabel: nil)], from: state)
        #expect(state.score("1") == 1)
        #expect(state.currentPins.map(\.pinType) == [.shot, .lostBall])
        #expect(state.currentPins.last?.shotNumber == 2)
    }

    @Test func deletingAnyPinSubtractsAStrokeAndRenumbers() {
        var state = run([
            .setScore(hole: "1", strokes: 3),
            .addPin(hole: "1", point: tee, source: .map, userLocation: nil, yardsToPin: nil, teeLabel: nil),
            .addPin(hole: "1", point: fairway, source: .map, userLocation: nil, yardsToPin: nil, teeLabel: nil),
        ])
        let first = state.currentPins[0]
        let transition = RoundEngine.apply(.deletePin(hole: "1", id: first.id), to: state)
        state = transition.state
        #expect(state.score("1") == 2)
        #expect(state.currentPins.map(\.shotNumber) == [1])
        #expect(transition.effects.contains(.pinRemoved(hole: "1", pin: first)))
    }

    @Test func lockedHoleRejectsPinsAndDeletes() {
        var state = run([.addPin(hole: "1", point: tee, source: .map, userLocation: nil, yardsToPin: nil, teeLabel: nil)])
        state = run([.setLocked(hole: "1", locked: true)], from: state)
        let add = RoundEngine.apply(.addPin(hole: "1", point: fairway, source: .gps, userLocation: nil, yardsToPin: nil, teeLabel: nil), to: state)
        #expect(!add.changed)
        #expect(add.effects == [.pinRejectedHoleLocked])
        let delete = RoundEngine.apply(.deletePin(hole: "1", id: state.currentPins[0].id), to: state)
        #expect(!delete.changed)
    }

    @Test func remotePinsDedupeWithin25YardsButLostBallsDoNot() {
        let near = GeoMath.destination(from: fairway, bearing: 0, meters: 10)
        var state = run([.addPin(hole: "1", point: fairway, source: .remote(eventID: "e1", lostBall: false), userLocation: nil, yardsToPin: nil, teeLabel: nil)])
        let dup = RoundEngine.apply(.addPin(hole: "1", point: near, source: .remote(eventID: "e2", lostBall: false), userLocation: nil, yardsToPin: nil, teeLabel: nil), to: state)
        #expect(dup.effects == [.pinIgnoredDuplicate])
        #expect(dup.state.currentPins.count == 1)
        state = run([.addPin(hole: "1", point: near, source: .remote(eventID: "e3", lostBall: true), userLocation: nil, yardsToPin: nil, teeLabel: nil)], from: dup.state)
        #expect(state.currentPins.count == 2)
        #expect(state.score("1") == 0, "remote scores arrive with the shared state")
    }

    @Test func duplicateEventIDsAreIgnored() {
        let far = GeoMath.destination(from: fairway, bearing: 0, meters: 150)
        let state = run([
            .addPin(hole: "1", point: fairway, source: .remote(eventID: "same", lostBall: true), userLocation: nil, yardsToPin: nil, teeLabel: nil),
            .addPin(hole: "1", point: far, source: .remote(eventID: "same", lostBall: true), userLocation: nil, yardsToPin: nil, teeLabel: nil),
        ])
        #expect(state.currentPins.count == 1)
    }

    @Test func remoteUndoPrefersEventIDOverProximity() {
        let near = GeoMath.destination(from: fairway, bearing: 90, meters: 5)
        var state = run([
            .addPin(hole: "1", point: fairway, source: .remote(eventID: "a", lostBall: true), userLocation: nil, yardsToPin: nil, teeLabel: nil),
            .addPin(hole: "1", point: near, source: .remote(eventID: "b", lostBall: true), userLocation: nil, yardsToPin: nil, teeLabel: nil),
        ])
        state = run([.applyRemoteUndo(hole: "1", point: fairway, pinEventID: "a")], from: state)
        #expect(state.currentPins.map(\.id) == ["b"])
        #expect(state.currentPins.first?.shotNumber == 1)

        state = run([.applyRemoteUndo(hole: "1", point: fairway, pinEventID: nil)], from: state)
        #expect(state.currentPins.isEmpty, "version 1 undo falls back to 25-yard proximity")
    }

    @Test func holeNavigationWraps() {
        var state = run([.previousHole])
        #expect(state.selectedHole == "3")
        state = run([.nextHole], from: state)
        #expect(state.selectedHole == "1")
        state = run([.applyRemoteTotals(scores: ["2": 4], putts: [:], selectedHole: "9")], from: state)
        #expect(state.selectedHole == "1", "unknown remote hole is ignored")
        #expect(state.score("2") == 4)
    }

    @Test func revisionAdvancesOnlyOnChange() {
        let state = makeState()
        #expect(RoundEngine.apply(.setScore(hole: "1", strokes: 0), to: state).state.revision == 0)
        #expect(RoundEngine.apply(.setScore(hole: "1", strokes: 4), to: state).state.revision == 1)
    }

    @Test func savingLocksEveryHoleAndKeepsIdentity() {
        let state = run([.setScore(hole: "1", strokes: 4)])
        let saved = state.savedRound()
        #expect(saved.lockedHoles == ["1", "2", "3"])
        #expect(saved.scores == ["1": 4, "2": 0, "3": 0])
        #expect(saved.id == "r1")
    }

    @Test func autoAdvanceNeedsMoreThanTwelveSecondsOnGreen() {
        var tracker = AutoAdvanceTracker()
        let start = Date(timeIntervalSince1970: 1000)
        let samples: [(Bool, TimeInterval)] = [(true, 0), (true, 12), (true, 12.1), (true, 30), (false, 31), (true, 32)]
        let fired = samples.map { onGreen, offset in tracker.update(onGreen: onGreen, now: start.addingTimeInterval(offset)) }
        #expect(fired == [false, false, true, false, false, false], "fires once per green visit, after more than 12 s")
    }

    @Test func roundStateRoundTripsThroughCodable() throws {
        let state = run([
            .setScore(hole: "2", strokes: 3),
            .addPin(hole: "2", point: fairway, source: .lostBall, userLocation: tee, yardsToPin: 80, teeLabel: "Back"),
            .setClubAim(hole: "2", point: tee),
        ])
        let data = try JSONEncoder().encode(state)
        #expect(try JSONDecoder().decode(RoundState.self, from: data) == state)
    }
}
