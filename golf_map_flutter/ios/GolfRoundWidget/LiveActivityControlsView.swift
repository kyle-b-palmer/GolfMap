import AppIntents
import SwiftUI
import WidgetKit

enum LiveActivityControlsLayout {
    case lockScreen
    case dynamicIsland
}

@available(iOSApplicationExtension 17.0, *)
struct LiveActivityScoreControlsView: View {
    let context: ActivityViewContext<LiveActivitiesAppAttributes>
    var layout: LiveActivityControlsLayout = .lockScreen

    private static let quickPickScores = [2, 3, 4, 5]

    private var accentGreen: Color {
        Color(red: 0.29, green: 0.87, blue: 0.50)
    }

    private var isCompact: Bool {
        layout == .dynamicIsland
    }

    private var scoreButtonSize: CGFloat {
        isCompact ? 26 : 30
    }

    private var quickScoreFontSize: CGFloat {
        isCompact ? 13 : 14
    }

    private var currentHoleScore: Int {
        if let state = GolfRoundLiveActivityController.shared.loadState() {
            return state.scores[state.selectedHole] ?? 0
        }
        let stored = sharedDefault.integer(
            forKey: context.attributes.prefixedKey("holeScore")
        )
        return stored > 0 ? stored : 0
    }

    private var quickPickSelected: Bool {
        Self.quickPickScores.contains(currentHoleScore)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: isCompact ? 5 : 6) {
            HStack(spacing: isCompact ? 4 : 6) {
                scoreButton(intent: DecrementGolfScoreIntent(), symbol: "minus")

                ForEach(Self.quickPickScores, id: \.self) { score in
                    quickScoreButton(score: score)
                }

                scoreButton(intent: IncrementGolfScoreIntent(), symbol: "plus")

                if !quickPickSelected && currentHoleScore > 0 {
                    Text("\(currentHoleScore)")
                        .font(.system(size: quickScoreFontSize, weight: .bold, design: .rounded))
                        .foregroundColor(.white.opacity(0.85))
                        .frame(minWidth: 16)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: isCompact ? 5 : 6) {
                holeNavButton(
                    intent: PreviousGolfHoleIntent(),
                    symbol: "arrow.left",
                    label: isCompact ? "PREV" : "PREV HOLE"
                )

                Button(intent: PinGolfShotIntent()) {
                    HStack(spacing: 4) {
                        Image(systemName: "mappin.and.ellipse")
                            .font(.system(size: isCompact ? 10 : 11, weight: .bold))
                        Text(isCompact ? "PIN" : "PIN SHOT")
                            .font(.system(size: isCompact ? 9 : 10, weight: .bold))
                    }
                    .foregroundColor(accentGreen)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, isCompact ? 7 : 8)
                    .background(Color.white.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)

                holeNavButton(
                    intent: NextGolfHoleIntent(),
                    symbol: "arrow.right",
                    label: isCompact ? "NEXT" : "NEXT HOLE"
                )
            }
        }
        .padding(.top, isCompact ? 2 : 4)
    }

    @ViewBuilder
    private func quickScoreButton(score: Int) -> some View {
        let selected = currentHoleScore == score

        Button(intent: SetGolfScoreIntent(score: score)) {
            Text("\(score)")
                .font(.system(size: quickScoreFontSize, weight: .bold, design: .rounded))
                .foregroundColor(selected ? .black : accentGreen)
                .frame(width: scoreButtonSize, height: scoreButtonSize)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(selected ? accentGreen : Color.white.opacity(0.1))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(selected ? accentGreen : Color.clear, lineWidth: 1.5)
                )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func holeNavButton<I: AppIntent>(
        intent: I,
        symbol: String,
        label: String
    ) -> some View {
        Button(intent: intent) {
            VStack(spacing: 2) {
                Image(systemName: symbol)
                    .font(.system(size: isCompact ? 9 : 10, weight: .bold))
                Text(label)
                    .font(.system(size: isCompact ? 8 : 9, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .foregroundColor(accentGreen)
            .frame(minWidth: isCompact ? 52 : 58)
            .padding(.horizontal, isCompact ? 6 : 8)
            .padding(.vertical, isCompact ? 6 : 7)
            .background(Color.white.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func scoreButton<I: AppIntent>(
        intent: I,
        symbol: String
    ) -> some View {
        Button(intent: intent) {
            Image(systemName: symbol)
                .font(.system(size: isCompact ? 11 : 12, weight: .bold))
                .foregroundColor(accentGreen)
                .frame(width: scoreButtonSize, height: scoreButtonSize)
                .background(Color.white.opacity(0.1))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

private let appGroupId = "group.com.golfmapapp.golfMapFlutter"
private let sharedDefault = UserDefaults(suiteName: appGroupId)!
