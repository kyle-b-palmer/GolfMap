import GolfCore
import GolfDesign
import MapKit
import SwiftUI
import UIKit

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
    /// on a draggable handle until release.
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

    /// The handle under the finger at touch-down, and where on it the finger landed.
    private struct Press {
        let id: ID
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
            .gesture(TouchDownDrag<Press>(
                begin: { location in
                    guard let hit = handle(at: location), hit.handle.isDraggable else { return nil }
                    dragging = hit.handle.id
                    return Press(id: hit.handle.id, grabOffset: hit.grabOffset)
                },
                changed: { press, location, translation, ended in
                    if ended { dragging = nil }
                    guard hypot(translation.width, translation.height) >= Self.dragThreshold,
                          let coordinate = coordinate(location, press) else { return }
                    onDrag(press.id, coordinate, ended)
                }
            ))
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

/// A one-finger drag that decides at touch-down, through `begin`, whether to take the touch. The map's pan
/// recognizers wait for it to fail, so a drag that starts on a handle never pans the map, however late the
/// next frame is.
private struct TouchDownDrag<Payload>: UIGestureRecognizerRepresentable {
    let begin: (CGPoint) -> Payload?
    let changed: (Payload, _ location: CGPoint, _ translation: CGSize, _ ended: Bool) -> Void

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        let converter: CoordinateSpaceConverter
        var payload: Payload?
        var start = CGPoint.zero

        init(converter: CoordinateSpaceConverter) {
            self.converter = converter
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            true
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool {
            other is UIPanGestureRecognizer
        }
    }

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
        Coordinator(converter: converter)
    }

    func makeUIGestureRecognizer(context: Context) -> TouchDownRecognizer {
        let recognizer = TouchDownRecognizer()
        recognizer.delegate = context.coordinator
        recognizer.cancelsTouchesInView = false
        updateUIGestureRecognizer(recognizer, context: context)
        return recognizer
    }

    func updateUIGestureRecognizer(_ recognizer: TouchDownRecognizer, context: Context) {
        let coordinator = context.coordinator
        recognizer.shouldBegin = { [begin] in
            let location = coordinator.converter.location(in: .local)
            coordinator.start = location
            coordinator.payload = begin(location)
            return coordinator.payload != nil
        }
    }

    func handleUIGestureRecognizerAction(_ recognizer: TouchDownRecognizer, context: Context) {
        let coordinator = context.coordinator
        guard let payload = coordinator.payload else { return }
        let location = context.converter.location(in: .local)
        let translation = CGSize(width: location.x - coordinator.start.x, height: location.y - coordinator.start.y)
        switch recognizer.state {
        case .changed:
            changed(payload, location, translation, false)
        case .ended, .cancelled:
            coordinator.payload = nil
            changed(payload, location, translation, true)
        default:
            break
        }
    }
}

private final class TouchDownRecognizer: UIGestureRecognizer {
    var shouldBegin: () -> Bool = { false }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)
        guard state == .possible else { return }
        state = numberOfTouches == 1 && shouldBegin() ? .began : .failed
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesMoved(touches, with: event)
        if state == .began || state == .changed { state = .changed }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesEnded(touches, with: event)
        if state == .began || state == .changed { state = .ended }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesCancelled(touches, with: event)
        if state == .began || state == .changed { state = .cancelled }
    }
}
