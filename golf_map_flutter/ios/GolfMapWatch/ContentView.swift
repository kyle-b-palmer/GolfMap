import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = GolfRoundWatchViewModel()

    var body: some View {
        Group {
            if let state = viewModel.state, state.isActiveRound {
                roundView(state)
            } else {
                waitingView
            }
        }
        .onAppear { viewModel.start() }
        .onDisappear { viewModel.stop() }
    }

    private var waitingView: some View {
        VStack(spacing: 8) {
            Image(systemName: "flag.fill")
                .font(.title2)
                .foregroundStyle(.green)
            Text("Golf Map")
                .font(.headline)
            Text("Start a round on iPhone")
                .font(.caption2)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            if viewModel.phoneReachable {
                Text("Phone connected")
                    .font(.caption2)
                    .foregroundStyle(.green)
            }
        }
        .padding()
    }

    private func roundView(_ state: GolfRoundSharedState) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text(state.courseName.uppercased())
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("HOLE")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(state.selectedHole)
                            .font(.title2.bold())
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("PAR")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text("\(state.currentPar)")
                            .font(.title3.bold())
                    }
                }

                yardageBlock

                scoreBlock(state)

                HStack {
                    totalBlock(state)
                    Spacer()
                    holeNavButtons
                }
            }
            .padding(.horizontal, 4)
        }
    }

    private var yardageBlock: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("TO GREEN")
                .font(.caption2)
                .foregroundStyle(.secondary)
            if let yards = viewModel.yardsToGreen, yards >= 0 {
                Text("\(yards)")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(.green)
                Text("YDS")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Text("—")
                    .font(.title)
                    .foregroundStyle(.secondary)
                Text("GPS")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(Color.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func scoreBlock(_ state: GolfRoundSharedState) -> some View {
        HStack {
            Button {
                viewModel.decrementScore()
            } label: {
                Image(systemName: "minus")
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.bordered)
            .tint(.white)

            VStack(spacing: 0) {
                Text("SCORE")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("\(max(state.currentHoleScore, 0))")
                    .font(.title.bold())
                    .monospacedDigit()
            }
            .frame(maxWidth: .infinity)

            Button {
                viewModel.incrementScore()
            } label: {
                Image(systemName: "plus")
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
        }
    }

    private func totalBlock(_ state: GolfRoundSharedState) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("TOTAL")
                .font(.caption2)
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(state.totalScore)")
                    .font(.headline.bold())
                if state.relativeToPar != 0 {
                    Text(formatRelative(state.relativeToPar))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var holeNavButtons: some View {
        HStack(spacing: 6) {
            Button("PREV") { viewModel.previousHole() }
                .font(.caption2)
            Button("NEXT") { viewModel.nextHole() }
                .font(.caption2.bold())
        }
        .buttonStyle(.bordered)
    }

    private func formatRelative(_ value: Int) -> String {
        if value > 0 { return "(+\(value))" }
        return "(\(value))"
    }
}

#Preview {
    ContentView()
}
