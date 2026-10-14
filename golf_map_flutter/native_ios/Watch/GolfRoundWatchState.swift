import Foundation
import GolfCore
import GolfSync
import WatchConnectivity

/// Holds no state of its own; everything lives in thread-safe `UserDefaults`.
final class GolfRoundWatchStore: @unchecked Sendable {
    static let shared = GolfRoundWatchStore()

    private let defaults = UserDefaults.standard
    private var appGroupDefaults: UserDefaults? {
        UserDefaults(suiteName: GolfRoundSharedState.appGroupId)
    }
    private static let acceptedSwingsKey = "golf_round_accepted_swings"
    private static let dedupRadiusYards = SyncProtocol.undoProximityYards

    private init() {}

    func loadPhoneAppGroupState() -> GolfRoundSharedState? {
        guard let defaults = appGroupDefaults,
              let data = defaults.data(forKey: GolfRoundSharedState.phoneStorageKey) else {
            return nil
        }
        return try? JSONDecoder().decode(GolfRoundSharedState.self, from: data)
    }

    func isPhoneRoundHostActive() -> Bool {
        appGroupDefaults?.bool(forKey: GolfRoundSharedState.hostActiveKey) ?? false
    }

    @discardableResult
    func reconcilePhoneAppGroupState() -> Bool {
        guard let phone = loadPhoneAppGroupState(),
              phone.isActiveRound else {
            return false
        }

        mergePhoneState(phone)
        return true
    }

    @discardableResult
    func reconcilePhoneHostAvailability() -> Bool {
        guard let local = load(), local.isActiveRound else { return false }

        let phoneState = loadPhoneAppGroupState()
        let hostActive = isPhoneRoundHostActive()

        if let phoneState,
           phoneState.isActiveRound,
           !local.sessionId.isEmpty,
           !phoneState.sessionId.isEmpty,
           local.sessionId != phoneState.sessionId {
            replaceWithPhoneSession(phoneState)
            return true
        }

        if let phoneState, phoneState.isActiveRound {
            return false
        }

        guard !hostActive else { return false }

        clearLocalSession()
        return true
    }

    func load() -> GolfRoundSharedState? {
        guard let data = defaults.data(forKey: GolfRoundSharedState.watchStorageKey) else {
            return nil
        }
        return try? JSONDecoder().decode(GolfRoundSharedState.self, from: data)
    }

    func save(_ state: GolfRoundSharedState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        defaults.set(data, forKey: GolfRoundSharedState.watchStorageKey)
    }

    func clearLocalSession() {
        defaults.removeObject(forKey: GolfRoundSharedState.watchStorageKey)
        clearAcceptedSwingPins()
    }

    func handleSessionReset(sessionId: String) {
        _ = sessionId
        clearLocalSession()
    }

    /// Ignore stale phone session resets while a newer round is already active.
    func shouldIgnoreSessionReset(_ sessionId: String) -> Bool {
        if isPhoneRoundHostActive() {
            return true
        }

        if let phone = loadPhoneAppGroupState(), phone.isActiveRound {
            mergePhoneState(phone)
            return true
        }

        if let local = load(), local.isActiveRound,
           !sessionId.isEmpty, !local.sessionId.isEmpty,
           sessionId != local.sessionId {
            return true
        }

        return false
    }

    @discardableResult
    func applySessionResetIfNeeded(sessionId: String) -> Bool {
        guard !shouldIgnoreSessionReset(sessionId) else { return false }
        handleSessionReset(sessionId: sessionId)
        return true
    }

    private func roundState(from context: [String: Any]) -> GolfRoundSharedState? {
        if let nested = context["state"] as? [String: Any],
           let phone = GolfRoundSharedState.fromDictionary(nested),
           phone.isActiveRound {
            return phone
        }
        return nil
    }

    func replaceWithPhoneSession(_ phone: GolfRoundSharedState) {
        clearAcceptedSwingPins()
        save(phone)
    }

    private func sessionsMismatch(local: GolfRoundSharedState?, phone: GolfRoundSharedState) -> Bool {
        if !phone.sessionId.isEmpty {
            if local?.sessionId != phone.sessionId {
                return true
            }
            return false
        }

        if let local, local.isActiveRound, local.courseName != phone.courseName {
            return true
        }
        return false
    }

    func applyPhoneState(_ state: GolfRoundSharedState) {
        mergePhoneState(state)
    }

    @discardableResult
    func reconcileFromPhoneContext() -> Bool {
        if reconcilePhoneAppGroupState() {
            return true
        }

        guard WCSession.isSupported() else { return false }
        let session = WCSession.default
        guard session.activationState == .activated else { return false }

        let context = session.receivedApplicationContext

        if context["type"] as? String == WatchMessage.roundStateType,
           let phone = roundState(from: context) {
            mergePhoneState(phone)
            return true
        }

        if context["type"] as? String == WatchMessage.sessionResetType {
            let sessionId = context["sessionId"] as? String ?? ""
            _ = applySessionResetIfNeeded(sessionId: sessionId)
            return false
        }

        return false
    }

    func mergePhoneState(_ phone: GolfRoundSharedState) {
        guard phone.isActiveRound else { return }

        let local = load()
        if sessionsMismatch(local: local, phone: phone) {
            replaceWithPhoneSession(phone)
            return
        }

        guard var local, local.isActiveRound else {
            save(phone)
            return
        }

        let localPending = local.pendingGpsPins

        if phone.revision > local.revision {
            if !phone.pendingGpsPinUndos.isEmpty {
                pruneAcceptedSwingPins(matching: phone.pendingGpsPinUndos)
            }

            var merged = phone
            for hole in phone.holes {
                let phoneScore = phone.scores[hole] ?? 0
                let localScore = local.scores[hole] ?? 0
                merged.scores[hole] = max(phoneScore, localScore)
            }
            merged.pendingGpsPins.removeAll { pin in
                phone.pendingGpsPinUndos.contains { pin.refersToSamePin(as: $0) }
            }
            if phone.pendingGpsPins.isEmpty {
                merged.pendingGpsPins = []
            } else {
                for pin in localPending where !merged.pendingGpsPins.contains(where: { $0.refersToSamePin(as: pin) }) {
                    let undone = phone.pendingGpsPinUndos.contains { pin.refersToSamePin(as: $0) }
                    if !undone {
                        merged.pendingGpsPins.append(pin)
                    }
                }
            }
            // Phone is authoritative; do not keep stale watch-only undo queues.
            merged.pendingGpsPinUndos = []
            save(merged)
            return
        }

        var changed = false
        if phone.gpsRefreshRevision > local.gpsRefreshRevision {
            local.yardsToGreen = phone.yardsToGreen
            local.gpsRefreshRevision = phone.gpsRefreshRevision
            changed = true
        }
        if phone.greenLatitude != local.greenLatitude ||
            phone.greenLongitude != local.greenLongitude {
            local.greenLatitude = phone.greenLatitude
            local.greenLongitude = phone.greenLongitude
            changed = true
        }

        if phone.revision == local.revision {
            if phone.scores != local.scores {
                for hole in phone.holes {
                    let phoneScore = phone.scores[hole] ?? 0
                    let localScore = local.scores[hole] ?? 0
                    local.scores[hole] = max(phoneScore, localScore)
                }
                changed = true
            }
            if phone.putts != local.putts {
                local.putts = phone.putts
                changed = true
            }
            if phone.selectedHole != local.selectedHole {
                local.selectedHole = phone.selectedHole
                changed = true
            }
        }

        if changed {
            save(local)
        }
    }

    /// Pull the latest revision from the phone so watch edits are not rejected.
    func syncRevisionFromPhone() {
        _ = reconcileFromPhoneContext()
    }

    private func bumpRevision(_ state: inout GolfRoundSharedState) {
        syncRevisionFromPhone()
        let baseline = load()?.revision ?? state.revision
        state.revision = baseline + 1
        state.protocolVersion = SyncProtocol.current
    }

    @discardableResult
    func adjustCurrentHoleScore(by delta: Int) -> GolfRoundSharedState? {
        guard var state = load(), state.isActiveRound else { return nil }
        let hole = state.selectedHole
        let current = state.scores[hole] ?? 0
        state.scores[hole] = max(0, min(99, current + delta))
        bumpRevision(&state)
        save(state)
        return state
    }

    @discardableResult
    func setCurrentHoleScore(to score: Int) -> GolfRoundSharedState? {
        guard var state = load(), state.isActiveRound else { return nil }
        let hole = state.selectedHole
        state.scores[hole] = max(0, min(99, score))
        bumpRevision(&state)
        save(state)
        return state
    }

    @discardableResult
    func setCurrentHolePutts(to putts: Int) -> GolfRoundSharedState? {
        guard var state = load(), state.isActiveRound else { return nil }
        let hole = state.selectedHole
        state.putts[hole] = max(0, min(9, putts))
        bumpRevision(&state)
        save(state)
        return state
    }

    @discardableResult
    func advanceHole() -> GolfRoundSharedState? {
        guard var state = load(), !state.holes.isEmpty else { return nil }
        let index = state.holes.firstIndex(of: state.selectedHole) ?? -1
        let nextIndex = index < 0 ? 0 : (index + 1) % state.holes.count
        state.selectedHole = state.holes[nextIndex]
        bumpRevision(&state)
        save(state)
        return state
    }

    @discardableResult
    func retreatHole() -> GolfRoundSharedState? {
        guard var state = load(), !state.holes.isEmpty else { return nil }
        let index = state.holes.firstIndex(of: state.selectedHole) ?? 0
        let previousIndex = (index - 1 + state.holes.count) % state.holes.count
        state.selectedHole = state.holes[previousIndex]
        bumpRevision(&state)
        save(state)
        return state
    }

    func updateWatchYardage(_ yards: Int) {
        guard var state = load() else { return }
        state.yardsToGreen = yards
        state.gpsRefreshRevision += 1
        save(state)
    }

    func loadAcceptedSwingPins() -> [GolfRoundGpsPin] {
        guard let data = defaults.data(forKey: Self.acceptedSwingsKey),
              let pins = try? JSONDecoder().decode([GolfRoundGpsPin].self, from: data) else {
            return []
        }
        return pins
    }

    func saveAcceptedSwingPins(_ pins: [GolfRoundGpsPin]) {
        guard let data = try? JSONEncoder().encode(pins) else { return }
        defaults.set(data, forKey: Self.acceptedSwingsKey)
    }

    func clearAcceptedSwingPins() {
        defaults.removeObject(forKey: Self.acceptedSwingsKey)
    }

    func hasAcceptedSwing(on hole: String) -> Bool {
        loadAcceptedSwingPins().contains { $0.hole == hole }
    }

    func hasUndoableSwing(on hole: String) -> Bool {
        if hasAcceptedSwing(on: hole) { return true }
        guard let state = load() else { return false }
        return state.pendingGpsPins.contains { $0.hole == hole }
    }

    func isPinWithinDedupRadius(
        hole: String,
        latitude: Double,
        longitude: Double
    ) -> Bool {
        let candidate = GolfRoundGpsPin(hole: hole, latitude: latitude, longitude: longitude, eventId: nil)
        let pending = load()?.pendingGpsPins.filter { $0.hole == hole } ?? []
        let accepted = loadAcceptedSwingPins().filter { $0.hole == hole }
        return (accepted + pending).contains { $0.yards(to: candidate) < Self.dedupRadiusYards }
    }

    func pruneAcceptedSwingPins(matching undos: [GolfRoundGpsPin]) {
        guard !undos.isEmpty else { return }
        let pending = load()?.pendingGpsPins ?? []
        var accepted = loadAcceptedSwingPins()
        accepted.removeAll { pin in
            guard undos.contains(where: { pin.refersToSamePin(as: $0) }) else {
                return false
            }
            // Keep swings still waiting to sync to the phone.
            if pending.contains(where: { pin.refersToSamePin(as: $0) }) {
                return false
            }
            return true
        }
        saveAcceptedSwingPins(accepted)
    }

    func pruneLastAcceptedSwing(on hole: String) {
        var accepted = loadAcceptedSwingPins()
        guard let index = accepted.lastIndex(where: { $0.hole == hole }) else { return }
        accepted.remove(at: index)
        saveAcceptedSwingPins(accepted)
    }

    func clearPendingSyncQueues() {
        guard var state = load() else { return }
        guard !state.pendingGpsPins.isEmpty || !state.pendingGpsPinUndos.isEmpty else {
            return
        }
        state.pendingGpsPins = []
        state.pendingGpsPinUndos = []
        save(state)
    }

    /// Records a detected full swing: pins GPS, increments score, and dedupes
    /// additional swings within 25 yards on the same hole (practice swings).
    @discardableResult
    func recordDetectedSwing(
        hole: String,
        latitude: Double,
        longitude: Double,
        imuSessionId: String? = nil
    ) -> GolfRoundSharedState? {
        guard var state = load(), state.isActiveRound else { return nil }

        if isPinWithinDedupRadius(
            hole: hole,
            latitude: latitude,
            longitude: longitude
        ) {
            return nil
        }

        let pin = GolfRoundGpsPin(
            hole: hole,
            latitude: latitude,
            longitude: longitude,
            imuSessionId: imuSessionId
        )

        state.pendingGpsPinUndos.removeAll { $0.hole == hole }

        var accepted = loadAcceptedSwingPins()
        accepted.append(pin)
        saveAcceptedSwingPins(accepted)

        state.pendingGpsPins.append(pin)

        let currentScore = state.scores[hole] ?? 0
        state.scores[hole] = min(99, currentScore + 1)
        bumpRevision(&state)
        save(state)
        return state
    }

    @discardableResult
    func recordLostBall(
        hole: String,
        latitude: Double,
        longitude: Double
    ) -> GolfRoundSharedState? {
        guard var state = load(), state.isActiveRound else { return nil }

        let pin = GolfRoundGpsPin(
            hole: hole,
            latitude: latitude,
            longitude: longitude,
            pinKind: "lostBall"
        )
        state.pendingGpsPins.append(pin)

        let currentScore = state.scores[hole] ?? 0
        state.scores[hole] = min(99, currentScore + 1)
        bumpRevision(&state)
        save(state)
        return state
    }

    @discardableResult
    func recordManualPin(
        hole: String,
        latitude: Double,
        longitude: Double
    ) -> GolfRoundSharedState? {
        guard var state = load(), state.isActiveRound else { return nil }

        let pin = GolfRoundGpsPin(
            hole: hole,
            latitude: latitude,
            longitude: longitude
        )
        state.pendingGpsPins.append(pin)
        bumpRevision(&state)
        save(state)
        return state
    }

    @discardableResult
    func undoLastDetectedSwing() -> GolfRoundSharedState? {
        guard var state = load(), state.isActiveRound else { return nil }
        let hole = state.selectedHole

        var accepted = loadAcceptedSwingPins()
        let removed: GolfRoundGpsPin

        if let index = accepted.lastIndex(where: { $0.hole == hole }) {
            removed = accepted.remove(at: index)
            saveAcceptedSwingPins(accepted)
        } else if let pendingIndex = state.pendingGpsPins.lastIndex(where: { $0.hole == hole }) {
            removed = state.pendingGpsPins.remove(at: pendingIndex)
        } else {
            return nil
        }

        if let pendingIndex = state.pendingGpsPins.lastIndex(where: { $0.refersToSamePin(as: removed) }) {
            state.pendingGpsPins.remove(at: pendingIndex)
        }

        if !state.pendingGpsPinUndos.contains(where: { $0.refersToSamePin(as: removed) }) {
            state.pendingGpsPinUndos.append(removed)
        }

        let currentScore = state.scores[hole] ?? 0
        state.scores[hole] = max(0, currentScore - 1)
        bumpRevision(&state)
        save(state)
        return state
    }
}
