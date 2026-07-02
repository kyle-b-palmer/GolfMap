import Flutter
import HealthKit

final class HealthWorkoutBridge: NSObject, FlutterPlugin {
    private static var workoutStartDate: Date?
    private static var workoutBuilderStorage: Any?

    static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "com.golfmapapp/health_workout",
            binaryMessenger: registrar.messenger()
        )
        let instance = HealthWorkoutBridge()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "isAvailable":
            result(HKHealthStore.isHealthDataAvailable())
        case "startGolfWorkout":
            startGolfWorkout(result: result)
        case "endGolfWorkout":
            endGolfWorkout(result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func startGolfWorkout(result: @escaping FlutterResult) {
        guard HKHealthStore.isHealthDataAvailable() else {
            result(false)
            return
        }

        let store = HKHealthStore()
        let typesToShare: Set<HKSampleType> = [HKObjectType.workoutType()]
        let typesToRead: Set<HKObjectType> = [HKObjectType.workoutType()]

        store.requestAuthorization(toShare: typesToShare, read: typesToRead) { success, _ in
            guard success else {
                DispatchQueue.main.async { result(false) }
                return
            }

            let startDate = Date()
            Self.workoutStartDate = startDate

            if #available(iOS 17.0, *) {
                Self.startWithBuilder(store: store, startDate: startDate, result: result)
            } else {
                DispatchQueue.main.async { result(nil) }
            }
        }
    }

    @available(iOS 17.0, *)
    private static func startWithBuilder(
        store: HKHealthStore,
        startDate: Date,
        result: @escaping FlutterResult
    ) {
        let config = HKWorkoutConfiguration()
        config.activityType = .golf
        config.locationType = .outdoor

        let builder = HKWorkoutBuilder(
            healthStore: store,
            configuration: config,
            device: .local()
        )
        builder.beginCollection(withStart: startDate) { success, _ in
            if success {
                workoutBuilderStorage = builder
                DispatchQueue.main.async { result(nil) }
            } else {
                workoutStartDate = nil
                DispatchQueue.main.async { result(false) }
            }
        }
    }

    private func endGolfWorkout(result: @escaping FlutterResult) {
        guard let startDate = Self.workoutStartDate else {
            result(nil)
            return
        }

        let endDate = Date()
        let store = HKHealthStore()

        if #available(iOS 17.0, *),
           let builder = Self.workoutBuilderStorage as? HKWorkoutBuilder {
            builder.endCollection(withEnd: endDate) { _, _ in
                builder.finishWorkout { _, _ in
                    Self.clearWorkoutState()
                    DispatchQueue.main.async { result(nil) }
                }
            }
            return
        }

        let workout = HKWorkout(
            activityType: .golf,
            start: startDate,
            end: endDate,
            workoutEvents: nil,
            totalEnergyBurned: nil,
            totalDistance: nil,
            device: HKDevice.local(),
            metadata: nil
        )
        store.save(workout) { _, _ in
            Self.clearWorkoutState()
            DispatchQueue.main.async { result(nil) }
        }
    }

    private static func clearWorkoutState() {
        workoutStartDate = nil
        workoutBuilderStorage = nil
    }
}
