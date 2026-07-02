import CoreLocation
import Foundation
import WatchConnectivity

struct GolfRoundGpsPin: Codable, Equatable {
    let hole: String
    let latitude: Double
    let longitude: Double
    var pinKind: String?

    init(
        hole: String,
        latitude: Double,
        longitude: Double,
        pinKind: String? = nil
    ) {
        self.hole = hole
        self.latitude = latitude
        self.longitude = longitude
        self.pinKind = pinKind
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hole = try container.decode(String.self, forKey: .hole)
        latitude = try container.decode(Double.self, forKey: .latitude)
        longitude = try container.decode(Double.self, forKey: .longitude)
        pinKind = try container.decodeIfPresent(String.self, forKey: .pinKind)
    }
}

struct GolfRoundSharedState: Codable, Equatable {
    var holes: [String]
    var selectedHole: String
    var scores: [String: Int]
    var putts: [String: Int]
    var pars: [String: Int]
    var handicaps: [String: Int]
    var courseName: String
    var yardsToGreen: Int
    var revision: Int
    var pendingGpsPins: [GolfRoundGpsPin]
    var pendingGpsPinUndos: [GolfRoundGpsPin]
    var greenLatitude: Double
    var greenLongitude: Double
    var gpsRefreshRevision: Int
    var sessionId: String

    static let storageKey = "golf_round_watch_state"
    static let phoneSharedStorageKey = "golf_round_shared_state"
    static let hostActiveKey = "golf_round_host_active"
    static let watchConnectivityKey = "roundState"
    static let appGroupId = "group.com.golfmapapp.golfMapFlutter"

    init(
        holes: [String] = [],
        selectedHole: String = "1",
        scores: [String: Int] = [:],
        putts: [String: Int] = [:],
        pars: [String: Int] = [:],
        handicaps: [String: Int] = [:],
        courseName: String = "",
        yardsToGreen: Int = -1,
        revision: Int = 0,
        pendingGpsPins: [GolfRoundGpsPin] = [],
        pendingGpsPinUndos: [GolfRoundGpsPin] = [],
        greenLatitude: Double = 0,
        greenLongitude: Double = 0,
        gpsRefreshRevision: Int = 0,
        sessionId: String = ""
    ) {
        self.holes = holes
        self.selectedHole = selectedHole
        self.scores = scores
        self.putts = putts
        self.pars = pars
        self.handicaps = handicaps
        self.courseName = courseName
        self.yardsToGreen = yardsToGreen
        self.revision = revision
        self.pendingGpsPins = pendingGpsPins
        self.pendingGpsPinUndos = pendingGpsPinUndos
        self.greenLatitude = greenLatitude
        self.greenLongitude = greenLongitude
        self.gpsRefreshRevision = gpsRefreshRevision
        self.sessionId = sessionId
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        holes = try container.decode([String].self, forKey: .holes)
        selectedHole = try container.decode(String.self, forKey: .selectedHole)
        scores = try container.decode([String: Int].self, forKey: .scores)
        putts = try container.decodeIfPresent([String: Int].self, forKey: .putts) ?? [:]
        pars = try container.decode([String: Int].self, forKey: .pars)
        handicaps = try container.decodeIfPresent([String: Int].self, forKey: .handicaps) ?? [:]
        courseName = try container.decode(String.self, forKey: .courseName)
        yardsToGreen = try container.decode(Int.self, forKey: .yardsToGreen)
        revision = try container.decode(Int.self, forKey: .revision)
        pendingGpsPins = try container.decodeIfPresent(
            [GolfRoundGpsPin].self,
            forKey: .pendingGpsPins
        ) ?? []
        pendingGpsPinUndos = try container.decodeIfPresent(
            [GolfRoundGpsPin].self,
            forKey: .pendingGpsPinUndos
        ) ?? []
        greenLatitude = try container.decodeIfPresent(Double.self, forKey: .greenLatitude) ?? 0
        greenLongitude = try container.decodeIfPresent(Double.self, forKey: .greenLongitude) ?? 0
        gpsRefreshRevision = try container.decodeIfPresent(Int.self, forKey: .gpsRefreshRevision) ?? 0
        sessionId = try container.decodeIfPresent(String.self, forKey: .sessionId) ?? ""
    }

    var isActiveRound: Bool {
        !holes.isEmpty && !courseName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var currentPar: Int {
        pars[selectedHole] ?? 0
    }

    var currentHandicap: Int {
        handicaps[selectedHole] ?? 0
    }

    var currentHoleScore: Int {
        scores[selectedHole] ?? 0
    }

    var currentHolePutts: Int {
        putts[selectedHole] ?? 0
    }

    var totalPutts: Int {
        holes.reduce(0) { partial, hole in
            partial + (putts[hole] ?? 0)
        }
    }

    var totalScore: Int {
        holes.reduce(0) { partial, hole in
            partial + (scores[hole] ?? 0)
        }
    }

    var relativeToPar: Int {
        holes.reduce(0) { partial, hole in
            let score = scores[hole] ?? 0
            guard score > 0 else { return partial }
            let par = pars[hole] ?? 0
            guard par > 0 else { return partial }
            return partial + (score - par)
        }
    }

    func dictionaryPayload() -> [String: Any] {
        guard let data = try? JSONEncoder().encode(self),
              let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any] else {
            return [:]
        }
        return dictionary
    }

    static func fromDictionary(_ dictionary: [String: Any]) -> GolfRoundSharedState? {
        guard JSONSerialization.isValidJSONObject(dictionary),
              let data = try? JSONSerialization.data(withJSONObject: dictionary) else {
            return nil
        }
        return try? JSONDecoder().decode(GolfRoundSharedState.self, from: data)
    }
}

final class GolfRoundWatchStore {
    static let shared = GolfRoundWatchStore()

    private let defaults = UserDefaults.standard
    private var appGroupDefaults: UserDefaults? {
        UserDefaults(suiteName: GolfRoundSharedState.appGroupId)
    }
    private static let acceptedSwingsKey = "golf_round_accepted_swings"
    private static let dedupRadiusYards = 25

    private init() {}

    func loadPhoneAppGroupState() -> GolfRoundSharedState? {
        guard let defaults = appGroupDefaults,
              let data = defaults.data(forKey: GolfRoundSharedState.phoneSharedStorageKey) else {
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
        guard let data = defaults.data(forKey: GolfRoundSharedState.storageKey) else {
            return nil
        }
        return try? JSONDecoder().decode(GolfRoundSharedState.self, from: data)
    }

    func save(_ state: GolfRoundSharedState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        defaults.set(data, forKey: GolfRoundSharedState.storageKey)
    }

    func clearLocalSession() {
        defaults.removeObject(forKey: GolfRoundSharedState.storageKey)
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

        if context["type"] as? String == "roundState",
           let phone = roundState(from: context) {
            mergePhoneState(phone)
            return true
        }

        if context["type"] as? String == "sessionReset" {
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
                phone.pendingGpsPinUndos.contains { undo in
                    pinsApproximatelyEqual(pin, undo)
                }
            }
            if phone.pendingGpsPins.isEmpty {
                merged.pendingGpsPins = []
            } else {
                for pin in localPending where !merged.pendingGpsPins.contains(pin) {
                    let undone = phone.pendingGpsPinUndos.contains { undo in
                        pinsApproximatelyEqual(pin, undo)
                    }
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
        let candidate = GolfRoundGpsPin(
            hole: hole,
            latitude: latitude,
            longitude: longitude
        )
        let pending = load()?.pendingGpsPins.filter { $0.hole == hole } ?? []
        let accepted = loadAcceptedSwingPins().filter { $0.hole == hole }
        for existing in accepted + pending {
            if yardsBetweenPin(existing, candidate) < Self.dedupRadiusYards {
                return true
            }
        }
        return false
    }

    func pruneAcceptedSwingPins(matching undos: [GolfRoundGpsPin]) {
        guard !undos.isEmpty else { return }
        let pending = load()?.pendingGpsPins ?? []
        var accepted = loadAcceptedSwingPins()
        accepted.removeAll { pin in
            guard undos.contains(where: { pinsApproximatelyEqual(pin, $0) }) else {
                return false
            }
            // Keep swings still waiting to sync to the phone.
            if pending.contains(where: { pinsApproximatelyEqual(pin, $0) }) {
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
        longitude: Double
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
            longitude: longitude
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

        if let pendingIndex = state.pendingGpsPins.lastIndex(where: {
            pinsApproximatelyEqual($0, removed)
        }) {
            state.pendingGpsPins.remove(at: pendingIndex)
        }

        let duplicateUndo = state.pendingGpsPinUndos.contains {
            pinsApproximatelyEqual($0, removed)
        }
        if !duplicateUndo {
            state.pendingGpsPinUndos.append(removed)
        }

        let currentScore = state.scores[hole] ?? 0
        state.scores[hole] = max(0, currentScore - 1)
        bumpRevision(&state)
        save(state)
        return state
    }
}

private func yardsBetweenPin(_ from: GolfRoundGpsPin, _ to: GolfRoundGpsPin) -> Int {
    let start = CLLocation(latitude: from.latitude, longitude: from.longitude)
    let end = CLLocation(latitude: to.latitude, longitude: to.longitude)
    return Int((start.distance(from: end) * 1.09361).rounded())
}

private func pinsApproximatelyEqual(_ lhs: GolfRoundGpsPin, _ rhs: GolfRoundGpsPin) -> Bool {
    guard lhs.hole == rhs.hole else { return false }
    return yardsBetweenPin(lhs, rhs) < 3
}
