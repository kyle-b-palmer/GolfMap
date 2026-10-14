import Foundation

/// Reads and writes timestamps the way Dart's `DateTime.parse` / `toIso8601String` do.
/// Strings without an offset are local wall-clock times.
public struct DartDate: Hashable, Sendable, Codable {
    public var date: Date
    public var isUTC: Bool

    public init(date: Date, isUTC: Bool) {
        self.date = date
        self.isUTC = isUTC
    }

    private static let pattern = try! NSRegularExpression(
        pattern: #"^([+-]?\d{4,6})-?(\d\d)-?(\d\d)(?:[T ](\d\d)(?::?(\d\d)(?::?(\d\d)(?:[.,](\d+))?)?)?\s*(Z|z|[+-]\d\d(?::?\d\d)?)?)?$"#
    )

    public static func parse(_ text: String, timeZone: TimeZone = .current) -> DartDate? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        let range = NSRange(trimmed.startIndex..., in: trimmed)
        guard let match = pattern.firstMatch(in: trimmed, range: range) else { return nil }

        func group(_ index: Int) -> String? {
            let r = match.range(at: index)
            guard r.location != NSNotFound, let swiftRange = Range(r, in: trimmed) else { return nil }
            return String(trimmed[swiftRange])
        }

        guard let year = Int(group(1) ?? ""), let month = Int(group(2) ?? ""), let day = Int(group(3) ?? "") else { return nil }
        let hour = Int(group(4) ?? "0") ?? 0
        let minute = Int(group(5) ?? "0") ?? 0
        let second = Int(group(6) ?? "0") ?? 0
        var micros = 0
        if let fraction = group(7) {
            let digits = String(fraction.prefix(6)).padding(toLength: 6, withPad: "0", startingAt: 0)
            micros = Int(digits) ?? 0
            if fraction.count > 6, let next = fraction.dropFirst(6).first, let digit = Int(String(next)), digit >= 5 {
                micros += 1
            }
        }

        var calendar = Calendar(identifier: .gregorian)
        let offset = group(8)
        let isUTC = offset != nil
        if let offset, offset.uppercased() != "Z" {
            let sign = offset.hasPrefix("-") ? -1 : 1
            let digits = offset.dropFirst().replacingOccurrences(of: ":", with: "")
            let hours = Int(digits.prefix(2)) ?? 0
            let minutes = Int(digits.dropFirst(2)) ?? 0
            calendar.timeZone = TimeZone(secondsFromGMT: sign * (hours * 3600 + minutes * 60))!
        } else {
            calendar.timeZone = isUTC ? TimeZone(identifier: "UTC")! : timeZone
        }

        var components = DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second)
        components.nanosecond = 0
        guard let whole = calendar.date(from: components) else { return nil }
        return DartDate(date: whole.addingTimeInterval(Double(micros) / 1_000_000), isUTC: isUTC)
    }

    /// `DateTime.toIso8601String()`: milliseconds always, microseconds only when non-zero, `Z` for UTC.
    public func iso8601String(timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = isUTC ? TimeZone(identifier: "UTC")! : timeZone
        let totalMicros = (date.timeIntervalSince1970 * 1_000_000).rounded()
        let wholeSeconds = (totalMicros / 1_000_000).rounded(.down)
        let micros = Int(totalMicros - wholeSeconds * 1_000_000)
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: Date(timeIntervalSince1970: wholeSeconds))
        var text = String(format: "%04d-%02d-%02dT%02d:%02d:%02d.%03d", c.year!, c.month!, c.day!, c.hour!, c.minute!, c.second!, micros / 1000)
        if micros % 1000 != 0 { text += String(format: "%03d", micros % 1000) }
        if isUTC { text += "Z" }
        return text
    }

    public init(from decoder: Decoder) throws {
        let text = try decoder.singleValueContainer().decode(String.self)
        guard let parsed = DartDate.parse(text) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid date \(text)"))
        }
        self = parsed
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(iso8601String())
    }
}
