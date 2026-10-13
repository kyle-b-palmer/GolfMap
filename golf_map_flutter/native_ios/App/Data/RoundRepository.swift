import Foundation
import GolfCore
import Observation
import os

/// Active round and saved rounds, one JSON file each under Application Support.
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
        write(saved, to: savedURL(saved.id))
        savedRounds.removeAll { $0.id == saved.id }
        savedRounds.insert(saved, at: 0)
        discardActive()
    }

    func delete(_ round: SavedRound) {
        try? FileManager.default.removeItem(at: savedURL(round.id))
        savedRounds.removeAll { $0.id == round.id }
    }

    /// Writes rounds that don't exist yet, leaving native copies alone so a retried import changes nothing.
    /// Returns how many were written.
    @discardableResult
    func importLegacy(_ rounds: [SavedRound]) -> Int {
        var written = 0
        for round in rounds where !FileManager.default.fileExists(atPath: savedURL(round.id).path) {
            write(round, to: savedURL(round.id))
            written += 1
        }
        savedRounds = Self.loadSaved(in: directory.appending(path: "saved"))
        return written
    }

    /// When the active round last changed, for deciding whether to restore it at launch.
    var activeRoundSavedAt: Date? {
        guard activeRound != nil else { return nil }
        let attributes = try? FileManager.default.attributesOfItem(atPath: directory.appending(path: "active-round.json").path)
        return attributes?[.modificationDate] as? Date
    }

    func hasSavedRound(id: String) -> Bool {
        FileManager.default.fileExists(atPath: savedURL(id).path)
    }

    /// Round IDs come from storage; percent-encoding keeps them inside the folder and distinct.
    private func savedURL(_ id: String) -> URL {
        let safe = id.addingPercentEncoding(withAllowedCharacters: Self.fileNameCharacters) ?? UUID().uuidString
        return directory.appending(path: "saved/\(safe).json")
    }

    private static let fileNameCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))

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
