import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/saved_round.dart';

class RoundStorageService {
  static const _storageKey = 'saved_golf_rounds';

  Future<List<SavedRound>> loadRounds() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw == null || raw.isEmpty) return [];

    final decoded = jsonDecode(raw) as List<dynamic>;
    final rounds = <SavedRound>[];
    for (final item in decoded) {
      if (item is! Map) continue;
      try {
        rounds.add(SavedRound.fromJson(Map<String, dynamic>.from(item)));
      } catch (_) {
        // Skip rounds that fail to parse (e.g. corrupted storage).
      }
    }
    rounds.sort((a, b) => b.playedAt.compareTo(a.playedAt));

    return rounds;
  }

  Future<void> saveRound(SavedRound round) async {
    final rounds = await loadRounds();
    final index = rounds.indexWhere((r) => r.id == round.id);
    if (index >= 0) {
      rounds[index] = round;
    } else {
      rounds.insert(0, round);
    }

    await _persist(rounds);
  }

  Future<void> deleteRound(String id) async {
    final rounds = await loadRounds()..removeWhere((r) => r.id == id);
    await _persist(rounds);
  }

  Future<void> _persist(List<SavedRound> rounds) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(rounds.map((r) => r.toJson()).toList());
    await prefs.setString(_storageKey, encoded);
  }
}
