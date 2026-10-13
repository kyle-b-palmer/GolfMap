import GolfCore
import GolfDesign
import SwiftUI

struct RoundView: View {
    let store: RoundStore

    @Environment(LocationService.self) private var location
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingsKey.autoAdvanceHoles) private var autoAdvance = true
    @AppStorage(SettingsKey.mapImagery) private var imagery = true
    @AppStorage(SettingsKey.keepScreenAwake) private var keepAwake = true
    @AppStorage(SettingsKey.gpsSimulationEnabled) private var simulationEnabled = false
    @State private var dockExpanded = false
    @State private var recenterToken = 0
    @State private var placingSimulatedLocation = false
    @State private var confirmEnd = false

    var body: some View {
        VStack(spacing: 0) {
            header
            HoleMapView(
                store: store,
                user: location.coordinate,
                isSimulated: location.simulatedCoordinate != nil,
                imagery: imagery,
                recenterToken: recenterToken,
                onTap: placingSimulatedLocation ? { coordinate in
                    location.simulatedCoordinate = coordinate
                    placingSimulatedLocation = false
                } : nil
            )
            .overlay(alignment: .top) {
                Group {
                    if placingSimulatedLocation {
                        PlacementBanner("Tap the map to set a simulated location") {
                            placingSimulatedLocation = false
                        }
                        .padding(.horizontal, GolfSpacing.m)
                    } else if let banner = store.banner {
                        Text(banner)
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, GolfSpacing.m)
                            .padding(.vertical, GolfSpacing.xs)
                            .background(.thickMaterial, in: Capsule())
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                .padding(.top, GolfSpacing.xs)
                .animation(.smooth, value: store.banner)
            }
            .overlay(alignment: .trailing) {
                VStack(spacing: GolfSpacing.s) {
                    MapControlButton("Show whole hole", systemImage: "scope") { recenterToken += 1 }
                    MapControlButton(imagery ? "Show standard map" : "Show satellite map", systemImage: "square.3.layers.3d", isActive: imagery) {
                        imagery.toggle()
                    }
                }
                .padding(.trailing, GolfSpacing.m)
            }
        }
        .background(GolfMapPalette.courseBackground.color.ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) {
            YardageDock(store: store, gps: location.status, user: location.coordinate, expanded: $dockExpanded) {
                guard let origin = store.gpsOrigin(location.coordinate) else { return }
                store.markShot(at: origin, from: origin, source: .gps)
            }
        }
        .sensoryFeedback(.success, trigger: store.round.currentPins.count) { old, new in new > old }
        .sensoryFeedback(.impact, trigger: store.round.selectedHole)
        .confirmationDialog("End round?", isPresented: $confirmEnd, titleVisibility: .visible) {
            Button("Save round") {
                store.finish()
                location.endRound()
                dismiss()
            }
            Button("Discard round", role: .destructive) {
                store.discard()
                location.endRound()
                dismiss()
            }
        } message: {
            Text("Saving locks every hole. You can reopen a saved round later.")
        }
        .onAppear {
            store.activate()
            location.start(inRound: true)
            UIApplication.shared.isIdleTimerDisabled = keepAwake
        }
        .onDisappear {
            store.deactivate()
            UIApplication.shared.isIdleTimerDisabled = false
        }
        .onChange(of: location.coordinate) { _, coordinate in
            store.locationChanged(coordinate, autoAdvanceEnabled: autoAdvance)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            store.consumeSharedChanges()
        }
    }

    private var header: some View {
        HStack(spacing: GolfSpacing.xs) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.backward")
                    .font(.headline)
                    .frame(width: GolfMetrics.minimumHitTarget, height: GolfMetrics.minimumHitTarget)
            }
            .accessibilityLabel("Courses")

            Button { store.send(.previousHole) } label: {
                Image(systemName: "chevron.left")
                    .frame(width: GolfMetrics.minimumHitTarget, height: GolfMetrics.minimumHitTarget)
            }
            .accessibilityLabel("Previous hole")

            Menu {
                Picker("Hole", selection: Binding(get: { store.round.selectedHole }, set: { store.send(.selectHole($0)) })) {
                    ForEach(store.round.holes, id: \.self) { hole in
                        Text(holeMenuTitle(hole)).tag(hole)
                    }
                }
            } label: {
                VStack(spacing: 0) {
                    HStack(spacing: GolfSpacing.xxs) {
                        Text("Hole \(store.round.selectedHole)")
                        if store.round.isCurrentHoleLocked {
                            Image(systemName: "lock.fill").accessibilityLabel("Locked")
                        }
                        Image(systemName: "chevron.down").font(.caption.weight(.bold)).accessibilityHidden(true)
                    }
                    .font(.headline)
                    Text(holeSubtitle)
                        .font(.subheadline)
                        .foregroundStyle(.golfSecondaryText)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                }
                .frame(maxWidth: .infinity, minHeight: GolfMetrics.minimumHitTarget)
            }
            .accessibilityLabel("Hole \(store.round.selectedHole), \(holeSubtitle)")
            .accessibilityHint("Choose a hole")

            Button { store.send(.nextHole) } label: {
                Image(systemName: "chevron.right")
                    .frame(width: GolfMetrics.minimumHitTarget, height: GolfMetrics.minimumHitTarget)
            }
            .accessibilityLabel("Next hole")

            Menu {
                Button(store.round.isCurrentHoleLocked ? "Unlock hole" : "Lock hole", systemImage: store.round.isCurrentHoleLocked ? "lock.open" : "lock") {
                    store.send(.setLocked(hole: store.round.selectedHole, locked: !store.round.isCurrentHoleLocked))
                }
                Toggle("Auto-advance on green", systemImage: "forward", isOn: $autoAdvance)
                Toggle("Keep screen awake", systemImage: "sun.max", isOn: $keepAwake)
                if simulationEnabled || location.simulatedCoordinate != nil {
                    Section("Developer") {
                        if simulationEnabled {
                            Button("Simulate location", systemImage: "hand.tap") { placingSimulatedLocation = true }
                        }
                        if location.simulatedCoordinate != nil {
                            Button("Use real GPS", systemImage: "location") { location.simulatedCoordinate = nil }
                        }
                    }
                }
                Divider()
                Button("End round", systemImage: "flag.checkered", role: .destructive) { confirmEnd = true }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
                    .frame(width: GolfMetrics.minimumHitTarget, height: GolfMetrics.minimumHitTarget)
            }
            .accessibilityLabel("Round options")
        }
        .foregroundStyle(.golfPrimaryText)
        .padding(.horizontal, GolfSpacing.xs)
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        .background(.thickMaterial)
        .onChange(of: keepAwake) { _, value in UIApplication.shared.isIdleTimerDisabled = value }
    }

    private var holeSubtitle: String {
        var parts: [String] = []
        let par = store.round.currentPar
        if par > 0 { parts.append("Par \(par)") }
        let handicap = store.round.currentHandicap
        if handicap > 0 { parts.append("Hcp \(handicap)") }
        if let yards = store.hole.yardage { parts.append("\(yards) yd") }
        return parts.joined(separator: " · ")
    }

    private func holeMenuTitle(_ hole: String) -> String {
        let par = store.round.par(hole)
        let score = store.round.score(hole)
        var title = "Hole \(hole)"
        if par > 0 { title += " · Par \(par)" }
        if score > 0 { title += " · \(score)" }
        return title
    }
}
