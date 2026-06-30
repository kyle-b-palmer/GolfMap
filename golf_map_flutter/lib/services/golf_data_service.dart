import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:supabase/supabase.dart';

import '../config/app_config.dart';
import '../models/course_catalog.dart';
import '../models/golf_feature.dart';
import '../utils/city_lookup.dart';
import '../utils/geo_utils.dart';

class GolfDataService {
  GolfDataService({SupabaseClient? client})
      : _client = client ??
            SupabaseClient(
              AppConfig.supabaseUrl,
              AppConfig.supabaseAnonKey,
            );

  final SupabaseClient? _client;

  Future<List<GolfFeature>> fetchGolfFeatures() async {
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
