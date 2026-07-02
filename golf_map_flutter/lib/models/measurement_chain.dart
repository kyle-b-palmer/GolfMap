import 'package:latlong2/latlong.dart';

/// A locked waypoint in the multi-shot measurement chain.
class MeasurementChainPoint {
  const MeasurementChainPoint({
    required this.point,
    required this.segmentYards,
    required this.shotNumber,
  });

  final LatLng point;
  final int segmentYards;
  final int shotNumber;

  factory MeasurementChainPoint.fromJson(Map<String, dynamic> json) {
    return MeasurementChainPoint(
      point: LatLng(
        (json['latitude'] as num).toDouble(),
        (json['longitude'] as num).toDouble(),
      ),
      segmentYards: (json['segmentYards'] as num).toInt(),
      shotNumber: (json['shotNumber'] as num).toInt(),
    );
  }

  Map<String, dynamic> toJson() => {
        'latitude': point.latitude,
        'longitude': point.longitude,
        'segmentYards': segmentYards,
        'shotNumber': shotNumber,
      };
}

class MeasurementSegmentInfo {
  const MeasurementSegmentInfo({
    required this.shotNumber,
    required this.yards,
  });

  final int shotNumber;
  final int yards;
}
