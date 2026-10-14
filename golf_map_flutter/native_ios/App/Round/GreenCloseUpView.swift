import GolfCore
import GolfDesign
import MapKit
import SwiftUI

/// Close-up of a green with a flag the player drags to today's hole location. Distance runs from GPS to the flag.
struct GreenCloseUpView: View {
    let store: RoundStore
    let imagery: Bool

    @Environment(LocationService.self) private var location
    @Environment(\.dismiss) private var dismiss
    @State private var hole: String
    @State private var flag: Coordinate?
    @State private var dragging: Coordinate?
    @State private var flagDragging: Bool?
    @State private var position: MapCameraPosition = .automatic

    init(store: RoundStore, imagery: Bool) {
        self.store = store
        self.imagery = imagery
        _hole = State(initialValue: store.round.selectedHole)
    }

    private var holeFeatures: [GolfFeature] {
        HoleGeometry.features(store.courseFeatures, course: store.round.courseName, hole: hole)
    }

    private var greenRings: [[Coordinate]] {
        holeFeatures.filter { $0.isType("green") }.flatMap(\.geometry.rings).filter { $0.count >= 3 }
    }

    private var defaultFlag: Coordinate? { HoleGeometry.greenCenter(holeFeatures) }
    private var effectiveFlag: Coordinate? { dragging ?? flag ?? defaultFlag }

    private static let flagSize: CGFloat = 56

    /// The flag is anchored at its base, so its marker sits half its height above the hole location.
    private var flagHandle: [MapHandle<Bool>] {
        effectiveFlag.map { [MapHandle(id: true, coordinate: $0, visualOffset: CGSize(width: 0, height: -Self.flagSize / 2))] } ?? []
    }

    private var yards: Int? {
        guard let user = location.coordinate, let effectiveFlag else { return nil }
        return GeoMath.yardsBetween(user, effectiveFlag)
    }

    var body: some View {
        MapReader { proxy in
            Map(position: $position, interactionModes: flagDragging == nil ? [.pan, .zoom, .rotate] : []) {
                ForEach(greenRings.indices, id: \.self) { index in
                    MapPolygon(coordinates: greenRings[index].map(\.clCoordinate))
                        .foregroundStyle(GolfMapPalette.green.color.opacity(0.55))
                        .stroke(GolfMapPalette.green.color, lineWidth: 2)
                }
                if let user = location.coordinate, let effectiveFlag {
                    MapPolyline(coordinates: [user.clCoordinate, effectiveFlag.clCoordinate])
                        .stroke(GolfMapPalette.measureLine.color, lineWidth: 3)
                }
                if let effectiveFlag {
                    Annotation("Hole location", coordinate: effectiveFlag.clCoordinate, anchor: .bottom) {
                        Image(systemName: "flag.fill")
                            .font(.largeTitle)
                            .foregroundStyle(GolfMapPalette.lostBallPin.color)
                            .shadow(color: .white, radius: 1)
                            .shadow(color: .black.opacity(0.6), radius: 3)
                            .frame(minWidth: Self.flagSize, minHeight: Self.flagSize)
                            .allowsHitTesting(false)
                            .accessibilityLabel("Hole location flag")
                            .accessibilityHint("Drag to where the hole is cut today")
                    }
                    .annotationTitles(.hidden)
                }
                UserAnnotation()
            }
            .mapStyle(imagery ? .imagery(elevation: .flat) : .standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll))
            .mapHandles(flagHandle, proxy: proxy, dragging: $flagDragging) { _, coordinate, ended in
                if ended {
                    flag = coordinate
                    dragging = nil
                } else {
                    dragging = coordinate
                }
            }
        }
        .background(GolfMapPalette.courseBackground.color.ignoresSafeArea())
        .safeAreaInset(edge: .top, spacing: 0) { header }
        .safeAreaInset(edge: .bottom, spacing: 0) { readout }
        .onChange(of: hole, initial: true) {
            flag = nil
            dragging = nil
            focusOnGreen()
        }
    }

    private var header: some View {
        HStack {
            Button("Done") { dismiss() }
                .frame(minHeight: GolfMetrics.minimumHitTarget)
            Spacer()
            Menu {
                Picker("Hole", selection: $hole) {
                    ForEach(store.round.holes, id: \.self) { Text("Hole \($0)").tag($0) }
                }
            } label: {
                HStack(spacing: GolfSpacing.xxs) {
                    Text("Hole \(hole) green").font(.headline)
                    Image(systemName: "chevron.down").font(.caption.weight(.bold)).accessibilityHidden(true)
                }
                .frame(minHeight: GolfMetrics.minimumHitTarget)
                .foregroundStyle(.golfPrimaryText)
            }
            .accessibilityHint("Choose a hole")
            Spacer()
            Button("Reset") {
                flag = nil
                focusOnGreen()
            }
            .disabled(flag == nil)
            .frame(minHeight: GolfMetrics.minimumHitTarget)
        }
        .padding(.horizontal, GolfSpacing.m)
        .background(.thickMaterial)
    }

    private var readout: some View {
        VStack(spacing: GolfSpacing.xxs) {
            Text(yards.map { "\($0)" } ?? "—")
                .font(GolfType.yardage(size: 56))
                .contentTransition(.numericText())
            Text(yards == nil ? "Waiting for GPS" : "Yards from you to the flag")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.golfSecondaryText)
            Text("Drag the flag to today's hole location.")
                .font(.footnote)
                .foregroundStyle(.golfSecondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(GolfSpacing.m)
        .background(.golfSurface)
        .accessibilityElement(children: .combine)
    }

    /// Green-up along the hole's direction, zoomed so the whole green fits with some margin.
    private func focusOnGreen() {
        guard let center = defaultFlag else { return }
        let points = greenRings.flatMap { $0 }
        let radius = points.map { GeoMath.distanceMeters(center, $0) }.max() ?? 20
        let heading = store.hole.hole == hole
            ? store.hole.orientation.map { GeoMath.bearing($0.tee, $0.green) } ?? 0
            : HoleGeometry.orientation(holeFeatures).map { GeoMath.bearing($0.tee, $0.green) } ?? 0
        position = .camera(MapCamera(
            centerCoordinate: center.clCoordinate,
            distance: max(radius * 7, 120),
            heading: (heading + 360).truncatingRemainder(dividingBy: 360),
            pitch: 0
        ))
    }
}
