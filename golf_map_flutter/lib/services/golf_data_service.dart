import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:supabase/supabase.dart';

import '../config/app_config.dart';
import '../models/golf_feature.dart';

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
    return features
        .map((f) => f.courseName)
        .whereType<String>()
        .toSet()
        .toList()
      ..sort();
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
