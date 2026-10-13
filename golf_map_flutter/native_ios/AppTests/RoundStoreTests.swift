import Foundation
import GolfCore
import GolfSync
import Testing
@testable import GolfMap

@MainActor
@Suite("Round store")
struct RoundStoreTests {
    let features: [GolfFeature]
    let folder: URL
    let shared: SharedRoundStore

    init() throws {
        let url = try #require(Bundle(for: RoundRepository.self).url(forResource: "san_antonio_courses", withExtension: "json"))
        features = try FeatureRowDecoder.decode(Data(contentsOf: url)).filter { $0.matchesCourse("Brackenridge Golf Course") }
        folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let suite = "round-store-tests-\(UUID().uuidString)"
        shared = SharedRoundStore(suiteName: suite, notificationName: "com.golfmapapp.tests.\(suite)")
    }

    func makeStore() -> RoundStore {
        RoundStore(
            round: RoundState.start(course: "Brackenridge Golf Course", features: features),
            courseFeatures: features,
            repository: RoundRepository(directory: folder),
            shared: shared
        )
    }

    @Test func activatingPersistsAndPublishes() throws {
        let store = makeStore()
        store.activate()
        defer { store.deactivate() }
        let snapshot = try #require(shared.load())
        #expect(snapshot.courseName == "Brackenridge Golf Course")
        #expect(snapshot.sessionId == store.round.sessionID)
        #expect(snapshot.greenLatitude != 0)
        #expect(RoundRepository(directory: folder).activeRound?.id == store.round.id)
    }

    @Test func liveActivityEditsAreApplied() throws {
        let store = makeStore()
        store.activate()
        defer { store.deactivate() }
        let green = try #require(store.hole.green)
        shared.update { current in
            guard var state = current else { return nil }
            state.scores[state.selectedHole] = 5
            state.pendingGpsPins.append(GolfRoundGpsPin(hole: state.selectedHole, latitude: green.latitude, longitude: green.longitude, eventId: "lock-screen"))
            state.revision += 1
            return state
        }
        store.consumeSharedChanges()
        #expect(store.round.currentScore == 5)
        #expect(store.round.currentPins.map(\.id) == ["lock-screen"])
        #expect(store.round.currentPins.first?.yardsToPin == 0)
        #expect(shared.load()?.pendingGpsPins.isEmpty == true, "consumed pins are cleared")
    }

    @Test func deletingPinPublishesIdentifiedUndo() throws {
        let store = makeStore()
        store.activate()
        defer { store.deactivate() }
        let green = try #require(store.hole.green)
        store.markShot(at: green, from: nil, source: .map)
        let pin = try #require(store.round.currentPins.first)
        store.send(.deletePin(hole: store.round.selectedHole, id: pin.id))
        #expect(shared.load()?.pendingGpsPinUndos.map(\.eventId) == [pin.id])
    }

    @Test func finishingSavesLockedRoundAndClearsShared() {
        let store = makeStore()
        store.activate()
        store.send(.setScore(hole: "1", strokes: 4))
        store.finish()
        let repository = RoundRepository(directory: folder)
        #expect(repository.activeRound == nil)
        #expect(repository.savedRounds.first?.scores["1"] == 4)
        #expect(repository.savedRounds.first?.lockedHoles.count == store.round.holes.count)
        #expect(shared.load() == nil)
    }

    @Test func autoAdvanceWaitsOnTheGreenAndStopsOnTheLastHole() throws {
        let store = makeStore()
        let start = Date(timeIntervalSince1970: 1_000)
        let green = try #require(store.hole.green)
        store.locationChanged(green, autoAdvanceEnabled: true, now: start)
        store.locationChanged(green, autoAdvanceEnabled: true, now: start.addingTimeInterval(12))
        #expect(store.round.selectedHole == "1", "needs more than 12 seconds")
        store.locationChanged(green, autoAdvanceEnabled: true, now: start.addingTimeInterval(12.5))
        #expect(store.round.selectedHole == "2")
        #expect(store.banner == "Advanced to hole 2")

        let last = try #require(store.round.holes.last)
        store.send(.selectHole(last))
        let lastGreen = try #require(store.hole.green)
        store.locationChanged(lastGreen, autoAdvanceEnabled: true, now: start)
        store.locationChanged(lastGreen, autoAdvanceEnabled: true, now: start.addingTimeInterval(60))
        #expect(store.round.selectedHole == last)
    }

    @Test func interruptedRoundRestoresFromDisk() throws {
        let store = makeStore()
        store.activate()
        store.send(.setScore(hole: "1", strokes: 5))
        store.send(.setPutts(hole: "1", putts: 2))
        store.send(.setLocked(hole: "1", locked: true))
        store.send(.setScoreTarget(80))
        store.send(.selectHole("2"))
        store.deactivate()

        let restored = try #require(RoundRepository(directory: folder).activeRound)
        #expect(restored == store.round)
        #expect(restored.selectedHole == "2")
        #expect(restored.scoreTarget == 80)
        #expect(restored.lockedHoles == ["1"])
    }

    @Test func reopeningASavedRoundKeepsItsIdentityAndDate() throws {
        let first = makeStore()
        first.activate()
        first.send(.setScore(hole: "1", strokes: 4))
        first.finish()
        let saved = try #require(RoundRepository(directory: folder).savedRounds.first)

        let repository = RoundRepository(directory: folder)
        let reopened = RoundStore(
            round: RoundState.reopen(saved, features: features),
            courseFeatures: features,
            repository: repository,
            shared: shared
        )
        reopened.activate()
        #expect(reopened.round.lockedHoles.count == reopened.round.holes.count, "saved rounds reopen locked")
        reopened.send(.setLocked(hole: "1", locked: false))
        reopened.send(.setScore(hole: "1", strokes: 6))
        reopened.finish()

        let rounds = RoundRepository(directory: folder).savedRounds
        #expect(rounds.count == 1)
        #expect(rounds.first?.id == saved.id)
        #expect(rounds.first?.playedAt == saved.playedAt)
        #expect(rounds.first?.scores["1"] == 6)
    }
}
