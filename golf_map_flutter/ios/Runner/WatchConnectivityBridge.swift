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
              state.isActiveRound else {
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
            let hasPins = !incoming.pendingGpsPins.isEmpty
            let hasUndos = !incoming.pendingGpsPinUndos.isEmpty
            let hasScoreChanges =
                incoming.scores != current.scores || incoming.putts != current.putts
            let hasHoleChange = incoming.selectedHole != current.selectedHole
            let revisionAhead = incoming.revision > current.revision

            guard revisionAhead || hasPins || hasUndos || hasScoreChanges || hasHoleChange else {
                return
            }

            var updated = current
            updated.scores = incoming.scores
            updated.putts = incoming.putts
            updated.selectedHole = incoming.selectedHole
            updated.revision = revisionAhead ? incoming.revision : current.revision + 1

            if hasPins {
                for pin in incoming.pendingGpsPins {
                    updated.pendingGpsPinUndos.removeAll { undo in
                        undo.hole == pin.hole &&
                            yardsBetweenPin(undo, pin) < 25
                    }

                    let duplicate = updated.pendingGpsPins.contains {
                        $0.hole == pin.hole &&
                            $0.latitude == pin.latitude &&
                            $0.longitude == pin.longitude
                    }
                    if !duplicate {
                        updated.pendingGpsPins.append(pin)
                    }
                }
            }
            if hasUndos {
                for pin in incoming.pendingGpsPinUndos {
                    let superseded = incoming.pendingGpsPins.contains { added in
                        added.hole == pin.hole &&
                            yardsBetweenPin(added, pin) < 25
                    }
                    if superseded { continue }

                    let duplicate = updated.pendingGpsPinUndos.contains {
                        $0.hole == pin.hole &&
                            $0.latitude == pin.latitude &&
                            $0.longitude == pin.longitude
                    }
                    if !duplicate {
                        updated.pendingGpsPinUndos.append(pin)
                    }
                }
            }
            GolfRoundLiveActivityController.shared.saveState(updated)
            publishWatchMerge(updated)
            return
        }

        guard !incoming.holes.isEmpty, !incoming.courseName.isEmpty else { return }
        GolfRoundLiveActivityController.shared.saveState(incoming)
        publishWatchMerge(incoming)
    }

    private func publishWatchMerge(_ state: GolfRoundSharedState) {
        LiveActivityBridge.notifyWatchStateChanged()
        if #available(iOS 16.1, *) {
            Task { @MainActor in
                await GolfRoundLiveActivityController.shared.pushDisplayUpdate(from: state)
            }
        }
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
        if message["type"] as? String == "requestRoundState" {
            if let state = GolfRoundLiveActivityController.shared.loadState(),
               state.isActiveRound {
                replyHandler(roundPayload(for: state))
            } else {
                replyHandler(["ok": false])
            }
            return
        }

        applyWatchPayload(message)
        replyHandler(["ok": true])
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        applyWatchPayload(userInfo)
    }
}
