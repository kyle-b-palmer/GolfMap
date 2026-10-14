import GolfCore
import GolfDesign
import MapKit
import SwiftUI

/// Which optional map content is visible. Stored in settings and toggled from the Layers menu.
struct MapLayers: Equatable {
    var imagery = true
    /// Off draws only the course shapes on a plain background, which works without map tiles.
    var mapUnderCourse = true
    var idealLine = true
    var bunkerDistances = false
    var dispersion = false
}

/// Course overlays, pins, measurements, and planning lines on a hole-up rotated map.
struct HoleMapView: View {
    let store: RoundStore
    let user: Coordinate?
    let isSimulated: Bool
    let layers: MapLayers
    let recenterToken: Int
    let onTap: (Coordinate) -> Void

    @State private var position: MapCameraPosition = .automatic
    @State private var visibleSize: CGSize = .zero
    @State private var requestedCamera: MapCamera?
    @State private var fitPassesRemaining = 0
    @State private var isFramedOnHole = false
    @State private var chainDrag: (index: Int, coordinate: Coordinate)?
    @State private var aimDrag: Coordinate?
    @State private var dragging: MapTarget?

    private enum MapTarget: Hashable {
        case pin(String)
        case chain(Int)
        case aim
    }

    var body: some View {
        MapReader { proxy in
            Map(position: $position, interactionModes: dragging == nil ? [.pan, .zoom, .rotate] : []) {
                if !layers.mapUnderCourse, let center = store.hole.green ?? store.hole.orientation?.tee {
                    MapPolygon(coordinates: Self.backgroundBox(around: center))
                        .foregroundStyle(GolfMapPalette.courseBackground.color)
                }
                ForEach(store.mapOverlays) { overlay in
                    MapPolygon(coordinates: overlay.coordinates.map(\.clCoordinate))
                        .foregroundStyle(overlay.color.color.opacity(overlay.opacity))
                        .stroke(overlay.isActive ? overlay.border.color.opacity(0.85) : .clear, lineWidth: 1.5)
                }
                ForEach(store.holeLines.indices, id: \.self) { index in
                    MapPolyline(coordinates: store.holeLines[index].map(\.clCoordinate))
                        .stroke(GolfMapPalette.holeLine.color.opacity(0.7), style: StrokeStyle(lineWidth: 2, dash: [6, 6]))
                }
                if layers.dispersion {
                    let heaviest = store.dispersion.map(\.weight).max() ?? 1
                    ForEach(Array(store.dispersion.enumerated()), id: \.offset) { _, point in
                        let share = point.weight / max(heaviest, 1)
                        MapCircle(center: CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude), radius: 3 + share * 6)
                            .foregroundStyle(GolfMapPalette.dispersion.color.opacity(0.15 + share * 0.35))
                            .stroke(GolfMapPalette.dispersion.color.opacity(0.5), lineWidth: 1)
                    }
                }
                idealLineContent
                measurementContent
                clubAimContent
                bunkerContent
                if let green = store.hole.green {
                    Annotation("Green", coordinate: green.clCoordinate, anchor: .bottom) {
                        Image(systemName: "flag.fill")
                            .font(.title3)
                            .foregroundStyle(.white)
                            .shadow(radius: 2)
                            .accessibilityHidden(true)
                    }
                    .annotationTitles(.hidden)
                }
                ForEach(store.round.currentPins) { pin in
                    Annotation(pinTitle(pin), coordinate: pin.coordinate.clCoordinate) {
                        PinMarker(number: pin.shotNumber, lostBall: pin.pinType == .lostBall, selected: store.selectedPinID == pin.id)
                            .allowsHitTesting(false)
                            .accessibilityLabel(pinTitle(pin))
                            .accessibilityAddTraits(store.selectedPinID == pin.id ? [.isButton, .isSelected] : .isButton)
                            .accessibilityAction { tapped(.pin(pin.id)) }
                    }
                    .annotationTitles(.hidden)
                }
                if isSimulated, let user {
                    Annotation("Simulated location", coordinate: user.clCoordinate) {
                        Circle()
                            .fill(GolfPalette.hazard.dark.color)
                            .frame(width: 18, height: 18)
                            .overlay(Circle().stroke(.white, lineWidth: 3))
                    }
                    .annotationTitles(.hidden)
                } else {
                    UserAnnotation()
                }
            }
            .mapStyle(mapStyle)
            .mapControls {
                MapCompass()
                MapScaleView()
            }
            .mapHandles(handles, proxy: proxy, dragging: $dragging, onTap: tapped, onMapTap: onTap, onDrag: dragged)
            // The layout frame stops at the dock even though the map draws beneath it.
            .onGeometryChange(for: CGSize.self) { $0.size } action: { size in
                let firstLayout = visibleSize == .zero
                visibleSize = size
                if firstLayout || isFramedOnHole || fitPassesRemaining > 0 { frameHole(animated: !firstLayout) }
            }
            .onMapCameraChange(frequency: .onEnd) { context in
                refineHoleFit(camera: context.camera, proxy: proxy)
            }
        }
        .onChange(of: store.hole.hole, initial: true) {
            frameHole(animated: false)
        }
        .onChange(of: recenterToken) {
            frameHole(animated: true)
        }
    }

    /// Course-only mode covers the imagery style because it has no labels; the standard style draws names above overlays.
    private var mapStyle: MapStyle {
        layers.imagery || !layers.mapUnderCourse
            ? .imagery(elevation: .flat)
            : .standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll)
    }

    /// About 11 km across: enough to cover the course at any zoom the round uses.
    private static func backgroundBox(around center: Coordinate) -> [CLLocationCoordinate2D] {
        let span = 0.05
        return [
            CLLocationCoordinate2D(latitude: center.latitude - span, longitude: center.longitude - span),
            CLLocationCoordinate2D(latitude: center.latitude + span, longitude: center.longitude - span),
            CLLocationCoordinate2D(latitude: center.latitude + span, longitude: center.longitude + span),
            CLLocationCoordinate2D(latitude: center.latitude - span, longitude: center.longitude + span),
        ]
    }

    // MARK: Planning and measuring

    @MapContentBuilder
    private var idealLineContent: some MapContent {
        if layers.idealLine, store.showsIdealLine, let start = store.gpsOrigin(user), let green = store.hole.green {
            let segments = HoleGeometry.plannedShots(start: start, green: green, store.hole.features)
            ForEach(segments, id: \.shotNumber) { segment in
                MapPolyline(coordinates: [segment.from.clCoordinate, segment.to.clCoordinate])
                    .stroke(.white.opacity(0.5), lineWidth: 5)
                MapPolyline(coordinates: [segment.from.clCoordinate, segment.to.clCoordinate])
                    .stroke(GolfMapPalette.idealLine.color, lineWidth: 3)
                if let carry = segment.carryPoint {
                    MapPolyline(coordinates: [segment.from.clCoordinate, carry.clCoordinate])
                        .stroke(.white, style: StrokeStyle(lineWidth: 2, dash: [4, 4]))
                }
                Annotation("Planned shot \(segment.shotNumber)", coordinate: midpoint(segment.from, segment.to)) {
                    MapDistanceLabel(yards: segment.yards, prefix: "\(segment.shotNumber)", tint: GolfMapPalette.idealLine)
                }
                .annotationTitles(.hidden)
            }
        }
    }

    @MapContentBuilder
    private var measurementContent: some MapContent {
        let chain = displayedChain
        let origin = chain.isEmpty ? store.gpsOrigin(user) : store.chainOrigin(user)
        if let green = store.hole.green {
            if chain.isEmpty {
                if let origin {
                    MapPolyline(coordinates: [origin.clCoordinate, green.clCoordinate])
                        .stroke(GolfMapPalette.measureLine.color, lineWidth: 3)
                }
            } else {
                let path = (origin.map { [$0] } ?? []) + chain.map(\.coordinate)
                MapPolyline(coordinates: path.map(\.clCoordinate))
                    .stroke(GolfMapPalette.measureLine.color, lineWidth: 3)
                if let last = chain.last {
                    MapPolyline(coordinates: [last.coordinate.clCoordinate, green.clCoordinate])
                        .stroke(GolfMapPalette.measureLine.color.opacity(0.8), style: StrokeStyle(lineWidth: 2, dash: [6, 5]))
                    Annotation("To green", coordinate: midpoint(last.coordinate, green)) {
                        MapDistanceLabel(yards: GeoMath.yardsBetween(last.coordinate, green), tint: GolfMapPalette.measureLine)
                    }
                    .annotationTitles(.hidden)
                }
            }
        }
        ForEach(Array(chain.enumerated()), id: \.offset) { index, point in
            let from = index == 0 ? store.chainOrigin(user) : chain[index - 1].coordinate
            if let from, point.segmentYards > 0 {
                Annotation("Segment \(index + 1)", coordinate: midpoint(from, point.coordinate)) {
                    MapDistanceLabel(yards: point.segmentYards, tint: GolfMapPalette.measureLine)
                }
                .annotationTitles(.hidden)
            }
            Annotation("Measure point \(index + 1)", coordinate: point.coordinate.clCoordinate) {
                ChainMarker(number: index + 1, selected: store.selectedChainIndex == index)
                    .allowsHitTesting(false)
                    .accessibilityLabel("Measure point \(index + 1), \(point.segmentYards) yards")
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction { tapped(.chain(index)) }
            }
            .annotationTitles(.hidden)
        }
    }

    /// The stored chain with any in-progress drag applied, measured from where the player is now.
    private var displayedChain: [MeasurementChainPoint] {
        var chain = store.chain
        if let chainDrag { chain = MeasurementChain.moving(chain, index: chainDrag.index, to: chainDrag.coordinate) }
        return MeasurementChain.recalculated(chain, origin: store.chainOrigin(user))
    }

    @MapContentBuilder
    private var clubAimContent: some MapContent {
        if let target = aimDrag ?? store.clubAim {
            if let origin = user ?? store.gpsOrigin(user) {
                let yards = GeoMath.yardsBetween(origin, target)
                MapPolyline(coordinates: [origin.clCoordinate, target.clCoordinate])
                    .stroke(GolfMapPalette.clubAim.color, style: StrokeStyle(lineWidth: 3, dash: [8, 6]))
                if yards >= 1 {
                    Annotation("Club target distance", coordinate: midpoint(origin, target)) {
                        MapDistanceLabel(yards: yards, tint: GolfMapPalette.clubAim)
                    }
                    .annotationTitles(.hidden)
                }
            }
            Annotation("Club target", coordinate: target.clCoordinate) {
                Image(systemName: "scope")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(GolfMapPalette.clubAim.color)
                    .shadow(color: .black.opacity(0.6), radius: 2)
                    .frame(width: GolfMetrics.minimumHitTarget, height: GolfMetrics.minimumHitTarget)
                    .allowsHitTesting(false)
                    .accessibilityLabel("Club target")
            }
            .annotationTitles(.hidden)
        }
    }

    @MapContentBuilder
    private var bunkerContent: some MapContent {
        if layers.bunkerDistances, let reference = store.bunkerReference(user) {
            let bunkers = HoleGeometry.bunkerDistances(from: reference, store.hole.features).filter { $0.point != nil && abs($0.yards) >= 1 }
            ForEach(Array(bunkers.enumerated()), id: \.offset) { _, bunker in
                if let point = bunker.point {
                    Annotation(bunker.label, coordinate: point.clCoordinate) {
                        MapDistanceLabel(yards: abs(bunker.yards), suffix: bunker.yards < 0 ? "BK" : nil, tint: GolfMapPalette.bunker)
                            .accessibilityLabel(bunker.yards < 0 ? "\(bunker.label), \(-bunker.yards) yards behind" : "\(bunker.label), \(bunker.yards) yards")
                    }
                    .annotationTitles(.hidden)
                }
            }
        }
    }

    /// Pins select on tap; measure points and the club target also drag, unless the hole is locked.
    private var handles: [MapHandle<MapTarget>] {
        let movable = !store.round.isCurrentHoleLocked
        var handles = displayedChain.enumerated().map { MapHandle(id: MapTarget.chain($0.offset), coordinate: $0.element.coordinate, isDraggable: movable) }
        if let target = aimDrag ?? store.clubAim {
            handles.append(MapHandle(id: .aim, coordinate: target, isDraggable: movable))
        }
        handles += store.round.currentPins.map { MapHandle(id: .pin($0.id), coordinate: $0.coordinate, isDraggable: false) }
        return handles
    }

    private func tapped(_ target: MapTarget) {
        switch target {
        case .pin(let id): store.selectedPinID = store.selectedPinID == id ? nil : id
        case .chain(let index): store.selectedChainIndex = store.selectedChainIndex == index ? nil : index
        case .aim: break
        }
    }

    private func dragged(_ target: MapTarget, to coordinate: Coordinate, ended: Bool) {
        switch target {
        case .chain(let index):
            chainDrag = ended ? nil : (index, coordinate)
            if ended { store.moveChainPoint(index, to: coordinate, user: user) }
        case .aim:
            aimDrag = ended ? nil : coordinate
            if ended { store.setClubAim(coordinate) }
        case .pin:
            break
        }
    }

    private func midpoint(_ a: Coordinate, _ b: Coordinate) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: (a.latitude + b.latitude) / 2, longitude: (a.longitude + b.longitude) / 2)
    }

    // MARK: Camera

    private func frameHole(animated: Bool) {
        guard let camera = holeCamera() else { return }
        fitPassesRemaining = 3
        move(to: camera, animated: animated)
    }

    private func move(to camera: MapCamera, animated: Bool) {
        requestedCamera = camera
        if animated {
            withAnimation(.smooth) { position = .camera(camera) }
        } else {
            position = .camera(camera)
        }
    }

    /// MapKit's zoom for a camera distance depends on the view's size, so after the first guess
    /// measure where the tee and green landed and correct until the hole fills the visible area.
    private func refineHoleFit(camera: MapCamera, proxy: MapProxy) {
        guard let requestedCamera, camera.isClose(to: requestedCamera) else {
            // Mid-fit, MapKit can still report the previous camera. Otherwise a gesture moved the map,
            // so stop keeping the hole framed through layout changes.
            if fitPassesRemaining == 0 { isFramedOnHole = false }
            return
        }
        guard fitPassesRemaining > 0, visibleSize != .zero else { return }
        fitPassesRemaining -= 1
        guard let orientation = store.hole.orientation,
              let tee = proxy.convert(orientation.tee.clCoordinate, to: .local),
              let green = proxy.convert(orientation.green.clCoordinate, to: .local),
              let anchor = proxy.convert(camera.centerCoordinate, to: .local)
        else { return }

        // Room for the flag above the green and the map buttons on the trailing edge.
        let target = CGRect(origin: .zero, size: visibleSize)
            .inset(by: UIEdgeInsets(top: 48, left: 32, bottom: 24, right: 64))
        guard target.width > 0, target.height > 0 else { return }
        let middle = CGPoint(x: (tee.x + green.x) / 2, y: (tee.y + green.y) / 2)
        let fitScale = max(abs(tee.y - green.y) / target.height, abs(tee.x - green.x) / target.width)
        let distance = max(camera.distance * fitScale, Self.minimumCameraDistance)
        let scale = distance / camera.distance
        if abs(scale - 1) < 0.06, hypot(middle.x - target.midX, middle.y - target.midY) < 12 {
            fitPassesRemaining = 0
            isFramedOnHole = true
            return
        }
        // After zooming by `scale` about screen point c, p lands at anchor + (p - c) / scale.
        let center = CGPoint(
            x: middle.x - (target.midX - anchor.x) * scale,
            y: middle.y - (target.midY - anchor.y) * scale
        )
        let next = MapCamera(
            centerCoordinate: proxy.convert(center, from: .local) ?? camera.centerCoordinate,
            distance: distance,
            heading: camera.heading,
            pitch: 0
        )
        if fitPassesRemaining == 0 { isFramedOnHole = true }
        move(to: next, animated: false)
    }

    private static let minimumCameraDistance: Double = 350

    private func pinTitle(_ pin: PinnedShot) -> String {
        pin.pinType == .lostBall ? "Lost ball, shot \(pin.shotNumber)" : "Shot \(pin.shotNumber)"
    }

    /// Tee at the bottom, green at the top; `refineHoleFit` corrects the framing once laid out.
    private func holeCamera() -> MapCamera? {
        guard let orientation = store.hole.orientation else { return nil }
        let length = GeoMath.distanceMeters(orientation.tee, orientation.green)
        let heading = GeoMath.bearing(orientation.tee, orientation.green)
        let center = GeoMath.destination(from: orientation.tee, bearing: heading, meters: length * 0.5)
        return MapCamera(
            centerCoordinate: center.clCoordinate,
            distance: max(length * 3.6, 450),
            heading: (heading + 360).truncatingRemainder(dividingBy: 360),
            pitch: 0
        )
    }
}

private extension MapCamera {
    func isClose(to other: MapCamera) -> Bool {
        let centerMeters = GeoMath.distanceMeters(Coordinate(centerCoordinate), Coordinate(other.centerCoordinate))
        let headingDelta = abs((heading - other.heading + 540).truncatingRemainder(dividingBy: 360) - 180)
        return centerMeters < 3 && abs(distance / other.distance - 1) < 0.03 && headingDelta < 2
    }
}

/// Yardage callout drawn on the map: dark chip with a colored border.
struct MapDistanceLabel: View {
    let yards: Int
    var prefix: String?
    var suffix: String?
    let tint: RGB

    var body: some View {
        HStack(spacing: 3) {
            if let prefix {
                Text(prefix).foregroundStyle(tint.color)
            }
            Text("\(yards)").foregroundStyle(.white)
            Text(suffix ?? "yd").foregroundStyle(.white.opacity(0.7))
        }
        .font(.caption.weight(.heavy).monospacedDigit())
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Color(red: 0.07, green: 0.09, blue: 0.06).opacity(0.92), in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(tint.color, lineWidth: 1))
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
    }
}

private struct ChainMarker: View {
    let number: Int
    let selected: Bool

    var body: some View {
        Text("\(number)")
            .font(.caption2.weight(.bold).monospacedDigit())
            .foregroundStyle(.white)
            .frame(width: 22, height: 22)
            .background(GolfMapPalette.measureLine.color, in: Circle())
            .overlay(Circle().stroke(selected ? GolfMapPalette.selection.color : .white, lineWidth: selected ? 4 : 2))
            .frame(width: GolfMetrics.minimumHitTarget, height: GolfMetrics.minimumHitTarget)
            .contentShape(Rectangle())
    }
}

private struct PinMarker: View {
    let number: Int
    let lostBall: Bool
    let selected: Bool

    var body: some View {
        Text("\(number)")
            .font(.caption.weight(.bold).monospacedDigit())
            .foregroundStyle(.white)
            .frame(width: 26, height: 26)
            .background((lostBall ? GolfMapPalette.lostBallPin : GolfMapPalette.shotPin).color, in: Circle())
            .overlay(Circle().stroke(selected ? GolfMapPalette.selection.color : .white, lineWidth: selected ? 4 : 2))
            .overlay(alignment: .topTrailing) {
                if lostBall {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(.white, GolfMapPalette.lostBallPin.color)
                        .offset(x: 6, y: -6)
                }
            }
            .frame(width: GolfMetrics.minimumHitTarget, height: GolfMetrics.minimumHitTarget)
            .contentShape(Rectangle())
    }
}
