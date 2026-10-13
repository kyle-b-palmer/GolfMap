import CoreMotion
import Foundation

/// Detects full golf swings and captures Plotter-compatible IMU windows on contact.
@MainActor
final class SwingDetector {
    static let shared = SwingDetector()

    private let motionManager = CMMotionManager()

    private let minPeakAcceleration = 5.5
    private let minPeakRotation = 14.0
    private let minRotationProminence = 10.0
    private let minRotationFloor = 6.0
    private let minEnvelopeDuration: TimeInterval = 0.35
    private let maxEnvelopeDuration: TimeInterval = 3.5
    private let historyDuration: TimeInterval = 5.0
    private let preImpactDuration: TimeInterval = 4.0
    private let postImpactDuration: TimeInterval = 0.75
    private let sampleInterval = 1.0 / 100.0
    private let requestedSampleRate = 100.0

    private struct BufferSample {
        let date: Date
        let hardwareTimestamp: TimeInterval
        let userAccel: CMAcceleration
        let gravity: CMAcceleration
        let rotation: CMRotationRate
        let attitude: CMAttitude

        var userAccelMagnitude: Double {
            sqrt(
                userAccel.x * userAccel.x +
                    userAccel.y * userAccel.y +
                    userAccel.z * userAccel.z
            )
        }

        var rotationMagnitude: Double {
            sqrt(
                rotation.x * rotation.x +
                    rotation.y * rotation.y +
                    rotation.z * rotation.z
            )
        }
    }

    private struct PendingCapture {
        let sessionId: UUID
        let peakDate: Date
        let peakHardwareTimestamp: TimeInterval
        let startHardwareTimestamp: TimeInterval
        var samples: [BufferSample]
        let peakUserAccelG: Double
        let peakRotation: Double
    }

    private var isRunning = false
    private var aboveThreshold = false
    private var lastTriggerDate: Date?
    private var recentSamples: [BufferSample] = []
    private var pendingCapture: PendingCapture?
    private var swingCooldownSeconds: TimeInterval = 4.0
    private var onSwingDetected: ((GolfSwingImuSession) -> Void)?

    private init() {}

    func start(onSwingDetected: @escaping (GolfSwingImuSession) -> Void) {
        guard !isRunning else {
            self.onSwingDetected = onSwingDetected
            return
        }
        guard motionManager.isDeviceMotionAvailable else { return }

        self.onSwingDetected = onSwingDetected
        isRunning = true
        aboveThreshold = false
        recentSamples.removeAll()
        pendingCapture = nil
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
        recentSamples.removeAll()
        pendingCapture = nil
        onSwingDetected = nil
    }

    private func evaluate(_ motion: CMDeviceMotion) {
        let now = Date()
        let sample = BufferSample(
            date: now,
            hardwareTimestamp: motion.timestamp,
            userAccel: motion.userAcceleration,
            gravity: motion.gravity,
            rotation: motion.rotationRate,
            attitude: motion.attitude
        )

        if var pending = pendingCapture {
            pending.samples.append(sample)
            pendingCapture = pending
            if now.timeIntervalSince(pending.peakDate) >= postImpactDuration {
                finishPendingCapture()
            }
            return
        }

        recentSamples.append(sample)
        recentSamples.removeAll {
            now.timeIntervalSince($0.date) > historyDuration
        }

        if !aboveThreshold,
           canTriggerNow(),
           let peak = validatedPeakSample(at: now) {
            aboveThreshold = true
            lastTriggerDate = now
            beginPendingCapture(peak: peak)
            return
        }

        if sample.userAccelMagnitude < minPeakAcceleration * 0.35 &&
            sample.rotationMagnitude < minPeakRotation * 0.35 {
            aboveThreshold = false
        }
    }

    private func beginPendingCapture(peak: BufferSample) {
        let sessionId = UUID()
        let windowStart = peak.date.addingTimeInterval(-preImpactDuration)
        let windowSamples = recentSamples.filter { $0.date >= windowStart }
        guard let first = windowSamples.first else { return }

        pendingCapture = PendingCapture(
            sessionId: sessionId,
            peakDate: peak.date,
            peakHardwareTimestamp: peak.hardwareTimestamp,
            startHardwareTimestamp: first.hardwareTimestamp,
            samples: windowSamples,
            peakUserAccelG: peak.userAccelMagnitude,
            peakRotation: peak.rotationMagnitude
        )
        recentSamples.removeAll()
    }

    private func finishPendingCapture() {
        guard let pending = pendingCapture else { return }
        pendingCapture = nil

        let samples = pending.samples.enumerated().map { index, sample in
            makeMotionSample(
                sample,
                sessionId: pending.sessionId,
                sequence: index + 1,
                startHardwareTimestamp: pending.startHardwareTimestamp
            )
        }

        guard samples.count >= 20 else { return }

        let duration = max(
            0.01,
            (samples.last?.relativeTime ?? 0) - (samples.first?.relativeTime ?? 0)
        )
        let effectiveRate = Double(samples.count - 1) / duration
        let impactRelative = pending.peakHardwareTimestamp - pending.startHardwareTimestamp

        let session = GolfSwingImuSession(
            id: pending.sessionId,
            duration: duration,
            requestedSampleRate: requestedSampleRate,
            effectiveSampleRate: effectiveRate,
            sampleCount: samples.count,
            estimatedImpactRelativeTime: impactRelative,
            peakUserAccelG: pending.peakUserAccelG,
            peakRotationRadPerSec: pending.peakRotation,
            samples: samples
        )
        onSwingDetected?(session)
    }

    private func makeMotionSample(
        _ sample: BufferSample,
        sessionId: UUID,
        sequence: Int,
        startHardwareTimestamp: TimeInterval
    ) -> GolfMotionSample {
        let totalAccelX = sample.userAccel.x + sample.gravity.x
        let totalAccelY = sample.userAccel.y + sample.gravity.y
        let totalAccelZ = sample.userAccel.z + sample.gravity.z
        let quaternion = sample.attitude.quaternion

        return GolfMotionSample(
            id: UUID(),
            sessionID: sessionId,
            sequence: sequence,
            relativeTime: sample.hardwareTimestamp - startHardwareTimestamp,
            timestamp: sample.date,
            hardwareTimestamp: sample.hardwareTimestamp,
            motionSource: "deviceMotion",
            accelerationSource: "deviceMotionTotal",
            gyroSource: "deviceMotion",
            accelX: totalAccelX,
            accelY: totalAccelY,
            accelZ: totalAccelZ,
            gyroX: sample.rotation.x,
            gyroY: sample.rotation.y,
            gyroZ: sample.rotation.z,
            userAccelX: sample.userAccel.x,
            userAccelY: sample.userAccel.y,
            userAccelZ: sample.userAccel.z,
            gravityX: sample.gravity.x,
            gravityY: sample.gravity.y,
            gravityZ: sample.gravity.z,
            dmRotationX: sample.rotation.x,
            dmRotationY: sample.rotation.y,
            dmRotationZ: sample.rotation.z,
            roll: sample.attitude.roll,
            pitch: sample.attitude.pitch,
            yaw: sample.attitude.yaw,
            quaternionX: quaternion.x,
            quaternionY: quaternion.y,
            quaternionZ: quaternion.z,
            quaternionW: quaternion.w
        )
    }

    private func validatedPeakSample(at now: Date) -> BufferSample? {
        guard recentSamples.count >= 20 else { return nil }

        let rotations = recentSamples.map(\.rotationMagnitude)
        guard let peakSample = recentSamples.max(by: {
            $0.rotationMagnitude < $1.rotationMagnitude
        }) else {
            return nil
        }

        guard peakSample.rotationMagnitude >= minPeakRotation else { return nil }

        let sorted = rotations.sorted()
        let median = sorted[sorted.count / 2]
        let prominence = peakSample.rotationMagnitude - median
        guard prominence >= minRotationProminence else { return nil }

        let floor = max(minRotationFloor, median + prominence * 0.25)
        let envelope = recentSamples.filter { $0.rotationMagnitude >= floor }
        guard let envelopeStart = envelope.first?.date,
              let envelopeEnd = envelope.last?.date else {
            return nil
        }

        let envelopeDuration = envelopeEnd.timeIntervalSince(envelopeStart)
        guard envelopeDuration >= minEnvelopeDuration,
              envelopeDuration <= maxEnvelopeDuration else {
            return nil
        }

        let impactWindow: TimeInterval = 0.18
        let peakAccel = recentSamples
            .filter {
                abs($0.date.timeIntervalSince(peakSample.date)) <= impactWindow
            }
            .map(\.userAccelMagnitude)
            .max() ?? 0

        guard peakAccel >= minPeakAcceleration else { return nil }
        return peakSample
    }

    private func canTriggerNow() -> Bool {
        guard let lastTriggerDate else { return true }
        return Date().timeIntervalSince(lastTriggerDate) >= swingCooldownSeconds
    }

    func noteAcceptedSwing(cooldownSeconds: TimeInterval = 12) {
        lastTriggerDate = Date()
        aboveThreshold = true
        swingCooldownSeconds = cooldownSeconds
        recentSamples.removeAll()
    }

    func noteRejectedSwing(cooldownSeconds: TimeInterval = 3) {
        lastTriggerDate = Date()
        aboveThreshold = true
        swingCooldownSeconds = max(swingCooldownSeconds, cooldownSeconds)
        recentSamples.removeAll()
        pendingCapture = nil
    }
}
