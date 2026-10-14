import GolfCore
import GolfDesign
import MapKit
import SwiftUI

/// Hole-by-hole course tracing and editing, as Flutter's `CourseTraceScreen`.
struct CourseEditorView: View {
    @State private var store: CourseEditorStore
    @Environment(LocationService.self) private var location
    @Environment(\.dismiss) private var dismiss
    @State private var position: MapCameraPosition = .automatic
    @State private var imagery = true
    @State private var strokeActive = false
    @State private var draggingVertex: (index: Int, point: Coordinate)?
    @State private var showingImport = false
    @State private var transfer: TransferRequest?
    @State private var transferHole = ""
    @State private var confirmClose = false

    init(store: CourseEditorStore) {
        _store = State(initialValue: store)
    }

    private struct TransferRequest: Identifiable {
        let feature: GolfFeature
        let copy: Bool
        var id: String { "\(feature.id?.description ?? "")-\(copy)" }
        var label: String { feature.featureType ?? "feature" }
    }

    var body: some View {
        NavigationStack {
            map
                .overlay(alignment: .top) { statusOverlay }
                .overlay(alignment: .topTrailing) {
                    MapControlButton(imagery ? "Show map" : "Show satellite", systemImage: imagery ? "map" : "globe.americas") { imagery.toggle() }
                        .padding(GolfSpacing.m)
                }
                .safeAreaInset(edge: .bottom, spacing: 0) { EditorPanel(store: store, transfer: startTransfer) }
                .navigationTitle(store.isExisting ? "Edit course" : "Trace course")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbar }
                .overlay {
                    if store.isLoading { ProgressView().controlSize(.large) }
                }
        }
        .task {
            location.start(inRound: false)
            await store.load()
        }
        .onChange(of: location.coordinate) { _, coordinate in store.locationChanged(coordinate) }
        .onChange(of: store.focusToken) { focusCamera() }
        .onChange(of: store.isFinished) { _, finished in if finished { dismiss() } }
        .sheet(isPresented: $showingImport) { CourseImportSheet(store: store) }
        .alert(transfer.map { "\($0.copy ? "Copy" : "Move") \($0.label)" } ?? "", isPresented: Binding(get: { transfer != nil }, set: { if !$0 { transfer = nil } })) {
            TextField("Hole (1–\(store.draft.holeCount))", text: $transferHole)
                .keyboardType(.numberPad)
            Button("Cancel", role: .cancel) {}
            Button(transfer?.copy == true ? "Copy" : "Move") {
                if let transfer, let id = transfer.feature.id, let hole = Int(transferHole) {
                    store.transfer(id, toHole: hole, copy: transfer.copy)
                }
            }
        } message: {
            if let transfer {
                Text(transfer.copy
                     ? "Keeps the \(transfer.label) on hole \(transfer.feature.holeNumber ?? "?") and adds a copy to:"
                     : "Takes the \(transfer.label) off hole \(transfer.feature.holeNumber ?? "?") and puts it on:")
            }
        }
        .alert(promptTitle, isPresented: Binding(get: { store.prompt != nil }, set: { if !$0 { store.prompt = nil } }), presenting: store.prompt) { prompt in
            switch prompt {
            case .unsavedEdit(_, let action):
                Button("Keep editing", role: .cancel) {}
                Button("Discard", role: .destructive) { store.resolveUnsavedEdit(keepChanges: false, then: action) }
                Button("Save shape") { store.resolveUnsavedEdit(keepChanges: true, then: action) }
            case .overwrite(let destination, _):
                Button("Cancel", role: .cancel) {}
                Button(destination == .local ? "Save" : "Upload", role: .destructive) {
                    Task { destination == .local ? await store.performSave() : await store.performUpload() }
                }
            }
        } message: { prompt in
            switch prompt {
            case .unsavedEdit:
                Text("Save your changes to this shape, or discard them to continue.")
            case .overwrite(let destination, let detail):
                Text("A course named \"\(store.draft.trimmedName)\" already exists \(detail). \(destination == .local ? "Saving" : "Uploading") replaces it with your \(store.draft.features.count) features.")
            }
        }
        .confirmationDialog("Discard changes to this course?", isPresented: $confirmClose, titleVisibility: .visible) {
            Button("Discard changes", role: .destructive) { store.close() }
        } message: {
            Text("Your traced features haven't been saved.")
        }
    }

    private var promptTitle: String {
        switch store.prompt {
        case .unsavedEdit(let type, _): "Unsaved \(type) changes"
        case .overwrite: "Replace \"\(store.draft.trimmedName)\"?"
        case nil: ""
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Close") {
                if store.hasUnsavedChanges { confirmClose = true } else { store.close() }
            }
        }
        ToolbarItem(placement: .confirmationAction) {
            Button("Save") { Task { await store.save() } }
                .disabled(store.isSaving || store.isLoading)
        }
        ToolbarItem(placement: .primaryAction) {
            Menu("More", systemImage: "ellipsis.circle") {
                Button("Find course data", systemImage: "magnifyingglass") { showingImport = true }
                Button("Upload to database", systemImage: "icloud.and.arrow.up") { Task { await store.upload() } }
                    .disabled(store.isUploading)
                if store.canExport, let file = try? store.geoJSONFile() {
                    ShareLink("Export GeoJSON", item: file)
                } else {
                    Button("Export GeoJSON", systemImage: "square.and.arrow.up") { store.show("Nothing to export yet.") }
                }
            }
        }
    }

    // MARK: Map

    private var map: some View {
        MapReader { proxy in
            Map(position: $position, interactionModes: interactionModes) {
                ForEach(Array(visibleFeatures.enumerated()), id: \.offset) { _, feature in
                    ForEach(Array(feature.geometry.rings.enumerated()), id: \.offset) { _, ring in
                        let style = Self.style(feature.featureType, onHole: feature.holeNumber == store.draft.holeKey)
                        MapPolygon(coordinates: ring.map(\.clCoordinate))
                            .foregroundStyle(style.fill)
                            .stroke(style.border, lineWidth: 1.5)
                    }
                }
                pendingContent
                editContent(proxy)
                if let user = store.user {
                    Annotation("You", coordinate: user.clCoordinate) {
                        Circle().fill(GolfMapPalette.measureLine.color).frame(width: 16, height: 16)
                            .overlay(Circle().stroke(.white, lineWidth: 2))
                    }
                    .annotationTitles(.hidden)
                }
            }
            .mapStyle(imagery ? .imagery : .standard(pointsOfInterest: .excludingAll))
            .onTapGesture(coordinateSpace: .global) { point in
                if let coordinate = proxy.convert(point, from: .global) { store.mapTapped(Coordinate(coordinate)) }
            }
            .gesture(drawGesture(proxy), including: isDrawing ? .all : .subviews)
        }
    }

    private var isDrawing: Bool { store.mode == .draw && store.editing == nil }

    private var interactionModes: MapInteractionModes {
        isDrawing || draggingVertex != nil ? [.zoom] : [.pan, .zoom]
    }

    private var visibleFeatures: [GolfFeature] {
        let editingID = store.editing?.featureID
        return store.draft.features.filter { editingID == nil || $0.id != editingID }
    }

    @MapContentBuilder
    private var pendingContent: some MapContent {
        let pending = store.draft.pending
        if pending.count >= 2 {
            MapPolyline(coordinates: pending.map(\.clCoordinate))
                .stroke(.white, lineWidth: 2.5)
        }
        ForEach(Array(pending.enumerated()), id: \.offset) { _, point in
            Annotation("", coordinate: point.clCoordinate) {
                Circle().fill(.white).frame(width: 12, height: 12)
                    .overlay(Circle().stroke(Color.golfBrand, lineWidth: 2))
            }
            .annotationTitles(.hidden)
        }
    }

    @MapContentBuilder
    private func editContent(_ proxy: MapProxy) -> some MapContent {
        if let session = store.editing {
            let vertices = session.vertices.enumerated().map { index, point in
                draggingVertex?.index == index ? draggingVertex!.point : point
            }
            if vertices.count >= 3 {
                MapPolygon(coordinates: vertices.map(\.clCoordinate))
                    .foregroundStyle(Color.golfBrand.opacity(0.35))
                    .stroke(.white, lineWidth: 3)
            }
            ForEach(Array(vertices.enumerated()), id: \.offset) { index, point in
                Annotation("Point \(index + 1)", coordinate: point.clCoordinate) {
                    VertexHandle(isDragging: draggingVertex?.index == index)
                        .onTapGesture { store.deleteEditVertex(index) }
                        .gesture(
                            DragGesture(minimumDistance: 4, coordinateSpace: .global)
                                .onChanged { value in
                                    if let coordinate = proxy.convert(value.location, from: .global) {
                                        draggingVertex = (index, Coordinate(coordinate))
                                    }
                                }
                                .onEnded { value in
                                    if let coordinate = proxy.convert(value.location, from: .global) {
                                        store.moveEditVertex(index, to: Coordinate(coordinate))
                                    }
                                    draggingVertex = nil
                                }
                        )
                        .accessibilityLabel("Point \(index + 1)")
                        .accessibilityHint("Tap to delete. Drag to move.")
                }
                .annotationTitles(.hidden)
            }
        }
    }

    private func drawGesture(_ proxy: MapProxy) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged { value in
                guard let coordinate = proxy.convert(value.location, from: .global) else { return }
                store.drawStroke(Coordinate(coordinate), isStart: !strokeActive)
                strokeActive = true
            }
            .onEnded { _ in strokeActive = false }
    }

    private func focusCamera() {
        let holePoints = store.draft.holeFeatures.flatMap(\.geometry.allPoints)
        let points = holePoints.isEmpty ? store.draft.features.flatMap(\.geometry.allPoints) : holePoints
        guard !points.isEmpty else {
            let center = store.user ?? Coordinate(latitude: 29.4241, longitude: -98.4936)
            withAnimation { position = .camera(MapCamera(centerCoordinate: center.clCoordinate, distance: 1500)) }
            return
        }
        let rects = points.map { MKMapRect(origin: MKMapPoint($0.clCoordinate), size: MKMapSize(width: 0, height: 0)) }
        let rect = rects.dropFirst().reduce(rects[0]) { $0.union($1) }
        let padding = max(rect.width, rect.height) * 0.12 + 30
        withAnimation { position = .rect(rect.insetBy(dx: -padding, dy: -padding)) }
    }

    // MARK: Overlays

    private var statusOverlay: some View {
        VStack(spacing: GolfSpacing.xs) {
            Label(modeText, systemImage: modeIcon)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, GolfSpacing.s)
                .padding(.vertical, GolfSpacing.xs)
                .background(.thickMaterial, in: Capsule())
                .accessibilityAddTraits(.updatesFrequently)
            if let message = store.message {
                Text(message)
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, GolfSpacing.m)
                    .padding(.vertical, GolfSpacing.xs)
                    .background(.thickMaterial, in: RoundedRectangle(cornerRadius: GolfRadius.small))
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(.top, GolfSpacing.xs)
        .padding(.horizontal, GolfSpacing.xl)
        .animation(.smooth, value: store.message)
    }

    private var modeText: String {
        if let session = store.editing {
            return "Editing \(session.featureType ?? "feature") · \(session.vertices.count) points"
        }
        let count = store.draft.pending.count
        switch store.mode {
        case .pan: return "Pan · \(store.draft.featureType.label)"
        case .draw: return "Draw \(store.draft.featureType.label.lowercased()) · \(count) points"
        case .walk: return "Walking \(store.draft.featureType.label.lowercased()) · \(count) points"
        }
    }

    private var modeIcon: String {
        if store.editing != nil { return "skew" }
        switch store.mode {
        case .pan: return "hand.draw"
        case .draw: return "scribble"
        case .walk: return "figure.walk"
        }
    }

    private func startTransfer(_ feature: GolfFeature, copy: Bool) {
        transferHole = ""
        transfer = TransferRequest(feature: feature, copy: copy)
    }

    static func style(_ type: String?, onHole: Bool) -> (fill: Color, border: Color) {
        let fill = GolfMapPalette.fill(for: type ?? "")
        let color = fill?.color.color ?? Color.golfBrand
        let opacity = onHole ? max(fill?.active ?? 0.5, 0.45) : (fill?.inactive ?? 0.15)
        return (color.opacity(opacity), color.opacity(onHole ? 0.95 : 0.35))
    }
}

/// A labeled value with − and + buttons, narrow enough for three in a row.
private struct CompactStepper: View {
    let title: String
    let value: Int
    let range: ClosedRange<Int>
    let onChange: (Int) -> Void

    var body: some View {
        HStack(spacing: 0) {
            Button("Decrease \(title)", systemImage: "minus") { onChange(value - 1) }
                .disabled(value <= range.lowerBound)
            VStack(spacing: 0) {
                Text(title).font(.caption2.weight(.semibold)).foregroundStyle(.golfSecondaryText)
                Text("\(value)").font(.headline.monospacedDigit())
            }
            .frame(maxWidth: .infinity)
            .accessibilityHidden(true)
            Button("Increase \(title)", systemImage: "plus") { onChange(value + 1) }
                .disabled(value >= range.upperBound)
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .frame(minHeight: GolfMetrics.minimumHitTarget)
        .padding(.horizontal, GolfSpacing.xs)
        .background(Color.golfElevatedSurface, in: RoundedRectangle(cornerRadius: GolfRadius.small))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityValue("\(value)")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: if value < range.upperBound { onChange(value + 1) }
            case .decrement: if value > range.lowerBound { onChange(value - 1) }
            @unknown default: break
            }
        }
    }
}

private struct VertexHandle: View {
    let isDragging: Bool

    var body: some View {
        Circle()
            .fill(isDragging ? .white : Color.golfBrand)
            .frame(width: isDragging ? 22 : 18, height: isDragging ? 22 : 18)
            .overlay(Circle().stroke(isDragging ? Color.golfBrand : .white, lineWidth: 2))
            .shadow(color: .black.opacity(0.5), radius: 3)
            .frame(width: GolfMetrics.minimumHitTarget, height: GolfMetrics.minimumHitTarget)
            .contentShape(Rectangle())
    }
}

/// Course name, hole settings, feature type, the hole's features, input mode, and shape actions.
private struct EditorPanel: View {
    let store: CourseEditorStore
    let transfer: (GolfFeature, Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: GolfSpacing.s) {
            if store.isExisting {
                Text(store.draft.trimmedName).font(.headline)
            } else {
                TextField("Course name (required)", text: Binding(get: { store.courseName }, set: { store.courseName = $0 }))
                    .textInputAutocapitalization(.words)
                    .font(.headline)
                    .submitLabel(.done)
            }
            if let source = store.importSource {
                Text("Loaded from \(source). Edit hole by hole, then save or upload.")
                    .font(.caption)
                    .foregroundStyle(.golfSecondaryText)
            }

            holeRow
            settingsRow

            Picker("Feature", selection: Binding(get: { store.featureType }, set: { store.featureType = $0 })) {
                ForEach(TraceFeatureType.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .disabled(store.editing != nil)

            featureChips

            Picker("Mode", selection: Binding(get: { store.mode }, set: { store.setMode($0) })) {
                Label("Pan", systemImage: "hand.draw").tag(CourseEditorStore.Mode.pan)
                Label("Draw", systemImage: "scribble").tag(CourseEditorStore.Mode.draw)
                Label("Walk", systemImage: "figure.walk").tag(CourseEditorStore.Mode.walk)
            }
            .pickerStyle(.segmented)
            .disabled(store.editing != nil)

            actions
        }
        .padding(GolfSpacing.m)
        .background(.regularMaterial)
    }

    private var holeRow: some View {
        HStack {
            Button("Previous hole", systemImage: "chevron.left") { store.goToHole(store.draft.currentHole - 1) }
                .labelStyle(.iconOnly)
                .disabled(store.draft.currentHole <= 1)
            Spacer()
            Text("Hole \(store.draft.currentHole) of \(store.draft.holeCount) · \(store.draft.holeFeatures.count) features")
                .font(.subheadline.weight(.bold).monospacedDigit())
            Spacer()
            Button("Next hole", systemImage: "chevron.right") { store.goToHole(store.draft.currentHole + 1) }
                .labelStyle(.iconOnly)
                .disabled(store.draft.currentHole >= store.draft.holeCount)
        }
        .frame(minHeight: GolfMetrics.minimumHitTarget)
    }

    private var settingsRow: some View {
        HStack(spacing: GolfSpacing.xs) {
            CompactStepper(title: "Holes", value: store.draft.holeCount, range: 1...36) { store.setHoleCount($0) }
            CompactStepper(title: "Par", value: store.draft.par, range: 3...6) { store.setPar($0) }
            CompactStepper(title: "Hcp", value: store.draft.handicap, range: 1...18) { store.setHandicap($0) }
        }
    }

    @ViewBuilder
    private var featureChips: some View {
        let features = store.draft.holeFeatures
        if !features.isEmpty {
            ScrollView(.horizontal) {
                HStack(spacing: GolfSpacing.xs) {
                    ForEach(features, id: \.self) { feature in
                        let isEditing = store.editing?.featureID == feature.id
                        Menu {
                            Button("Edit shape", systemImage: "skew") { if let id = feature.id { store.beginEditing(id) } }
                            Button("Move to hole…", systemImage: "arrow.right.circle") { transfer(feature, false) }
                            Button("Copy to hole…", systemImage: "plus.square.on.square") { transfer(feature, true) }
                            Button("Delete", systemImage: "trash", role: .destructive) { if let id = feature.id { store.deleteFeature(id) } }
                        } label: {
                            Text(feature.featureType ?? "feature")
                                .font(.subheadline.weight(.semibold))
                                .padding(.horizontal, GolfSpacing.s)
                                .frame(minHeight: 36)
                                .background(isEditing ? Color.golfBrand.opacity(0.35) : Color.golfElevatedSurface, in: Capsule())
                                .overlay(Capsule().stroke(CourseEditorView.style(feature.featureType, onHole: true).border, lineWidth: 1.5))
                        } primaryAction: {
                            if let id = feature.id { store.beginEditing(id) }
                        }
                        .accessibilityHint("Edits the shape. Touch and hold for more.")
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
    }

    @ViewBuilder
    private var actions: some View {
        if store.editing != nil {
            HStack {
                Button("Undo") { store.undoEdit() }
                    .disabled(store.editing?.canUndo != true)
                Button("Cancel") { store.cancelEdit() }
                Spacer()
                Button("Save shape") { store.saveEdit() }
                    .buttonStyle(.borderedProminent)
            }
            .buttonStyle(.bordered)
            Text("Tap the map to add a point, tap a point to delete it, or drag a point to move it.")
                .font(.caption)
                .foregroundStyle(.golfSecondaryText)
        } else {
            HStack {
                Button("Undo") { store.undoPoint() }
                    .disabled(store.draft.pending.isEmpty)
                Button("Clear") { store.clearPoints() }
                    .disabled(store.draft.pending.isEmpty)
                Spacer()
                Button("Save \(store.draft.featureType.label.lowercased())") { store.commitShape() }
                    .buttonStyle(.borderedProminent)
            }
            .buttonStyle(.bordered)
            Text(hint)
                .font(.caption)
                .foregroundStyle(.golfSecondaryText)
        }
    }

    private var hint: String {
        switch store.mode {
        case .pan: "Move the map, then choose Draw or Walk to trace. Tap a feature above to edit its shape."
        case .draw: "Drag a finger around the edge, or tap points. Pinch to zoom."
        case .walk: "Walk the edge; a point is added every 2 meters."
        }
    }
}

/// Searches the shared database, built-in data, and OpenStreetMap, then loads a course into the draft.
private struct CourseImportSheet: View {
    let store: CourseEditorStore

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [CourseImportMatch]?
    @State private var searching = false
    @State private var failure: String?
    @State private var replacing: CourseImportMatch?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        TextField("Course name", text: $query)
                            .submitLabel(.search)
                            .onSubmit(search)
                        if searching { ProgressView() }
                    }
                } footer: {
                    Text("Searches the shared database, built-in courses, and OpenStreetMap.")
                }
                if let failure {
                    Text(failure).foregroundStyle(.golfDestructive)
                }
                if let results {
                    Section(results.isEmpty ? "No courses found for \"\(query)\"" : "Matches") {
                        ForEach(results) { match in
                            Button { choose(match) } label: {
                                VStack(alignment: .leading, spacing: GolfSpacing.xxs) {
                                    HStack {
                                        Text(match.name).foregroundStyle(.golfPrimaryText)
                                        Spacer()
                                        Text(match.source.label)
                                            .font(.caption.weight(.bold))
                                            .foregroundStyle(match.source == .database ? Color.golfBrand : .golfSecondaryText)
                                    }
                                    if let subtitle = match.subtitle {
                                        Text(subtitle).font(.caption).foregroundStyle(.golfSecondaryText).lineLimit(2)
                                    }
                                }
                            }
                            .disabled(store.isImporting)
                        }
                    }
                }
            }
            .navigationTitle("Find course data")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Search", action: search).disabled(query.trimmingCharacters(in: .whitespaces).isEmpty || searching)
                }
            }
            .overlay { if store.isImporting { ProgressView("Loading course…").padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: GolfRadius.small)) } }
            .confirmationDialog("Replace current draft?", isPresented: Binding(get: { replacing != nil }, set: { if !$0 { replacing = nil } }), titleVisibility: .visible, presenting: replacing) { match in
                Button("Replace", role: .destructive) { load(match) }
            } message: { _ in
                Text("Loading course data replaces the features you've traced so far.")
            }
        }
        .onAppear { query = store.draft.trimmedName }
    }

    private func search() {
        let text = query.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        searching = true
        failure = nil
        Task {
            defer { searching = false }
            do {
                results = try await store.search(text)
            } catch {
                results = nil
                failure = error.localizedDescription
            }
        }
    }

    private func choose(_ match: CourseImportMatch) {
        if store.draft.features.isEmpty { load(match) } else { replacing = match }
    }

    private func load(_ match: CourseImportMatch) {
        Task {
            await store.load(match)
            dismiss()
        }
    }
}
