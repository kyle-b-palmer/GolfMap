import 'dart:math' as math;

import 'package:flutter_map/flutter_map.dart';
import 'package:geotypes/geotypes.dart' as geo;
import 'package:latlong2/latlong.dart';
import 'package:turf/turf.dart' as turf;

import '../models/golf_feature.dart';

const _metersToYards = 1.09361;

Map<String, dynamic> normalizeGeometry(dynamic raw) {
  if (raw is String) {
    throw FormatException('Geometry string not yet parsed: $raw');
  }
  return Map<String, dynamic>.from(raw as Map);
}

void _walkCoordinates(dynamic coords, void Function(double lng, double lat) emit) {
  if (coords is! List || coords.isEmpty) return;

  if (coords[0] is num) {
    emit((coords[0] as num).toDouble(), (coords[1] as num).toDouble());
    return;
  }

  for (final part in coords) {
    _walkCoordinates(part, emit);
  }
}

List<LatLng> allPointsFromGeometry(Map<String, dynamic> geometry) {
  final points = <LatLng>[];
  _walkCoordinates(geometry['coordinates'], (lng, lat) {
    points.add(LatLng(lat, lng));
  });
  return points;
}

List<LatLng> latLngRingFromCoords(List<dynamic> ring) {
  return ring
      .map((coord) => LatLng(
            (coord[1] as num).toDouble(),
            (coord[0] as num).toDouble(),
          ))
      .toList();
}

List<List<LatLng>> ringsFromGeometry(Map<String, dynamic> geometry) {
  final type = geometry['type'] as String?;
  final coords = geometry['coordinates'];

  if (type == 'Polygon' && coords is List) {
    return coords
        .map((ring) => latLngRingFromCoords(ring as List<dynamic>))
        .toList();
  }

  if (type == 'MultiPolygon' && coords is List) {
    final rings = <List<LatLng>>[];
    for (final polygon in coords) {
      if (polygon is List && polygon.isNotEmpty) {
        rings.add(latLngRingFromCoords(polygon.first as List<dynamic>));
      }
    }
    return rings;
  }

  return [];
}

List<List<LatLng>> lineStringsFromGeometry(Map<String, dynamic> geometry) {
  final type = geometry['type'] as String?;
  final coords = geometry['coordinates'];

  if (type == 'LineString' && coords is List) {
    final line = latLngRingFromCoords(coords);
    return line.length >= 2 ? [line] : [];
  }

  return [];
}

LatLng? latLngFromGeometry(Map<String, dynamic> geometry) {
  final type = geometry['type'] as String?;
  final coords = geometry['coordinates'];

  if (type == 'Point' && coords is List && coords.length >= 2) {
    return LatLng(
      (coords[1] as num).toDouble(),
      (coords[0] as num).toDouble(),
    );
  }

  final points = allPointsFromGeometry(geometry);
  if (points.isEmpty) return null;

  if (type == 'LineString') {
    return points[points.length ~/ 2];
  }

  final centroid = centroidOfFeature(geometry);
  if (centroid == null) return null;
  return LatLng(centroid[1], centroid[0]);
}

List<double>? centroidOfFeature(Map<String, dynamic> geometry) {
  try {
    final feature = turf.Feature(
      geometry: _geometryFromMap(geometry),
      properties: {},
    );
    final center = turf.centroid(feature);
    final coords = center.geometry!.coordinates;
    return [coords.lng.toDouble(), coords.lat.toDouble()];
  } catch (_) {
    final points = allPointsFromGeometry(geometry);
    if (points.isEmpty) return null;
    final avgLat = points.map((p) => p.latitude).reduce((a, b) => a + b) / points.length;
    final avgLng = points.map((p) => p.longitude).reduce((a, b) => a + b) / points.length;
    return [avgLng, avgLat];
  }
}

List<double>? centroidOfGolfFeature(GolfFeature feature) =>
    centroidOfFeature(feature.geometry);

geo.GeometryObject _geometryFromMap(Map<String, dynamic> geometry) {
  final type = geometry['type'] as String;
  final coords = geometry['coordinates'];

  switch (type) {
    case 'Point':
      final c = coords as List;
      return geo.Point(
        coordinates: geo.Position(c[0].toDouble(), c[1].toDouble()),
      );
    case 'LineString':
      return geo.LineString(
        coordinates: (coords as List)
            .map(
              (c) => geo.Position(
                (c[0] as num).toDouble(),
                (c[1] as num).toDouble(),
              ),
            )
            .toList(),
      );
    case 'Polygon':
      return geo.Polygon(
        coordinates: (coords as List)
            .map(
              (ring) => (ring as List)
                  .map(
                    (c) => geo.Position(
                      (c[0] as num).toDouble(),
                      (c[1] as num).toDouble(),
                    ),
                  )
                  .toList(),
            )
            .toList(),
      );
    case 'MultiPolygon':
      return geo.MultiPolygon(
        coordinates: (coords as List)
            .map(
              (poly) => (poly as List)
                  .map(
                    (ring) => (ring as List)
                        .map(
                          (c) => geo.Position(
                            (c[0] as num).toDouble(),
                            (c[1] as num).toDouble(),
                          ),
                        )
                        .toList(),
                  )
                  .toList(),
            )
            .toList(),
      );
    default:
      throw UnsupportedError('Unsupported geometry type: $type');
  }
}

geo.Point _pointFromLatLng(LatLng point) {
  return geo.Point(
    coordinates: geo.Position(point.longitude, point.latitude),
  );
}

double bearingBetween(LatLng from, LatLng to) {
  return turf.bearing(_pointFromLatLng(from), _pointFromLatLng(to)).toDouble();
}

double distanceMeters(LatLng from, LatLng to) {
  return turf
      .distance(_pointFromLatLng(from), _pointFromLatLng(to), turf.Unit.meters)
      .toDouble();
}

int metersToYards(double meters) => (meters * _metersToYards).round();

int metersToYardsSigned(double meters) {
  final yards = (meters.abs() * _metersToYards).round();
  return meters < 0 ? -yards : yards;
}

LatLngBounds? boundsForFeatures(List<GolfFeature> features) {
  final points = <LatLng>[];
  for (final feature in features) {
    points.addAll(allPointsFromGeometry(feature.geometry));
  }
  if (points.isEmpty) return null;
  return LatLngBounds.fromPoints(points);
}

LatLng? centerForFeatures(List<GolfFeature> features) {
  final points = <LatLng>[];
  for (final feature in features) {
    points.addAll(allPointsFromGeometry(feature.geometry));
  }
  if (points.isEmpty) return null;
  final avgLat = points.map((p) => p.latitude).reduce((a, b) => a + b) / points.length;
  final avgLng = points.map((p) => p.longitude).reduce((a, b) => a + b) / points.length;
  return LatLng(avgLat, avgLng);
}

class HoleOrientation {
  const HoleOrientation({required this.tee, required this.green});

  final LatLng tee;
  final LatLng green;
}

double _minDistanceMeters(LatLng point, List<LatLng> targets) {
  var min = double.infinity;
  for (final target in targets) {
    final d = distanceMeters(point, target);
    if (d < min) min = d;
  }
  return min;
}

/// Tee at bottom of screen, green at top — flutter_map rotation is opposite
/// Mapbox bearing (clockwise map rotation vs direction at top of viewport).
double mapRotationForHole(LatLng tee, LatLng green) {
  final bearing = bearingBetween(tee, green);
  return (360 - bearing) % 360;
}

HoleOrientation? holeOrientationForFeatures(List<GolfFeature> features) {
  final teePoints = features
      .where((f) => f.featureType == 'tee')
      .map((f) => latLngFromGeometry(f.geometry))
      .whereType<LatLng>()
      .toList();

  final greenPoints = features
      .where((f) => f.featureType == 'green')
      .map((f) => latLngFromGeometry(f.geometry))
      .whereType<LatLng>()
      .toList();

  for (final hole in features.where((f) => f.featureType == 'hole')) {
    final line = allPointsFromGeometry(hole.geometry);
    if (line.length >= 2) {
      final start = line.first;
      final end = line.last;

      if (teePoints.isNotEmpty) {
        final startNearTee = _minDistanceMeters(start, teePoints) <=
            _minDistanceMeters(end, teePoints);
        return HoleOrientation(
          tee: startNearTee ? start : end,
          green: startNearTee ? end : start,
        );
      }

      if (greenPoints.isNotEmpty) {
        final startNearGreen = _minDistanceMeters(start, greenPoints) <=
            _minDistanceMeters(end, greenPoints);
        return HoleOrientation(
          tee: startNearGreen ? end : start,
          green: startNearGreen ? start : end,
        );
      }

      return HoleOrientation(tee: start, green: end);
    }
  }

  if (teePoints.isNotEmpty && greenPoints.isNotEmpty) {
    var bestTee = teePoints.first;
    var bestGreen = greenPoints.first;
    var bestSeparation = 0.0;

    for (final tee in teePoints) {
      for (final green in greenPoints) {
        final separation = distanceMeters(tee, green);
        if (separation > bestSeparation) {
          bestSeparation = separation;
          bestTee = tee;
          bestGreen = green;
        }
      }
    }

    return HoleOrientation(tee: bestTee, green: bestGreen);
  }

  return null;
}

LatLng? greenCenterForHole(List<GolfFeature> holeFeatures) {
  final greens = holeFeatures.where((f) => f.featureType == 'green').toList();
  if (greens.isEmpty) return null;

  GolfFeature? primaryGreen;
  var largest = 0;
  for (final green in greens) {
    final pointCount = allPointsFromGeometry(green.geometry).length;
    if (pointCount > largest) {
      largest = pointCount;
      primaryGreen = green;
    }
  }

  if (primaryGreen == null) return null;
  final centroid = centroidOfFeature(primaryGreen.geometry);
  if (centroid == null) return null;
  return LatLng(centroid[1], centroid[0]);
}

/// Outer boundary rings for a hole — fairway outline, or convex hull fallback.
List<List<LatLng>> holeBoundaryRings(
  List<GolfFeature> features,
  String? course,
  String hole, {
  required bool activeOnly,
}) {
  final rings = <List<LatLng>>[];

  for (final fairway in features.where((f) => f.featureType == 'fairway')) {
    if (activeOnly && !fairway.isActive(course, hole)) continue;
    for (final ring in ringsFromGeometry(fairway.geometry)) {
      if (ring.length >= 3) rings.add(ring);
    }
  }
  if (rings.isNotEmpty) return rings;

  final points = <LatLng>[];
  for (final type in ['fairway', 'green', 'tee']) {
    for (final feature in features.where((f) => f.featureType == type)) {
      if (activeOnly && !feature.isActive(course, hole)) continue;
      points.addAll(allPointsFromGeometry(feature.geometry));
    }
  }

  final hull = _convexHull(points);
  if (hull.length >= 3) rings.add(hull);
  return rings;
}

List<LatLng> _convexHull(List<LatLng> input) {
  if (input.length <= 2) return input;

  final points = [...input]
    ..sort((a, b) {
      final latCmp = a.latitude.compareTo(b.latitude);
      return latCmp != 0 ? latCmp : a.longitude.compareTo(b.longitude);
    });

  double cross(LatLng o, LatLng a, LatLng b) {
    return (a.longitude - o.longitude) * (b.latitude - o.latitude) -
        (a.latitude - o.latitude) * (b.longitude - o.longitude);
  }

  final lower = <LatLng>[];
  for (final p in points) {
    while (lower.length >= 2 &&
        cross(lower[lower.length - 2], lower.last, p) <= 0) {
      lower.removeLast();
    }
    lower.add(p);
  }

  final upper = <LatLng>[];
  for (final p in points.reversed) {
    while (upper.length >= 2 &&
        cross(upper[upper.length - 2], upper.last, p) <= 0) {
      upper.removeLast();
    }
    upper.add(p);
  }

  lower.removeLast();
  upper.removeLast();
  return [...lower, ...upper];
}

/// Elliptical ring around a hole aligned tee → green (tees, fairway, bunkers, green).
List<LatLng> holeEncirclementRing(
  List<GolfFeature> features,
  String? course,
  String hole,
) {
  final holeFeatures =
      features.where((f) => f.isActive(course, hole)).toList();

  final points = <LatLng>[];
  for (final type in ['tee', 'fairway', 'green', 'bunker']) {
    for (final feature in holeFeatures.where((f) => f.featureType == type)) {
      points.addAll(allPointsFromGeometry(feature.geometry));
    }
  }
  if (points.length < 2) return const [];

  final green = greenCenterForHole(holeFeatures);
  final tee = longestTeeForHole(holeFeatures);
  if (green == null || tee == null) {
    final hull = _convexHull(points);
    return hull.length >= 3 ? hull : const [];
  }

  final axisBearing = bearingBetween(tee, green);
  final axisCenter = LatLng(
    (tee.latitude + green.latitude) / 2,
    (tee.longitude + green.longitude) / 2,
  );

  var minAlong = double.infinity;
  var maxAlong = -double.infinity;
  var maxLateral = 0.0;

  for (final point in points) {
    final dist = distanceMeters(axisCenter, point);
    final pointBearing = bearingBetween(axisCenter, point);
    final along =
        dist * math.cos(_bearingDiffRadians(axisBearing, pointBearing));
    final lateral = dist *
        math.sin(_bearingDiffRadians(axisBearing, pointBearing)).abs();

    if (along < minAlong) minAlong = along;
    if (along > maxAlong) maxAlong = along;
    if (lateral > maxLateral) maxLateral = lateral;
  }

  const alongPadMeters = 10.0;
  const lateralPadMeters = 8.0;
  final semiMajor = (maxAlong - minAlong) / 2 + alongPadMeters;
  final semiMinor = maxLateral + lateralPadMeters;
  final center = destinationFromBearing(
    axisCenter,
    axisBearing,
    (minAlong + maxAlong) / 2,
  );

  if (semiMajor < 15 || semiMinor < 10) return const [];

  const steps = 72;
  final ring = <LatLng>[];
  for (var i = 0; i <= steps; i++) {
    final theta = 2 * math.pi * i / steps;
    final alongM = semiMajor * math.cos(theta);
    final lateralM = semiMinor * math.sin(theta);

    final onAxis = destinationFromBearing(center, axisBearing, alongM);
    ring.add(destinationFromBearing(onAxis, axisBearing + 90, lateralM));
  }

  return ring;
}

double _bearingDiffRadians(double fromBearing, double toBearing) {
  var diff = (toBearing - fromBearing) % 360;
  if (diff > 180) diff -= 360;
  if (diff < -180) diff += 360;
  return diff * math.pi / 180;
}

List<LatLng> _greenBoundarySamplePoints(List<GolfFeature> holeFeatures) {
  final points = <LatLng>[];
  for (final green in holeFeatures.where((f) => f.featureType == 'green')) {
    for (final ring in ringsFromGeometry(green.geometry)) {
      if (ring.isEmpty) continue;
      points.addAll(ring);
      final limit = ring.length > 1 && ring.first == ring.last
          ? ring.length - 1
          : ring.length;
      for (var i = 0; i < limit; i++) {
        final a = ring[i];
        final b = ring[(i + 1) % ring.length];
        points.add(
          LatLng(
            (a.latitude + b.latitude) / 2,
            (a.longitude + b.longitude) / 2,
          ),
        );
      }
    }
  }
  return points;
}

double _frontOfGreenMeters(LatLng from, List<GolfFeature> holeFeatures) {
  final fromPoint = _pointFromLatLng(from);
  var minMeters = double.infinity;

  for (final green in holeFeatures.where((f) => f.featureType == 'green')) {
    for (final ring in ringsFromGeometry(green.geometry)) {
      if (ring.length < 2) continue;
      final limit = ring.length > 1 && ring.first == ring.last
          ? ring.length - 1
          : ring.length;

      for (var i = 0; i < limit; i++) {
        final a = ring[i];
        final b = ring[(i + 1) % ring.length];
        final line = geo.LineString(
          coordinates: [
            geo.Position(a.longitude, a.latitude),
            geo.Position(b.longitude, b.latitude),
          ],
        );
        final segmentMeters = turf
            .pointToLineDistance(
              fromPoint,
              line,
              unit: turf.Unit.meters,
            )
            .toDouble();
        if (segmentMeters < minMeters) minMeters = segmentMeters;
      }
    }
  }

  return minMeters.isFinite ? minMeters : 0;
}

double _backOfGreenMeters(
  LatLng from,
  LatLng greenCenter,
  List<GolfFeature> holeFeatures,
) {
  final approach = bearingBetween(from, greenCenter);
  var maxAlong = 0.0;

  for (final point in _greenBoundarySamplePoints(holeFeatures)) {
    final dist = distanceMeters(from, point);
    final pointBearing = bearingBetween(from, point);
    final along = dist * math.cos(_bearingDiffRadians(approach, pointBearing));
    if (along > maxAlong) maxAlong = along;
  }

  return maxAlong;
}

GreenYardages greenDistancesFromPoint(
  LatLng from,
  List<GolfFeature> holeFeatures,
) {
  final center = greenCenterForHole(holeFeatures);
  if (center == null) {
    return const GreenYardages(front: 0, middle: 0, back: 0);
  }

  final front = metersToYards(_frontOfGreenMeters(from, holeFeatures));
  final middle = metersToYards(distanceMeters(from, center));
  final back = metersToYards(_backOfGreenMeters(from, center, holeFeatures));

  return GreenYardages(
    front: front,
    middle: middle,
    back: back,
  );
}

double _distanceToFeatureEdgeMeters(LatLng from, Map<String, dynamic> geometry) {
  final fromPoint = _pointFromLatLng(from);
  var minMeters = double.infinity;

  for (final ring in ringsFromGeometry(geometry)) {
    if (ring.length < 2) continue;
    final limit = ring.length > 1 && ring.first == ring.last
        ? ring.length - 1
        : ring.length;

    for (var i = 0; i < limit; i++) {
      final a = ring[i];
      final b = ring[(i + 1) % ring.length];
      final line = geo.LineString(
        coordinates: [
          geo.Position(a.longitude, a.latitude),
          geo.Position(b.longitude, b.latitude),
        ],
      );
      final segmentMeters = turf
          .pointToLineDistance(
            fromPoint,
            line,
            unit: turf.Unit.meters,
          )
          .toDouble();
      if (segmentMeters < minMeters) minMeters = segmentMeters;
    }
  }

  return minMeters;
}

/// Signed edge distance: positive when bunker is ahead toward the green, negative when behind.
double _signedDistanceToBunkerEdgeMeters(
  LatLng from,
  GolfFeature bunker,
  LatLng greenCenter,
) {
  final edgeMeters = _distanceToFeatureEdgeMeters(from, bunker.geometry);
  if (!edgeMeters.isFinite) return 0;

  final bunkerPoint = latLngFromGeometry(bunker.geometry);
  if (bunkerPoint == null) return edgeMeters;

  final approach = bearingBetween(from, greenCenter);
  final toBunker = bearingBetween(from, bunkerPoint);
  final along = distanceMeters(from, bunkerPoint) *
      math.cos(_bearingDiffRadians(approach, toBunker));

  return along >= 0 ? edgeMeters : -edgeMeters;
}

List<BunkerDistance> bunkerDistancesFromPoint(
  LatLng from,
  List<GolfFeature> holeFeatures,
) {
  final greenCenter = greenCenterForHole(holeFeatures);
  if (greenCenter == null) return const [];

  final bunkers = holeFeatures.where((f) => f.featureType == 'bunker').toList();
  final results = <BunkerDistance>[];

  for (var i = 0; i < bunkers.length; i++) {
    final bunker = bunkers[i];
    final meters =
        _signedDistanceToBunkerEdgeMeters(from, bunker, greenCenter);
    if (!meters.isFinite) continue;

    final name = bunker.name?.trim();
    final label = (name != null && name.isNotEmpty) ? name : 'Bunker ${i + 1}';
    results.add(
      BunkerDistance(label: label, yards: metersToYardsSigned(meters)),
    );
  }

  results.sort((a, b) => a.yards.abs().compareTo(b.yards.abs()));
  return results;
}

/// Back tee: the tee box farthest from the green on this hole.
LatLng? longestTeeForHole(List<GolfFeature> holeFeatures) {
  final greenCenter = greenCenterForHole(holeFeatures);
  final teePoints = holeFeatures
      .where((f) => f.featureType == 'tee')
      .map((f) => latLngFromGeometry(f.geometry))
      .whereType<LatLng>()
      .toList();

  if (teePoints.isEmpty) {
    return holeOrientationForFeatures(holeFeatures)?.tee;
  }
  if (greenCenter == null) return teePoints.first;

  var farthestTee = teePoints.first;
  var farthestMeters = 0.0;
  for (final tee in teePoints) {
    final meters = distanceMeters(tee, greenCenter);
    if (meters > farthestMeters) {
      farthestMeters = meters;
      farthestTee = tee;
    }
  }
  return farthestTee;
}

class TeeOption {
  const TeeOption({
    required this.featureId,
    required this.point,
    required this.label,
  });

  final dynamic featureId;
  final LatLng point;
  final String label;
}

List<String> _teeLabels(int count) {
  if (count == 1) return ['Tee'];
  if (count == 2) return ['Back', 'Front'];
  if (count == 3) return ['Back', 'Middle', 'Front'];
  return [for (var i = 0; i < count; i++) 'Tee ${i + 1}'];
}

List<TeeOption> teeOptionsForHole(List<GolfFeature> holeFeatures) {
  final greenCenter = greenCenterForHole(holeFeatures);
  final tees = holeFeatures.where((f) => f.featureType == 'tee').toList();

  final ranked = <({dynamic id, LatLng point, double dist})>[];
  for (final tee in tees) {
    final point = latLngFromGeometry(tee.geometry);
    if (point == null) continue;
    final dist = greenCenter != null ? distanceMeters(point, greenCenter) : 0.0;
    ranked.add((id: tee.id, point: point, dist: dist));
  }

  ranked.sort((a, b) => b.dist.compareTo(a.dist));
  final labels = _teeLabels(ranked.length);

  return [
    for (var i = 0; i < ranked.length; i++)
      TeeOption(
        featureId: ranked[i].id,
        point: ranked[i].point,
        label: labels[i],
      ),
  ];
}

LatLng? teePointById(List<GolfFeature> holeFeatures, dynamic featureId) {
  for (final feature in holeFeatures) {
    if (feature.id == featureId && feature.featureType == 'tee') {
      return latLngFromGeometry(feature.geometry);
    }
  }
  return null;
}

TeeOption? teeOptionByLabel(List<GolfFeature> holeFeatures, String label) {
  for (final option in teeOptionsForHole(holeFeatures)) {
    if (option.label == label) return option;
  }
  return null;
}

/// Tee-to-green yardage for the selected tee box on this hole.
int? holeYardageFromSelectedTee(
  List<GolfFeature> holeFeatures,
  dynamic selectedTeeFeatureId,
) {
  final teePoint = teePointById(holeFeatures, selectedTeeFeatureId);
  final greenCenter = greenCenterForHole(holeFeatures);
  if (teePoint == null || greenCenter == null) return null;
  return metersToYards(distanceMeters(teePoint, greenCenter));
}

/// Shot distance only makes sense when the device is on/near the hole.
bool isUserNearHole(
  LatLng user,
  List<GolfFeature> holeFeatures, {
  double maxYards = 1200,
}) {
  final maxMeters = maxYards / _metersToYards;
  var nearestMeters = double.infinity;

  for (final feature in holeFeatures) {
    for (final point in allPointsFromGeometry(feature.geometry)) {
      final meters = distanceMeters(user, point);
      if (meters < nearestMeters) nearestMeters = meters;
    }
  }

  return nearestMeters <= maxMeters;
}

int? shotDistanceYards(
  LatLng? user,
  LatLng tap,
  List<GolfFeature> holeFeatures, {
  dynamic selectedTeeFeatureId,
}) {
  final origin = shotDistanceOrigin(
    user,
    holeFeatures,
    selectedTeeFeatureId: selectedTeeFeatureId,
  );
  if (origin == null) return null;
  return metersToYards(distanceMeters(origin, tap));
}

LatLng? shotDistanceOrigin(
  LatLng? user,
  List<GolfFeature> holeFeatures, {
  dynamic selectedTeeFeatureId,
}) {
  if (user != null && isUserNearHole(user, holeFeatures)) {
    return user;
  }

  if (selectedTeeFeatureId != null) {
    final selected = teePointById(holeFeatures, selectedTeeFeatureId);
    if (selected != null) return selected;
  }

  return longestTeeForHole(holeFeatures);
}

bool isUsingGpsForShot(LatLng? user, List<GolfFeature> holeFeatures) {
  return user != null && isUserNearHole(user, holeFeatures);
}

const kMaxPlannedShotYards = 250;
const kMaxFollowUpPlannedShotYards = 200;

class PlannedShotSegment {
  const PlannedShotSegment({
    required this.shotNumber,
    required this.from,
    required this.to,
    required this.yards,
  });

  final int shotNumber;
  final LatLng from;
  final LatLng to;
  final int yards;
}

LatLng destinationFromBearing(LatLng from, double bearingDeg, double meters) {
  const earthRadius = 6378137.0;
  final bearing = bearingDeg * math.pi / 180;
  final lat1 = from.latitude * math.pi / 180;
  final lng1 = from.longitude * math.pi / 180;
  final angular = meters / earthRadius;

  final lat2 = math.asin(
    math.sin(lat1) * math.cos(angular) +
        math.cos(lat1) * math.sin(angular) * math.cos(bearing),
  );
  final lng2 = lng1 +
      math.atan2(
        math.sin(bearing) * math.sin(angular) * math.cos(lat1),
        math.cos(angular) - math.sin(lat1) * math.sin(lat2),
      );

  return LatLng(lat2 * 180 / math.pi, lng2 * 180 / math.pi);
}

bool _isPointInRing(LatLng point, List<LatLng> ring) {
  var inside = false;
  for (var i = 0, j = ring.length - 1; i < ring.length; j = i++) {
    final yi = ring[i].latitude;
    final yj = ring[j].latitude;
    final xi = ring[i].longitude;
    final xj = ring[j].longitude;
    final intersects = ((yi > point.latitude) != (yj > point.latitude)) &&
        (point.longitude <
            (xj - xi) * (point.latitude - yi) / (yj - yi) + xi);
    if (intersects) inside = !inside;
  }
  return inside;
}

bool isPointInGolfFeature(LatLng point, GolfFeature feature) {
  for (final ring in ringsFromGeometry(feature.geometry)) {
    if (ring.length >= 3 && _isPointInRing(point, ring)) return true;
  }
  return false;
}

bool isPointInFairway(LatLng point, List<GolfFeature> holeFeatures) {
  for (final feature in holeFeatures.where((f) => f.featureType == 'fairway')) {
    if (isPointInGolfFeature(point, feature)) return true;
  }
  return false;
}

bool isPointInGreen(LatLng point, List<GolfFeature> holeFeatures) {
  for (final feature in holeFeatures.where((f) => f.featureType == 'green')) {
    if (isPointInGolfFeature(point, feature)) return true;
  }
  return false;
}

double _alongTrackMeters(LatLng from, double approachBearing, LatLng point) {
  final dist = distanceMeters(from, point);
  final bearing = bearingBetween(from, point);
  return dist * math.cos(_bearingDiffRadians(approachBearing, bearing));
}

/// Center of the fairway cross-section at a given along-track distance.
LatLng? _fairwayCenterAtAlongDistance(
  LatLng from,
  double approachBearing,
  double targetAlongMeters,
  List<GolfFeature> holeFeatures,
) {
  final onLine = destinationFromBearing(from, approachBearing, targetAlongMeters);
  final perpPlus = approachBearing + 90;
  final perpMinus = approachBearing - 90;

  LatLng? edgePlus;
  for (var lateral = 0.0; lateral <= 100.0; lateral += 2.0) {
    final point = destinationFromBearing(onLine, perpPlus, lateral);
    if (isPointInFairway(point, holeFeatures)) {
      edgePlus = point;
    } else if (edgePlus != null) {
      break;
    }
  }

  LatLng? edgeMinus;
  for (var lateral = 0.0; lateral <= 100.0; lateral += 2.0) {
    final point = destinationFromBearing(onLine, perpMinus, lateral);
    if (isPointInFairway(point, holeFeatures)) {
      edgeMinus = point;
    } else if (edgeMinus != null) {
      break;
    }
  }

  if (edgePlus != null && edgeMinus != null) {
    return LatLng(
      (edgePlus.latitude + edgeMinus.latitude) / 2,
      (edgePlus.longitude + edgeMinus.longitude) / 2,
    );
  }

  if (edgePlus != null) return edgePlus;
  if (edgeMinus != null) return edgeMinus;
  if (isPointInFairway(onLine, holeFeatures)) return onLine;

  return null;
}

/// Furthest fairway center toward [green] within [maxShotYards].
LatLng? optimalFairwayLanding({
  required LatLng from,
  required LatLng green,
  required List<GolfFeature> holeFeatures,
  int maxShotYards = kMaxPlannedShotYards,
}) {
  final maxMeters = maxShotYards / _metersToYards;
  final distToGreen = distanceMeters(from, green);
  if (distToGreen < 8) return null;

  final approach = bearingBetween(from, green);
  final capMeters = math.min(maxMeters, distToGreen);

  if (distToGreen <= maxMeters) {
    if (isPointInGreen(green, holeFeatures) ||
        isPointInFairway(green, holeFeatures)) {
      return green;
    }
  }

  for (var targetAlong = capMeters; targetAlong >= 15; targetAlong -= 8) {
    final center = _fairwayCenterAtAlongDistance(
      from,
      approach,
      targetAlong,
      holeFeatures,
    );
    if (center == null) continue;
    if (!isPointInFairway(center, holeFeatures) &&
        !isPointInGreen(center, holeFeatures)) {
      continue;
    }

    final shotMeters = distanceMeters(from, center);
    if (shotMeters > maxMeters + 2) continue;

    final along = _alongTrackMeters(from, approach, center);
    if (along <= 0) continue;

    return center;
  }

  final fallback = destinationFromBearing(from, approach, capMeters);
  if (isPointInFairway(fallback, holeFeatures) ||
      isPointInGreen(fallback, holeFeatures)) {
    return fallback;
  }

  return _fairwayCenterAtAlongDistance(from, approach, capMeters * 0.85, holeFeatures) ??
      fallback;
}

List<PlannedShotSegment> plannedShotSegments({
  required LatLng start,
  required LatLng green,
  required List<GolfFeature> holeFeatures,
}) {
  final segments = <PlannedShotSegment>[];
  var current = start;
  var shotNumber = 1;

  for (var i = 0; i < 6; i++) {
    if (distanceMeters(current, green) < 10) break;

    final maxShotYards =
        shotNumber == 1 ? kMaxPlannedShotYards : kMaxFollowUpPlannedShotYards;

    final target = optimalFairwayLanding(
      from: current,
      green: green,
      holeFeatures: holeFeatures,
      maxShotYards: maxShotYards,
    );
    if (target == null) break;

    final yards = metersToYards(distanceMeters(current, target));
    if (segments.isNotEmpty && yards < 18) break;

    segments.add(
      PlannedShotSegment(
        shotNumber: shotNumber++,
        from: current,
        to: target,
        yards: yards,
      ),
    );

    if (distanceMeters(target, green) < 12) break;
    current = target;
  }

  return segments;
}
