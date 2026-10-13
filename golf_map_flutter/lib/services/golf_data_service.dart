import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:supabase/supabase.dart';

import '../config/app_config.dart';
import '../models/course_catalog.dart';
import '../models/golf_feature.dart';
import '../utils/city_lookup.dart';
import '../utils/geo_utils.dart';
import 'user_course_storage_service.dart';

class CourseExistenceResult {
  const CourseExistenceResult({
    this.localFeatureCount = 0,
    this.remoteFeatureCount = 0,
    this.bundledFeatureCount = 0,
  });

  final int localFeatureCount;
  final int remoteFeatureCount;
  final int bundledFeatureCount;

  bool get existsLocally => localFeatureCount > 0;
  bool get existsRemotely => remoteFeatureCount > 0;
  bool get existsInBundledData => bundledFeatureCount > 0;
}

class GolfDataService {
  GolfDataService({
    SupabaseClient? client,
    UserCourseStorageService? userCourseStorage,
  })  : _client = client ??
            SupabaseClient(
              AppConfig.supabaseUrl,
              AppConfig.supabaseAnonKey,
            ),
        _userCourseStorage = userCourseStorage ?? UserCourseStorageService();

  final SupabaseClient? _client;
  final UserCourseStorageService _userCourseStorage;
  List<GolfFeature>? _cachedSourceFeatures;
  List<String>? _cachedSourceCourseNames;
  Future<List<GolfFeature>>? _sourceFeaturesInFlight;
  List<String>? _cachedRemoteCourseNames;
  Future<List<String>>? _remoteCourseNamesInFlight;

  Future<List<GolfFeature>> fetchGolfFeatures() async {
    final bundled = await _fetchBundledOrRemoteFeatures();
    final userFeatures = await _userCourseStorage.loadFeatures();
    if (userFeatures.isEmpty) return bundled;
    return [...bundled, ...userFeatures];
  }

  Future<List<String>> fetchUserCourseNames() {
    return _userCourseStorage.loadCourseNames();
  }

  Future<void> deleteUserCourse(String courseName) {
    return _userCourseStorage.deleteCourse(courseName);
  }

  Future<CourseExistenceResult> checkCourseExistence(String courseName) async {
    final normalized = courseName.trim();
    if (normalized.isEmpty) return const CourseExistenceResult();

    final localCount =
        await _userCourseStorage.featureCountForCourse(normalized);
    final bundledFeatures = await fetchSourceFeaturesForCourse(normalized);
    final remoteCount = await _countRemoteCourseFeatures(normalized);

    return CourseExistenceResult(
      localFeatureCount: localCount,
      remoteFeatureCount: remoteCount,
      bundledFeatureCount: bundledFeatures.length,
    );
  }

  Future<int> _countRemoteCourseFeatures(String courseName) async {
    final client = _client;
    if (client == null) return 0;

    final normalized = courseName.trim();
    if (normalized.isEmpty) return 0;

    final data = await client
        .from('golf_features')
        .select('id')
        .eq('course_name', normalized);

    return (data as List).length;
  }

  /// Replaces all remote rows for [courseName] with [featureRows].
  Future<int> uploadCourseFeatures(
    String courseName,
    List<Map<String, dynamic>> featureRows,
  ) async {
    final client = _client;
    if (client == null) {
      throw StateError('Supabase client is not configured.');
    }

    final normalized = courseName.trim();
    if (normalized.isEmpty) {
      throw ArgumentError('Course name is required.');
    }
    if (featureRows.isEmpty) {
      throw ArgumentError('No features to upload.');
    }

    final maxRow = await client
        .from('golf_features')
        .select('id')
        .order('id', ascending: false)
        .limit(1)
        .maybeSingle();
    var nextId = (maxRow?['id'] as num?)?.toInt() ?? 0;

    await client.from('golf_features').delete().eq('course_name', normalized);

    final inserts = <Map<String, dynamic>>[];
    for (final row in featureRows) {
      nextId++;
      final rawGeom = row['geom'];
      final geometry = rawGeom is Map
          ? Map<String, dynamic>.from(rawGeom.cast<String, dynamic>())
          : Map<String, dynamic>.from(
              (jsonDecode(rawGeom as String) as Map).cast<String, dynamic>(),
            );
      geometry.remove('crs');

      final insert = <String, dynamic>{
        'id': nextId,
        'feature_type': row['feature_type'],
        'hole_number': row['hole_number'],
        'name': row['name'],
        'geom': geometry,
        'course_name': normalized,
      };
      if (row['par'] != null) insert['par'] = row['par'];
      if (row['handicap'] != null) insert['handicap'] = row['handicap'];
      inserts.add(insert);
    }

    await client.from('golf_features').insert(inserts);
    _cachedRemoteCourseNames = null;
    return inserts.length;
  }

  /// Course names currently stored in Supabase `golf_features`.
  Future<List<String>> fetchRemoteCourseNames() async {
    final cached = _cachedRemoteCourseNames;
    if (cached != null) return cached;

    final inFlight = _remoteCourseNamesInFlight;
    if (inFlight != null) return inFlight;

    final future = _loadRemoteCourseNames();
    _remoteCourseNamesInFlight = future;
    try {
      final names = await future;
      _cachedRemoteCourseNames = names;
      return names;
    } finally {
      _remoteCourseNamesInFlight = null;
    }
  }

  Future<List<String>> _loadRemoteCourseNames() async {
    final client = _client;
    if (client == null) return const [];

    try {
      final data = await client.from('golf_features').select('course_name');
      final names = (data as List)
          .map((row) => (row as Map)['course_name']?.toString())
          .whereType<String>()
          .map((name) => name.trim())
          .where((name) => name.isNotEmpty)
          .toSet()
          .toList()
        ..sort();
      return names;
    } catch (_) {
      return const [];
    }
  }

  /// Features for one course from Supabase (always hits the remote table).
  Future<List<GolfFeature>> fetchRemoteFeaturesForCourse(
    String courseName,
  ) async {
    final client = _client;
    if (client == null) {
      throw StateError('Supabase client is not configured.');
    }

    final normalized = courseName.trim();
    if (normalized.isEmpty) return const [];

    final data = await client
        .from('golf_features')
        .select(
          'id, feature_type, hole_number, name, geom, par, handicap, course_name',
        )
        .eq('course_name', normalized);

    final rows = (data as List).cast<Map<String, dynamic>>();
    return _parseFeatureRows(rows);
  }

  /// Course names from bundled assets or Supabase (open-source baseline data).
  Future<List<String>> fetchSourceCourseNames() async {
    final cached = _cachedSourceCourseNames;
    if (cached != null) return cached;

    final features = await _fetchBundledOrRemoteFeatures();
    final names = extractCourses(features);
    _cachedSourceCourseNames = names;
    return names;
  }

  Future<List<GolfFeature>> fetchSourceFeaturesForCourse(String courseName) async {
    final normalized = courseName.trim();
    if (normalized.isEmpty) return const [];

    final features = await _fetchBundledOrRemoteFeatures();
    return features.where((f) => f.matchesCourse(normalized)).toList();
  }

  List<GolfFeature> cloneFeaturesForCourse(
    List<GolfFeature> source,
    String targetCourseName,
  ) {
    final normalized = targetCourseName.trim();
    final stamp = DateTime.now().millisecondsSinceEpoch;
    return source.asMap().entries.map((entry) {
      final feature = entry.value;
      return GolfFeature(
        id: 'user-$stamp-${entry.key}',
        featureType: feature.featureType,
        holeNumber: feature.holeNumber,
        name: feature.name,
        par: feature.par,
        handicap: feature.handicap,
        courseName: normalized,
        geometry: Map<String, dynamic>.from(feature.geometry),
      );
    }).toList();
  }

  Future<List<GolfFeature>> _fetchBundledOrRemoteFeatures() async {
    final cached = _cachedSourceFeatures;
    if (cached != null) return cached;

    final inFlight = _sourceFeaturesInFlight;
    if (inFlight != null) return inFlight;

    final future = _loadSourceFeatures();
    _sourceFeaturesInFlight = future;
    try {
      final features = await future;
      _cachedSourceFeatures = features;
      return features;
    } finally {
      _sourceFeaturesInFlight = null;
    }
  }

  Future<List<GolfFeature>> _loadSourceFeatures() async {
    if (AppConfig.useBundledCourseData) {
      try {
        return await _fetchBundledGolfFeatures();
      } catch (_) {
        // Fall back to Supabase when the asset is missing or invalid.
      }
    }

    return _fetchRemoteGolfFeatures();
  }

  Future<List<GolfFeature>> _fetchBundledGolfFeatures() async {
    final json = await rootBundle.loadString(AppConfig.bundledCoursesAsset);
    final rows = (jsonDecode(json) as List).cast<Map<String, dynamic>>();
    return _parseFeatureRows(rows);
  }

  Future<List<GolfFeature>> _fetchRemoteGolfFeatures() async {
    final client = _client;
    if (client == null) {
      throw StateError('Supabase client is not configured.');
    }

    final data = await client
        .from('golf_features')
        .select(
          'id, feature_type, hole_number, name, geom, par, handicap, course_name',
        );

    final rows = (data as List).cast<Map<String, dynamic>>();
    return _parseFeatureRows(rows);
  }

  List<GolfFeature> _parseFeatureRows(List<Map<String, dynamic>> rows) {
    return rows.map((item) {
      final rawGeom = item['geom'];
      final geometry = rawGeom is String
          ? Map<String, dynamic>.from(
              (jsonDecode(rawGeom) as Map).cast<String, dynamic>(),
            )
          : Map<String, dynamic>.from(rawGeom as Map);
      geometry.remove('crs');

      var holeNumber = item['hole_number'];
      if (holeNumber == null ||
          holeNumber.toString().toLowerCase() == 'null') {
        holeNumber = null;
      }

      return GolfFeature(
        id: item['id'],
        featureType: item['feature_type'] as String?,
        holeNumber: holeNumber?.toString(),
        name: item['name'] as String?,
        par: item['par'] as int?,
        handicap: item['handicap'] as int?,
        courseName: item['course_name'] as String?,
        geometry: geometry,
      );
    }).toList();
  }

  List<String> extractCourses(List<GolfFeature> features) {
    return buildCourseCatalog(features).map((entry) => entry.name).toList();
  }

  List<CourseCatalogEntry> buildCourseCatalog(List<GolfFeature> features) {
    final featuresByCourse = <String, List<GolfFeature>>{};

    for (final feature in features) {
      final name = feature.courseName?.trim();
      if (name == null || name.isEmpty) continue;
      featuresByCourse.putIfAbsent(name, () => []).add(feature);
    }

    final entries = <CourseCatalogEntry>[];

    for (final courseEntry in featuresByCourse.entries) {
      final centroids = courseEntry.value
          .map(centroidOfGolfFeature)
          .whereType<List<double>>()
          .toList();

      if (centroids.isEmpty) continue;

      final latitude =
          centroids.map((point) => point[1]).reduce((a, b) => a + b) /
              centroids.length;
      final longitude =
          centroids.map((point) => point[0]).reduce((a, b) => a + b) /
              centroids.length;
      final city = nearestCity(latitude, longitude);

      entries.add(
        CourseCatalogEntry(
          name: courseEntry.key,
          state: city.state,
          stateCode: city.stateCode,
          city: city.name,
          latitude: latitude,
          longitude: longitude,
        ),
      );
    }

    entries.sort((a, b) {
      final stateCompare = a.state.compareTo(b.state);
      if (stateCompare != 0) return stateCompare;
      final cityCompare = a.city.compareTo(b.city);
      if (cityCompare != 0) return cityCompare;
      return a.name.compareTo(b.name);
    });

    return entries;
  }

  List<String> holesForCourse(List<GolfFeature> features, String course) {
    return features
        .where((f) => f.matchesCourse(course) && f.holeNumber != null)
        .map((f) => f.holeNumber!)
        .toSet()
        .toList()
      ..sort((a, b) => int.parse(a).compareTo(int.parse(b)));
  }

  HoleStats? statsForHole(
    List<GolfFeature> features,
    String course,
    String hole,
  ) {
    final holeFeatures = features
        .where((f) => f.matchesCourse(course) && f.matchesHole(hole))
        .toList();

    if (holeFeatures.isEmpty) return null;

    final statFeature = holeFeatures.firstWhere(
      (f) => f.par != null,
      orElse: () => holeFeatures.first,
    );

    return HoleStats(
      par: statFeature.par ?? 0,
      handicap: statFeature.handicap ?? 0,
    );
  }
}
