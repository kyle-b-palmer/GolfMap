#if DEBUG
import Foundation
import GolfSync

/// UI tests launch with `-GolfMapUITesting`, and with `-GolfMapUITestReset` to start from an empty install. The reset
/// must run before any store reads storage, so `GolfMapApp` calls it before creating them.
enum UITestSupport {
    static let testingArgument = "-GolfMapUITesting"
    static let resetArgument = "-GolfMapUITestReset"

    /// A background location session makes the system relaunch the app, without arguments, after a test ends; that
    /// instance can then stand in for the next test's launch and skip its reset.
    static var allowsBackgroundLocation: Bool {
        !ProcessInfo.processInfo.arguments.contains(testingArgument)
    }

    static func resetIfRequested() {
        guard ProcessInfo.processInfo.arguments.contains(resetArgument) else { return }
        // Removing keys one at a time; `removePersistentDomain` left them readable for the rest of the launch.
        let defaults = UserDefaults.standard
        let stored = Bundle.main.bundleIdentifier.flatMap(defaults.persistentDomain(forName:)) ?? [:]
        for key in stored.keys { defaults.removeObject(forKey: key) }
        try? FileManager.default.removeItem(at: .applicationSupportDirectory)
        SharedRoundStore.shared.clear()
    }
}
#endif
