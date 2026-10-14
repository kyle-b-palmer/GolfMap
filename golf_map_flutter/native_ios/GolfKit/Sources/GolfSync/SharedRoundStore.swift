import Foundation

/// App Group storage for the shared round snapshot, used by the phone app and the Live Activity extension.
///
/// Writers in different processes serialize read-modify-write cycles with a coordinated lock file,
/// then post a Darwin notification so other processes re-read instead of polling.
public final class SharedRoundStore: @unchecked Sendable {
    public static let shared = SharedRoundStore()

    private let defaults: UserDefaults?
    private let storageKey: String
    private let lockURL: URL?
    private let notificationName: String

    public init(
        suiteName: String = GolfRoundSharedState.appGroupId,
        storageKey: String = GolfRoundSharedState.phoneStorageKey,
        notificationName: String = GolfRoundSharedState.changedNotification
    ) {
        defaults = UserDefaults(suiteName: suiteName)
        self.storageKey = storageKey
        self.notificationName = notificationName
        lockURL = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: suiteName)?
            .appendingPathComponent("round-state.lock")
    }

    public func load() -> GolfRoundSharedState? {
        guard let data = defaults?.data(forKey: storageKey) else { return nil }
        return try? JSONDecoder().decode(GolfRoundSharedState.self, from: data)
    }

    /// Atomically reads, transforms, and writes the snapshot. Returning nil from `transform` skips the write.
    @discardableResult
    public func update(_ transform: (GolfRoundSharedState?) -> GolfRoundSharedState?) -> GolfRoundSharedState? {
        var result: GolfRoundSharedState?
        withWriteLock {
            guard let next = transform(load()) else { return }
            write(next)
            result = next
        }
        if result != nil { DarwinNotification.post(notificationName) }
        return result
    }

    public func save(_ state: GolfRoundSharedState) {
        update { _ in state }
    }

    public func clear() {
        withWriteLock {
            defaults?.removeObject(forKey: storageKey)
            defaults?.set(false, forKey: GolfRoundSharedState.hostActiveKey)
        }
        DarwinNotification.post(notificationName)
    }

    public var activeSessionId: String {
        get { defaults?.string(forKey: GolfRoundSharedState.activeSessionIdKey) ?? "" }
        set { defaults?.set(newValue, forKey: GolfRoundSharedState.activeSessionIdKey) }
    }

    public var isRoundHostActive: Bool {
        get { defaults?.bool(forKey: GolfRoundSharedState.hostActiveKey) ?? false }
        set { defaults?.set(newValue, forKey: GolfRoundSharedState.hostActiveKey) }
    }

    /// Per-activity display values read by the Live Activity views.
    public func setActivityValue(_ value: Any, key: String, activityId: String) {
        defaults?.set(value, forKey: "\(activityId)_\(key)")
    }

    public func activityValue(key: String, activityId: String) -> Any? {
        defaults?.object(forKey: "\(activityId)_\(key)")
    }

    private func write(_ state: GolfRoundSharedState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        defaults?.set(data, forKey: storageKey)
        defaults?.set(true, forKey: GolfRoundSharedState.hostActiveKey)
    }

    private func withWriteLock(_ body: () -> Void) {
        guard let lockURL else {
            body()
            return
        }
        if !FileManager.default.fileExists(atPath: lockURL.path) {
            FileManager.default.createFile(atPath: lockURL.path, contents: Data())
        }
        var coordinationError: NSError?
        var ran = false
        NSFileCoordinator(filePresenter: nil).coordinate(writingItemAt: lockURL, options: [], error: &coordinationError) { _ in
            ran = true
            body()
        }
        if !ran { body() }
    }
}

/// Cross-process change signal (carries no payload).
public enum DarwinNotification {
    public static func post(_ name: String) {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(name as CFString),
            nil,
            nil,
            true
        )
    }
}

/// Calls `handler` on the main queue whenever the named Darwin notification is posted.
public final class DarwinNotificationObserver: @unchecked Sendable {
    private let name: String
    private let handler: @Sendable () -> Void

    public init(name: String, handler: @escaping @Sendable () -> Void) {
        self.name = name
        self.handler = handler
        let observer = Unmanaged.passUnretained(self).toOpaque()
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            observer,
            { _, observer, _, _, _ in
                guard let observer else { return }
                let instance = Unmanaged<DarwinNotificationObserver>.fromOpaque(observer).takeUnretainedValue()
                DispatchQueue.main.async { instance.handler() }
            },
            name as CFString,
            nil,
            .deliverImmediately
        )
    }

    deinit {
        CFNotificationCenterRemoveObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque(),
            CFNotificationName(name as CFString),
            nil
        )
    }
}
