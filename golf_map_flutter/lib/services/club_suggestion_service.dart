import '../models/club_bag.dart';

class ClubSuggestion {
  const ClubSuggestion({
    required this.club,
    required this.targetYards,
    this.alternateClub,
  });

  final String club;
  final int targetYards;
  final String? alternateClub;
}

class ClubSuggestionService {
  ClubSuggestionService({List<ClubDistance>? clubs})
      : _clubs = List.of(clubs ?? ClubBag.defaultClubs);

  List<ClubDistance> _clubs;

  void updateClubs(List<ClubDistance> clubs) {
    _clubs = List.of(clubs.isEmpty ? ClubBag.defaultClubs : clubs);
  }

  static bool isDriverClub(String name) {
    final normalized = name.trim().toUpperCase();
    return normalized == 'DR' ||
        normalized == 'DRIVER' ||
        normalized == '1W' ||
        normalized == 'D';
  }

  ClubSuggestion? suggest(
    int yards, {
    bool allowDriver = true,
  }) {
    if (yards <= 0) return null;

    final eligible = allowDriver
        ? _clubs
        : _clubs.where((club) => !isDriverClub(club.name)).toList();
    if (eligible.isEmpty) return null;

    ClubDistance? best;
    var bestDiff = 9999;

    for (final club in eligible) {
      final diff = (club.carryYards - yards).abs();
      if (diff < bestDiff) {
        bestDiff = diff;
        best = club;
      }
    }

    if (best == null) return null;

    String? alternate;
    if (yards > best.carryYards + 8) {
      alternate = eligible
          .where((c) => c.carryYards > best!.carryYards)
          .fold<ClubDistance?>(
            null,
            (prev, c) => prev == null || c.carryYards < prev.carryYards ? c : prev,
          )
          ?.name;
    } else if (yards < best.carryYards - 12) {
      alternate = eligible
          .where((c) => c.carryYards < best!.carryYards)
          .fold<ClubDistance?>(
            null,
            (prev, c) => prev == null || c.carryYards > prev.carryYards ? c : prev,
          )
          ?.name;
    }

    return ClubSuggestion(
      club: best.name,
      targetYards: yards,
      alternateClub: alternate,
    );
  }
}
