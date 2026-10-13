// Exports expected outputs of the Dart calculation code so the native Swift
// port can be checked against the same inputs.
//
// Run: flutter test test/parity/export_parity_fixtures_test.dart
// Output: native_ios/GolfKit/Tests/GolfCoreTests/Fixtures/parity_v1.json
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:golf_map_flutter/models/club_bag.dart';
import 'package:golf_map_flutter/models/golf_feature.dart';
import 'package:golf_map_flutter/models/saved_round.dart';
import 'package:golf_map_flutter/services/club_suggestion_service.dart';
import 'package:golf_map_flutter/services/golf_data_service.dart';
import 'package:golf_map_flutter/services/round_storage_service.dart';
import 'package:golf_map_flutter/services/shot_dispersion_service.dart';
import 'package:golf_map_flutter/utils/geo_utils.dart';
import 'package:golf_map_flutter/utils/weather_adjustment.dart';
import 'package:latlong2/latlong.dart';

const _assetPath = 'assets/courses/san_antonio_courses.json';
const _outputPath =
    'native_ios/GolfKit/Tests/GolfCoreTests/Fixtures/parity_v1.json';

List<GolfFeature> _parseFeatureRows(List<Map<String, dynamic>> rows) {
  return rows.map((item) {
    final rawGeom = item['geom'];
    final geometry = rawGeom is String
        ? Map<String, dynamic>.from(
            (jsonDecode(rawGeom) as Map).cast<String, dynamic>(),
          )
        : Map<String, dynamic>.from(rawGeom as Map);
    geometry.remove('crs');

    var holeNumber = item['hole_number'];
    if (holeNumber == null || holeNumber.toString().toLowerCase() == 'null') {
      holeNumber = null;
    }

    return GolfFeature(
      id: item['id'],
      featureType: item['feature_type'] as String?,
      holeNumber: holeNumber?.toString(),
      name: item['name'] as String?,
      par: item['par'] as int?,
      handicap: item['handicap'] as int?,
      courseName: item['course_name'] as String?,
      geometry: geometry,
    );
  }).toList();
}

List<double> _ll(LatLng p) => [p.latitude, p.longitude];

class _FakeRoundStorage extends RoundStorageService {
  _FakeRoundStorage(this.rounds);

  final List<SavedRound> rounds;

  @override
  Future<List<SavedRound>> loadRounds() async => rounds;
}

Map<String, dynamic> _pointCase(
  String label,
  LatLng point,
  List<GolfFeature> features,
  List<GolfFeature> holeFeatures,
  String course,
  String hole,
) {
  final green = greenDistancesFromPoint(point, holeFeatures);
  final bunkers = bunkerDistancesFromPoint(point, holeFeatures);
  final back = backOfGreenPoint(point, holeFeatures);
  return {
    'label': label,
    'point': _ll(point),
    'green': [green.front, green.middle, green.back],
    'backOfGreen': back == null ? null : _ll(back),
    'bunkers': [
      for (final b in bunkers)
        {
          'label': b.label,
          'yards': b.yards,
          'point': b.point == null ? null : _ll(b.point!),
        },
    ],
    'nearHole': isUserNearHole(point, holeFeatures),
    'onTeeBox': isUserOnTeeBox(point, holeFeatures),
    'inFairway': isPointInFairway(point, holeFeatures),
    'inGreen': isPointInGreen(point, holeFeatures),
    'inEncirclement': isPointInHoleEncirclement(point, features, course, hole),
    'gpsInPlayArea': isGpsWithinHolePlayArea(point, features, course, hole),
    'outsideEncirclementMeters':
        distanceOutsideHoleEncirclementMeters(point, features, course, hole),
  };
}

Map<String, dynamic> _holeCase(
  List<GolfFeature> features,
  GolfDataService dataService,
  String course,
  String hole,
) {
  final holeFeatures =
      features.where((f) => f.isActive(course, hole)).toList();
  final stats = dataService.statsForHole(features, course, hole);
  final greenCenter = greenCenterForHole(holeFeatures);
  final longestTee = longestTeeForHole(holeFeatures);
  final orientation = holeOrientationForFeatures(holeFeatures);
  final tees = teeOptionsForHole(holeFeatures);
  final ring = holeEncirclementRing(features, course, hole);

  final points = <Map<String, dynamic>>[];
  for (final tee in tees) {
    points.add(
      _pointCase('tee:${tee.label}', tee.point, features, holeFeatures,
          course, hole),
    );
  }
  if (longestTee != null && greenCenter != null) {
    final bearing = bearingBetween(longestTee, greenCenter);
    final total = distanceMeters(longestTee, greenCenter);
    for (final fraction in [0.25, 0.5, 0.75, 0.9]) {
      final p = destinationFromBearing(longestTee, bearing, total * fraction);
      points.add(
        _pointCase('along:$fraction', p, features, holeFeatures, course, hole),
      );
    }
    final mid = destinationFromBearing(longestTee, bearing, total * 0.5);
    for (final lateral in [-35.0, 35.0]) {
      final p = destinationFromBearing(mid, bearing + 90, lateral);
      points.add(
        _pointCase('lateral:$lateral', p, features, holeFeatures, course, hole),
      );
    }
    final behindGreen = destinationFromBearing(greenCenter, bearing, 20);
    points.add(
      _pointCase('behindGreen', behindGreen, features, holeFeatures, course,
          hole),
    );
    final far = destinationFromBearing(longestTee, bearing + 180, 2000);
    points.add(_pointCase('far', far, features, holeFeatures, course, hole));
  }

  final planned = longestTee != null && greenCenter != null
      ? plannedShotSegments(
          start: longestTee,
          green: greenCenter,
          holeFeatures: holeFeatures,
        )
      : const <PlannedShotSegment>[];

  return {
    'course': course,
    'hole': hole,
    'featureCount': holeFeatures.length,
    'par': stats?.par,
    'handicap': stats?.handicap,
    'greenCenter': greenCenter == null ? null : _ll(greenCenter),
    'longestTee': longestTee == null ? null : _ll(longestTee),
    'orientation': orientation == null
        ? null
        : {
            'tee': _ll(orientation.tee),
            'green': _ll(orientation.green),
            'mapRotation':
                mapRotationForHole(orientation.tee, orientation.green),
          },
    'tees': [
      for (final tee in tees)
        {
          'featureId': tee.featureId,
          'label': tee.label,
          'point': _ll(tee.point),
          'holeYards': holeYardageFromSelectedTee(holeFeatures, tee.featureId),
        },
    ],
    'encirclement': {
      'count': ring.length,
      'samples': [
        for (final i in [0, 18, 36, 54])
          if (i < ring.length) _ll(ring[i]),
      ],
    },
    'plannedShots': [
      for (final s in planned)
        {
          'shotNumber': s.shotNumber,
          'from': _ll(s.from),
          'to': _ll(s.to),
          'yards': s.yards,
          'carryYards': s.carryYards,
        },
    ],
    'points': points,
  };
}

List<Map<String, dynamic>> _savedRoundInputs() => [
      {
        'name': 'modern_full',
        'json': {
          'id': 'round-modern',
          'courseName': 'Brackenridge Golf Course',
          'playedAt': '2026-09-20T08:15:30.123456',
          'scores': {'1': 5, '2': 4, '3': 0},
          'putts': {'1': 2, '2': 1},
          'pinnedShots': {
            '1': [
              {
                'shotNumber': 2,
                'latitude': 29.46,
                'longitude': -98.47,
                'fromLatitude': 29.459,
                'fromLongitude': -98.471,
                'teeLabel': 'Back',
                'shotYards': 150,
                'yardsToPin': 40,
              },
              {
                'shotNumber': 1,
                'latitude': 29.459,
                'longitude': -98.471,
                'fromLatitude': 29.457,
                'fromLongitude': -98.473,
                'shotYards': 240,
                'pinType': 'lostBall',
              },
            ],
          },
          'measurementChains': {
            '2': [
              {
                'latitude': 29.47,
                'longitude': -98.48,
                'segmentYards': 120,
                'shotNumber': 2,
              },
              {
                'latitude': 29.469,
                'longitude': -98.479,
                'segmentYards': 210,
                'shotNumber': 1,
              },
            ],
          },
          'lockedHoles': ['2', '1'],
        },
      },
      {
        'name': 'legacy_pins_no_locks',
        'json': {
          'id': 'round-legacy-pins',
          'courseName': 'Olmos Basin Golf Course',
          'playedAt': '2025-04-02T14:00:00.000Z',
          'scores': {'1': 4.0, '2': 'bad', '3': 6},
          'pinnedShots': {
            '3': [
              {
                'shotNumber': 1,
                'latitude': 29.48,
                'longitude': -98.48,
                'yardsFromTee': 222,
              },
              {'shotNumber': 'oops', 'latitude': 1},
            ],
          },
        },
      },
      {
        'name': 'legacy_scores_only',
        'json': {
          'id': 'round-legacy-scores',
          'courseName': 'Yaupon Golf Course',
          'playedAt': '2024-06-01T09:30:00',
          'scores': {'5': 3, '6': 5},
        },
      },
      {
        'name': 'empty_locks_list',
        'json': {
          'id': 'round-empty-locks',
          'courseName': 'Estes Park Golf Course',
          'playedAt': '2026-01-01T00:00:00.5',
          'scores': {'1': 4},
          'pinnedShots': {
            '1': [
              {'shotNumber': 1, 'latitude': 40.0, 'longitude': -105.0},
            ],
          },
          'lockedHoles': <String>[],
        },
      },
    ];

void main() {
  test('export parity fixtures', () async {
    final rows = (jsonDecode(File(_assetPath).readAsStringSync()) as List)
        .cast<Map<String, dynamic>>();
    final features = _parseFeatureRows(rows);
    final dataService = GolfDataService();

    final catalog = dataService.buildCourseCatalog(features);
    final courses = <Map<String, dynamic>>[];
    final holes = <Map<String, dynamic>>[];
    for (final entry in catalog) {
      final courseFeatures =
          features.where((f) => f.matchesCourse(entry.name)).toList();
      final holeNumbers = dataService.holesForCourse(features, entry.name);
      final typeCounts = <String, int>{};
      for (final f in courseFeatures) {
        final key = f.featureType ?? 'null';
        typeCounts[key] = (typeCounts[key] ?? 0) + 1;
      }
      courses.add({
        'name': entry.name,
        'state': entry.state,
        'stateCode': entry.stateCode,
        'city': entry.city,
        'latitude': entry.latitude,
        'longitude': entry.longitude,
        'featureCount': courseFeatures.length,
        'featureTypeCounts': typeCounts,
        'holes': holeNumbers,
      });
      for (final hole in holeNumbers) {
        holes.add(_holeCase(features, dataService, entry.name, hole));
      }
    }

    final clubService = ClubSuggestionService();
    final noDriverBag = ClubBag.defaultClubs.skip(1).toList();
    final clubCases = <Map<String, dynamic>>[];
    for (var yards = -5; yards <= 280; yards += 7) {
      for (final allowDriver in [true, false]) {
        final s = clubService.suggest(yards, allowDriver: allowDriver);
        clubCases.add({
          'yards': yards,
          'allowDriver': allowDriver,
          'club': s?.club,
          'alternate': s?.alternateClub,
        });
      }
    }
    final noDriverService = ClubSuggestionService(clubs: noDriverBag);
    for (final yards in [60, 150, 240, 300]) {
      final s = noDriverService.suggest(yards);
      clubCases.add({
        'yards': yards,
        'allowDriver': true,
        'bag': 'noDriver',
        'club': s?.club,
        'alternate': s?.alternateClub,
      });
    }

    final playsLikeCases = <Map<String, dynamic>>[];
    for (final actual in [1, 95, 150, 212]) {
      for (final temp in [null, 40.0, 70.0, 98.5]) {
        for (final wind in [
          null,
          [1.5, 0.0, 0.0],
          [12.0, 180.0, 0.0],
          [12.0, 0.0, 0.0],
          [20.0, 270.0, 45.0],
        ]) {
          for (final elevation in [null, 650.0, 5280.0]) {
            final w = wind as List<double>?;
            playsLikeCases.add({
              'actual': actual,
              'temperatureF': temp,
              'windMph': w?[0],
              'windDirectionDeg': w?[1],
              'shotBearingDeg': w?[2],
              'elevationFeet': elevation,
              'expected': playsLikeYards(
                actualYards: actual,
                temperatureF: temp,
                windMph: w?[0],
                windDirectionDeg: w?[1],
                shotBearingDeg: w?[2],
                elevationFeet: elevation,
              ),
            });
          }
        }
      }
    }

    final savedRoundCases = <Map<String, dynamic>>[];
    final parsedRounds = <SavedRound>[];
    for (final input in _savedRoundInputs()) {
      final round = SavedRound.fromJson(
        Map<String, dynamic>.from(input['json'] as Map),
      );
      parsedRounds.add(round);
      savedRoundCases.add({
        'name': input['name'],
        'input': input['json'],
        'expected': round.toJson(),
        'playedAtIsUtc': round.playedAt.isUtc,
        'totalStrokes': round.totalStrokes,
        'totalPutts': round.totalPutts,
        'holesScored': round.holesScored,
        'totalPinnedShots': round.totalPinnedShots,
      });
    }

    final dispersion = await ShotDispersionService(
      storage: _FakeRoundStorage(parsedRounds),
    ).pointsForHole(courseName: 'Brackenridge Golf Course', hole: '1');

    final output = {
      'version': 1,
      'generatedFrom': 'Flutter checkpoint geo_utils/turf 0.0.12',
      'asset': _assetPath,
      'courses': courses,
      'holes': holes,
      'clubSuggestions': clubCases,
      'playsLike': playsLikeCases,
      'savedRounds': savedRoundCases,
      'dispersionBrackenridgeHole1': [
        for (final p in dispersion)
          {'latitude': p.latitude, 'longitude': p.longitude, 'weight': p.weight},
      ],
    };

    final file = File(_outputPath);
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(const JsonEncoder.withIndent(' ').convert(output));
    expect(holes, isNotEmpty);
  });
}
