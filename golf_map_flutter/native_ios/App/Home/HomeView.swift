import GolfCore
import GolfDesign
import GolfSync
import SwiftUI

struct HomeView: View {
    @Environment(CourseRepository.self) private var courses
    @Environment(RoundRepository.self) private var rounds
    @State private var query = ""
    @State private var activeRound: RoundStore?
    @State private var pendingCourse: CourseCatalogEntry?

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Golf Map")
                .searchable(text: $query, prompt: "Course, city, or state")
        }
        .fullScreenCover(item: $activeRound) { store in
            RoundView(store: store)
        }
        #if DEBUG
        .overlay {
            // Screenshot automation shows that course's round in place of Home. Set it as a persistent default
            // (`simctl spawn <sim> defaults write <bundle id> GolfMapOpenCourse "<name>"`) rather than a launch
            // argument: the background location session relaunches the app without arguments.
            if courses.state == .loaded,
               let name = UserDefaults.standard.string(forKey: "GolfMapOpenCourse"),
               courses.entry(named: name) != nil {
                DebugRoundHost(course: name)
            }
        }
        #endif
        .confirmationDialog(
            "A round is in progress",
            isPresented: Binding(get: { pendingCourse != nil }, set: { if !$0 { pendingCourse = nil } }),
            presenting: pendingCourse
        ) { entry in
            Button("Resume \(rounds.activeRound?.courseName ?? "round")") {
                if let active = rounds.activeRound { open(active) }
            }
            Button("Discard and start \(entry.name)", role: .destructive) {
                rounds.discardActive()
                SharedRoundStore.shared.clear()
                start(entry)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch courses.state {
        case .idle, .loading:
            ProgressView("Loading courses")
        case .failed(let message):
            ContentUnavailableView {
                Label("Couldn't load courses", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("Try again") { Task { await courses.load() } }
            }
        case .loaded:
            list
        }
    }

    private var groups: [CourseCatalogGroup] {
        CourseCatalog.grouped(courses.catalog.filter { query.isEmpty || $0.matches(query: query) })
    }

    private var list: some View {
        List {
            if query.isEmpty, let active = rounds.activeRound {
                Section {
                    Button { open(active) } label: {
                        HStack(spacing: GolfSpacing.s) {
                            Image(systemName: "figure.golf")
                                .font(.title2)
                                .foregroundStyle(.golfBrand)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: GolfSpacing.xxs) {
                                Text("Resume round").font(.headline)
                                Text("\(active.courseName) · Hole \(active.selectedHole) · \(active.totalScore) strokes")
                                    .font(.subheadline)
                                    .foregroundStyle(.golfSecondaryText)
                            }
                        }
                        .frame(minHeight: GolfMetrics.minimumHitTarget)
                    }
                    .foregroundStyle(.golfPrimaryText)
                }
            }

            ForEach(groups) { group in
                Section(group.state) {
                    ForEach(group.cities, id: \.city) { city in
                        ForEach(city.courses) { entry in
                            Button { choose(entry) } label: {
                                VStack(alignment: .leading, spacing: GolfSpacing.xxs) {
                                    Text(entry.name).font(.body.weight(.semibold))
                                    Text(entry.locationLabel).font(.subheadline).foregroundStyle(.golfSecondaryText)
                                }
                                .frame(minHeight: GolfMetrics.minimumHitTarget, alignment: .leading)
                            }
                            .foregroundStyle(.golfPrimaryText)
                        }
                    }
                }
            }

            if query.isEmpty, !rounds.savedRounds.isEmpty {
                Section("Recent rounds") {
                    ForEach(rounds.savedRounds.prefix(10)) { round in
                        HStack {
                            VStack(alignment: .leading, spacing: GolfSpacing.xxs) {
                                Text(round.courseName).font(.body.weight(.semibold))
                                Text(round.playedAt.date, format: .dateTime.month().day().year())
                                    .font(.subheadline)
                                    .foregroundStyle(.golfSecondaryText)
                            }
                            Spacer()
                            Text("\(round.totalStrokes)")
                                .font(GolfType.secondaryNumber)
                                .accessibilityLabel("\(round.totalStrokes) strokes")
                        }
                    }
                    .onDelete { offsets in
                        for index in offsets { rounds.delete(rounds.savedRounds[index]) }
                    }
                }
            }
        }
        .overlay {
            if groups.isEmpty, !query.isEmpty {
                ContentUnavailableView.search(text: query)
            }
        }
    }

    private func choose(_ entry: CourseCatalogEntry) {
        if let active = rounds.activeRound {
            if active.courseName == entry.name {
                open(active)
            } else {
                pendingCourse = entry
            }
            return
        }
        start(entry)
    }

    private func start(_ entry: CourseCatalogEntry) {
        let features = courses.features(for: entry.name)
        open(RoundState.start(course: entry.name, features: features))
    }

    private func open(_ round: RoundState) {
        activeRound = RoundStore(round: round, courseFeatures: courses.features(for: round.courseName), repository: rounds)
    }
}

extension RoundStore: Identifiable {}

#if DEBUG
private struct DebugRoundHost: View {
    let course: String
    @Environment(CourseRepository.self) private var courses
    @Environment(RoundRepository.self) private var rounds
    @State private var store: RoundStore?

    var body: some View {
        ZStack {
            GolfMapPalette.courseBackground.color.ignoresSafeArea()
            if let store { RoundView(store: store) }
        }
        .onAppear {
            guard store == nil else { return }
            let round = rounds.activeRound.flatMap { $0.courseName == course ? $0 : nil }
                ?? RoundState.start(course: course, features: courses.features(for: course))
            store = RoundStore(round: round, courseFeatures: courses.features(for: course), repository: rounds)
        }
    }
}
#endif
