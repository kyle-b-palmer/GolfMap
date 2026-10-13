import 'dart:math' as math;

import '../models/golf_feature.dart';
import 'golf_data_service.dart';
import 'osm_golf_course_service.dart';

enum CourseImportSource { database, bundled, openStreetMap }

class CourseImportMatch {
  const CourseImportMatch({
    required this.name,
    required this.source,
    this.osmSummary,
    this.subtitle,
  });

  final String name;
  final CourseImportSource source;
  final OsmGolfCourseSummary? osmSummary;
  final String? subtitle;

  String get sourceLabel => switch (source) {
        CourseImportSource.database => 'Database',
        CourseImportSource.bundled => 'Built-in',
        CourseImportSource.openStreetMap => 'OpenStreetMap',
      };
}

class CourseImportResult {
  const CourseImportResult({
    required this.sourceName,
    required this.features,
    required this.holeNumbers,
  });

  final String sourceName;
  final List<GolfFeature> features;
  final List<int> holeNumbers;
}

/// Finds golf courses by name in the shared database, bundled data, and OSM.
class CourseImportService {
  CourseImportService({
    GolfDataService? dataService,
    OsmGolfCourseService? osmService,
  })  : _dataService = dataService ?? GolfDataService(),
        _osmService = osmService ?? OsmGolfCourseService();

  final GolfDataService _dataService;
  final OsmGolfCourseService _osmService;

  Future<List<CourseImportMatch>> searchCourses(
    String query, {
    double? latitude,
    double? longitude,
  }) async {
    final normalized = query.trim();
    if (normalized.isEmpty) return [];

    final queryLower = normalized.toLowerCase();
    final matches = <CourseImportMatch>[];
    final seenKeys = <String>{};

    void addMatch(CourseImportMatch match) {
      final key =
          '${match.source.name}:${match.name.trim().toLowerCase()}';
      if (key.endsWith(':') || seenKeys.contains(key)) return;
      seenKeys.add(key);
      matches.add(match);
    }

    // Database, built-in catalog, and OSM search in parallel.
    final remoteFuture = _dataService.fetchRemoteCourseNames();
    final bundledFuture = _dataService.fetchSourceCourseNames();
    final osmFuture = _osmService.searchCoursesByName(
      normalized,
      latitude: latitude,
      longitude: longitude,
    );

    final remoteNames = await remoteFuture;
    for (final name in remoteNames) {
      if (_nameMatches(name, queryLower)) {
        addMatch(
          CourseImportMatch(
            name: name,
            source: CourseImportSource.database,
            subtitle: 'Shared database · edit and re-upload',
          ),
        );
      }
    }

    final bundledNames = await bundledFuture;
    for (final name in bundledNames) {
      if (_nameMatches(name, queryLower)) {
        addMatch(
          CourseImportMatch(
            name: name,
            source: CourseImportSource.bundled,
            subtitle: 'Built-in course data',
          ),
        );
      }
    }

    final osmCourses = await osmFuture;
    for (final course in osmCourses) {
      addMatch(
        CourseImportMatch(
          name: course.name,
          source: CourseImportSource.openStreetMap,
          osmSummary: course,
          subtitle: course.displayName,
        ),
      );
    }

    matches.sort((a, b) {
      if (latitude != null && longitude != null) {
        final aDistance = _distanceToMatch(a, latitude, longitude);
        final bDistance = _distanceToMatch(b, latitude, longitude);
        if (aDistance != null && bDistance != null && aDistance != bDistance) {
          return aDistance.compareTo(bDistance);
        }
        if (aDistance != null && bDistance == null) return -1;
        if (aDistance == null && bDistance != null) return 1;
      }

      final aScore = _matchScore(a.name, queryLower);
      final bScore = _matchScore(b.name, queryLower);
      if (aScore != bScore) return bScore.compareTo(aScore);

      final sourceCompare =
          _sourcePriority(a.source).compareTo(_sourcePriority(b.source));
      if (sourceCompare != 0) return sourceCompare;
      return a.name.compareTo(b.name);
    });

    return matches;
  }

  Future<CourseImportResult> loadCourse(
    CourseImportMatch match,
    String targetCourseName,
  ) async {
    final List<GolfFeature> imported;
    switch (match.source) {
      case CourseImportSource.database:
        imported =
            await _dataService.fetchRemoteFeaturesForCourse(match.name);
      case CourseImportSource.bundled:
        imported = await _dataService.fetchSourceFeaturesForCourse(match.name);
      case CourseImportSource.openStreetMap:
        imported = await _osmService.fetchCourseFeatures(match.osmSummary!);
    }

    if (imported.isEmpty) {
      throw Exception('No mappable golf features found for ${match.name}.');
    }

    final cloned =
        _dataService.cloneFeaturesForCourse(imported, targetCourseName);
    final holeNumbers = _holeNumbersFromFeatures(cloned);

    return CourseImportResult(
      sourceName: match.name,
      features: cloned,
      holeNumbers: holeNumbers,
    );
  }

  int _sourcePriority(CourseImportSource source) => switch (source) {
        CourseImportSource.database => 0,
        CourseImportSource.bundled => 1,
        CourseImportSource.openStreetMap => 2,
      };

  List<int> _holeNumbersFromFeatures(List<GolfFeature> features) {
    return features
        .map((f) => f.holeNumber)
        .whereType<String>()
        .map(int.tryParse)
        .whereType<int>()
        .toSet()
        .toList()
      ..sort();
  }

  bool _nameMatches(String name, String queryLower) {
    final nameLower = name.trim().toLowerCase();
    if (nameLower.isEmpty) return false;
    if (nameLower == queryLower) return true;
    if (nameLower.contains(queryLower) || queryLower.contains(nameLower)) {
      return true;
    }

    final queryTokens = _meaningfulTokens(queryLower);
    if (queryTokens.isEmpty) return true;
    return queryTokens.every(nameLower.contains);
  }

  List<String> _meaningfulTokens(String text) {
    return text
        .split(RegExp(r'\s+'))
        .where((part) => part.length > 2 && !_stopWords.contains(part))
        .toList();
  }

  int _matchScore(String name, String queryLower) {
    final nameLower = name.trim().toLowerCase();
    if (nameLower == queryLower) return 100;
    if (nameLower.startsWith(queryLower)) return 80;
    if (nameLower.contains(queryLower)) return 60;

    final queryTokens = _meaningfulTokens(queryLower);
    if (queryTokens.isNotEmpty &&
        queryTokens.every(nameLower.contains)) {
      return 50;
    }
    return 20;
  }

  double? _distanceToMatch(
    CourseImportMatch match,
    double latitude,
    double longitude,
  ) {
    final summary = match.osmSummary;
    if (summary == null) return null;
    return _distanceMeters(
      latitude,
      longitude,
      summary.latitude,
      summary.longitude,
    );
  }

  double _distanceMeters(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const earthRadius = 6371000.0;
    final dLat = _toRadians(lat2 - lat1);
    final dLon = _toRadians(lon2 - lon1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_toRadians(lat1)) *
            math.cos(_toRadians(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadius * c;
  }

  double _toRadians(double degrees) => degrees * math.pi / 180.0;

  static const _stopWords = {
    'the',
    'a',
    'an',
    'golf',
    'course',
    'club',
    'links',
    'country',
    'at',
    'of',
  };
}
