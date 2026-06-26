import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:permission_handler/permission_handler.dart';

import '../config/app_theme.dart';
import '../models/golf_feature.dart';
import '../models/measurement_chain.dart';
import '../models/pinned_shot.dart';
import '../models/saved_round.dart';
import '../services/app_preferences_service.dart';
import '../services/golf_data_service.dart';
import '../services/round_live_activity_service.dart';
import '../services/round_storage_service.dart';
import '../utils/geo_utils.dart';
import '../widgets/distance_details_sheet.dart';
import '../widgets/golf_map_view.dart';
import '../widgets/hole_selector.dart';
import '../widgets/hole_stats_panel.dart';
import '../widgets/score_panel.dart';
import '../widgets/track_shot_button.dart';
import 'gps_to_green_screen.dart';

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

class _GolfMapScreenState extends State<GolfMapScreen> with WidgetsBindingObserver {
  final _dataService = GolfDataService();
  final _roundStorage = RoundStorageService();
  final _appPrefs = AppPreferencesService();
  final _liveActivity = RoundLiveActivityService.instance;
  final _mapController = MapController();
  final _mapViewportKey = GlobalKey();
  final _mapHeaderKey = GlobalKey();
  final _mapCourseNameKey = GlobalKey();
  final _mapHolePickerKey = GlobalKey();
  final _mapBottomBarKey = GlobalKey();
  final _mapSidebarKey = GlobalKey();
  int _holeFocusGeneration = 0;

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
  bool _showScoreTarget = true;
  bool _showBunkerDistancesOnMap = false;
  bool _savingRound = false;
  int? _scoreTargetTotal;

  LatLng? _userCoord;
  LatLng? _greenCenter;
  LatLng? _shotOrigin;
  final List<MeasurementChainPoint> _lockedMeasurementPoints = [];
  int? _selectedMeasurementPinIndex;
  DistanceInfo? _distanceInfo;
  dynamic _selectedTeeFeatureId;
  String? _preferredTeeLabel;
  StreamSubscription<Position>? _positionSub;
  Timer? _liveActivityGpsTimer;
  bool _promptedAlwaysLocation = false;
  bool _liveActivityReady = false;
  bool _liveActivityBootstrapped = false;
  bool _liveActivityGpsTimerStarted = false;
  int _liveActivitySession = 0;
  bool _appIsResumed = true;
  String? _pendingFocusHole;
  DateTime? _lastForegroundSyncAt;
  StreamSubscription<void>? _foregroundSub;
  int _mapVisualEpoch = 0;

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
    WidgetsBinding.instance.addObserver(this);
    if (widget.initialPinnedShots != null) {
      for (final entry in widget.initialPinnedShots!.entries) {
        final shots = entry.value;
        if (shots.isNotEmpty) {
          _pinnedShots[entry.key] = List<PinnedShot>.from(shots);
        }
      }
    }
    _loadData();
    _loadPreferences();
    _initLocation();
    unawaited(_bootstrapLiveActivity());
    _foregroundSub = _liveActivity.foregroundStream.listen((_) {
      unawaited(_handleAppReturnToForeground());
    });
  }

  Future<void> _bootstrapLiveActivity() async {
    _liveActivitySession = await _liveActivity.beginRound();
    if (!mounted) return;
    _liveActivityBootstrapped = true;
    _tryActivateLiveActivitySync();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appIsResumed = state == AppLifecycleState.resumed;

    if (state == AppLifecycleState.resumed && _liveActivityReady) {
      unawaited(_handleAppReturnToForeground());
      return;
    }
  }

  Future<void> _handleAppReturnToForeground() async {
    final now = DateTime.now();
    if (_lastForegroundSyncAt != null &&
        now.difference(_lastForegroundSyncAt!) <
            const Duration(milliseconds: 400)) {
      return;
    }
    _lastForegroundSyncAt = now;
    _appIsResumed = true;

    if (!_liveActivityReady) return;

    _liveActivity.resetGpsThrottle();
    _startLiveActivityGpsTimer();
    await _pullAndSyncAfterResume();
    await _refocusMapForCurrentHole();
  }

  Future<void> _pullAndSyncAfterResume() async {
    await _pullWidgetRoundChanges();
    if (!mounted || !_liveActivityReady) return;
    _syncLiveActivity(force: true);
  }

  Future<void> _refocusMapForCurrentHole() async {
    final hole = _pendingFocusHole ?? _selectedHole;
    _pendingFocusHole = hole;

    for (final delayMs in [0, 80, 200, 450, 800]) {
      if (delayMs > 0) {
        await Future<void>.delayed(Duration(milliseconds: delayMs));
      }
      if (!mounted) return;
      if (!_mapReady) continue;
      _focusOnHole(hole: hole);
    }

    if (mounted) {
      _pendingFocusHole = null;
      _wakeMapAfterCameraMove();
    }
  }

  /// flutter_map may not repaint after background resume until the user pans.
  /// A tiny camera nudge plus a rebuild forces tiles and layers to refresh.
  void _wakeMapAfterCameraMove() {
    if (!mounted || !_mapReady) return;

    final camera = _mapController.camera;
    if (camera.nonRotatedSize == MapCamera.kImpossibleSize) return;

    final center = camera.center;
    final zoom = camera.zoom;
    final rotation = camera.rotation;

    _mapController.move(center, zoom + 0.0001);
    _mapController.moveAndRotate(center, zoom, rotation);

    setState(() => _mapVisualEpoch++);
    SchedulerBinding.instance.scheduleForcedFrame();
  }

  void _resetMapToDefault() {
    if (!_mapReady) return;
    _focusOnHole(hole: _selectedHole);
  }

  void _startLiveActivityGpsTimer() {
    if (!Platform.isIOS || _liveActivityGpsTimerStarted) return;
    _liveActivityGpsTimerStarted = true;
    _liveActivityGpsTimer?.cancel();
    _liveActivityGpsTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted ||
          _loading ||
          _selectedCourse == null ||
          !_liveActivityReady) {
        return;
      }
      unawaited(_pullWidgetRoundChanges());
      unawaited(_syncLiveActivityGps(force: true));
    });
  }

  void _activateLiveActivitySync() {
    if (_liveActivityReady) return;
    _liveActivityReady = true;
    _liveActivity.resetGpsThrottle();
    _startLiveActivityGpsTimer();
  }

  void _tryActivateLiveActivitySync() {
    if (!_liveActivityBootstrapped || _loading || _selectedCourse == null) {
      return;
    }
    if (!_liveActivityReady) {
      _activateLiveActivitySync();
    }
    _syncLiveActivity(force: true);
  }

  LocationSettings get _locationSettings {
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return AppleSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 1,
        activityType: ActivityType.fitness,
        pauseLocationUpdatesAutomatically: false,
        allowBackgroundLocationUpdates: true,
        showBackgroundLocationIndicator: true,
      );
    }
    return const LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 2,
    );
  }

  Future<void> _loadPreferences() async {
    final showScoreTarget = await _appPrefs.getShowScoreTarget();
    final idealLineEnabled = await _appPrefs.getIdealLineEnabled();
    if (!mounted) return;
    setState(() {
      _showScoreTarget = showScoreTarget;
      _idealLineEnabled = idealLineEnabled;
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _foregroundSub?.cancel();
    _liveActivityReady = false;
    _liveActivityGpsTimer?.cancel();
    _positionSub?.cancel();
    unawaited(_liveActivity.end());
    super.dispose();
  }

  int get _liveActivityHoleScore =>
      _currentHoleScore > 0 ? _currentHoleScore : -1;

  void _syncLiveActivity({bool force = false}) {
    if (!_liveActivityReady || !_appIsResumed) return;
    final course = _selectedCourse;
    if (course == null || _loading) return;

    unawaited(_liveActivity.syncRound(
      courseName: course,
      hole: _selectedHole,
      par: _currentHoleStats?.par ?? 0,
      holeScore: _liveActivityHoleScore,
      totalScore: _totalScore,
      relativeToPar: _totalRelativeToPar,
      yardsToGreen: _yardsToGreenForLiveActivity,
      force: force,
      session: _liveActivitySession,
    ));
    _syncInteractiveRoundState();
  }

  void _syncInteractiveRoundState() {
    final course = _selectedCourse;
    if (course == null || _holes.isEmpty || !_liveActivityReady) return;

    final green = greenCenterForHole(_currentHoleFeatures);

    unawaited(_liveActivity.syncInteractiveRoundState(
      holes: _holes,
      selectedHole: _selectedHole,
      scores: {
        for (final hole in _holes)
          hole: _scores[_scoreKey(course, hole)] ?? 0,
      },
      pars: {
        for (final hole in _holes)
          hole: _dataService.statsForHole(_features, course, hole)?.par ?? 0,
      },
      courseName: course,
      yardsToGreen: _yardsToGreenForLiveActivity,
      greenLatitude: green?.latitude,
      greenLongitude: green?.longitude,
    ));
  }

  Future<void> _pullWidgetRoundChanges() async {
    final course = _selectedCourse;
    if (course == null || !_liveActivityReady) return;

    final changes = await _liveActivity.consumeWidgetChanges();
    if (changes == null || !mounted) return;
    if (changes.courseName != course) return;

    if (changes.pendingGpsPins.isNotEmpty) {
      for (final pin in changes.pendingGpsPins) {
        if (!_holes.contains(pin.hole)) continue;
        _addPinnedShot(
          LatLng(pin.latitude, pin.longitude),
          'GPS',
          hole: pin.hole,
          showSnackBar: pin.hole == _selectedHole,
        );
      }
      await _liveActivity.acknowledgePendingGpsPins();
    }

    final holeChanged = changes.selectedHole != _selectedHole;

    setState(() {
      for (final entry in changes.scores.entries) {
        _scores[_scoreKey(course, entry.key)] = entry.value;
      }
    });

    if (holeChanged) {
      if (!_holes.contains(changes.selectedHole) && _holes.isNotEmpty) {
        return;
      }
      _pendingFocusHole = changes.selectedHole;
      _clearDistance();
      _liveActivity.resetGpsThrottle();
      _refreshHoleState(holeOverride: changes.selectedHole);
      return;
    }

    await _liveActivity.syncInteractiveRoundState(
      holes: _holes,
      selectedHole: _selectedHole,
      scores: {
        for (final hole in _holes)
          hole: _scores[_scoreKey(course, hole)] ?? 0,
      },
      pars: {
        for (final hole in _holes)
          hole: _dataService.statsForHole(_features, course, hole)?.par ?? 0,
      },
      courseName: course,
      yardsToGreen: _yardsToGreenForLiveActivity,
      greenLatitude: greenCenterForHole(
        _features
            .where(
              (f) => f.matchesCourse(course) && f.matchesHole(changes.selectedHole),
            )
            .toList(),
      )?.latitude,
      greenLongitude: greenCenterForHole(
        _features
            .where(
              (f) => f.matchesCourse(course) && f.matchesHole(changes.selectedHole),
            )
            .toList(),
      )?.longitude,
      revision: changes.revision,
    );
  }

  Future<void> _syncLiveActivityGps({bool force = false}) async {
    if (!_liveActivityReady) return;
    final course = _selectedCourse;
    if (course == null || _loading) return;

    final shared = await _liveActivity.getSharedGpsYardage();
    if (shared != null &&
        shared.gpsRefreshRevision > _liveActivity.lastSeenNativeGpsRevision) {
      _liveActivity.acknowledgeNativeGpsRevision(shared.gpsRefreshRevision);
      try {
        final position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
          ),
        );
        if (mounted) {
          setState(() {
            _userCoord = LatLng(position.latitude, position.longitude);
          });
        }
      } catch (_) {}
    }

    final green = greenCenterForHole(_currentHoleFeatures);

    await _liveActivity.syncGpsYardage(
      courseName: course,
      hole: _selectedHole,
      par: _currentHoleStats?.par ?? 0,
      holeScore: _liveActivityHoleScore,
      totalScore: _totalScore,
      relativeToPar: _totalRelativeToPar,
      yardsToGreen: _gpsYardsToGreenForLiveActivity ?? shared?.yardsToGreen,
      greenLatitude: green?.latitude,
      greenLongitude: green?.longitude,
      force: force,
      session: _liveActivitySession,
    );
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
      if (Platform.isIOS) {
        unawaited(_requestAlwaysLocationIfNeeded());
      }
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

    await _requestAlwaysLocationIfNeeded();
    _startPositionStream();
  }

  Future<void> _requestAlwaysLocationIfNeeded() async {
    if (!Platform.isIOS) return;

    final always = await Permission.locationAlways.status;
    if (always.isGranted) return;

    final whenInUse = await Permission.locationWhenInUse.status;
    if (!whenInUse.isGranted) return;

    // iOS never offers "Always" on the first prompt — this second request can.
    final upgraded = await Permission.locationAlways.request();
    if (!mounted || upgraded.isGranted || _promptedAlwaysLocation) return;

    _promptedAlwaysLocation = true;
    await _showAlwaysLocationSettingsDialog();
  }

  Future<void> _showAlwaysLocationSettingsDialog() async {
    if (!mounted) return;

    final openSettings = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A22),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: AppTheme.panelBorder),
        ),
        title: const Text(
          'Enable Always for lock screen yardage',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: const Text(
          'iOS only shows "Allow While Using" at first. To update yardage on '
          'your lock screen, open Settings and set Location to Always.',
          style: TextStyle(color: AppTheme.textMuted, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Not now'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'Open Settings',
              style: TextStyle(color: AppTheme.accentGreen),
            ),
          ),
        ],
      ),
    );

    if (openSettings == true) {
      await openAppSettings();
    }
  }

  void _startPositionStream() {
    _positionSub?.cancel();
    _positionSub = Geolocator.getPositionStream(
      locationSettings: _locationSettings,
    ).listen((position) {
      if (!mounted) return;
      setState(() {
        _userCoord = LatLng(position.latitude, position.longitude);
      });
      if (_lockedMeasurementPoints.isNotEmpty) {
        _recalculateMeasurementChain();
      }
      _refreshMeasurementDisplay();
      if (_liveActivityReady) {
        unawaited(_syncLiveActivityGps());
      }
    });
  }

  void _refreshHoleState({String? holeOverride}) {
    final course = _selectedCourse;
    if (course == null) return;

    final holes = _dataService.holesForCourse(_features, course);
    var selectedHole = holeOverride ?? _selectedHole;
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

    _scheduleFocusOnHole(hole: selectedHole);
    _tryActivateLiveActivitySync();
  }

  void _scheduleFocusOnHole({String? hole}) {
    _pendingFocusHole = hole ?? _selectedHole;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _focusOnHole(hole: _pendingFocusHole);
      });
    });
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

  int? _yardageForHole(List<GolfFeature> holeFeatures) {
    final teeId = _selectedTeeFeatureId;
    if (teeId != null) {
      return holeYardageFromSelectedTee(holeFeatures, teeId);
    }
    final options = teeOptionsForHole(holeFeatures);
    if (options.isEmpty) return null;
    return holeYardageFromSelectedTee(holeFeatures, options.first.featureId);
  }

  EdgeInsets _mapFocusPadding() {
    const fallbackLeft = 88.0;
    const fallbackTop = 56.0;
    const fallbackRight = 79.0;
    const fallbackBottom = 92.0;

    final mapBox =
        _mapViewportKey.currentContext?.findRenderObject() as RenderBox?;
    if (mapBox == null || !mapBox.hasSize) {
      return const EdgeInsets.fromLTRB(
        fallbackLeft,
        fallbackTop,
        fallbackRight,
        fallbackBottom,
      );
    }

    final mapSize = mapBox.size;
    var top = fallbackTop;
    var bottom = fallbackBottom;
    var right = fallbackRight;
    var left = fallbackLeft;

    final courseNameRow =
        _mapCourseNameKey.currentContext?.findRenderObject() as RenderBox?;
    if (courseNameRow != null && courseNameRow.hasSize) {
      final courseNameBottom = mapBox.globalToLocal(
        courseNameRow.localToGlobal(Offset(0, courseNameRow.size.height)),
      );
      top = courseNameBottom.dy + 2;
    } else {
      final header =
          _mapHeaderKey.currentContext?.findRenderObject() as RenderBox?;
      if (header != null && header.hasSize) {
        final headerBottom = mapBox.globalToLocal(
          header.localToGlobal(Offset(0, header.size.height)),
        );
        top = headerBottom.dy + 2;
      }
    }

    final holePicker =
        _mapHolePickerKey.currentContext?.findRenderObject() as RenderBox?;
    if (holePicker != null && holePicker.hasSize) {
      final pickerRight = mapBox.globalToLocal(
        holePicker.localToGlobal(Offset(holePicker.size.width, 0)),
      );
      left = pickerRight.dx + 8;
    }

    final bottomBar =
        _mapBottomBarKey.currentContext?.findRenderObject() as RenderBox?;
    if (bottomBar != null && bottomBar.hasSize) {
      final bottomTop =
          mapBox.globalToLocal(bottomBar.localToGlobal(Offset.zero));
      bottom = mapSize.height - bottomTop.dy + 2;
    }

    final sidebar =
        _mapSidebarKey.currentContext?.findRenderObject() as RenderBox?;
    if (sidebar != null && sidebar.hasSize) {
      final sidebarLeft =
          mapBox.globalToLocal(sidebar.localToGlobal(Offset.zero));
      right = mapSize.width - sidebarLeft.dx + 8;
    }

    return EdgeInsets.fromLTRB(left, top, right, bottom);
  }

  static const _calloutFocusHeightPx = 80.0;

  LatLng? _greenCalloutAnchorForHole(List<GolfFeature> holeFeatures) {
    final green = greenCenterForHole(holeFeatures);
    if (green == null) return null;

    final tee = teePointById(holeFeatures, _selectedTeeFeatureId) ??
        longestTeeForHole(holeFeatures);
    if (tee == null) return green;

    return backOfGreenPoint(tee, holeFeatures) ?? green;
  }

  MapCamera _fitHoleCamera({
    required MapCamera camera,
    required List<LatLng> baseCoordinates,
    required EdgeInsets padding,
    required double rotation,
    LatLng? calloutAnchor,
    required double maxZoom,
  }) {
    var coords = List<LatLng>.from(baseCoordinates);
    var fitted = camera.withRotation(rotation);

    for (var pass = 0; pass < 3; pass++) {
      fitted = CameraFit.coordinates(
        coordinates: coords,
        padding: padding,
        maxZoom: maxZoom,
      ).fit(fitted);

      if (calloutAnchor == null) break;

      final anchorScreen = fitted.latLngToScreenOffset(calloutAnchor);
      final topPoint = fitted.screenOffsetToLatLng(
        anchorScreen - const Offset(0, _calloutFocusHeightPx),
      );
      coords = [...baseCoordinates, topPoint];
    }

    return fitted;
  }

  void _focusOnHole({String? hole}) {
    if (!_mapReady || _selectedCourse == null) return;

    final course = _selectedCourse!;
    final targetHole = hole ?? _selectedHole;
    final generation = ++_holeFocusGeneration;

    final holeFeatures = _features
        .where(
          (f) => f.matchesCourse(course) && f.matchesHole(targetHole),
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

    final stats = _dataService.statsForHole(_features, course, targetHole);
    final yardage = _yardageForHole(holeFeatures);
    final shortHole =
        stats?.par == 3 || (yardage != null && yardage <= 210);

    final ring = holeCameraFocusRing(
      _features,
      course,
      targetHole,
      tightZoom: shortHole,
    );
    final displayRing = holeEncirclementRing(_features, course, targetHole);
    final bounds = boundsForEncirclementRing(_features, course, targetHole) ??
        boundsForFeatures(holeFeatures);
    final center = centerForFeatures(holeFeatures);
    final calloutAnchor = _greenCalloutAnchorForHole(holeFeatures);
    final maxZoom = shortHole ? 20.0 : 19.0;

    void applyFocus() {
      if (!mounted || generation != _holeFocusGeneration) return;

      final camera = _mapController.camera;
      if (camera.nonRotatedSize == MapCamera.kImpossibleSize) {
        WidgetsBinding.instance.addPostFrameCallback((_) => applyFocus());
        return;
      }

      final padding = _mapFocusPadding();
      final focusCoords = ring.length >= 3 ? ring : displayRing;

      if (focusCoords.length >= 3) {
        final fitted = _fitHoleCamera(
          camera: camera,
          baseCoordinates: focusCoords,
          padding: padding,
          rotation: rotation,
          calloutAnchor: calloutAnchor,
          maxZoom: maxZoom,
        );

        _mapController.moveAndRotate(
          fitted.center,
          fitted.zoom,
          rotation,
        );
      } else if (bounds != null) {
        final fitted = CameraFit.bounds(
          bounds: bounds,
          padding: padding,
          maxZoom: maxZoom,
        ).fit(camera.withRotation(rotation));

        _mapController.moveAndRotate(
          fitted.center,
          fitted.zoom,
          rotation,
        );
      } else if (center != null) {
        _mapController.moveAndRotate(center, maxZoom - 2, rotation);
      }

      _wakeMapAfterCameraMove();
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      WidgetsBinding.instance.addPostFrameCallback((_) => applyFocus());
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

  GreenYardages? get _gpsGreenYardages {
    if (!_usingGpsForShot || _userCoord == null) return null;
    final holeFeatures = _currentHoleFeatures;
    if (greenCenterForHole(holeFeatures) == null) return null;
    return greenDistancesFromPoint(_userCoord!, holeFeatures);
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
    _syncLiveActivity();
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
    DistanceDetailsSheet.show(
      context,
      courseName: _selectedCourse ?? 'Course',
      selectedHole: _selectedHole,
      par: _currentHoleStats?.par ?? 0,
      distanceInfo: _distanceInfo,
      teeOptions: _teeOptions,
      selectedTeeFeatureId: _selectedTeeFeatureId,
      onSelectTee: _selectTee,
      onPinShot: _pinBlueDotShot,
      pinnedShotCount: _currentHolePinnedShots.length,
      selectedMeasurementPinIndex: _selectedMeasurementPinIndex,
      onSelectMeasurementPin: _selectMeasurementPin,
      onDeleteSelectedPin: _deleteSelectedMeasurementPin,
      showScoreTarget: _showScoreTarget,
      onShowScoreTargetChanged: (value) {
        setState(() => _showScoreTarget = value);
        _appPrefs.setShowScoreTarget(value);
      },
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

  void _addPinnedShot(
    LatLng point,
    String source, {
    String? hole,
    bool showSnackBar = true,
  }) {
    final course = _selectedCourse;
    if (course == null) return;

    final targetHole = hole ?? _selectedHole;
    final holeFeatures = _features
        .where(
          (f) => f.matchesCourse(course) && f.matchesHole(targetHole),
        )
        .toList();
    final teeFeatureId = targetHole == _selectedHole
        ? _selectedTeeFeatureId
        : teeOptionsForHole(holeFeatures).firstOrNull?.featureId;
    final teePoint = teePointById(holeFeatures, teeFeatureId) ??
        longestTeeForHole(holeFeatures);
    final holePins =
        List<PinnedShot>.from(_pinnedShots[targetHole] ?? const []);
    final shotNumber = holePins.length + 1;

    if (holePins.isEmpty && teePoint == null) {
      if (showSnackBar && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Select a tee box for the first shot')),
        );
      }
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
    final greenPoint = greenCenterForHole(holeFeatures);
    final yardsToPin = greenPoint != null
        ? greenDistancesFromPoint(point, holeFeatures).middle
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
      _pinnedShots[targetHole] = holePins;
    });

    if (showSnackBar && mounted) {
      final sourceLabel = source == 'GPS' ? 'GPS' : 'map';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Shot $shotNumber pinned ($sourceLabel) on hole $targetHole — $shotYards yds',
          ),
        ),
      );
    }
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

  void _setHoleScore(int score) {
    final course = _selectedCourse;
    if (course == null) return;
    setState(() {
      _scores[_scoreKey(course, _selectedHole)] = score.clamp(0, 99);
    });
    _syncLiveActivity(force: true);
  }

  void _selectHole(String hole) {
    _clearDistance();
    _liveActivity.resetGpsThrottle();
    _refreshHoleState(holeOverride: hole);
  }

  void _goToNextHole() {
    if (_holes.isEmpty) return;
    final index = _holes.indexOf(_selectedHole);
    final nextIndex = index < 0 ? 0 : (index + 1) % _holes.length;
    _selectHole(_holes[nextIndex]);
  }

  void _handleTrackShotAction(TrackShotAction action) {
    switch (action) {
      case TrackShotAction.gps:
        _pinGpsShot();
      case TrackShotAction.mapPin:
        _pinBlueDotShot();
      case TrackShotAction.shotLine:
        if (_lockedMeasurementPoints.isEmpty) {
          final enabled = !_idealLineEnabled;
          setState(() => _idealLineEnabled = enabled);
          _appPrefs.setIdealLineEnabled(enabled);
        }
    }
  }

  void _openGpsToGreen() {
    final course = _selectedCourse;
    if (course == null) return;

    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => GpsToGreenScreen(
          features: _features,
          course: course,
          hole: _selectedHole,
          holes: _holes,
          initialUserCoord: _userCoord,
        ),
      ),
    );
  }

  int get _currentHoleScore {
    final course = _selectedCourse;
    if (course == null) return 0;
    return _scores[_scoreKey(course, _selectedHole)] ?? 0;
  }

  int? get _gpsYardsToGreenForLiveActivity {
    final holeFeatures = _currentHoleFeatures;
    if (_userCoord != null && greenCenterForHole(holeFeatures) != null) {
      return greenDistancesFromPoint(_userCoord!, holeFeatures).middle;
    }
    return null;
  }

  int? get _yardsToGreenForLiveActivity {
    return _gpsYardsToGreenForLiveActivity ?? _holeYardage;
  }

  int get _totalScore {
    final course = _selectedCourse;
    if (course == null) return 0;
    return _holes.fold<int>(
      0,
      (sum, hole) => sum + (_scores[_scoreKey(course, hole)] ?? 0),
    );
  }

  int get _totalCoursePar {
    final course = _selectedCourse;
    if (course == null) return 0;
    return _holes.fold<int>(
      0,
      (sum, hole) =>
          sum + (_dataService.statsForHole(_features, course, hole)?.par ?? 0),
    );
  }

  int get _effectiveScoreTarget => _scoreTargetTotal ?? _totalCoursePar;

  int get _strokesRemainingForTarget =>
      _effectiveScoreTarget - _totalScore;

  int get _forToPlayLabel {
    final index = _holes.indexOf(_selectedHole);
    if (index >= 0) {
      return (_holes.length - index - 1).clamp(0, 999);
    }
    final parsed = int.tryParse(_selectedHole);
    if (parsed != null && _holes.isNotEmpty) {
      return (_holes.length - parsed).clamp(0, 999);
    }
    return 0;
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

  Future<bool> _saveRound() async {
    if (_savingRound) return false;
    final course = _selectedCourse;
    if (course == null) return false;

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
      if (!mounted) return false;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Round saved')),
      );
      return true;
    } catch (error) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save round: $error')),
      );
      return false;
    } finally {
      if (mounted) setState(() => _savingRound = false);
    }
  }

  Future<void> _handleSaveAndExit() async {
    final saved = await _saveRound();
    if (!mounted || !saved) return;
    await _liveActivity.end();
    if (!mounted) return;
    Navigator.pop(context, true);
  }

  Future<void> _handleBackPressed() async {
    final choice = await showDialog<_ExitRoundChoice>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A22),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: AppTheme.panelBorder),
        ),
        title: const Text(
          'Leave round?',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: const Text(
          'Do you want to save this round before leaving?',
          style: TextStyle(color: AppTheme.textMuted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, _ExitRoundChoice.cancel),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, _ExitRoundChoice.discard),
            child: const Text("Don't Save"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, _ExitRoundChoice.save),
            child: const Text(
              'Save',
              style: TextStyle(color: AppTheme.accentGreen),
            ),
          ),
        ],
      ),
    );

    if (!mounted || choice == null || choice == _ExitRoundChoice.cancel) {
      return;
    }

    if (choice == _ExitRoundChoice.discard) {
      await _liveActivity.end();
      if (!mounted) return;
      Navigator.pop(context, false);
      return;
    }

    await _handleSaveAndExit();
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

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _handleBackPressed();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: kIsWeb
            ? _buildBody()
            : SafeArea(child: _buildBody()),
      ),
    );
  }

  Widget _buildBody() {
    return Stack(
      children: [
        Positioned.fill(
          key: _mapViewportKey,
          child: GolfMapView(
            key: ValueKey('golf-map-$_selectedCourse'),
            mapController: _mapController,
            mapVisualEpoch: _mapVisualEpoch,
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
              final hole = _pendingFocusHole ?? _selectedHole;
              _focusOnHole(hole: hole);
              if (_pendingFocusHole != null) {
                unawaited(_refocusMapForCurrentHole());
              }
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
          child: KeyedSubtree(
            key: _mapHeaderKey,
            child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  key: _mapCourseNameKey,
                  children: [
                    _MapActionButton(
                      icon: Icons.arrow_back_rounded,
                      tooltip: 'Back',
                      onTap: _handleBackPressed,
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
                      tooltip: 'Save round',
                      emphasized: true,
                      onTap: _savingRound ? null : _handleSaveAndExit,
                    ),
                  ],
                ),
                if (_holes.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  KeyedSubtree(
                    key: _mapHolePickerKey,
                    child: SidebarHolePicker(
                      holes: _holes,
                      selectedHole: _selectedHole,
                      onSelectHole: _selectHole,
                      large: true,
                    ),
                  ),
                ],
              ],
            ),
          ),
          ),
        ),
        if (_currentHoleStats != null)
          Positioned(
            top: kIsWeb ? 72 : 64,
            right: 15,
            child: KeyedSubtree(
              key: _mapSidebarKey,
              child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                HoleStatsPanel(
                  stats: _currentHoleStats!,
                  onNextHole: _holes.length > 1 ? _goToNextHole : null,
                  yardage: _holeYardage,
                  gpsGreenYardages: _gpsGreenYardages,
                  showBunkerDistancesOnMap: _showBunkerDistancesOnMap,
                  onToggleBunkerDistancesOnMap: (value) {
                    setState(() => _showBunkerDistancesOnMap = value);
                  },
                  onOpenDetails: _openDistanceDetails,
                  onOpenGpsToGreen: _openGpsToGreen,
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
          ),
        Positioned(
          right: 15,
          bottom: MediaQuery.paddingOf(context).bottom + 118,
          child: _MapActionButton(
            icon: Icons.zoom_out_map_rounded,
            tooltip: 'Reset hole view',
            onTap: _mapReady ? _resetMapToDefault : null,
          ),
        ),
        Positioned(
          left: 15,
          right: 15,
          bottom: MediaQuery.paddingOf(context).bottom + 6,
          child: KeyedSubtree(
            key: _mapBottomBarKey,
            child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              TrackShotButton(
                shotLineEnabled: _showIdealLine,
                mapPinEnabled: _lockedMeasurementPoints.isNotEmpty,
                pinnedShotCount: _currentHolePinnedShots.length,
                onClearPins: _currentHolePinnedShots.isNotEmpty
                    ? _clearPinnedShots
                    : null,
                onAction: _handleTrackShotAction,
              ),
              const Spacer(),
              ScorePanel(
                par: _currentHoleStats?.par ?? 0,
                currentHoleScore: _currentHoleScore,
                totalScore: _totalScore,
                scorecardLines: _scorecardLines,
                courseName: _selectedCourse ?? 'Course',
                playedAt: widget.existingRoundPlayedAt ?? DateTime.now(),
                holeRelativeToPar: _currentHoleRelativeToPar,
                totalRelativeToPar: _totalRelativeToPar,
                strokesRemainingForEvenPar: _strokesRemainingForTarget,
                holesToPlay: _forToPlayLabel,
                showScoreTarget: _showScoreTarget,
                scoreTargetTotal: _effectiveScoreTarget,
                coursePar: _totalCoursePar,
                onScoreTargetChanged: (target) {
                  setState(() => _scoreTargetTotal = target);
                },
                onScoreChanged: _setHoleScore,
              ),
            ],
          ),
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
    this.tooltip,
    required this.onTap,
    this.emphasized = false,
  });

  final IconData icon;
  final String? tooltip;
  final VoidCallback? onTap;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final button = Material(
      color: emphasized
          ? AppTheme.accentGreen.withValues(alpha: 0.15)
          : AppTheme.panelBg,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: emphasized ? AppTheme.accentGreen : AppTheme.panelBorder,
            ),
          ),
          child: Icon(
            icon,
            size: 18,
            color: emphasized ? AppTheme.accentGreen : AppTheme.textMuted,
          ),
        ),
      ),
    );

    if (tooltip == null) return button;
    return Tooltip(message: tooltip!, child: button);
  }
}

enum _ExitRoundChoice { save, discard, cancel }
