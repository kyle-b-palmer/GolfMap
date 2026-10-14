/// `UserDefaults.standard` keys for native settings. Legacy Flutter values are imported into these once.
enum SettingsKey {
    static let autoAdvanceHoles = "autoAdvanceHoles"
    static let mapImagery = "mapImagery"
    static let keepScreenAwake = "keepScreenAwake"
    static let showScoreTarget = "showScoreTarget"
    static let idealLineEnabled = "idealLineEnabled"
    static let showShotDispersion = "showShotDispersion"
    static let bunkerDistancesOnMap = "bunkerDistancesOnMap"
    static let healthWorkoutMode = "healthWorkoutMode"
    static let gpsSimulationEnabled = "gpsSimulationEnabled"
    /// JSON list of `{name, carryYards}`; empty means the default bag.
    static let clubBag = "clubBag"
    static let favoriteCourses = "favoriteCourses"
    static let courseVisitCounts = "courseVisitCounts"
}
