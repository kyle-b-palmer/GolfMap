import GolfCore
import GolfDesign
import SwiftUI

/// Shareable images of a round, following Flutter's scorecard and recap cards. Always rendered dark.
enum RoundShareCard {
    case scorecard
    case recap

    var fileName: String { self == .scorecard ? "golf-scorecard.png" : "golf-round-recap.png" }
    var title: String { self == .scorecard ? "Scorecard" : "Round recap" }

    func subject(_ recap: RoundRecap) -> String {
        "\(recap.courseName) \(self == .scorecard ? "Scorecard" : "Round Recap")"
    }

    func message(_ recap: RoundRecap) -> String {
        let base = "\(recap.courseName) · \(recap.playedAt.formatted(.dateTime.month(.wide).day().year())) · \(recap.totalScore) (\(formatRelativeToPar(recap.relativeToPar)))"
        return self == .scorecard ? base : "\(base) · \(recap.trackedShots) tracked shots"
    }

    @MainActor @ViewBuilder
    func view(_ recap: RoundRecap) -> some View {
        switch self {
        case .scorecard: ScorecardShareCard(recap: recap)
        case .recap: RecapShareCard(recap: recap)
        }
    }

    /// Renders the card at 3x into a temporary PNG for `ShareLink`.
    @MainActor
    func render(_ recap: RoundRecap) -> (file: URL, image: UIImage)? {
        let renderer = ImageRenderer(content: view(recap).environment(\.colorScheme, .dark))
        renderer.scale = 3
        guard let image = renderer.uiImage, let data = image.pngData() else { return nil }
        let url = FileManager.default.temporaryDirectory.appending(path: fileName)
        do {
            try data.write(to: url, options: .atomic)
            return (url, image)
        } catch {
            return nil
        }
    }
}

private let cardGreen = Color(red: 0x4A / 255, green: 0xDE / 255, blue: 0x80 / 255)

private struct ScorecardShareCard: View {
    let recap: RoundRecap

    var body: some View {
        VStack(spacing: GolfSpacing.m) {
            VStack(spacing: GolfSpacing.xxs) {
                Text(recap.courseName.uppercased())
                    .font(.system(size: 18, weight: .heavy))
                    .tracking(1.1)
                    .foregroundStyle(cardGreen)
                    .multilineTextAlignment(.center)
                Text(recap.playedAt, format: .dateTime.month(.wide).day().year())
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.75))
            }
            HStack(spacing: 28) {
                stat("PAR", "\(recap.coursePar)")
                stat("SCORE", "\(recap.totalScore)")
                stat("+/-", formatRelativeToPar(recap.relativeToPar))
            }
            .padding(.horizontal, GolfSpacing.m)
            .padding(.vertical, GolfSpacing.s)
            .frame(maxWidth: .infinity)
            .background(cardGreen.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(cardGreen.opacity(0.35)))
            ScorecardGrid(
                holes: recap.lines.map { ScorecardHole(hole: $0.hole, par: $0.par, score: $0.score, putts: $0.putts) },
                scrolls: false
            )
            .font(.subheadline)
            footer
        }
        .padding(20)
        .frame(width: recap.lines.count > 9 ? 470 : 400)
        .background(
            LinearGradient(colors: [Color(red: 0x1A / 255, green: 0x33 / 255, blue: 0x28 / 255), Color(red: 0x12 / 255, green: 0x12 / 255, blue: 0x18 / 255)], startPoint: .top, endPoint: .bottom),
            in: RoundedRectangle(cornerRadius: 20)
        )
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(cardGreen.opacity(0.45)))
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(label).font(.caption2.weight(.bold)).foregroundStyle(.white.opacity(0.6))
            Text(value).font(GolfType.score(size: 26)).foregroundStyle(.white)
        }
    }
}

private struct RecapShareCard: View {
    let recap: RoundRecap

    var body: some View {
        VStack(alignment: .leading, spacing: GolfSpacing.m) {
            VStack(alignment: .leading, spacing: GolfSpacing.xxs) {
                Text(recap.courseName.uppercased())
                    .font(.system(size: 14, weight: .heavy))
                    .tracking(1.1)
                    .foregroundStyle(cardGreen)
                Text(recap.playedAt, format: .dateTime.month(.wide).day().year())
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
            }
            HStack(spacing: 10) {
                chip("SCORE", "\(recap.totalScore)")
                chip("VS PAR", formatRelativeToPar(recap.relativeToPar))
                chip("PINS", "\(recap.trackedShots)")
            }
            if recap.longestDriveYards != nil || recap.bestHole != nil {
                VStack(alignment: .leading, spacing: 2) {
                    if let yards = recap.longestDriveYards { Text("Longest drive: \(yards) yds") }
                    if let best = recap.bestHole { Text("Best hole: \(best)") }
                }
                .font(.footnote)
                .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: GolfSpacing.xs) {
                Text("Scorecard").font(.caption.weight(.bold)).foregroundStyle(.white.opacity(0.8))
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 6), alignment: .leading, spacing: 6) {
                    ForEach(recap.lines.filter { $0.score > 0 }, id: \.hole) { line in
                        Text("\(line.hole): \(line.score)")
                            .font(.caption2.weight(.semibold).monospacedDigit())
                            .foregroundStyle(.white)
                            .padding(.vertical, 4)
                            .frame(maxWidth: .infinity)
                            .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
            footer
        }
        .padding(20)
        .frame(width: 360, alignment: .leading)
        .background(
            LinearGradient(colors: [Color(red: 0x12 / 255, green: 0x14 / 255, blue: 0x1A / 255), Color(red: 0x1C / 255, green: 0x24 / 255, blue: 0x20 / 255)], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 18)
        )
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(cardGreen.opacity(0.45)))
    }

    private func chip(_ label: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(label).font(.system(size: 9, weight: .semibold)).foregroundStyle(.white.opacity(0.6))
            Text(value).font(.system(size: 16, weight: .heavy).monospacedDigit()).foregroundStyle(.white)
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
    }
}

private var footer: some View {
    Text("South Texas Golf Tracker")
        .font(.caption2)
        .foregroundStyle(.white.opacity(0.55))
        .frame(maxWidth: .infinity)
}

/// Renders the card once, then offers it to the share sheet.
struct RoundShareLink: View {
    let card: RoundShareCard
    let recap: RoundRecap
    var label: String?

    @State private var rendered: (file: URL, image: UIImage)?

    var body: some View {
        Group {
            if let rendered {
                ShareLink(
                    item: rendered.file,
                    subject: Text(card.subject(recap)),
                    message: Text(card.message(recap)),
                    preview: SharePreview(card.subject(recap), image: Image(uiImage: rendered.image))
                ) {
                    Label(label ?? "Share \(card.title.lowercased())", systemImage: "square.and.arrow.up")
                }
            } else {
                Label(label ?? "Share \(card.title.lowercased())", systemImage: "square.and.arrow.up")
                    .foregroundStyle(.secondary)
            }
        }
        .task(id: recap) { rendered = card.render(recap) }
    }
}
