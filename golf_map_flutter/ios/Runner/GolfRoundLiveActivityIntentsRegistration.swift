import AppIntents

/// Registers live-activity score intents with the main app so button taps run
/// the real handlers when iOS dispatches `LiveActivityIntent` in the app process.
@available(iOS 17.0, *)
enum GolfRoundLiveActivityIntentsRegistration {
    static let intents: [any AppIntent.Type] = [
        IncrementGolfScoreIntent.self,
        DecrementGolfScoreIntent.self,
        SetGolfScoreIntent.self,
        PinGolfShotIntent.self,
        RefreshGpsYardageIntent.self,
        NextGolfHoleIntent.self,
        PreviousGolfHoleIntent.self,
    ]
}
