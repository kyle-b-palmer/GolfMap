import Foundation

public enum TraceFeatureType: String, CaseIterable, Sendable, Identifiable {
    case tee, fairway, green, bunker

    public var id: String { rawValue }
    public var label: String { rawValue.capitalized }

    /// Drawing or moving a green or fairway onto a hole replaces the one already there. Tees and bunkers
    /// accumulate, since holes have several of each.
    public static func replacesExisting(_ type: String?) -> Bool {
        type == TraceFeatureType.green.rawValue || type == TraceFeatureType.fairway.rawValue
    }
}

/// The course editor's state: traced features, the shape being drawn, and an in-progress shape edit.
/// Methods return the message Flutter showed as a snackbar, if any.
public struct CourseDraft: Sendable, Equatable {
    public static let minimumPointSpacingMeters = 4.0
    public static let walkPointSpacingMeters = 2.0
    static let editUndoLimit = 40
    static let teeHalfSizeDegrees = 0.00004

    public struct EditSession: Sendable, Equatable {
        public var featureID: FeatureID
        public var featureType: String?
        public var vertices: [Coordinate]
        var baseline: [Coordinate]
        var undoStack: [[Coordinate]] = []

        public var hasChanges: Bool {
            guard vertices.count == baseline.count else { return true }
            return zip(vertices, baseline).contains { abs($0.latitude - $1.latitude) >= 1e-7 || abs($0.longitude - $1.longitude) >= 1e-7 }
        }

        public var canUndo: Bool { !undoStack.isEmpty }

        mutating func pushUndo() {
            undoStack.append(vertices)
            if undoStack.count > CourseDraft.editUndoLimit { undoStack.removeFirst() }
        }
    }

    /// Every feature takes this name, so renaming a new course can't leave rows under the old one.
    public var courseName: String {
        didSet {
            let name = courseName.trimmingCharacters(in: .whitespaces)
            for index in features.indices { features[index].courseName = name }
        }
    }
    public private(set) var features: [GolfFeature]
    public var holeCount: Int
    public private(set) var currentHole = 1
    public var featureType = TraceFeatureType.fairway
    public private(set) var par = 4
    public private(set) var handicap = 1
    public private(set) var pending: [Coordinate] = []
    public private(set) var editing: EditSession?

    public init(courseName: String, features: [GolfFeature] = [], holeCount: Int = 18) {
        self.courseName = courseName
        self.features = features
        self.holeCount = holeCount
        let name = courseName.trimmingCharacters(in: .whitespaces)
        for index in self.features.indices { self.features[index].courseName = name }
        applyLoadedHoles()
    }

    public var trimmedName: String { courseName.trimmingCharacters(in: .whitespaces) }
    public var holeKey: String { String(currentHole) }
    public var holeFeatures: [GolfFeature] { features.filter { $0.holeNumber == holeKey } }

    // MARK: Drawing

    /// Adds a traced point unless it's within `minimumSpacing` meters of the previous one.
    public mutating func addPoint(_ point: Coordinate, minimumSpacing: Double = 0) {
        if minimumSpacing > 0, let last = pending.last, GeoMath.distanceMeters(last, point) < minimumSpacing { return }
        pending.append(point)
    }

    public mutating func undoPoint() {
        _ = pending.popLast()
    }

    public mutating func clearPoints() {
        pending.removeAll()
    }

    /// Closes the drawn shape into a feature on the current hole. A tee can be a single tap or the
    /// player's position, which becomes a small square.
    public mutating func commitShape(user: Coordinate?, now: Date = .now) -> String {
        guard !trimmedName.isEmpty else { return "Enter a course name first." }
        var vertices = pending
        if featureType == .tee {
            if vertices.isEmpty, let user { vertices = [user] }
            if vertices.count == 1 { vertices = Self.teeSquare(vertices[0]) }
        }
        guard vertices.count >= 3 else { return "Add at least 3 points (or tap once for a tee)." }

        let isGreen = featureType == .green
        let feature = GolfFeature(
            id: .string(newID(now: now)),
            featureType: featureType.rawValue,
            holeNumber: holeKey,
            name: nil,
            par: isGreen ? par : nil,
            handicap: isGreen ? handicap : nil,
            courseName: trimmedName,
            geometry: .polygon(vertices: vertices)
        )
        if TraceFeatureType.replacesExisting(featureType.rawValue) {
            let hole = holeKey, type = featureType.rawValue
            features.removeAll { $0.holeNumber == hole && $0.featureType == type }
        }
        features.append(feature)
        pending.removeAll()
        return "Saved \(featureType.label.lowercased()) for hole \(currentHole)."
    }

    // MARK: Holes

    /// Callers resolve an in-progress edit first.
    public mutating func goToHole(_ hole: Int) -> String? {
        guard hole >= 1 else { return nil }
        guard hole <= holeCount else { return "Already on the last hole." }
        currentHole = hole
        pending.removeAll()
        syncParFields()
        return nil
    }

    /// Updates the field and the current hole's greens, which carry par for the course.
    public mutating func setPar(_ value: Int) {
        par = value
        for index in greenIndicesOnHole { features[index].par = value }
    }

    public mutating func setHandicap(_ value: Int) {
        handicap = value
        for index in greenIndicesOnHole { features[index].handicap = value }
    }

    private var greenIndicesOnHole: [Int] {
        features.indices.filter { features[$0].holeNumber == holeKey && features[$0].featureType == TraceFeatureType.green.rawValue }
    }

    // MARK: Features

    public mutating func deleteFeature(_ id: FeatureID) {
        if editing?.featureID == id { editing = nil }
        features.removeAll { $0.id == id }
    }

    /// Moves a feature to another hole, or copies it there with a new ID, then shows that hole.
    public mutating func transferFeature(_ id: FeatureID, toHole hole: Int, copy: Bool, now: Date = .now) -> String? {
        guard let source = features.first(where: { $0.id == id }) else { return nil }
        let label = source.featureType ?? "feature"
        let target = String(hole)
        guard source.holeNumber != target else { return "The \(label) is already on hole \(hole)." }
        guard (1...max(holeCount, 1)).contains(hole) else { return "Choose a hole from 1 to \(holeCount)." }
        if editing?.featureID == id { editing = nil }

        if TraceFeatureType.replacesExisting(source.featureType) {
            features.removeAll { $0.holeNumber == target && $0.featureType == source.featureType && $0.id != id }
        }
        if copy {
            var clone = source
            clone.id = .string(newID(now: now))
            clone.holeNumber = target
            features.append(clone)
        } else if let index = features.firstIndex(where: { $0.id == id }) {
            features[index].holeNumber = target
        }
        let from = source.holeNumber ?? "?"
        currentHole = hole
        pending.removeAll()
        syncParFields()
        return copy ? "Copied \(label) to hole \(hole)." : "Moved \(label) from hole \(from) to hole \(hole)."
    }

    /// Replaces every feature with imported ones, already renamed for this course.
    public mutating func replaceFeatures(_ imported: [GolfFeature]) {
        features = imported
        let name = trimmedName
        if !name.isEmpty {
            for index in features.indices { features[index].courseName = name }
        }
        pending.removeAll()
        editing = nil
        applyLoadedHoles()
    }

    // MARK: Shape editing

    public mutating func beginEditing(_ id: FeatureID) -> String? {
        guard let feature = features.first(where: { $0.id == id }) else { return nil }
        let vertices = feature.geometry.editableVertices
        guard vertices.count >= 3 else { return "This feature can't be edited." }
        editing = EditSession(featureID: id, featureType: feature.featureType, vertices: vertices, baseline: vertices)
        pending.removeAll()
        return nil
    }

    /// Inserts a point on the nearest edge, unless it's on top of an existing vertex.
    public mutating func insertEditPoint(_ point: Coordinate) {
        guard var session = editing else { return }
        guard !session.vertices.contains(where: { GeoMath.distanceMeters($0, point) < Self.minimumPointSpacingMeters }) else { return }
        session.pushUndo()
        session.vertices.insert(point, at: Self.insertIndex(in: session.vertices, for: point))
        editing = session
    }

    public mutating func deleteEditVertex(at index: Int) -> String? {
        guard var session = editing, session.vertices.indices.contains(index) else { return nil }
        guard session.vertices.count > 3 else { return "A shape needs at least 3 points." }
        session.pushUndo()
        session.vertices.remove(at: index)
        editing = session
        return nil
    }

    public mutating func moveEditVertex(at index: Int, to point: Coordinate) {
        guard var session = editing, session.vertices.indices.contains(index) else { return }
        session.pushUndo()
        session.vertices[index] = point
        editing = session
    }

    public mutating func undoEdit() -> String? {
        guard var session = editing else { return nil }
        guard let previous = session.undoStack.popLast() else { return "Nothing to undo." }
        session.vertices = previous
        editing = session
        return nil
    }

    public mutating func saveEdit() -> String? {
        guard let session = editing else { return nil }
        guard session.vertices.count >= 3 else { return "A shape needs at least 3 points." }
        if let index = features.firstIndex(where: { $0.id == session.featureID }) {
            features[index].geometry = .polygon(vertices: session.vertices)
        }
        editing = nil
        return "Saved \(session.featureType ?? "feature")."
    }

    public mutating func cancelEdit() -> String? {
        guard let session = editing else { return nil }
        editing = nil
        return session.hasChanges ? "Discarded changes." : nil
    }

    // MARK: Output

    /// Rows for local save and upload.
    public var rows: [JSONValue] { features.map(\.row) }

    /// A GeoJSON FeatureCollection of the course.
    public func geoJSON() throws -> Data {
        try JSONValue.object([
            "type": .string("FeatureCollection"),
            "features": .array(features.map(\.geoJSONFeature)),
        ]).encoded()
    }

    // MARK: Helpers

    /// Index after the start vertex of the edge nearest `point`.
    static func insertIndex(in vertices: [Coordinate], for point: Coordinate) -> Int {
        guard vertices.count > 1 else { return vertices.count }
        var best = (edge: 0, distance: Double.infinity)
        for index in vertices.indices {
            let distance = GeoMath.distanceToSegmentMeters(point, vertices[index], vertices[(index + 1) % vertices.count])
            if distance < best.distance { best = (index, distance) }
        }
        return best.edge + 1
    }

    static func teeSquare(_ center: Coordinate) -> [Coordinate] {
        let d = teeHalfSizeDegrees
        return [
            Coordinate(latitude: center.latitude - d, longitude: center.longitude - d),
            Coordinate(latitude: center.latitude - d, longitude: center.longitude + d),
            Coordinate(latitude: center.latitude + d, longitude: center.longitude + d),
            Coordinate(latitude: center.latitude + d, longitude: center.longitude - d),
        ]
    }

    private func newID(now: Date) -> String {
        "user-\(Int(now.timeIntervalSince1970 * 1000))-\(features.count)"
    }

    private var numericHoles: [Int] { features.compactMap { $0.holeNumber.flatMap { Int($0) } } }

    private mutating func applyLoadedHoles() {
        let holes = numericHoles
        if let last = holes.max() { holeCount = last }
        currentHole = holes.min() ?? 1
        syncParFields()
    }

    private mutating func syncParFields() {
        let onHole = holeFeatures
        let source = onHole.first { $0.par != nil } ?? onHole.first
        par = source?.par ?? 4
        handicap = source?.handicap ?? 1
    }
}
