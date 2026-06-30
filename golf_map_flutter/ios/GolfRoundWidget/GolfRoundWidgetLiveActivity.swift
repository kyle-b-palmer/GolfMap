import ActivityKit
import SwiftUI
import WidgetKit

private let appGroupId = "group.com.golfmapapp.golfMapFlutter"
private let sharedDefault = UserDefaults(suiteName: appGroupId)!

@main
struct GolfRoundWidgetBundle: WidgetBundle {
    var body: some Widget {
        if #available(iOS 16.1, *) {
            GolfRoundLiveActivityWidget()
        }
    }
}

@available(iOSApplicationExtension 16.1, *)
struct GolfRoundLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LiveActivitiesAppAttributes.self) { context in
            GolfRoundLockScreenView(context: context)
                .activityBackgroundTint(Color(red: 0.07, green: 0.07, blue: 0.09))
                .activitySystemActionForegroundColor(Color(red: 0.29, green: 0.87, blue: 0.50))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("HOLE \(hole(context))")
                            .font(.caption.weight(.bold))
                            .foregroundColor(accentGreen)
                        AdaptiveCourseNameLabel(
                            text: course(context),
                            maxSize: 11,
                            minScale: 0.55,
                            weight: .semibold
                        )
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    LiveActivityYardageView(
                        context: context,
                        showScoreLine: true,
                        yardsFontSize: 17,
                        compact: true
                    )
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if #available(iOSApplicationExtension 17.0, *) {
                        LiveActivityScoreControlsView(
                            context: context,
                            layout: .dynamicIsland
                        )
                    }
                }
            } compactLeading: {
                Text(hole(context))
                    .font(.caption.weight(.bold))
                    .foregroundColor(accentGreen)
            } compactTrailing: {
                Text(yardsCompact(context))
                    .font(.caption.weight(.bold))
            } minimal: {
                Text(hole(context))
                    .font(.caption2.weight(.bold))
            }
        }
        // iOS only — do not opt into .small (watchOS Smart Stack). The system may
        // still mirror a compact Live Activity to Apple Watch; users can disable
        // that under Watch Settings → Smart Stack → Live Activities.
        .supplementalActivityFamilies([.medium])
    }

    private var accentGreen: Color {
        Color(red: 0.29, green: 0.87, blue: 0.50)
    }

    private func hole(_ context: ActivityViewContext<LiveActivitiesAppAttributes>) -> String {
        sharedDefault.string(forKey: context.attributes.prefixedKey("hole")) ?? "—"
    }

    private func course(_ context: ActivityViewContext<LiveActivitiesAppAttributes>) -> String {
        sharedDefault.string(forKey: context.attributes.prefixedKey("courseName")) ?? "Golf"
    }

    private func yards(_ context: ActivityViewContext<LiveActivitiesAppAttributes>) -> Int {
        sharedDefault.integer(forKey: context.attributes.prefixedKey("yardsToGreen"))
    }

    private func yardsText(_ context: ActivityViewContext<LiveActivitiesAppAttributes>) -> String {
        let value = yards(context)
        return value >= 0 ? "\(value) YDS" : "— YDS"
    }

    private func yardsCompact(_ context: ActivityViewContext<LiveActivitiesAppAttributes>) -> String {
        let value = yards(context)
        return value >= 0 ? "\(value) YDS" : "—"
    }

    private func scoreLine(_ context: ActivityViewContext<LiveActivitiesAppAttributes>) -> String {
        let total = sharedDefault.integer(forKey: context.attributes.prefixedKey("totalScore"))
        let relative = sharedDefault.integer(forKey: context.attributes.prefixedKey("relativeToPar"))
        let relativeLabel = formatRelativeToPar(relative)
        if relativeLabel.isEmpty {
            return "TOT \(total)"
        }
        return "TOT \(total) \(relativeLabel)"
    }
}

@available(iOSApplicationExtension 16.1, *)
struct GolfRoundLockScreenView: View {
    let context: ActivityViewContext<LiveActivitiesAppAttributes>

    private var accentGreen: Color {
        Color(red: 0.29, green: 0.87, blue: 0.50)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            AdaptiveCourseNameLabel(
                text: courseName,
                maxSize: 14,
                minScale: 0.45,
                weight: .bold
            )

            HStack(alignment: .center, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("HOLE")
                        .font(.caption2.weight(.bold))
                        .foregroundColor(.secondary)
                    Text(hole)
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundColor(accentGreen)
                    Text("PAR \(par)")
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(.secondary)
                }

                Spacer(minLength: 4)

                LiveActivityYardageView(
                    context: context,
                    showScoreLine: true,
                    yardsFontSize: 22,
                    compact: false
                )
                .fixedSize(horizontal: true, vertical: false)
            }

            if #available(iOSApplicationExtension 17.0, *) {
                LiveActivityScoreControlsView(
                    context: context,
                    layout: .lockScreen
                )
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var courseName: String {
        sharedDefault.string(forKey: context.attributes.prefixedKey("courseName")) ?? "Golf"
    }

    private var hole: String {
        sharedDefault.string(forKey: context.attributes.prefixedKey("hole")) ?? "—"
    }

    private var par: Int {
        sharedDefault.integer(forKey: context.attributes.prefixedKey("par"))
    }

    private var yardsLabel: String {
        let yards = sharedDefault.integer(forKey: context.attributes.prefixedKey("yardsToGreen"))
        return yards >= 0 ? "\(yards) YDS" : "— YDS"
    }

    private var scoreLabel: String {
        let total = sharedDefault.integer(forKey: context.attributes.prefixedKey("totalScore"))
        let relative = sharedDefault.integer(forKey: context.attributes.prefixedKey("relativeToPar"))
        let relativeLabel = formatRelativeToPar(relative)
        if relativeLabel.isEmpty {
            return "TOT \(total)"
        }
        return "TOT \(total) \(relativeLabel)"
    }
}

private func formatRelativeToPar(_ relative: Int) -> String {
    if relative == 0 { return "" }
    if relative > 0 { return "(+\(relative))" }
    return "(\(relative))"
}

private struct AdaptiveCourseNameLabel: View {
    let text: String
    let maxSize: CGFloat
    let minScale: CGFloat
    let weight: Font.Weight

    var body: some View {
        Text(text)
            .font(.system(size: maxSize, weight: weight))
            .foregroundColor(.white.opacity(0.92))
            .lineLimit(1)
            .minimumScaleFactor(minScale)
            .allowsTightening(true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
