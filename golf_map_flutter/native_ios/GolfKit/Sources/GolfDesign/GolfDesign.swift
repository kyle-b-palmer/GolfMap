import SwiftUI

/// sRGB color with WCAG luminance helpers.
public struct RGB: Hashable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    public init(hex: UInt32, alpha: Double = 1) {
        red = Double((hex >> 16) & 0xFF) / 255
        green = Double((hex >> 8) & 0xFF) / 255
        blue = Double(hex & 0xFF) / 255
        self.alpha = alpha
    }

    public var relativeLuminance: Double {
        func linear(_ channel: Double) -> Double {
            channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    public static func contrast(_ a: RGB, _ b: RGB) -> Double {
        let (high, low) = (max(a.relativeLuminance, b.relativeLuminance), min(a.relativeLuminance, b.relativeLuminance))
        return (high + 0.05) / (low + 0.05)
    }

    public var color: Color {
        Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }
}

/// A color with light, dark, and increased-contrast variants.
public struct ColorToken: Sendable {
    public var light: RGB
    public var dark: RGB
    public var lightHighContrast: RGB
    public var darkHighContrast: RGB

    public init(light: UInt32, dark: UInt32, lightHighContrast: UInt32? = nil, darkHighContrast: UInt32? = nil) {
        self.light = RGB(hex: light)
        self.dark = RGB(hex: dark)
        self.lightHighContrast = RGB(hex: lightHighContrast ?? light)
        self.darkHighContrast = RGB(hex: darkHighContrast ?? dark)
    }

    public func resolved(dark isDark: Bool, highContrast: Bool) -> RGB {
        switch (isDark, highContrast) {
        case (false, false): light
        case (true, false): dark
        case (false, true): lightHighContrast
        case (true, true): darkHighContrast
        }
    }

    public static let allVariants: [(dark: Bool, highContrast: Bool)] = [(false, false), (true, false), (false, true), (true, true)]

    public var color: Color {
        #if os(iOS)
        Color(uiColor: UIColor { traits in
            let rgb = resolved(dark: traits.userInterfaceStyle == .dark, highContrast: traits.accessibilityContrast == .high)
            return UIColor(red: rgb.red, green: rgb.green, blue: rgb.blue, alpha: rgb.alpha)
        })
        #elseif os(macOS)
        Color(nsColor: NSColor(name: nil) { appearance in
            let match = appearance.bestMatch(from: [.aqua, .darkAqua, .accessibilityHighContrastAqua, .accessibilityHighContrastDarkAqua])
            let isDark = match == .darkAqua || match == .accessibilityHighContrastDarkAqua
            let isHigh = match == .accessibilityHighContrastAqua || match == .accessibilityHighContrastDarkAqua
            let rgb = resolved(dark: isDark, highContrast: isHigh)
            return NSColor(srgbRed: rgb.red, green: rgb.green, blue: rgb.blue, alpha: rgb.alpha)
        })
        #else
        dark.color
        #endif
    }
}

/// Semantic color tokens. Text-bearing tokens meet 4.5:1 on both surfaces in every variant (see `GolfDesignTests`).
public enum GolfPalette {
    public static let brand = ColorToken(light: 0x15803D, dark: 0x4ADE80, lightHighContrast: 0x14532D, darkHighContrast: 0x86EFAC)
    public static let onBrand = ColorToken(light: 0xFFFFFF, dark: 0x052E16, lightHighContrast: 0xFFFFFF, darkHighContrast: 0x022C22)
    public static let measure = ColorToken(light: 0x1D4ED8, dark: 0x6BB0FF, lightHighContrast: 0x1E3A8A, darkHighContrast: 0xA5CFFF)
    public static let sand = ColorToken(light: 0x7C5A10, dark: 0xE8D48A, lightHighContrast: 0x5C420A, darkHighContrast: 0xF5E6B8)
    public static let hazard = ColorToken(light: 0xB45309, dark: 0xFBBF24, lightHighContrast: 0x7C2D12, darkHighContrast: 0xFDE68A)
    public static let destructive = ColorToken(light: 0xB91C1C, dark: 0xF87171, lightHighContrast: 0x7F1D1D, darkHighContrast: 0xFCA5A5)
    public static let surface = ColorToken(light: 0xFFFFFF, dark: 0x121218, lightHighContrast: 0xFFFFFF, darkHighContrast: 0x000000)
    public static let elevatedSurface = ColorToken(light: 0xF3F4F6, dark: 0x1C1C24, lightHighContrast: 0xF3F4F6, darkHighContrast: 0x16161C)
    public static let separator = ColorToken(light: 0xD1D5DB, dark: 0x2A2A32, lightHighContrast: 0x6B7280, darkHighContrast: 0x9CA3AF)
    public static let primaryText = ColorToken(light: 0x111827, dark: 0xF9FAFB, lightHighContrast: 0x000000, darkHighContrast: 0xFFFFFF)
    public static let secondaryText = ColorToken(light: 0x4B5563, dark: 0x9CA3AF, lightHighContrast: 0x1F2937, darkHighContrast: 0xD1D5DB)

    public static let textTokens: [(name: String, token: ColorToken)] = [
        ("brand", brand), ("measure", measure), ("sand", sand), ("hazard", hazard),
        ("destructive", destructive), ("primaryText", primaryText), ("secondaryText", secondaryText),
    ]
}

/// Course overlay colors. These sit on imagery or the offline rough background, so they do not vary by appearance.
public enum GolfMapPalette {
    public static let courseBackground = RGB(hex: 0x1A3328)
    public static let fairway = RGB(hex: 0x2CE06C)
    public static let green = RGB(hex: 0x00FF55)
    public static let bunker = RGB(hex: 0xF0E3BC)
    public static let tee = RGB(hex: 0xE8D48A)
    public static let teeBorder = RGB(hex: 0x8B7355)
    public static let water = RGB(hex: 0x38BDF8)
    public static let holeLine = RGB(hex: 0xFFFFFF)
    public static let cartPath = RGB(hex: 0xD1D5DB)
    public static let shotPin = RGB(hex: 0xFF9800)
    public static let lostBallPin = RGB(hex: 0xEF4444)
    public static let selection = RGB(hex: 0xFFD54F)
    public static let aimLine = RGB(hex: 0x0EA5E9)
    public static let measureLine = RGB(hex: 0x4A9EFF)
    public static let idealLine = RGB(hex: 0xE53935)
    public static let clubAim = RGB(hex: 0x7DD3FC)
    public static let dispersion = RGB(hex: 0x22C55E)

    /// Active and inactive fill opacity for a feature type.
    public static func fill(for featureType: String) -> (color: RGB, active: Double, inactive: Double)? {
        switch featureType {
        case "fairway": (fairway, 0.35, 0.08)
        case "green": (green, 0.6, 0.1)
        case "bunker": (bunker, 0.7, 0.12)
        case "tee": (tee, 0.55, 0.06)
        case "water_hazard", "lateral_water_hazard": (water, 0.5, 0.12)
        default: nil
        }
    }
}

public extension ShapeStyle where Self == Color {
    static var golfBrand: Color { GolfPalette.brand.color }
    static var golfOnBrand: Color { GolfPalette.onBrand.color }
    static var golfMeasure: Color { GolfPalette.measure.color }
    static var golfSand: Color { GolfPalette.sand.color }
    static var golfHazard: Color { GolfPalette.hazard.color }
    static var golfDestructive: Color { GolfPalette.destructive.color }
    static var golfSurface: Color { GolfPalette.surface.color }
    static var golfElevatedSurface: Color { GolfPalette.elevatedSurface.color }
    static var golfSeparator: Color { GolfPalette.separator.color }
    static var golfPrimaryText: Color { GolfPalette.primaryText.color }
    static var golfSecondaryText: Color { GolfPalette.secondaryText.color }
}

/// 4 pt spacing scale.
public enum GolfSpacing {
    public static let xxs: CGFloat = 4
    public static let xs: CGFloat = 8
    public static let s: CGFloat = 12
    public static let m: CGFloat = 16
    public static let l: CGFloat = 24
    public static let xl: CGFloat = 32
}

public enum GolfRadius {
    public static let small: CGFloat = 8
    public static let medium: CGFloat = 12
    public static let large: CGFloat = 20
}

public enum GolfMetrics {
    public static let minimumHitTarget: CGFloat = 44
}

/// Display styles for numbers. Pair the base sizes with `@ScaledMetric` so they follow Dynamic Type.
public enum GolfType {
    public static let yardageBaseSize: CGFloat = 64
    public static let scoreBaseSize: CGFloat = 34

    public static func yardage(size: CGFloat) -> Font {
        .system(size: size, weight: .bold, design: .rounded).monospacedDigit()
    }

    public static func score(size: CGFloat) -> Font {
        .system(size: size, weight: .semibold, design: .rounded).monospacedDigit()
    }

    public static let secondaryNumber = Font.title3.weight(.semibold).monospacedDigit()
    public static let label = Font.subheadline.weight(.semibold)
}
