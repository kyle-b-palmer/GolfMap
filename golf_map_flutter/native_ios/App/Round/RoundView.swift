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
    @AppStorage(SettingsKey.idealLineEnabled) private var idealLine = true
    @AppStorage(SettingsKey.bunkerDistancesOnMap) private var bunkerDistances = false
    @AppStorage(SettingsKey.showShotDispersion) private var dispersion = false
    @AppStorage(SettingsKey.healthWorkoutMode) private var healthMode = HealthWorkoutMode.always.rawValue
    @State private var askToStartWorkout = false
    @State private var savedRecap: RoundRecap?
    @State private var dockExpanded = true
    @State private var recenterToken = 0
    @State private var placement: MapPlacement?
    @State private var confirmEnd = false
    @State private var showingGreen = false

    private var layers: MapLayers {
        MapLayers(imagery: imagery, idealLine: idealLine, bunkerDistances: bunkerDistances, dispersion: dispersion)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            HoleMapView(
                store: store,
                user: location.coordinate,
                isSimulated: location.simulatedCoordinate != nil,
                layers: layers,
                recenterToken: recenterToken,
                onTap: handleMapTap
            )
            .overlay(alignment: .top) {
                Group {
                    if let placement {
                        PlacementBanner(placement.message) { self.placement = nil }
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
                    MapControlButton("Show whole hole", systemImage: "arrow.up.left.and.arrow.down.right") { recenterToken += 1 }
                    layersMenu
                    MapControlButton("Green close-up", systemImage: "flag") { showingGreen = true }
                }
                .padding(.trailing, GolfSpacing.m)
            }
        }
        .background(GolfMapPalette.courseBackground.color.ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) {
            YardageDock(store: store, gps: location.status, user: location.coordinate, expanded: $dockExpanded) {
                guard let origin = store.gpsOrigin(location.coordinate) else { return }
                store.markShot(at: origin, from: origin, source: .gps)
            } onLostBall: {
                guard let user = location.coordinate else { return }
                store.markShot(at: user, from: user, source: .lostBall)
            }
        }
        .fullScreenCover(isPresented: $showingGreen) {
            GreenCloseUpView(store: store, imagery: imagery)
        }
        #if DEBUG
        .task {
            // Screenshot automation, set like `GolfMapOpenCourse`.
            if UserDefaults.standard.string(forKey: "GolfMapRoundRoute") == "green" { showingGreen = true }
        }
        #endif
        .sensoryFeedback(.success, trigger: store.round.currentPins.count) { old, new in new > old }
        .sensoryFeedback(.impact, trigger: store.round.selectedHole)
        .confirmationDialog("End round?", isPresented: $confirmEnd, titleVisibility: .visible) {
            Button("Save round") {
                let recap = store.recapAsSaved
                store.finish()
                location.endRound()
                savedRecap = recap
            }
            Button("Discard round", role: .destructive) {
                store.discard()
                location.endRound()
                dismiss()
            }
        } message: {
            Text("Saving locks every hole. You can reopen a saved round later.")
        }
        .sheet(isPresented: Binding(get: { savedRecap != nil }, set: { if !$0 { savedRecap = nil } }), onDismiss: { dismiss() }) {
            if let savedRecap {
                NavigationStack { SavedRecapSheet(recap: savedRecap) }
            }
        }
        .alert("Start Apple Health workout?", isPresented: $askToStartWorkout) {
            Button("Not now", role: .cancel) {}
            Button("Start workout") { Task { await HealthWorkoutService.shared.start() } }
        } message: {
            Text("Track this round as a golf workout in Apple Health. You can change this in Settings.")
        }
        .onAppear {
            store.activate()
            location.start(inRound: true)
            UIApplication.shared.isIdleTimerDisabled = keepAwake
            startWorkoutIfNeeded()
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

    /// Once per round session, and never for a reopened round.
    private func startWorkoutIfNeeded() {
        let health = HealthWorkoutService.shared
        let session = store.round.sessionID
        guard !store.round.isReopened, health.isAvailable, !health.isRunning, !health.hasHandled(session: session) else { return }
        health.markHandled(session: session)
        switch HealthWorkoutMode(rawValue: healthMode) ?? .always {
        case .always: Task { await health.start() }
        case .ask: askToStartWorkout = true
        case .never: break
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
                if !store.round.isCurrentHoleLocked {
                    Button(store.clubAim == nil ? "Set club target" : "Move club target", systemImage: "scope") { placement = .clubAim }
                }
                if store.clubAim != nil {
                    Button("Clear club target", systemImage: "xmark.circle") { store.setClubAim(nil) }
                }
                if store.hole.tees.count > 1 {
                    Picker(selection: Binding(
                        get: { store.round.preferredTeeLabel ?? store.hole.tees.first?.label ?? "" },
                        set: { store.send(.setPreferredTee(label: $0)) }
                    )) {
                        ForEach(store.hole.tees, id: \.label) { tee in
                            Text(tee.label).tag(tee.label)
                        }
                    } label: {
                        Label("Tees", systemImage: "arrow.up.to.line")
                    }
                    .pickerStyle(.menu)
                }
                Toggle("Auto-advance on green", systemImage: "forward", isOn: $autoAdvance)
                Toggle("Keep screen awake", systemImage: "sun.max", isOn: $keepAwake)
                if simulationEnabled || location.simulatedCoordinate != nil {
                    Section("Developer") {
                        if simulationEnabled {
                            Button("Simulate location", systemImage: "hand.tap") { placement = .simulatedLocation }
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

    private var layersMenu: some View {
        Menu {
            Picker("Map style", selection: $imagery) {
                Label("Satellite", systemImage: "globe.americas").tag(true)
                Label("Map", systemImage: "map").tag(false)
            }
            .pickerStyle(.inline)
            Divider()
            Toggle("Ideal line", systemImage: "point.topleft.down.to.point.bottomright.curvepath", isOn: $idealLine)
            Toggle("Bunker distances", systemImage: "circle.dashed", isOn: $bunkerDistances)
            Toggle("Shot dispersion", systemImage: "circle.grid.cross", isOn: $dispersion)
        } label: {
            MapControlLabel(systemImage: "square.3.layers.3d")
        }
        .accessibilityLabel("Map layers")
        .onChange(of: bunkerDistances) { _, shown in
            guard shown else { return }
            if let reference = store.bunkerReference(location.coordinate) {
                if HoleGeometry.bunkerDistances(from: reference, store.hole.features).isEmpty { store.showMessage("No bunkers on this hole") }
            } else {
                store.showMessage("Need GPS, a tee, or a tracked shot for bunker distances")
            }
        }
        .onChange(of: dispersion) { _, shown in
            if shown, store.dispersion.isEmpty { store.showMessage("No saved shots on this hole yet") }
        }
    }

    /// A tap places whatever is pending; otherwise it adds a measurement point, as in Flutter.
    private func handleMapTap(_ coordinate: Coordinate) {
        switch placement {
        case .simulatedLocation:
            location.simulatedCoordinate = coordinate
            store.showMessage("Test GPS position set")
        case .clubAim:
            store.setClubAim(coordinate)
            if !store.round.isCurrentHoleLocked { store.showMessage("Club target set") }
        case nil:
            if store.selectedPinID != nil || store.selectedChainIndex != nil {
                store.selectedPinID = nil
                store.selectedChainIndex = nil
            } else if !store.round.isCurrentHoleLocked {
                store.addChainPoint(coordinate, user: location.coordinate)
            }
        }
        placement = nil
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

private enum MapPlacement {
    case simulatedLocation
    case clubAim

    var message: String {
        switch self {
        case .simulatedLocation: "Tap the map to set a simulated location"
        case .clubAim: "Tap the map where you want to land"
        }
    }
}
