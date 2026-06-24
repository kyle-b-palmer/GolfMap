import 'pinned_shot.dart';

class SavedRound {
  const SavedRound({
    required this.id,
    required this.courseName,
    required this.playedAt,
    required this.scores,
    Map<String, List<PinnedShot>>? pinnedShots,
  }) : pinnedShots = pinnedShots ?? const {};

  final String id;
  final String courseName;
  final DateTime playedAt;
  final Map<String, int> scores;
  final Map<String, List<PinnedShot>> pinnedShots;

  int get totalStrokes =>
      scores.values.fold<int>(0, (sum, strokes) => sum + strokes);

  int get holesScored =>
      scores.values.where((strokes) => strokes > 0).length;

  int get totalPinnedShots {
    var total = 0;
    for (final shots in pinnedShots.values) {
      total += shots.length;
    }
    return total;
  }

  factory SavedRound.fromJson(Map<String, dynamic> json) {
    final rawScores = json['scores'];
    final scores = <String, int>{};
    if (rawScores is Map) {
      rawScores.forEach((hole, strokes) {
        if (strokes is num) {
          scores[hole.toString()] = strokes.toInt();
        }
      });
    }

    return SavedRound(
      id: json['id'] as String,
      courseName: json['courseName'] as String,
      playedAt: DateTime.parse(json['playedAt'] as String),
      scores: scores,
      pinnedShots: _parsePinnedShots(json['pinnedShots']),
    );
  }

  static Map<String, List<PinnedShot>> _parsePinnedShots(dynamic raw) {
    if (raw == null || raw is! Map) return {};

    final result = <String, List<PinnedShot>>{};
    raw.forEach((hole, shots) {
      if (shots is! List) return;

      final parsed = <PinnedShot>[];
      for (final item in shots) {
        if (item is! Map) continue;
        try {
          parsed.add(
            PinnedShot.fromJson(Map<String, dynamic>.from(item)),
          );
        } catch (_) {
          // Skip malformed shot entries from older saves.
        }
      }
      parsed.sort((a, b) => a.shotNumber.compareTo(b.shotNumber));
      result[hole.toString()] = parsed;
    });
    return result;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'courseName': courseName,
        'playedAt': playedAt.toIso8601String(),
        'scores': scores,
        'pinnedShots': pinnedShots.map(
          (hole, shots) => MapEntry(
            hole,
            shots.map((s) => s.toJson()).toList(),
          ),
        ),
      };
}
