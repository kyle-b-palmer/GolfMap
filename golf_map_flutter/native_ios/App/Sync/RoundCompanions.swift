import Foundation
import GolfSync

/// The surfaces that follow a round outside the app: the Watch, the Live Activity, and the Health workout.
@MainActor
protocol RoundCompanions: AnyObject {
    func roundPublished(_ state: GolfRoundSharedState)
    /// The round screen closed with the round still active.
    func roundLeft()
    /// The round was saved or discarded.
    func roundEnded(sessionId: String)
}

@MainActor
final class LiveRoundCompanions: RoundCompanions {
    static let shared = LiveRoundCompanions()

    func roundPublished(_ state: GolfRoundSharedState) {
        PhoneWatchSession.shared.pushRoundState()
        RoundLiveActivity.shared.update(from: state)
    }

    /// Flutter ended the Live Activity whenever the round screen closed; it returns with the round.
    func roundLeft() {
        RoundLiveActivity.shared.end()
    }

    func roundEnded(sessionId: String) {
        RoundLiveActivity.shared.end()
        PhoneWatchSession.shared.pushSessionReset(sessionId: sessionId)
        Task { await HealthWorkoutService.shared.end() }
    }
}
