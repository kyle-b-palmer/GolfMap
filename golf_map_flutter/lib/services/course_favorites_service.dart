import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

enum FavoriteToggleResult { added, removed, limitReached }

class CourseFavoritesService {
  static const maxFavorites = 5;
  static const _storageKey = 'favorite_courses';

  Future<List<String>> loadFavorites() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw == null || raw.isEmpty) return [];

    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .map((item) => item.toString().trim())
          .where((name) => name.isNotEmpty)
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<FavoriteToggleResult> toggle(String courseName) async {
    final trimmed = courseName.trim();
    if (trimmed.isEmpty) return FavoriteToggleResult.limitReached;

    final favorites = await loadFavorites();
    final index = favorites.indexOf(trimmed);

    if (index >= 0) {
      favorites.removeAt(index);
      await _save(favorites);
      return FavoriteToggleResult.removed;
    }

    if (favorites.length >= maxFavorites) {
      return FavoriteToggleResult.limitReached;
    }

    favorites.insert(0, trimmed);
    await _save(favorites);
    return FavoriteToggleResult.added;
  }

  Future<void> _save(List<String> favorites) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKey, jsonEncode(favorites));
  }
}
