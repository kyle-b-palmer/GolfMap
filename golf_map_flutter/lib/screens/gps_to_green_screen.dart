import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../config/app_config.dart';
import '../config/app_theme.dart';
import '../models/golf_feature.dart';
import '../utils/geo_utils.dart';
import '../widgets/map_marker_graphics.dart';

class GpsToGreenScreen extends StatefulWidget {
  const GpsToGreenScreen({
    super.key,
    required this.features,
    required this.course,
    required this.hole,
    this.initialUserCoord,
  });

  final List<GolfFeature> features;
  final String course;
  final String hole;
  final LatLng? initialUserCoord;

  @override
  State<GpsToGreenScreen> createState() => _GpsToGreenScreenState();
}

class _GpsToGreenScreenState extends State<GpsToGreenScreen> {
  static const _courseMapBackground = Color(0xFF1A3328);
  static const _pinHitSize = 44.0;

  final _mapController = MapController();

  LatLng? _userCoord;
  late LatLng _pinPosition;
  bool _mapReady = false;
  bool _draggingPin = false;
  LatLng? _dragPinCoord;
  Offset? _dragAnchorScreen;
  StreamSubscription<Position>? _positionSub;

  List<GolfFeature> get _holeFeatures => widget.features
      .where(
        (f) => f.matchesCourse(widget.course) && f.matchesHole(widget.hole),
      )
      .toList();

  List<GolfFeature> get _greenFeatures =>
      _holeFeatures.where((f) => f.featureType == 'green').toList();

  LatLng get _effectivePin => _draggingPin && _dragPinCoord != null
      ? _dragPinCoord!
      : _pinPosition;

  int? get _distanceYards {
    final gps = _userCoord;
    if (gps == null) return null;
    return metersToYards(distanceMeters(gps, _effectivePin));
  }

  @override
  void initState() {
    super.initState();
    _userCoord = widget.initialUserCoord;
    _pinPosition =
        greenCenterForHole(_holeFeatures) ??
        centerForFeatures(_greenFeatures) ??
        LatLng(AppConfig.defaultCenter[0], AppConfig.defaultCenter[1]);
    _initLocation();
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    super.dispose();
  }

  Future<void> _initLocation() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return;
    }

    _positionSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
      ),
    ).listen((position) {
      if (!mounted) return;
      setState(() {
        _userCoord = LatLng(position.latitude, position.longitude);
      });
    });
  }

  void _focusOnGreen() {
    if (!_mapReady || _greenFeatures.isEmpty) return;

    final orientation = holeOrientationForFeatures(_holeFeatures);
    final greenCenter = greenCenterForHole(_holeFeatures);
    final rotation = orientation != null
        ? mapRotationForHole(orientation.tee, orientation.green)
        : 0.0;

    final bounds = boundsForFeatures(_greenFeatures);
    final center = centerForFeatures(_greenFeatures) ?? greenCenter;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      if (bounds != null) {
        final fitted = CameraFit.bounds(
          bounds: bounds,
          padding: const EdgeInsets.all(56),
          maxZoom: 20,
        ).fit(_mapController.camera.withRotation(rotation));

        _mapController.moveAndRotate(
          fitted.center,
          fitted.zoom,
          rotation,
        );
      } else if (center != null) {
        _mapController.moveAndRotate(center, 19, rotation);
      }
    });
  }

  void _beginPinDrag() {
    final screen = _mapController.camera.latLngToScreenOffset(_pinPosition);
    setState(() {
      _draggingPin = true;
      _dragPinCoord = _pinPosition;
      _dragAnchorScreen = screen;
    });
  }

  void _updatePinDrag(DragUpdateDetails details) {
    if (!_draggingPin) return;
    final anchor = _dragAnchorScreen;
    if (anchor == null) return;

    final nextScreen = anchor + details.delta;
    final updated = _screenOffsetToLatLng(nextScreen);
    if (updated == null) return;

    setState(() {
      _dragAnchorScreen = nextScreen;
      _dragPinCoord = updated;
    });
  }

  void _endPinDrag() {
    if (!_draggingPin) return;

    var finalCoord = _dragPinCoord ?? _pinPosition;
    if (!isPointInGreen(finalCoord, _holeFeatures)) {
      finalCoord = _pinPosition;
    }

    setState(() {
      _draggingPin = false;
      _dragPinCoord = null;
      _dragAnchorScreen = null;
      _pinPosition = finalCoord;
    });
  }

  LatLng? _screenOffsetToLatLng(Offset screen) {
    try {
      return _mapController.camera.screenOffsetToLatLng(screen);
    } catch (_) {
      return null;
    }
  }

  List<Polygon> _buildGreenPolygons() {
    final polygons = <Polygon>[];
    for (final feature in _greenFeatures) {
      for (final ring in ringsFromGeometry(feature.geometry)) {
        if (ring.length < 3) continue;
        polygons.add(
          Polygon(
            points: ring,
            color: const Color(0xFF00FF55).withValues(alpha: 0.65),
            borderColor: AppTheme.accentGreen.withValues(alpha: 0.95),
            borderStrokeWidth: 2,
          ),
        );
      }
    }
    return polygons;
  }

  List<Polyline> _buildGpsLine() {
    final gps = _userCoord;
    if (gps == null) return [];

    return [
      Polyline(
        points: [gps, _effectivePin],
        color: Colors.white.withValues(alpha: 0.5),
        strokeWidth: 5,
      ),
      Polyline(
        points: [gps, _effectivePin],
        color: AppTheme.measureBlueBright,
        strokeWidth: 3,
        pattern: StrokePattern.dashed(segments: [12, 8]),
      ),
    ];
  }

  Marker _buildDraggablePinMarker() {
    return Marker(
      point: _effectivePin,
      width: _pinHitSize,
      height: 56,
      alignment: Alignment.topCenter,
      child: RawGestureDetector(
        behavior: HitTestBehavior.opaque,
        gestures: <Type, GestureRecognizerFactory>{
          _EagerPanGestureRecognizer:
              GestureRecognizerFactoryWithHandlers<_EagerPanGestureRecognizer>(
            _EagerPanGestureRecognizer.new,
            (recognizer) {
              recognizer.onStart = (_) => _beginPinDrag();
              recognizer.onUpdate = _updatePinDrag;
              recognizer.onEnd = (_) => _endPinDrag();
              recognizer.onCancel = _endPinDrag;
            },
          ),
        },
        child: const GreenFlagPin(),
      ),
    );
  }

  Marker? _buildUserMarker() {
    final gps = _userCoord;
    if (gps == null) return null;

    return Marker(
      point: gps,
      width: 24,
      height: 24,
      alignment: Alignment.center,
      child: const GolfBallMarker(size: 16),
    );
  }

  Marker? _buildDistanceLabel() {
    final yards = _distanceYards;
    final gps = _userCoord;
    if (yards == null || gps == null) return null;

    final mid = LatLng(
      (gps.latitude + _effectivePin.latitude) / 2,
      (gps.longitude + _effectivePin.longitude) / 2,
    );

    return Marker(
      point: mid,
      width: 72,
      height: 24,
      alignment: Alignment.center,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xF0121810),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: AppTheme.measureBlue, width: 1),
        ),
        child: Text(
          '$yards yds',
          style: const TextStyle(
            color: Color(0xFF90CAF9),
            fontSize: 10,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final markers = <Marker>[
      _buildDraggablePinMarker(),
      ? _buildUserMarker(),
      ? _buildDistanceLabel(),
    ];

    return Scaffold(
      backgroundColor: Colors.black,
      body: kIsWeb
          ? _buildBody(markers)
          : SafeArea(child: _buildBody(markers)),
    );
  }

  Widget _buildBody(List<Marker> markers) {
    final distanceYards = _distanceYards;

    return Stack(
      children: [
        Positioned.fill(
          child: FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              backgroundColor: _courseMapBackground,
              initialCenter: _pinPosition,
              initialZoom: 19,
              onMapReady: () {
                setState(() => _mapReady = true);
                _focusOnGreen();
              },
              interactionOptions: InteractionOptions(
                flags: _draggingPin
                    ? InteractiveFlag.pinchZoom |
                        InteractiveFlag.rotate |
                        InteractiveFlag.doubleTapZoom
                    : InteractiveFlag.all,
              ),
            ),
            children: [
              PolygonLayer(polygons: _buildGreenPolygons()),
              if (_userCoord != null)
                PolylineLayer(polylines: _buildGpsLine()),
              MarkerLayer(rotate: true, markers: markers),
            ],
          ),
        ),
        Positioned(
          top: 8,
          left: 12,
          right: 12,
          child: Row(
            children: [
              _HeaderButton(
                icon: Icons.arrow_back_rounded,
                label: 'Back',
                onTap: () => Navigator.pop(context),
              ),
              Expanded(
                child: Text(
                  'HOLE ${widget.hole} · GPS TO GREEN',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppTheme.accentGreen,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              const SizedBox(width: 72),
            ],
          ),
        ),
        Positioned(
          left: 16,
          right: 16,
          bottom: MediaQuery.paddingOf(context).bottom + 16,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                decoration: BoxDecoration(
                  color: AppTheme.panelBg,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppTheme.panelBorder),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x44000000),
                      blurRadius: 12,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Text(
                      distanceYards != null ? '$distanceYards' : '—',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 42,
                        fontWeight: FontWeight.w800,
                        height: 1,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      distanceYards != null
                          ? 'YARDS FROM GPS TO PIN'
                          : 'WAITING FOR GPS…',
                      style: TextStyle(
                        color: AppTheme.textMuted.withValues(alpha: 0.95),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Drag the pin to your target on the green',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppTheme.textMuted.withValues(alpha: 0.9),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _HeaderButton extends StatelessWidget {
  const _HeaderButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.panelBg,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.panelBorder),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: AppTheme.textMuted),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EagerPanGestureRecognizer extends PanGestureRecognizer {
  @override
  void handleEvent(PointerEvent event) {
    if (event is PointerDownEvent || event is PointerMoveEvent) {
      resolve(GestureDisposition.accepted);
    }
    super.handleEvent(event);
  }
}
