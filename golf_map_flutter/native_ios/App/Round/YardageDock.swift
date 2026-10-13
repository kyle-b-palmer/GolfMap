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

    private var origin: Coordinate? { store.gpsOrigin(user) }
    private var yardages: GreenYardages? { store.yardages(from: origin) }

    private var advice: ShotAdvice? {
        guard gps.allowsYardage else { return nil }
        return store.shotAdvice(from: origin, clubs: ClubDistance.decodeBag(clubBagJSON))
    }

    private var selectedPin: PinnedShot? {
        store.round.currentPins.first { $0.id == store.selectedPinID }
    }

    var body: some View {
        VStack(spacing: GolfSpacing.s) {
            handle
            YardageReadout(middle: yardages?.middle, front: yardages?.front, back: yardages?.back, gps: gps)
            Group {
                if user != nil, origin == nil {
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

            HStack {
                Text("Round")
                Spacer()
                Text("\(store.round.totalScore) strokes · \(relative(store.round.totalRelativeToPar))")
                    .monospacedDigit()
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.golfSecondaryText)
        }
        .font(.subheadline)
    }

    private func relative(_ value: Int) -> String {
        value == 0 ? "E" : value > 0 ? "+\(value)" : "\(value)"
    }
}
