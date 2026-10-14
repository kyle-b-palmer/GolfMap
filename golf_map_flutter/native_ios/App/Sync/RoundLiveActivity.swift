import ActivityKit
import Foundation
import GolfSync
import os

/// Starts, updates, and ends the round's Live Activity. Display values live in the App Group, keyed by
/// activity ID, which is the format the widget (and Flutter's `live_activities` plugin) use.
@MainActor
final class RoundLiveActivity {
    static let shared = RoundLiveActivity()

    private var lastUpdate: Date?
    private var lastDisplayed: DisplayKey?
    private static let logger = Logger(subsystem: "com.golfmapapp.golfMapFlutter", category: "live-activity")

    /// Yardage-only changes update at most this often; anything else updates at once.
    static let yardageInterval: TimeInterval = 5

    private struct DisplayKey: Equatable {
        var hole: String
        var scores: [String: Int]
        var yardsToGreen: Int
    }

    private var running: [Activity<LiveActivitiesAppAttributes>] {
        Activity<LiveActivitiesAppAttributes>.activities.filter { $0.activityState == .active || $0.activityState == .stale }
    }

    /// Creates the activity on first use, as Flutter's `syncRound` did, then pushes the current values.
    func update(from state: GolfRoundSharedState, now: Date = .now) {
        guard state.isActiveRound, ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let key = DisplayKey(hole: state.selectedHole, scores: state.scores, yardsToGreen: state.yardsToGreen)
        if let lastDisplayed, let lastUpdate, !running.isEmpty {
            if key == lastDisplayed { return }
            let onlyYardage = key.hole == lastDisplayed.hole && key.scores == lastDisplayed.scores
            if onlyYardage, now.timeIntervalSince(lastUpdate) < Self.yardageInterval { return }
        }
        if running.isEmpty {
            do {
                let content = ActivityContent(state: LiveActivitiesAppAttributes.ContentState(appGroupId: GolfRoundSharedState.appGroupId), staleDate: nil)
                _ = try Activity.request(attributes: LiveActivitiesAppAttributes(), content: content, pushType: nil)
            } catch {
                Self.logger.error("Live Activity request failed: \(error.localizedDescription)")
                return
            }
        }
        lastDisplayed = key
        lastUpdate = now
        Task { await GolfRoundLiveActivityController.shared.pushDisplayUpdate(from: state) }
    }

    func end() {
        lastDisplayed = nil
        lastUpdate = nil
        Task.detached {
            for activity in Activity<LiveActivitiesAppAttributes>.activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }
}
