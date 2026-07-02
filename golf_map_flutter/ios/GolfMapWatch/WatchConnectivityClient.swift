import Foundation
import WatchConnectivity

extension Notification.Name {
    static let golfRoundWatchStateDidChange = Notification.Name("golfRoundWatchStateDidChange")
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

        let payload: [String: Any] = [
            "type": "roundState",
            "revision": state.revision,
            "sessionId": state.sessionId,
            "state": state.dictionaryPayload(),
        ]

        try? session.updateApplicationContext(payload)

        if session.isReachable {
            session.sendMessage(
                payload,
                replyHandler: nil,
                errorHandler: { _ in
                    session.transferUserInfo(payload)
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
            ["type": "requestRoundState"],
            replyHandler: { [weak self] reply in
                Task { @MainActor in
                    if reply["ok"] as? Bool == false {
                        if GolfRoundWatchStore.shared.reconcilePhoneAppGroupState() {
                            NotificationCenter.default.post(
                                name: .golfRoundWatchStateDidChange,
                                object: nil
                            )
                            return
                        }
                        if GolfRoundWatchStore.shared.reconcilePhoneHostAvailability() {
                            NotificationCenter.default.post(
                                name: .golfRoundWatchStateDidChange,
                                object: nil
                            )
                        }
                        return
                    }
                    self?.applyIncomingPayload(reply)
                }
            },
            errorHandler: { _ in
                Task { @MainActor in
                    guard GolfRoundWatchStore.shared.load()?.isActiveRound == true else { return }
                    if GolfRoundWatchStore.shared.reconcilePhoneHostAvailability() {
                        NotificationCenter.default.post(
                            name: .golfRoundWatchStateDidChange,
                            object: nil
                        )
                    }
                }
            }
        )
    }

    private func applyIncomingPayload(_ payload: [String: Any]) {
        if payload["type"] as? String == "roundState",
           let state = decodeState(from: payload),
           state.isActiveRound {
            GolfRoundWatchStore.shared.mergePhoneState(state)
            NotificationCenter.default.post(name: .golfRoundWatchStateDidChange, object: nil)
            return
        }

        if payload["type"] as? String == "sessionReset" {
            let sessionId = payload["sessionId"] as? String ?? ""
            if GolfRoundWatchStore.shared.applySessionResetIfNeeded(sessionId: sessionId) {
                NotificationCenter.default.post(name: .golfRoundWatchStateDidChange, object: nil)
            }
            return
        }

        guard let state = decodeState(from: payload), state.isActiveRound else { return }
        GolfRoundWatchStore.shared.mergePhoneState(state)
        NotificationCenter.default.post(name: .golfRoundWatchStateDidChange, object: nil)
    }

    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        Task { @MainActor in
            phoneReachable = session.isReachable
            if GolfRoundWatchStore.shared.reconcileFromPhoneContext() {
                NotificationCenter.default.post(name: .golfRoundWatchStateDidChange, object: nil)
            }
            if session.isReachable {
                requestPhoneRoundStateIfNeeded(minimumInterval: 0)
            }
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            phoneReachable = session.isReachable
            if session.isReachable {
                if GolfRoundWatchStore.shared.reconcileFromPhoneContext() {
                    NotificationCenter.default.post(name: .golfRoundWatchStateDidChange, object: nil)
                }
                requestPhoneRoundStateIfNeeded(minimumInterval: 0)
            }
        }
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveApplicationContext applicationContext: [String: Any]
    ) {
        Task { @MainActor in
            applyIncomingPayload(applicationContext)
        }
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveUserInfo userInfo: [String: Any]
    ) {
        Task { @MainActor in
            applyIncomingPayload(userInfo)
        }
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any]
    ) {
        Task { @MainActor in
            applyIncomingPayload(message)
        }
    }

    nonisolated private func decodeState(from payload: [String: Any]) -> GolfRoundSharedState? {
        if let nested = payload["state"] as? [String: Any] {
            return GolfRoundSharedState.fromDictionary(nested)
        }
        return GolfRoundSharedState.fromDictionary(payload)
    }
}
