import '../models/pinned_shot.dart';
import '../models/pin_type.dart';
import '../services/round_storage_service.dart';

class DispersionPoint {
  const DispersionPoint({
    required this.latitude,
    required this.longitude,
    required this.weight,
  });

  final double latitude;
  final double longitude;
  final double weight;
}

class ShotDispersionService {
  ShotDispersionService({RoundStorageService? storage})
      : _storage = storage ?? RoundStorageService();

  final RoundStorageService _storage;

  Future<List<DispersionPoint>> pointsForHole({
    required String courseName,
    required String hole,
    int gridYards = 8,
  }) async {
    final rounds = await _storage.loadRounds();
    final shots = <PinnedShot>[];

    for (final round in rounds) {
      if (round.courseName != courseName) continue;
      final holeShots = round.pinnedShots[hole];
      if (holeShots == null) continue;
      shots.addAll(holeShots.where((s) => s.pinType != PinType.lostBall));
    }

    if (shots.isEmpty) return [];

    final buckets = <String, List<PinnedShot>>{};
    for (final shot in shots) {
      final key = _bucketKey(shot.latitude, shot.longitude, gridYards);
      buckets.putIfAbsent(key, () => []).add(shot);
    }

    return buckets.values.map((group) {
      final lat =
          group.map((s) => s.latitude).reduce((a, b) => a + b) / group.length;
      final lng =
          group.map((s) => s.longitude).reduce((a, b) => a + b) / group.length;
      return DispersionPoint(
        latitude: lat,
        longitude: lng,
        weight: group.length.toDouble(),
      );
    }).toList();
  }

  String _bucketKey(double lat, double lng, int gridYards) {
    final gridMeters = gridYards / 1.09361;
    final latBucket = (lat / (gridMeters / 111320)).round();
    final lngBucket = (lng / (gridMeters / 111320)).round();
    return '$latBucket:$lngBucket:$lat';
  }
}
