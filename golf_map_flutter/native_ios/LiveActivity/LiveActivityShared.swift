import ActivityKit
import CoreLocation
import Foundation
import GolfCore
import GolfSync

/// Lock Screen and Dynamic Island actions. Runs in whichever process iOS dispatches the intent to,
/// so every change goes through the coordinated App Group store and notifies the phone app.
final class GolfRoundLiveActivityController: @unchecked Sendable {
    static let shared = GolfRoundLiveActivityController()

    private let store = SharedRoundStore.shared

    private init() {}

    func loadState() -> GolfRoundSharedState? {
        store.load()
    }

    @MainActor
    func adjustCurrentHoleScore(by delta: Int) async {
        await mutate { state in
            let hole = state.selectedHole
            state.scores[hole] = max(0, min(99, (state.scores[hole] ?? 0) + delta))
        }
    }

    @MainActor
    func setCurrentHoleScore(to score: Int) async {
        await mutate { state in
            state.scores[state.selectedHole] = max(0, min(99, score))
        }
    }

    @MainActor
    func advanceToNextHole() async {
        await mutate { state in
            guard !state.holes.isEmpty else { return }
            let index = state.holes.firstIndex(of: state.selectedHole) ?? -1
            state.selectedHole = state.holes[index < 0 ? 0 : (index + 1) % state.holes.count]
        }
    }

    @MainActor
    func retreatToPreviousHole() async {
        await mutate { state in
            guard !state.holes.isEmpty else { return }
            let index = state.holes.firstIndex(of: state.selectedHole) ?? 0
            state.selectedHole = state.holes[(index - 1 + state.holes.count) % state.holes.count]
        }
    }

    @MainActor
    func pinCurrentLocationShot() async {
        guard let location = await LiveActivityLocationProvider.shared.currentLocation() else { return }
        await mutate { state in
            state.pendingGpsPins.append(GolfRoundGpsPin(
                hole: state.selectedHole,
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude
            ))
        }
    }

    @MainActor
    func refreshGpsYardage() async {
        guard let location = await LiveActivityLocationProvider.shared.currentLocation() else { return }
        let here = Coordinate(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
        let updated = store.update { current in
            guard var state = current, let green = state.greenCoordinate else { return nil }
            state.yardsToGreen = GeoMath.yardsBetween(here, green)
            state.gpsRefreshRevision += 1
            return state
        }
        if let updated {
            await pushDisplayUpdate(from: updated)
        }
    }

    @MainActor
    private func mutate(_ change: @escaping (inout GolfRoundSharedState) -> Void) async {
        let updated = store.update { current in
            guard var state = current else { return nil }
            change(&state)
            state.revision += 1
            state.protocolVersion = SyncProtocol.current
            return state
        }
        if let updated {
            await pushDisplayUpdate(from: updated)
        }
    }

    @MainActor
    func pushDisplayUpdate(from state: GolfRoundSharedState) async {
        let rawScore = state.currentHoleScore
        let payload: [String: Any] = [
            "courseName": state.courseName,
            "hole": state.selectedHole,
            "par": state.currentPar,
            "holeScore": rawScore > 0 ? rawScore : -1,
            "totalScore": state.totalScore,
            "relativeToPar": state.relativeToPar,
            "yardsToGreen": state.yardsToGreen,
        ]

        let content = LiveActivitiesAppAttributes.ContentState(appGroupId: GolfRoundSharedState.appGroupId)
        for activity in Activity<LiveActivitiesAppAttributes>.activities {
            guard activity.activityState == .active || activity.activityState == .stale else { continue }
            for (key, value) in payload {
                store.setActivityValue(value, key: key, activityId: activity.attributes.id.uuidString)
            }
            await activity.update(ActivityContent(state: content, staleDate: nil))
        }
    }
}

@MainActor
final class LiveActivityLocationProvider: NSObject, CLLocationManagerDelegate {
    static let shared = LiveActivityLocationProvider()

    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocation?, Never>?
    private var timeoutTask: Task<Void, Never>?

    private override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
    }

    func currentLocation(timeoutSeconds: TimeInterval = 10) async -> CLLocation? {
        let status = manager.authorizationStatus
        if status == .denied || status == .restricted {
            return manager.location
        }

        if status == .notDetermined {
            manager.requestWhenInUseAuthorization()
            try? await Task.sleep(nanoseconds: 400_000_000)
        }

        if let cached = manager.location,
           abs(cached.timestamp.timeIntervalSinceNow) < 20 {
            return cached
        }

        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            manager.requestLocation()

            timeoutTask?.cancel()
            timeoutTask = Task {
                try? await Task.sleep(nanoseconds: UInt64(timeoutSeconds * 1_000_000_000))
                self.finish(with: self.manager.location)
            }
        }
    }

    private func finish(with location: CLLocation?) {
        timeoutTask?.cancel()
        timeoutTask = nil
        continuation?.resume(returning: location)
        continuation = nil
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let location = locations.last
        Task { @MainActor in
            finish(with: location)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            finish(with: self.manager.location)
        }
    }
}
