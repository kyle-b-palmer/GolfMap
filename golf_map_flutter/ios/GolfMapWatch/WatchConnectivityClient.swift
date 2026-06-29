import Foundation
import WatchConnectivity

extension Notification.Name {
    static let golfRoundWatchStateDidChange = Notification.Name("golfRoundWatchStateDidChange")
}

@MainActor
final class WatchConnectivityClient: NSObject, ObservableObject, WCSessionDelegate {
    static let shared = WatchConnectivityClient()

    @Published private(set) var phoneReachable = false

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
            "state": state.dictionaryPayload(),
        ]

        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil) { _ in
                session.transferUserInfo(payload)
            }
        } else {
            session.transferUserInfo(payload)
        }
    }

    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        Task { @MainActor in
            phoneReachable = session.isReachable
            if let state = decodeState(from: session.receivedApplicationContext) {
                GolfRoundWatchStore.shared.applyPhoneState(state)
                NotificationCenter.default.post(name: .golfRoundWatchStateDidChange, object: nil)
            }
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            phoneReachable = session.isReachable
        }
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveApplicationContext applicationContext: [String: Any]
    ) {
        guard let state = decodeState(from: applicationContext) else { return }
        Task { @MainActor in
            GolfRoundWatchStore.shared.applyPhoneState(state)
            NotificationCenter.default.post(name: .golfRoundWatchStateDidChange, object: nil)
        }
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveUserInfo userInfo: [String: Any]
    ) {
        guard let state = decodeState(from: userInfo) else { return }
        Task { @MainActor in
            GolfRoundWatchStore.shared.applyPhoneState(state)
            NotificationCenter.default.post(name: .golfRoundWatchStateDidChange, object: nil)
        }
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any]
    ) {
        guard let state = decodeState(from: message) else { return }
        Task { @MainActor in
            GolfRoundWatchStore.shared.applyPhoneState(state)
            NotificationCenter.default.post(name: .golfRoundWatchStateDidChange, object: nil)
        }
    }

    nonisolated private func decodeState(from payload: [String: Any]) -> GolfRoundSharedState? {
        if let nested = payload["state"] as? [String: Any] {
            return GolfRoundSharedState.fromDictionary(nested)
        }
        return GolfRoundSharedState.fromDictionary(payload)
    }
}
