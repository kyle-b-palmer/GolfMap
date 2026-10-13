import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/golf_feature.dart';

/// Persists user-traced course geometry on device (same row shape as bundled JSON).
class UserCourseStorageService {
  static const _storageKey = 'user_traced_course_features_v1';

  Future<List<Map<String, dynamic>>> loadFeatureRows() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw == null || raw.isEmpty) return [];

    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  Future<List<String>> loadCourseNames() async {
    final rows = await loadFeatureRows();
    return rows
        .map((row) => row['course_name']?.toString())
        .whereType<String>()
        .where((name) => name.trim().isNotEmpty)
        .toSet()
        .toList()
      ..sort();
  }

  Future<bool> hasCourse(String courseName) async {
    final normalized = courseName.trim();
    if (normalized.isEmpty) return false;
    final names = await loadCourseNames();
    return names.any((name) => name.trim() == normalized);
  }

  Future<int> featureCountForCourse(String courseName) async {
    final normalized = courseName.trim();
    if (normalized.isEmpty) return 0;
    final rows = await loadFeatureRows();
    return rows
        .where((row) => row['course_name']?.toString().trim() == normalized)
        .length;
  }

  Future<List<GolfFeature>> loadFeatures() async {
    final rows = await loadFeatureRows();
    return _parseRows(rows);
  }

  Future<void> saveCourseFeatures(
    String courseName,
    List<Map<String, dynamic>> featureRows,
  ) async {
    final normalizedName = courseName.trim();
    if (normalizedName.isEmpty) return;

    final existing = await loadFeatureRows();
    final kept = existing
        .where((row) => row['course_name']?.toString() != normalizedName)
        .toList();
    final merged = [...kept, ...featureRows];
    await _persist(merged);
  }

  Future<void> deleteCourse(String courseName) async {
    final normalizedName = courseName.trim();
    if (normalizedName.isEmpty) return;

    final existing = await loadFeatureRows();
    final kept = existing
        .where((row) => row['course_name']?.toString() != normalizedName)
        .toList();
    await _persist(kept);
  }

  Future<void> _persist(List<Map<String, dynamic>> rows) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKey, jsonEncode(rows));
  }

  int? _parseOptionalInt(Object? value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString());
  }

  List<GolfFeature> _parseRows(List<Map<String, dynamic>> rows) {
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
        par: _parseOptionalInt(item['par']),
        handicap: _parseOptionalInt(item['handicap']),
        courseName: item['course_name'] as String?,
        geometry: geometry,
      );
    }).toList();
  }
}
