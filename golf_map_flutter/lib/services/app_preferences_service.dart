import 'package:shared_preferences/shared_preferences.dart';

class AppPreferencesService {
  static const _showScoreTargetKey = 'show_score_target';
  static const _idealLineEnabledKey = 'ideal_line_enabled';

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
}
