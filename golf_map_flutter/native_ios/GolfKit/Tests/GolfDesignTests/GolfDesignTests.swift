import Testing
@testable import GolfDesign

@Suite("Design tokens")
struct GolfDesignTests {
    @Test func textTokensMeetContrastOnBothSurfaces() {
        for (name, token) in GolfPalette.textTokens {
            for variant in ColorToken.allVariants {
                for surface in [GolfPalette.surface, GolfPalette.elevatedSurface] {
                    let ratio = RGB.contrast(
                        token.resolved(dark: variant.dark, highContrast: variant.highContrast),
                        surface.resolved(dark: variant.dark, highContrast: variant.highContrast)
                    )
                    #expect(ratio >= 4.5, "\(name) dark=\(variant.dark) high=\(variant.highContrast): \(ratio)")
                }
            }
        }
    }

    @Test func onBrandTextIsLegible() {
        for variant in ColorToken.allVariants {
            let ratio = RGB.contrast(
                GolfPalette.onBrand.resolved(dark: variant.dark, highContrast: variant.highContrast),
                GolfPalette.brand.resolved(dark: variant.dark, highContrast: variant.highContrast)
            )
            #expect(ratio >= 4.5, "dark=\(variant.dark) high=\(variant.highContrast): \(ratio)")
        }
    }

    @Test func gpsStatusOnlyAllowsCurrentPreciseFixes() {
        #expect(GPSStatus.live(accuracyMeters: 5).allowsYardage)
        #expect(GPSStatus.weak(accuracyMeters: 40).allowsYardage)
        #expect(GPSStatus.simulated.allowsYardage)
        #expect(!GPSStatus.reducedAccuracy.allowsYardage)
        #expect(!GPSStatus.searching.allowsYardage)
        #expect(!GPSStatus.stale(seconds: 30).allowsYardage)
        #expect(!GPSStatus.denied.allowsYardage)
    }

    @Test func gpsStatusClassification() {
        func classify(accuracy: Double? = 5, age: Double = 1, authorized: Bool = true, precise: Bool = true, simulated: Bool = false) -> GPSStatus {
            GPSStatus.classify(accuracyMeters: accuracy, ageSeconds: age, authorized: authorized, precise: precise, simulated: simulated)
        }
        #expect(classify() == .live(accuracyMeters: 5))
        #expect(classify(accuracy: 30) == .weak(accuracyMeters: 30))
        #expect(classify(age: 20) == .stale(seconds: 20))
        #expect(classify(accuracy: nil) == .searching)
        #expect(classify(authorized: false) == .denied)
        #expect(classify(precise: false) == .reducedAccuracy)
        #expect(classify(accuracy: nil, authorized: false, simulated: true) == .simulated)
    }
}
