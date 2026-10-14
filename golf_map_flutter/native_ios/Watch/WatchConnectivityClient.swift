import Foundation
import GolfSync
import WatchConnectivity

extension Notification.Name {
    static let golfRoundWatchStateDidChange = Notification.Name("golfRoundWatchStateDidChange")
}

/// A WatchConnectivity payload decoded before it crosses to the main actor.
private struct IncomingPayload: Sendable {
    var type: String?
    var sessionId: String
    var state: GolfRoundSharedState?
    var ok: Bool?

    init(_ payload: [String: Any]) {
        type = payload["type"] as? String
        sessionId = payload["sessionId"] as? String ?? ""
        state = WatchMessage.decodeState(payload)
        ok = payload["ok"] as? Bool
    }
}

@MainActor
final class WatchConnectivityClient: NSObject, ObservableObject, WCSessionDelegate {
    static let shared = WatchConnectivityClient()

    @Published private(set) var phoneReachable = false

    private var lastPhoneSyncRequest: Date?

    private override init() {
        super.init()
    }

    func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    func sendStateChange(_ state: GolfRoundSharedState) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else { return }

        let payload = WatchMessage.roundState(state)

        try? session.updateApplicationContext(payload)

        if session.isReachable {
            session.sendMessage(
                payload,
                replyHandler: nil,
                errorHandler: { _ in
                    WCSession.default.transferUserInfo(WatchMessage.roundState(state))
                }
            )
        } else {
            session.transferUserInfo(payload)
        }
    }

    func requestPhoneRoundStateIfNeeded(minimumInterval: TimeInterval = 3) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated, session.isReachable else { return }

        let now = Date()
        if let lastPhoneSyncRequest,
           now.timeIntervalSince(lastPhoneSyncRequest) < minimumInterval {
            return
        }
        lastPhoneSyncRequest = now

        session.sendMessage(
            ["type": WatchMessage.requestRoundStateType],
            replyHandler: { [weak self] reply in
                let incoming = IncomingPayload(reply)
                Task { @MainActor in
                    if incoming.ok == false {
                        if GolfRoundWatchStore.shared.reconcilePhoneAppGroupState()
                            || GolfRoundWatchStore.shared.reconcilePhoneHostAvailability() {
                            NotificationCenter.default.post(name: .golfRoundWatchStateDidChange, object: nil)
                        }
                        return
                    }
                    self?.applyIncomingPayload(incoming)
                }
            },
            errorHandler: { _ in
                Task { @MainActor in
                    guard GolfRoundWatchStore.shared.load()?.isActiveRound == true else { return }
                    if GolfRoundWatchStore.shared.reconcilePhoneHostAvailability() {
                        NotificationCenter.default.post(name: .golfRoundWatchStateDidChange, object: nil)
                    }
                }
            }
        )
    }

    private func applyIncomingPayload(_ payload: IncomingPayload) {
        if payload.type == WatchMessage.sessionResetType {
            if GolfRoundWatchStore.shared.applySessionResetIfNeeded(sessionId: payload.sessionId) {
                NotificationCenter.default.post(name: .golfRoundWatchStateDidChange, object: nil)
            }
            return
        }

        guard let state = payload.state, state.isActiveRound else { return }
        GolfRoundWatchStore.shared.mergePhoneState(state)
        NotificationCenter.default.post(name: .golfRoundWatchStateDidChange, object: nil)
    }

    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        let reachable = session.isReachable
        Task { @MainActor in
            phoneReachable = reachable
            if GolfRoundWatchStore.shared.reconcileFromPhoneContext() {
                NotificationCenter.default.post(name: .golfRoundWatchStateDidChange, object: nil)
            }
            if reachable {
                requestPhoneRoundStateIfNeeded(minimumInterval: 0)
            }
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        let reachable = session.isReachable
        Task { @MainActor in
            phoneReachable = reachable
            if reachable {
                if GolfRoundWatchStore.shared.reconcileFromPhoneContext() {
                    NotificationCenter.default.post(name: .golfRoundWatchStateDidChange, object: nil)
                }
                requestPhoneRoundStateIfNeeded(minimumInterval: 0)
            }
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        let incoming = IncomingPayload(applicationContext)
        Task { @MainActor in applyIncomingPayload(incoming) }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        let incoming = IncomingPayload(userInfo)
        Task { @MainActor in applyIncomingPayload(incoming) }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        let incoming = IncomingPayload(message)
        Task { @MainActor in applyIncomingPayload(incoming) }
    }
}
