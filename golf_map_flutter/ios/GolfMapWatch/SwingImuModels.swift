import Foundation

/// Plotter-compatible IMU sample (device-motion axes, Watch device frame).
struct GolfMotionSample: Codable, Equatable {
    var id: UUID
    var sessionID: UUID
    var sequence: Int
    var relativeTime: Double
    var timestamp: Date
    var hardwareTimestamp: Double

    var motionSource: String?
    var accelerationSource: String?
    var gyroSource: String?

    var accelX: Double?
    var accelY: Double?
    var accelZ: Double?

    var gyroX: Double?
    var gyroY: Double?
    var gyroZ: Double?

    var userAccelX: Double?
    var userAccelY: Double?
    var userAccelZ: Double?

    var gravityX: Double?
    var gravityY: Double?
    var gravityZ: Double?

    var dmRotationX: Double?
    var dmRotationY: Double?
    var dmRotationZ: Double?

    var roll: Double?
    var pitch: Double?
    var yaw: Double?

    var quaternionX: Double?
    var quaternionY: Double?
    var quaternionZ: Double?
    var quaternionW: Double?
}

/// One contact-swing IMU capture, aligned with AppleWatchPlotter SwingSession fields we need.
struct GolfSwingImuSession: Codable, Equatable {
    static let currentSchemaVersion = 8

    var id: UUID
    var schemaVersion: Int
    var date: Date
    var duration: TimeInterval
    var requestedSampleRate: Double
    var effectiveSampleRate: Double
    var sampleCount: Int
    var captureProfile: String
    var triggerSource: String
    var captureMode: String
    var estimatedImpactRelativeTime: Double?
    var peakUserAccelG: Double?
    var peakRotationRadPerSec: Double?
    var latitude: Double?
    var longitude: Double?
    var hole: String?
    var courseName: String?
    var samples: [GolfMotionSample]

    init(
        id: UUID = UUID(),
        schemaVersion: Int = GolfSwingImuSession.currentSchemaVersion,
        date: Date = Date(),
        duration: TimeInterval,
        requestedSampleRate: Double,
        effectiveSampleRate: Double,
        sampleCount: Int,
        captureProfile: String = "deviceMotion100",
        triggerSource: String = "autoContact",
        captureMode: String = "continuousRound",
        estimatedImpactRelativeTime: Double? = nil,
        peakUserAccelG: Double? = nil,
        peakRotationRadPerSec: Double? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil,
        hole: String? = nil,
        courseName: String? = nil,
        samples: [GolfMotionSample]
    ) {
        self.id = id
        self.schemaVersion = schemaVersion
        self.date = date
        self.duration = duration
        self.requestedSampleRate = requestedSampleRate
        self.effectiveSampleRate = effectiveSampleRate
        self.sampleCount = sampleCount
        self.captureProfile = captureProfile
        self.triggerSource = triggerSource
        self.captureMode = captureMode
        self.estimatedImpactRelativeTime = estimatedImpactRelativeTime
        self.peakUserAccelG = peakUserAccelG
        self.peakRotationRadPerSec = peakRotationRadPerSec
        self.latitude = latitude
        self.longitude = longitude
        self.hole = hole
        self.courseName = courseName
        self.samples = samples
    }
}

enum GolfSwingImuStore {
    static let appGroupId = "group.com.golfmapapp.golfMapFlutter"
    static let directoryName = "imu_sessions"

    static var directoryURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupId)?
            .appendingPathComponent(directoryName, isDirectory: true)
    }

    static func fileURL(for sessionId: UUID) -> URL? {
        directoryURL?.appendingPathComponent("\(sessionId.uuidString).json")
    }

    @discardableResult
    static func save(_ session: GolfSwingImuSession) -> Bool {
        guard let directory = directoryURL else { return false }
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .millisecondsSince1970
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(session)
            guard let fileURL = fileURL(for: session.id) else { return false }
            try data.write(to: fileURL, options: [.atomic])
            return true
        } catch {
            return false
        }
    }

    static func load(sessionId: String) -> GolfSwingImuSession? {
        guard let uuid = UUID(uuidString: sessionId),
              let fileURL = fileURL(for: uuid),
              let data = try? Data(contentsOf: fileURL) else {
            return nil
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return try? decoder.decode(GolfSwingImuSession.self, from: data)
    }

    static func loadDictionary(sessionId: String) -> [String: Any]? {
        guard let uuid = UUID(uuidString: sessionId),
              let fileURL = fileURL(for: uuid),
              let data = try? Data(contentsOf: fileURL),
              let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any] else {
            return nil
        }
        return dictionary
    }
}
