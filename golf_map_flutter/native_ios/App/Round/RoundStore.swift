import Foundation
import GolfCore
import GolfDesign
import GolfSync
import Observation
import os

/// Per-hole geometry, recomputed only when the hole changes.
struct HoleContext: Equatable {
    var hole: String
    var features: [GolfFeature]
    var green: Coordinate?
    var orientation: HoleOrientation?
    var tees: [TeeOption]
    var yardage: Int?

    init(course: String, hole: String, courseFeatures: [GolfFeature], preferredTee: String?) {
        self.hole = hole
        features = HoleGeometry.features(courseFeatures, course: course, hole: hole)
        green = HoleGeometry.greenCenter(features)
        orientation = HoleGeometry.orientation(features)
        tees = HoleGeometry.teeOptions(features)
        let tee = preferredTee.flatMap { HoleGeometry.teeOption(features, label: $0) } ?? tees.first
        yardage = HoleGeometry.holeYardage(features, teeID: tee?.featureID)
    }
}

struct MapOverlay: Identifiable {
    var id: Int
    var coordinates: [Coordinate]
    var color: RGB
    var border: RGB
    var opacity: Double
    var isActive: Bool

    static func build(_ features: [GolfFeature], course: String, hole: String) -> [MapOverlay] {
        var overlays: [MapOverlay] = []
        for feature in features {
            guard let type = feature.featureType, let style = GolfMapPalette.fill(for: type) else { continue }
            let active = feature.isActive(course: course, hole: hole)
            for ring in feature.geometry.rings where ring.count >= 3 {
                overlays.append(MapOverlay(
                    id: overlays.count,
                    coordinates: ring,
                    color: style.color,
                    border: type == "tee" ? GolfMapPalette.teeBorder : style.color,
                    opacity: active ? style.active : style.inactive,
                    isActive: active
                ))
            }
        }
        // Active features draw last so they sit above neighbouring holes.
        return overlays.filter { !$0.isActive } + overlays.filter(\.isActive)
    }
}

/// Owns the active round: applies actions through `RoundEngine`, persists after every change,
/// and keeps the App Group snapshot (Watch and Live Activity) in step.
@Observable
@MainActor
final class RoundStore {
    private(set) var round: RoundState
    private(set) var hole: HoleContext {
        didSet { refreshMapContent() }
    }
    private(set) var mapOverlays: [MapOverlay] = []
    private(set) var holeLines: [[Coordinate]] = []
    private(set) var banner: String?
    private(set) var weather: WeatherConditions?
    private(set) var dispersion: [DispersionPoint] = []
    var selectedPinID: String? {
        didSet { if selectedPinID != nil { selectedChainIndex = nil } }
    }
    var selectedChainIndex: Int? {
        didSet { if selectedChainIndex != nil { selectedPinID = nil } }
    }

    let courseFeatures: [GolfFeature]
    private let repository: RoundRepository
    private let shared: SharedRoundStore
    private let weatherService: WeatherService
    private var weatherTask: Task<Void, Never>?
    private var autoAdvance = AutoAdvanceTracker()
    private var lastPublishedRevision = 0
    private var lastPublishedYards: Int?
    private var observer: DarwinNotificationObserver?
    private var bannerTask: Task<Void, Never>?

    private static let logger = Logger(subsystem: "com.golfmapapp.golfMapFlutter", category: "round")

    init(
        round: RoundState,
        courseFeatures: [GolfFeature],
        repository: RoundRepository,
        shared: SharedRoundStore = .shared,
        weatherService: WeatherService = .shared
    ) {
        self.round = round
        self.courseFeatures = courseFeatures
        self.repository = repository
        self.shared = shared
        self.weatherService = weatherService
        hole = HoleContext(course: round.courseName, hole: round.selectedHole, courseFeatures: courseFeatures, preferredTee: round.preferredTeeLabel)
        refreshMapContent()
    }

    private func refreshMapContent() {
        mapOverlays = MapOverlay.build(courseFeatures, course: round.courseName, hole: hole.hole)
        holeLines = hole.features.filter { $0.isType("hole") }.flatMap(\.geometry.lineStrings)
        dispersion = ShotDispersion.points(rounds: repository.savedRounds, courseName: round.courseName, hole: hole.hole)
    }

    // MARK: Measurement chain and club target

    var chain: [MeasurementChainPoint] { round.measurementChains[round.selectedHole] ?? [] }
    var clubAim: Coordinate? { round.clubAim[round.selectedHole] }

    /// Chain segments start at the player. Without a fix they start at the selected tee, where Flutter left them at zero.
    func chainOrigin(_ user: Coordinate?) -> Coordinate? {
        guard !round.isCurrentHoleLocked else { return nil }
        return user ?? selectedTeePoint
    }

    private var selectedTeePoint: Coordinate? {
        round.preferredTeeLabel.flatMap { HoleGeometry.teeOption(hole.features, label: $0)?.point } ?? hole.tees.first?.point
    }

    func addChainPoint(_ point: Coordinate, user: Coordinate?) {
        guard !round.isCurrentHoleLocked else { return }
        selectedPinID = nil
        selectedChainIndex = nil
        setChain(MeasurementChain.adding(point, to: chain), user: user)
    }

    func moveChainPoint(_ index: Int, to point: Coordinate, user: Coordinate?) {
        guard !round.isCurrentHoleLocked else { return }
        setChain(MeasurementChain.moving(chain, index: index, to: point), user: user)
    }

    func deleteChainPoint(_ index: Int, user: Coordinate?) {
        guard !round.isCurrentHoleLocked else { return }
        selectedChainIndex = nil
        setChain(MeasurementChain.removing(chain, index: index), user: user)
    }

    func clearChain() {
        selectedChainIndex = nil
        send(.setMeasurementChain(hole: round.selectedHole, points: []))
    }

    /// Segment lengths from where the player stands now; the stored chain updates only when edited.
    func displayChain(user: Coordinate?) -> [MeasurementChainPoint] {
        MeasurementChain.recalculated(chain, origin: chainOrigin(user))
    }

    private func setChain(_ points: [MeasurementChainPoint], user: Coordinate?) {
        send(.setMeasurementChain(hole: round.selectedHole, points: MeasurementChain.recalculated(points, origin: chainOrigin(user))))
    }

    func setClubAim(_ point: Coordinate?) {
        if round.isCurrentHoleLocked {
            show("Unlock the hole to set a club target")
            return
        }
        send(.setClubAim(hole: round.selectedHole, point: point))
    }

    /// Where bunker distances are measured from, in Flutter's order of preference.
    func bunkerReference(_ user: Coordinate?) -> Coordinate? {
        let lastTracked = round.lastTrackedPoint(round.selectedHole)
        if round.isCurrentHoleLocked { return lastTracked }
        if let origin = gpsOrigin(user) { return origin }
        return lastTracked ?? selectedTeePoint ?? HoleGeometry.longestTee(hole.features) ?? user
    }

    /// Flutter shows the ideal line only on an unlocked hole with no measurement chain.
    var showsIdealLine: Bool { !round.isCurrentHoleLocked && chain.isEmpty }

    func activate() {
        repository.saveActive(round)
        publish(yardsToGreen: nil)
        observer = DarwinNotificationObserver(name: GolfRoundSharedState.changedNotification) { [weak self] in
            MainActor.assumeIsolated { self?.consumeSharedChanges() }
        }
    }

    func deactivate() {
        observer = nil
    }

    // MARK: Actions

    func send(_ action: RoundAction) {
        let transition = RoundEngine.apply(action, to: round)
        guard transition.changed || !transition.effects.isEmpty else { return }
        round = transition.state
        var undos: [GolfRoundGpsPin] = []
        for effect in transition.effects {
            switch effect {
            case .message(let text):
                show(text)
            case .pinAdded(_, let shotNumber, let yards):
                show(yards.map { "Shot \(shotNumber) · \($0) yd to green" } ?? "Shot \(shotNumber) marked")
            case .pinRejectedHoleLocked:
                show("Unlock the hole to add shots")
            case .pinIgnoredDuplicate:
                break
            case .pinRemoved(let hole, let pin):
                undos.append(PhoneRoundSync.undoEntry(for: pin, hole: hole))
                if selectedPinID == pin.id { selectedPinID = nil }
            case .holeChanged:
                break
            }
        }
        if hole.hole != round.selectedHole || isPreferredTeeChange(action) {
            hole = HoleContext(course: round.courseName, hole: round.selectedHole, courseFeatures: courseFeatures, preferredTee: round.preferredTeeLabel)
            selectedPinID = nil
            selectedChainIndex = nil
            autoAdvance = AutoAdvanceTracker()
        }
        if transition.changed {
            repository.saveActive(round)
            publish(yardsToGreen: lastPublishedYards, extraUndos: undos)
        }
    }

    private func isPreferredTeeChange(_ action: RoundAction) -> Bool {
        if case .setPreferredTee = action { return true }
        return false
    }

    func markShot(at point: Coordinate, from user: Coordinate?, source: PinSource) {
        send(.addPin(
            hole: round.selectedHole,
            point: point,
            source: source,
            userLocation: user,
            yardsToPin: yardsToGreen(from: point, features: hole.features),
            teeLabel: round.preferredTeeLabel
        ))
    }

    func finish() {
        send(.lockAllHoles)
        repository.finish(round, features: courseFeatures)
        shared.clear()
        deactivate()
    }

    func discard() {
        repository.discardActive()
        shared.clear()
        deactivate()
    }

    // MARK: Location

    /// The fix used for distances: only within 1,200 yards of the hole, as in the Flutter app.
    func gpsOrigin(_ user: Coordinate?) -> Coordinate? {
        HoleGeometry.shotOrigin(user: user, hole.features)
    }

    func yardages(from origin: Coordinate?) -> GreenYardages? {
        guard let origin, hole.green != nil else { return nil }
        return HoleGeometry.greenYardages(from: origin, hole.features)
    }

    /// Plays-like yardage to the middle of the green and the club for it; raw yardage when weather is missing.
    func shotAdvice(from origin: Coordinate?, clubs: [ClubDistance]) -> ShotAdvice? {
        guard let origin else { return nil }
        return ShotAdvice.make(
            actualYards: yardages(from: origin)?.middle,
            origin: origin,
            greenCenter: hole.green,
            weather: weather,
            clubs: clubs,
            onTeeBox: HoleGeometry.isOnTeeBox(origin, hole.features),
            hasTrackedShots: !round.currentPins.isEmpty
        )
    }

    /// Called for each new fix: keeps the shared yardage current, refreshes weather, and runs auto-advance.
    /// Auto-advance skips one-hole courses (as Flutter does) and stops on the final hole rather than wrapping to the first.
    func locationChanged(_ user: Coordinate?, autoAdvanceEnabled: Bool, now: Date = .now) {
        let origin = gpsOrigin(user)
        let yards = yardages(from: origin)?.middle
        if yards != lastPublishedYards {
            publish(yardsToGreen: yards)
        }
        if let origin { refreshWeather(at: origin) }
        guard autoAdvanceEnabled, let user, round.holes.count > 1, round.selectedHole != round.holes.last else { return }
        if autoAdvance.update(onGreen: HoleGeometry.isPointInGreen(user, hole.features), now: now) {
            send(.nextHole)
            show("Advanced to hole \(round.selectedHole)")
        }
    }

    /// The service caches for 15 minutes within 500 m, so this only reaches the network occasionally.
    private func refreshWeather(at origin: Coordinate) {
        guard weatherTask == nil else { return }
        let service = weatherService
        weatherTask = Task { [weak self] in
            let conditions = await service.conditions(at: origin)
            guard let self else { return }
            if conditions != weather { weather = conditions }
            weatherTask = nil
        }
    }

    // MARK: Shared state

    private func publish(yardsToGreen: Int?, extraUndos: [GolfRoundGpsPin] = [], clearPending: Bool = false) {
        let round = round
        let green = hole.green
        let updated = shared.update { previous in
            var snapshot = PhoneRoundSync.snapshot(of: round, yardsToGreen: yardsToGreen, green: green, previous: previous)
            if clearPending {
                snapshot.pendingGpsPins = []
                snapshot.pendingGpsPinUndos = []
            }
            snapshot.pendingGpsPinUndos.append(contentsOf: extraUndos)
            return snapshot
        }
        shared.activeSessionId = round.sessionID
        lastPublishedYards = yardsToGreen
        if let updated { lastPublishedRevision = updated.revision }
    }

    /// Applies edits made by the Live Activity or Watch since the phone last published.
    func consumeSharedChanges() {
        guard let changes = shared.load(), changes.revision > lastPublishedRevision else { return }
        let actions = PhoneRoundSync.actions(for: changes, round: round)
        Self.logger.info("Applying \(actions.count) shared actions from revision \(changes.revision)")
        for action in actions {
            send(withPinYardage(action))
        }
        publish(yardsToGreen: lastPublishedYards, clearPending: true)
    }

    private func withPinYardage(_ action: RoundAction) -> RoundAction {
        guard case let .addPin(pinHole, point, source, user, nil, tee) = action else { return action }
        let features = pinHole == hole.hole ? hole.features : HoleGeometry.features(courseFeatures, course: round.courseName, hole: pinHole)
        return .addPin(hole: pinHole, point: point, source: source, userLocation: user, yardsToPin: yardsToGreen(from: point, features: features), teeLabel: tee)
    }

    private func yardsToGreen(from point: Coordinate, features: [GolfFeature]) -> Int? {
        HoleGeometry.greenCenter(features) == nil ? nil : HoleGeometry.greenYardages(from: point, features).middle
    }

    func showMessage(_ message: String) { show(message) }

    private func show(_ message: String) {
        banner = message
        bannerTask?.cancel()
        bannerTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            self?.banner = nil
        }
    }
}
