import Foundation
import WatchKit

/// Keeps motion + GPS active longer while a round is in progress on the watch.
@MainActor
final class WatchRoundRuntimeSession: NSObject, WKExtendedRuntimeSessionDelegate {
    static let shared = WatchRoundRuntimeSession()

    private var session: WKExtendedRuntimeSession?

    private override init() {
        super.init()
    }

    func startIfNeeded() {
        guard session == nil else { return }
        let session = WKExtendedRuntimeSession()
        session.delegate = self
        session.start()
        self.session = session
    }

    func stop() {
        session?.invalidate()
        session = nil
    }

    nonisolated func extendedRuntimeSessionDidStart(
        _ extendedRuntimeSession: WKExtendedRuntimeSession
    ) {}

    nonisolated func extendedRuntimeSessionWillExpire(
        _ extendedRuntimeSession: WKExtendedRuntimeSession
    ) {}

    nonisolated func extendedRuntimeSession(
        _ extendedRuntimeSession: WKExtendedRuntimeSession,
        didInvalidateWith reason: WKExtendedRuntimeSessionInvalidationReason,
        error: Error?
    ) {
        Task { @MainActor in
            if self.session === extendedRuntimeSession {
                self.session = nil
            }
        }
    }
}
