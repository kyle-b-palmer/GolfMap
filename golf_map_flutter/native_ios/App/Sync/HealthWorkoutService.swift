import Foundation
import HealthKit
import os

/// Records a round as an Apple Health golf workout, as Flutter's `HealthWorkoutBridge` did.
@MainActor
final class HealthWorkoutService {
    static let shared = HealthWorkoutService()

    private let store = HKHealthStore()
    private var builder: HKWorkoutBuilder?
    private static let logger = Logger(subsystem: "com.golfmapapp.golfMapFlutter", category: "health")

    /// Round sessions that already started or declined a workout, so resuming doesn't ask again.
    private static let handledSessionsKey = "healthWorkout.handledSessions"

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }
    var isRunning: Bool { builder != nil }

    func hasHandled(session: String) -> Bool {
        (UserDefaults.standard.stringArray(forKey: Self.handledSessionsKey) ?? []).contains(session)
    }

    func markHandled(session: String) {
        var handled = UserDefaults.standard.stringArray(forKey: Self.handledSessionsKey) ?? []
        guard !handled.contains(session) else { return }
        handled.append(session)
        UserDefaults.standard.set(Array(handled.suffix(20)), forKey: Self.handledSessionsKey)
    }

    /// Returns false when Health is unavailable, permission was refused, or collection couldn't begin.
    @discardableResult
    func start() async -> Bool {
        guard isAvailable, builder == nil else { return isRunning }
        do {
            try await store.requestAuthorization(toShare: [HKObjectType.workoutType()], read: [HKObjectType.workoutType()])
        } catch {
            Self.logger.error("Health authorization failed: \(error.localizedDescription)")
            return false
        }
        guard store.authorizationStatus(for: HKObjectType.workoutType()) == .sharingAuthorized else { return false }

        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .golf
        configuration.locationType = .outdoor
        let builder = HKWorkoutBuilder(healthStore: store, configuration: configuration, device: .local())
        do {
            try await builder.beginCollection(at: .now)
            self.builder = builder
            return true
        } catch {
            Self.logger.error("Workout didn't start: \(error.localizedDescription)")
            return false
        }
    }

    func end() async {
        guard let builder else { return }
        self.builder = nil
        do {
            try await builder.endCollection(at: .now)
            try await builder.finishWorkout()
        } catch {
            Self.logger.error("Workout didn't save: \(error.localizedDescription)")
        }
    }
}
