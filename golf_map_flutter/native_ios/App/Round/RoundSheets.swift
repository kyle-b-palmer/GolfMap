import GolfCore
import GolfDesign
import SwiftUI

/// Sets the round's total score target. Mirrors Flutter's sheet: a number field plus Par, 80, and 90 presets.
struct ScoreTargetSheet: View {
    let coursePar: Int
    let current: Int
    let onSelect: (Int?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text: String
    @FocusState private var focused: Bool

    init(coursePar: Int, current: Int, onSelect: @escaping (Int?) -> Void) {
        self.coursePar = coursePar
        self.current = current
        self.onSelect = onSelect
        _text = State(initialValue: "\(current)")
    }

    private var value: Int? { Int(text.trimmingCharacters(in: .whitespaces)).flatMap { $0 > 0 ? $0 : nil } }

    var body: some View {
        Form {
            Section {
                TextField("Target score", text: $text)
                    .keyboardType(.numberPad)
                    .font(GolfType.score(size: 34))
                    .multilineTextAlignment(.center)
                    .focused($focused)
                    .onSubmit(apply)
            } footer: {
                Text("Strokes left for the target appear under your score.")
            }
            Section("Presets") {
                if coursePar > 0 {
                    Button("Par (\(coursePar))") { select(nil) }
                }
                Button("80") { select(80) }
                Button("90") { select(90) }
            }
        }
        .navigationTitle("Score target")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Set", action: apply).disabled(value == nil)
            }
        }
        .onAppear { focused = true }
    }

    private func apply() {
        guard let value else { return }
        select(value == coursePar ? nil : value)
    }

    /// `nil` follows the course par, which is the default target.
    private func select(_ target: Int?) {
        onSelect(target)
        dismiss()
    }
}

/// The live round's scorecard, opened from the round total.
struct RoundScorecardSheet: View {
    let round: RoundState

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section {
                HStack(alignment: .firstTextBaseline) {
                    Text(round.playedAt.date, format: .dateTime.month().day().year())
                        .foregroundStyle(.golfSecondaryText)
                    Spacer()
                    Text("\(round.totalScore)")
                        .font(GolfType.score(size: 34))
                    if round.coursePar > 0 {
                        Text(formatRelativeToPar(round.totalRelativeToPar))
                            .font(.headline.monospacedDigit())
                            .foregroundStyle(.golfSecondaryText)
                    }
                }
                .accessibilityElement(children: .combine)
            }
            Section {
                ScorecardGrid(holes: round.holes.map {
                    ScorecardHole(hole: $0, par: round.par($0), score: round.score($0), putts: round.putts($0))
                })
            }
        }
        .navigationTitle(round.courseName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                RoundShareLink(card: .scorecard, recap: RoundRecap(round), label: "Share")
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
    }
}

/// Offered after saving, as Flutter's "Share recap" prompt was.
struct SavedRecapSheet: View {
    let recap: RoundRecap

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(spacing: GolfSpacing.l) {
                RoundShareCard.recap.view(recap)
                    .environment(\.colorScheme, .dark)
                RoundShareLink(card: .recap, recap: recap, label: "Share recap")
                    .buttonStyle(.golfPrimary)
                RoundShareLink(card: .scorecard, recap: recap, label: "Share scorecard")
            }
            .padding(GolfSpacing.m)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Round saved")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
    }
}
