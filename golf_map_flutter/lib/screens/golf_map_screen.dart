import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
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
import '../widgets/distance_details_sheet.dart';
import '../widgets/golf_map_view.dart';
import '../widgets/hole_selector.dart';
import '../widgets/hole_stats_panel.dart';
import '../widgets/score_panel.dart';
import '../widgets/track_shot_button.dart';

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
  List<String> _holes = [];
  String? _selectedCourse;
  String _selectedHole = '1';
  HoleStats? _currentHoleStats;
  final Map<String, int> _scores = {};
  final Map<String, List<PinnedShot>> _pinnedShots = {};

  bool _loading = true;
  bool _mapReady = false;
  bool _idealLineEnabled = true;
  bool _showBunkerDistancesOnMap = true;
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

  bool get _usingGpsForShot => isUsingGpsForShot(
        _userCoord,
        _currentHoleFeatures,
        course: _selectedCourse,
        hole: _selectedHole,
      );

  LatLng? get _measurementOrigin => shotDistanceOrigin(
        _userCoord,
        _currentHoleFeatures,
        selectedTeeFeatureId: _selectedTeeFeatureId,
        course: _selectedCourse,
        hole: _selectedHole,
      );

  int? get _holeYardage {
    final teeId = _selectedTeeFeatureId;
    if (teeId == null) return null;
    return holeYardageFromSelectedTee(_currentHoleFeatures, teeId);
  }

  List<PinnedShot> get _currentHolePinnedShots =>
      _pinnedShots[_selectedHole] ?? const [];

  bool get _showIdealLine =>
      _lockedMeasurementPoints.isEmpty && _idealLineEnabled;

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

      if (!mounted) return;

      setState(() {
        _features = features;
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
      }
      _refreshMeasurementDisplay();
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
        final saved = widget.initialScores?[hole];
        if (saved != null) {
          _scores[key] = saved;
        } else {
          _scores[key] = 0;
        }
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
    }
    _refreshMeasurementDisplay();

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
      _idealLineEnabled = true;
    });
  }

  void _recalculateMeasurementChain() {
    if (_lockedMeasurementPoints.isEmpty) return;

    final origin = _measurementOrigin;
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
    final origin = _measurementOrigin;
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

  void _deselectMeasurementPin() {
    if (_selectedMeasurementPinIndex == null) return;
    setState(() => _selectedMeasurementPinIndex = null);
  }

  void _deleteMeasurementPin(int index) {
    if (index < 0 || index >= _lockedMeasurementPoints.length) return;

    setState(() {
      _lockedMeasurementPoints.removeAt(index);
      _selectedMeasurementPinIndex = null;
    });

    if (_lockedMeasurementPoints.isEmpty) {
      _refreshMeasurementDisplay();
      return;
    }

    _recalculateMeasurementChain();
    _refreshMeasurementDisplay();
  }

  void _deleteSelectedMeasurementPin() {
    final index = _selectedMeasurementPinIndex;
    if (index == null) return;
    _deleteMeasurementPin(index);
  }

  void _moveLockedMeasurementPoint(int index, LatLng newPoint) {
    if (index < 0 || index >= _lockedMeasurementPoints.length) return;

    final origin = _measurementOrigin;

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

    final usingGps = _usingGpsForShot;
    final origin = _measurementOrigin;
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

  void _openDistanceDetails() {
    final info = _distanceInfo;
    if (info == null) return;

    DistanceDetailsSheet.show(
      context,
      courseName: _selectedCourse ?? 'Course',
      selectedHole: _selectedHole,
      par: _currentHoleStats?.par ?? 0,
      distanceInfo: info,
      teeOptions: _teeOptions,
      selectedTeeFeatureId: _selectedTeeFeatureId,
      onSelectTee: _selectTee,
      onPinShot: _pinBlueDotShot,
      pinnedShotCount: _currentHolePinnedShots.length,
      selectedMeasurementPinIndex: _selectedMeasurementPinIndex,
      onSelectMeasurementPin: _selectMeasurementPin,
      onDeleteSelectedPin: _deleteSelectedMeasurementPin,
    );
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

  void _handleTrackShotAction(TrackShotAction action) {
    switch (action) {
      case TrackShotAction.gps:
        _pinGpsShot();
      case TrackShotAction.mapPin:
        _pinBlueDotShot();
      case TrackShotAction.shotLine:
        if (_lockedMeasurementPoints.isEmpty) {
          setState(() => _idealLineEnabled = !_idealLineEnabled);
        }
    }
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

  int get _currentHoleRelativeToPar {
    final score = _currentHoleScore;
    final par = _currentHoleStats?.par ?? 0;
    if (score <= 0 || par <= 0 || score == par) return 0;
    return score - par;
  }

  int get _totalRelativeToPar {
    final course = _selectedCourse;
    if (course == null) return 0;
    return _holes.fold<int>(0, (sum, hole) {
      final score = _scores[_scoreKey(course, hole)] ?? 0;
      if (score <= 0) return sum;
      final par = _dataService.statsForHole(_features, course, hole)?.par ?? 0;
      if (par <= 0) return sum;
      return sum + (score - par);
    });
  }

  List<HoleScoreLine> get _scorecardLines {
    final course = _selectedCourse;
    if (course == null) return const [];

    return [
      for (final hole in _holes)
        HoleScoreLine(
          hole: hole,
          par: _dataService.statsForHole(_features, course, hole)?.par ?? 0,
          score: _scores[_scoreKey(course, hole)] ?? 0,
        ),
    ];
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
            showShotDirection: _showIdealLine,
            greenCenter: _greenCenter,
            shotOrigin: _shotOrigin,
            userCoord: _userCoord,
            selectedTeeFeatureId: _selectedTeeFeatureId,
            usingGpsForShot: _usingGpsForShot,
            onTap: _handleMapTap,
            onLockedMeasurementDrag: _handleLockedMeasurementDrag,
            onLockedMeasurementDragEnd: _handleLockedMeasurementDragEnd,
            onSelectMeasurementPin: _selectMeasurementPin,
            onDeselectMeasurementPin: _deselectMeasurementPin,
            selectedMeasurementPinIndex: _selectedMeasurementPinIndex,
            onSelectTee: _selectTee,
            onMapReady: () {
              setState(() => _mapReady = true);
              _focusOnHole();
            },
            pinnedShots: _currentHolePinnedShots,
            lockedMeasurementPoints: _lockedMeasurementPoints,
            greenYardages: _distanceInfo?.greenYardages,
            showGreenYardageCallout: true,
            bunkerDistances: _showBunkerDistancesOnMap
                ? (_distanceInfo?.bunkerDistances ?? const [])
                : const [],
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
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Text(
                          (_selectedCourse ?? 'Course').toUpperCase(),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: AppTheme.accentGreen,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.6,
                            height: 1.15,
                            shadows: [
                              Shadow(
                                color: AppTheme.accentGreen.withValues(
                                  alpha: 0.45,
                                ),
                                blurRadius: 8,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    _MapActionButton(
                      icon: Icons.save_rounded,
                      label: _savingRound ? 'Saving...' : 'Save Round',
                      emphasized: true,
                      onTap: _savingRound ? null : _saveRound,
                    ),
                  ],
                ),
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
            ),
          ),
        ),
        if (_currentHoleStats != null)
          Positioned(
            top: kIsWeb ? 132 : 117,
            right: 15,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                HoleStatsPanel(
                  stats: _currentHoleStats!,
                  yardage: _holeYardage,
                  greenYardages: _distanceInfo?.greenYardages,
                  showBunkerDistancesOnMap: _showBunkerDistancesOnMap,
                  onToggleBunkerDistancesOnMap: (value) {
                    setState(() => _showBunkerDistancesOnMap = value);
                  },
                  onOpenDetails: _distanceInfo == null
                      ? null
                      : _openDistanceDetails,
                ),
                if (_selectedMeasurementPinIndex != null) ...[
                  const SizedBox(height: 8),
                  _DeleteNodeButton(
                    onTap: () =>
                        _deleteMeasurementPin(_selectedMeasurementPinIndex!),
                  ),
                ],
              ],
            ),
          ),
        Positioned(
          left: 15,
          right: 15,
          bottom: MediaQuery.paddingOf(context).bottom + 6,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: TrackShotButton(
                  shotLineEnabled: _showIdealLine,
                  mapPinEnabled: _lockedMeasurementPoints.isNotEmpty,
                  pinnedShotCount: _currentHolePinnedShots.length,
                  onClearPins: _currentHolePinnedShots.isNotEmpty
                      ? _clearPinnedShots
                      : null,
                  onAction: _handleTrackShotAction,
                ),
              ),
              const SizedBox(height: 8),
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: ScorePanel(
                    selectedHole: _selectedHole,
                    par: _currentHoleStats?.par ?? 0,
                    currentHoleScore: _currentHoleScore,
                    totalScore: _totalScore,
                    scorecardLines: _scorecardLines,
                    holeRelativeToPar: _currentHoleRelativeToPar,
                    totalRelativeToPar: _totalRelativeToPar,
                    onDecrement: () => _updateScore(-1),
                    onIncrement: () => _updateScore(1),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DeleteNodeButton extends StatelessWidget {
  const _DeleteNodeButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Material(
        color: const Color(0xE61A1A22),
        elevation: 4,
        shadowColor: Colors.black54,
        shape: const CircleBorder(),
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0xFFEF4444), width: 1.5),
          ),
          child: const Icon(
            Icons.delete_outline_rounded,
            color: Color(0xFFEF4444),
            size: 20,
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
