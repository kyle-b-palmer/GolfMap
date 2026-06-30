import Foundation
import WatchConnectivity

final class WatchConnectivityBridge: NSObject, WCSessionDelegate {
    static let shared = WatchConnectivityBridge()

    private override init() {
        super.init()
    }

    func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    func pushRoundStateIfNeeded() {
        guard WCSession.isSupported() else { return }

        let session = WCSession.default
        guard session.activationState == .activated else { return }
        guard let state = GolfRoundLiveActivityController.shared.loadState(),
              !state.holes.isEmpty,
              !state.courseName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        let payload = roundPayload(for: state)

        do {
            try session.updateApplicationContext(payload)
        } catch {
            // Context update can fail if unchanged; fall through to message.
        }

        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil, errorHandler: nil)
        }
    }

    private func roundPayload(for state: GolfRoundSharedState) -> [String: Any] {
        [
            "type": "roundState",
            "revision": state.revision,
            "state": dictionary(from: state),
        ]
    }

    private func dictionary(from state: GolfRoundSharedState) -> [String: Any] {
        guard let data = try? JSONEncoder().encode(state),
              let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any] else {
            return [:]
        }
        return dictionary
    }

    private func applyWatchPayload(_ payload: [String: Any]) {
        guard let nested = payload["state"] as? [String: Any],
              JSONSerialization.isValidJSONObject(nested),
              let data = try? JSONSerialization.data(withJSONObject: nested),
              let incoming = try? JSONDecoder().decode(GolfRoundSharedState.self, from: data) else {
            return
        }

        if let current = GolfRoundLiveActivityController.shared.loadState() {
            guard incoming.revision > current.revision else { return }
            var updated = current
            updated.scores = incoming.scores
            updated.putts = incoming.putts
            updated.selectedHole = incoming.selectedHole
            updated.revision = incoming.revision
            GolfRoundLiveActivityController.shared.saveState(updated)
            publishWatchMerge(updated)
            return
        }

        guard !incoming.holes.isEmpty, !incoming.courseName.isEmpty else { return }
        GolfRoundLiveActivityController.shared.saveState(incoming)
        publishWatchMerge(incoming)
    }

    private func publishWatchMerge(_ state: GolfRoundSharedState) {
        if #available(iOS 16.1, *) {
            Task { @MainActor in
                await GolfRoundLiveActivityController.shared.pushDisplayUpdate(from: state)
            }
        }
        LiveActivityBridge.notifyForeground()
    }

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        pushRoundStateIfNeeded()
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        if session.isReachable {
            pushRoundStateIfNeeded()
        }
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        applyWatchPayload(message)
    }

    func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        applyWatchPayload(message)
        replyHandler(["ok": true])
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        applyWatchPayload(userInfo)
    }
}
