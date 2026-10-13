import Foundation

/// Complete in-progress round. Changed only through `RoundEngine.apply`.
public struct RoundState: Codable, Hashable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var id: String
    public var courseName: String
    public var playedAt: DartDate
    /// True when the round was reopened from history; saving keeps its ID and date.
    public var isReopened: Bool
    public var holes: [String]
    public var pars: [String: Int]
    public var handicaps: [String: Int]
    public var selectedHole: String
    public var scores: [String: Int]
    public var putts: [String: Int]
    public var pinnedShots: [String: [PinnedShot]]
    public var measurementChains: [String: [MeasurementChainPoint]]
    public var lockedHoles: Set<String>
    public var preferredTeeLabel: String?
    public var scoreTarget: Int?
    public var clubAim: [String: Coordinate]
    public var sessionID: String
    /// Incremented on every change other devices should see.
    public var revision: Int
    /// Recently applied remote event IDs, used to drop duplicate deliveries.
    public var appliedEventIDs: [String]

    public init(
        id: String,
        courseName: String,
        playedAt: DartDate,
        holes: [String],
        pars: [String: Int],
        handicaps: [String: Int],
        isReopened: Bool = false,
        sessionID: String = UUID().uuidString
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.id = id
        self.courseName = courseName
        self.playedAt = playedAt
        self.isReopened = isReopened
        self.holes = holes
        self.pars = pars
        self.handicaps = handicaps
        self.selectedHole = holes.first ?? "1"
        self.scores = Dictionary(uniqueKeysWithValues: holes.map { ($0, 0) })
        self.putts = Dictionary(uniqueKeysWithValues: holes.map { ($0, 0) })
        self.pinnedShots = [:]
        self.measurementChains = [:]
        self.lockedHoles = []
        self.preferredTeeLabel = nil
        self.scoreTarget = nil
        self.clubAim = [:]
        self.sessionID = sessionID
        self.revision = 0
        self.appliedEventIDs = []
    }

    /// Starts a new round on a course.
    public static func start(course: String, features: [GolfFeature], now: Date = Date(), sessionID: String = UUID().uuidString) -> RoundState {
        let holes = CourseCatalog.holes(features, course: course)
        var pars: [String: Int] = [:], handicaps: [String: Int] = [:]
        for hole in holes {
            let stats = CourseCatalog.stats(features, course: course, hole: hole)
            pars[hole] = stats?.par ?? 0
            handicaps[hole] = stats?.handicap ?? 0
        }
        let id = String(Int64(now.timeIntervalSince1970 * 1000))
        return RoundState(
            id: id,
            courseName: course,
            playedAt: DartDate(date: now, isUTC: false),
            holes: holes,
            pars: pars,
            handicaps: handicaps,
            sessionID: sessionID
        )
    }

    /// Reopens a saved round; holes missing a stored score start at zero.
    public static func reopen(_ saved: SavedRound, features: [GolfFeature], sessionID: String = UUID().uuidString) -> RoundState {
        var state = start(course: saved.courseName, features: features, sessionID: sessionID)
        state.id = saved.id
        state.playedAt = saved.playedAt
        state.isReopened = true
        for (hole, value) in saved.scores { state.scores[hole] = value }
        for (hole, value) in saved.putts { state.putts[hole] = value }
        state.pinnedShots = saved.pinnedShots
        state.measurementChains = saved.measurementChains
        state.lockedHoles = saved.lockedHoles
        return state
    }

    // MARK: Derived values

    public func score(_ hole: String) -> Int { scores[hole] ?? 0 }
    public func putts(_ hole: String) -> Int { putts[hole] ?? 0 }
    public func par(_ hole: String) -> Int { pars[hole] ?? 0 }
    public var currentScore: Int { score(selectedHole) }
    public var currentPutts: Int { putts(selectedHole) }
    public var currentPar: Int { par(selectedHole) }
    public var currentHandicap: Int { handicaps[selectedHole] ?? 0 }
    public var isCurrentHoleLocked: Bool { lockedHoles.contains(selectedHole) }

    public var totalScore: Int { holes.reduce(0) { $0 + score($1) } }
    public var totalPutts: Int { holes.reduce(0) { $0 + putts($1) } }
    public var coursePar: Int { holes.reduce(0) { $0 + par($1) } }
    public var effectiveScoreTarget: Int { scoreTarget ?? coursePar }
    public var strokesRemainingForTarget: Int { effectiveScoreTarget - totalScore }

    /// Relative to par over holes that have both a score and a par.
    public var totalRelativeToPar: Int {
        holes.reduce(0) { sum, hole in
            let s = score(hole), p = par(hole)
            guard s > 0, p > 0 else { return sum }
            return sum + (s - p)
        }
    }

    public var currentRelativeToPar: Int {
        let s = currentScore, p = currentPar
        if s <= 0 || p <= 0 || s == p { return 0 }
        return s - p
    }

    /// Holes left after the selected one.
    public var holesToPlay: Int {
        if let index = holes.firstIndex(of: selectedHole) { return max(0, holes.count - index - 1) }
        if let number = Int(selectedHole), !holes.isEmpty { return max(0, holes.count - number) }
        return 0
    }

    public func sortedPins(_ hole: String) -> [PinnedShot] {
        stableSorted(pinnedShots[hole] ?? []) { $0.shotNumber < $1.shotNumber }
    }

    public var currentPins: [PinnedShot] { sortedPins(selectedHole) }

    /// Last tracked position on a hole (excluding lost balls), falling back to the measurement chain.
    public func lastTrackedPoint(_ hole: String) -> Coordinate? {
        if let pin = sortedPins(hole).last(where: { $0.pinType != .lostBall }) { return pin.coordinate }
        return measurementChains[hole]?.last?.coordinate
    }

    /// Saved-history record. Saving locks every hole, as the Flutter app does.
    public func savedRound() -> SavedRound {
        SavedRound(
            id: id,
            courseName: courseName,
            playedAt: playedAt,
            scores: Dictionary(uniqueKeysWithValues: holes.map { ($0, score($0)) }),
            putts: Dictionary(uniqueKeysWithValues: holes.map { ($0, putts($0)) }),
            pinnedShots: pinnedShots.filter { !$0.value.isEmpty },
            measurementChains: measurementChains.filter { !$0.value.isEmpty },
            lockedHoles: lockedHoles.union(holes)
        )
    }
}

public enum PinSource: Hashable, Sendable {
    case gps
    case map
    /// Phone lost-ball action: adds a lost-ball pin and one penalty stroke.
    case lostBall
    /// Pin reported by the Watch or Live Activity. Scores arrive separately with the shared state.
    case remote(eventID: String?, lostBall: Bool)
}

public enum RoundAction: Hashable, Sendable {
    case setScore(hole: String, strokes: Int)
    case adjustScore(hole: String, delta: Int)
    case setPutts(hole: String, putts: Int)
    case selectHole(String)
    case nextHole
    case previousHole
    /// `yardsToPin` is computed by the caller from course geometry.
    case addPin(hole: String, point: Coordinate, source: PinSource, userLocation: Coordinate?, yardsToPin: Int?, teeLabel: String?)
    case deletePin(hole: String, id: String)
    case clearPins(hole: String)
    case setMeasurementChain(hole: String, points: [MeasurementChainPoint])
    case setLocked(hole: String, locked: Bool)
    case lockAllHoles
    case setScoreTarget(Int?)
    case setClubAim(hole: String, point: Coordinate?)
    case setPreferredTee(label: String?)
    /// Scores/putts/hole from the shared Watch and widget state (the phone takes them as given).
    case applyRemoteTotals(scores: [String: Int], putts: [String: Int], selectedHole: String?)
    /// Remote undo of a pin: by event ID only when one is given (version 2), otherwise the last pin within 25 yards.
    case applyRemoteUndo(hole: String, point: Coordinate, pinEventID: String?)
}

public enum RoundEffect: Hashable, Sendable {
    case message(String)
    case pinAdded(hole: String, shotNumber: Int, yards: Int?)
    case pinRejectedHoleLocked
    case pinIgnoredDuplicate
    /// A phone deletion other devices must learn about.
    case pinRemoved(hole: String, pin: PinnedShot)
    case holeChanged(String)
}

public struct RoundTransition: Sendable {
    public var state: RoundState
    public var effects: [RoundEffect]
    public var changed: Bool
}

public enum RoundEngine {
    public static let remotePinDedupYards = 25
    public static let maxRememberedEvents = 200

    public static func apply(_ action: RoundAction, to input: RoundState) -> RoundTransition {
        var state = input
        var effects: [RoundEffect] = []

        switch action {
        case .setScore(let hole, let strokes):
            state.scores[hole] = min(max(strokes, 0), 99)

        case .adjustScore(let hole, let delta):
            state.scores[hole] = min(max(state.score(hole) + delta, 0), 99)

        case .setPutts(let hole, let putts):
            state.putts[hole] = min(max(putts, 0), 9)

        case .selectHole(let hole):
            guard state.holes.contains(hole) else { break }
            state.selectedHole = hole
            effects.append(.holeChanged(hole))

        case .nextHole:
            guard !state.holes.isEmpty else { break }
            let index = state.holes.firstIndex(of: state.selectedHole)
            state.selectedHole = state.holes[index.map { ($0 + 1) % state.holes.count } ?? 0]
            effects.append(.holeChanged(state.selectedHole))

        case .previousHole:
            guard !state.holes.isEmpty else { break }
            let index = state.holes.firstIndex(of: state.selectedHole) ?? 0
            state.selectedHole = state.holes[(index - 1 + state.holes.count) % state.holes.count]
            effects.append(.holeChanged(state.selectedHole))

        case let .addPin(hole, point, source, userLocation, yardsToPin, teeLabel):
            if hole == state.selectedHole && state.isCurrentHoleLocked {
                effects.append(.pinRejectedHoleLocked)
                return RoundTransition(state: input, effects: effects, changed: false)
            }
            var pins = state.sortedPins(hole)
            var eventID: String?
            var pinType: PinType = source == .lostBall ? .lostBall : .shot

            if case .remote(let id, let lostBall) = source {
                eventID = id
                pinType = lostBall ? .lostBall : .shot
                if let id, state.appliedEventIDs.contains(id) {
                    effects.append(.pinIgnoredDuplicate)
                    return RoundTransition(state: input, effects: effects, changed: false)
                }
                if !lostBall, pins.contains(where: { GeoMath.yardsBetween($0.coordinate, point) < remotePinDedupYards }) {
                    effects.append(.pinIgnoredDuplicate)
                    if let id { remember(id, in: &state) }
                    return RoundTransition(state: state, effects: effects, changed: state != input)
                }
            }

            let from: Coordinate
            var shotYards: Int?
            if let previous = pins.last {
                from = previous.coordinate
                shotYards = GeoMath.yardsBetween(from, point)
            } else {
                from = userLocation ?? point
                if let userLocation {
                    let yards = GeoMath.yardsBetween(userLocation, point)
                    shotYards = yards < 1 ? nil : yards
                }
            }

            let shot = PinnedShot(
                id: eventID ?? UUID().uuidString,
                shotNumber: pins.count + 1,
                latitude: point.latitude,
                longitude: point.longitude,
                fromLatitude: from.latitude,
                fromLongitude: from.longitude,
                teeLabel: teeLabel,
                shotYards: shotYards,
                yardsToPin: yardsToPin,
                pinType: pinType
            )
            pins.append(shot)
            state.pinnedShots[hole] = pins
            if source == .lostBall {
                state.scores[hole] = state.score(hole) + 1
            }
            if let eventID { remember(eventID, in: &state) }
            effects.append(.pinAdded(hole: hole, shotNumber: shot.shotNumber, yards: shotYards))

        case .deletePin(let hole, let id):
            guard !state.lockedHoles.contains(hole) else { break }
            var pins = state.sortedPins(hole)
            guard let index = pins.firstIndex(where: { $0.id == id }) else { break }
            let removed = pins.remove(at: index)
            setRenumbered(pins, hole: hole, in: &state)
            if state.score(hole) > 0 {
                state.scores[hole] = state.score(hole) - 1
            }
            effects.append(.pinRemoved(hole: hole, pin: removed))

        case .clearPins(let hole):
            guard !(state.pinnedShots[hole] ?? []).isEmpty else { break }
            state.pinnedShots[hole] = nil

        case .setMeasurementChain(let hole, let points):
            state.measurementChains[hole] = points.isEmpty ? nil : points

        case .setLocked(let hole, let locked):
            if locked { state.lockedHoles.insert(hole) } else { state.lockedHoles.remove(hole) }

        case .lockAllHoles:
            state.lockedHoles.formUnion(state.holes)

        case .setScoreTarget(let target):
            state.scoreTarget = target

        case .setClubAim(let hole, let point):
            guard !state.lockedHoles.contains(hole) else { break }
            state.clubAim[hole] = point

        case .setPreferredTee(let label):
            state.preferredTeeLabel = label

        case let .applyRemoteTotals(scores, putts, selectedHole):
            for (hole, value) in scores { state.scores[hole] = value }
            for (hole, value) in putts { state.putts[hole] = value }
            if let selectedHole, selectedHole != state.selectedHole, state.holes.contains(selectedHole) {
                state.selectedHole = selectedHole
                effects.append(.holeChanged(selectedHole))
            }

        case let .applyRemoteUndo(hole, point, pinEventID):
            var pins = state.sortedPins(hole)
            let index: Int?
            if let pinEventID {
                index = pins.lastIndex { $0.id == pinEventID }
            } else {
                index = pins.lastIndex { GeoMath.yardsBetween($0.coordinate, point) < remotePinDedupYards }
            }
            guard let index else { break }
            pins.remove(at: index)
            setRenumbered(pins, hole: hole, in: &state)
            effects.append(.message("Undid last swing pin on hole \(hole)"))
        }

        let changed = state != input
        if changed { state.revision = input.revision + 1 }
        return RoundTransition(state: state, effects: effects, changed: changed)
    }

    private static func setRenumbered(_ pins: [PinnedShot], hole: String, in state: inout RoundState) {
        let renumbered = pins.enumerated().map { index, pin -> PinnedShot in
            var copy = pin
            copy.shotNumber = index + 1
            return copy
        }
        state.pinnedShots[hole] = renumbered.isEmpty ? nil : renumbered
    }

    private static func remember(_ eventID: String, in state: inout RoundState) {
        state.appliedEventIDs.append(eventID)
        if state.appliedEventIDs.count > maxRememberedEvents {
            state.appliedEventIDs.removeFirst(state.appliedEventIDs.count - maxRememberedEvents)
        }
    }
}

/// Advances once the player has stayed on the green for more than 12 seconds.
public struct AutoAdvanceTracker: Hashable, Sendable {
    public static let dwell: TimeInterval = 12

    public private(set) var enteredGreenAt: Date?
    public private(set) var triggered = false

    public init() {}

    public mutating func reset() {
        enteredGreenAt = nil
        triggered = false
    }

    /// Returns true exactly once per green visit when the dwell time is exceeded.
    public mutating func update(onGreen: Bool, now: Date) -> Bool {
        guard onGreen else {
            reset()
            return false
        }
        let entered = enteredGreenAt ?? now
        enteredGreenAt = entered
        guard !triggered, now.timeIntervalSince(entered) > Self.dwell else { return false }
        triggered = true
        return true
    }
}
