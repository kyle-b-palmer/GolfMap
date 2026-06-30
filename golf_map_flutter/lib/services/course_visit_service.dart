import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/saved_round.dart';
import 'round_storage_service.dart';

class CommonlyVisitedEntry {
  const CommonlyVisitedEntry({
    required this.courseName,
    required this.savedRoundCount,
    required this.viewCount,
  });

  final String courseName;
  final int savedRoundCount;
  final int viewCount;

  String get countLabel {
    if (savedRoundCount > 0) {
      return savedRoundCount == 1
          ? '1 saved round'
          : '$savedRoundCount saved rounds';
    }
    return viewCount == 1 ? 'viewed 1 time' : 'viewed $viewCount times';
  }
}

class CourseVisitService {
  static const _countsKey = 'course_visit_counts';
  static const _bootstrappedKey = 'course_visit_bootstrapped';

  Future<Map<String, int>> loadCounts() async {
    final prefs = await SharedPreferences.getInstance();
    await _bootstrapFromSavedRoundsIfNeeded(prefs);

    final raw = prefs.getString(_countsKey);
    if (raw == null || raw.isEmpty) return {};

    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return decoded.map(
        (course, count) => MapEntry(course, (count as num).toInt()),
      );
    } catch (_) {
      return {};
    }
  }

  Future<void> recordVisit(String courseName) async {
    final trimmed = courseName.trim();
    if (trimmed.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    final counts = await loadCounts();
    counts[trimmed] = (counts[trimmed] ?? 0) + 1;

    await prefs.setString(_countsKey, jsonEncode(counts));
  }

  /// Top courses by saved rounds, falling back to open/view counts for ranking.
  Future<List<CommonlyVisitedEntry>> commonlyVisited({
    required List<SavedRound> savedRounds,
    int limit = 2,
  }) async {
    final visitCounts = await loadCounts();
    final savedCounts = _countsFromRounds(savedRounds);

    final courseNames = <String>{
      ...savedCounts.keys,
      ...visitCounts.keys,
    };

    final entries = courseNames
        .map(
          (courseName) => CommonlyVisitedEntry(
            courseName: courseName,
            savedRoundCount: savedCounts[courseName] ?? 0,
            viewCount: visitCounts[courseName] ?? 0,
          ),
        )
        .where(
          (entry) => entry.savedRoundCount > 0 || entry.viewCount > 0,
        )
        .toList()
      ..sort((a, b) {
        final savedCompare =
            b.savedRoundCount.compareTo(a.savedRoundCount);
        if (savedCompare != 0) return savedCompare;
        final viewCompare = b.viewCount.compareTo(a.viewCount);
        if (viewCompare != 0) return viewCompare;
        return a.courseName.compareTo(b.courseName);
      });

    return entries.take(limit).toList();
  }

  Future<void> _bootstrapFromSavedRoundsIfNeeded(SharedPreferences prefs) async {
    if (prefs.getBool(_bootstrappedKey) ?? false) return;

    final rounds = await RoundStorageService().loadRounds();
    if (rounds.isEmpty) {
      await prefs.setBool(_bootstrappedKey, true);
      return;
    }

    final counts = _countsFromRounds(rounds);
    await prefs.setString(_countsKey, jsonEncode(counts));
    await prefs.setBool(_bootstrappedKey, true);
  }

  Map<String, int> _countsFromRounds(List<SavedRound> rounds) {
    final counts = <String, int>{};
    for (final round in rounds) {
      final name = round.courseName.trim();
      if (name.isEmpty) continue;
      counts[name] = (counts[name] ?? 0) + 1;
    }
    return counts;
  }
}
