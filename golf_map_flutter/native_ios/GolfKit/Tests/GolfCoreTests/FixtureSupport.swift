import Foundation
@testable import GolfCore

enum Fixtures {
    static let parity: JSONValue = {
        let url = Bundle.module.url(forResource: "parity_v1", withExtension: "json", subdirectory: "Fixtures")!
        return try! JSONValue.parse(Data(contentsOf: url))
    }()

    /// The bundled course asset still lives in the Flutter project during migration.
    static let bundledCoursesURL: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // GolfCoreTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // GolfKit
        .deletingLastPathComponent() // native_ios
        .deletingLastPathComponent() // golf_map_flutter
        .appendingPathComponent("assets/courses/san_antonio_courses.json")

    static let features: [GolfFeature] = try! FeatureRowDecoder.decode(Data(contentsOf: bundledCoursesURL))
}

extension JSONValue {
    var coordinate: Coordinate? {
        guard let array = arrayValue, array.count == 2,
              let lat = array[0].numberValue, let lng = array[1].numberValue else { return nil }
        return Coordinate(latitude: lat, longitude: lng)
    }

    var bool: Bool? {
        if case .bool(let value) = self { return value }
        return nil
    }

    /// Structural equality treating 4 and 4.0 as equal and ignoring object key order.
    func isEquivalent(to other: JSONValue) -> Bool {
        if let a = numberValue, let b = other.numberValue { return a == b }
        switch (self, other) {
        case (.null, .null): return true
        case let (.bool(a), .bool(b)): return a == b
        case let (.string(a), .string(b)): return a == b
        case let (.array(a), .array(b)):
            return a.count == b.count && zip(a, b).allSatisfy { $0.isEquivalent(to: $1) }
        case let (.object(a), .object(b)):
            return a.keys.sorted() == b.keys.sorted() && a.allSatisfy { key, value in value.isEquivalent(to: b[key]!) }
        default: return false
        }
    }
}

func close(_ a: Coordinate?, _ b: Coordinate?, tolerance: Double = 1e-9) -> Bool {
    switch (a, b) {
    case (nil, nil): return true
    case let (a?, b?): return abs(a.latitude - b.latitude) <= tolerance && abs(a.longitude - b.longitude) <= tolerance
    default: return false
    }
}
