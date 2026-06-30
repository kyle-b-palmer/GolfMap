import CoreLocation
import Foundation

@MainActor
final class WatchLocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = WatchLocationManager()

    @Published private(set) var yardsToGreen: Int?
    @Published private(set) var authorizationDenied = false

    private let manager = CLLocationManager()
    private var greenLatitude = 0.0
    private var greenLongitude = 0.0
    private var freshLocationContinuation: CheckedContinuation<CLLocation?, Never>?
    private var freshLocationTimeoutTask: Task<Void, Never>?

    private override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 1
    }

    func updateGreenTarget(latitude: Double, longitude: Double) {
        greenLatitude = latitude
        greenLongitude = longitude
        if let location = manager.location {
            yardsToGreen = yardsBetween(location.coordinate, latitude, longitude)
        }
    }

    func startUpdates() {
        let status = manager.authorizationStatus
        if status == .denied || status == .restricted {
            authorizationDenied = true
            return
        }
        authorizationDenied = false
        if status == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
        manager.startUpdatingLocation()
    }

    func stopUpdates() {
        manager.stopUpdatingLocation()
        cancelFreshLocationRequest(returning: nil)
    }

    /// Requests a new GPS fix instead of returning a stale coordinate.
    func requestFreshLocation(timeoutSeconds: TimeInterval = 8) async -> CLLocation? {
        let status = manager.authorizationStatus
        if status == .denied || status == .restricted {
            return manager.location
        }
        if status == .notDetermined {
            manager.requestWhenInUseAuthorization()
            try? await Task.sleep(nanoseconds: 400_000_000)
        }

        if let cached = manager.location,
           abs(cached.timestamp.timeIntervalSinceNow) < 8,
           cached.horizontalAccuracy >= 0,
           cached.horizontalAccuracy <= 40 {
            return cached
        }

        cancelFreshLocationRequest(returning: nil)

        return await withCheckedContinuation { continuation in
            freshLocationContinuation = continuation
            manager.requestLocation()

            freshLocationTimeoutTask?.cancel()
            freshLocationTimeoutTask = Task {
                try? await Task.sleep(
                    nanoseconds: UInt64(timeoutSeconds * 1_000_000_000)
                )
                await MainActor.run {
                    if let cached = self.manager.location,
                       cached.horizontalAccuracy >= 0 {
                        self.cancelFreshLocationRequest(returning: cached)
                    } else {
                        self.cancelFreshLocationRequest(returning: nil)
                    }
                }
            }
        }
    }

    private func cancelFreshLocationRequest(returning location: CLLocation?) {
        freshLocationTimeoutTask?.cancel()
        freshLocationTimeoutTask = nil
        guard let continuation = freshLocationContinuation else { return }
        freshLocationContinuation = nil
        continuation.resume(returning: location)
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            let status = manager.authorizationStatus
            authorizationDenied = status == .denied || status == .restricted
            if status == .authorizedWhenInUse || status == .authorizedAlways {
                manager.startUpdatingLocation()
            }
        }
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            if freshLocationContinuation != nil {
                cancelFreshLocationRequest(returning: location)
            }

            guard greenLatitude != 0, greenLongitude != 0 else { return }
            let yards = yardsBetween(
                location.coordinate,
                greenLatitude,
                greenLongitude
            )
            yardsToGreen = yards
            GolfRoundWatchStore.shared.updateWatchYardage(yards)
        }
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didFailWithError error: Error
    ) {
        Task { @MainActor in
            if freshLocationContinuation != nil {
                cancelFreshLocationRequest(returning: manager.location)
            }
        }
    }
}

private func yardsBetween(
    _ from: CLLocationCoordinate2D,
    _ toLatitude: Double,
    _ toLongitude: Double
) -> Int {
    let start = CLLocation(latitude: from.latitude, longitude: from.longitude)
    let end = CLLocation(latitude: toLatitude, longitude: toLongitude)
    return Int((start.distance(from: end) * 1.09361).rounded())
}

private func yardsBetween(
    _ from: CLLocationCoordinate2D,
    _ to: CLLocationCoordinate2D
) -> Int {
    yardsBetween(from, to.latitude, to.longitude)
}
