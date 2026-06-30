import ActivityKit
import CoreLocation
import CryptoKit
import Foundation

struct GolfRoundGpsPin: Codable, Equatable {
    let hole: String
    let latitude: Double
    let longitude: Double
}

struct GolfRoundSharedState: Codable {
    var holes: [String]
    var selectedHole: String
    var scores: [String: Int]
    var putts: [String: Int]
    var pars: [String: Int]
    var handicaps: [String: Int]
    var courseName: String
    var yardsToGreen: Int
    var revision: Int
    var pendingGpsPins: [GolfRoundGpsPin]
    var pendingGpsPinUndos: [GolfRoundGpsPin]
    var greenLatitude: Double
    var greenLongitude: Double
    var gpsRefreshRevision: Int

    static let storageKey = "golf_round_shared_state"
    static let appGroupId = "group.com.golfmapapp.golfMapFlutter"
    static let activityId = "golf-round-live"

    init(
        holes: [String],
        selectedHole: String,
        scores: [String: Int],
        putts: [String: Int] = [:],
        pars: [String: Int],
        handicaps: [String: Int] = [:],
        courseName: String,
        yardsToGreen: Int,
        revision: Int,
        pendingGpsPins: [GolfRoundGpsPin] = [],
        pendingGpsPinUndos: [GolfRoundGpsPin] = [],
        greenLatitude: Double = 0,
        greenLongitude: Double = 0,
        gpsRefreshRevision: Int = 0
    ) {
        self.holes = holes
        self.selectedHole = selectedHole
        self.scores = scores
        self.putts = putts
        self.pars = pars
        self.handicaps = handicaps
        self.courseName = courseName
        self.yardsToGreen = yardsToGreen
        self.revision = revision
        self.pendingGpsPins = pendingGpsPins
        self.pendingGpsPinUndos = pendingGpsPinUndos
        self.greenLatitude = greenLatitude
        self.greenLongitude = greenLongitude
        self.gpsRefreshRevision = gpsRefreshRevision
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        holes = try container.decode([String].self, forKey: .holes)
        selectedHole = try container.decode(String.self, forKey: .selectedHole)
        scores = try container.decode([String: Int].self, forKey: .scores)
        putts = try container.decodeIfPresent([String: Int].self, forKey: .putts) ?? [:]
        pars = try container.decode([String: Int].self, forKey: .pars)
        handicaps = try container.decodeIfPresent([String: Int].self, forKey: .handicaps) ?? [:]
        courseName = try container.decode(String.self, forKey: .courseName)
        yardsToGreen = try container.decode(Int.self, forKey: .yardsToGreen)
        revision = try container.decode(Int.self, forKey: .revision)
        pendingGpsPins = try container.decodeIfPresent(
            [GolfRoundGpsPin].self,
            forKey: .pendingGpsPins
        ) ?? []
        pendingGpsPinUndos = try container.decodeIfPresent(
            [GolfRoundGpsPin].self,
            forKey: .pendingGpsPinUndos
        ) ?? []
        greenLatitude = try container.decodeIfPresent(Double.self, forKey: .greenLatitude) ?? 0
        greenLongitude = try container.decodeIfPresent(Double.self, forKey: .greenLongitude) ?? 0
        gpsRefreshRevision = try container.decodeIfPresent(Int.self, forKey: .gpsRefreshRevision) ?? 0
    }

    var isActiveRound: Bool {
        !holes.isEmpty && !courseName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

enum GolfRoundLiveActivitySupport {
    static var interactiveControlsAvailable: Bool {
        if #available(iOS 17.0, *) {
            return true
        }
        return false
    }
}

final class GolfRoundLiveActivityController {
    static let shared = GolfRoundLiveActivityController()

    private let defaults: UserDefaults?

    private init() {
        defaults = UserDefaults(suiteName: GolfRoundSharedState.appGroupId)
    }

    func loadState() -> GolfRoundSharedState? {
        guard let defaults,
              let data = defaults.data(forKey: GolfRoundSharedState.storageKey) else {
            return nil
        }
        return try? JSONDecoder().decode(GolfRoundSharedState.self, from: data)
    }

    func saveState(_ state: GolfRoundSharedState) {
        guard let defaults,
              let data = try? JSONEncoder().encode(state) else {
            return
        }
        defaults.set(data, forKey: GolfRoundSharedState.storageKey)
    }

    func clearSharedState() {
        defaults?.removeObject(forKey: GolfRoundSharedState.storageKey)
    }

    func syncFromFlutter(
        holes: [String],
        selectedHole: String,
        scores: [String: Int],
        putts: [String: Int] = [:],
        pars: [String: Int],
        handicaps: [String: Int] = [:],
        courseName: String,
        yardsToGreen: Int,
        revision: Int,
        greenLatitude: Double = 0,
        greenLongitude: Double = 0
    ) {
        let pendingGpsPins = loadState()?.pendingGpsPins ?? []
        let pendingGpsPinUndos = loadState()?.pendingGpsPinUndos ?? []
        let state = GolfRoundSharedState(
            holes: holes,
            selectedHole: selectedHole,
            scores: scores,
            putts: putts,
            pars: pars,
            handicaps: handicaps,
            courseName: courseName,
            yardsToGreen: yardsToGreen,
            revision: revision,
            pendingGpsPins: pendingGpsPins,
            pendingGpsPinUndos: pendingGpsPinUndos,
            greenLatitude: greenLatitude,
            greenLongitude: greenLongitude
        )
        saveState(state)
    }

    func updateGreenTarget(
        greenLatitude: Double,
        greenLongitude: Double
    ) {
        guard var state = loadState() else { return }
        state.greenLatitude = greenLatitude
        state.greenLongitude = greenLongitude
        saveState(state)
    }

    func clearPendingGpsPins() {
        guard var state = loadState() else { return }
        guard !state.pendingGpsPins.isEmpty || !state.pendingGpsPinUndos.isEmpty else { return }
        state.pendingGpsPins = []
        state.pendingGpsPinUndos = []
        saveState(state)
    }

    func clearPendingGpsPinUndos() {
        guard var state = loadState() else { return }
        guard !state.pendingGpsPinUndos.isEmpty else { return }
        state.pendingGpsPinUndos = []
        saveState(state)
    }

    func reportPinnedShotRemoved(
        hole: String,
        latitude: Double,
        longitude: Double,
        scores: [String: Int]
    ) {
        guard var state = loadState() else { return }

        let undo = GolfRoundGpsPin(
            hole: hole,
            latitude: latitude,
            longitude: longitude
        )

        let duplicate = state.pendingGpsPinUndos.contains {
            $0.hole == undo.hole &&
                $0.latitude == undo.latitude &&
                $0.longitude == undo.longitude
        }
        if !duplicate {
            state.pendingGpsPinUndos.append(undo)
        }

        state.scores = scores
        state.revision += 1
        saveState(state)
    }

    func consumeChanges(after revision: Int) -> GolfRoundSharedState? {
        guard let state = loadState() else { return nil }
        if state.revision > revision {
            return state
        }
        if !state.pendingGpsPins.isEmpty || !state.pendingGpsPinUndos.isEmpty {
            return state
        }
        return nil
    }

    @MainActor
    func adjustCurrentHoleScore(by delta: Int) async {
        guard var state = loadState() else { return }
        let hole = state.selectedHole
        let current = state.scores[hole] ?? 0
        let next = max(0, min(99, current + delta))
        state.scores[hole] = next
        state.revision += 1
        saveState(state)
        if #available(iOS 16.1, *) {
            await pushDisplayUpdate(from: state)
        }
    }

    @MainActor
    func setCurrentHoleScore(to score: Int) async {
        guard var state = loadState() else { return }
        let hole = state.selectedHole
        state.scores[hole] = max(0, min(99, score))
        state.revision += 1
        saveState(state)
        if #available(iOS 16.1, *) {
            await pushDisplayUpdate(from: state)
        }
    }

    @MainActor
    func advanceToNextHole() async {
        guard var state = loadState(), !state.holes.isEmpty else { return }
        let index = state.holes.firstIndex(of: state.selectedHole) ?? -1
        let nextIndex = index < 0 ? 0 : (index + 1) % state.holes.count
        state.selectedHole = state.holes[nextIndex]
        state.revision += 1
        saveState(state)
        if #available(iOS 16.1, *) {
            await pushDisplayUpdate(from: state)
        }
    }

    @MainActor
    func retreatToPreviousHole() async {
        guard var state = loadState(), !state.holes.isEmpty else { return }
        let index = state.holes.firstIndex(of: state.selectedHole) ?? 0
        let previousIndex = (index - 1 + state.holes.count) % state.holes.count
        state.selectedHole = state.holes[previousIndex]
        state.revision += 1
        saveState(state)
        if #available(iOS 16.1, *) {
            await pushDisplayUpdate(from: state)
        }
    }

    @MainActor
    func pinCurrentLocationShot() async {
        guard var state = loadState() else { return }
        guard let location = await LiveActivityLocationProvider.shared.currentLocation() else {
            return
        }

        let pin = GolfRoundGpsPin(
            hole: state.selectedHole,
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude
        )
        state.pendingGpsPins.append(pin)
        state.revision += 1
        saveState(state)
        if #available(iOS 16.1, *) {
            await pushDisplayUpdate(from: state)
        }
    }

    @MainActor
    func refreshGpsYardage() async {
        guard var state = loadState() else { return }
        guard let location = await LiveActivityLocationProvider.shared.currentLocation() else {
            return
        }

        if state.greenLatitude != 0 && state.greenLongitude != 0 {
            let green = CLLocationCoordinate2D(
                latitude: state.greenLatitude,
                longitude: state.greenLongitude
            )
            state.yardsToGreen = yardsBetween(location.coordinate, green)
            state.gpsRefreshRevision += 1
            saveState(state)
            if #available(iOS 16.1, *) {
                await pushDisplayUpdate(from: state)
            }
        }
    }

    @available(iOS 16.1, *)
    @MainActor
    func pushDisplayUpdate(from state: GolfRoundSharedState) async {
        guard let defaults else { return }

        let par = state.pars[state.selectedHole] ?? 0
        let rawScore = state.scores[state.selectedHole] ?? 0
        let holeScore = rawScore > 0 ? rawScore : -1
        let total = totalScore(for: state)
        let relative = relativeToPar(for: state)

        let payload: [String: Any] = [
            "courseName": state.courseName,
            "hole": state.selectedHole,
            "par": par,
            "holeScore": holeScore,
            "totalScore": total,
            "relativeToPar": relative,
            "yardsToGreen": state.yardsToGreen,
        ]

        let content = LiveActivitiesAppAttributes.LiveDeliveryData(
            appGroupId: GolfRoundSharedState.appGroupId
        )

        let activities = Activity<LiveActivitiesAppAttributes>.activities
        guard !activities.isEmpty else { return }

        for activity in activities {
            guard isUpdatableActivity(activity) else { continue }

            let prefix = activity.attributes.id
            for (key, value) in payload {
                defaults.set(value, forKey: "\(prefix)_\(key)")
            }

            if #available(iOS 16.2, *) {
                await activity.update(ActivityContent(state: content, staleDate: nil))
            } else {
                await activity.update(using: content)
            }
        }
    }

    @available(iOS 16.1, *)
    private func isUpdatableActivity(_ activity: Activity<LiveActivitiesAppAttributes>) -> Bool {
        switch activity.activityState {
        case .active:
            return true
        case .stale:
            if #available(iOS 16.2, *) {
                return true
            }
            return false
        default:
            return false
        }
    }

    func totalScore(for state: GolfRoundSharedState) -> Int {
        state.holes.reduce(0) { partial, hole in
            partial + (state.scores[hole] ?? 0)
        }
    }

    func relativeToPar(for state: GolfRoundSharedState) -> Int {
        state.holes.reduce(0) { partial, hole in
            let score = state.scores[hole] ?? 0
            guard score > 0 else { return partial }
            let par = state.pars[hole] ?? 0
            guard par > 0 else { return partial }
            return partial + (score - par)
        }
    }

    func liveActivityPrefixUUID() -> UUID {
        uuid5(name: GolfRoundSharedState.activityId)
    }
}

private func uuid5(
    namespace: UUID = UUID(uuidString: "6ba7b810-9dad-11d1-80b4-00c04fd430c8")!,
    name: String
) -> UUID {
    var namespaceBytes = withUnsafeBytes(of: namespace.uuid) { Data($0) }
    namespaceBytes.append(Data(name.utf8))

    let hash = Insecure.SHA1.hash(data: namespaceBytes)
    var bytes = [UInt8](hash.prefix(16))
    bytes[6] = (bytes[6] & 0x0F) | 0x50
    bytes[8] = (bytes[8] & 0x3F) | 0x80

    return UUID(
        uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        )
    )
}

private func yardsBetween(
    _ from: CLLocationCoordinate2D,
    _ to: CLLocationCoordinate2D
) -> Int {
    let start = CLLocation(latitude: from.latitude, longitude: from.longitude)
    let end = CLLocation(latitude: to.latitude, longitude: to.longitude)
    return Int((start.distance(from: end) * 1.09361).rounded())
}

func yardsBetweenPin(_ from: GolfRoundGpsPin, _ to: GolfRoundGpsPin) -> Int {
    yardsBetween(
        CLLocationCoordinate2D(latitude: from.latitude, longitude: from.longitude),
        CLLocationCoordinate2D(latitude: to.latitude, longitude: to.longitude)
    )
}

@MainActor
final class LiveActivityLocationProvider: NSObject, CLLocationManagerDelegate {
    static let shared = LiveActivityLocationProvider()

    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocation?, Never>?
    private var timeoutTask: Task<Void, Never>?

    private override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
    }

    func currentLocation(timeoutSeconds: TimeInterval = 10) async -> CLLocation? {
        let status = locationAuthorizationStatus()
        if status == .denied || status == .restricted {
            return manager.location
        }

        if status == .notDetermined {
            manager.requestWhenInUseAuthorization()
            try? await Task.sleep(nanoseconds: 400_000_000)
        }

        if let cached = manager.location,
           abs(cached.timestamp.timeIntervalSinceNow) < 20 {
            return cached
        }

        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            manager.requestLocation()

            timeoutTask?.cancel()
            timeoutTask = Task {
                try? await Task.sleep(nanoseconds: UInt64(timeoutSeconds * 1_000_000_000))
                await self.finish(with: self.manager.location)
            }
        }
    }

    private func finish(with location: CLLocation?) {
        timeoutTask?.cancel()
        timeoutTask = nil
        continuation?.resume(returning: location)
        continuation = nil
    }

    private func locationAuthorizationStatus() -> CLAuthorizationStatus {
        if #available(iOS 14.0, *) {
            return manager.authorizationStatus
        }
        return CLLocationManager.authorizationStatus()
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        Task { @MainActor in
            finish(with: locations.last)
        }
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didFailWithError error: Error
    ) {
        Task { @MainActor in
            finish(with: manager.location)
        }
    }
}
