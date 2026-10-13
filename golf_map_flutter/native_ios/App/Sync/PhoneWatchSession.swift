import Foundation
import GolfSync
import os
import WatchConnectivity

/// Phone end of WatchConnectivity. Sends the shared round snapshot to the Watch and merges the Watch's
/// edits into it; the round store then picks them up through the App Group change notification.
final class PhoneWatchSession: NSObject, WCSessionDelegate, @unchecked Sendable {
    static let shared = PhoneWatchSession()

    private let store: SharedRoundStore
    private static let logger = Logger(subsystem: "com.golfmapapp.golfMapFlutter", category: "watch")

    init(store: SharedRoundStore = .shared) {
        self.store = store
        super.init()
    }

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    /// Application context always holds the latest state; a live message or queued transfer wakes the Watch sooner.
    func pushRoundState() {
        guard let session = activeSession, let state = store.load(), state.isActiveRound else { return }
        send(WatchMessage.roundState(state), via: session, queueIfUnreachable: true)
    }

    func pushSessionReset(sessionId: String) {
        guard let session = activeSession else { return }
        send(WatchMessage.sessionReset(sessionId: sessionId), via: session, queueIfUnreachable: false)
    }

    private var activeSession: WCSession? {
        guard WCSession.isSupported() else { return nil }
        let session = WCSession.default
        guard session.activationState == .activated, session.isPaired, session.isWatchAppInstalled else { return nil }
        return session
    }

    private func send(_ payload: [String: Any], via session: WCSession, queueIfUnreachable: Bool) {
        do {
            try session.updateApplicationContext(payload)
        } catch {
            Self.logger.debug("Application context not updated: \(error.localizedDescription)")
        }
        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil) { error in
                Self.logger.notice("Watch message failed: \(error.localizedDescription)")
            }
        } else if queueIfUnreachable {
            session.transferUserInfo(payload)
        }
    }

    /// Applies a Watch payload. Returns whether the shared snapshot changed.
    @discardableResult
    func apply(_ payload: [String: Any]) -> Bool {
        if payload["type"] as? String == WatchMessage.sessionResetType {
            let sessionId = payload["sessionId"] as? String ?? ""
            if !sessionId.isEmpty, store.load()?.sessionId == sessionId { return false }
            store.clear()
            return true
        }
        guard let incoming = WatchMessage.decodeState(payload) else { return false }
        var merged: GolfRoundSharedState?
        store.update { current in
            merged = PhoneRoundSync.mergeWatchPayload(incoming, into: current, activeSessionId: store.activeSessionId)
            return merged
        }
        guard let merged else { return false }
        Task { @MainActor in RoundLiveActivity.shared.update(from: merged) }
        return true
    }

    // MARK: WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if let error { Self.logger.error("Watch session activation failed: \(error.localizedDescription)") }
        pushRoundState()
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        if session.isReachable { pushRoundState() }
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        apply(message)
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        if message["type"] as? String == WatchMessage.requestRoundStateType {
            if let state = store.load(), state.isActiveRound {
                replyHandler(WatchMessage.roundState(state))
            } else {
                replyHandler(["ok": false])
            }
            return
        }
        apply(message)
        replyHandler(["ok": true])
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        apply(userInfo)
    }
}
