import Foundation

/// Loosely typed JSON used where legacy payloads must be decoded tolerantly.
public enum JSONValue: Sendable, Hashable, Codable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .int(let value): try container.encode(value)
        case .double(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }

    public static func parse(_ data: Data) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: data)
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }

    public subscript(key: String) -> JSONValue? {
        if case .object(let object) = self { return object[key] }
        return nil
    }

    public var objectValue: [String: JSONValue]? {
        if case .object(let object) = self { return object }
        return nil
    }

    public var arrayValue: [JSONValue]? {
        if case .array(let array) = self { return array }
        return nil
    }

    public var stringValue: String? {
        if case .string(let string) = self { return string }
        return nil
    }

    public var isNull: Bool {
        if case .null = self { return true }
        return false
    }

    /// Numeric value when the JSON value is a number (Dart `num`).
    public var numberValue: Double? {
        switch self {
        case .int(let value): return Double(value)
        case .double(let value): return value
        default: return nil
        }
    }

    /// Dart `(value as num).toInt()`: truncates toward zero.
    public var truncatedInt: Int? {
        switch self {
        case .int(let value): return value
        case .double(let value) where value.isFinite: return Int(value)
        default: return nil
        }
    }

    /// Integer from a number or a numeric string, matching `int.tryParse` fallbacks.
    public var lenientInt: Int? {
        if let value = truncatedInt { return value }
        if case .string(let string) = self { return Int(string.trimmingCharacters(in: .whitespaces)) }
        return nil
    }

    /// Dart `toString()` for scalar values.
    public var dartString: String? {
        switch self {
        case .null: return nil
        case .bool(let value): return value ? "true" : "false"
        case .int(let value): return String(value)
        case .double(let value):
            if value.isFinite, value == value.rounded(.towardZero), abs(value) < 1e21 {
                return String(format: "%.1f", value)
            }
            return String(value)
        case .string(let value): return value
        case .array, .object: return nil
        }
    }
}
