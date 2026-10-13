import GolfCore
import GolfDesign
import MapKit
import SwiftUI

/// Course overlays, pins, and the live line to the green on a hole-up rotated map.
struct HoleMapView: View {
    let store: RoundStore
    let user: Coordinate?
    let isSimulated: Bool
    let imagery: Bool
    let recenterToken: Int
    let onTap: ((Coordinate) -> Void)?

    @State private var position: MapCameraPosition = .automatic
    @State private var visibleSize: CGSize = .zero
    @State private var requestedCamera: MapCamera?
    @State private var fitPassesRemaining = 0
    @State private var isFramedOnHole = false

    var body: some View {
        MapReader { proxy in
            Map(position: $position, interactionModes: [.pan, .zoom, .rotate]) {
                ForEach(store.mapOverlays) { overlay in
                    MapPolygon(coordinates: overlay.coordinates.map(\.clCoordinate))
                        .foregroundStyle(overlay.color.color.opacity(overlay.opacity))
                        .stroke(overlay.isActive ? overlay.border.color.opacity(0.85) : .clear, lineWidth: 1.5)
                }
                ForEach(store.holeLines.indices, id: \.self) { index in
                    MapPolyline(coordinates: store.holeLines[index].map(\.clCoordinate))
                        .stroke(GolfMapPalette.holeLine.color.opacity(0.7), style: StrokeStyle(lineWidth: 2, dash: [6, 6]))
                }
                if let origin = store.gpsOrigin(user), let green = store.hole.green {
                    MapPolyline(coordinates: [origin.clCoordinate, green.clCoordinate])
                        .stroke(GolfMapPalette.measureLine.color, lineWidth: 3)
                }
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
                        Button {
                            store.selectedPinID = store.selectedPinID == pin.id ? nil : pin.id
                        } label: {
                            PinMarker(number: pin.shotNumber, lostBall: pin.pinType == .lostBall, selected: store.selectedPinID == pin.id)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(pinTitle(pin))
                        .accessibilityAddTraits(store.selectedPinID == pin.id ? .isSelected : [])
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
            .mapStyle(imagery ? .imagery(elevation: .flat) : .standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll))
            .mapControls {
                MapCompass()
                MapScaleView()
            }
            .onTapGesture { point in
                guard let onTap, let coordinate = proxy.convert(point, from: .local) else { return }
                onTap(Coordinate(coordinate))
            }
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
