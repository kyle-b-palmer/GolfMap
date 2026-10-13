import GolfCore
import GolfDesign
import SwiftUI

struct SavedRoundDetailView: View {
    let round: SavedRound
    let onContinue: (SavedRound) -> Void
    let onDelete: (SavedRound) -> Void

    @Environment(CourseRepository.self) private var courses
    @Environment(\.dismiss) private var dismiss
    @State private var confirmDelete = false

    /// The round as it would reopen, which supplies pars and hole order.
    private var state: RoundState { RoundState.reopen(round, features: courses.features(for: round.courseName)) }

    private var holes: [ScorecardHole] {
        let state = state
        return state.holes.map { ScorecardHole(hole: $0, par: state.par($0), score: state.score($0), putts: state.putts($0)) }
    }

    var body: some View {
        let state = state
        List {
            Section {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: GolfSpacing.xxs) {
                        Text(round.playedAt.date, format: .dateTime.weekday(.wide).month().day().year())
                            .font(.subheadline)
                            .foregroundStyle(.golfSecondaryText)
                        Text("\(round.holesScored) of \(state.holes.count) holes scored")
                            .font(.subheadline)
                            .foregroundStyle(.golfSecondaryText)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 0) {
                        Text("\(state.totalScore)")
                            .font(GolfType.score(size: 40))
                            .accessibilityLabel("\(state.totalScore) strokes")
                        if state.coursePar > 0 {
                            Text(formatRelativeToPar(state.totalRelativeToPar))
                                .font(.headline.monospacedDigit())
                                .foregroundStyle(.golfSecondaryText)
                                .accessibilityLabel("Relative to par \(formatRelativeToPar(state.totalRelativeToPar))")
                        }
                    }
                }
                LabeledContent("Putts", value: "\(state.totalPutts)")
                if round.totalPinnedShots > 0 {
                    LabeledContent("Tracked shots", value: "\(round.totalPinnedShots)")
                }
            }

            Section("Scorecard") {
                ScorecardGrid(holes: holes)
                    .listRowInsets(EdgeInsets(top: GolfSpacing.s, leading: GolfSpacing.m, bottom: GolfSpacing.s, trailing: GolfSpacing.m))
            }

            Section {
                Button("Continue editing", systemImage: "pencil") { onContinue(round) }
                Button("Delete round", systemImage: "trash", role: .destructive) { confirmDelete = true }
            } footer: {
                Text("Continuing reopens the round with its scores, shots, and date.")
            }
        }
        .navigationTitle(round.courseName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                let recap = RoundRecap(state)
                Menu("Share", systemImage: "square.and.arrow.up") {
                    RoundShareLink(card: .scorecard, recap: recap)
                    RoundShareLink(card: .recap, recap: recap)
                }
            }
        }
        .confirmationDialog("Delete this round?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete round", role: .destructive) {
                onDelete(round)
                dismiss()
            }
        } message: {
            Text("\(round.courseName), \(round.playedAt.date.formatted(date: .abbreviated, time: .omitted)). This can't be undone.")
        }
    }
}
