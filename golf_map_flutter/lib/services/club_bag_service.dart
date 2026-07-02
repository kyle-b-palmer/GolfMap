import 'dart:convert';

import '../models/club_bag.dart';
import 'app_preferences_service.dart';

class ClubBagService {
  ClubBagService({AppPreferencesService? prefs})
      : _prefs = prefs ?? AppPreferencesService();

  final AppPreferencesService _prefs;

  Future<List<ClubDistance>> loadClubs() async {
    final json = await _prefs.getClubBagJson();
    if (json == null || json.isEmpty) {
      return List.from(ClubBag.defaultClubs);
    }
    try {
      final raw = jsonDecode(json) as List<dynamic>;
      final clubs = ClubBag.fromJsonList(raw);
      return clubs.isEmpty ? List.from(ClubBag.defaultClubs) : clubs;
    } catch (_) {
      return List.from(ClubBag.defaultClubs);
    }
  }

  Future<void> saveClubs(List<ClubDistance> clubs) async {
    await _prefs.setClubBagJson(
      jsonEncode(ClubBag.toJsonList(clubs)),
    );
  }

  Future<void> resetToDefaults() async {
    await saveClubs(List.from(ClubBag.defaultClubs));
  }
}
