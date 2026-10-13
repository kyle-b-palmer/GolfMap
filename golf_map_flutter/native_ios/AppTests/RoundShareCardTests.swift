import Foundation
import GolfCore
import Testing
@testable import GolfMap

@MainActor
@Suite("Share cards")
struct RoundShareCardTests {
    @Test func bothCardsRenderAtThreeTimesScale() throws {
        var round = RoundState.start(course: "Brackenridge Golf Course", features: [])
        round.holes = (1...18).map(String.init)
        round.pars = Dictionary(uniqueKeysWithValues: round.holes.map { ($0, [4, 3, 5][Int($0)! % 3]) })
        round.scores = Dictionary(uniqueKeysWithValues: round.holes.map { ($0, [4, 2, 6, 5, 3, 7][Int($0)! % 6]) })
        let recap = RoundRecap(round)

        for card in [RoundShareCard.scorecard, .recap] {
            let rendered = try #require(card.render(recap))
            #expect(rendered.image.scale == 3)
            #expect(rendered.image.size.width >= 360)
            #expect(FileManager.default.fileExists(atPath: rendered.file.path()))
            if let folder = ProcessInfo.processInfo.environment["GOLFMAP_SHARE_PREVIEW_DIR"] {
                try? FileManager.default.copyItem(at: rendered.file, to: URL(filePath: folder).appending(path: card.fileName))
            }
        }
        #expect(RoundShareCard.recap.message(recap).hasSuffix("· 0 tracked shots"))
    }
}
