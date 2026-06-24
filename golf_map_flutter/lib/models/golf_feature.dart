import 'measurement_chain.dart';

class GolfFeature {
  GolfFeature({
    required this.id,
    required this.featureType,
    required this.holeNumber,
    required this.name,
    required this.par,
    required this.handicap,
    required this.courseName,
    required this.geometry,
  });

  final dynamic id;
  final String? featureType;
  final String? holeNumber;
  final String? name;
  final int? par;
  final int? handicap;
  final String? courseName;
  final Map<String, dynamic> geometry;

  bool matchesCourse(String? course) =>
      course != null &&
      courseName != null &&
      courseName!.trim() == course.trim();

  bool matchesHole(String hole) =>
      holeNumber != null && holeNumber == hole;

  bool isActive(String? course, String hole) =>
      matchesCourse(course) && matchesHole(hole);

  Map<String, dynamic> toGeoJsonFeature() => {
        'type': 'Feature',
        'id': id,
        'properties': {
          'feature_type': featureType,
          'hole_number': holeNumber,
          'name': name,
          'par': par,
          'handicap': handicap,
          'course_name': courseName,
        },
        'geometry': geometry,
      };
}

class GreenYardages {
  const GreenYardages({
    required this.front,
    required this.middle,
    required this.back,
  });

  final int front;
  final int middle;
  final int back;
}

class DistanceInfo {
  const DistanceInfo({
    required this.greenYardages,
    required this.bunkerDistances,
    required this.hasBunkerReference,
    required this.fromUserYards,
    required this.lockedSegments,
    required this.activeSegmentYards,
    required this.holeNumber,
    required this.holeCoord,
    required this.shotOriginCoord,
    required this.usingGps,
  });

  final GreenYardages greenYardages;
  final List<BunkerDistance> bunkerDistances;
  final bool hasBunkerReference;
  final int? fromUserYards;
  final List<MeasurementSegmentInfo> lockedSegments;
  final int? activeSegmentYards;
  final String holeNumber;
  final List<double> holeCoord; // [lng, lat] green center
  final List<double> shotOriginCoord; // [lng, lat]
  final bool usingGps;
}

class BunkerDistance {
  const BunkerDistance({required this.label, required this.yards});

  final String label;
  final int yards;
}

class HoleStats {
  const HoleStats({required this.par, required this.handicap});

  final int par;
  final int handicap;
}
