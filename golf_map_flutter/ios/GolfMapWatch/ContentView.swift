import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = GolfRoundWatchViewModel()
    @State private var showingScorePicker = false
    @State private var showingPuttsPicker = false
    @State private var pickerScore = 0
    @State private var pickerPutts = 0

    private let accentGreen = Color(red: 0.29, green: 0.87, blue: 0.50)
    private let scoreRange = Array(0...15)
    private let puttsRange = Array(0...9)

    var body: some View {
        Group {
            if let state = viewModel.state, state.isActiveRound {
                roundView(state)
            } else {
                idleView
            }
        }
        .onAppear { viewModel.start() }
        .onDisappear { viewModel.stop() }
    }

    private var idleView: some View {
        VStack(spacing: 8) {
            Image("AppLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            Text("South Texas Golf Tracker")
                .font(.headline)
                .multilineTextAlignment(.center)
            Text("Waiting for round")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding()
    }

    private func roundView(_ state: GolfRoundSharedState) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                Text(state.courseName)
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 6)

                HStack(alignment: .firstTextBaseline) {
                    Text("HOLE \(state.selectedHole)")
                        .font(.headline.bold())
                    Spacer(minLength: 4)
                    totalLabel(state)
                }

                yardageAndStatsRow(state)

                HStack(spacing: 6) {
                    scoreTapBlock(state)
                    puttsTapBlock(state)
                }

                if viewModel.canUndoLastSwing {
                    Button {
                        viewModel.undoLastSwing()
                    } label: {
                        Label("Undo last swing", systemImage: "arrow.uturn.backward")
                            .font(.caption2.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.bordered)
                    .tint(.orange)
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .contentShape(Rectangle())
        .simultaneousGesture(holeSwipeGesture)
        .sheet(isPresented: $showingScorePicker) {
            scorePickerSheet
        }
        .sheet(isPresented: $showingPuttsPicker) {
            puttsPickerSheet
        }
    }

    private var holeSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 20, coordinateSpace: .local)
            .onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                if value.translation.width < -24 {
                    viewModel.nextHole()
                } else if value.translation.width > 24 {
                    viewModel.previousHole()
                }
            }
    }

    private func yardageAndStatsRow(_ state: GolfRoundSharedState) -> some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                if let yards = viewModel.yardsToGreen, yards >= 0 {
                    Text("\(yards) YDS")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(accentGreen)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                } else {
                    Text("— YDS")
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 12) {
                    Text("PAR \(state.currentPar > 0 ? "\(state.currentPar)" : "—")")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)

                    Text("HCP \(state.currentHandicap > 0 ? "\(state.currentHandicap)" : "—")")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)

            pinButton
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var pinButton: some View {
        Button {
            viewModel.pinCurrentLocation()
        } label: {
            VStack(spacing: 2) {
                if viewModel.isPinningLocation {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "mappin.circle.fill")
                        .font(.title3)
                        .foregroundStyle(accentGreen)
                }
                Text("PIN")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 44)
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isPinningLocation)
    }

    private func totalLabel(_ state: GolfRoundSharedState) -> some View {
        HStack(spacing: 3) {
            Text("TOTAL")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text("\(state.totalScore)")
                .font(.subheadline.bold())
                .monospacedDigit()
            if state.relativeToPar != 0 {
                Text(formatRelative(state.relativeToPar))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }

    private func scoreTapBlock(_ state: GolfRoundSharedState) -> some View {
        let currentScore = max(state.currentHoleScore, 0)

        return Button {
            pickerScore = currentScore
            showingScorePicker = true
        } label: {
            VStack(spacing: 2) {
                Text("SCORE")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(currentScore > 0 ? "\(currentScore)" : "—")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .monospacedDigit()
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    private func puttsTapBlock(_ state: GolfRoundSharedState) -> some View {
        let currentPutts = max(state.currentHolePutts, 0)

        return Button {
            pickerPutts = currentPutts
            showingPuttsPicker = true
        } label: {
            VStack(spacing: 2) {
                Text("PUTTS")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(currentPutts > 0 ? "\(currentPutts)" : "—")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .monospacedDigit()
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    private var scorePickerSheet: some View {
        VStack(spacing: 4) {
            Text("Score")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Picker("Score", selection: $pickerScore) {
                ForEach(scoreRange, id: \.self) { score in
                    Text(score == 0 ? "—" : "\(score)")
                        .tag(score)
                }
            }
            .pickerStyle(.wheel)
            .labelsHidden()
            .onChange(of: pickerScore) { _, newValue in
                viewModel.setScore(newValue)
            }

            Button("Done") {
                showingScorePicker = false
            }
            .buttonStyle(.borderedProminent)
            .tint(accentGreen)
        }
        .padding(.horizontal, 4)
    }

    private var puttsPickerSheet: some View {
        VStack(spacing: 4) {
            Text("Putts")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Picker("Putts", selection: $pickerPutts) {
                ForEach(puttsRange, id: \.self) { putts in
                    Text(putts == 0 ? "—" : "\(putts)")
                        .tag(putts)
                }
            }
            .pickerStyle(.wheel)
            .labelsHidden()
            .onChange(of: pickerPutts) { _, newValue in
                viewModel.setPutts(newValue)
            }

            Button("Done") {
                showingPuttsPicker = false
            }
            .buttonStyle(.borderedProminent)
            .tint(accentGreen)
        }
        .padding(.horizontal, 4)
    }

    private func formatRelative(_ value: Int) -> String {
        if value > 0 { return "(+\(value))" }
        return "(\(value))"
    }
}

#Preview {
    ContentView()
}
