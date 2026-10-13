import SwiftUI

/// Traditional scorecard marks: circles under par, squares over par, doubled at two or more.
public struct ScoreMark: View {
    let score: Int
    let par: Int

    public init(score: Int, par: Int) {
        self.score = score
        self.par = par
    }

    private var relative: Int { score > 0 && par > 0 ? score - par : 0 }

    public var body: some View {
        Text(score > 0 ? "\(score)" : "–")
            .font(.body.weight(.bold).monospacedDigit())
            .frame(minWidth: 26, minHeight: 26)
            .overlay { mark }
            .accessibilityLabel(accessibilityText)
    }

    @ViewBuilder
    private var mark: some View {
        switch relative {
        case ...(-2):
            ZStack {
                Circle().stroke(lineWidth: 1.35)
                Circle().stroke(lineWidth: 1.35).padding(4)
            }
        case -1:
            Circle().stroke(lineWidth: 1.35).padding(1)
        case 1:
            Rectangle().stroke(lineWidth: 1.35).padding(2)
        case 2...:
            ZStack {
                Rectangle().stroke(lineWidth: 1.35)
                Rectangle().stroke(lineWidth: 1.35).padding(4)
            }
        default:
            EmptyView()
        }
    }

    private var accessibilityText: String {
        guard score > 0 else { return "Not scored" }
        switch relative {
        case ...(-2): return "\(score), eagle or better"
        case -1: return "\(score), birdie"
        case 0 where par > 0: return "\(score), par"
        case 1: return "\(score), bogey"
        case 2...: return "\(score), double bogey or worse"
        default: return "\(score)"
        }
    }
}

public struct ScorecardHole: Hashable, Sendable, Identifiable {
    public var hole: String
    public var par: Int
    public var score: Int
    public var putts: Int

    public var id: String { hole }

    public init(hole: String, par: Int, score: Int, putts: Int) {
        self.hole = hole
        self.par = par
        self.score = score
        self.putts = putts
    }
}

/// Front and back nine tables with subtotals, scrolling sideways when text is large.
public struct ScorecardGrid: View {
    let holes: [ScorecardHole]

    public init(holes: [ScorecardHole]) {
        self.holes = holes
    }

    private var nines: [(title: String, holes: [ScorecardHole])] {
        guard holes.count > 9 else { return [("Total", holes)] }
        return [("Out", Array(holes.prefix(9))), ("In", Array(holes.dropFirst(9)))]
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: GolfSpacing.m) {
            ForEach(nines, id: \.title) { nine in
                ScrollView(.horizontal) {
                    table(nine.title, nine.holes)
                        .padding(.vertical, GolfSpacing.xxs)
                }
                .scrollIndicators(.hidden)
            }
        }
    }

    private func table(_ title: String, _ holes: [ScorecardHole]) -> some View {
        Grid(horizontalSpacing: GolfSpacing.xxs, verticalSpacing: GolfSpacing.xs) {
            GridRow {
                label("Hole")
                ForEach(holes) { Text($0.hole).font(.caption.weight(.bold)).foregroundStyle(.golfSecondaryText) }
                Text(title).font(.caption.weight(.bold)).foregroundStyle(.golfSecondaryText)
            }
            GridRow {
                label("Par")
                ForEach(holes) { Text($0.par > 0 ? "\($0.par)" : "–").monospacedDigit() }
                Text("\(holes.reduce(0) { $0 + $1.par })").monospacedDigit().bold()
            }
            .font(.subheadline)
            GridRow {
                label("Score")
                ForEach(holes) { ScoreMark(score: $0.score, par: $0.par) }
                Text("\(holes.reduce(0) { $0 + $1.score })").font(.body.weight(.heavy).monospacedDigit())
            }
            GridRow {
                label("Putts")
                ForEach(holes) { Text($0.putts > 0 ? "\($0.putts)" : "–").monospacedDigit() }
                Text("\(holes.reduce(0) { $0 + $1.putts })").monospacedDigit().bold()
            }
            .font(.subheadline)
            .foregroundStyle(.golfSecondaryText)
        }
        .foregroundStyle(.golfPrimaryText)
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.golfSecondaryText)
            .gridColumnAlignment(.leading)
    }
}

/// "E", "+3", or "−2".
public func formatRelativeToPar(_ value: Int) -> String {
    value == 0 ? "E" : value > 0 ? "+\(value)" : "−\(-value)"
}

#Preview("Scorecard") {
    let holes = (1...18).map { ScorecardHole(hole: "\($0)", par: [4, 3, 5][$0 % 3], score: [4, 2, 6, 5, 3, 0][$0 % 6], putts: $0 % 3) }
    return ScorecardGrid(holes: holes).padding()
}
