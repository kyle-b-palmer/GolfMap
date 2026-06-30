import Foundation
import Combine

@MainActor
final class GolfRoundWatchViewModel: ObservableObject {
    @Published private(set) var state: GolfRoundSharedState?
    @Published private(set) var yardsToGreen: Int?

    private var timer: Timer?
    private var cancellables = Set<AnyCancellable>()

    init() {
        WatchLocationManager.shared.$yardsToGreen
            .receive(on: RunLoop.main)
            .sink { [weak self] yards in
                self?.yardsToGreen = yards
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .golfRoundWatchStateDidChange)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.reload()
            }
            .store(in: &cancellables)
    }

    func start() {
        WatchConnectivityClient.shared.activate()
        reload()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.reload()
            }
        }
        WatchLocationManager.shared.startUpdates()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        WatchLocationManager.shared.stopUpdates()
    }

    func reload() {
        let loaded = GolfRoundWatchStore.shared.load()
        state = loaded
        if let loaded {
            WatchLocationManager.shared.updateGreenTarget(
                latitude: loaded.greenLatitude,
                longitude: loaded.greenLongitude
            )
        }
        if yardsToGreen == nil {
            yardsToGreen = loaded?.yardsToGreen
        }
    }

    func incrementScore() {
        applyScoreChange(GolfRoundWatchStore.shared.adjustCurrentHoleScore(by: 1))
    }

    func decrementScore() {
        applyScoreChange(GolfRoundWatchStore.shared.adjustCurrentHoleScore(by: -1))
    }

    func setScore(_ score: Int) {
        applyScoreChange(GolfRoundWatchStore.shared.setCurrentHoleScore(to: score))
    }

    func setPutts(_ putts: Int) {
        applyScoreChange(GolfRoundWatchStore.shared.setCurrentHolePutts(to: putts))
    }

    func nextHole() {
        guard let updated = GolfRoundWatchStore.shared.advanceHole() else { return }
        state = updated
        WatchConnectivityClient.shared.sendStateChange(updated)
        WatchLocationManager.shared.updateGreenTarget(
            latitude: updated.greenLatitude,
            longitude: updated.greenLongitude
        )
    }

    func previousHole() {
        guard let updated = GolfRoundWatchStore.shared.retreatHole() else { return }
        state = updated
        WatchConnectivityClient.shared.sendStateChange(updated)
        WatchLocationManager.shared.updateGreenTarget(
            latitude: updated.greenLatitude,
            longitude: updated.greenLongitude
        )
    }

    private func applyScoreChange(_ updated: GolfRoundSharedState?) {
        guard let updated else { return }
        state = updated
        WatchConnectivityClient.shared.sendStateChange(updated)
    }
}
