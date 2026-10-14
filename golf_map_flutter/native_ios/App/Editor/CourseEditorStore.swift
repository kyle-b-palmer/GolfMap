import Foundation
import GolfCore
import Observation

/// Drives the course editor: the draft, the input mode, imports, and saving or uploading.
@Observable
@MainActor
final class CourseEditorStore {
    enum Mode: String, CaseIterable, Identifiable {
        case pan, draw, walk
        var id: String { rawValue }
    }

    /// Work that waits on an unsaved shape edit being saved or discarded.
    enum PendingAction: Equatable {
        case mode(Mode)
        case hole(Int)
        case edit(FeatureID)
        case transfer(FeatureID, hole: Int, copy: Bool)
        case saveCourse
        case close
    }

    enum Destination: Equatable {
        case local, database
    }

    enum Prompt: Identifiable, Equatable {
        case unsavedEdit(String, then: PendingAction)
        case overwrite(Destination, detail: String)

        var id: String {
            switch self {
            case .unsavedEdit: "unsaved"
            case .overwrite(let destination, _): "overwrite-\(destination)"
            }
        }
    }

    private(set) var draft: CourseDraft
    private(set) var mode = Mode.pan
    let existingName: String?
    private(set) var importSource: String?
    private(set) var message: String?
    private(set) var isLoading = true
    private(set) var isImporting = false
    private(set) var isSaving = false
    private(set) var isUploading = false
    /// The editor should close: the course saved, or the user confirmed leaving.
    private(set) var isFinished = false
    var prompt: Prompt?
    /// Bumped when the camera should frame the current hole again.
    private(set) var focusToken = 0
    private(set) var user: Coordinate?

    private let seedName: String?
    private let repository: CourseRepository
    private let osm: OSMClient
    private var messageTask: Task<Void, Never>?
    private var savedFeatures: [GolfFeature] = []

    /// Features differ from what was loaded or last saved.
    var hasUnsavedChanges: Bool { draft.features != savedFeatures || draft.editing?.hasChanges == true }

    init(existing: String? = nil, seed: String? = nil, repository: CourseRepository, osm: OSMClient = OSMClient()) {
        existingName = existing?.trimmingCharacters(in: .whitespaces).nilIfEmpty
        seedName = seed?.trimmingCharacters(in: .whitespaces).nilIfEmpty
        self.repository = repository
        self.osm = osm
        draft = CourseDraft(courseName: existingName ?? seedName ?? "")
    }

    var isExisting: Bool { existingName != nil }
    var editing: CourseDraft.EditSession? { draft.editing }

    var courseName: String {
        get { draft.courseName }
        set { if !isExisting { draft.courseName = newValue } }
    }

    var featureType: TraceFeatureType {
        get { draft.featureType }
        set { draft.featureType = newValue }
    }

    // MARK: Loading

    /// Opens a saved course, or seeds a new one from the database, then the built-in data.
    func load() async {
        defer {
            isLoading = false
            focusToken += 1
        }
        if let existingName {
            let rows = (try? repository.userCourses.rows(forCourse: existingName)) ?? []
            draft.replaceFeatures(rows.enumerated().compactMap { try? FeatureRowDecoder.decodeRow($1, index: $0) })
            savedFeatures = draft.features
            if !draft.features.isEmpty { return }
        }
        guard let seed = seedName ?? existingName else { return }
        var source = (try? await repository.remote.features(forCourse: seed)) ?? []
        var label = CourseImportSource.database.label
        if source.isEmpty {
            source = repository.sourceFeatures.filter { $0.matchesCourse(seed) }
            label = CourseImportSource.bundled.label
        }
        guard !source.isEmpty else { return }
        draft.replaceFeatures(CourseImportRanking.clone(source, as: seed))
        importSource = "\(seed) (\(label))"
    }

    // MARK: Location and drawing

    func locationChanged(_ coordinate: Coordinate?) {
        user = coordinate
        if mode == .walk, let coordinate {
            draft.addPoint(coordinate, minimumSpacing: CourseDraft.walkPointSpacingMeters)
        }
    }

    /// A tap draws a point in Draw mode, or adds a vertex to the shape being edited.
    func mapTapped(_ point: Coordinate) {
        if draft.editing != nil {
            draft.insertEditPoint(point)
        } else if mode == .draw {
            draft.addPoint(point)
        }
    }

    /// A finger drag in Draw mode; the first point of each stroke is always kept.
    func drawStroke(_ point: Coordinate, isStart: Bool) {
        guard mode == .draw, draft.editing == nil else { return }
        draft.addPoint(point, minimumSpacing: isStart ? 0 : CourseDraft.minimumPointSpacingMeters)
    }

    func undoPoint() { draft.undoPoint() }
    func clearPoints() { draft.clearPoints() }

    func commitShape() {
        show(draft.commitShape(user: user))
    }

    func setMode(_ next: Mode) {
        guard resolveEdit(then: .mode(next)) else { return }
        mode = next
    }

    func setPar(_ value: Int) { draft.setPar(value) }
    func setHandicap(_ value: Int) { draft.setHandicap(value) }

    func setHoleCount(_ value: Int) {
        guard value > 0 else { return }
        draft.holeCount = value
    }

    func goToHole(_ hole: Int) {
        guard resolveEdit(then: .hole(hole)) else { return }
        if let message = draft.goToHole(hole) {
            show(message)
        } else {
            focusToken += 1
        }
    }

    // MARK: Features and shape edits

    func beginEditing(_ id: FeatureID) {
        guard draft.editing?.featureID != id, resolveEdit(then: .edit(id)) else { return }
        if mode == .walk { mode = .pan }
        if let message = draft.beginEditing(id) { show(message) }
    }

    func deleteFeature(_ id: FeatureID) { draft.deleteFeature(id) }
    func deleteEditVertex(_ index: Int) { show(draft.deleteEditVertex(at: index)) }
    func moveEditVertex(_ index: Int, to point: Coordinate) { draft.moveEditVertex(at: index, to: point) }
    func undoEdit() { show(draft.undoEdit()) }
    func saveEdit() { show(draft.saveEdit()) }
    func cancelEdit() { show(draft.cancelEdit()) }

    func transfer(_ id: FeatureID, toHole hole: Int, copy: Bool) {
        if draft.editing?.featureID == id, draft.editing?.hasChanges == true {
            prompt = .unsavedEdit(draft.editing?.featureType ?? "feature", then: .transfer(id, hole: hole, copy: copy))
            return
        }
        show(draft.transferFeature(id, toHole: hole, copy: copy))
        focusToken += 1
    }

    /// Returns true when there's no unsaved shape edit in the way; otherwise asks first.
    private func resolveEdit(then action: PendingAction) -> Bool {
        guard let session = draft.editing else { return true }
        guard session.hasChanges else {
            _ = draft.cancelEdit()
            return true
        }
        prompt = .unsavedEdit(session.featureType ?? "feature", then: action)
        return false
    }

    /// Answers the unsaved-edit prompt and continues with what was interrupted.
    func resolveUnsavedEdit(keepChanges: Bool, then action: PendingAction) {
        prompt = nil
        if keepChanges {
            show(draft.saveEdit())
            if draft.editing != nil { return }
        } else {
            _ = draft.cancelEdit()
        }
        switch action {
        case .mode(let mode): setMode(mode)
        case .hole(let hole): goToHole(hole)
        case .edit(let id): beginEditing(id)
        case .transfer(let id, let hole, let copy): transfer(id, toHole: hole, copy: copy)
        case .saveCourse: Task { await self.save() }
        case .close: isFinished = true
        }
    }

    func close() {
        isFinished = true
    }

    // MARK: Import

    /// Searches the shared database, the built-in courses, and OpenStreetMap. An OpenStreetMap failure only
    /// surfaces when nothing else matched.
    func search(_ query: String) async throws -> [CourseImportMatch] {
        let remote = repository.remote
        async let databaseNames = (try? remote.courseNames()) ?? []
        let osmResult: Result<[OSMCourseSummary], Error>
        do {
            osmResult = .success(try await osm.searchCourses(named: query, near: user))
        } catch {
            osmResult = .failure(error)
        }
        let matches = CourseImportRanking.matches(
            query: query,
            databaseNames: await databaseNames,
            bundledNames: repository.sourceCourseNames,
            osm: (try? osmResult.get()) ?? [],
            near: user
        )
        if matches.isEmpty, case .failure(let error) = osmResult { throw error }
        return matches
    }

    func load(_ match: CourseImportMatch) async {
        isImporting = true
        defer { isImporting = false }
        let target = existingName ?? draft.trimmedName.nilIfEmpty ?? match.name
        do {
            let imported: [GolfFeature]
            switch match.source {
            case .database: imported = try await repository.remote.features(forCourse: match.name)
            case .bundled: imported = repository.sourceFeatures.filter { $0.matchesCourse(match.name) }
            case .openStreetMap:
                guard let course = match.osm else { return }
                imported = try await osm.features(for: course)
            }
            guard !imported.isEmpty else {
                show("No hole geometry found for \(match.name).")
                return
            }
            if !isExisting, draft.trimmedName.isEmpty { draft.courseName = target }
            draft.replaceFeatures(CourseImportRanking.clone(imported, as: target))
            mode = .pan
            importSource = "\(match.name) (\(match.source.label))"
            let holes = Set(draft.features.compactMap(\.holeNumber)).count
            show("Loaded \(draft.features.count) features across \(holes) holes from \(match.source.label). Edit, then save or upload.")
            focusToken += 1
        } catch {
            show("Couldn't load the course: \(error.localizedDescription)")
        }
    }

    // MARK: Save, upload, export

    func save() async {
        guard let name = readyName(for: "saving") else { return }
        guard resolveEdit(then: .saveCourse) else { return }
        if existingName != name {
            let count = (try? repository.userCourses.rows(forCourse: name).count) ?? 0
            if count > 0 {
                prompt = .overwrite(.local, detail: "on this device (\(count) saved features)")
                return
            }
        }
        await performSave()
    }

    func performSave() async {
        prompt = nil
        isSaving = true
        defer { isSaving = false }
        do {
            try repository.userCourses.save(course: draft.trimmedName, rows: draft.rows)
            savedFeatures = draft.features
            await repository.reload()
            isFinished = true
        } catch {
            show("Couldn't save: \(error.localizedDescription)")
        }
    }

    func upload() async {
        guard let name = readyName(for: "uploading") else { return }
        isUploading = true
        defer { isUploading = false }
        do {
            let count = try await repository.remote.featureCount(forCourse: name)
            if count > 0 {
                prompt = .overwrite(.database, detail: "in the shared database (\(count) features)")
                return
            }
        } catch {
            show("Couldn't reach the course database: \(error.localizedDescription)")
            return
        }
        await performUpload()
    }

    func performUpload() async {
        prompt = nil
        isUploading = true
        defer { isUploading = false }
        do {
            let count = try await repository.remote.replaceCourse(draft.trimmedName, with: draft.features)
            show("Uploaded \(count) features for \(draft.trimmedName).")
        } catch {
            show(error.localizedDescription)
        }
    }

    var canExport: Bool { !draft.trimmedName.isEmpty && !draft.features.isEmpty }

    func geoJSONFile() throws -> URL {
        let safeName = draft.trimmedName.replacingOccurrences(of: "/", with: "-")
        let url = FileManager.default.temporaryDirectory.appending(path: "\(safeName).geojson")
        try draft.geoJSON().write(to: url, options: .atomic)
        return url
    }

    private func readyName(for action: String) -> String? {
        let name = draft.trimmedName
        guard !name.isEmpty else {
            show("Enter a course name first.")
            return nil
        }
        guard !draft.features.isEmpty else {
            show("Trace at least one feature before \(action).")
            return nil
        }
        return name
    }

    // MARK: Messages

    func show(_ text: String?) {
        guard let text else { return }
        message = text
        messageTask?.cancel()
        messageTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            self?.message = nil
        }
    }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
