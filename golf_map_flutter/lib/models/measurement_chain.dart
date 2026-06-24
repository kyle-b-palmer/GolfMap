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
}

class MeasurementSegmentInfo {
  const MeasurementSegmentInfo({
    required this.shotNumber,
    required this.yards,
  });

  final int shotNumber;
  final int yards;
}
