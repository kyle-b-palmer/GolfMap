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
}
