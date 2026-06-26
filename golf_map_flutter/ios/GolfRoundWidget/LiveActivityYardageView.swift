import AppIntents
import SwiftUI
import WidgetKit

@available(iOSApplicationExtension 16.1, *)
struct LiveActivityYardageView: View {
    let context: ActivityViewContext<LiveActivitiesAppAttributes>
    var showScoreLine: Bool = true
    var yardsFontSize: CGFloat = 22
    var compact: Bool = false

    private var accentGreen: Color {
        Color(red: 0.29, green: 0.87, blue: 0.50)
    }

    private var yardsValue: Int {
        yardageSharedDefault.integer(forKey: context.attributes.prefixedKey("yardsToGreen"))
    }

    private var yardsLabel: String {
        yardsValue >= 0 ? "\(yardsValue) YDS" : "— YDS"
    }

    private var scoreLabel: String {
        let total = yardageSharedDefault.integer(forKey: context.attributes.prefixedKey("totalScore"))
        let relative = yardageSharedDefault.integer(forKey: context.attributes.prefixedKey("relativeToPar"))
        let relativeLabel = formatYardageRelativeToPar(relative)
        if relativeLabel.isEmpty {
            return "TOT \(total)"
        }
        return "TOT \(total) \(relativeLabel)"
    }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            if #available(iOSApplicationExtension 17.0, *) {
                Button(intent: RefreshGpsYardageIntent()) {
                    Image(systemName: "mappin.and.ellipse")
                        .font(.system(size: compact ? 14 : 16, weight: .bold))
                        .foregroundColor(accentGreen)
                        .frame(width: compact ? 30 : 34, height: compact ? 30 : 34)
                        .background(Color.white.opacity(0.12))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }

            VStack(alignment: .trailing, spacing: 2) {
                Text(yardsLabel)
                    .font(.system(size: yardsFontSize, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text("TO GREEN")
                    .font(.system(size: compact ? 8 : 9, weight: .bold))
                    .foregroundColor(.secondary)
                if showScoreLine {
                    Text(scoreLabel)
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(accentGreen)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
        }
    }
}

private let yardageAppGroupId = "group.com.golfmapapp.golfMapFlutter"
private let yardageSharedDefault = UserDefaults(suiteName: yardageAppGroupId)!

private func formatYardageRelativeToPar(_ relative: Int) -> String {
    if relative == 0 { return "" }
    if relative > 0 { return "(+\(relative))" }
    return "(\(relative))"
}
