import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../config/app_config.dart';
import '../config/app_theme.dart';
import '../models/golf_feature.dart';
import '../models/measurement_chain.dart';
import '../models/pinned_shot.dart';
import '../utils/geo_utils.dart';
import 'map_marker_graphics.dart';

class GolfMapView extends StatefulWidget {
  const GolfMapView({
    super.key,
    required this.mapController,
    required this.features,
    required this.selectedCourse,
    required this.selectedHole,
    required this.showShotDirection,
    required this.greenCenter,
    required this.shotOrigin,
    required this.userCoord,
    required this.selectedTeeFeatureId,
    required this.usingGpsForShot,
    required this.onTap,
    required this.onLockedMeasurementDrag,
    required this.onLockedMeasurementDragEnd,
    required this.onSelectMeasurementPin,
    required this.onSelectTee,
    required this.onMapReady,
    this.pinnedShots = const [],
    this.lockedMeasurementPoints = const [],
    this.selectedMeasurementPinIndex,
  });

  final MapController mapController;
  final List<GolfFeature> features;
  final String? selectedCourse;
  final String selectedHole;
  final bool showShotDirection;
  final LatLng? greenCenter;
  final LatLng? shotOrigin;
  final LatLng? userCoord;
  final dynamic selectedTeeFeatureId;
  final bool usingGpsForShot;
  final void Function(LatLng) onTap;
  final void Function(int index, LatLng point) onLockedMeasurementDrag;
  final void Function(int index, LatLng point) onLockedMeasurementDragEnd;
  final void Function(int index) onSelectMeasurementPin;
  final void Function(dynamic featureId) onSelectTee;
  final VoidCallback onMapReady;
  final List<PinnedShot> pinnedShots;
  final List<MeasurementChainPoint> lockedMeasurementPoints;
  final int? selectedMeasurementPinIndex;

  @override
  State<GolfMapView> createState() => _GolfMapViewState();
}

class _GolfMapViewState extends State<GolfMapView> {
  int? _draggingLockedIndex;
  LatLng? _dragLockedCoord;
  Offset? _panAnchorScreen;
  DateTime? _lastDragNotify;
  List<Widget> _baseLayers = [];

  static const _lockedHitTarget = 52.0;
  static const _lockedPinHitPixels = 52.0;
  static const _dragNotifyInterval = Duration(milliseconds: 50);

  bool get _isDragging => _draggingLockedIndex != null;

  /// Keep marker graphics upright when the map is rotated tee → green.
  MarkerLayer _uprightMarkerLayer(List<Marker> markers) =>
      MarkerLayer(rotate: true, markers: markers);

  LatLng? get _chainTerminal {
    if (widget.lockedMeasurementPoints.isNotEmpty) {
      return widget.lockedMeasurementPoints.last.point;
    }
    return widget.shotOrigin;
  }

  LatLng _effectiveLockedPoint(int index) {
    if (_draggingLockedIndex == index && _dragLockedCoord != null) {
      return _dragLockedCoord!;
    }
    return widget.lockedMeasurementPoints[index].point;
  }

  List<LatLng> _measurementChainPoints() {
    final points = <LatLng>[];
    if (widget.shotOrigin != null) points.add(widget.shotOrigin!);
    for (var i = 0; i < widget.lockedMeasurementPoints.length; i++) {
      points.add(_effectiveLockedPoint(i));
    }
    return points;
  }

  void _addSegmentLine(
    List<Polyline> lines,
    LatLng from,
    LatLng to, {
    required bool dashed,
  }) {
    if (dashed) {
      lines.add(
        Polyline(
          points: [from, to],
          color: Colors.white.withValues(alpha: 0.55),
          strokeWidth: 5.5,
          pattern: StrokePattern.dashed(segments: [16, 9]),
        ),
      );
      lines.add(
        Polyline(
          points: [from, to],
          color: AppTheme.measureBlueBright,
          strokeWidth: 3.5,
          pattern: StrokePattern.dashed(segments: [16, 9]),
        ),
      );
      return;
    }

    lines.add(
      Polyline(
        points: [from, to],
        color: Colors.white.withValues(alpha: 0.45),
        strokeWidth: 5,
      ),
    );
    lines.add(
      Polyline(
        points: [from, to],
        color: AppTheme.measureBlue,
        strokeWidth: 3,
      ),
    );
  }

  Marker _segmentLabelMarker(LatLng from, LatLng to, int yards, int shotNumber) {
    final mid = LatLng(
      (from.latitude + to.latitude) / 2,
      (from.longitude + to.longitude) / 2,
    );
    return Marker(
      point: mid,
      width: 72,
      height: 22,
      alignment: Alignment.center,
      child: _ShotDistanceLabel(
        yards: yards,
        shotNumber: shotNumber,
        borderColor: AppTheme.measureBlue,
        textColor: const Color(0xFF90CAF9),
      ),
    );
  }

  List<Marker> _buildLockedMeasurementMarkers() {
    return [
      for (var i = 0; i < widget.lockedMeasurementPoints.length; i++)
        _draggableLockedMeasurementMarker(
          i,
          _effectiveLockedPoint(i),
          widget.lockedMeasurementPoints[i].shotNumber,
        ),
    ];
  }

  void _notifyLockedDrag(int index, LatLng point, {bool force = false}) {
    final now = DateTime.now();
    if (!force &&
        _lastDragNotify != null &&
        now.difference(_lastDragNotify!) < _dragNotifyInterval) {
      return;
    }
    _lastDragNotify = now;
    widget.onLockedMeasurementDrag(index, point);
  }

  Marker _draggableLockedMeasurementMarker(
    int index,
    LatLng point,
    int shotNumber,
  ) {
    final isDragging = _draggingLockedIndex == index;
    return Marker(
      point: point,
      width: _lockedHitTarget,
      height: _lockedHitTarget,
      alignment: Alignment.center,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => widget.onSelectMeasurementPin(index),
        onPanStart: (details) {
          final anchor = widget.lockedMeasurementPoints[index].point;
          final screen =
              widget.mapController.camera.latLngToScreenOffset(anchor);
          setState(() {
            _draggingLockedIndex = index;
            _dragLockedCoord = anchor;
            _panAnchorScreen = screen;
            _lastDragNotify = null;
          });
        },
        onPanUpdate: (details) {
          if (_draggingLockedIndex != index) return;
          final anchor = _panAnchorScreen;
          if (anchor == null) return;
          final nextScreen = anchor + details.delta;
          final updated = _screenOffsetToLatLng(nextScreen);
          if (updated == null) return;
          setState(() {
            _panAnchorScreen = nextScreen;
            _dragLockedCoord = updated;
          });
          _notifyLockedDrag(index, updated);
        },
        onPanEnd: (_) {
          if (_draggingLockedIndex != index) return;
          final finalCoord = _dragLockedCoord;
          setState(() {
            _draggingLockedIndex = null;
            _dragLockedCoord = null;
            _panAnchorScreen = null;
            _lastDragNotify = null;
          });
          if (finalCoord != null) {
            _notifyLockedDrag(index, finalCoord, force: true);
            widget.onLockedMeasurementDragEnd(index, finalCoord);
          }
        },
        onPanCancel: () {
          if (_draggingLockedIndex != index) return;
          final finalCoord =
              _dragLockedCoord ?? widget.lockedMeasurementPoints[index].point;
          setState(() {
            _draggingLockedIndex = null;
            _dragLockedCoord = null;
            _panAnchorScreen = null;
            _lastDragNotify = null;
          });
          _notifyLockedDrag(index, finalCoord, force: true);
          widget.onLockedMeasurementDragEnd(index, finalCoord);
        },
        child: _LockedMeasurementMarker(
          shotNumber: shotNumber,
          isDragging: isDragging,
          isSelected: widget.selectedMeasurementPinIndex == index,
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _rebuildBaseLayers();
  }

  @override
  void didUpdateWidget(GolfMapView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.features != widget.features ||
        oldWidget.selectedCourse != widget.selectedCourse ||
        oldWidget.selectedHole != widget.selectedHole ||
        oldWidget.selectedTeeFeatureId != widget.selectedTeeFeatureId ||
        oldWidget.usingGpsForShot != widget.usingGpsForShot ||
        oldWidget.greenCenter != widget.greenCenter) {
      _rebuildBaseLayers();
    }
    if (oldWidget.lockedMeasurementPoints != widget.lockedMeasurementPoints &&
        _draggingLockedIndex == null) {
      _dragLockedCoord = null;
    }
  }

  static const _courseMapBackground = Color(0xFF1A3328);

  void _rebuildBaseLayers() {
    final courseOnly = AppConfig.mapBackground == MapBackground.courseOnly;
    final inactiveFairwayOpacity = courseOnly ? 0.18 : 0.05;
    final inactiveGreenOpacity = courseOnly ? 0.12 : 0.1;
    final inactiveBunkerOpacity = courseOnly ? 0.15 : 0.1;

    _baseLayers = [
      if (AppConfig.mapBackground == MapBackground.openStreetMap)
        TileLayer(
          urlTemplate: AppConfig.openStreetMapTileUrl,
          userAgentPackageName: 'com.golfmapapp.golf_map_flutter',
          maxZoom: 19,
        ),
      PolygonLayer(
        polygons: _buildPolygons('fairway', 0xFF2CE06C, 0.35, inactiveFairwayOpacity),
      ),
      PolygonLayer(
        polygons: _buildPolygons('green', 0xFF00FF55, 0.6, inactiveGreenOpacity),
      ),
      PolygonLayer(
        polygons: _buildPolygons('bunker', 0xFFF0E3BC, 0.7, inactiveBunkerOpacity),
      ),
      PolygonLayer(polygons: _buildTeePolygons()),
      PolylineLayer(polylines: _buildHoleBoundaryPolylines()),
      _uprightMarkerLayer(_buildTeeMarkers()),
      _uprightMarkerLayer(_buildGreenPinMarkers()),
      if (widget.userCoord != null &&
          (widget.shotOrigin == null || widget.userCoord != widget.shotOrigin))
        _uprightMarkerLayer([_userMarker(widget.userCoord!)]),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return FlutterMap(
      mapController: widget.mapController,
      options: MapOptions(
        backgroundColor: AppConfig.mapBackground == MapBackground.courseOnly
            ? _courseMapBackground
            : const Color(0xFFE8E8E8),
        initialCenter: LatLng(
          AppConfig.defaultCenter[0],
          AppConfig.defaultCenter[1],
        ),
        initialZoom: 15,
        onTap: (_, point) {
          if (_isDragging) return;
          if (_lockedPinIndexNearTap(point) != null) return;
          if (!widget.usingGpsForShot) {
            final teeId = _teeIdNearTap(point);
            if (teeId != null) {
              widget.onSelectTee(teeId);
              return;
            }
          }
          widget.onTap(point);
        },
        onMapReady: widget.onMapReady,
        interactionOptions: InteractionOptions(
          flags: _isDragging
              ? InteractiveFlag.pinchZoom | InteractiveFlag.rotate
              : InteractiveFlag.all,
        ),
      ),
      children: [
        ..._baseLayers,
        if (AppConfig.mapBackground == MapBackground.openStreetMap)
          RichAttributionWidget(
            attributions: [
              TextSourceAttribution(
                'OpenStreetMap contributors',
                onTap: () {},
              ),
            ],
          ),
        if (widget.pinnedShots.isNotEmpty) ..._buildPinnedShotLayers(),
        if (widget.showShotDirection) ..._buildShotDirectionLayers(),
        if (widget.lockedMeasurementPoints.isNotEmpty)
          ..._buildMeasurementLayers(),
        if (widget.lockedMeasurementPoints.isNotEmpty)
          _uprightMarkerLayer(_buildLockedMeasurementMarkers()),
      ],
    );
  }

  int? _lockedPinIndexNearTap(LatLng tap) {
    if (widget.lockedMeasurementPoints.isEmpty) return null;

    final camera = widget.mapController.camera;
    final tapScreen = camera.latLngToScreenOffset(tap);

    int? closestIndex;
    var closestDist = _lockedPinHitPixels;

    for (var i = 0; i < widget.lockedMeasurementPoints.length; i++) {
      final pinScreen =
          camera.latLngToScreenOffset(_effectiveLockedPoint(i));
      final dist = (tapScreen - pinScreen).distance;
      if (dist < closestDist) {
        closestDist = dist;
        closestIndex = i;
      }
    }

    return closestIndex;
  }

  LatLng? _screenOffsetToLatLng(Offset screen) {
    try {
      return widget.mapController.camera.screenOffsetToLatLng(screen);
    } catch (_) {
      return null;
    }
  }

  /// Screen-space hit test so tee selection works at any zoom level.
  dynamic _teeIdNearTap(LatLng tap) {
    const hitPixels = 32.0;
    final camera = widget.mapController.camera;
    final tapScreen = camera.latLngToScreenOffset(tap);

    dynamic closestId;
    var closestDist = hitPixels;

    for (final feature
        in widget.features.where((f) => f.featureType == 'tee')) {
      if (!feature.isActive(widget.selectedCourse, widget.selectedHole)) {
        continue;
      }
      final point = latLngFromGeometry(feature.geometry);
      if (point == null) continue;

      final teeScreen = camera.latLngToScreenOffset(point);
      final dist = (tapScreen - teeScreen).distance;
      if (dist < closestDist) {
        closestDist = dist;
        closestId = feature.id;
      }
    }

    return closestId;
  }

  List<Widget> _buildPinnedShotLayers() {
    final lines = <Polyline>[];
    final markers = <Marker>[];
    final sorted = [...widget.pinnedShots]
      ..sort((a, b) => a.shotNumber.compareTo(b.shotNumber));

    for (var i = 0; i < sorted.length; i++) {
      final shot = sorted[i];
      final to = LatLng(shot.latitude, shot.longitude);
      final from = i == 0
          ? LatLng(shot.fromLatitude, shot.fromLongitude)
          : LatLng(sorted[i - 1].latitude, sorted[i - 1].longitude);

      final yards = shot.shotYards ??
          metersToYards(distanceMeters(from, to));
      final mid = LatLng(
        (from.latitude + to.latitude) / 2,
        (from.longitude + to.longitude) / 2,
      );

      lines.add(
        Polyline(
          points: [from, to],
          color: Colors.white.withValues(alpha: 0.45),
          strokeWidth: 4.5,
        ),
      );
      lines.add(
        Polyline(
          points: [from, to],
          color: const Color(0xFFFF9800),
          strokeWidth: 3,
        ),
      );

      markers.add(
        Marker(
          point: mid,
          width: 72,
          height: 22,
          alignment: Alignment.center,
          child: _ShotDistanceLabel(yards: yards),
        ),
      );

      markers.add(
        Marker(
          point: to,
          width: 26,
          height: 26,
          alignment: Alignment.center,
          child: _PinnedShotMarker(shotNumber: shot.shotNumber),
        ),
      );
    }

    return [
      PolylineLayer(polylines: lines),
      _uprightMarkerLayer(markers),
    ];
  }

  List<Widget> _buildMeasurementLayers() {
    final lines = <Polyline>[];
    final markers = <Marker>[];
    final chain = _measurementChainPoints();

    if (chain.length >= 2) {
      var shotNumber = 1;
      for (var i = 0; i < chain.length - 1; i++) {
        final from = chain[i];
        final to = chain[i + 1];
        _addSegmentLine(lines, from, to, dashed: false);
        final yards = metersToYards(distanceMeters(from, to));
        markers.add(_segmentLabelMarker(from, to, yards, shotNumber++));
      }
    }

    final terminal = _chainTerminal;
    if (terminal != null && widget.greenCenter != null) {
      _addSegmentLine(lines, terminal, widget.greenCenter!, dashed: false);

      final toPinYards =
          metersToYards(distanceMeters(terminal, widget.greenCenter!));
      markers.add(
        Marker(
          point: LatLng(
            (terminal.latitude + widget.greenCenter!.latitude) / 2,
            (terminal.longitude + widget.greenCenter!.longitude) / 2,
          ),
          width: 80,
          height: 22,
          alignment: Alignment.center,
          child: _ShotDistanceLabel(
            yards: toPinYards,
            shotNumber: null,
            borderColor: AppTheme.accentGreen,
            textColor: const Color(0xFF81C784),
            suffix: 'pin',
          ),
        ),
      );
    }

    if (lines.isEmpty) return [];
    return [
      PolylineLayer(polylines: lines),
      if (markers.isNotEmpty) _uprightMarkerLayer(markers),
    ];
  }

  List<Polyline> _buildHoleBoundaryPolylines() {
    final lines = <Polyline>[];

    void addRing(
      List<LatLng> ring, {
      required bool active,
      required bool encircle,
    }) {
      if (ring.length < 3) return;

      final closed = List<LatLng>.from(ring);
      if (closed.first != closed.last) closed.add(closed.first);

      final opacity = active ? 1.0 : 0.2;
      final lineWidth = encircle ? (active ? 3.0 : 2.0) : (active ? 3.0 : 1.5);
      final strokeColor = encircle
          ? (active ? AppTheme.measureBlueBright : AppTheme.accentGreen)
          : AppTheme.accentGreen;
      final dashPattern = StrokePattern.dashed(segments: [14, 10]);

      if (encircle && active) {
        lines.add(
          Polyline(
            points: closed,
            color: Colors.white.withValues(alpha: 0.5 * opacity),
            strokeWidth: lineWidth + 2,
            pattern: dashPattern,
          ),
        );
        lines.add(
          Polyline(
            points: closed,
            color: strokeColor.withValues(alpha: 0.95 * opacity),
            strokeWidth: lineWidth,
            pattern: dashPattern,
          ),
        );
        return;
      }

      lines.add(
        Polyline(
          points: closed,
          color: Colors.white.withValues(alpha: 0.55 * opacity),
          strokeWidth: lineWidth + 2.5,
        ),
      );
      lines.add(
        Polyline(
          points: closed,
          color: strokeColor.withValues(alpha: 0.95 * opacity),
          strokeWidth: lineWidth,
        ),
      );
    }

    void addRings(
      List<List<LatLng>> rings, {
      required bool active,
      required bool encircle,
    }) {
      for (final ring in rings) {
        addRing(ring, active: active, encircle: encircle);
      }
    }

    addRing(
      holeEncirclementRing(
        widget.features,
        widget.selectedCourse,
        widget.selectedHole,
      ),
      active: true,
      encircle: true,
    );

    for (final hole in widget.features
        .map((f) => f.holeNumber)
        .whereType<String>()
        .toSet()) {
      if (hole == widget.selectedHole) continue;
      addRings(
        holeBoundaryRings(
          widget.features,
          widget.selectedCourse,
          hole,
          activeOnly: true,
        ),
        active: false,
        encircle: false,
      );
    }

    return lines;
  }

  List<Polygon> _buildTeePolygons() {
    final polygons = <Polygon>[];

    for (final feature in widget.features.where((f) => f.featureType == 'tee')) {
      final isActive =
          feature.isActive(widget.selectedCourse, widget.selectedHole);
      final opacity = isActive ? 0.55 : 0.12;

      for (final ring in ringsFromGeometry(feature.geometry)) {
        if (ring.length < 3) continue;
        polygons.add(
          Polygon(
            points: ring,
            color: AppTheme.teeFill.withValues(alpha: opacity),
            borderColor: isActive
                ? AppTheme.teeBorder.withValues(alpha: 0.85)
                : Colors.transparent,
            borderStrokeWidth: isActive ? 1.5 : 0,
          ),
        );
      }
    }

    return polygons;
  }

  List<Polygon> _buildPolygons(
    String featureType,
    int color,
    double activeOpacity,
    double inactiveOpacity,
  ) {
    final polygons = <Polygon>[];

    for (final feature in widget.features.where((f) => f.featureType == featureType)) {
      final isActive = feature.isActive(widget.selectedCourse, widget.selectedHole);
      final opacity = isActive ? activeOpacity : inactiveOpacity;
      final fillColor = Color(color).withValues(alpha: opacity);
      final borderColor = isActive
          ? (featureType == 'tee'
              ? AppTheme.teeBorder
              : Color(color).withValues(alpha: 0.9))
          : Colors.transparent;

      for (final ring in ringsFromGeometry(feature.geometry)) {
        if (ring.length < 3) continue;
        polygons.add(
          Polygon(
            points: ring,
            color: fillColor,
            borderColor: isActive
                ? borderColor.withValues(alpha: 0.85)
                : Colors.transparent,
            borderStrokeWidth: isActive ? 1.5 : 0,
          ),
        );
      }
    }

    return polygons;
  }

  List<Widget> _buildShotDirectionLayers() {
    final holeFeatures = widget.features
        .where((f) => f.isActive(widget.selectedCourse, widget.selectedHole))
        .toList();
    final green = greenCenterForHole(holeFeatures);
    if (green == null) return [];

    final start = shotDistanceOrigin(
      widget.userCoord,
      holeFeatures,
      selectedTeeFeatureId: widget.selectedTeeFeatureId,
    );
    if (start == null) return [];

    final segments = plannedShotSegments(
      start: start,
      green: green,
      holeFeatures: holeFeatures,
    );
    if (segments.isEmpty) return [];

    final lines = <Polyline>[];
    final markers = <Marker>[];

    for (final segment in segments) {
      lines.add(
        Polyline(
          points: [segment.from, segment.to],
          color: Colors.white.withValues(alpha: 0.5),
          strokeWidth: 5,
        ),
      );
      lines.add(
        Polyline(
          points: [segment.from, segment.to],
          color: Colors.red,
          strokeWidth: 3,
        ),
      );

      final mid = LatLng(
        (segment.from.latitude + segment.to.latitude) / 2,
        (segment.from.longitude + segment.to.longitude) / 2,
      );

      markers.add(
        Marker(
          point: mid,
          width: 88,
          height: 22,
          alignment: Alignment.center,
          child: _ShotDistanceLabel(
            yards: segment.yards,
            shotNumber: segment.shotNumber,
            borderColor: const Color(0xFFE53935),
            textColor: const Color(0xFFFF8A80),
          ),
        ),
      );

      markers.add(
        Marker(
          point: segment.to,
          width: 14,
          height: 14,
          alignment: Alignment.center,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.red,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
            ),
          ),
        ),
      );
    }

    return [
      PolylineLayer(polylines: lines),
      _uprightMarkerLayer(markers),
    ];
  }

  List<Marker> _buildGreenPinMarkers() {
    final holeFeatures = widget.features
        .where((f) => f.isActive(widget.selectedCourse, widget.selectedHole))
        .toList();
    final center = greenCenterForHole(holeFeatures);
    if (center == null) return [];

    return [
      Marker(
        point: center,
        width: 32,
        height: 48,
        // flutter_map: topCenter anchors the widget's bottom edge to [point].
        alignment: Alignment.topCenter,
        child: const GreenFlagPin(),
      ),
    ];
  }

  List<Marker> _buildTeeMarkers() {
    final markers = <Marker>[];
    final holeFeatures = widget.features
        .where((f) => f.isActive(widget.selectedCourse, widget.selectedHole))
        .toList();
    final teeLabels = {
      for (final t in teeOptionsForHole(holeFeatures)) t.featureId: t.label,
    };

    for (final feature in widget.features.where((f) => f.featureType == 'tee')) {
      if (!feature.isActive(widget.selectedCourse, widget.selectedHole)) continue;
      final point = latLngFromGeometry(feature.geometry);
      if (point == null) continue;

      final isSelected =
          !widget.usingGpsForShot && feature.id == widget.selectedTeeFeatureId;
      final label = teeLabels[feature.id] ?? 'T';

      markers.add(
        Marker(
          point: point,
          width: isSelected ? 40 : 28,
          height: isSelected ? 52 : 28,
          alignment: Alignment.topCenter,
          child: GestureDetector(
            onTap: widget.usingGpsForShot
                ? null
                : () => widget.onSelectTee(feature.id),
            child: _TeePinMarker(label: label, isSelected: isSelected),
          ),
        ),
      );
    }

    return markers;
  }

  Marker _userMarker(LatLng point) {
    return Marker(
      point: point,
      width: 20,
      height: 20,
      alignment: Alignment.center,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF34A853),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2.5),
          boxShadow: const [
            BoxShadow(
              color: Color(0x66000000),
              blurRadius: 5,
              offset: Offset(0, 1),
            ),
          ],
        ),
      ),
    );
  }
}

class _TeePinMarker extends StatelessWidget {
  const _TeePinMarker({required this.label, required this.isSelected});

  final String label;
  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    final short = label.isNotEmpty ? label[0].toUpperCase() : 'T';

    if (isSelected) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const GolfBallMarker(size: 16),
          const SizedBox(height: 2),
          _TeeDisc(short: short, isSelected: true),
        ],
      );
    }

    return _TeeDisc(short: short, isSelected: false);
  }
}

class _TeeDisc extends StatelessWidget {
  const _TeeDisc({required this.short, required this.isSelected});

  final String short;
  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      width: isSelected ? 26 : 24,
      height: isSelected ? 26 : 24,
      decoration: BoxDecoration(
        color: const Color(0xFFF8F6F0),
        shape: BoxShape.circle,
        border: Border.all(
          color: isSelected ? AppTheme.accentGreen : const Color(0xFF3D3D3D),
          width: isSelected ? 2.5 : 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isSelected ? 0.4 : 0.28),
            blurRadius: isSelected ? 5 : 3,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Center(
        child: Text(
          short,
          style: TextStyle(
            color: const Color(0xFF1F2937),
            fontSize: isSelected ? 11 : 10,
            fontWeight: FontWeight.w800,
            height: 1,
          ),
        ),
      ),
    );
  }
}

class _PinnedShotMarker extends StatelessWidget {
  const _PinnedShotMarker({required this.shotNumber});

  final int shotNumber;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        color: const Color(0xFFFF9800),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: const [
          BoxShadow(
            color: Color(0x66000000),
            blurRadius: 4,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: Center(
        child: Text(
          '$shotNumber',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 10,
            fontWeight: FontWeight.w900,
            height: 1,
          ),
        ),
      ),
    );
  }
}

class _LockedMeasurementMarker extends StatelessWidget {
  const _LockedMeasurementMarker({
    required this.shotNumber,
    this.isDragging = false,
    this.isSelected = false,
  });

  final int shotNumber;
  final bool isDragging;
  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    final highlighted = isDragging || isSelected;
    return Container(
      width: isDragging ? 26 : (isSelected ? 24 : 22),
      height: isDragging ? 26 : (isSelected ? 24 : 22),
      decoration: BoxDecoration(
        color: AppTheme.measureBlue,
        shape: BoxShape.circle,
        border: Border.all(
          color: isSelected ? const Color(0xFFFFD54F) : Colors.white,
          width: highlighted ? 2.5 : 2,
        ),
        boxShadow: [
          BoxShadow(
            color: isSelected
                ? const Color(0x99FFD54F)
                : isDragging
                    ? AppTheme.measureBlue.withValues(alpha: 0.55)
                    : const Color(0x66000000),
            blurRadius: isDragging || isSelected ? 8 : 4,
            spreadRadius: isSelected ? 2 : (isDragging ? 1 : 0),
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Center(
        child: Text(
          '$shotNumber',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 10,
            fontWeight: FontWeight.w900,
            height: 1,
          ),
        ),
      ),
    );
  }
}

class _ShotDistanceLabel extends StatelessWidget {
  const _ShotDistanceLabel({
    required this.yards,
    this.shotNumber,
    this.borderColor = const Color(0xFFFF9800),
    this.textColor = const Color(0xFFFFB74D),
    this.suffix,
  });

  final int yards;
  final int? shotNumber;
  final Color borderColor;
  final Color textColor;
  final String? suffix;

  @override
  Widget build(BuildContext context) {
    final yardsText = '$yards yds';
    final label = shotNumber != null
        ? '#$shotNumber · $yardsText'
        : suffix != null
            ? '$yardsText · $suffix'
            : yardsText;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xE0101018),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: borderColor, width: 1),
        boxShadow: const [
          BoxShadow(
            color: Color(0x66000000),
            blurRadius: 4,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: Text(
        label,
        maxLines: 1,
        softWrap: false,
        style: TextStyle(
          color: textColor,
          fontSize: 9,
          fontWeight: FontWeight.w800,
          height: 1,
        ),
      ),
    );
  }
}
