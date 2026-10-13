import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:share_plus/share_plus.dart';

import '../config/app_config.dart';
import '../config/app_theme.dart';
import '../models/golf_feature.dart';
import '../services/course_import_service.dart';
import '../services/golf_data_service.dart';
import '../services/user_course_storage_service.dart';
import '../utils/geo_utils.dart';

enum _TraceMode { pan, draw, walk, edit }

enum _TraceMapStyle { street, satellite }

enum _TraceFeatureType {
  tee('tee', 'Tee'),
  fairway('fairway', 'Fairway'),
  green('green', 'Green'),
  bunker('bunker', 'Bunker');

  const _TraceFeatureType(this.value, this.label);
  final String value;
  final String label;
}

class CourseTraceScreen extends StatefulWidget {
  const CourseTraceScreen({
    super.key,
    this.existingCourseName,
    this.seedCourseName,
  });

  /// Opens a previously saved on-device traced course for editing.
  final String? existingCourseName;

  /// Prefills and auto-loads geometry from database / built-in data.
  final String? seedCourseName;

  @override
  State<CourseTraceScreen> createState() => _CourseTraceScreenState();
}

class _CourseTraceScreenState extends State<CourseTraceScreen> {
  final _mapKey = GlobalKey();
  final _mapController = MapController();
  final _courseNameController = TextEditingController();
  final _importSearchController = TextEditingController();
  final _holeCountController = TextEditingController(text: '18');
  final _parController = TextEditingController(text: '4');
  final _handicapController = TextEditingController(text: '1');
  final _storage = UserCourseStorageService();
  final _importService = CourseImportService();
  final _golfDataService = GolfDataService();

  static const _drawMinDistanceMeters = 4.0;
  static const _tileNativeMaxZoom = 19;
  static const _mapMaxZoom = 21.0;
  static const _satelliteTileUrl =
      'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}';

  List<GolfFeature> _savedFeatures = [];
  List<GolfFeature> _draftFeatures = [];
  final List<LatLng> _currentVertices = [];
  int _currentHole = 1;
  int _holeCount = 18;
  _TraceFeatureType _featureType = _TraceFeatureType.fairway;
  _TraceMode _traceMode = _TraceMode.pan;
  _TraceMapStyle _mapStyle = _TraceMapStyle.street;
  GolfFeature? _editingFeature;
  List<LatLng> _editVertices = [];
  List<LatLng> _editBaselineVertices = [];
  final List<List<LatLng>> _editUndoStack = [];
  int? _draggingEditVertexIndex;
  LatLng? _dragEditVertexCoord;
  LatLng? _userCoord;
  StreamSubscription<Position>? _walkSub;
  LatLng? _lastWalkPoint;
  LatLng? _lastDrawPoint;
  bool _isDrawingOnMap = false;
  int _activeDrawPointers = 0;
  bool _importing = false;
  String? _importSourceLabel;
  bool _saving = false;
  bool _uploading = false;
  bool _loadingExisting = true;

  void _dismissKeyboard() {
    FocusManager.instance.primaryFocus?.unfocus();
  }

  InputDecoration _traceFieldDecoration({
    required String labelText,
    String? hintText,
  }) {
    return InputDecoration(
      labelText: labelText,
      hintText: hintText,
      labelStyle: const TextStyle(color: AppTheme.textMuted),
      enabledBorder: const UnderlineInputBorder(
        borderSide: BorderSide(color: AppTheme.panelBorder),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    final initialName =
        widget.existingCourseName?.trim() ?? widget.seedCourseName?.trim();
    if (initialName != null && initialName.isNotEmpty) {
      _courseNameController.text = initialName;
      _importSearchController.text = initialName;
    }
    unawaited(_bootstrap());
  }

  @override
  void dispose() {
    _walkSub?.cancel();
    _courseNameController.dispose();
    _importSearchController.dispose();
    _holeCountController.dispose();
    _parController.dispose();
    _handicapController.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    await _ensureLocationPermission();
    await _loadExistingCourse();
    await _seedCourseIfNeeded();
    await _startUserLocation();
    if (!mounted) return;
    setState(() => _loadingExisting = false);
    _focusMap();
  }

  Future<void> _loadExistingCourse() async {
    final name = widget.existingCourseName?.trim();
    if (name == null || name.isEmpty) return;

    final all = await _storage.loadFeatures();
    _savedFeatures = all.where((f) => f.matchesCourse(name)).toList();
    _draftFeatures = List<GolfFeature>.from(_savedFeatures);

    _applyLoadedCourseMetadata(name);
  }

  Future<void> _seedCourseIfNeeded() async {
    if (_draftFeatures.isNotEmpty) return;

    final seed = (widget.seedCourseName ?? widget.existingCourseName)?.trim();
    if (seed == null || seed.isEmpty) return;

    List<GolfFeature> source = const [];
    var sourceLabel = 'Built-in';

    try {
      source = await _golfDataService.fetchRemoteFeaturesForCourse(seed);
      if (source.isNotEmpty) {
        sourceLabel = 'Database';
      }
    } catch (_) {}

    if (source.isEmpty) {
      source = await _golfDataService.fetchSourceFeaturesForCourse(seed);
      sourceLabel = 'Built-in';
    }

    if (source.isEmpty) return;

    final cloned = _golfDataService.cloneFeaturesForCourse(source, seed);
    _draftFeatures = cloned;
    _savedFeatures = const [];
    _importSourceLabel = '$seed ($sourceLabel)';
    _applyLoadedCourseMetadata(seed);
  }

  void _applyLoadedCourseMetadata(String name) {
    final holes = _draftFeatures
        .map((f) => f.holeNumber)
        .whereType<String>()
        .map(int.tryParse)
        .whereType<int>()
        .toList();
    if (holes.isNotEmpty) {
      _holeCount = holes.reduce((a, b) => a > b ? a : b);
      _currentHole = holes.first;
      _holeCountController.text = '$_holeCount';
    }

    final stats = _draftFeatures.firstWhere(
      (f) => f.holeNumber == '$_currentHole' && f.par != null,
      orElse: () => _draftFeatures.isNotEmpty
          ? _draftFeatures.first
          : GolfFeature(
              id: 0,
              featureType: null,
              holeNumber: '1',
              name: null,
              par: 4,
              handicap: 1,
              courseName: name,
              geometry: const {},
            ),
    );
    _parController.text = '${stats.par ?? 4}';
    _handicapController.text = '${stats.handicap ?? 1}';
  }

  Future<void> _ensureLocationPermission() async {
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
  }

  Future<void> _startUserLocation() async {
    try {
      final position = await Geolocator.getCurrentPosition();
      if (!mounted) return;
      setState(() {
        _userCoord = LatLng(position.latitude, position.longitude);
      });
    } catch (_) {}
  }

  void _focusMap() {
    _focusMapOnCurrentHole(fallbackToAll: true);
  }

  void _focusMapOnCurrentHole({bool fallbackToAll = false}) {
    final holeFeatures = _draftFeatures
        .where((f) => f.holeNumber == '$_currentHole')
        .toList();
    final features = holeFeatures.isNotEmpty
        ? holeFeatures
        : (fallbackToAll ? _draftFeatures : <GolfFeature>[]);

    final center = centerForFeatures(features) ??
        _userCoord ??
        LatLng(AppConfig.defaultCenter[0], AppConfig.defaultCenter[1]);
    final bounds = boundsForFeatures(features);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (bounds != null) {
        _mapController.fitCamera(
          CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(48)),
        );
      } else {
        _mapController.move(center, 16);
      }
    });
  }

  List<GolfFeature> get _allPreviewFeatures => [
        ..._draftFeatures.where((f) => f.id != _editingFeature?.id),
        if (_currentVertices.length >= 2)
          GolfFeature(
            id: 'draft',
            featureType: _featureType.value,
            holeNumber: '$_currentHole',
            name: null,
            par: int.tryParse(_parController.text.trim()),
            handicap: int.tryParse(_handicapController.text.trim()),
            courseName: _courseNameController.text.trim(),
            geometry: {
              'type': 'Polygon',
              'coordinates': [
                _ringCoordinates(_currentVertices, closed: false),
              ],
            },
          ),
      ];

  List<LatLng> get _effectiveEditVertices {
    if (_draggingEditVertexIndex == null || _dragEditVertexCoord == null) {
      return _editVertices;
    }
    return [
      for (var index = 0; index < _editVertices.length; index++)
        index == _draggingEditVertexIndex!
            ? _dragEditVertexCoord!
            : _editVertices[index],
    ];
  }

  bool get _vertexDragActive => _draggingEditVertexIndex != null;

  void _toggleMapStyle() {
    _dismissKeyboard();
    setState(() {
      _mapStyle = _mapStyle == _TraceMapStyle.street
          ? _TraceMapStyle.satellite
          : _TraceMapStyle.street;
    });
  }

  int _mapInteractionFlags() {
    if (_traceMode == _TraceMode.draw || _vertexDragActive) {
      return InteractiveFlag.pinchZoom |
          InteractiveFlag.doubleTapZoom |
          InteractiveFlag.scrollWheelZoom;
    }
    return InteractiveFlag.all & ~InteractiveFlag.rotate;
  }

  void _onMapTap(LatLng point) {
    if (_traceMode == _TraceMode.draw) {
      _maybeAddDrawPoint(point, force: true);
      return;
    }
    if (_traceMode == _TraceMode.edit) {
      _insertEditPoint(point);
    }
  }

  void _handleMapTap(LatLng point) {
    _dismissKeyboard();
    _onMapTap(point);
  }

  void _onDrawPointerDown(PointerDownEvent event) {
    if (_traceMode != _TraceMode.draw) return;

    setState(() => _activeDrawPointers++);
    if (_activeDrawPointers > 1) {
      _isDrawingOnMap = false;
      return;
    }

    _isDrawingOnMap = true;
    final point = _latLngFromScreen(event.localPosition);
    if (point == null) return;
    _lastDrawPoint = null;
    _maybeAddDrawPoint(point, force: true);
  }

  void _onDrawPointerMove(PointerMoveEvent event) {
    if (_traceMode != _TraceMode.draw) return;
    if (_activeDrawPointers > 1 || !_isDrawingOnMap) return;
    final point = _latLngFromScreen(event.localPosition);
    if (point == null) return;
    _maybeAddDrawPoint(point);
  }

  void _onDrawPointerUp(PointerUpEvent event) {
    setState(() {
      _activeDrawPointers =
          (_activeDrawPointers - 1).clamp(0, _activeDrawPointers);
    });
    _isDrawingOnMap = false;
  }

  void _onDrawPointerCancel(PointerCancelEvent event) {
    setState(() {
      _activeDrawPointers =
          (_activeDrawPointers - 1).clamp(0, _activeDrawPointers);
    });
    _isDrawingOnMap = false;
  }

  LatLng? _latLngFromScreen(Offset screen) {
    try {
      return _mapController.camera.screenOffsetToLatLng(screen);
    } catch (_) {
      return null;
    }
  }

  LatLng? _latLngFromGlobal(Offset global) {
    final renderObject =
        _mapKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderObject == null) return null;
    return _latLngFromScreen(renderObject.globalToLocal(global));
  }

  void _maybeAddDrawPoint(LatLng point, {bool force = false}) {
    if (!force && _lastDrawPoint != null) {
      final distance = const Distance().distance(_lastDrawPoint!, point);
      if (distance < _drawMinDistanceMeters) return;
    }

    setState(() {
      _currentVertices.add(point);
      _lastDrawPoint = point;
    });
  }

  void _setTraceMode(_TraceMode mode) {
    unawaited(_setTraceModeAsync(mode));
  }

  Future<void> _setTraceModeAsync(_TraceMode mode) async {
    if (_traceMode == mode) return;

    if (_traceMode == _TraceMode.edit && mode != _TraceMode.edit) {
      if (!await _confirmLeaveFeatureEdit()) return;
    }

    if (_traceMode == _TraceMode.walk) {
      _stopWalkTrace();
    }

    setState(() {
      _traceMode = mode;
      _isDrawingOnMap = false;
      _activeDrawPointers = 0;
    });

    if (mode == _TraceMode.walk) {
      _startWalkTrace();
    }
  }

  void _toggleWalkTrace() {
    if (_traceMode == _TraceMode.walk) {
      _setTraceMode(_TraceMode.pan);
      return;
    }
    _setTraceMode(_TraceMode.walk);
  }

  void _startWalkTrace() {
    _walkSub?.cancel();
    _lastWalkPoint = _userCoord;
    const settings = LocationSettings(
      accuracy: LocationAccuracy.best,
      distanceFilter: 2,
    );
    _walkSub = Geolocator.getPositionStream(locationSettings: settings).listen(
      (position) {
        final point = LatLng(position.latitude, position.longitude);
        setState(() {
          _userCoord = point;
          if (_lastWalkPoint == null ||
              const Distance().distance(_lastWalkPoint!, point) >= 2) {
            _currentVertices.add(point);
            _lastWalkPoint = point;
          }
        });
      },
    );
  }

  void _stopWalkTrace() {
    _walkSub?.cancel();
    _walkSub = null;
    _lastWalkPoint = null;
  }

  void _undoVertex() {
    if (_currentVertices.isEmpty) return;
    setState(() {
      _currentVertices.removeLast();
      _lastDrawPoint =
          _currentVertices.isEmpty ? null : _currentVertices.last;
    });
  }

  void _clearVertices() {
    setState(() {
      _currentVertices.clear();
      _lastDrawPoint = null;
    });
  }

  List<LatLng> _cloneVertexList(List<LatLng> vertices) {
    return vertices.map((point) => LatLng(point.latitude, point.longitude)).toList();
  }

  bool get _hasUnsavedEditChanges {
    if (_editingFeature == null) return false;
    if (_editVertices.length != _editBaselineVertices.length) return true;
    for (var index = 0; index < _editVertices.length; index++) {
      if (!latLngPointsEqual(_editVertices[index], _editBaselineVertices[index])) {
        return true;
      }
    }
    return false;
  }

  void _pushEditUndoState() {
    _editUndoStack.add(_cloneVertexList(_editVertices));
    if (_editUndoStack.length > 40) {
      _editUndoStack.removeAt(0);
    }
  }

  void _clearFeatureEditState({bool leavePanMode = true}) {
    _editingFeature = null;
    _editVertices.clear();
    _editBaselineVertices.clear();
    _editUndoStack.clear();
    _draggingEditVertexIndex = null;
    _dragEditVertexCoord = null;
    if (leavePanMode && _traceMode == _TraceMode.edit) {
      _traceMode = _TraceMode.pan;
    }
  }

  Future<bool> _confirmLeaveFeatureEdit() async {
    if (_editingFeature == null) return true;
    if (!_hasUnsavedEditChanges) {
      setState(() => _clearFeatureEditState());
      return true;
    }

    final label = _editingFeature!.featureType ?? 'feature';
    final action = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A22),
        title: Text('Unsaved $label changes'),
        content: const Text(
          'Save your edits with Save feature, or discard them to continue.',
          style: TextStyle(color: AppTheme.textMuted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 'cancel'),
            child: const Text('Keep editing'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'discard'),
            child: const Text('Discard'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.accentGreen,
              foregroundColor: const Color(0xFF0F172A),
            ),
            onPressed: () => Navigator.pop(context, 'save'),
            child: const Text('Save feature'),
          ),
        ],
      ),
    );

    if (!mounted) return false;
    switch (action) {
      case 'save':
        if (_editVertices.length < 3) {
          _showSnack('Need at least 3 points to save.');
          return false;
        }
        _saveFeatureEdit();
        return true;
      case 'discard':
        setState(() => _clearFeatureEditState());
        return true;
      default:
        return false;
    }
  }

  void _startEditingFeature(GolfFeature feature) {
    unawaited(_startEditingFeatureAsync(feature));
  }

  Future<void> _startEditingFeatureAsync(GolfFeature feature) async {
    if (_editingFeature?.id == feature.id && _traceMode == _TraceMode.edit) {
      return;
    }

    if (_traceMode == _TraceMode.edit) {
      if (!await _confirmLeaveFeatureEdit()) return;
    }
    if (_traceMode == _TraceMode.walk) {
      _stopWalkTrace();
    }

    final vertices = editableVerticesFromGeometry(feature.geometry);
    if (vertices.length < 3) {
      _showSnack('This feature cannot be edited.');
      return;
    }

    setState(() {
      _editingFeature = feature;
      _editVertices = _cloneVertexList(vertices);
      _editBaselineVertices = _cloneVertexList(vertices);
      _editUndoStack.clear();
      _traceMode = _TraceMode.edit;
      _draggingEditVertexIndex = null;
      _dragEditVertexCoord = null;
      _currentVertices.clear();
      _lastDrawPoint = null;
      _isDrawingOnMap = false;
      _activeDrawPointers = 0;
    });
  }

  void _saveFeatureEdit() {
    if (_editingFeature == null) return;
    if (_editVertices.length < 3) {
      _showSnack('Need at least 3 points to save.');
      return;
    }

    final original = _editingFeature!;
    final updated = GolfFeature(
      id: original.id,
      featureType: original.featureType,
      holeNumber: original.holeNumber,
      name: original.name,
      par: original.par,
      handicap: original.handicap,
      courseName: original.courseName,
      geometry: polygonGeometryFromVertices(_editVertices),
    );
    final index = _draftFeatures.indexWhere((f) => f.id == original.id);
    if (index >= 0) {
      _draftFeatures[index] = updated;
    }

    setState(() => _clearFeatureEditState());
    _showSnack('Saved ${original.featureType ?? 'feature'}.');
  }

  void _cancelFeatureEdit() {
    if (_editingFeature == null) return;
    if (!_hasUnsavedEditChanges) {
      setState(() => _clearFeatureEditState());
      return;
    }

    setState(() {
      _editVertices = _cloneVertexList(_editBaselineVertices);
      _clearFeatureEditState();
    });
    _showSnack('Discarded changes.');
  }

  void _insertEditPoint(LatLng point) {
    for (final vertex in _editVertices) {
      if (distanceMeters(vertex, point) < _drawMinDistanceMeters) {
        return;
      }
    }

    setState(() {
      _pushEditUndoState();
      if (_editVertices.isEmpty) {
        _editVertices.add(point);
      } else {
        final insertAt = insertIndexOnPolygonRing(_editVertices, point);
        _editVertices.insert(insertAt, point);
      }
    });
  }

  void _deleteEditVertex(int index) {
    if (_editVertices.length <= 3) {
      _showSnack('Need at least 3 points.');
      return;
    }
    setState(() {
      _pushEditUndoState();
      _editVertices.removeAt(index);
    });
  }

  void _beginEditVertexDrag(int index) {
    if (index < 0 || index >= _editVertices.length) return;
    _pushEditUndoState();
    final anchor = _editVertices[index];
    setState(() {
      _draggingEditVertexIndex = index;
      _dragEditVertexCoord = anchor;
    });
  }

  void _updateEditVertexDragFromGlobal(Offset globalPosition) {
    if (_draggingEditVertexIndex == null) return;
    final updated = _latLngFromGlobal(globalPosition);
    if (updated == null) return;
    setState(() => _dragEditVertexCoord = updated);
  }

  void _endEditVertexDrag(int index) {
    if (_draggingEditVertexIndex != index) return;
    final finalCoord = _dragEditVertexCoord ?? _editVertices[index];
    setState(() {
      _editVertices[index] = finalCoord;
      _draggingEditVertexIndex = null;
      _dragEditVertexCoord = null;
    });
  }

  void _undoEditChange() {
    if (_editUndoStack.isEmpty) {
      _showSnack('Nothing to undo.');
      return;
    }
    setState(() {
      _editVertices = _cloneVertexList(_editUndoStack.removeLast());
      _draggingEditVertexIndex = null;
      _dragEditVertexCoord = null;
    });
  }

  List<List<double>> _ringCoordinates(
    List<LatLng> points, {
    required bool closed,
  }) {
    final ring = points
        .map((point) => [point.longitude, point.latitude])
        .toList();
    if (closed && ring.isNotEmpty) {
      final first = ring.first;
      final last = ring.last;
      if (first[0] != last[0] || first[1] != last[1]) {
        ring.add([first[0], first[1]]);
      }
    }
    return ring;
  }

  List<LatLng> _teeSquare(LatLng center) {
    const offset = 0.00004;
    return [
      LatLng(center.latitude - offset, center.longitude - offset),
      LatLng(center.latitude - offset, center.longitude + offset),
      LatLng(center.latitude + offset, center.longitude + offset),
      LatLng(center.latitude + offset, center.longitude - offset),
    ];
  }

  Future<void> _commitCurrentFeature() async {
    final courseName = _courseNameController.text.trim();
    if (courseName.isEmpty) {
      _showSnack('Enter a course name first.');
      return;
    }

    List<LatLng> vertices = List<LatLng>.from(_currentVertices);
    if (_featureType == _TraceFeatureType.tee) {
      if (vertices.isEmpty && _userCoord != null) {
        vertices = [_userCoord!];
      }
      if (vertices.length == 1) {
        vertices = _teeSquare(vertices.first);
      }
    }

    if (vertices.length < 3) {
      _showSnack('Add at least 3 points (or draw once for tee).');
      return;
    }

    final par = int.tryParse(_parController.text.trim());
    final handicap = int.tryParse(_handicapController.text.trim());
    final id =
        'user-${DateTime.now().millisecondsSinceEpoch}-${_draftFeatures.length}';

    final feature = GolfFeature(
      id: id,
      featureType: _featureType.value,
      holeNumber: '$_currentHole',
      name: null,
      par: _featureType == _TraceFeatureType.green ? par : null,
      handicap: _featureType == _TraceFeatureType.green ? handicap : null,
      courseName: courseName,
      geometry: {
        'type': 'Polygon',
        'coordinates': [_ringCoordinates(vertices, closed: true)],
      },
    );

    setState(() {
      _draftFeatures.removeWhere(
        (f) =>
            f.holeNumber == '$_currentHole' &&
            f.featureType == _featureType.value,
      );
      _draftFeatures.add(feature);
      _currentVertices.clear();
      _lastDrawPoint = null;
    });
    _showSnack('Saved ${_featureType.label} for hole $_currentHole.');
  }

  void _nextHole() {
    unawaited(_changeHole(_currentHole + 1));
  }

  void _previousHole() {
    unawaited(_changeHole(_currentHole - 1));
  }

  Future<void> _changeHole(int targetHole) async {
    if (_traceMode == _TraceMode.edit) {
      if (!await _confirmLeaveFeatureEdit()) return;
    }

    final parsed = int.tryParse(_holeCountController.text.trim());
    if (parsed != null && parsed > 0) {
      _holeCount = parsed;
    }
    if (targetHole < 1) return;
    if (targetHole > _holeCount) {
      _showSnack('Already on last hole.');
      return;
    }

    setState(() {
      _currentHole = targetHole;
      _currentVertices.clear();
      _lastDrawPoint = null;
      _syncParFieldsForCurrentHole();
    });
    _focusMapOnCurrentHole(fallbackToAll: true);
  }

  void _syncParFieldsForCurrentHole() {
    final green = _draftFeatures.firstWhere(
      (f) => f.holeNumber == '$_currentHole' && f.par != null,
      orElse: () => _draftFeatures.firstWhere(
        (f) => f.holeNumber == '$_currentHole',
        orElse: () => GolfFeature(
          id: 0,
          featureType: null,
          holeNumber: '$_currentHole',
          name: null,
          par: 4,
          handicap: 1,
          courseName: _courseNameController.text.trim(),
          geometry: const {},
        ),
      ),
    );
    _parController.text = '${green.par ?? 4}';
    _handicapController.text = '${green.handicap ?? 1}';
  }

  List<GolfFeature> get _holeDraftFeatures => _draftFeatures
      .where((f) => f.holeNumber == '$_currentHole')
      .toList();

  void _deleteDraftFeature(GolfFeature feature) {
    if (_editingFeature?.id == feature.id) {
      setState(() => _clearFeatureEditState());
    }
    setState(() => _draftFeatures.remove(feature));
  }

  int get _resolvedHoleCount {
    final parsed = int.tryParse(_holeCountController.text.trim());
    if (parsed != null && parsed > 0) return parsed;
    return _holeCount;
  }

  String _newFeatureId() =>
      'user-${DateTime.now().millisecondsSinceEpoch}-${_draftFeatures.length}';

  GolfFeature _cloneFeature(
    GolfFeature source, {
    required String holeNumber,
    required String id,
  }) {
    return GolfFeature(
      id: id,
      featureType: source.featureType,
      holeNumber: holeNumber,
      name: source.name,
      par: source.par,
      handicap: source.handicap,
      courseName: source.courseName,
      geometry: Map<String, dynamic>.from(source.geometry),
    );
  }

  void _removeConflictingFeaturesOnHole(String holeNumber, String? featureType) {
    if (featureType == 'bunker') return;
    _draftFeatures.removeWhere(
      (feature) =>
          feature.holeNumber == holeNumber && feature.featureType == featureType,
    );
  }

  Future<void> _moveFeatureToHole(GolfFeature feature, int targetHole) async {
    if (_editingFeature?.id == feature.id && _hasUnsavedEditChanges) {
      if (!await _confirmLeaveFeatureEdit()) return;
    } else if (_editingFeature?.id == feature.id) {
      setState(() => _clearFeatureEditState());
    }

    final target = '$targetHole';
    final sourceHole = feature.holeNumber;
    if (sourceHole == target) {
      _showSnack('Feature is already on hole $targetHole.');
      return;
    }

    _removeConflictingFeaturesOnHole(target, feature.featureType);

    final index = _draftFeatures.indexWhere((f) => f.id == feature.id);
    if (index < 0) return;
    final current = _draftFeatures[index];

    setState(() {
      _draftFeatures[index] = _cloneFeature(
        current,
        holeNumber: target,
        id: current.id,
      );
      _currentHole = targetHole;
      _syncParFieldsForCurrentHole();
    });
    _focusMapOnCurrentHole(fallbackToAll: true);
    _showSnack(
      'Moved ${feature.featureType ?? 'feature'} from hole $sourceHole to hole $targetHole.',
    );
  }

  Future<void> _copyFeatureToHole(GolfFeature feature, int targetHole) async {
    if (_editingFeature?.id == feature.id) {
      if (_hasUnsavedEditChanges) {
        if (!await _confirmLeaveFeatureEdit()) return;
      } else {
        setState(() => _clearFeatureEditState());
      }
    }

    final target = '$targetHole';
    if (feature.holeNumber == target) {
      _showSnack('Feature is already on hole $targetHole.');
      return;
    }

    final index = _draftFeatures.indexWhere((f) => f.id == feature.id);
    final current = index >= 0 ? _draftFeatures[index] : feature;

    _removeConflictingFeaturesOnHole(target, current.featureType);

    setState(() {
      _draftFeatures.add(
        _cloneFeature(
          current,
          holeNumber: target,
          id: _newFeatureId(),
        ),
      );
      _currentHole = targetHole;
      _syncParFieldsForCurrentHole();
    });
    _focusMapOnCurrentHole(fallbackToAll: true);
    _showSnack(
      'Copied ${current.featureType ?? 'feature'} to hole $targetHole.',
    );
  }

  Future<void> _promptTransferFeature(
    GolfFeature feature, {
    required bool move,
  }) async {
    final holeCount = _resolvedHoleCount;
    final controller = TextEditingController(
      text: feature.holeNumber == '$_currentHole'
          ? ''
          : feature.holeNumber,
    );
    final label = feature.featureType ?? 'feature';

    final targetHole = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A22),
        title: Text(move ? 'Move $label' : 'Copy $label'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              move
                  ? 'Hole ${feature.holeNumber} → remove from this hole and place on:'
                  : 'Hole ${feature.holeNumber} → keep here and also place on:',
              style: const TextStyle(color: AppTheme.textMuted, fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.number,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'Target hole (1-$holeCount)',
                labelStyle: const TextStyle(color: AppTheme.textMuted),
              ),
              onSubmitted: (value) {
                final hole = int.tryParse(value.trim());
                if (hole != null && hole >= 1 && hole <= holeCount) {
                  Navigator.pop(context, hole);
                }
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.accentGreen,
              foregroundColor: const Color(0xFF0F172A),
            ),
            onPressed: () {
              final hole = int.tryParse(controller.text.trim());
              if (hole == null || hole < 1 || hole > holeCount) return;
              Navigator.pop(context, hole);
            },
            child: Text(move ? 'Move' : 'Copy'),
          ),
        ],
      ),
    );

    controller.dispose();
    if (targetHole == null || !mounted) return;

    if (move) {
      _moveFeatureToHole(feature, targetHole);
    } else {
      _copyFeatureToHole(feature, targetHole);
    }
  }

  Future<void> _findAndLoadCourse() async {
    if (_importing) return;
    _dismissKeyboard();

    final searchQuery = _importSearchQuery.trim();
    if (searchQuery.isEmpty) {
      _showSnack('Enter a golf course name to search.');
      return;
    }

    if (_draftFeatures.isNotEmpty) {
      final replace = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A22),
          title: const Text('Replace current draft?'),
          content: const Text(
            'Loading course data will replace the features you have traced so far.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Replace'),
            ),
          ],
        ),
      );
      if (replace != true || !mounted) return;
    }

    setState(() => _importing = true);
    try {
      final matches = await _importService.searchCourses(
        searchQuery,
        latitude: _userCoord?.latitude,
        longitude: _userCoord?.longitude,
      );

      if (!mounted) return;
      if (matches.isEmpty) {
        _showSnack('No courses found for "$searchQuery". Try a different name.');
        return;
      }

      final selected = matches.length == 1
          ? matches.first
          : await showDialog<CourseImportMatch>(
              context: context,
              builder: (context) => _CourseMatchDialog(
                query: searchQuery,
                matches: matches,
              ),
            );

      if (selected == null || !mounted) return;

      final targetName = _targetCourseName(selected.name);
      final result = await _importService.loadCourse(selected, targetName);
      if (!mounted) return;

      if (result.features.isEmpty) {
        _showSnack('No hole geometry found for ${selected.name}.');
        return;
      }

      setState(() {
        _draftFeatures = result.features;
        _currentVertices.clear();
        _lastDrawPoint = null;
        _importSourceLabel = result.sourceName;
        _currentHole = result.holeNumbers.isNotEmpty ? result.holeNumbers.first : 1;
        if (result.holeNumbers.isNotEmpty) {
          _holeCount = result.holeNumbers.last;
          _holeCountController.text = '$_holeCount';
        }
        _syncParFieldsForCurrentHole();
      });

      if (widget.existingCourseName == null &&
          _courseNameController.text.trim().isEmpty) {
        _courseNameController.text = targetName;
      }

      _focusMapOnCurrentHole(fallbackToAll: true);
      final holeLabel = result.holeNumbers.isEmpty
          ? 'holes'
          : '${result.holeNumbers.length} holes';
      _showSnack(
        'Loaded ${result.features.length} features across $holeLabel '
        'from ${selected.sourceLabel}. Edit, then Save / Upload.',
      );
    } catch (error) {
      _showSnack('Could not load course: $error');
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  String get _importSearchQuery =>
      widget.existingCourseName == null
          ? _courseNameController.text
          : _importSearchController.text;

  String _targetCourseName(String fallbackName) {
    if (widget.existingCourseName != null) {
      return widget.existingCourseName!.trim();
    }
    final entered = _courseNameController.text.trim();
    return entered.isEmpty ? fallbackName : entered;
  }

  Future<bool> _confirmOverwriteIfNeeded({
    required String courseName,
    required String actionLabel,
    required CourseExistenceResult existence,
    required bool checkLocal,
    required bool checkRemote,
  }) async {
    final conflicts = <String>[];
    if (checkLocal && existence.existsLocally) {
      conflicts.add(
        'on this device (${existence.localFeatureCount} saved features)',
      );
    }
    if (checkRemote && existence.existsRemotely) {
      conflicts.add(
        'in the shared database (${existence.remoteFeatureCount} features)',
      );
    }

    if (conflicts.isEmpty) return true;

    final locationText = conflicts.length == 1
        ? conflicts.first
        : '${conflicts.sublist(0, conflicts.length - 1).join(', ')} and ${conflicts.last}';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A22),
        title: Text('Overwrite "$courseName"?'),
        content: Text(
          'A course with this name already exists $locationText. '
          '$actionLabel will replace that data with your '
          '${_draftFeatures.length} traced features.',
          style: const TextStyle(color: AppTheme.textMuted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.accentGreen,
              foregroundColor: const Color(0xFF0F172A),
            ),
            onPressed: () => Navigator.pop(context, true),
            child: Text(actionLabel),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  Future<void> _uploadCourseToDatabase() async {
    final courseName = _courseNameController.text.trim();
    if (courseName.isEmpty) {
      _showSnack('Course name is required.');
      return;
    }
    if (_draftFeatures.isEmpty) {
      _showSnack('Trace at least one feature before uploading.');
      return;
    }

    final existence =
        await _golfDataService.checkCourseExistence(courseName);
    if (!mounted) return;

    final confirmed = await _confirmOverwriteIfNeeded(
      courseName: courseName,
      actionLabel: 'Upload',
      existence: existence,
      checkLocal: false,
      checkRemote: true,
    );
    if (!confirmed || !mounted) return;

    setState(() => _uploading = true);
    try {
      final rows = _draftFeatures.map(_featureToRow).toList();
      final count = await _golfDataService.uploadCourseFeatures(
        courseName,
        rows,
      );
      if (!mounted) return;
      _showSnack('Uploaded $count features for $courseName.');
    } catch (error) {
      if (!mounted) return;
      _showSnack('Upload failed: $error');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _saveCourse() async {
    final courseName = _courseNameController.text.trim();
    if (courseName.isEmpty) {
      _showSnack('Course name is required.');
      return;
    }
    if (_draftFeatures.isEmpty) {
      _showSnack('Trace at least one feature before saving.');
      return;
    }

    final editingExisting = widget.existingCourseName?.trim() == courseName;
    if (!editingExisting) {
      final existence =
          await _golfDataService.checkCourseExistence(courseName);
      if (!mounted) return;

      final confirmed = await _confirmOverwriteIfNeeded(
        courseName: courseName,
        actionLabel: 'Save',
        existence: existence,
        checkLocal: true,
        checkRemote: false,
      );
      if (!confirmed || !mounted) return;
    }

    setState(() => _saving = true);
    try {
      final rows = _draftFeatures.map(_featureToRow).toList();
      await _storage.saveCourseFeatures(courseName, rows);
      if (!mounted) return;
      _showSnack('Saved $courseName.');
      Navigator.of(context).pop(true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Map<String, dynamic> _featureToRow(GolfFeature feature) {
    return {
      'id': feature.id,
      'feature_type': feature.featureType,
      'hole_number': feature.holeNumber,
      'name': feature.name,
      'geom': feature.geometry,
      'course_name': feature.courseName,
      if (feature.par != null) 'par': feature.par,
      if (feature.handicap != null) 'handicap': feature.handicap,
    };
  }

  Future<void> _exportGeoJson() async {
    final courseName = _courseNameController.text.trim();
    if (courseName.isEmpty || _draftFeatures.isEmpty) {
      _showSnack('Nothing to export yet.');
      return;
    }

    final features = _draftFeatures
        .where((f) => f.matchesCourse(courseName))
        .map((f) => f.toGeoJsonFeature())
        .toList();

    final payload = jsonEncode({
      'type': 'FeatureCollection',
      'features': features,
    });

    await SharePlus.instance.share(
      ShareParams(text: payload, subject: '$courseName.geojson'),
    );
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    final courseName = _courseNameController.text.trim();
    final previewFeatures = _allPreviewFeatures
        .where((f) => courseName.isEmpty || f.matchesCourse(courseName))
        .toList();

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF121218),
        foregroundColor: Colors.white,
        title: Text(
          widget.existingCourseName == null ? 'Trace course' : 'Edit course',
        ),
        actions: [
          IconButton(
            tooltip: 'Find and load course',
            onPressed: _importing ? null : _findAndLoadCourse,
            icon: _importing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.cloud_download_outlined),
          ),
          IconButton(
            tooltip: 'Export GeoJSON',
            onPressed: _exportGeoJson,
            icon: const Icon(Icons.ios_share_rounded),
          ),
          IconButton(
            tooltip: 'Upload to database',
            onPressed: _uploading ? null : _uploadCourseToDatabase,
            icon: _uploading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.cloud_upload_outlined),
          ),
          TextButton(
            onPressed: _saving ? null : _saveCourse,
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text(
                    'Save',
                    style: TextStyle(
                      color: AppTheme.accentGreen,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
          ),
        ],
      ),
      body: _loadingExisting
          ? const Center(
              child: CircularProgressIndicator(color: AppTheme.accentGreen),
            )
          : Stack(
              children: [
                Positioned.fill(child: _buildMap(previewFeatures)),
                DraggableScrollableSheet(
                  initialChildSize: 0.26,
                  minChildSize: 0.16,
                  maxChildSize: 0.55,
                  snap: true,
                  snapSizes: const [0.26, 0.55],
                  builder: (context, scrollController) {
                    return _buildControls(scrollController);
                  },
                ),
              ],
            ),
    );
  }

  Widget _buildMap(List<GolfFeature> features) {
    final center = centerForFeatures(features) ??
        _userCoord ??
        LatLng(AppConfig.defaultCenter[0], AppConfig.defaultCenter[1]);

    final polygons = <Polygon>[];
    for (final feature in features) {
      if (_editingFeature?.id == feature.id) continue;
      final rings = ringsFromGeometry(feature.geometry);
      if (rings.isEmpty) continue;
      final isDraft = feature.id == 'draft';
      final isCurrentHole = feature.holeNumber == '$_currentHole';
      final type = feature.featureType ?? '';
      Color fill;
      Color border;
      switch (type) {
        case 'green':
          fill = const Color(0xAA2ECC71);
          border = const Color(0xFF27AE60);
        case 'fairway':
          fill = const Color(0xAA3D8B40);
          border = const Color(0xFF2E7D32);
        case 'bunker':
          fill = const Color(0xAAF5DEB3);
          border = const Color(0xFFD4A574);
        case 'tee':
          fill = AppTheme.teeFill;
          border = AppTheme.teeBorder;
        default:
          fill = const Color(0x884ADE80);
          border = AppTheme.accentGreen;
      }
      if (isDraft) {
        fill = fill.withValues(alpha: 0.35);
        border = Colors.white;
      } else if (!isCurrentHole) {
        fill = fill.withValues(alpha: 0.18);
        border = border.withValues(alpha: 0.35);
      }
      for (final ring in rings) {
        polygons.add(
          Polygon(
            points: ring,
            color: fill,
            borderColor: border,
            borderStrokeWidth: isDraft ? 2.5 : 1.5,
          ),
        );
      }
    }

    if (_traceMode == _TraceMode.edit && _effectiveEditVertices.length >= 3) {
      polygons.add(
        Polygon(
          points: _effectiveEditVertices,
          color: const Color(0x664ADE80),
          borderColor: Colors.white,
          borderStrokeWidth: 3,
        ),
      );
    }

    final markers = _currentVertices
        .map(
          (point) => Marker(
            point: point,
            width: 14,
            height: 14,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                border: Border.all(color: AppTheme.accentGreen, width: 2),
              ),
            ),
          ),
        )
        .toList();

    if (_traceMode == _TraceMode.edit) {
      final vertices = _effectiveEditVertices;
      for (var index = 0; index < vertices.length; index++) {
        final point = vertices[index];
        final vertexIndex = index;
        final isDragging = _draggingEditVertexIndex == vertexIndex;
        markers.add(
          Marker(
            point: point,
            width: 36,
            height: 36,
            alignment: Alignment.center,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _deleteEditVertex(vertexIndex),
              onLongPressStart: (_) => _beginEditVertexDrag(vertexIndex),
              onLongPressMoveUpdate: (details) =>
                  _updateEditVertexDragFromGlobal(details.globalPosition),
              onLongPressEnd: (_) => _endEditVertexDrag(vertexIndex),
              onLongPressCancel: () => _endEditVertexDrag(vertexIndex),
              child: Container(
                width: isDragging ? 22 : 18,
                height: isDragging ? 22 : 18,
                decoration: BoxDecoration(
                  color: isDragging ? Colors.white : AppTheme.accentGreen,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isDragging ? AppTheme.accentGreen : Colors.white,
                    width: 2,
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x88000000),
                      blurRadius: 4,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }
    }

    if (_userCoord != null) {
      markers.add(
        Marker(
          point: _userCoord!,
          width: 18,
          height: 18,
          child: Container(
            decoration: BoxDecoration(
              color: AppTheme.measureBlue,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
            ),
          ),
        ),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        FlutterMap(
          key: _mapKey,
          mapController: _mapController,
          options: MapOptions(
            initialCenter: center,
            initialZoom: 16,
            minZoom: 3,
            maxZoom: _mapMaxZoom,
            backgroundColor: const Color(0xFFE8E8E8),
            onTap: (_, point) => _handleMapTap(point),
            interactionOptions: InteractionOptions(
              flags: _mapInteractionFlags(),
            ),
          ),
          children: [
            TileLayer(
              urlTemplate: _mapStyle == _TraceMapStyle.satellite
                  ? _satelliteTileUrl
                  : AppConfig.openStreetMapTileUrl,
              userAgentPackageName: 'com.golfmapapp.golfMapFlutter',
              maxNativeZoom: _tileNativeMaxZoom,
              maxZoom: _mapMaxZoom,
            ),
            PolygonLayer(polygons: polygons),
            if (_currentVertices.length >= 2)
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: _currentVertices,
                    color: Colors.white,
                    strokeWidth: 2.5,
                  ),
                ],
              ),
            if (_traceMode == _TraceMode.edit &&
                _effectiveEditVertices.length >= 2)
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: _effectiveEditVertices,
                    color: Colors.white,
                    strokeWidth: 2.5,
                  ),
                ],
              ),
            MarkerLayer(markers: markers),
            if (_mapStyle == _TraceMapStyle.street)
              RichAttributionWidget(
                attributions: [
                  TextSourceAttribution(
                    'OpenStreetMap contributors',
                    onTap: () {},
                  ),
                ],
              ),
            if (_mapStyle == _TraceMapStyle.satellite)
              RichAttributionWidget(
                attributions: [
                  TextSourceAttribution(
                    'Esri World Imagery',
                    onTap: () {},
                  ),
                ],
              ),
          ],
        ),
        Positioned(
          top: 12,
          right: 12,
          child: Material(
            color: const Color(0xCC121218),
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: _toggleMapStyle,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _mapStyle == _TraceMapStyle.satellite
                          ? Icons.map_outlined
                          : Icons.satellite_alt_outlined,
                      color: Colors.white,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _mapStyle == _TraceMapStyle.satellite
                          ? 'Street'
                          : 'Satellite',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (_traceMode == _TraceMode.draw)
          Positioned.fill(
            child: IgnorePointer(
              ignoring: _activeDrawPointers >= 2,
              child: Listener(
                behavior: HitTestBehavior.translucent,
                onPointerDown: _onDrawPointerDown,
                onPointerMove: _onDrawPointerMove,
                onPointerUp: _onDrawPointerUp,
                onPointerCancel: _onDrawPointerCancel,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildControls(ScrollController scrollController) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: Color(0xFF121218),
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        border: Border(top: BorderSide(color: AppTheme.panelBorder)),
        boxShadow: [
          BoxShadow(
            color: Color(0xAA000000),
            blurRadius: 16,
            offset: Offset(0, -4),
          ),
        ],
      ),
      child: ListView(
        controller: scrollController,
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: EdgeInsets.fromLTRB(
          16,
          8,
          16,
          12 + MediaQuery.paddingOf(context).bottom,
        ),
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: AppTheme.panelBorder,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
            if (widget.existingCourseName == null) ...[
              const Text(
                'New course: enter a name below (required to save). '
                'Find & load can pull from the shared database, built-in data, '
                'or OpenStreetMap — then edit hole by hole.',
                style: TextStyle(color: AppTheme.textMuted, fontSize: 12),
              ),
              const SizedBox(height: 12),
            ],
            if (widget.existingCourseName != null) ...[
              TextField(
                controller: _courseNameController,
                enabled: false,
                style: const TextStyle(color: Colors.white),
                decoration: _traceFieldDecoration(labelText: 'Saved course name'),
              ),
              const SizedBox(height: 8),
            ],
            if (widget.existingCourseName == null)
              TextField(
                controller: _courseNameController,
                style: const TextStyle(color: Colors.white),
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.done,
                onTapOutside: (_) => _dismissKeyboard(),
                onSubmitted: (_) => _dismissKeyboard(),
                decoration: _traceFieldDecoration(
                  labelText: 'Course name (required)',
                  hintText: 'e.g. My Practice Course',
                ),
              ),
            if (widget.existingCourseName == null) const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (widget.existingCourseName != null)
                  Expanded(
                    child: TextField(
                      controller: _importSearchController,
                      style: const TextStyle(color: Colors.white),
                      textInputAction: TextInputAction.search,
                      onTapOutside: (_) => _dismissKeyboard(),
                      onSubmitted: (_) {
                        _dismissKeyboard();
                        unawaited(_findAndLoadCourse());
                      },
                      decoration: _traceFieldDecoration(
                        labelText: 'Find course data',
                        hintText: 'e.g. Brackenridge Park Golf Course',
                      ),
                    ),
                  ),
                if (widget.existingCourseName != null) const SizedBox(width: 8),
                if (widget.existingCourseName != null)
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.accentGreen,
                      foregroundColor: const Color(0xFF0F172A),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 14,
                      ),
                    ),
                    onPressed: _importing ? null : () {
                      _dismissKeyboard();
                      unawaited(_findAndLoadCourse());
                    },
                    child: _importing
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Find & load'),
                  ),
              ],
            ),
            if (widget.existingCourseName == null)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _importing
                      ? null
                      : () {
                          _dismissKeyboard();
                          unawaited(_findAndLoadCourse());
                        },
                  icon: _importing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.cloud_download_outlined),
                  label: Text(
                    _importing
                        ? 'Searching…'
                        : 'Find & load database / map data',
                  ),
                ),
              ),
            if (_importSourceLabel != null) ...[
              const SizedBox(height: 8),
              Text(
                'Loaded "$_importSourceLabel". Edit holes, then Save locally '
                'and/or Upload to database when ready.',
                style: const TextStyle(color: AppTheme.textMuted, fontSize: 12),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _holeCountController,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(color: Colors.white),
                    onTapOutside: (_) => _dismissKeyboard(),
                    decoration: const InputDecoration(
                      labelText: 'Holes',
                      labelStyle: TextStyle(color: AppTheme.textMuted),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _parController,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(color: Colors.white),
                    onTapOutside: (_) => _dismissKeyboard(),
                    decoration: const InputDecoration(
                      labelText: 'Par (green)',
                      labelStyle: TextStyle(color: AppTheme.textMuted),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _handicapController,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(color: Colors.white),
                    onTapOutside: (_) => _dismissKeyboard(),
                    decoration: const InputDecoration(
                      labelText: 'Hcp',
                      labelStyle: TextStyle(color: AppTheme.textMuted),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                IconButton(
                  onPressed: _previousHole,
                  icon: const Icon(Icons.chevron_left, color: Colors.white),
                ),
                Expanded(
                  child: Text(
                    'Hole $_currentHole · ${_holeDraftFeatures.length} loaded',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: _nextHole,
                  icon: const Icon(Icons.chevron_right, color: Colors.white),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _TraceFeatureType.values.map((type) {
                final selected = _featureType == type;
                return ChoiceChip(
                  label: Text(type.label),
                  selected: selected,
                  onSelected: (_) => setState(() => _featureType = type),
                  selectedColor: AppTheme.accentGreen.withValues(alpha: 0.35),
                  labelStyle: TextStyle(
                    color: selected ? Colors.white : AppTheme.textMuted,
                    fontWeight: FontWeight.w700,
                  ),
                );
              }).toList(),
            ),
            if (_holeDraftFeatures.isNotEmpty) ...[
              const SizedBox(height: 8),
              const Text(
                'Tap a feature to edit its shape.',
                style: TextStyle(color: AppTheme.textMuted, fontSize: 12),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _holeDraftFeatures.map((feature) {
                  final label = feature.featureType ?? 'feature';
                  final isEditing = _editingFeature?.id == feature.id;
                  return InputChip(
                    label: Text(label),
                    selected: isEditing,
                    onPressed: () => _startEditingFeature(feature),
                    deleteIcon: const Icon(Icons.close, size: 16),
                    onDeleted: () => _deleteDraftFeature(feature),
                    selectedColor: AppTheme.accentGreen.withValues(alpha: 0.35),
                    backgroundColor: AppTheme.panelBg,
                    labelStyle: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  );
                }).toList(),
              ),
            ],
            if (_traceMode == _TraceMode.edit && _editingFeature != null) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => unawaited(
                        _promptTransferFeature(_editingFeature!, move: true),
                      ),
                      child: const Text('Move to hole'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => unawaited(
                        _promptTransferFeature(_editingFeature!, move: false),
                      ),
                      child: const Text('Copy to hole'),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _setTraceMode(_TraceMode.pan),
                    icon: Icon(
                      Icons.pan_tool_alt_outlined,
                      color: _traceMode == _TraceMode.pan
                          ? AppTheme.accentGreen
                          : AppTheme.textMuted,
                    ),
                    label: Text(
                      'Pan',
                      style: TextStyle(
                        color: _traceMode == _TraceMode.pan
                            ? AppTheme.accentGreen
                            : AppTheme.textMuted,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _setTraceMode(_TraceMode.draw),
                    icon: Icon(
                      Icons.gesture_rounded,
                      color: _traceMode == _TraceMode.draw
                          ? AppTheme.accentGreen
                          : AppTheme.textMuted,
                    ),
                    label: Text(
                      'Draw',
                      style: TextStyle(
                        color: _traceMode == _TraceMode.draw
                            ? AppTheme.accentGreen
                            : AppTheme.textMuted,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _toggleWalkTrace,
                    icon: Icon(
                      Icons.directions_walk_rounded,
                      color: _traceMode == _TraceMode.walk
                          ? AppTheme.accentGreen
                          : AppTheme.textMuted,
                    ),
                    label: Text(
                      _traceMode == _TraceMode.walk ? 'Walking…' : 'Walk',
                      style: TextStyle(
                        color: _traceMode == _TraceMode.walk
                            ? AppTheme.accentGreen
                            : AppTheme.textMuted,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              _traceMode == _TraceMode.edit
                  ? 'Editing ${_editingFeature?.featureType ?? 'feature'} · '
                      '${_effectiveEditVertices.length} points. Tap an edge to add, '
                      'tap a pin to delete, hold and drag to move.'
                  : _traceMode == _TraceMode.pan
                      ? 'Pan and pinch to move the map. Switch to Draw to trace boundaries.'
                      : _traceMode == _TraceMode.walk
                          ? 'Walking adds GPS points every ~2m. Switch to Pan to move the map.'
                          : '${_currentVertices.length} draw points · pinch with two fingers to zoom',
              style: const TextStyle(color: AppTheme.textMuted, fontSize: 12),
            ),
            const SizedBox(height: 8),
            if (_traceMode == _TraceMode.edit) ...[
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _undoEditChange,
                      child: const Text('Undo'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _cancelFeatureEdit,
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppTheme.accentGreen,
                        foregroundColor: const Color(0xFF0F172A),
                      ),
                      onPressed: _saveFeatureEdit,
                      child: const Text('Save feature'),
                    ),
                  ),
                ],
              ),
            ] else ...[
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _undoVertex,
                      child: const Text('Undo'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _clearVertices,
                      child: const Text('Clear'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppTheme.accentGreen,
                        foregroundColor: const Color(0xFF0F172A),
                      ),
                      onPressed: _commitCurrentFeature,
                      child: const Text('Save feature'),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _uploading ? null : _uploadCourseToDatabase,
              icon: _uploading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.cloud_upload_outlined),
              label: const Text('Upload to database'),
            ),
          ],
      ),
    );
  }
}

class _CourseMatchDialog extends StatelessWidget {
  const _CourseMatchDialog({
    required this.query,
    required this.matches,
  });

  final String query;
  final List<CourseImportMatch> matches;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1A1A22),
      title: Text('Matches for "$query"'),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView.separated(
          shrinkWrap: true,
          itemCount: matches.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final match = matches[index];
            return ListTile(
              title: Text(
                match.name,
                style: const TextStyle(color: Colors.white),
              ),
              subtitle: Text(
                [
                  match.sourceLabel,
                  if (match.subtitle != null &&
                      match.subtitle != match.sourceLabel)
                    match.subtitle!,
                ].join(' · '),
                style: const TextStyle(color: AppTheme.textMuted, fontSize: 12),
              ),
              trailing: Text(
                match.sourceLabel,
                style: TextStyle(
                  color: match.source == CourseImportSource.database
                      ? AppTheme.accentGreen
                      : AppTheme.textMuted,
                  fontWeight: FontWeight.w700,
                  fontSize: 11,
                ),
              ),
              onTap: () => Navigator.pop(context, match),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}
