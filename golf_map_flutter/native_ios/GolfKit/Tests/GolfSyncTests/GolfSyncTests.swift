import Foundation
import Testing
import GolfCore
@testable import GolfSync

@Suite("Sync protocol")
struct GolfSyncTests {
    let green = Coordinate(latitude: 29.47, longitude: -98.47)

    func round() -> RoundState {
        RoundState(
            id: "r1",
            courseName: "Brackenridge Golf Course",
            playedAt: DartDate(date: Date(timeIntervalSince1970: 0), isUTC: false),
            holes: ["1", "2"],
            pars: ["1": 4, "2": 3],
            handicaps: ["1": 5, "2": 9],
            sessionID: "s1"
        )
    }

    @Test func decodesVersionOnePayloadWithoutEventIDs() throws {
        let json = """
        {"holes":["1","2"],"selectedHole":"2","scores":{"1":5},"pars":{"1":4,"2":3},"courseName":"X",
         "yardsToGreen":140,"revision":7,"pendingGpsPins":[{"hole":"2","latitude":1.0,"longitude":2.0,"pinKind":"lostBall"}]}
        """
        let state = try JSONDecoder().decode(GolfRoundSharedState.self, from: Data(json.utf8))
        #expect(state.protocolVersion == nil)
        #expect(state.putts.isEmpty)
        #expect(state.sessionId == "")
        #expect(state.pendingGpsPins.first?.eventId == nil)
        #expect(state.pendingGpsPins.first?.isLostBall == true)
    }

    @Test func versionTwoKeysAreAdditive() throws {
        let state = PhoneRoundSync.snapshot(of: round(), yardsToGreen: 150, green: green, previous: nil)
        let object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as? [String: Any])
        #expect(object["protocolVersion"] as? Int == 2)
        for key in ["holes", "selectedHole", "scores", "putts", "pars", "handicaps", "courseName", "yardsToGreen",
                    "revision", "pendingGpsPins", "pendingGpsPinUndos", "greenLatitude", "greenLongitude",
                    "gpsRefreshRevision", "sessionId"] {
            #expect(object[key] != nil, "\(key)")
        }
    }

    @Test func snapshotKeepsPendingQueuesOnlyWithinSession() {
        var previous = GolfRoundSharedState(holes: ["1"], courseName: "X", revision: 4, sessionId: "s1")
        previous.pendingGpsPins = [GolfRoundGpsPin(hole: "1", latitude: 1, longitude: 2)]
        let same = PhoneRoundSync.snapshot(of: round(), yardsToGreen: nil, green: nil, previous: previous)
        #expect(same.pendingGpsPins.count == 1)
        #expect(same.revision == 5)
        #expect(same.yardsToGreen == -1)
        previous.sessionId = "other"
        #expect(PhoneRoundSync.snapshot(of: round(), yardsToGreen: nil, green: nil, previous: previous).pendingGpsPins.isEmpty)
    }

    @Test func watchChangesBecomeRoundActions() {
        let pinA = GolfRoundGpsPin(hole: "1", latitude: 29.46, longitude: -98.47, eventId: "a")
        var changes = GolfRoundSharedState(
            holes: ["1", "2"], selectedHole: "2", scores: ["1": 4], putts: ["1": 2],
            courseName: "Brackenridge Golf Course", sessionId: "s1"
        )
        changes.pendingGpsPins = [pinA]
        let actions = PhoneRoundSync.actions(for: changes, round: round())
        let state = actions.reduce(round()) { RoundEngine.apply($1, to: $0).state }
        #expect(state.score("1") == 4)
        #expect(state.putts("1") == 2)
        #expect(state.sortedPins("1").map(\.id) == ["a"])
        #expect(state.selectedHole == "2")

        var wrongSession = changes
        wrongSession.sessionId = "s9"
        #expect(PhoneRoundSync.actions(for: wrongSession, round: round()).isEmpty)
    }

    @Test func undoWithEventIDRemovesExactPin() {
        var state = round()
        for (id, meters) in [("a", 0.0), ("b", 8.0)] {
            let point = GeoMath.destination(from: green, bearing: 0, meters: meters)
            state = RoundEngine.apply(.addPin(hole: "1", point: point, source: .remote(eventID: id, lostBall: true),
                                              userLocation: nil, yardsToPin: nil, teeLabel: nil), to: state).state
        }
        var changes = PhoneRoundSync.snapshot(of: state, yardsToGreen: nil, green: nil, previous: nil)
        changes.pendingGpsPinUndos = [GolfRoundGpsPin(hole: "1", latitude: green.latitude, longitude: green.longitude, eventId: "a")]
        state = PhoneRoundSync.actions(for: changes, round: state).reduce(state) { RoundEngine.apply($1, to: $0).state }
        #expect(state.sortedPins("1").map(\.id) == ["b"])
    }

    @Test func mergeIgnoresOtherSessionsAndNoOps() {
        let current = GolfRoundSharedState(holes: ["1"], scores: ["1": 3], courseName: "X", revision: 5, sessionId: "s1")
        var other = current
        other.sessionId = "s2"
        other.scores = ["1": 4]
        #expect(PhoneRoundSync.mergeWatchPayload(other, into: current, activeSessionId: "s1") == nil)
        #expect(PhoneRoundSync.mergeWatchPayload(current, into: current, activeSessionId: "s1") == nil)
    }

    @Test func mergeAppendsPinsAndDropsSupersededUndos() throws {
        let current = GolfRoundSharedState(holes: ["1"], scores: ["1": 3], courseName: "X", revision: 5, sessionId: "s1")
        var incoming = current
        incoming.scores = ["1": 4]
        incoming.revision = 6
        let pin = GolfRoundGpsPin(hole: "1", latitude: 29.46, longitude: -98.47, eventId: "p")
        incoming.pendingGpsPins = [pin]
        incoming.pendingGpsPinUndos = [GolfRoundGpsPin(hole: "1", latitude: 29.46, longitude: -98.47, eventId: "p")]
        let merged = try #require(PhoneRoundSync.mergeWatchPayload(incoming, into: current, activeSessionId: "s1"))
        #expect(merged.scores["1"] == 4)
        #expect(merged.revision == 6)
        #expect(merged.pendingGpsPins == [pin])
        #expect(merged.pendingGpsPinUndos.isEmpty)
    }

    @Test func phoneDeletionProducesIdentifiedUndo() {
        let shot = PinnedShot(id: "z", shotNumber: 1, latitude: 1, longitude: 2, fromLatitude: 1, fromLongitude: 2, pinType: .lostBall)
        let undo = PhoneRoundSync.undoEntry(for: shot, hole: "3")
        #expect(undo.eventId == "z")
        #expect(undo.isLostBall)
    }
}
