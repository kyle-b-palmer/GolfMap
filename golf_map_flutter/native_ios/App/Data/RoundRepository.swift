import Foundation
import GolfCore
import Observation
import os

/// Active round and saved rounds, one JSON file each under Application Support.
/// Legacy `SharedPreferences` rounds are imported in Phase 2.
@Observable
@MainActor
final class RoundRepository {
    private(set) var savedRounds: [SavedRound] = []
    private(set) var activeRound: RoundState?

    private let directory: URL
    private static let logger = Logger(subsystem: "com.golfmapapp.golfMapFlutter", category: "rounds")

    init(directory: URL? = nil) {
        let base = directory ?? URL.applicationSupportDirectory.appending(path: "Rounds", directoryHint: .isDirectory)
        self.directory = base
        try? FileManager.default.createDirectory(at: base.appending(path: "saved"), withIntermediateDirectories: true)
        activeRound = Self.read(RoundState.self, from: base.appending(path: "active-round.json"))
        savedRounds = Self.loadSaved(in: base.appending(path: "saved"))
    }

    func saveActive(_ round: RoundState) {
        activeRound = round
        write(round, to: directory.appending(path: "active-round.json"))
    }

    func discardActive() {
        activeRound = nil
        try? FileManager.default.removeItem(at: directory.appending(path: "active-round.json"))
    }

    func finish(_ round: RoundState) {
        let saved = round.savedRound()
        write(saved, to: directory.appending(path: "saved/\(saved.id).json"))
        savedRounds.removeAll { $0.id == saved.id }
        savedRounds.insert(saved, at: 0)
        discardActive()
    }

    func delete(_ round: SavedRound) {
        try? FileManager.default.removeItem(at: directory.appending(path: "saved/\(round.id).json"))
        savedRounds.removeAll { $0.id == round.id }
    }

    private func write<Value: Encodable>(_ value: Value, to url: URL) {
        do {
            let data = try JSONEncoder().encode(value)
            try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch {
            Self.logger.error("Write failed for \(url.lastPathComponent): \(error.localizedDescription)")
        }
    }

    private static func read<Value: Decodable>(_ type: Value.Type, from url: URL) -> Value? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            logger.error("Unreadable \(url.lastPathComponent): \(error.localizedDescription)")
            return nil
        }
    }

    private static func loadSaved(in folder: URL) -> [SavedRound] {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return files
            .filter { $0.pathExtension == "json" }
            .compactMap { read(SavedRound.self, from: $0) }
            .sorted { $0.playedAt.date > $1.playedAt.date }
    }
}
