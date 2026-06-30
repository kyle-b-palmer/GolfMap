import Foundation

struct GolfRoundGpsPin: Codable, Equatable {
    let hole: String
    let latitude: Double
    let longitude: Double
}

struct GolfRoundSharedState: Codable, Equatable {
    var holes: [String]
    var selectedHole: String
    var scores: [String: Int]
    var putts: [String: Int]
    var pars: [String: Int]
    var handicaps: [String: Int]
    var courseName: String
    var yardsToGreen: Int
    var revision: Int
    var pendingGpsPins: [GolfRoundGpsPin]
    var greenLatitude: Double
    var greenLongitude: Double
    var gpsRefreshRevision: Int

    static let storageKey = "golf_round_watch_state"
    static let watchConnectivityKey = "roundState"

    init(
        holes: [String] = [],
        selectedHole: String = "1",
        scores: [String: Int] = [:],
        putts: [String: Int] = [:],
        pars: [String: Int] = [:],
        handicaps: [String: Int] = [:],
        courseName: String = "",
        yardsToGreen: Int = -1,
        revision: Int = 0,
        pendingGpsPins: [GolfRoundGpsPin] = [],
        greenLatitude: Double = 0,
        greenLongitude: Double = 0,
        gpsRefreshRevision: Int = 0
    ) {
        self.holes = holes
        self.selectedHole = selectedHole
        self.scores = scores
        self.putts = putts
        self.pars = pars
        self.handicaps = handicaps
        self.courseName = courseName
        self.yardsToGreen = yardsToGreen
        self.revision = revision
        self.pendingGpsPins = pendingGpsPins
        self.greenLatitude = greenLatitude
        self.greenLongitude = greenLongitude
        self.gpsRefreshRevision = gpsRefreshRevision
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        holes = try container.decode([String].self, forKey: .holes)
        selectedHole = try container.decode(String.self, forKey: .selectedHole)
        scores = try container.decode([String: Int].self, forKey: .scores)
        putts = try container.decodeIfPresent([String: Int].self, forKey: .putts) ?? [:]
        pars = try container.decode([String: Int].self, forKey: .pars)
        handicaps = try container.decodeIfPresent([String: Int].self, forKey: .handicaps) ?? [:]
        courseName = try container.decode(String.self, forKey: .courseName)
        yardsToGreen = try container.decode(Int.self, forKey: .yardsToGreen)
        revision = try container.decode(Int.self, forKey: .revision)
        pendingGpsPins = try container.decodeIfPresent(
            [GolfRoundGpsPin].self,
            forKey: .pendingGpsPins
        ) ?? []
        greenLatitude = try container.decodeIfPresent(Double.self, forKey: .greenLatitude) ?? 0
        greenLongitude = try container.decodeIfPresent(Double.self, forKey: .greenLongitude) ?? 0
        gpsRefreshRevision = try container.decodeIfPresent(Int.self, forKey: .gpsRefreshRevision) ?? 0
    }

    var isActiveRound: Bool {
        !holes.isEmpty && !courseName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var currentPar: Int {
        pars[selectedHole] ?? 0
    }

    var currentHandicap: Int {
        handicaps[selectedHole] ?? 0
    }

    var currentHoleScore: Int {
        scores[selectedHole] ?? 0
    }

    var currentHolePutts: Int {
        putts[selectedHole] ?? 0
    }

    var totalPutts: Int {
        holes.reduce(0) { partial, hole in
            partial + (putts[hole] ?? 0)
        }
    }

    var totalScore: Int {
        holes.reduce(0) { partial, hole in
            partial + (scores[hole] ?? 0)
        }
    }

    var relativeToPar: Int {
        holes.reduce(0) { partial, hole in
            let score = scores[hole] ?? 0
            guard score > 0 else { return partial }
            let par = pars[hole] ?? 0
            guard par > 0 else { return partial }
            return partial + (score - par)
        }
    }

    func dictionaryPayload() -> [String: Any] {
        guard let data = try? JSONEncoder().encode(self),
              let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any] else {
            return [:]
        }
        return dictionary
    }

    static func fromDictionary(_ dictionary: [String: Any]) -> GolfRoundSharedState? {
        guard JSONSerialization.isValidJSONObject(dictionary),
              let data = try? JSONSerialization.data(withJSONObject: dictionary) else {
            return nil
        }
        return try? JSONDecoder().decode(GolfRoundSharedState.self, from: data)
    }
}

final class GolfRoundWatchStore {
    static let shared = GolfRoundWatchStore()

    private let defaults = UserDefaults.standard

    private init() {}

    func load() -> GolfRoundSharedState? {
        guard let data = defaults.data(forKey: GolfRoundSharedState.storageKey) else {
            return nil
        }
        return try? JSONDecoder().decode(GolfRoundSharedState.self, from: data)
    }

    func save(_ state: GolfRoundSharedState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        defaults.set(data, forKey: GolfRoundSharedState.storageKey)
    }

    func applyPhoneState(_ state: GolfRoundSharedState) {
        guard state.isActiveRound else { return }
        save(state)
    }

    @discardableResult
    func adjustCurrentHoleScore(by delta: Int) -> GolfRoundSharedState? {
        guard var state = load(), state.isActiveRound else { return nil }
        let hole = state.selectedHole
        let current = state.scores[hole] ?? 0
        state.scores[hole] = max(0, min(99, current + delta))
        state.revision += 1
        save(state)
        return state
    }

    @discardableResult
    func setCurrentHoleScore(to score: Int) -> GolfRoundSharedState? {
        guard var state = load(), state.isActiveRound else { return nil }
        let hole = state.selectedHole
        state.scores[hole] = max(0, min(99, score))
        state.revision += 1
        save(state)
        return state
    }

    @discardableResult
    func setCurrentHolePutts(to putts: Int) -> GolfRoundSharedState? {
        guard var state = load(), state.isActiveRound else { return nil }
        let hole = state.selectedHole
        state.putts[hole] = max(0, min(9, putts))
        state.revision += 1
        save(state)
        return state
    }

    @discardableResult
    func advanceHole() -> GolfRoundSharedState? {
        guard var state = load(), !state.holes.isEmpty else { return nil }
        let index = state.holes.firstIndex(of: state.selectedHole) ?? -1
        let nextIndex = index < 0 ? 0 : (index + 1) % state.holes.count
        state.selectedHole = state.holes[nextIndex]
        state.revision += 1
        save(state)
        return state
    }

    @discardableResult
    func retreatHole() -> GolfRoundSharedState? {
        guard var state = load(), !state.holes.isEmpty else { return nil }
        let index = state.holes.firstIndex(of: state.selectedHole) ?? 0
        let previousIndex = (index - 1 + state.holes.count) % state.holes.count
        state.selectedHole = state.holes[previousIndex]
        state.revision += 1
        save(state)
        return state
    }

    func updateWatchYardage(_ yards: Int) {
        guard var state = load() else { return }
        state.yardsToGreen = yards
        state.gpsRefreshRevision += 1
        save(state)
    }
}
