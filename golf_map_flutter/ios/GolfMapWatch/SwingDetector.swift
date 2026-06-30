import CoreMotion
import Foundation

/// Detects full-swing motion on the wrist (driver / long irons).
/// Uses a short rolling peak window so accel and rotation peaks do not need
/// to line up on the same 50 Hz sample. 25-yard dedup is handled after GPS.
@MainActor
final class SwingDetector {
    static let shared = SwingDetector()

    private let motionManager = CMMotionManager()

    /// Peak user-acceleration (g) within the swing window.
    private let peakAccelerationThreshold = 3.0
    /// Peak rotation rate (rad/s) within the swing window.
    private let peakRotationThreshold = 5.5
    /// Look back this long for separate accel/rotation peaks in one swing.
    private let swingWindowSeconds = 0.5
    /// Ignore re-triggers while the wrist is still moving through one swing.
    private var swingCooldownSeconds: TimeInterval = 4.0
    /// Device-motion sample rate.
    private let sampleInterval = 1.0 / 50.0

    private struct MotionPeak {
        let accel: Double
        let rotation: Double
        let date: Date
    }

    private var isRunning = false
    private var aboveThreshold = false
    private var lastTriggerDate: Date?
    private var recentPeaks: [MotionPeak] = []
    private var onSwingDetected: (() -> Void)?

    private init() {}

    func start(onSwingDetected: @escaping () -> Void) {
        guard !isRunning else {
            self.onSwingDetected = onSwingDetected
            return
        }
        guard motionManager.isDeviceMotionAvailable else { return }

        self.onSwingDetected = onSwingDetected
        isRunning = true
        aboveThreshold = false
        recentPeaks.removeAll()
        motionManager.deviceMotionUpdateInterval = sampleInterval
        motionManager.startDeviceMotionUpdates(
            using: .xArbitraryZVertical,
            to: .main
        ) { [weak self] motion, _ in
            guard let self, let motion else { return }
            self.evaluate(motion)
        }
    }

    func stop() {
        guard isRunning else { return }
        motionManager.stopDeviceMotionUpdates()
        isRunning = false
        aboveThreshold = false
        recentPeaks.removeAll()
        onSwingDetected = nil
    }

    private func evaluate(_ motion: CMDeviceMotion) {
        let acceleration = motion.userAcceleration
        let accelMagnitude = sqrt(
            acceleration.x * acceleration.x +
                acceleration.y * acceleration.y +
                acceleration.z * acceleration.z
        )

        let rotation = motion.rotationRate
        let rotationMagnitude = sqrt(
            rotation.x * rotation.x +
                rotation.y * rotation.y +
                rotation.z * rotation.z
        )

        let now = Date()
        recentPeaks.append(
            MotionPeak(
                accel: accelMagnitude,
                rotation: rotationMagnitude,
                date: now
            )
        )
        recentPeaks.removeAll {
            now.timeIntervalSince($0.date) > swingWindowSeconds
        }

        let peakAccel = recentPeaks.map(\.accel).max() ?? 0
        let peakRotation = recentPeaks.map(\.rotation).max() ?? 0
        let isStrongSwing =
            peakAccel >= peakAccelerationThreshold &&
            peakRotation >= peakRotationThreshold

        if isStrongSwing {
            if !aboveThreshold, canTriggerNow() {
                aboveThreshold = true
                lastTriggerDate = now
                recentPeaks.removeAll()
                onSwingDetected?()
            }
            return
        }

        if peakAccel < peakAccelerationThreshold * 0.4 &&
            peakRotation < peakRotationThreshold * 0.4 {
            aboveThreshold = false
        }
    }

    private func canTriggerNow() -> Bool {
        guard let lastTriggerDate else { return true }
        return Date().timeIntervalSince(lastTriggerDate) >= swingCooldownSeconds
    }

    /// Called after a swing is accepted so practice swings at the same spot are ignored.
    func noteAcceptedSwing(cooldownSeconds: TimeInterval = 10) {
        lastTriggerDate = Date()
        aboveThreshold = true
        swingCooldownSeconds = cooldownSeconds
        recentPeaks.removeAll()
    }

    /// Brief cooldown after a rejected swing (GPS miss / dedup) to avoid spam.
    func noteRejectedSwing(cooldownSeconds: TimeInterval = 2) {
        lastTriggerDate = Date()
        aboveThreshold = true
        swingCooldownSeconds = max(swingCooldownSeconds, cooldownSeconds)
        recentPeaks.removeAll()
    }
}
