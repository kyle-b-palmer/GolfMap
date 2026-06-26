import AppIntents
import Foundation

@available(iOS 17.0, *)
struct IncrementGolfScoreIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Increase Score"
    static var description = IntentDescription("Increase the score for the current hole.")
    static var openAppWhenRun: Bool = false
    static var isDiscoverable: Bool = false

    func perform() async throws -> some IntentResult {
        await GolfRoundLiveActivityController.shared.adjustCurrentHoleScore(by: 1)
        return .result()
    }
}

@available(iOS 17.0, *)
struct DecrementGolfScoreIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Decrease Score"
    static var description = IntentDescription("Decrease the score for the current hole.")
    static var openAppWhenRun: Bool = false
    static var isDiscoverable: Bool = false

    func perform() async throws -> some IntentResult {
        await GolfRoundLiveActivityController.shared.adjustCurrentHoleScore(by: -1)
        return .result()
    }
}

@available(iOS 17.0, *)
struct SetGolfScoreIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Set Score"
    static var description = IntentDescription("Set the score for the current hole.")
    static var openAppWhenRun: Bool = false
    static var isDiscoverable: Bool = false

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
    static var title: LocalizedStringResource = "Pin Shot"
    static var description = IntentDescription("Pin your current GPS location on the hole map.")
    static var openAppWhenRun: Bool = false
    static var isDiscoverable: Bool = false

    func perform() async throws -> some IntentResult {
        await GolfRoundLiveActivityController.shared.pinCurrentLocationShot()
        return .result()
    }
}

@available(iOS 17.0, *)
struct RefreshGpsYardageIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Refresh GPS Yardage"
    static var description = IntentDescription("Refresh yards to green using current GPS.")
    static var openAppWhenRun: Bool = false
    static var isDiscoverable: Bool = false

    func perform() async throws -> some IntentResult {
        await GolfRoundLiveActivityController.shared.refreshGpsYardage()
        return .result()
    }
}

@available(iOS 17.0, *)
struct NextGolfHoleIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Next Hole"
    static var description = IntentDescription("Advance to the next hole.")
    static var openAppWhenRun: Bool = false
    static var isDiscoverable: Bool = false

    func perform() async throws -> some IntentResult {
        await GolfRoundLiveActivityController.shared.advanceToNextHole()
        return .result()
    }
}

@available(iOS 17.0, *)
struct PreviousGolfHoleIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Previous Hole"
    static var description = IntentDescription("Go back to the previous hole.")
    static var openAppWhenRun: Bool = false
    static var isDiscoverable: Bool = false

    func perform() async throws -> some IntentResult {
        await GolfRoundLiveActivityController.shared.retreatToPreviousHole()
        return .result()
    }
}
