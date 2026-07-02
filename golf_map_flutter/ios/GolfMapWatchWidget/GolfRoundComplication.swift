import Foundation
import SwiftUI
import WidgetKit

private let appGroupId = "group.com.golfmapapp.golfMapFlutter"
private let snapshotKey = "golf_watch_complication_snapshot"

private struct ComplicationSnapshot: Codable {
    var courseName: String
    var hole: String
    var yardsToGreen: Int
    var holeScore: Int
    var totalScore: Int
    var updatedAt: Date
}

private enum ComplicationSnapshotStore {
    static func load() -> ComplicationSnapshot? {
        guard let defaults = UserDefaults(suiteName: appGroupId),
              let data = defaults.data(forKey: snapshotKey) else {
            return nil
        }
        return try? JSONDecoder().decode(ComplicationSnapshot.self, from: data)
    }
}

struct GolfRoundComplicationEntry: TimelineEntry {
    let date: Date
    let hole: String
    let yards: Int
    let score: Int
}

struct GolfRoundComplicationProvider: TimelineProvider {
    func placeholder(in context: Context) -> GolfRoundComplicationEntry {
        GolfRoundComplicationEntry(date: Date(), hole: "1", yards: 150, score: 0)
    }

    func getSnapshot(in context: Context, completion: @escaping (GolfRoundComplicationEntry) -> Void) {
        completion(currentEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<GolfRoundComplicationEntry>) -> Void) {
        let entry = currentEntry()
        let timeline = Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(60)))
        completion(timeline)
    }

    private func currentEntry() -> GolfRoundComplicationEntry {
        if let payload = ComplicationSnapshotStore.load() {
            return GolfRoundComplicationEntry(
                date: payload.updatedAt,
                hole: payload.hole,
                yards: max(payload.yardsToGreen, 0),
                score: payload.holeScore
            )
        }
        return GolfRoundComplicationEntry(date: Date(), hole: "—", yards: -1, score: 0)
    }
}

struct GolfRoundComplicationView: View {
    let entry: GolfRoundComplicationEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Text("HOLE \(entry.hole)")
                    .font(.caption2.weight(.bold))
                if entry.yards >= 0 {
                    Text("\(entry.yards) YDS")
                        .font(.headline.weight(.bold))
                } else {
                    Text("GOLF")
                        .font(.headline.weight(.bold))
                }
                if entry.score > 0 {
                    Text("Score \(entry.score)")
                        .font(.caption2)
                }
            }
        case .accessoryCircular:
            VStack(spacing: 0) {
                Text(entry.hole)
                    .font(.caption2.weight(.bold))
                if entry.yards >= 0 {
                    Text("\(entry.yards)")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                }
            }
        default:
            Text(entry.yards >= 0 ? "H\(entry.hole) · \(entry.yards)" : "Golf")
                .font(.caption)
        }
    }
}

struct GolfRoundComplicationWidget: Widget {
    let kind = "GolfRoundComplication"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: GolfRoundComplicationProvider()) { entry in
            GolfRoundComplicationView(entry: entry)
        }
        .configurationDisplayName("Golf Round")
        .description("Hole and distance to green.")
        .supportedFamilies([
            .accessoryRectangular,
            .accessoryCircular,
        ])
    }
}
