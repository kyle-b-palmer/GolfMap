import Foundation
import Combine
import WatchKit
import WidgetKit

@MainActor
final class GolfRoundWatchViewModel: ObservableObject {
    @Published private(set) var state: GolfRoundSharedState?
    @Published private(set) var yardsToGreen: Int?
    @Published private(set) var canUndoLastSwing = false
    @Published private(set) var isPinningLocation = false

    private var timer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private var swingDetectionSessionId = ""
    private var isHandlingSwing = false

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
        updateSwingDetection(for: state)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        WatchLocationManager.shared.stopUpdates()
        stopSwingDetection()
        WatchRoundRuntimeSession.shared.stop()
    }

    func reload() {
        _ = GolfRoundWatchStore.shared.reconcilePhoneAppGroupState()
        _ = GolfRoundWatchStore.shared.reconcileFromPhoneContext()
        WatchConnectivityClient.shared.requestPhoneRoundStateIfNeeded()

        let loaded = GolfRoundWatchStore.shared.load()
        state = loaded
        if let loaded {
            WatchLocationManager.shared.updateGreenTarget(
                latitude: loaded.greenLatitude,
                longitude: loaded.greenLongitude
            )
            yardsToGreen = loaded.yardsToGreen
            GolfRoundWidgetSnapshot.save(from: loaded, yardsToGreen: yardsToGreen)
            WidgetCenter.shared.reloadAllTimelines()
        } else {
            yardsToGreen = nil
            GolfRoundWidgetSnapshot.clear()
            WidgetCenter.shared.reloadAllTimelines()
        }
        updateSwingDetection(for: loaded)
        refreshUndoAvailability()
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

    func undoLastSwing() {
        guard let updated = GolfRoundWatchStore.shared.undoLastDetectedSwing() else {
            return
        }

        WKInterfaceDevice.current().play(.click)
        state = updated
        canUndoLastSwing = false
        refreshUndoAvailability()
        WatchConnectivityClient.shared.sendStateChange(updated)
    }

    func pinCurrentLocation() {
        guard !isPinningLocation else { return }
        guard let current = state, current.isActiveRound else { return }

        isPinningLocation = true
        Task {
            defer { isPinningLocation = false }

            guard let location = await WatchLocationManager.shared.requestFreshLocation() else {
                return
            }

            guard let updated = GolfRoundWatchStore.shared.recordManualPin(
                hole: current.selectedHole,
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude
            ) else {
                return
            }

            WKInterfaceDevice.current().play(.success)
            state = updated
            WatchConnectivityClient.shared.sendStateChange(updated)
        }
    }

    func recordLostBall() {
        guard !isPinningLocation else { return }
        guard let current = state, current.isActiveRound else { return }

        isPinningLocation = true
        Task {
            defer { isPinningLocation = false }

            guard let location = await WatchLocationManager.shared.requestFreshLocation() else {
                return
            }

            guard let updated = GolfRoundWatchStore.shared.recordLostBall(
                hole: current.selectedHole,
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude
            ) else {
                return
            }

            WKInterfaceDevice.current().play(.notification)
            state = updated
            WatchConnectivityClient.shared.sendStateChange(updated)
        }
    }

    var isPuttMode: Bool {
        guard let yards = yardsToGreen else { return false }
        return yards >= 0 && yards <= 45
    }

    func incrementPutts() {
        guard let current = state else { return }
        let hole = current.selectedHole
        let next = min(9, (current.putts[hole] ?? 0) + 1)
        applyScoreChange(GolfRoundWatchStore.shared.setCurrentHolePutts(to: next))
    }

    func decrementPutts() {
        guard let current = state else { return }
        let hole = current.selectedHole
        let next = max(0, (current.putts[hole] ?? 0) - 1)
        applyScoreChange(GolfRoundWatchStore.shared.setCurrentHolePutts(to: next))
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

    private func updateSwingDetection(for loaded: GolfRoundSharedState?) {
        guard let loaded, loaded.isActiveRound else {
            stopSwingDetection()
            return
        }

        let sessionKey = loaded.sessionId.isEmpty ? loaded.courseName : loaded.sessionId
        if !swingDetectionSessionId.isEmpty && sessionKey != swingDetectionSessionId {
            GolfRoundWatchStore.shared.clearAcceptedSwingPins()
        }
        swingDetectionSessionId = sessionKey

        WatchRoundRuntimeSession.shared.startIfNeeded()
        SwingDetector.shared.start { [weak self] in
            Task { @MainActor in
                await self?.handleDetectedSwing()
            }
        }
    }

    private func stopSwingDetection() {
        SwingDetector.shared.stop()
        swingDetectionSessionId = ""
        isHandlingSwing = false
        canUndoLastSwing = false
    }

    private func handleDetectedSwing() async {
        guard !isHandlingSwing else { return }
        guard let current = state, current.isActiveRound else { return }

        isHandlingSwing = true
        defer { isHandlingSwing = false }

        guard let location = await WatchLocationManager.shared.requestFreshLocation() else {
            WKInterfaceDevice.current().play(.failure)
            SwingDetector.shared.noteRejectedSwing()
            return
        }

        guard let updated = GolfRoundWatchStore.shared.recordDetectedSwing(
            hole: current.selectedHole,
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude
        ) else {
            WKInterfaceDevice.current().play(.click)
            SwingDetector.shared.noteRejectedSwing(cooldownSeconds: 3)
            return
        }

        SwingDetector.shared.noteAcceptedSwing()
        WKInterfaceDevice.current().play(.success)
        state = updated
        canUndoLastSwing = true
        refreshUndoAvailability()
        WatchConnectivityClient.shared.sendStateChange(updated)
    }

    private func refreshUndoAvailability() {
        guard let hole = state?.selectedHole else {
            canUndoLastSwing = false
            return
        }
        canUndoLastSwing = GolfRoundWatchStore.shared.hasUndoableSwing(on: hole)
    }
}
