import GolfCore
import GolfDesign
import SwiftUI

/// Bottom panel: yardage, club, score, and the shot action. Expands for tees, hazards, and shots.
struct YardageDock: View {
    let store: RoundStore
    let gps: GPSStatus
    let user: Coordinate?
    @Binding var expanded: Bool
    let onMarkShot: () -> Void

    @AppStorage(SettingsKey.clubBag) private var clubBagJSON = ""
    @AppStorage(SettingsKey.showScoreTarget) private var showScoreTarget = true
    @State private var sheet: DockSheet?
    @Environment(\.openURL) private var openURL

    private var origin: Coordinate? { store.gpsOrigin(user) }
    private var yardages: GreenYardages? { store.yardages(from: origin) }

    private var advice: ShotAdvice? {
        guard gps.allowsYardage else { return nil }
        return store.shotAdvice(from: origin, clubs: ClubDistance.decodeBag(clubBagJSON))
    }

    /// Why yardage is hidden and what to do about it; nil when a usable fix is available or still expected.
    private var gpsRecovery: String? {
        switch gps {
        case .denied: "Allow location access to see yardages."
        case .reducedAccuracy: "Turn on Precise Location for accurate yardages."
        case .stale: "Waiting for a GPS update. Yardages return with the next fix."
        default: nil
        }
    }

    private var selectedPin: PinnedShot? {
        store.round.currentPins.first { $0.id == store.selectedPinID }
    }

    var body: some View {
        VStack(spacing: GolfSpacing.s) {
            handle
            YardageReadout(middle: yardages?.middle, front: yardages?.front, back: yardages?.back, gps: gps)
            Group {
                if let recovery = gpsRecovery {
                    HStack(spacing: GolfSpacing.s) {
                        Text(recovery)
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(.golfSecondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                        if gps == .denied || gps == .reducedAccuracy {
                            Spacer(minLength: 0)
                            Button("Settings") {
                                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                            }
                            .buttonStyle(.bordered)
                            .accessibilityHint("Opens Golf Map's location settings")
                        }
                    }
                } else if user != nil, origin == nil {
                    Label("More than 1,200 yd from hole \(store.round.selectedHole)", systemImage: "location.slash")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.golfSecondaryText)
                } else {
                    ClubSuggestionLine(
                        playsLike: advice.flatMap { $0.showsPlaysLike ? $0.playsLikeYards : nil },
                        club: advice?.suggestion?.club,
                        alternate: advice?.suggestion?.alternateClub
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(alignment: .top) {
                ScoreStepper(
                    "Score",
                    value: Binding(get: { store.round.currentScore }, set: { store.send(.setScore(hole: store.round.selectedHole, strokes: $0)) }),
                    in: 0...99,
                    detail: scoreDetail,
                    isEnabled: !store.round.isCurrentHoleLocked
                )
                Spacer(minLength: GolfSpacing.m)
                ScoreStepper(
                    "Putts",
                    value: Binding(get: { store.round.currentPutts }, set: { store.send(.setPutts(hole: store.round.selectedHole, putts: $0)) }),
                    in: 0...9,
                    isEnabled: !store.round.isCurrentHoleLocked
                )
            }
            roundSummary
            actionRow
            if expanded {
                details
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(.horizontal, GolfSpacing.m)
        .padding(.bottom, GolfSpacing.s)
        .background(
            UnevenRoundedRectangle(topLeadingRadius: GolfRadius.large, topTrailingRadius: GolfRadius.large, style: .continuous)
                .fill(.golfSurface)
                .shadow(color: .black.opacity(0.25), radius: 12, y: -2)
                .ignoresSafeArea(edges: .bottom)
        )
    }

    private var handle: some View {
        Button {
            withAnimation(.smooth) { expanded.toggle() }
        } label: {
            Capsule()
                .fill(.golfSeparator)
                .frame(width: 40, height: 5)
                .frame(maxWidth: .infinity, minHeight: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(expanded ? "Hide hole details" : "Show hole details")
        .gesture(DragGesture(minimumDistance: 12).onEnded { value in
            withAnimation(.smooth) { expanded = value.translation.height < 0 }
        })
    }

    @ViewBuilder
    private var actionRow: some View {
        if let pin = selectedPin {
            SelectionBar(
                title: pin.pinType == .lostBall ? "Lost ball · shot \(pin.shotNumber)" : "Shot \(pin.shotNumber)",
                detail: pinDetail(pin),
                onDelete: { store.send(.deletePin(hole: store.round.selectedHole, id: pin.id)) },
                onDone: { store.selectedPinID = nil }
            )
        } else {
            Button(action: onMarkShot) {
                Label("Mark shot", systemImage: "mappin.and.ellipse")
            }
            .buttonStyle(.golfPrimary)
            .disabled(origin == nil || store.round.isCurrentHoleLocked)
            .accessibilityHint(origin == nil ? "Available within 1,200 yards of the hole" : "Pins your current location as the next shot")
        }
    }

    private var scoreDetail: String? {
        let par = store.round.currentPar
        let score = store.round.currentScore
        guard par > 0 else { return nil }
        guard score > 0 else { return "Par \(par)" }
        let diff = score - par
        return diff == 0 ? "Par" : diff > 0 ? "+\(diff)" : "\(diff)"
    }

    private func pinDetail(_ pin: PinnedShot) -> String? {
        var parts: [String] = []
        if let shot = pin.shotYards { parts.append("\(shot) yd") }
        if let toPin = pin.yardsToPin { parts.append("\(toPin) to green") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: GolfSpacing.m) {
            if store.hole.tees.count > 1 {
                Picker("Tees", selection: Binding(
                    get: { store.round.preferredTeeLabel ?? store.hole.tees.first?.label ?? "" },
                    set: { store.send(.setPreferredTee(label: $0)) }
                )) {
                    ForEach(store.hole.tees, id: \.label) { tee in
                        Text(tee.label).tag(tee.label)
                    }
                }
                .pickerStyle(.menu)
            }

            if let origin, gps.allowsYardage {
                let bunkers = HoleGeometry.bunkerDistances(from: origin, store.hole.features)
                if !bunkers.isEmpty {
                    VStack(alignment: .leading, spacing: GolfSpacing.xxs) {
                        Text("Hazards").font(GolfType.label).foregroundStyle(.golfSecondaryText)
                        ForEach(Array(bunkers.prefix(4).enumerated()), id: \.offset) { _, bunker in
                            HStack {
                                Text(bunker.label)
                                Spacer()
                                Text(bunker.yards >= 0 ? "\(bunker.yards) yd" : "\(-bunker.yards) yd behind")
                                    .monospacedDigit()
                            }
                            .foregroundStyle(.golfSand)
                        }
                    }
                }
            }

            if !store.round.currentPins.isEmpty {
                VStack(alignment: .leading, spacing: GolfSpacing.xxs) {
                    Text("Shots").font(GolfType.label).foregroundStyle(.golfSecondaryText)
                    ForEach(store.round.currentPins) { pin in
                        Button {
                            store.selectedPinID = pin.id
                        } label: {
                            HStack {
                                Text(pin.pinType == .lostBall ? "\(pin.shotNumber). Lost ball" : "\(pin.shotNumber). Shot")
                                Spacer()
                                Text(pinDetail(pin) ?? "").monospacedDigit().foregroundStyle(.golfSecondaryText)
                            }
                            .frame(minHeight: GolfMetrics.minimumHitTarget)
                        }
                        .foregroundStyle(.golfPrimaryText)
                    }
                }
            }
        }
        .font(.subheadline)
    }

    /// Strokes left for the target (Flutter's "LEFT n FOR m TO PLAY") and the round total, which opens the scorecard.
    private var roundSummary: some View {
        let round = store.round
        return HStack(spacing: GolfSpacing.s) {
            if showScoreTarget {
                Button { sheet = .target } label: {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("\(round.strokesRemainingForTarget) left for \(round.holesToPlay) to play")
                            .font(.subheadline.weight(.semibold).monospacedDigit())
                        Text(round.scoreTarget == nil ? "Target par \(round.effectiveScoreTarget)" : "Target \(round.effectiveScoreTarget)")
                            .font(.caption)
                            .foregroundStyle(.golfSecondaryText)
                    }
                    .frame(minHeight: GolfMetrics.minimumHitTarget)
                    .contentShape(Rectangle())
                }
                .foregroundStyle(.golfPrimaryText)
                .accessibilityLabel("\(round.strokesRemainingForTarget) strokes left for target \(round.effectiveScoreTarget), \(round.holesToPlay) holes to play")
                .accessibilityHint("Changes the score target")
            }
            Spacer(minLength: 0)
            Button { sheet = .scorecard } label: {
                HStack(spacing: GolfSpacing.xxs) {
                    Text("Total \(round.totalScore)")
                    if round.coursePar > 0 {
                        Text(formatRelativeToPar(round.totalRelativeToPar)).foregroundStyle(.golfSecondaryText)
                    }
                    Image(systemName: "list.number").accessibilityHidden(true)
                }
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .frame(minHeight: GolfMetrics.minimumHitTarget)
                .contentShape(Rectangle())
            }
            .foregroundStyle(.golfPrimaryText)
            .accessibilityLabel("Total \(round.totalScore), \(formatRelativeToPar(round.totalRelativeToPar))")
            .accessibilityHint("Shows the scorecard")
        }
        .sheet(item: $sheet) { sheet in
            NavigationStack {
                switch sheet {
                case .target:
                    ScoreTargetSheet(coursePar: round.coursePar, current: round.effectiveScoreTarget) {
                        store.send(.setScoreTarget($0))
                    }
                case .scorecard:
                    RoundScorecardSheet(round: store.round)
                }
            }
            .presentationDetents(sheet == .target ? [.medium] : [.medium, .large])
        }
    }
}

private enum DockSheet: String, Identifiable {
    case target
    case scorecard

    var id: String { rawValue }
}
