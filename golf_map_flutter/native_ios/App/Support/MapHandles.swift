import GolfCore
import GolfDesign
import MapKit
import SwiftUI

/// A map point the player can tap or drag. `visualOffset` is where its marker's center sits relative to the
/// coordinate on screen, for markers anchored at their bottom.
struct MapHandle<ID: Hashable> {
    let id: ID
    let coordinate: Coordinate
    var isDraggable = true
    var visualOffset: CGSize = .zero
}

extension View {
    /// Taps and drags for map points, recognized on the map itself. Gestures inside `Annotation` content never
    /// receive a drag, and a tap on the map also fires for a tap on an annotation, so markers should only draw
    /// (`allowsHitTesting(false)`) and let this find the one under the finger. `dragging` is set from touch-down
    /// on a draggable handle until release, so the map can turn off panning.
    func mapHandles<ID: Hashable>(
        _ handles: [MapHandle<ID>],
        proxy: MapProxy,
        dragging: Binding<ID?>,
        onTap: @escaping (ID) -> Void = { _ in },
        onMapTap: ((Coordinate) -> Void)? = nil,
        onDrag: @escaping (ID, Coordinate, _ ended: Bool) -> Void
    ) -> some View {
        modifier(MapHandleGestures(handles: handles, proxy: proxy, dragging: dragging, onTap: onTap, onMapTap: onMapTap, onDrag: onDrag))
    }
}

private struct MapHandleGestures<ID: Hashable>: ViewModifier {
    let handles: [MapHandle<ID>]
    let proxy: MapProxy
    @Binding var dragging: ID?
    let onTap: (ID) -> Void
    let onMapTap: ((Coordinate) -> Void)?
    let onDrag: (ID, Coordinate, Bool) -> Void

    /// Set at touch-down: the handle under the finger, or nil for empty map, and where on it the finger landed.
    @State private var press: Press?

    private struct Press {
        let id: ID?
        let grabOffset: CGSize
    }

    private static var hitRadius: CGFloat { GolfMetrics.minimumHitTarget / 2 }
    private static var dragThreshold: CGFloat { 4 }

    func body(content: Content) -> some View {
        content
            .simultaneousGesture(SpatialTapGesture().onEnded { value in
                if let hit = handle(at: value.location) {
                    onTap(hit.handle.id)
                } else if let onMapTap, let coordinate = proxy.convert(value.location, from: .local) {
                    onMapTap(Coordinate(coordinate))
                }
            })
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if press == nil {
                            let hit = handle(at: value.startLocation).flatMap { $0.handle.isDraggable ? $0 : nil }
                            press = Press(id: hit?.handle.id, grabOffset: hit?.grabOffset ?? .zero)
                            dragging = hit?.handle.id
                        }
                        guard let press, let id = press.id, moved(value) else { return }
                        if let coordinate = coordinate(value.location, press) { onDrag(id, coordinate, false) }
                    }
                    .onEnded { value in
                        defer {
                            press = nil
                            dragging = nil
                        }
                        guard let press, let id = press.id, moved(value) else { return }
                        if let coordinate = coordinate(value.location, press) { onDrag(id, coordinate, true) }
                    }
            )
    }

    private func moved(_ value: DragGesture.Value) -> Bool {
        hypot(value.translation.width, value.translation.height) >= Self.dragThreshold
    }

    /// Keeps the spot the finger grabbed under the finger, so a marker drawn above its point doesn't jump.
    private func coordinate(_ location: CGPoint, _ press: Press) -> Coordinate? {
        let point = CGPoint(x: location.x - press.grabOffset.width, y: location.y - press.grabOffset.height)
        return proxy.convert(point, from: .local).map(Coordinate.init)
    }

    /// The nearest handle whose marker is within reach of `location`; later handles win ties, as they draw on top.
    private func handle(at location: CGPoint) -> (handle: MapHandle<ID>, grabOffset: CGSize)? {
        var best: (handle: MapHandle<ID>, grabOffset: CGSize, distance: CGFloat)?
        for handle in handles {
            guard let anchor = proxy.convert(handle.coordinate.clCoordinate, to: .local) else { continue }
            let center = CGPoint(x: anchor.x + handle.visualOffset.width, y: anchor.y + handle.visualOffset.height)
            let distance = hypot(location.x - center.x, location.y - center.y)
            guard distance <= Self.hitRadius, distance <= (best?.distance ?? .infinity) else { continue }
            best = (handle, CGSize(width: location.x - anchor.x, height: location.y - anchor.y), distance)
        }
        return best.map { ($0.handle, $0.grabOffset) }
    }
}
