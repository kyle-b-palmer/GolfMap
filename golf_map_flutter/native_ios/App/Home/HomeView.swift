import GolfCore
import GolfDesign
import GolfSync
import SwiftUI

struct HomeView: View {
    @Environment(CourseRepository.self) private var courses
    @Environment(RoundRepository.self) private var rounds
    @Environment(CourseLibraryStore.self) private var library
    @State private var query = ""
    @State private var path = NavigationPath()
    @State private var activeRound: RoundStore?
    @State private var startCandidate: CourseCatalogEntry?
    @State private var conflict: PendingStart?
    @State private var courseToDelete: String?
    @State private var sheet: HomeSheet?
    @State private var favoriteLimitAlert = false
    @State private var checkedRestore = false
    @State private var editor: CourseEditorStore?

    /// An interrupted round reopens by itself at launch only if it changed this recently; older ones wait on Resume.
    private static let restoreWindow: TimeInterval = 12 * 60 * 60

    var body: some View {
        NavigationStack(path: $path) {
            content
                .navigationTitle("Golf Map")
                .searchable(text: $query, prompt: "Course, city, or state")
                .toolbar {
                    ToolbarItemGroup(placement: .primaryAction) {
                        Button("Trace a course", systemImage: "pencil.and.outline") { editor = CourseEditorStore(repository: courses) }
                        Button("Club bag", systemImage: "bag") { sheet = .clubBag }
                        Button("Settings", systemImage: "gearshape") { sheet = .settings }
                    }
                }
                .navigationDestination(for: SavedRound.self) { round in
                    SavedRoundDetailView(round: round, onContinue: { request(.saved($0)) }, onDelete: rounds.delete)
                }
        }
        .fullScreenCover(item: $activeRound, onDismiss: { Task { await courses.reload() } }) { store in
            RoundView(store: store)
        }
        .fullScreenCover(item: $editor) { store in
            CourseEditorView(store: store)
        }
        .sheet(item: $sheet) { sheet in
            NavigationStack {
                switch sheet {
                case .clubBag: ClubBagView()
                case .settings: SettingsView()
                }
            }
        }
        .onChange(of: courses.state == .loaded, initial: true) { _, loaded in
            guard loaded, !checkedRestore else { return }
            checkedRestore = true
            #if DEBUG
            if UserDefaults.standard.string(forKey: "GolfMapOpenCourse") != nil || UserDefaults.standard.string(forKey: "GolfMapHomeRoute") != nil { return }
            #endif
            if let active = rounds.activeRound, let savedAt = rounds.activeRoundSavedAt, Date.now.timeIntervalSince(savedAt) < Self.restoreWindow {
                open(active, isNewVisit: false)
            }
        }
        #if DEBUG
        .onChange(of: courses.state == .loaded, initial: true) { _, loaded in
            // Screenshot automation: `settings`, `clubBag`, `latestRound`, `trace`, or `edit:<course>`, set like `GolfMapOpenCourse`.
            guard loaded else { return }
            switch UserDefaults.standard.string(forKey: "GolfMapHomeRoute") {
            case "settings": sheet = .settings
            case "clubBag": sheet = .clubBag
            case "latestRound": if let round = rounds.savedRounds.first { path.append(round) }
            case "trace": editor = CourseEditorStore(repository: courses)
            case let route? where route.hasPrefix("edit:"): editCourse(String(route.dropFirst(5)))
            default: break
            }
        }
        .overlay {
            // Screenshot automation shows that course's round in place of Home. It's a persistent default rather
            // than a launch argument because the background location session relaunches the app without arguments.
            if courses.state == .loaded,
               let name = UserDefaults.standard.string(forKey: "GolfMapOpenCourse"),
               courses.entry(named: name) != nil {
                DebugRoundHost(course: name)
            }
        }
        #endif
        .confirmationDialog(
            "Start a round?",
            isPresented: Binding(get: { startCandidate != nil }, set: { if !$0 { startCandidate = nil } }),
            titleVisibility: .visible,
            presenting: startCandidate
        ) { entry in
            Button("Start at \(entry.name)") { start(entry.name) }
        } message: { entry in
            Text("\(entry.locationLabel)")
        }
        .confirmationDialog(
            "A round is in progress",
            isPresented: Binding(get: { conflict != nil }, set: { if !$0 { conflict = nil } }),
            titleVisibility: .visible,
            presenting: conflict
        ) { pending in
            Button("Resume \(rounds.activeRound?.courseName ?? "round")") {
                if let active = rounds.activeRound { open(active) }
            }
            Button("Discard it and \(pending.actionTitle)", role: .destructive) {
                rounds.discardActive()
                SharedRoundStore.shared.clear()
                perform(pending)
            }
        } message: { _ in
            Text("Unsaved scores in the current round are lost if you discard it.")
        }
        .confirmationDialog(
            "Delete traced course?",
            isPresented: Binding(get: { courseToDelete != nil }, set: { if !$0 { courseToDelete = nil } }),
            titleVisibility: .visible,
            presenting: courseToDelete
        ) { name in
            Button("Delete \(name)", role: .destructive) {
                Task { await courses.deleteUserCourse(name) }
            }
        } message: { name in
            Text("Remove \(name) from this device? Saved rounds stay.")
        }
        .alert("Five favorites at most", isPresented: $favoriteLimitAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Unstar a course to add another.")
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
                    .buttonStyle(.borderedProminent)
            }
        case .loaded:
            list
        }
    }

    // MARK: List

    private var groups: [CourseCatalogGroup] {
        CourseCatalog.grouped(courses.catalog.filter { query.isEmpty || $0.matches(query: query) })
    }

    private var list: some View {
        List {
            if query.isEmpty {
                if let active = rounds.activeRound {
                    Section { resumeRow(active) }
                }
                if !library.favorites.isEmpty {
                    Section("Favorites") {
                        ForEach(library.favorites, id: \.self) { name in
                            courseRow(name: name, detail: courses.entry(named: name)?.locationLabel)
                        }
                    }
                }
                let visited = library.commonlyVisited(savedRounds: rounds.savedRounds)
                    .filter { !library.isFavorite($0.courseName) }
                if !visited.isEmpty {
                    Section("Commonly played") {
                        ForEach(visited) { entry in
                            courseRow(name: entry.courseName, detail: entry.countLabel)
                        }
                    }
                }
                Section("Traced on this device") {
                    ForEach(courses.userCourseNames, id: \.self) { name in
                        courseRow(name: name, detail: "Traced course", isTraced: true)
                    }
                    Button("Trace a course", systemImage: "pencil.and.outline") { editor = CourseEditorStore(repository: courses) }
                        .frame(minHeight: GolfMetrics.minimumHitTarget)
                }
            }

            ForEach(groups) { group in
                Section(group.state) {
                    ForEach(group.cities, id: \.city) { city in
                        ForEach(city.courses) { entry in
                            courseRow(name: entry.name, detail: entry.locationLabel)
                        }
                    }
                }
            }

            if query.isEmpty {
                Section("Saved rounds") {
                    if rounds.savedRounds.isEmpty {
                        Text("No saved rounds yet. Finish a round and choose Save to keep it here.")
                            .font(.subheadline)
                            .foregroundStyle(.golfSecondaryText)
                    } else {
                        ForEach(rounds.savedRounds) { round in
                            NavigationLink(value: round) { savedRoundRow(round) }
                        }
                        .onDelete { offsets in
                            for index in offsets { rounds.delete(rounds.savedRounds[index]) }
                        }
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

    private func resumeRow(_ active: RoundState) -> some View {
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

    private func courseRow(name: String, detail: String?, isTraced: Bool = false) -> some View {
        let favorite = library.isFavorite(name)
        return HStack(spacing: GolfSpacing.s) {
            Button { choose(name) } label: {
                VStack(alignment: .leading, spacing: GolfSpacing.xxs) {
                    Text(name).font(.body.weight(.semibold))
                    if let detail {
                        Text(detail).font(.subheadline).foregroundStyle(.golfSecondaryText)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: GolfMetrics.minimumHitTarget, alignment: .leading)
                .contentShape(Rectangle())
            }
            .foregroundStyle(.golfPrimaryText)
            .accessibilityHint("Starts a round")

            Button { toggleFavorite(name) } label: {
                Image(systemName: favorite ? "star.fill" : "star")
                    .foregroundStyle(favorite ? GolfPalette.hazard.color : Color.golfSecondaryText)
                    .frame(width: GolfMetrics.minimumHitTarget, height: GolfMetrics.minimumHitTarget)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(favorite ? "Remove \(name) from favorites" : "Add \(name) to favorites")
        }
        .contextMenu {
            Button("Start round", systemImage: "play.fill") { choose(name) }
            Button(favorite ? "Unfavorite" : "Favorite", systemImage: favorite ? "star.slash" : "star") { toggleFavorite(name) }
            Button("Edit course", systemImage: "pencil.and.outline") { editCourse(name) }
            if isTraced {
                Button("Delete traced course", systemImage: "trash", role: .destructive) { courseToDelete = name }
            }
        }
        .swipeActions(edge: .trailing) {
            if isTraced {
                Button("Delete", systemImage: "trash", role: .destructive) { courseToDelete = name }
            }
        }
    }

    /// A course traced on this device opens as is; any other starts a local copy seeded from its data.
    private func editCourse(_ name: String) {
        let isLocal = courses.userCourseNames.contains(name.trimmingCharacters(in: .whitespaces))
        editor = isLocal ? CourseEditorStore(existing: name, repository: courses) : CourseEditorStore(seed: name, repository: courses)
    }

    private func savedRoundRow(_ round: SavedRound) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: GolfSpacing.xxs) {
                Text(round.courseName).font(.body.weight(.semibold))
                Text(round.playedAt.date, format: .dateTime.month().day().year())
                    .font(.subheadline)
                    .foregroundStyle(.golfSecondaryText)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 0) {
                Text("\(round.totalStrokes)")
                    .font(GolfType.secondaryNumber)
                Text("\(round.holesScored)/\(round.scores.count) holes")
                    .font(.caption)
                    .foregroundStyle(.golfSecondaryText)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(round.courseName), \(round.playedAt.date.formatted(date: .long, time: .omitted)), \(round.totalStrokes) strokes over \(round.holesScored) holes")
    }

    // MARK: Actions

    private func toggleFavorite(_ name: String) {
        if library.toggleFavorite(name) == .limitReached { favoriteLimitAlert = true }
    }

    private func choose(_ name: String) {
        if let active = rounds.activeRound, active.courseName == name {
            open(active)
        } else if let entry = courses.entry(named: name) {
            startCandidate = entry
        }
    }

    private func start(_ name: String) {
        request(.course(name))
    }

    private func request(_ pending: PendingStart) {
        if let active = rounds.activeRound {
            if case .saved(let saved) = pending, saved.id == active.id {
                open(active)
            } else {
                conflict = pending
            }
            return
        }
        perform(pending)
    }

    private func perform(_ pending: PendingStart) {
        switch pending {
        case .course(let name):
            open(RoundState.start(course: name, features: courses.features(for: name)))
        case .saved(let saved):
            open(RoundState.reopen(saved, features: courses.features(for: saved.courseName)))
        }
    }

    private func open(_ round: RoundState, isNewVisit: Bool = true) {
        if isNewVisit { library.recordVisit(round.courseName) }
        path = NavigationPath()
        activeRound = RoundStore(round: round, courseFeatures: courses.features(for: round.courseName), repository: rounds)
    }
}

private enum PendingStart: Hashable {
    case course(String)
    case saved(SavedRound)

    var actionTitle: String {
        switch self {
        case .course(let name): "start \(name)"
        case .saved(let round): "edit \(round.courseName)"
        }
    }
}

private enum HomeSheet: String, Identifiable {
    case clubBag
    case settings

    var id: String { rawValue }
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

extension CourseEditorStore: Identifiable {}
