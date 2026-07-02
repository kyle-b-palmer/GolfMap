import 'package:shared_preferences/shared_preferences.dart';

import '../models/health_workout_mode.dart';

class AppPreferencesService {
  static const _showScoreTargetKey = 'show_score_target';
  static const _idealLineEnabledKey = 'ideal_line_enabled';
  static const _mapOverlayEnabledKey = 'map_overlay_enabled';
  static const _autoAdvanceHoleKey = 'auto_advance_hole';
  static const _showDispersionKey = 'show_shot_dispersion';
  static const _healthWorkoutKey = 'health_workout_enabled';
  static const _healthWorkoutModeKey = 'health_workout_mode';
  static const _startHealthWorkoutWithRoundKey = 'start_health_workout_with_round';
  static const _gpsSimModeKey = 'gps_sim_mode_enabled';
  static const _clubBagKey = 'club_bag_json';

  Future<bool> getShowScoreTarget() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_showScoreTargetKey) ?? true;
  }

  Future<void> setShowScoreTarget(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_showScoreTargetKey, value);
  }

  Future<bool> getIdealLineEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_idealLineEnabledKey) ?? true;
  }

  Future<void> setIdealLineEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_idealLineEnabledKey, value);
  }

  Future<bool> getMapOverlayEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_mapOverlayEnabledKey) ?? true;
  }

  Future<void> setMapOverlayEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_mapOverlayEnabledKey, value);
  }

  Future<bool> getAutoAdvanceHole() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_autoAdvanceHoleKey) ?? true;
  }

  Future<void> setAutoAdvanceHole(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_autoAdvanceHoleKey, value);
  }

  Future<bool> getShowShotDispersion() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_showDispersionKey) ?? false;
  }

  Future<void> setShowShotDispersion(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_showDispersionKey, value);
  }

  Future<HealthWorkoutMode> getHealthWorkoutMode() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_healthWorkoutModeKey);
    if (stored != null) {
      return HealthWorkoutMode.fromStorage(stored);
    }
    if (prefs.containsKey(_healthWorkoutKey)) {
      final legacyEnabled = prefs.getBool(_healthWorkoutKey) ?? true;
      return legacyEnabled ? HealthWorkoutMode.always : HealthWorkoutMode.never;
    }
    return HealthWorkoutMode.always;
  }

  Future<void> setHealthWorkoutMode(HealthWorkoutMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_healthWorkoutModeKey, mode.name);
    await prefs.setBool(
      _healthWorkoutKey,
      mode == HealthWorkoutMode.always,
    );
  }

  Future<bool> getStartHealthWorkoutWithRound() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_startHealthWorkoutWithRoundKey) ?? true;
  }

  Future<void> setStartHealthWorkoutWithRound(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_startHealthWorkoutWithRoundKey, value);
  }

  Future<bool> getGpsSimModeEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_gpsSimModeKey) ?? false;
  }

  Future<void> setGpsSimModeEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_gpsSimModeKey, value);
  }

  Future<String?> getClubBagJson() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_clubBagKey);
  }

  Future<void> setClubBagJson(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_clubBagKey, value);
  }
}
