import SwiftUI

/// Location quality as shown to the golfer. Yardage is hidden unless the fix is current and precise.
public enum GPSStatus: Hashable, Sendable {
    case searching
    case live(accuracyMeters: Double)
    case weak(accuracyMeters: Double)
    case reducedAccuracy
    case stale(seconds: Int)
    case denied
    case simulated

    public static let staleAfterSeconds: Double = 15
    public static let weakAboveMeters: Double = 20

    public static func classify(
        accuracyMeters: Double?,
        ageSeconds: Double,
        authorized: Bool,
        precise: Bool,
        simulated: Bool
    ) -> GPSStatus {
        if simulated { return .simulated }
        if !authorized { return .denied }
        if !precise { return .reducedAccuracy }
        guard let accuracyMeters, accuracyMeters >= 0 else { return .searching }
        if ageSeconds > staleAfterSeconds { return .stale(seconds: Int(ageSeconds)) }
        return accuracyMeters > weakAboveMeters ? .weak(accuracyMeters: accuracyMeters) : .live(accuracyMeters: accuracyMeters)
    }

    public var allowsYardage: Bool {
        switch self {
        case .live, .weak, .simulated: true
        case .searching, .reducedAccuracy, .stale, .denied: false
        }
    }

    public var title: String {
        switch self {
        case .searching: "Searching"
        case .live: "GPS"
        case .weak: "Weak GPS"
        case .reducedAccuracy: "Approximate"
        case .stale: "GPS lost"
        case .denied: "Location off"
        case .simulated: "Simulated"
        }
    }

    public var systemImage: String {
        switch self {
        case .searching: "location.magnifyingglass"
        case .live: "location.fill"
        case .weak: "location"
        case .reducedAccuracy: "location.circle"
        case .stale: "location.slash"
        case .denied: "location.slash.fill"
        case .simulated: "hammer.fill"
        }
    }

    public var accessibilityDescription: String {
        switch self {
        case .searching: "Searching for GPS"
        case .live(let accuracy): "GPS accurate to \(Int(accuracy.rounded())) meters"
        case .weak(let accuracy): "Weak GPS, accurate to \(Int(accuracy.rounded())) meters"
        case .reducedAccuracy: "Precise location is off. Yardages are hidden."
        case .stale(let seconds): "No GPS update for \(seconds) seconds. Yardages are hidden."
        case .denied: "Location access is off. Yardages are hidden."
        case .simulated: "Simulated location"
        }
    }

    var tint: ColorToken {
        switch self {
        case .live: GolfPalette.brand
        case .weak, .searching, .simulated: GolfPalette.hazard
        case .reducedAccuracy, .stale, .denied: GolfPalette.destructive
        }
    }
}

/// Compact GPS quality label; shape (symbol) differs per state so it does not rely on color alone.
public struct GPSStatusBadge: View {
    let status: GPSStatus

    public init(_ status: GPSStatus) {
        self.status = status
    }

    public var body: some View {
        Label(status.title, systemImage: status.systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(status.tint.color)
            .padding(.horizontal, GolfSpacing.xs)
            .padding(.vertical, GolfSpacing.xxs)
            .background(status.tint.color.opacity(0.14), in: Capsule())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(status.accessibilityDescription)
    }
}

#Preview("GPS states") {
    VStack(alignment: .leading, spacing: GolfSpacing.xs) {
        GPSStatusBadge(.live(accuracyMeters: 4))
        GPSStatusBadge(.weak(accuracyMeters: 32))
        GPSStatusBadge(.searching)
        GPSStatusBadge(.reducedAccuracy)
        GPSStatusBadge(.stale(seconds: 22))
        GPSStatusBadge(.denied)
        GPSStatusBadge(.simulated)
    }
    .padding()
}
