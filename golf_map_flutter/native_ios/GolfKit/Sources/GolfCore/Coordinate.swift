import Foundation

public struct Coordinate: Hashable, Codable, Sendable {
    public var latitude: Double
    public var longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }
}

/// Feature identifiers are integers in Supabase rows and strings (for example `way/-1`)
/// in OSM-derived rows. They are not unique across a course.
public enum FeatureID: Hashable, Sendable, Codable, CustomStringConvertible {
    case int(Int)
    case string(String)

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else {
            self = .string(try container.decode(String.self))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .int(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        }
    }

    init?(json: JSONValue?) {
        switch json {
        case .int(let value): self = .int(value)
        case .double(let value) where value == value.rounded(): self = .int(Int(value))
        case .string(let value): self = .string(value)
        default: return nil
        }
    }

    public var jsonValue: JSONValue {
        switch self {
        case .int(let value): return .int(value)
        case .string(let value): return .string(value)
        }
    }

    public var description: String {
        switch self {
        case .int(let value): return String(value)
        case .string(let value): return value
        }
    }
}
