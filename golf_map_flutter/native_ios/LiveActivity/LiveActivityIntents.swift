import AppIntents
import Foundation

@available(iOS 17.0, *)
struct IncrementGolfScoreIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Increase Score"
    static let description = IntentDescription("Increase the score for the current hole.")
    static let openAppWhenRun: Bool = false
    static let isDiscoverable: Bool = false

    func perform() async throws -> some IntentResult {
        await GolfRoundLiveActivityController.shared.adjustCurrentHoleScore(by: 1)
        return .result()
    }
}

@available(iOS 17.0, *)
struct DecrementGolfScoreIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Decrease Score"
    static let description = IntentDescription("Decrease the score for the current hole.")
    static let openAppWhenRun: Bool = false
    static let isDiscoverable: Bool = false

    func perform() async throws -> some IntentResult {
        await GolfRoundLiveActivityController.shared.adjustCurrentHoleScore(by: -1)
        return .result()
    }
}

@available(iOS 17.0, *)
struct SetGolfScoreIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Set Score"
    static let description = IntentDescription("Set the score for the current hole.")
    static let openAppWhenRun: Bool = false
    static let isDiscoverable: Bool = false

    @Parameter(title: "Score")
    var score: Int

    init() {
        self.score = 0
    }

    init(score: Int) {
        self.score = score
    }

    func perform() async throws -> some IntentResult {
        await GolfRoundLiveActivityController.shared.setCurrentHoleScore(to: score)
        return .result()
    }
}

@available(iOS 17.0, *)
struct PinGolfShotIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Pin Shot"
    static let description = IntentDescription("Pin your current GPS location on the hole map.")
    static let openAppWhenRun: Bool = false
    static let isDiscoverable: Bool = false

    func perform() async throws -> some IntentResult {
        await GolfRoundLiveActivityController.shared.pinCurrentLocationShot()
        return .result()
    }
}

@available(iOS 17.0, *)
struct RefreshGpsYardageIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Refresh GPS Yardage"
    static let description = IntentDescription("Refresh yards to green using current GPS.")
    static let openAppWhenRun: Bool = false
    static let isDiscoverable: Bool = false

    func perform() async throws -> some IntentResult {
        await GolfRoundLiveActivityController.shared.refreshGpsYardage()
        return .result()
    }
}

@available(iOS 17.0, *)
struct NextGolfHoleIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Next Hole"
    static let description = IntentDescription("Advance to the next hole.")
    static let openAppWhenRun: Bool = false
    static let isDiscoverable: Bool = false

    func perform() async throws -> some IntentResult {
        await GolfRoundLiveActivityController.shared.advanceToNextHole()
        return .result()
    }
}

@available(iOS 17.0, *)
struct PreviousGolfHoleIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Previous Hole"
    static let description = IntentDescription("Go back to the previous hole.")
    static let openAppWhenRun: Bool = false
    static let isDiscoverable: Bool = false

    func perform() async throws -> some IntentResult {
        await GolfRoundLiveActivityController.shared.retreatToPreviousHole()
        return .result()
    }
}
