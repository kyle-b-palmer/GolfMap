import CoreLocation
import GolfCore
import GolfDesign
import Observation

/// Live location for yardage. Holds a background activity session while a round is active
/// so yardage and Live Activity updates continue with the screen locked.
@Observable
@MainActor
final class LocationService {
    private(set) var location: CLLocation?
    private(set) var status: GPSStatus = .searching

    /// Developer setting: when set, replaces the real fix everywhere.
    var simulatedCoordinate: Coordinate? {
        didSet { refreshStatus() }
    }

    var coordinate: Coordinate? {
        if let simulatedCoordinate { return simulatedCoordinate }
        guard status.allowsYardage, let location else { return nil }
        return Coordinate(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
    }

    private var authorized = true
    private var precise = true
    /// Core Location stops sending fixes while the device isn't moving; the last one stays current until it moves.
    private var stationary = false
    private var updatesTask: Task<Void, Never>?
    private var stalenessTask: Task<Void, Never>?
    private var serviceSession: CLServiceSession?
    private var backgroundSession: CLBackgroundActivitySession?

    func start(inRound: Bool) {
        if serviceSession == nil {
            serviceSession = CLServiceSession(authorization: .whenInUse, fullAccuracyPurposeKey: "PreciseYardage")
        }
        if inRound, backgroundSession == nil, Self.allowsBackgroundSession {
            backgroundSession = CLBackgroundActivitySession()
        }
        guard updatesTask == nil else { return }

        updatesTask = Task { [weak self] in
            do {
                for try await update in CLLocationUpdate.liveUpdates(.fitness) {
                    guard let self else { return }
                    self.handle(update)
                }
            } catch {
                self?.refreshStatus()
            }
        }
        stalenessTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                self?.refreshStatus()
            }
        }
    }

    private static var allowsBackgroundSession: Bool {
        #if DEBUG
        UITestSupport.allowsBackgroundLocation
        #else
        true
        #endif
    }

    func endRound() {
        backgroundSession?.invalidate()
        backgroundSession = nil
    }

    func stop() {
        endRound()
        updatesTask?.cancel()
        stalenessTask?.cancel()
        updatesTask = nil
        stalenessTask = nil
        serviceSession?.invalidate()
        serviceSession = nil
    }

    private func handle(_ update: CLLocationUpdate) {
        authorized = !(update.authorizationDenied || update.authorizationDeniedGlobally)
        precise = !update.accuracyLimited
        stationary = update.stationary
        if let fix = update.location, fix.horizontalAccuracy >= 0 {
            location = fix
        }
        refreshStatus()
    }

    private func refreshStatus() {
        let next = GPSStatus.classify(
            accuracyMeters: location?.horizontalAccuracy,
            ageSeconds: stationary ? 0 : location.map { -$0.timestamp.timeIntervalSinceNow } ?? 0,
            authorized: authorized,
            precise: precise,
            simulated: simulatedCoordinate != nil
        )
        if next != status { status = next }
    }
}
