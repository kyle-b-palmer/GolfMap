import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:permission_handler/permission_handler.dart';

import '../config/app_config.dart';
import '../config/app_theme.dart';
import '../models/golf_feature.dart';
import '../models/health_workout_mode.dart';
import '../models/measurement_chain.dart';
import '../models/pinned_shot.dart';
import '../models/pin_type.dart';
import '../models/saved_round.dart';
import '../services/app_preferences_service.dart';
import '../services/club_bag_service.dart';
import '../services/club_suggestion_service.dart';
import '../services/course_visit_service.dart';
import '../services/golf_data_service.dart';
import '../services/health_workout_service.dart';
import '../services/round_live_activity_service.dart';
import '../services/round_recap_share_service.dart';
import '../services/round_storage_service.dart';
import '../services/shot_dispersion_service.dart';
import '../services/weather_service.dart';
import '../utils/weather_adjustment.dart';
import '../utils/geo_utils.dart';
import '../widgets/distance_details_sheet.dart';
import '../widgets/golf_map_view.dart';
import '../widgets/hole_selector.dart';
import '../widgets/hole_stats_panel.dart';
import '../widgets/score_panel.dart';
import '../widgets/track_shot_button.dart';
import 'club_bag_screen.dart';
import 'gps_to_green_screen.dart';

class GolfMapScreen extends StatefulWidget {
  const GolfMapScreen({
    super.key,
    required this.initialCourse,
    this.initialScores,
    this.initialPutts,
    this.initialPinnedShots,
    this.initialMeasurementChains,
    this.initialLockedHoles,
    this.existingRoundId,
    this.existingRoundPlayedAt,
    this.startHealthWorkout,
  });

  final String initialCourse;
  final Map<String, int>? initialScores;
  final Map<String, int>? initialPutts;
  final Map<String, List<PinnedShot>>? initialPinnedShots;
  final Map<String, List<MeasurementChainPoint>>? initialMeasurementChains;
  final Set<String>? initialLockedHoles;
  final String? existingRoundId;
  final DateTime? existingRoundPlayedAt;
  final bool? startHealthWorkout;

  @override
  State<GolfMapScreen> createState() => _GolfMapScreenState();
}

class _GolfMapScreenState extends State<GolfMapScreen> with WidgetsBindingObserver {
  static const _mapEdgeInset = 15.0;
  static const _mapSidebarWidth = 52.0;
  static const _mapChromeGap = 8.0;
  static const _mapHeaderRowHeight = 52.0;

  final _dataService = GolfDataService();
  final _roundStorage = RoundStorageService();
  final _appPrefs = AppPreferencesService();
  final _courseVisits = CourseVisitService();
  final _liveActivity = RoundLiveActivityService.instance;
  final _weatherService = WeatherService();
  final _clubBagService = ClubBagService();
  final _clubSuggestionService = ClubSuggestionService();
  final _dispersionService = ShotDispersionService();
  final _recapShareService = RoundRecapShareService();
  final _healthWorkout = HealthWorkoutService.instance;
  final _mapController = MapController();
  final _mapViewportKey = GlobalKey();
  final _mapHeaderKey = GlobalKey();
  final _mapCourseNameKey = GlobalKey();
  final _mapHolePickerKey = GlobalKey();
  final _mapLeftToolbarKey = GlobalKey();
  final _mapLeftControlsKey = GlobalKey();
  final _mapDeleteButtonKey = GlobalKey();
  final _mapBottomBarKey = GlobalKey();
  final _mapSidebarKey = GlobalKey();
  int _holeFocusGeneration = 0;

  List<GolfFeature> _features = [];
  List<String> _holes = [];
  String? _selectedCourse;
  String _selectedHole = '1';
  HoleStats? _currentHoleStats;
  final Map<String, int> _scores = {};
  final Map<String, int> _putts = {};
  final Map<String, List<PinnedShot>> _pinnedShots = {};
  final Map<String, List<MeasurementChainPoint>> _measurementChainsByHole = {};
  final Set<String> _lockedHoles = {};

  bool _loading = true;
  bool _mapReady = false;
  bool _idealLineEnabled = true;
  bool _showScoreTarget = true;
  bool _mapOverlayEnabled = true;
  bool _showBunkerDistancesOnMap = false;
  bool _savingRound = false;
  int? _scoreTargetTotal;

  LatLng? _userCoord;
  LatLng? _greenCenter;
  LatLng? _shotOrigin;
  final List<MeasurementChainPoint> _lockedMeasurementPoints = [];
  int? _selectedMeasurementPinIndex;
  int? _selectedPinnedShotIndex;
  DistanceInfo? _distanceInfo;
  dynamic _selectedTeeFeatureId;
  String? _preferredTeeLabel;
  StreamSubscription<Position>? _positionSub;
  Timer? _liveActivityGpsTimer;
  Timer? _liveActivityGpsSlowTimer;
  bool _promptedAlwaysLocation = false;
  bool _liveActivityReady = false;
  bool _liveActivityBootstrapped = false;
  bool _liveActivityGpsTimerStarted = false;
  int _liveActivitySession = 0;
  bool _appIsResumed = true;
  String? _pendingFocusHole;
  DateTime? _lastForegroundSyncAt;
  StreamSubscription<String>? _stateChangeSub;
  int _mapVisualEpoch = 0;

  ClubSuggestion? _clubSuggestion;
  int? _playsLikeMiddle;
  bool _clubUsesAimTarget = false;
  final Map<String, LatLng> _clubAimByHole = {};
  bool _clubAimPlacementMode = false;
  bool _gpsSimMode = false;
  bool _gpsSimPlacementMode = false;
  bool _autoAdvanceHole = true;
  bool _showDispersion = false;
  List<DispersionPoint> _dispersionPoints = [];
  DateTime? _enteredGreenAt;
  bool _autoAdvanceTriggeredForHole = false;
  HealthWorkoutMode _healthWorkoutMode = HealthWorkoutMode.always;
  bool _healthWorkoutPromptHandled = false;
  Future<void>? _preferencesLoadFuture;

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
      );

  LatLng? get _measurementOrigin => shotDistanceOrigin(
        _userCoord,
        _currentHoleFeatures,
      );

  int? get _holeYardage => _yardageForHole(_currentHoleFeatures);

  List<PinnedShot> get _currentHolePinnedShots =>
      _pinnedShots[_selectedHole] ?? const [];

  bool get _isCurrentHoleLocked => _lockedHoles.contains(_selectedHole);

  LatLng? get _clubAimPoint => _clubAimByHole[_selectedHole];

  bool get _allowDriverSuggestion {
    if (_currentHolePinnedShots.isNotEmpty) return false;
    if (_lockedMeasurementPoints.isNotEmpty) return false;
    final coord = _userCoord;
    if (coord == null) return false;
    return isUserOnTeeBox(coord, _currentHoleFeatures);
  }

  LatLng? get _clubSuggestionOrigin => _userCoord;

  LatLng? get _clubSuggestionTarget {
    final aimPoint = _clubAimPoint;
    if (aimPoint != null) return aimPoint;

    return _greenCenter ?? greenCenterForHole(_currentHoleFeatures);
  }

  LatLng? get _clubAimLineOrigin => _userCoord ?? _measurementOrigin;

  LatLng? get _bunkerReferencePoint {
    if (_isCurrentHoleLocked) {
      return _lastTrackedPointForHole(_selectedHole);
    }

    if (_usingGpsForShot && _userCoord != null) {
      return _userCoord;
    }

    final lastTracked = _lastTrackedPointForHole(_selectedHole);
    if (lastTracked != null) return lastTracked;

    final holeFeatures = _currentHoleFeatures;
    return teePointById(holeFeatures, _selectedTeeFeatureId) ??
        longestTeeForHole(holeFeatures) ??
        _userCoord;
  }

  List<BunkerDistance> get _mapBunkerDistances {
    if (!_showBunkerDistancesOnMap) return const [];

    final from = _bunkerReferencePoint;
    if (from == null) return const [];

    return bunkerDistancesFromPoint(from, _currentHoleFeatures);
  }

  bool get _showIdealLine =>
      !_isCurrentHoleLocked &&
      _lockedMeasurementPoints.isEmpty &&
      _idealLineEnabled;

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
    if (widget.initialMeasurementChains != null) {
      for (final entry in widget.initialMeasurementChains!.entries) {
        final points = entry.value;
        if (points.isNotEmpty) {
          _measurementChainsByHole[entry.key] =
              List<MeasurementChainPoint>.from(points);
        }
      }
    }
    if (widget.initialLockedHoles != null) {
      _lockedHoles.addAll(widget.initialLockedHoles!);
    }
    _loadData();
    _preferencesLoadFuture = _loadPreferences();
    unawaited(_loadClubBag());
    _initLocation();
    unawaited(_bootstrapLiveActivity());
    _stateChangeSub = _liveActivity.stateChangeStream.listen((event) {
      if (event == 'watchState') {
        unawaited(_pullWidgetRoundChanges());
        return;
      }
      unawaited(_handleAppReturnToForeground());
    });
  }

  Future<void> _bootstrapLiveActivity() async {
    _liveActivitySession = await _liveActivity.beginRound();
    if (!mounted) return;
    if (widget.existingRoundId != null) {
      await _liveActivity.acknowledgePendingGpsPins();
      await _liveActivity.clearPendingGpsPinUndos();
    }
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
    _liveActivityGpsTimer = Timer.periodic(const Duration(milliseconds: 300), (_) {
      if (!mounted ||
          _loading ||
          _selectedCourse == null ||
          !_liveActivityReady) {
        return;
      }
      unawaited(_pullWidgetRoundChanges());
    });
    _liveActivityGpsSlowTimer?.cancel();
    _liveActivityGpsSlowTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted ||
          _loading ||
          _selectedCourse == null ||
          !_liveActivityReady) {
        return;
      }
      unawaited(_syncLiveActivityGps(force: true));
      unawaited(() async {
        await _pullWidgetRoundChanges();
        await _liveActivity.pushWatchRoundState();
      }());
    });
  }

  void _activateLiveActivitySync() {
    if (_liveActivityReady) return;
    _liveActivityReady = true;
    _liveActivity.resetGpsThrottle();
    _startLiveActivityGpsTimer();
    unawaited(_maybeStartHealthWorkout());
  }

  Future<void> _maybeStartHealthWorkout() async {
    if (!Platform.isIOS) return;
    if (widget.existingRoundId != null) return;

    if (widget.startHealthWorkout != null) {
      if (widget.startHealthWorkout!) {
        final available = await _healthWorkout.isAvailable();
        if (available) {
          await _healthWorkout.startGolfWorkout();
        }
      }
      return;
    }

    await (_preferencesLoadFuture ??= _loadPreferences());
    if (!mounted) return;

    switch (_healthWorkoutMode) {
      case HealthWorkoutMode.never:
        return;
      case HealthWorkoutMode.always:
        await _healthWorkout.startGolfWorkout();
        return;
      case HealthWorkoutMode.ask:
        if (_healthWorkoutPromptHandled) return;
        _healthWorkoutPromptHandled = true;

        final available = await _healthWorkout.isAvailable();
        if (!mounted || !available) return;

        final start = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            backgroundColor: AppTheme.panelBg,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: const BorderSide(color: AppTheme.panelBorder),
            ),
            title: const Text(
              'Start Apple Health workout?',
              style: TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
            content: const Text(
              'Track this round as a golf workout in Apple Health. '
              'You can change this in Hole details → settings.',
              style: TextStyle(
                color: AppTheme.textMuted,
                fontSize: 14,
                height: 1.35,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text(
                  'Not now',
                  style: TextStyle(color: AppTheme.textMuted),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text(
                  'Start workout',
                  style: TextStyle(
                    color: AppTheme.accentGreen,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        );
        if (start == true) {
          await _healthWorkout.startGolfWorkout();
        }
    }
  }

  void _tryActivateLiveActivitySync() {
    if (!_liveActivityBootstrapped || _loading || _selectedCourse == null) {
      return;
    }
    if (!_liveActivityReady) {
      _activateLiveActivitySync();
    }
    _syncLiveActivity(force: true);
    unawaited(_pushWatchRoundStateWhenReady());
  }

  Future<void> _pushWatchRoundStateWhenReady() async {
    if (_holes.isEmpty || _selectedCourse == null) return;
    await _liveActivity.syncInteractiveRoundState(
      holes: _holes,
      selectedHole: _selectedHole,
      scores: {
        for (final hole in _holes)
          hole: _scores[_scoreKey(_selectedCourse!, hole)] ?? 0,
      },
      putts: {
        for (final hole in _holes)
          hole: _putts[_scoreKey(_selectedCourse!, hole)] ?? 0,
      },
      pars: {
        for (final hole in _holes)
          hole: _dataService.statsForHole(_features, _selectedCourse!, hole)?.par ?? 0,
      },
      handicaps: {
        for (final hole in _holes)
          hole: _dataService.statsForHole(_features, _selectedCourse!, hole)?.handicap ?? 0,
      },
      courseName: _selectedCourse!,
      yardsToGreen: _yardsToGreenForLiveActivity,
      greenLatitude: greenCenterForHole(_currentHoleFeatures)?.latitude,
      greenLongitude: greenCenterForHole(_currentHoleFeatures)?.longitude,
      sessionId: _liveActivity.roundSessionId,
    );
    await _liveActivity.pushWatchRoundState();
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

  Future<void> _loadClubBag() async {
    final clubs = await _clubBagService.loadClubs();
    if (!mounted) return;
    _clubSuggestionService.updateClubs(clubs);
    unawaited(_refreshWeatherAndSuggestions());
  }

  Future<void> _openClubBagEditor() async {
    final updated = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const ClubBagScreen()),
    );
    if (updated == true && mounted) {
      await _loadClubBag();
    }
  }

  Future<void> _loadPreferences() async {
    final showScoreTarget = await _appPrefs.getShowScoreTarget();
    final idealLineEnabled = await _appPrefs.getIdealLineEnabled();
    final mapOverlayEnabled = await _appPrefs.getMapOverlayEnabled();
    final autoAdvanceHole = await _appPrefs.getAutoAdvanceHole();
    final showDispersion = await _appPrefs.getShowShotDispersion();
    final healthWorkoutMode = await _appPrefs.getHealthWorkoutMode();
    final gpsSimMode = await _appPrefs.getGpsSimModeEnabled();
    if (!mounted) return;
    setState(() {
      _showScoreTarget = showScoreTarget;
      _idealLineEnabled = idealLineEnabled;
      _mapOverlayEnabled = mapOverlayEnabled;
      _autoAdvanceHole = autoAdvanceHole;
      _showDispersion = showDispersion;
      _healthWorkoutMode = healthWorkoutMode;
      _gpsSimMode = gpsSimMode;
    });
    if (gpsSimMode) {
      _seedSimulatedGpsIfNeeded();
    }
  }

  LatLng? _defaultSimGpsForHole() {
    final holeFeatures = _currentHoleFeatures;
    return teePointById(holeFeatures, _selectedTeeFeatureId) ??
        longestTeeForHole(holeFeatures) ??
        greenCenterForHole(holeFeatures);
  }

  void _seedSimulatedGpsIfNeeded() {
    final seed = _defaultSimGpsForHole();
    if (seed == null) return;
    setState(() => _userCoord = seed);
    _refreshMeasurementDisplay();
    unawaited(_refreshWeatherAndSuggestions());
  }

  void _setSimulatedGps(LatLng point) {
    setState(() => _userCoord = point);
    _refreshMeasurementDisplay();
    unawaited(_refreshWeatherAndSuggestions());
    if (_liveActivityReady) {
      unawaited(_syncLiveActivityGps(force: true));
    }
  }

  Future<void> _toggleGpsSimMode() async {
    final enabling = !_gpsSimMode;
    setState(() {
      _gpsSimMode = enabling;
      _gpsSimPlacementMode = false;
      if (!enabling) {
        _clubAimPlacementMode = false;
      }
    });
    await _appPrefs.setGpsSimModeEnabled(enabling);

    if (enabling) {
      _seedSimulatedGpsIfNeeded();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'GPS test mode — drag the dot or tap “Place GPS” then tap the map',
            ),
          ),
        );
      }
      return;
    }

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
        _refreshMeasurementDisplay();
        unawaited(_refreshWeatherAndSuggestions());
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('GPS test mode off — could not read GPS')),
        );
      }
    }
  }

  void _toggleGpsSimPlacementMode() {
    if (!_gpsSimMode) {
      unawaited(_toggleGpsSimMode().then((_) {
        if (mounted) setState(() => _gpsSimPlacementMode = true);
      }));
      return;
    }
    setState(() => _gpsSimPlacementMode = !_gpsSimPlacementMode);
    if (_gpsSimPlacementMode && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tap the map to place your test GPS position')),
      );
    }
  }

  MapBackground get _mapBackground =>
      resolveMapBackground(overlayEnabled: _mapOverlayEnabled);

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stateChangeSub?.cancel();
    _liveActivityReady = false;
    _liveActivityGpsTimer?.cancel();
    _liveActivityGpsSlowTimer?.cancel();
    _positionSub?.cancel();
    unawaited(_healthWorkout.endGolfWorkout());
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
      putts: {
        for (final hole in _holes)
          hole: _putts[_scoreKey(course, hole)] ?? 0,
      },
      pars: {
        for (final hole in _holes)
          hole: _dataService.statsForHole(_features, course, hole)?.par ?? 0,
      },
      handicaps: {
        for (final hole in _holes)
          hole: _dataService.statsForHole(_features, course, hole)?.handicap ?? 0,
      },
      courseName: course,
      yardsToGreen: _yardsToGreenForLiveActivity,
      greenLatitude: green?.latitude,
      greenLongitude: green?.longitude,
      sessionId: _liveActivity.roundSessionId,
    ));
  }

  Future<void> _pullWidgetRoundChanges() async {
    final course = _selectedCourse;
    if (course == null || !_liveActivityReady) return;

    final changes = await _liveActivity.consumeWidgetChanges();
    if (changes == null || !mounted) return;
    if (changes.courseName != course) return;

    final holeChanged = changes.selectedHole != _selectedHole;

    setState(() {
      for (final entry in changes.scores.entries) {
        _scores[_scoreKey(course, entry.key)] = entry.value;
      }
      for (final entry in changes.putts.entries) {
        _putts[_scoreKey(course, entry.key)] = entry.value;
      }
    });

    final undosToApply = changes.pendingGpsPinUndos.where((undo) {
      if (!_holes.contains(undo.hole)) return false;
      for (final pin in changes.pendingGpsPins) {
        if (pin.hole != undo.hole) continue;
        if (metersToYards(
              distanceMeters(
                LatLng(pin.latitude, pin.longitude),
                LatLng(undo.latitude, undo.longitude),
              ),
            ) <
            25) {
          return false;
        }
      }
      return true;
    }).toList();

    if (undosToApply.isNotEmpty) {
      for (final pin in undosToApply) {
        _undoPinnedShot(
          pin,
          showSnackBar: pin.hole == _selectedHole,
        );
      }
    }

    if (changes.pendingGpsPins.isNotEmpty) {
      for (final pin in changes.pendingGpsPins) {
        if (!_holes.contains(pin.hole)) continue;
        final pinType = pin.pinKind == 'lostBall'
            ? PinType.lostBall
            : PinType.shot;
        _addPinnedShot(
          LatLng(pin.latitude, pin.longitude),
          pin.pinKind == 'lostBall' ? 'lostBall' : 'watch',
          hole: pin.hole,
          showSnackBar: pin.hole == _selectedHole,
          pinType: pinType,
        );
      }
    }

    if (changes.pendingGpsPins.isNotEmpty ||
        undosToApply.isNotEmpty) {
      await _liveActivity.acknowledgePendingGpsPins();
      if (mounted) {
        setState(() => _mapVisualEpoch++);
      }
    } else if (undosToApply.isEmpty &&
        changes.pendingGpsPinUndos.isNotEmpty) {
      // Scores already applied above; clear stale undos that did not match a pin.
      await _liveActivity.clearPendingGpsPinUndos();
    }

    if (holeChanged) {
      if (!_holes.contains(changes.selectedHole) && _holes.isNotEmpty) {
        return;
      }
      _pendingFocusHole = changes.selectedHole;
      _persistMeasurementChainForHole(_selectedHole);
      _clearDistance();
      _liveActivity.resetGpsThrottle();
      _refreshHoleState(holeOverride: changes.selectedHole);
      unawaited(_liveActivity.syncInteractiveRoundState(
        holes: _holes,
        selectedHole: _selectedHole,
        scores: {
          for (final hole in _holes)
            hole: _scores[_scoreKey(course, hole)] ?? 0,
        },
        putts: {
          for (final hole in _holes)
            hole: _putts[_scoreKey(course, hole)] ?? 0,
        },
        pars: {
          for (final hole in _holes)
            hole: _dataService.statsForHole(_features, course, hole)?.par ?? 0,
        },
        handicaps: {
          for (final hole in _holes)
            hole:
                _dataService.statsForHole(_features, course, hole)?.handicap ??
                    0,
        },
        courseName: course,
        yardsToGreen: _yardsToGreenForLiveActivity,
        greenLatitude: greenCenterForHole(_currentHoleFeatures)?.latitude,
        greenLongitude: greenCenterForHole(_currentHoleFeatures)?.longitude,
      ));
      return;
    }

    unawaited(_liveActivity.syncInteractiveRoundState(
      holes: _holes,
      selectedHole: _selectedHole,
      scores: {
        for (final hole in _holes)
          hole: _scores[_scoreKey(course, hole)] ?? 0,
      },
      putts: {
        for (final hole in _holes)
          hole: _putts[_scoreKey(course, hole)] ?? 0,
      },
      pars: {
        for (final hole in _holes)
          hole: _dataService.statsForHole(_features, course, hole)?.par ?? 0,
      },
      handicaps: {
        for (final hole in _holes)
          hole: _dataService.statsForHole(_features, course, hole)?.handicap ?? 0,
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
    ));
    unawaited(_liveActivity.pushWatchRoundState());
  }

  Future<void> _syncLiveActivityGps({bool force = false}) async {
    if (!_liveActivityReady) return;
    final course = _selectedCourse;
    if (course == null || _loading) return;

    final shared = await _liveActivity.getSharedGpsYardage();
    if (shared != null &&
        shared.gpsRefreshRevision > _liveActivity.lastSeenNativeGpsRevision &&
        !_gpsSimMode) {
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

      unawaited(_courseVisits.recordVisit(widget.initialCourse));
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
      if (_gpsSimMode) return;
      setState(() {
        _userCoord = LatLng(position.latitude, position.longitude);
      });
      if (_lockedMeasurementPoints.isNotEmpty) {
        _recalculateMeasurementChain();
      }
      _refreshMeasurementDisplay();
      unawaited(_refreshWeatherAndSuggestions());
      if (_liveActivityReady) {
        unawaited(_syncLiveActivityGps());
        _checkAutoAdvanceHole();
      }
    });
  }

  Future<void> _refreshWeatherAndSuggestions() async {
    final holeFeatures = _currentHoleFeatures;
    final origin = _clubSuggestionOrigin;
    final target = _clubSuggestionTarget;
    if (origin == null || target == null) {
      if (!mounted) return;
      setState(() {
        _playsLikeMiddle = null;
        _clubSuggestion = null;
        _clubUsesAimTarget = false;
      });
      return;
    }

    final weather = await _weatherService.fetchForLocation(origin);
    if (!mounted) return;

    final usesPlacedPoint = _clubAimPoint != null;
    final int? actualYards = usesPlacedPoint
        ? metersToYards(distanceMeters(origin, target))
        : greenDistancesFromPoint(origin, holeFeatures).middle;
    final bearing = bearingBetween(origin, target);

    ClubSuggestion? suggestion;
    var playsLike = actualYards;

    if (playsLike != null && playsLike > 0) {
      playsLike = playsLikeYards(
        actualYards: playsLike,
        temperatureF: weather?.temperatureF,
        windMph: weather?.windMph,
        windDirectionDeg: weather?.windDirectionDeg,
        shotBearingDeg: bearing,
        elevationFeet: weather?.elevationFeet,
      );
      suggestion = _clubSuggestionService.suggest(
        playsLike,
        allowDriver: _allowDriverSuggestion,
      );
    }

    setState(() {
      _playsLikeMiddle = playsLike;
      _clubSuggestion = suggestion;
      _clubUsesAimTarget = usesPlacedPoint;
    });
  }

  void _checkAutoAdvanceHole() {
    if (!_autoAdvanceHole || _userCoord == null || _holes.length <= 1) return;

    final onGreen = isPointInGreen(_userCoord!, _currentHoleFeatures);
    if (onGreen) {
      _enteredGreenAt ??= DateTime.now();
      if (!_autoAdvanceTriggeredForHole &&
          DateTime.now().difference(_enteredGreenAt!) >
              const Duration(seconds: 12)) {
        _autoAdvanceTriggeredForHole = true;
        _goToNextHole();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Advanced to hole $_selectedHole')),
        );
      }
    } else {
      _enteredGreenAt = null;
      _autoAdvanceTriggeredForHole = false;
    }
  }

  Future<void> _loadDispersionForCurrentHole() async {
    final course = _selectedCourse;
    if (course == null || !_showDispersion) return;
    final points = await _dispersionService.pointsForHole(
      courseName: course,
      hole: _selectedHole,
    );
    if (!mounted) return;
    setState(() => _dispersionPoints = points);
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
      if (!_putts.containsKey(key)) {
        final savedPutts = widget.initialPutts?[hole];
        if (savedPutts != null) {
          _putts[key] = savedPutts;
        } else {
          _putts[key] = 0;
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

    _pendingFocusHole = selectedHole;
    unawaited(_refocusMapForCurrentHole());
    _tryActivateLiveActivitySync();
    _restoreMeasurementChainForHole(selectedHole);
    if (_showDispersion) {
      unawaited(_loadDispersionForCurrentHole());
    }
    unawaited(_refreshWeatherAndSuggestions());
    if (_gpsSimMode && _userCoord == null) {
      _seedSimulatedGpsIfNeeded();
    }
  }

  void _applyTeeSelectionForHole() {
    final options = teeOptionsForHole(_currentHoleFeatures);
    if (options.isEmpty) {
      _selectedTeeFeatureId = null;
      return;
    }

    if (_preferredTeeLabel != null) {
      final selected = teeOptionByLabel(_currentHoleFeatures, _preferredTeeLabel!);
      _selectedTeeFeatureId = selected?.featureId;
      return;
    }

    _selectedTeeFeatureId = null;
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

    final leftToolbar =
        _mapLeftToolbarKey.currentContext?.findRenderObject() as RenderBox?;
    if (leftToolbar != null && leftToolbar.hasSize) {
      final toolbarRight = mapBox.globalToLocal(
        leftToolbar.localToGlobal(Offset(leftToolbar.size.width, 0)),
      );
      left = math.max(left, toolbarRight.dx + 8);
    }

    final leftControls =
        _mapLeftControlsKey.currentContext?.findRenderObject() as RenderBox?;
    if (leftControls != null && leftControls.hasSize) {
      final controlsRight = mapBox.globalToLocal(
        leftControls.localToGlobal(Offset(leftControls.size.width, 0)),
      );
      left = math.max(left, controlsRight.dx + 8);
      final controlsTop =
          mapBox.globalToLocal(leftControls.localToGlobal(Offset.zero));
      bottom = math.max(bottom, mapSize.height - controlsTop.dy + 2);
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

  LatLng? _lastTrackedPointForHole(String hole) {
    final pins = _sortedPinnedShotsForHole(hole)
        .where((shot) => shot.pinType != PinType.lostBall)
        .toList();
    if (pins.isNotEmpty) {
      final last = pins.last;
      return LatLng(last.latitude, last.longitude);
    }

    final chain = hole == _selectedHole
        ? (_lockedMeasurementPoints.isNotEmpty
            ? _lockedMeasurementPoints
            : _measurementChainsByHole[hole])
        : _measurementChainsByHole[hole];
    if (chain != null && chain.isNotEmpty) {
      return chain.last.point;
    }
    return null;
  }

  void _toggleHoleLock() {
    if (_isCurrentHoleLocked) {
      setState(() => _lockedHoles.remove(_selectedHole));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Hole unlocked — you can add shots')),
        );
      }
      return;
    }

    _persistMeasurementChainForHole(_selectedHole);
    setState(() => _lockedHoles.add(_selectedHole));
    _refreshMeasurementDisplay();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Hole locked — using last pegged shot')),
      );
    }
  }

  void _lockAllHolesBeforeSave() {
    _persistMeasurementChainForHole(_selectedHole);
    setState(() {
      _lockedHoles.addAll(_holes);
    });
  }

  void _persistMeasurementChainForHole(String hole) {
    if (_lockedMeasurementPoints.isEmpty) {
      _measurementChainsByHole.remove(hole);
      return;
    }
    _measurementChainsByHole[hole] = List<MeasurementChainPoint>.from(
      _lockedMeasurementPoints,
    );
  }

  void _restoreMeasurementChainForHole(String hole) {
    final chain = _measurementChainsByHole[hole];
    setState(() {
      _lockedMeasurementPoints
        ..clear()
        ..addAll(chain ?? const []);
      _selectedMeasurementPinIndex = null;
    });
    if (_lockedMeasurementPoints.isNotEmpty) {
      _refreshMeasurementDisplay();
    } else if (_lockedHoles.contains(hole)) {
      _refreshMeasurementDisplay();
    }
  }

  Map<String, List<MeasurementChainPoint>> _measurementChainsForSave() {
    final chains = <String, List<MeasurementChainPoint>>{
      for (final entry in _measurementChainsByHole.entries)
        if (entry.value.isNotEmpty)
          entry.key: List<MeasurementChainPoint>.from(entry.value),
    };
    if (_lockedMeasurementPoints.isNotEmpty) {
      chains[_selectedHole] = List<MeasurementChainPoint>.from(
        _lockedMeasurementPoints,
      );
    }
    return chains;
  }

  Map<String, List<PinnedShot>> _pinnedShotsForSave() {
    final pins = <String, List<PinnedShot>>{
      for (final entry in _pinnedShots.entries)
        if (entry.value.isNotEmpty)
          entry.key: List<PinnedShot>.from(entry.value),
    };

    final course = _selectedCourse;
    if (course == null) return pins;

    for (final entry in _measurementChainsForSave().entries) {
      _mergeMeasurementChainIntoPins(
        pins,
        hole: entry.key,
        chain: entry.value,
        course: course,
      );
    }
    return pins;
  }

  void _mergeMeasurementChainIntoPins(
    Map<String, List<PinnedShot>> pins, {
    required String hole,
    required List<MeasurementChainPoint> chain,
    required String course,
  }) {
    if (chain.isEmpty) return;

    final holeFeatures = _features
        .where((f) => f.matchesCourse(course) && f.matchesHole(hole))
        .toList();
    final holePins = List<PinnedShot>.from(pins[hole] ?? const []);

    for (final point in chain) {
      final candidate = point.point;
      final duplicate = holePins.any(
        (shot) =>
            metersToYards(
              distanceMeters(
                LatLng(shot.latitude, shot.longitude),
                candidate,
              ),
            ) <
            3,
      );
      if (duplicate) continue;

      final fromPoint = holePins.isEmpty
          ? candidate
          : LatLng(holePins.last.latitude, holePins.last.longitude);
      final shotNumber = holePins.length + 1;
      final greenPoint = greenCenterForHole(holeFeatures);
      final segmentYards = holePins.isEmpty && point.segmentYards <= 0
          ? null
          : point.segmentYards;

      holePins.add(
        PinnedShot(
          shotNumber: shotNumber,
          latitude: candidate.latitude,
          longitude: candidate.longitude,
          fromLatitude: fromPoint.latitude,
          fromLongitude: fromPoint.longitude,
          shotYards: segmentYards,
          yardsToPin: greenPoint != null
              ? greenDistancesFromPoint(candidate, holeFeatures).middle
              : null,
        ),
      );
    }

    if (holePins.isNotEmpty) {
      pins[hole] = holePins;
    }
  }

  void _clearDistance() {
    setState(() {
      _distanceInfo = null;
      _greenCenter = null;
      _shotOrigin = null;
      _lockedMeasurementPoints.clear();
      _selectedMeasurementPinIndex = null;
    });
  }

  LatLng? get _chainOrigin =>
      _isCurrentHoleLocked ? null : (_measurementOrigin ?? _userCoord);

  void _recalculateMeasurementChain() {
    if (_lockedMeasurementPoints.isEmpty) return;

    final origin = _chainOrigin;
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
      _shotOrigin = origin;
    });
  }

  void _addMeasurementChainPoint(LatLng point) {
    setState(() {
      _lockedMeasurementPoints.add(
        MeasurementChainPoint(
          point: point,
          segmentYards: 0,
          shotNumber: _lockedMeasurementPoints.length + 1,
        ),
      );
      _greenCenter = greenCenterForHole(_currentHoleFeatures);
      _selectedMeasurementPinIndex = null;
    });
    _recalculateMeasurementChain();
    _refreshMeasurementDisplay();
    unawaited(_refreshWeatherAndSuggestions());
  }

  void _selectMeasurementPin(int index) {
    if (index < 0 || index >= _lockedMeasurementPoints.length) return;
    setState(() {
      _selectedPinnedShotIndex = null;
      _selectedMeasurementPinIndex =
          _selectedMeasurementPinIndex == index ? null : index;
    });
  }

  void _deselectMeasurementPin() {
    if (_selectedMeasurementPinIndex == null) return;
    setState(() => _selectedMeasurementPinIndex = null);
  }

  void _selectPinnedShot(int index) {
    final pins = _sortedPinnedShotsForHole(_selectedHole);
    if (index < 0 || index >= pins.length) return;
    setState(() {
      _selectedMeasurementPinIndex = null;
      _selectedPinnedShotIndex =
          _selectedPinnedShotIndex == index ? null : index;
    });
  }

  void _deselectPinnedShot() {
    if (_selectedPinnedShotIndex == null) return;
    setState(() => _selectedPinnedShotIndex = null);
  }

  List<PinnedShot> _sortedPinnedShotsForHole(String hole) {
    final pins = List<PinnedShot>.from(_pinnedShots[hole] ?? const []);
    pins.sort((a, b) => a.shotNumber.compareTo(b.shotNumber));
    return pins;
  }

  void _deletePinnedShot(int index) {
    if (_isCurrentHoleLocked) return;
    final pins = _sortedPinnedShotsForHole(_selectedHole);
    if (index < 0 || index >= pins.length) return;

    final removed = pins[index];
    final course = _selectedCourse;
    pins.removeAt(index);

    final renumbered = <PinnedShot>[];
    for (var i = 0; i < pins.length; i++) {
      final shot = pins[i];
      renumbered.add(
        PinnedShot(
          shotNumber: i + 1,
          latitude: shot.latitude,
          longitude: shot.longitude,
          fromLatitude: shot.fromLatitude,
          fromLongitude: shot.fromLongitude,
          teeLabel: shot.teeLabel,
          shotYards: shot.shotYards,
          yardsToPin: shot.yardsToPin,
          pinType: shot.pinType,
        ),
      );
    }

    final scoreKey = course != null
        ? _scoreKey(course, _selectedHole)
        : null;
    final updatedScores = <String, int>{
      if (course != null)
        for (final hole in _holes)
          hole: _scores[_scoreKey(course, hole)] ?? 0,
    };
    if (scoreKey != null) {
      final currentScore = _scores[scoreKey] ?? 0;
      if (currentScore > 0) {
        updatedScores[_selectedHole] = currentScore - 1;
      }
    }

    setState(() {
      _selectedPinnedShotIndex = null;
      if (renumbered.isEmpty) {
        _pinnedShots.remove(_selectedHole);
      } else {
        _pinnedShots[_selectedHole] = renumbered;
      }
      if (scoreKey != null && updatedScores.containsKey(_selectedHole)) {
        _scores[scoreKey] = updatedScores[_selectedHole]!;
      }
    });

    if (course != null && _liveActivityReady) {
      unawaited(() async {
        await _liveActivity.reportPinnedShotRemoved(
          hole: _selectedHole,
          latitude: removed.latitude,
          longitude: removed.longitude,
          scores: updatedScores,
        );
        await Future<void>.delayed(const Duration(seconds: 2));
        await _liveActivity.clearPendingGpsPinUndos();
      }());
      _syncLiveActivity(force: true);
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Removed shot ${index + 1} on hole $_selectedHole')),
    );
  }

  void _deleteSelectedPinnedShot() {
    final index = _selectedPinnedShotIndex;
    if (index == null) return;
    _deletePinnedShot(index);
  }

  void _deleteMeasurementPin(int index) {
    if (_isCurrentHoleLocked) return;
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
    if (_isCurrentHoleLocked) return;
    if (index < 0 || index >= _lockedMeasurementPoints.length) return;

    final updated = List<MeasurementChainPoint>.from(_lockedMeasurementPoints);
    updated[index] = MeasurementChainPoint(
      point: newPoint,
      segmentYards: updated[index].segmentYards,
      shotNumber: updated[index].shotNumber,
    );

    setState(() {
      _lockedMeasurementPoints
        ..clear()
        ..addAll(updated);
    });
    _recalculateMeasurementChain();
    _refreshMeasurementDisplay();
    if (_clubAimPoint != null) {
      unawaited(_refreshWeatherAndSuggestions());
    }
  }

  void _moveClubAimPoint(LatLng point) {
    if (_isCurrentHoleLocked) return;
    setState(() => _clubAimByHole[_selectedHole] = point);
    unawaited(_refreshWeatherAndSuggestions());
  }

  void _handleLockedMeasurementDrag(int index, LatLng point) {
    _moveLockedMeasurementPoint(index, point);
  }

  void _handleLockedMeasurementDragEnd(int index, LatLng point) {
    _moveLockedMeasurementPoint(index, point);
  }

  GreenYardages? get _gpsGreenYardages {
    final holeFeatures = _currentHoleFeatures;
    if (greenCenterForHole(holeFeatures) == null) return null;

    final origin = _isCurrentHoleLocked
        ? _lastTrackedPointForHole(_selectedHole)
        : _userCoord;
    if (origin == null) return null;
    return greenDistancesFromPoint(origin, holeFeatures);
  }

  int? get _yardsFromUserToLastPin {
    if (_isCurrentHoleLocked || _userCoord == null) return null;

    final pins = _sortedPinnedShotsForHole(_selectedHole)
        .where((shot) => shot.pinType != PinType.lostBall)
        .toList();
    LatLng? target;
    if (pins.isNotEmpty) {
      final last = pins.last;
      target = LatLng(last.latitude, last.longitude);
    } else if (_lockedMeasurementPoints.isNotEmpty) {
      target = _lockedMeasurementPoints.last.point;
    }
    if (target == null) return null;

    final yards = metersToYards(distanceMeters(_userCoord!, target));
    return yards < 1 ? null : yards;
  }

  void _refreshMeasurementDisplay() {
    final holeFeatures = _currentHoleFeatures;
    final greenPoint = greenCenterForHole(holeFeatures);
    if (greenPoint == null) {
      setState(() => _distanceInfo = null);
      return;
    }

    final usingGps = _usingGpsForShot && !_isCurrentHoleLocked;
    final origin = _chainOrigin;
    final bunkerFrom = _bunkerReferencePoint;
    final lastTracked = _lastTrackedPointForHole(_selectedHole);
    final referencePoint = _isCurrentHoleLocked
        ? lastTracked
        : (_lockedMeasurementPoints.lastOrNull?.point ?? origin ?? bunkerFrom);

    final bunkerDistances = bunkerFrom == null
        ? const <BunkerDistance>[]
        : bunkerDistancesFromPoint(bunkerFrom, holeFeatures);

    if (referencePoint == null) {
      setState(() {
        _greenCenter = greenPoint;
        _shotOrigin = origin;
        _distanceInfo = bunkerFrom == null
            ? null
            : DistanceInfo(
                greenYardages: const GreenYardages(
                  front: 0,
                  middle: 0,
                  back: 0,
                ),
                bunkerDistances: bunkerDistances,
                hasBunkerReference: true,
                fromUserYards: null,
                lockedSegments: const [],
                activeSegmentYards: null,
                holeNumber: _selectedHole,
                holeCoord: [greenPoint.longitude, greenPoint.latitude],
                shotOriginCoord: [
                  bunkerFrom.longitude,
                  bunkerFrom.latitude,
                ],
                usingGps: usingGps,
              );
      });
      return;
    }

    setState(() {
      _greenCenter = greenPoint;
      _shotOrigin = origin;
      _distanceInfo = DistanceInfo(
        greenYardages: greenDistancesFromPoint(referencePoint, holeFeatures),
        bunkerDistances: bunkerDistances,
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

  void _handleMapTap(LatLng tapped) {
    if (_isCurrentHoleLocked) return;
    if (_gpsSimMode && _gpsSimPlacementMode) {
      setState(() => _gpsSimPlacementMode = false);
      _setSimulatedGps(tapped);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Test GPS position set')),
        );
      }
      return;
    }
    if (_clubAimPlacementMode) {
      setState(() {
        _clubAimByHole[_selectedHole] = tapped;
        _clubAimPlacementMode = false;
      });
      unawaited(_refreshWeatherAndSuggestions());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Club target set — distance to this point')),
        );
      }
      return;
    }
    _addMeasurementChainPoint(tapped);
  }

  void _toggleClubAimPlacementMode() {
    if (_isCurrentHoleLocked) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unlock the hole to set a club target')),
      );
      return;
    }
    setState(() => _clubAimPlacementMode = !_clubAimPlacementMode);
    if (_clubAimPlacementMode && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tap the map where you want to land')),
      );
    }
  }

  void _clearClubAimPoint() {
    setState(() {
      _clubAimByHole.remove(_selectedHole);
      _clubAimPlacementMode = false;
    });
    unawaited(_refreshWeatherAndSuggestions());
  }

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
      healthWorkoutMode: Platform.isIOS ? _healthWorkoutMode : null,
      onHealthWorkoutModeChanged: Platform.isIOS
          ? (mode) {
              setState(() => _healthWorkoutMode = mode);
              _appPrefs.setHealthWorkoutMode(mode);
            }
          : null,
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
    PinType pinType = PinType.shot,
  }) {
    final course = _selectedCourse;
    if (course == null) return;

    final targetHole = hole ?? _selectedHole;
    if (targetHole == _selectedHole && _isCurrentHoleLocked) {
      if (showSnackBar && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Unlock the hole to add shots')),
        );
      }
      return;
    }

    final holeFeatures = _features
        .where(
          (f) => f.matchesCourse(course) && f.matchesHole(targetHole),
        )
        .toList();
    final holePins =
        List<PinnedShot>.from(_pinnedShots[targetHole] ?? const []);
    final shotNumber = holePins.length + 1;
    final isWatchPin = source == 'watch';

    if (isWatchPin) {
      const dedupRadiusYards = 25;
      final candidate = point;
      for (final existing in holePins) {
        final existingPoint =
            LatLng(existing.latitude, existing.longitude);
        if (metersToYards(distanceMeters(existingPoint, candidate)) <
            dedupRadiusYards) {
          return;
        }
      }
    }

    final LatLng fromPoint;
    int? shotYards;
    if (holePins.isEmpty) {
      fromPoint = _userCoord ?? point;
      shotYards = _userCoord == null
          ? null
          : metersToYards(distanceMeters(fromPoint, point));
      if (shotYards != null && shotYards < 1) shotYards = null;
    } else {
      final previous = holePins.last;
      fromPoint = LatLng(previous.latitude, previous.longitude);
      shotYards = metersToYards(distanceMeters(fromPoint, point));
    }

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
        shotYards: shotYards,
        yardsToPin: yardsToPin,
        pinType: pinType,
      ),
    );

    setState(() {
      _pinnedShots[targetHole] = holePins;
    });

    if (targetHole == _selectedHole) {
      unawaited(_refreshWeatherAndSuggestions());
    }

    if (showSnackBar && mounted) {
      final sourceLabel = switch (source) {
        'GPS' => 'GPS',
        'watch' => 'watch',
        'lostBall' => 'lost ball',
        _ => 'map',
      };
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            shotYards != null
                ? 'Shot $shotNumber pinned ($sourceLabel) on hole $targetHole — $shotYards yds'
                : 'Shot $shotNumber pinned ($sourceLabel) on hole $targetHole',
          ),
        ),
      );
    }
  }

  void _undoPinnedShot(
    LiveActivityGpsPin pin, {
    bool showSnackBar = true,
  }) {
    final holePins = List<PinnedShot>.from(_pinnedShots[pin.hole] ?? const []);
    if (holePins.isEmpty) return;

    const toleranceYards = 25;
    var removeIndex = holePins.lastIndexWhere(
      (shot) =>
          metersToYards(
            distanceMeters(
              LatLng(shot.latitude, shot.longitude),
              LatLng(pin.latitude, pin.longitude),
            ),
          ) <
          toleranceYards,
    );
    if (removeIndex < 0) return;

    holePins.removeAt(removeIndex);

    final renumbered = <PinnedShot>[];
    for (var i = 0; i < holePins.length; i++) {
      final shot = holePins[i];
      renumbered.add(
        PinnedShot(
          shotNumber: i + 1,
          latitude: shot.latitude,
          longitude: shot.longitude,
          fromLatitude: shot.fromLatitude,
          fromLongitude: shot.fromLongitude,
          teeLabel: shot.teeLabel,
          shotYards: shot.shotYards,
          yardsToPin: shot.yardsToPin,
          pinType: shot.pinType,
        ),
      );
    }

    setState(() {
      if (renumbered.isEmpty) {
        _pinnedShots.remove(pin.hole);
      } else {
        _pinnedShots[pin.hole] = renumbered;
      }
    });

    if (showSnackBar && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Undid last swing pin on hole ${pin.hole}'),
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

  void _setHolePutts(int putts) {
    final course = _selectedCourse;
    if (course == null) return;
    setState(() {
      _putts[_scoreKey(course, _selectedHole)] = putts.clamp(0, 9);
    });
    _syncLiveActivity(force: true);
  }

  void _selectHole(String hole) {
    _persistMeasurementChainForHole(_selectedHole);
    _clearDistance();
    setState(() {
      _selectedPinnedShotIndex = null;
      _selectedMeasurementPinIndex = null;
      _enteredGreenAt = null;
      _autoAdvanceTriggeredForHole = false;
      _clubAimPlacementMode = false;
      _gpsSimPlacementMode = false;
    });
    _liveActivity.resetGpsThrottle();
    _refreshHoleState(holeOverride: hole);
    if (_gpsSimMode) {
      _seedSimulatedGpsIfNeeded();
    }
    unawaited(_loadDispersionForCurrentHole());
    unawaited(_refreshWeatherAndSuggestions());
  }

  void _goToNextHole() {
    if (_holes.isEmpty) return;
    final index = _holes.indexOf(_selectedHole);
    final nextIndex = index < 0 ? 0 : (index + 1) % _holes.length;
    _selectHole(_holes[nextIndex]);
  }

  void _handleTrackShotAction(TrackShotAction action) {
    if (_isCurrentHoleLocked) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unlock the hole to track more shots')),
      );
      return;
    }

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
      case TrackShotAction.lostBall:
        _pinLostBall();
    }
  }

  void _pinLostBall() {
    final point = _userCoord;
    if (point == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('GPS not available for lost ball pin')),
      );
      return;
    }

    _addPinnedShot(point, 'lostBall', pinType: PinType.lostBall);
    final course = _selectedCourse;
    if (course == null) return;
    setState(() {
      final key = _scoreKey(course, _selectedHole);
      _scores[key] = (_scores[key] ?? 0) + 1;
    });
    _syncLiveActivity(force: true);
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

  int get _currentHolePutts {
    final course = _selectedCourse;
    if (course == null) return 0;
    return _putts[_scoreKey(course, _selectedHole)] ?? 0;
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
          putts: _putts[_scoreKey(course, hole)] ?? 0,
        ),
    ];
  }

  Future<bool> _saveRound() async {
    if (_savingRound) return false;
    final course = _selectedCourse;
    if (course == null) return false;

    setState(() => _savingRound = true);
    try {
      _lockAllHolesBeforeSave();
      final scores = <String, int>{
        for (final hole in _holes)
          hole: _scores[_scoreKey(course, hole)] ?? 0,
      };
      final putts = <String, int>{
        for (final hole in _holes)
          hole: _putts[_scoreKey(course, hole)] ?? 0,
      };

      final round = SavedRound(
        id: widget.existingRoundId ??
            DateTime.now().millisecondsSinceEpoch.toString(),
        courseName: course,
        playedAt: widget.existingRoundPlayedAt ?? DateTime.now(),
        scores: scores,
        putts: putts,
        pinnedShots: _pinnedShotsForSave(),
        measurementChains: _measurementChainsForSave(),
        lockedHoles: Set<String>.from(_lockedHoles),
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

    final course = _selectedCourse;
    if (course != null) {
      final offerShare = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A22),
          title: const Text('Round saved', style: TextStyle(color: Colors.white)),
          content: const Text(
            'Share a round recap image?',
            style: TextStyle(color: AppTheme.textMuted),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Not now'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text(
                'Share recap',
                style: TextStyle(color: AppTheme.accentGreen),
              ),
            ),
          ],
        ),
      );

      if (offerShare == true && mounted) {
        final scores = <String, int>{
          for (final hole in _holes)
            hole: _scores[_scoreKey(course, hole)] ?? 0,
        };
        final pars = <String, int>{
          for (final hole in _holes)
            hole: _dataService.statsForHole(_features, course, hole)?.par ?? 0,
        };
        final round = SavedRound(
          id: widget.existingRoundId ??
              DateTime.now().millisecondsSinceEpoch.toString(),
          courseName: course,
          playedAt: widget.existingRoundPlayedAt ?? DateTime.now(),
          scores: scores,
          putts: {
            for (final hole in _holes)
              hole: _putts[_scoreKey(course, hole)] ?? 0,
          },
          pinnedShots: _pinnedShotsForSave(),
          measurementChains: _measurementChainsForSave(),
          lockedHoles: Set<String>.from(_lockedHoles),
        );
        await _recapShareService.shareRoundRecap(
          context: context,
          round: round,
          lines: _scorecardLines,
          totalScore: _totalScore,
          relativeToPar: _totalRelativeToPar,
          longestDriveYards:
              RoundRecapShareService.longestDrive(_pinnedShotsForSave()),
          bestHoleLabel: RoundRecapShareService.bestHoleVsPar(
            scores: scores,
            pars: pars,
          ),
        );
      }
    }

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

  Widget _buildMapActionPanel() {
    return MapActionPanel(
      holeLocked: _isCurrentHoleLocked,
      onToggleHoleLock: _toggleHoleLock,
      clubAimPlacementMode: _clubAimPlacementMode,
      hasClubAimPoint: _clubAimPoint != null,
      onToggleClubAimPlacement:
          _isCurrentHoleLocked ? null : _toggleClubAimPlacementMode,
      onClearClubAimPoint: _clubAimPoint != null ? _clearClubAimPoint : null,
      gpsSimMode: _gpsSimMode,
      gpsSimPlacementMode: _gpsSimPlacementMode,
      onToggleGpsSimMode: _toggleGpsSimMode,
      onToggleGpsSimPlacement: _toggleGpsSimPlacementMode,
      showClubBagButton: _clubSuggestion == null,
      onEditClubBag: _openClubBagEditor,
      showMapOverlay: _mapOverlayEnabled,
      onToggleMapOverlay: (value) {
        setState(() => _mapOverlayEnabled = value);
        unawaited(_appPrefs.setMapOverlayEnabled(value));
        _wakeMapAfterCameraMove();
      },
      showBunkerDistancesOnMap: _showBunkerDistancesOnMap,
      onToggleBunkerDistancesOnMap: (value) {
        setState(() => _showBunkerDistancesOnMap = value);
        _refreshMeasurementDisplay();
        if (!value || !mounted) return;

        final from = _bunkerReferencePoint;
        if (from == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Need GPS, a tee, or a tracked shot for bunker distances',
              ),
            ),
          );
          return;
        }

        final bunkers = bunkerDistancesFromPoint(from, _currentHoleFeatures);
        if (bunkers.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No bunkers on this hole')),
          );
        }
      },
      showDispersion: _showDispersion,
      onToggleDispersion: (value) {
        setState(() => _showDispersion = value);
        unawaited(_appPrefs.setShowShotDispersion(value));
        if (value) {
          unawaited(_loadDispersionForCurrentHole());
        } else {
          setState(() => _dispersionPoints = []);
        }
      },
      autoAdvanceHole: _autoAdvanceHole,
      onToggleAutoAdvance: (value) {
        setState(() => _autoAdvanceHole = value);
        unawaited(_appPrefs.setAutoAdvanceHole(value));
      },
      onOpenDetails: _openDistanceDetails,
      onOpenGpsToGreen: _openGpsToGreen,
    );
  }

  Widget _buildLeftBottomControls() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
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
        const SizedBox(height: 8),
        _MapActionButton(
          icon: Icons.zoom_out_map_rounded,
          tooltip: 'Reset hole view',
          onTap: _mapReady ? _resetMapToDefault : null,
        ),
      ],
    );
  }

  Widget? _buildDeleteSelectedPinButton() {
    if (_isCurrentHoleLocked) return null;
    if (_selectedPinnedShotIndex == null &&
        _selectedMeasurementPinIndex == null) {
      return null;
    }

    return KeyedSubtree(
      key: _mapDeleteButtonKey,
      child: DeleteSelectedPinButton(
        label: _selectedPinnedShotIndex != null
            ? 'Delete shot pin'
            : 'Delete shot node',
        onTap: _selectedPinnedShotIndex != null
            ? _deleteSelectedPinnedShot
            : () => _deleteMeasurementPin(_selectedMeasurementPinIndex!),
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
            mapBackground: _mapBackground,
            features: _features,
            selectedCourse: _selectedCourse,
            selectedHole: _selectedHole,
            showShotDirection: _showIdealLine,
            greenCenter: _greenCenter,
            shotOrigin: _shotOrigin,
            userCoord: _userCoord,
            gpsSimMode: _gpsSimMode,
            onUserCoordDrag: _gpsSimMode ? _setSimulatedGps : null,
            onUserCoordDragEnd: _gpsSimMode ? _setSimulatedGps : null,
            selectedTeeFeatureId: _selectedTeeFeatureId,
            usingGpsForShot: _usingGpsForShot,
            onTap: _handleMapTap,
            onLockedMeasurementDrag: _handleLockedMeasurementDrag,
            onLockedMeasurementDragEnd: _handleLockedMeasurementDragEnd,
            onSelectMeasurementPin: _selectMeasurementPin,
            onDeselectMeasurementPin: _deselectMeasurementPin,
            onSelectPinnedShot: _selectPinnedShot,
            onDeselectPinnedShot: _deselectPinnedShot,
            selectedMeasurementPinIndex: _selectedMeasurementPinIndex,
            selectedPinnedShotIndex: _selectedPinnedShotIndex,
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
            bunkerDistances: _mapBunkerDistances,
            dispersionPoints: _dispersionPoints,
            showDispersion: _showDispersion,
            holeLocked: _isCurrentHoleLocked,
            clubAimPoint: _clubAimPoint,
            clubAimOrigin: _clubAimLineOrigin,
            onClubAimDrag: _isCurrentHoleLocked ? null : _moveClubAimPoint,
            onClubAimDragEnd: _isCurrentHoleLocked ? null : _moveClubAimPoint,
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
              ],
            ),
          ),
          ),
        ),
        if (_holes.isNotEmpty)
          Positioned(
            left: _mapEdgeInset,
            top: _mapTopInset(context) + _mapHeaderRowHeight,
            bottom: MediaQuery.paddingOf(context).bottom + 6,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                KeyedSubtree(
                  key: _mapHolePickerKey,
                  child: SidebarHolePicker(
                    holes: _holes,
                    selectedHole: _selectedHole,
                    onSelectHole: _selectHole,
                    large: true,
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: KeyedSubtree(
                    key: _mapLeftToolbarKey,
                    child: SingleChildScrollView(
                      child: _buildMapActionPanel(),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                KeyedSubtree(
                  key: _mapLeftControlsKey,
                  child: _buildLeftBottomControls(),
                ),
              ],
            ),
          ),
        if (_currentHoleStats != null)
          Positioned(
            top: kIsWeb ? 72 : 64,
            right: _mapEdgeInset,
            child: KeyedSubtree(
              key: _mapSidebarKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  HoleStatsPanel(
                    stats: _currentHoleStats!,
                    yardage: _holeYardage,
                    gpsGreenYardages: _gpsGreenYardages,
                    playsLikeYards: _playsLikeMiddle,
                    yardsFromLastPin: _yardsFromUserToLastPin,
                    clubSuggestion: _clubSuggestion,
                    clubUsesAimTarget: _clubUsesAimTarget,
                    onEditClubBag: _openClubBagEditor,
                  ),
                  if (_holes.length > 1) ...[
                    const SizedBox(height: 8),
                    NextHoleButton(onTap: _goToNextHole),
                  ],
                  if (_buildDeleteSelectedPinButton() case final deleteButton?) ...[
                    const SizedBox(height: 8),
                    deleteButton,
                  ],
                ],
              ),
            ),
          ),
        Positioned(
          left: _mapEdgeInset + _mapSidebarWidth + _mapChromeGap,
          right: _mapEdgeInset + _mapSidebarWidth + _mapChromeGap,
          bottom: MediaQuery.paddingOf(context).bottom + 6,
          child: KeyedSubtree(
            key: _mapBottomBarKey,
            child: Align(
              alignment: Alignment.bottomRight,
              child: ScorePanel(
                par: _currentHoleStats?.par ?? 0,
                currentHoleScore: _currentHoleScore,
                currentHolePutts: _currentHolePutts,
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
                onPuttsChanged: _setHolePutts,
              ),
            ),
          ),
        ),
      ],
    );
  }

  double _mapTopInset(BuildContext context) {
    final media = MediaQuery.of(context);
    return (kIsWeb ? 16.0 : 8.0) + media.padding.top;
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
