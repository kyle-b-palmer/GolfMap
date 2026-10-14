import SwiftUI

/// Primary dock readout: large middle distance with front and back beside it.
public struct YardageReadout: View {
    let middle: Int?
    let front: Int?
    let back: Int?
    let gps: GPSStatus

    @ScaledMetric(relativeTo: .largeTitle) private var middleSize = GolfType.yardageBaseSize

    public init(middle: Int?, front: Int?, back: Int?, gps: GPSStatus) {
        self.middle = middle
        self.front = front
        self.back = back
        self.gps = gps
    }

    /// Without a usable fix there is nothing to read, so the readout says so instead of showing placeholders.
    private var shownMiddle: Int? { gps.allowsYardage ? middle : nil }

    public var body: some View {
        Group {
            if let shownMiddle {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .center, spacing: GolfSpacing.l) {
                        middleText(shownMiddle)
                        frontBack(axis: .vertical)
                        Spacer(minLength: 0)
                        GPSStatusBadge(gps)
                    }
                    VStack(alignment: .leading, spacing: GolfSpacing.xs) {
                        HStack {
                            middleText(shownMiddle)
                            Spacer(minLength: 0)
                            GPSStatusBadge(gps)
                        }
                        frontBack(axis: .horizontal)
                    }
                }
            } else {
                HStack(spacing: GolfSpacing.s) {
                    Text("No yardage")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.golfSecondaryText)
                    Spacer(minLength: 0)
                    GPSStatusBadge(gps)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private func middleText(_ yards: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("\(yards)")
                .font(GolfType.yardage(size: middleSize))
                .foregroundStyle(.golfPrimaryText)
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text("yd to center")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.golfSecondaryText)
        }
    }

    @ViewBuilder
    private func frontBack(axis: Axis) -> some View {
        let layout = axis == .vertical
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: GolfSpacing.xxs))
            : AnyLayout(HStackLayout(spacing: GolfSpacing.m))
        layout {
            if let front { labeled("Front", front) }
            if let back { labeled("Back", back) }
        }
    }

    private func labeled(_ label: String, _ yards: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: GolfSpacing.xs) {
            Text(label).font(.subheadline.weight(.semibold)).foregroundStyle(.golfSecondaryText)
            Text("\(yards)").font(GolfType.secondaryNumber).foregroundStyle(.golfPrimaryText)
        }
    }

    private var accessibilityText: String {
        guard gps.allowsYardage, let middle else { return "Yardage unavailable. \(gps.accessibilityDescription)" }
        var parts = ["\(middle) yards to the middle of the green"]
        if let front { parts.append("front \(front)") }
        if let back { parts.append("back \(back)") }
        if case .weak = gps { parts.append(gps.accessibilityDescription) }
        if case .simulated = gps { parts.append("simulated location") }
        return parts.joined(separator: ", ")
    }
}

/// "Plays 154 · 7 Iron (or 6 Iron)" line under the readout.
public struct ClubSuggestionLine: View {
    let playsLike: Int?
    let club: String?
    let alternate: String?

    public init(playsLike: Int?, club: String?, alternate: String?) {
        self.playsLike = playsLike
        self.club = club
        self.alternate = alternate
    }

    public var body: some View {
        if playsLike != nil || club != nil {
            HStack(spacing: GolfSpacing.xs) {
                if let playsLike {
                    Text("Plays \(playsLike)").monospacedDigit()
                }
                if playsLike != nil, club != nil {
                    Text("·").accessibilityHidden(true)
                }
                if let club {
                    Text(club).foregroundStyle(.golfBrand)
                    if let alternate {
                        Text("(or \(alternate))").foregroundStyle(.golfSecondaryText)
                    }
                }
            }
            .font(.callout.weight(.semibold))
            .foregroundStyle(.golfPrimaryText)
            .accessibilityElement(children: .combine)
        }
    }
}

/// Labeled − value + control with 44 pt targets, VoiceOver adjustable action, and haptics.
public struct ScoreStepper: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    let detail: String?
    let isEnabled: Bool

    @ScaledMetric(relativeTo: .title) private var valueSize = GolfType.scoreBaseSize

    public init(_ title: String, value: Binding<Int>, in range: ClosedRange<Int>, detail: String? = nil, isEnabled: Bool = true) {
        self.title = title
        _value = value
        self.range = range
        self.detail = detail
        self.isEnabled = isEnabled
    }

    public var body: some View {
        VStack(spacing: GolfSpacing.xxs) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.golfSecondaryText)
            HStack(spacing: GolfSpacing.xs) {
                stepButton("minus", label: "Decrease \(title.lowercased())", delta: -1)
                Text("\(value)")
                    .font(GolfType.score(size: valueSize))
                    .foregroundStyle(.golfPrimaryText)
                    .contentTransition(.numericText(value: Double(value)))
                    .frame(minWidth: valueSize * 1.2)
                stepButton("plus", label: "Increase \(title.lowercased())", delta: 1)
            }
            if let detail {
                Text(detail)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.golfSecondaryText)
            }
        }
        .sensoryFeedback(.selection, trigger: value)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(detail.map { "\(value), \($0)" } ?? "\(value)")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: step(1)
            case .decrement: step(-1)
            @unknown default: break
            }
        }
        .disabled(!isEnabled)
    }

    private func step(_ delta: Int) {
        guard isEnabled else { return }
        value = min(max(value + delta, range.lowerBound), range.upperBound)
    }

    private func stepButton(_ symbol: String, label: String, delta: Int) -> some View {
        Button {
            step(delta)
        } label: {
            Image(systemName: symbol)
                .font(.title3.weight(.bold))
                .frame(width: GolfMetrics.minimumHitTarget, height: GolfMetrics.minimumHitTarget)
                .background(.golfElevatedSurface, in: Circle())
                .overlay(Circle().strokeBorder(.golfSeparator))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.golfPrimaryText)
        .disabled(!range.contains(value + delta))
        .accessibilityLabel(label)
    }
}

/// Full-width filled button for the dock's main action (Mark Shot).
public struct GolfPrimaryButtonStyle: ButtonStyle {
    let tint: ColorToken
    @Environment(\.isEnabled) private var isEnabled

    public init(tint: ColorToken = GolfPalette.brand) {
        self.tint = tint
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: GolfMetrics.minimumHitTarget + 6)
            .foregroundStyle(.golfOnBrand)
            .background(tint.color.opacity(isEnabled ? 1 : 0.4), in: RoundedRectangle(cornerRadius: GolfRadius.medium, style: .continuous))
            .opacity(configuration.isPressed ? 0.8 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

public extension ButtonStyle where Self == GolfPrimaryButtonStyle {
    static var golfPrimary: GolfPrimaryButtonStyle { GolfPrimaryButtonStyle() }
}

/// Round floating map control (recenter, layers). Always labeled for VoiceOver.
public struct MapControlButton: View {
    let systemImage: String
    let label: String
    let isActive: Bool
    let action: () -> Void

    public init(_ label: String, systemImage: String, isActive: Bool = false, action: @escaping () -> Void) {
        self.label = label
        self.systemImage = systemImage
        self.isActive = isActive
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            MapControlLabel(systemImage: systemImage, isActive: isActive)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }
}

/// The round map-button look, for menus as well as buttons.
public struct MapControlLabel: View {
    let systemImage: String
    let isActive: Bool

    public init(systemImage: String, isActive: Bool = false) {
        self.systemImage = systemImage
        self.isActive = isActive
    }

    public var body: some View {
        Image(systemName: systemImage)
            .font(.body.weight(.semibold))
            .symbolVariant(isActive ? .fill : .none)
            .frame(width: GolfMetrics.minimumHitTarget, height: GolfMetrics.minimumHitTarget)
            .foregroundStyle(isActive ? .golfBrand : .golfPrimaryText)
            .background(.thickMaterial, in: Circle())
            .overlay(Circle().strokeBorder(isActive ? .golfBrand : .golfSeparator, lineWidth: isActive ? 2 : 1))
    }
}

/// Replaces the dock's action row while a pin or chain node is selected.
public struct SelectionBar: View {
    let title: String
    let detail: String?
    let onDelete: () -> Void
    let onDone: () -> Void

    public init(title: String, detail: String? = nil, onDelete: @escaping () -> Void, onDone: @escaping () -> Void) {
        self.title = title
        self.detail = detail
        self.onDelete = onDelete
        self.onDone = onDone
    }

    public var body: some View {
        HStack(spacing: GolfSpacing.s) {
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(.headline).foregroundStyle(.golfPrimaryText)
                if let detail {
                    Text(detail).font(.subheadline).monospacedDigit().foregroundStyle(.golfSecondaryText)
                }
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 0)
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
                    .frame(minHeight: GolfMetrics.minimumHitTarget)
            }
            .foregroundStyle(.golfDestructive)
            Button("Done", action: onDone)
                .font(.headline)
                .frame(minHeight: GolfMetrics.minimumHitTarget)
                .foregroundStyle(.golfBrand)
        }
        .padding(.horizontal, GolfSpacing.m)
        .padding(.vertical, GolfSpacing.xs)
        .background(.golfElevatedSurface, in: RoundedRectangle(cornerRadius: GolfRadius.medium, style: .continuous))
        .sensoryFeedback(.selection, trigger: title)
    }
}

/// Mode banner for tap-to-place interactions (aim point, simulated GPS).
public struct PlacementBanner: View {
    let message: String
    let systemImage: String
    let onCancel: () -> Void

    public init(_ message: String, systemImage: String = "hand.tap", onCancel: @escaping () -> Void) {
        self.message = message
        self.systemImage = systemImage
        self.onCancel = onCancel
    }

    public var body: some View {
        HStack(spacing: GolfSpacing.s) {
            Image(systemName: systemImage)
                .font(.headline)
                .foregroundStyle(.golfMeasure)
                .accessibilityHidden(true)
            Text(message)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.golfPrimaryText)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button("Cancel", action: onCancel)
                .font(.subheadline.weight(.semibold))
                .frame(minHeight: GolfMetrics.minimumHitTarget)
                .foregroundStyle(.golfMeasure)
        }
        .padding(.horizontal, GolfSpacing.m)
        .background(.thickMaterial, in: RoundedRectangle(cornerRadius: GolfRadius.medium, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: GolfRadius.medium, style: .continuous).strokeBorder(.golfMeasure, lineWidth: 1.5))
        .accessibilityElement(children: .contain)
    }
}

private struct DockPreview: View {
    @State private var score = 4
    @State private var putts = 2
    let gps: GPSStatus

    var body: some View {
        VStack(alignment: .leading, spacing: GolfSpacing.s) {
            YardageReadout(middle: 148, front: 139, back: 157, gps: gps)
            ClubSuggestionLine(playsLike: 154, club: "7 Iron", alternate: "6 Iron")
            HStack {
                ScoreStepper("Score", value: $score, in: 0...99, detail: "+1")
                Spacer()
                ScoreStepper("Putts", value: $putts, in: 0...9)
            }
            Button("Mark shot") {}
                .buttonStyle(.golfPrimary)
        }
        .padding(GolfSpacing.m)
        .background(.golfSurface)
    }
}

#Preview("Dock") {
    DockPreview(gps: .live(accuracyMeters: 4))
}

#Preview("Dock, dark, accessibility size") {
    DockPreview(gps: .weak(accuracyMeters: 28))
        .preferredColorScheme(.dark)
        .dynamicTypeSize(.accessibility2)
}

#Preview("Dock, stale GPS") {
    DockPreview(gps: .stale(seconds: 24))
        .preferredColorScheme(.dark)
}

#Preview("Map controls and bars") {
    VStack(spacing: GolfSpacing.m) {
        HStack {
            MapControlButton("Recenter", systemImage: "location") {}
            MapControlButton("Layers", systemImage: "square.3.layers.3d", isActive: true) {}
        }
        SelectionBar(title: "Shot 2", detail: "164 yd", onDelete: {}, onDone: {})
        PlacementBanner("Tap the map to set an aim point") {}
    }
    .padding()
    .background(Color(.sRGB, red: 0.1, green: 0.2, blue: 0.16))
}
