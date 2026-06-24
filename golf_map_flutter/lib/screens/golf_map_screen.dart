import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../config/app_theme.dart';
import '../models/golf_feature.dart';
import '../models/measurement_chain.dart';
import '../models/pinned_shot.dart';
import '../models/saved_round.dart';
import '../services/golf_data_service.dart';
import '../services/round_storage_service.dart';
import '../utils/geo_utils.dart';
import '../widgets/course_selector.dart';
import '../widgets/distance_card.dart';
import '../widgets/golf_map_view.dart';
import '../widgets/hole_selector.dart';
import '../widgets/hole_stats_panel.dart';
import '../widgets/score_panel.dart';
import '../widgets/shot_direction_toggle.dart';

class GolfMapScreen extends StatefulWidget {
  const GolfMapScreen({
    super.key,
    required this.initialCourse,
    this.initialScores,
    this.initialPinnedShots,
    this.existingRoundId,
    this.existingRoundPlayedAt,
  });

  final String initialCourse;
  final Map<String, int>? initialScores;
  final Map<String, List<PinnedShot>>? initialPinnedShots;
  final String? existingRoundId;
  final DateTime? existingRoundPlayedAt;

  @override
  State<GolfMapScreen> createState() => _GolfMapScreenState();
}

class _GolfMapScreenState extends State<GolfMapScreen> {
  final _dataService = GolfDataService();
  final _roundStorage = RoundStorageService();
  final _mapController = MapController();

  List<GolfFeature> _features = [];
  List<String> _courses = [];
  List<String> _holes = [];
  String? _selectedCourse;
  String _selectedHole = '1';
  HoleStats? _currentHoleStats;
  final Map<String, int> _scores = {};
  final Map<String, List<PinnedShot>> _pinnedShots = {};

  bool _loading = true;
  bool _mapReady = false;
  bool _showCourseDropdown = false;
  bool _showShotDirection = false;
  bool _savingRound = false;

  LatLng? _userCoord;
  LatLng? _greenCenter;
  LatLng? _shotOrigin;
  final List<MeasurementChainPoint> _lockedMeasurementPoints = [];
  int? _selectedMeasurementPinIndex;
  DistanceInfo? _distanceInfo;
  dynamic _selectedTeeFeatureId;
  String? _preferredTeeLabel;
  StreamSubscription<Position>? _positionSub;

  List<GolfFeature> get _currentHoleFeatures {
    final course = _selectedCourse;
    if (course == null) return [];
    return _features
        .where(
          (f) => f.matchesCourse(course) && f.matchesHole(_selectedHole),
        )
        .toList();
  }

  List<TeeOption> get _teeOptions => teeOptionsForHole(_currentHoleFeatures);

  bool get _usingGpsForShot =>
      isUsingGpsForShot(_userCoord, _currentHoleFeatures);

  int? get _holeYardage {
    final teeId = _selectedTeeFeatureId;
    if (teeId == null) return null;
    return holeYardageFromSelectedTee(_currentHoleFeatures, teeId);
  }

  List<PinnedShot> get _currentHolePinnedShots =>
      _pinnedShots[_selectedHole] ?? const [];

  @override
  void initState() {
    super.initState();
    if (widget.initialPinnedShots != null) {
      for (final entry in widget.initialPinnedShots!.entries) {
        final shots = entry.value;
        if (shots.isNotEmpty) {
          _pinnedShots[entry.key] = List<PinnedShot>.from(shots);
        }
      }
    }
    _loadData();
    _initLocation();
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    super.dispose();
  }

  Future<void> _loadData() async {
    try {
      final features = await _dataService.fetchGolfFeatures();
      final courses = _dataService.extractCourses(features);

      if (!mounted) return;

      setState(() {
        _features = features;
        _courses = courses;
        _selectedCourse = widget.initialCourse;
        _loading = false;
      });

      _refreshHoleState();
    } catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading course layout: $error')),
      );
    }
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
      if (_lockedMeasurementPoints.isNotEmpty) {
        _recalculateMeasurementChain();
        _refreshMeasurementDisplay();
      }
    });
  }

  void _refreshHoleState() {
    final course = _selectedCourse;
    if (course == null) return;

    final holes = _dataService.holesForCourse(_features, course);
    var selectedHole = _selectedHole;
    if (holes.isNotEmpty && !holes.contains(selectedHole)) {
      selectedHole = holes.first;
    }

    final stats = _dataService.statsForHole(_features, course, selectedHole);

    for (final hole in holes) {
      final key = _scoreKey(course, hole);
      if (!_scores.containsKey(key)) {
        _scores[key] = widget.initialScores?[hole] ?? 0;
      }
    }

    setState(() {
      _holes = holes;
      _selectedHole = selectedHole;
      _currentHoleStats = stats;
      _applyTeeSelectionForHole();
    });

    if (_lockedMeasurementPoints.isNotEmpty) {
      _recalculateMeasurementChain();
      _refreshMeasurementDisplay();
    }

    _focusOnHole();
  }

  void _applyTeeSelectionForHole() {
    final options = teeOptionsForHole(_currentHoleFeatures);
    if (options.isEmpty) {
      _selectedTeeFeatureId = null;
      return;
    }

    TeeOption selected;
    if (_preferredTeeLabel != null) {
      selected = teeOptionByLabel(_currentHoleFeatures, _preferredTeeLabel!) ??
          options.first;
    } else {
      selected = options.first;
      _preferredTeeLabel = selected.label;
    }

    _selectedTeeFeatureId = selected.featureId;
  }

  void _focusOnHole() {
    if (!_mapReady || _selectedCourse == null) return;

    final holeFeatures = _features
        .where(
          (f) =>
              f.matchesCourse(_selectedCourse) &&
              f.matchesHole(_selectedHole),
        )
        .toList();

    if (holeFeatures.isEmpty) return;

    final orientation = holeOrientationForFeatures(holeFeatures);
    final green = greenCenterForHole(holeFeatures);
    final teeForRotation = teePointById(holeFeatures, _selectedTeeFeatureId) ??
        orientation?.tee;
    final rotation = teeForRotation != null && green != null
        ? mapRotationForHole(teeForRotation, green)
        : orientation != null
            ? mapRotationForHole(orientation.tee, orientation.green)
            : 0.0;

    final bounds = boundsForFeatures(holeFeatures);
    final center = centerForFeatures(holeFeatures);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      if (bounds != null) {
        final fitted = CameraFit.bounds(
          bounds: bounds,
          padding: const EdgeInsets.all(80),
          maxZoom: 18,
        ).fit(_mapController.camera.withRotation(rotation));

        _mapController.moveAndRotate(
          fitted.center,
          fitted.zoom,
          rotation,
        );
      } else if (center != null) {
        _mapController.moveAndRotate(center, 17, rotation);
      }
    });
  }

  String _scoreKey(String course, String hole) => '${course}_$hole';

  void _clearDistance() {
    setState(() {
      _distanceInfo = null;
      _greenCenter = null;
      _shotOrigin = null;
      _lockedMeasurementPoints.clear();
      _selectedMeasurementPinIndex = null;
    });
  }

  void _recalculateMeasurementChain() {
    if (_lockedMeasurementPoints.isEmpty) return;

    final origin = shotDistanceOrigin(
      _userCoord,
      _currentHoleFeatures,
      selectedTeeFeatureId: _selectedTeeFeatureId,
    );
    if (origin == null) return;

    final updated = <MeasurementChainPoint>[];
    var previous = origin;
    for (var i = 0; i < _lockedMeasurementPoints.length; i++) {
      final point = _lockedMeasurementPoints[i].point;
      updated.add(
        MeasurementChainPoint(
          point: point,
          segmentYards: metersToYards(distanceMeters(previous, point)),
          shotNumber: i + 1,
        ),
      );
      previous = point;
    }

    setState(() {
      _lockedMeasurementPoints
        ..clear()
        ..addAll(updated);
    });
  }

  void _addMeasurementChainPoint(LatLng point) {
    final holeFeatures = _currentHoleFeatures;
    final origin = shotDistanceOrigin(
      _userCoord,
      holeFeatures,
      selectedTeeFeatureId: _selectedTeeFeatureId,
    );
    final from = _lockedMeasurementPoints.isNotEmpty
        ? _lockedMeasurementPoints.last.point
        : origin;

    if (from == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select a tee box for the first shot')),
      );
      return;
    }

    final yards = metersToYards(distanceMeters(from, point));
    final shotNumber = _lockedMeasurementPoints.length + 1;

    setState(() {
      _lockedMeasurementPoints.add(
        MeasurementChainPoint(
          point: point,
          segmentYards: yards,
          shotNumber: shotNumber,
        ),
      );
      _greenCenter = greenCenterForHole(holeFeatures);
      _shotOrigin = origin;
      _selectedMeasurementPinIndex = null;
    });
    _refreshMeasurementDisplay();
  }

  void _selectMeasurementPin(int index) {
    if (index < 0 || index >= _lockedMeasurementPoints.length) return;
    setState(() {
      _selectedMeasurementPinIndex =
          _selectedMeasurementPinIndex == index ? null : index;
    });
  }

  void _deleteSelectedMeasurementPin() {
    final index = _selectedMeasurementPinIndex;
    if (index == null || index < 0 || index >= _lockedMeasurementPoints.length) {
      return;
    }

    setState(() {
      _lockedMeasurementPoints.removeAt(index);
      _selectedMeasurementPinIndex = null;
    });

    if (_lockedMeasurementPoints.isEmpty) {
      setState(() {
        _distanceInfo = null;
        _greenCenter = null;
        _shotOrigin = null;
      });
      return;
    }

    _recalculateMeasurementChain();
    _refreshMeasurementDisplay();
  }

  void _moveLockedMeasurementPoint(int index, LatLng newPoint) {
    if (index < 0 || index >= _lockedMeasurementPoints.length) return;

    final holeFeatures = _currentHoleFeatures;
    final origin = shotDistanceOrigin(
      _userCoord,
      holeFeatures,
      selectedTeeFeatureId: _selectedTeeFeatureId,
    );

    final updated = List<MeasurementChainPoint>.from(_lockedMeasurementPoints);
    final previous = index == 0 ? origin : updated[index - 1].point;
    if (previous == null) return;

    updated[index] = MeasurementChainPoint(
      point: newPoint,
      segmentYards: metersToYards(distanceMeters(previous, newPoint)),
      shotNumber: updated[index].shotNumber,
    );

    if (index + 1 < updated.length) {
      final next = updated[index + 1];
      updated[index + 1] = MeasurementChainPoint(
        point: next.point,
        segmentYards: metersToYards(distanceMeters(newPoint, next.point)),
        shotNumber: next.shotNumber,
      );
    }

    setState(() {
      _lockedMeasurementPoints
        ..clear()
        ..addAll(updated);
    });
    _refreshMeasurementDisplay();
  }

  void _handleLockedMeasurementDrag(int index, LatLng point) {
    _moveLockedMeasurementPoint(index, point);
  }

  void _handleLockedMeasurementDragEnd(int index, LatLng point) {
    _moveLockedMeasurementPoint(index, point);
  }

  void _refreshMeasurementDisplay() {
    final holeFeatures = _currentHoleFeatures;
    final greenPoint = greenCenterForHole(holeFeatures);
    if (greenPoint == null) {
      setState(() => _distanceInfo = null);
      return;
    }

    final usingGps = isUsingGpsForShot(_userCoord, holeFeatures);
    final origin = shotDistanceOrigin(
      _userCoord,
      holeFeatures,
      selectedTeeFeatureId: _selectedTeeFeatureId,
    );
    final bunkerFrom = usingGps ? _userCoord : origin;
    final referencePoint =
        _lockedMeasurementPoints.lastOrNull?.point ?? origin;

    if (referencePoint == null) {
      setState(() {
        _distanceInfo = null;
        _greenCenter = greenPoint;
        _shotOrigin = origin;
      });
      return;
    }

    setState(() {
      _greenCenter = greenPoint;
      _shotOrigin = origin;
      _distanceInfo = DistanceInfo(
        greenYardages: greenDistancesFromPoint(referencePoint, holeFeatures),
        bunkerDistances: bunkerFrom == null
            ? const []
            : bunkerDistancesFromPoint(bunkerFrom, holeFeatures),
        hasBunkerReference: bunkerFrom != null,
        fromUserYards: _lockedMeasurementPoints.isEmpty
            ? null
            : _lockedMeasurementPoints.last.segmentYards,
        lockedSegments: [
          for (final locked in _lockedMeasurementPoints)
            MeasurementSegmentInfo(
              shotNumber: locked.shotNumber,
              yards: locked.segmentYards,
            ),
        ],
        activeSegmentYards: null,
        holeNumber: _selectedHole,
        holeCoord: [greenPoint.longitude, greenPoint.latitude],
        shotOriginCoord: origin == null
            ? [greenPoint.longitude, greenPoint.latitude]
            : [origin.longitude, origin.latitude],
        usingGps: usingGps,
      );
    });
  }

  void _handleMapTap(LatLng tapped) => _addMeasurementChainPoint(tapped);

  void _selectTee(dynamic featureId) {
    TeeOption? match;
    for (final option in teeOptionsForHole(_currentHoleFeatures)) {
      if (option.featureId == featureId) {
        match = option;
        break;
      }
    }

    setState(() {
      _selectedTeeFeatureId = featureId;
      if (match != null) {
        _preferredTeeLabel = match.label;
      }
    });
    _rotateMapToSelectedTee();
    if (_lockedMeasurementPoints.isNotEmpty) {
      _recalculateMeasurementChain();
      _refreshMeasurementDisplay();
    }
  }

  void _rotateMapToSelectedTee() {
    if (!_mapReady) return;

    final holeFeatures = _currentHoleFeatures;
    final green = greenCenterForHole(holeFeatures);
    final tee = teePointById(holeFeatures, _selectedTeeFeatureId);
    if (tee == null || green == null) return;

    final camera = _mapController.camera;
    _mapController.moveAndRotate(
      camera.center,
      camera.zoom,
      mapRotationForHole(tee, green),
    );
  }

  Future<void> _testGps() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    var permission = await Geolocator.checkPermission();

    if (!serviceEnabled) {
      if (!mounted) return;
      await _showGpsTestDialog(
        serviceEnabled: false,
        permission: permission,
      );
      return;
    }

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      if (!mounted) return;
      await _showGpsTestDialog(
        serviceEnabled: serviceEnabled,
        permission: permission,
      );
      return;
    }

    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      final point = LatLng(position.latitude, position.longitude);

      if (!mounted) return;
      setState(() => _userCoord = point);
      _centerMapOnUser(point);

      await _showGpsTestDialog(
        serviceEnabled: serviceEnabled,
        permission: permission,
        position: position,
        point: point,
      );
    } catch (error) {
      if (!mounted) return;
      await _showGpsTestDialog(
        serviceEnabled: serviceEnabled,
        permission: permission,
        errorMessage: error.toString(),
      );
    }
  }

  void _centerMapOnUser(LatLng point) {
    if (!_mapReady) return;

    final camera = _mapController.camera;
    final zoom = camera.zoom < 17 ? 17.0 : camera.zoom;
    _mapController.moveAndRotate(point, zoom, camera.rotation);
  }

  int? _nearestHoleDistanceYards(LatLng user) {
    final holeFeatures = _currentHoleFeatures;
    if (holeFeatures.isEmpty) return null;

    var nearestMeters = double.infinity;
    for (final feature in holeFeatures) {
      for (final featurePoint in allPointsFromGeometry(feature.geometry)) {
        final meters = distanceMeters(user, featurePoint);
        if (meters < nearestMeters) nearestMeters = meters;
      }
    }

    if (nearestMeters == double.infinity) return null;
    return metersToYards(nearestMeters);
  }

  Future<void> _showGpsTestDialog({
    required bool serviceEnabled,
    required LocationPermission permission,
    Position? position,
    LatLng? point,
    String? errorMessage,
  }) async {
    final onCourse = point != null &&
        isUserNearHole(point, _currentHoleFeatures);
    final usingGps = point != null &&
        isUsingGpsForShot(point, _currentHoleFeatures);
    final nearestYards = point != null ? _nearestHoleDistanceYards(point) : null;

    String permissionLabel;
    switch (permission) {
      case LocationPermission.always:
      case LocationPermission.whileInUse:
        permissionLabel = 'Granted';
      case LocationPermission.denied:
        permissionLabel = 'Denied';
      case LocationPermission.deniedForever:
        permissionLabel = 'Denied permanently';
      case LocationPermission.unableToDetermine:
        permissionLabel = 'Unknown';
    }

    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: AppTheme.panelBg,
          title: const Text(
            'GPS test',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          ),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (errorMessage != null) ...[
                  Text(
                    errorMessage,
                    style: const TextStyle(color: Color(0xFFEF4444)),
                  ),
                  const SizedBox(height: 12),
                ],
                _gpsInfoRow('Location services', serviceEnabled ? 'On' : 'Off'),
                _gpsInfoRow('Permission', permissionLabel),
                if (point != null) ...[
                  const SizedBox(height: 8),
                  _gpsInfoRow(
                    'Latitude',
                    point.latitude.toStringAsFixed(6),
                  ),
                  _gpsInfoRow(
                    'Longitude',
                    point.longitude.toStringAsFixed(6),
                  ),
                  if (position != null)
                    _gpsInfoRow(
                      'Accuracy',
                      '±${position.accuracy.toStringAsFixed(1)} m',
                    ),
                  if (position?.altitude != null)
                    _gpsInfoRow(
                      'Altitude',
                      '${position!.altitude.toStringAsFixed(1)} m',
                    ),
                  _gpsInfoRow(
                    'On current hole',
                    onCourse ? 'Yes' : 'No',
                  ),
                  _gpsInfoRow(
                    'Using GPS for yardages',
                    usingGps ? 'Yes' : 'No (using tee)',
                  ),
                  if (nearestYards != null)
                    _gpsInfoRow(
                      'Nearest hole feature',
                      '$nearestYards yds',
                    ),
                ] else if (errorMessage == null) ...[
                  const SizedBox(height: 8),
                  const Text(
                    'Enable location services and grant permission to read GPS.',
                    style: TextStyle(color: AppTheme.textMuted, height: 1.4),
                  ),
                ],
                if (kIsWeb) ...[
                  const SizedBox(height: 12),
                  const Text(
                    'On web, Chrome needs HTTPS and a location prompt.',
                    style: TextStyle(color: AppTheme.textMuted, fontSize: 12),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            if (point != null)
              TextButton(
                onPressed: () {
                  Clipboard.setData(
                    ClipboardData(
                      text:
                          '${point.latitude.toStringAsFixed(6)}, ${point.longitude.toStringAsFixed(6)}',
                    ),
                  );
                  Navigator.pop(context);
                  ScaffoldMessenger.of(this.context).showSnackBar(
                    const SnackBar(content: Text('Coordinates copied')),
                  );
                },
                child: const Text('Copy'),
              ),
            if (point != null)
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  _centerMapOnUser(point);
                },
                child: const Text('Center map'),
              ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  Widget _gpsInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 148,
            child: Text(
              label,
              style: const TextStyle(color: AppTheme.textMuted, fontSize: 13),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pinGpsShot() async {
    var point = _userCoord;

    if (point == null) {
      try {
        final position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
          ),
        );
        point = LatLng(position.latitude, position.longitude);
        if (mounted) setState(() => _userCoord = point);
      } catch (_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'GPS unavailable — enable location to pin your shot',
            ),
          ),
        );
        return;
      }
    }

    _addPinnedShot(point, 'GPS');
  }

  void _pinBlueDotShot() {
    final point = _lockedMeasurementPoints.lastOrNull?.point;
    if (point == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Tap the map to place a shot first'),
        ),
      );
      return;
    }

    _addPinnedShot(point, 'map');
  }

  void _addPinnedShot(LatLng point, String source) {
    final teePoint = teePointById(_currentHoleFeatures, _selectedTeeFeatureId);
    final holePins = List<PinnedShot>.from(_currentHolePinnedShots);
    final shotNumber = holePins.length + 1;

    if (holePins.isEmpty && teePoint == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select a tee box for the first shot')),
      );
      return;
    }

    final LatLng fromPoint;
    if (holePins.isEmpty) {
      fromPoint = teePoint!;
    } else {
      final previous = holePins.last;
      fromPoint = LatLng(previous.latitude, previous.longitude);
    }

    final shotYards = metersToYards(distanceMeters(fromPoint, point));
    final greenPoint = greenCenterForHole(_currentHoleFeatures);
    final yardsToPin = greenPoint != null
        ? greenDistancesFromPoint(point, _currentHoleFeatures).middle
        : null;

    holePins.add(
      PinnedShot(
        shotNumber: shotNumber,
        latitude: point.latitude,
        longitude: point.longitude,
        fromLatitude: fromPoint.latitude,
        fromLongitude: fromPoint.longitude,
        teeLabel: shotNumber == 1 ? _preferredTeeLabel : null,
        shotYards: shotYards,
        yardsToPin: yardsToPin,
      ),
    );

    setState(() {
      _pinnedShots[_selectedHole] = holePins;
    });

    final sourceLabel = source == 'GPS' ? 'GPS' : 'map';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Shot $shotNumber pinned ($sourceLabel) — $shotYards yds'),
      ),
    );
  }

  void _clearPinnedShots() {
    if (_currentHolePinnedShots.isEmpty) return;

    setState(() {
      _pinnedShots.remove(_selectedHole);
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Cleared pins for hole $_selectedHole'),
      ),
    );
  }

  void _updateScore(int delta) {
    final course = _selectedCourse;
    if (course == null) return;

    final key = _scoreKey(course, _selectedHole);
    final current = _scores[key] ?? 0;
    setState(() {
      _scores[key] = (current + delta).clamp(0, 99);
    });
  }

  int get _currentHoleScore {
    final course = _selectedCourse;
    if (course == null) return 0;
    return _scores[_scoreKey(course, _selectedHole)] ?? 0;
  }

  int get _totalScore {
    final course = _selectedCourse;
    if (course == null) return 0;
    return _holes.fold<int>(
      0,
      (sum, hole) => sum + (_scores[_scoreKey(course, hole)] ?? 0),
    );
  }

  Future<void> _saveRound() async {
    if (_savingRound) return;
    final course = _selectedCourse;
    if (course == null) return;

    setState(() => _savingRound = true);
    try {
      final scores = <String, int>{
        for (final hole in _holes)
          hole: _scores[_scoreKey(course, hole)] ?? 0,
      };

      final round = SavedRound(
        id: widget.existingRoundId ??
            DateTime.now().millisecondsSinceEpoch.toString(),
        courseName: course,
        playedAt: widget.existingRoundPlayedAt ?? DateTime.now(),
        scores: scores,
        pinnedShots: {
          for (final entry in _pinnedShots.entries)
            if (entry.value.isNotEmpty)
              entry.key: List<PinnedShot>.from(entry.value),
        },
      );

      await _roundStorage.saveRound(round);
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Round saved')),
      );
      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save round: $error')),
      );
    } finally {
      if (mounted) setState(() => _savingRound = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: Color(0xFF121212),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: AppTheme.accentGreen),
              SizedBox(height: 10),
              Text(
                'Loading Course Layout...',
                style: TextStyle(
                  color: AppTheme.accentGreen,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: kIsWeb
          ? _buildBody()
          : SafeArea(child: _buildBody()),
    );
  }

  Widget _buildBody() {
    return Stack(
      children: [
        Positioned.fill(
          child: GolfMapView(
            mapController: _mapController,
            features: _features,
            selectedCourse: _selectedCourse,
            selectedHole: _selectedHole,
            showShotDirection: _showShotDirection,
            greenCenter: _greenCenter,
            shotOrigin: _shotOrigin,
            userCoord: _userCoord,
            selectedTeeFeatureId: _selectedTeeFeatureId,
            usingGpsForShot: _usingGpsForShot,
            onTap: _handleMapTap,
            onLockedMeasurementDrag: _handleLockedMeasurementDrag,
            onLockedMeasurementDragEnd: _handleLockedMeasurementDragEnd,
            onSelectMeasurementPin: _selectMeasurementPin,
            selectedMeasurementPinIndex: _selectedMeasurementPinIndex,
            onSelectTee: _selectTee,
            onMapReady: () {
              setState(() => _mapReady = true);
              _focusOnHole();
            },
            pinnedShots: _currentHolePinnedShots,
            lockedMeasurementPoints: _lockedMeasurementPoints,
          ),
        ),
        Positioned(
          top: kIsWeb ? 16 : 8,
          left: 15,
          right: 15,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    _MapActionButton(
                      icon: Icons.arrow_back_rounded,
                      label: 'Home',
                      onTap: () => Navigator.pop(context, false),
                    ),
                    const Spacer(),
                    _MapActionButton(
                      icon: Icons.save_rounded,
                      label: _savingRound ? 'Saving...' : 'Save',
                      emphasized: true,
                      onTap: _savingRound ? null : _saveRound,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                CourseSelector(
                  courses: _courses,
                  selectedCourse: _selectedCourse,
                  showDropdown: _showCourseDropdown,
                  onToggleDropdown: () {
                    setState(() {
                      _showCourseDropdown = !_showCourseDropdown;
                    });
                  },
                  onSelectCourse: (course) {
                    setState(() {
                      _selectedCourse = course;
                      _showCourseDropdown = false;
                    });
                    _clearDistance();
                    _refreshHoleState();
                  },
                ),
                if (!_showCourseDropdown) ...[
                  const SizedBox(height: 10),
                  HoleSelector(
                    holes: _holes,
                    selectedHole: _selectedHole,
                    onSelectHole: (hole) {
                      setState(() => _selectedHole = hole);
                      _clearDistance();
                      _refreshHoleState();
                    },
                  ),
                ],
              ],
            ),
          ),
        ),
        if (_currentHoleStats != null && !_showCourseDropdown)
          Positioned(
            top: kIsWeb ? 198 : 183,
            right: 15,
            child: HoleStatsPanel(
              stats: _currentHoleStats!,
              yardage: _holeYardage,
            ),
          ),
        if (!_showCourseDropdown)
          Positioned(
            left: 15,
            bottom: 290,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _PinShotButton(
                  label: 'Test GPS',
                  icon: _userCoord != null
                      ? Icons.my_location_rounded
                      : Icons.location_searching_rounded,
                  accentColor: const Color(0xFF34A853),
                  enabled: true,
                  onPin: _testGps,
                ),
                const SizedBox(height: 8),
                _PinShotButton(
                  label: 'Pin shot ${_currentHolePinnedShots.length + 1} (GPS)',
                  icon: _userCoord != null
                      ? Icons.gps_fixed_rounded
                      : Icons.gps_not_fixed_rounded,
                  accentColor: const Color(0xFFFF9800),
                  enabled: true,
                  onPin: _pinGpsShot,
                ),
                const SizedBox(height: 8),
                _PinShotButton(
                  label:
                      'Pin shot ${_currentHolePinnedShots.length + 1} (map)',
                  icon: Icons.place_rounded,
                  accentColor: AppTheme.measureBlue,
                  enabled: _lockedMeasurementPoints.isNotEmpty,
                  onPin: _pinBlueDotShot,
                ),
                if (_currentHolePinnedShots.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _PinShotButton(
                    label: 'Clear pins (${_currentHolePinnedShots.length})',
                    icon: Icons.clear_rounded,
                    accentColor: const Color(0xFFEF4444),
                    enabled: true,
                    onPin: _clearPinnedShots,
                  ),
                ],
              ],
            ),
          ),
        if (!_showCourseDropdown)
          Positioned(
            left: 15,
            bottom: 130,
            child: ShotDirectionToggle(
              showShotDirection: _showShotDirection,
              onToggle: () {
                setState(() => _showShotDirection = !_showShotDirection);
              },
            ),
          ),
        Positioned(
          left: 15,
          right: 15,
          bottom: 16,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: ScorePanel(
                selectedHole: _selectedHole,
                currentHoleScore: _currentHoleScore,
                totalScore: _totalScore,
                onDecrement: () => _updateScore(-1),
                onIncrement: () => _updateScore(1),
              ),
            ),
          ),
        ),
        if (_distanceInfo != null)
          Positioned(
            top: kIsWeb ? 203 : 188,
            left: 15,
            child: DistanceCard(
              distanceInfo: _distanceInfo!,
              teeOptions: _teeOptions,
              selectedTeeFeatureId: _selectedTeeFeatureId,
              onSelectTee: _selectTee,
              onClear: _clearDistance,
              onPinShot: _pinBlueDotShot,
              selectedMeasurementPinIndex: _selectedMeasurementPinIndex,
              onSelectMeasurementPin: _selectMeasurementPin,
              onDeleteSelectedPin: _deleteSelectedMeasurementPin,
              pinnedShotCount: _currentHolePinnedShots.length,
            ),
          ),
      ],
    );
  }
}

class _PinShotButton extends StatelessWidget {
  const _PinShotButton({
    required this.label,
    required this.icon,
    required this.accentColor,
    required this.enabled,
    required this.onPin,
  });

  final String label;
  final IconData icon;
  final Color accentColor;
  final bool enabled;
  final VoidCallback onPin;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: accentColor.withValues(alpha: 0.2),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: enabled ? onPin : null,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: enabled ? accentColor : AppTheme.panelBorder,
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x33000000),
                blurRadius: 8,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                color: enabled ? accentColor : AppTheme.textMuted,
                size: 17,
              ),
              const SizedBox(width: 7),
              Text(
                label,
                style: TextStyle(
                  color: enabled ? accentColor : AppTheme.textMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MapActionButton extends StatelessWidget {
  const _MapActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.emphasized = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: emphasized
          ? AppTheme.accentGreen.withValues(alpha: 0.15)
          : AppTheme.panelBg,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: emphasized ? AppTheme.accentGreen : AppTheme.panelBorder,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 18,
                color: emphasized ? AppTheme.accentGreen : AppTheme.textMuted,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: emphasized ? AppTheme.accentGreen : Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
