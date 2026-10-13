import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../models/golf_feature.dart';
import '../utils/geo_utils.dart';

/// Fetches golf course outlines and hole geometry from OpenStreetMap.
class OsmGolfCourseService {
  OsmGolfCourseService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  static const _userAgent = 'SouthTexasGolfTracker/1.0 (course import)';
  static const _nominatimUrl = 'https://nominatim.openstreetmap.org/search';
  static const _overpassEndpoints = [
    'https://overpass.kumi.systems/api/interpreter',
    'https://overpass-api.de/api/interpreter',
    'https://maps.mail.ru/osm/tools/overpass/api/interpreter',
  ];

  Future<List<OsmGolfCourseSummary>> searchNearbyCourses({
    required double latitude,
    required double longitude,
    int radiusMeters = 15000,
  }) async {
    final query = '''
[out:json][timeout:20];
(
  way["leisure"="golf_course"](around:$radiusMeters,$latitude,$longitude);
  relation["leisure"="golf_course"](around:$radiusMeters,$latitude,$longitude);
);
out center tags bb;
''';

    return _summariesFromOverpassQuery(query);
  }

  Future<List<OsmGolfCourseSummary>> searchCoursesByName(
    String query, {
    double? latitude,
    double? longitude,
  }) async {
    final normalized = query.trim();
    if (normalized.isEmpty) return [];

    final summaries = <OsmGolfCourseSummary>[];
    final seenKeys = <String>{};

    void addSummary(OsmGolfCourseSummary? summary) {
      if (summary == null) return;
      final key = '${summary.osmType}:${summary.osmId}';
      if (seenKeys.contains(key)) return;
      seenKeys.add(key);
      summaries.add(summary);
    }

    final viewbox = latitude != null && longitude != null
        ? _viewboxAround(latitude, longitude, radiusKm: 120)
        : null;

    // Nominatim often ranks rock quarries above golf courses for queries like
    // "Quarry Golf". Try club/course variants and a nearby Overpass name search.
    for (final searchQuery in _searchQueries(normalized)) {
      final results = await _nominatimSearch(
        searchQuery,
        viewbox: viewbox,
        bounded: false,
      );
      for (final result in results) {
        addSummary(_summaryFromNominatim(result));
      }
      if (summaries.isNotEmpty) break;
    }

    if (summaries.isEmpty && latitude != null && longitude != null) {
      final nearby = await _searchNearbyCoursesByName(
        normalized,
        latitude: latitude,
        longitude: longitude,
      );
      for (final course in nearby) {
        addSummary(course);
      }
    }

    if (latitude != null && longitude != null) {
      summaries.sort((a, b) {
        final aDistance = _distanceMeters(
          latitude,
          longitude,
          a.latitude,
          a.longitude,
        );
        final bDistance = _distanceMeters(
          latitude,
          longitude,
          b.latitude,
          b.longitude,
        );
        return aDistance.compareTo(bDistance);
      });
    } else {
      summaries.sort((a, b) => a.name.compareTo(b.name));
    }

    return summaries;
  }

  Future<List<OsmGolfCourseSummary>> _searchNearbyCoursesByName(
    String query, {
    required double latitude,
    required double longitude,
    int radiusMeters = 120000,
  }) async {
    final pattern = _overpassNamePattern(query);
    if (pattern == null) return const [];

    final overpassQuery = '''
[out:json][timeout:20];
(
  way["leisure"="golf_course"]["name"~$pattern,i](around:$radiusMeters,$latitude,$longitude);
  relation["leisure"="golf_course"]["name"~$pattern,i](around:$radiusMeters,$latitude,$longitude);
);
out center tags bb;
''';

    try {
      return await _summariesFromOverpassQuery(overpassQuery);
    } catch (_) {
      return const [];
    }
  }

  Future<List<GolfFeature>> fetchCourseFeatures(OsmGolfCourseSummary course) async {
    final bounds = course.bounds;
    if (bounds == null) {
      return fetchFeaturesNear(
        latitude: course.latitude,
        longitude: course.longitude,
        radiusMeters: 1200,
        courseName: course.name,
      );
    }

    // Pad slightly so edge tees/greens are not clipped.
    final south = bounds.south - 0.0015;
    final west = bounds.west - 0.0015;
    final north = bounds.north + 0.0015;
    final east = bounds.east + 0.0015;

    final query = '''
[out:json][timeout:25];
(
  way["golf"~"^(tee|teeing_ground|fairway|green|bunker|sand_trap|hole)\$"]($south,$west,$north,$east);
  relation["type"="multipolygon"]["golf"~"^(tee|teeing_ground|fairway|green|bunker|sand_trap)\$"]($south,$west,$north,$east);
);
out geom tags;
''';

    final payload = await _runOverpassQuery(query);
    return _featuresFromElements(
      (payload['elements'] as List?)?.cast<Map<String, dynamic>>() ?? const [],
      courseName: course.name,
    );
  }

  Future<List<GolfFeature>> fetchFeaturesNear({
    required double latitude,
    required double longitude,
    int radiusMeters = 1200,
    required String courseName,
  }) async {
    final query = '''
[out:json][timeout:25];
(
  way["golf"~"^(tee|teeing_ground|fairway|green|bunker|sand_trap|hole)\$"](around:$radiusMeters,$latitude,$longitude);
  relation["type"="multipolygon"]["golf"~"^(tee|teeing_ground|fairway|green|bunker|sand_trap)\$"](around:$radiusMeters,$latitude,$longitude);
);
out geom tags;
''';

    final payload = await _runOverpassQuery(query);
    return _featuresFromElements(
      (payload['elements'] as List?)?.cast<Map<String, dynamic>>() ?? const [],
      courseName: courseName,
    );
  }

  Future<List<Map<String, dynamic>>> _nominatimSearch(
    String query, {
    OsmBounds? viewbox,
    bool bounded = false,
  }) async {
    final params = <String, String>{
      'q': query,
      'format': 'jsonv2',
      'limit': '8',
      'dedupe': '1',
      'addressdetails': '0',
      'extratags': '0',
      'namedetails': '0',
      // This app targets US courses; without this, "Quarry Golf" ranks a
      // Papua New Guinea rock quarry above San Antonio's Quarry Golf Club.
      'countrycodes': 'us',
    };

    if (viewbox != null) {
      params['viewbox'] =
          '${viewbox.west},${viewbox.north},${viewbox.east},${viewbox.south}';
      params['bounded'] = bounded ? '1' : '0';
    }

    final uri = Uri.parse(_nominatimUrl).replace(queryParameters: params);
    final response = await _client
        .get(
          uri,
          headers: {
            'User-Agent': _userAgent,
            'Accept-Language': 'en',
          },
        )
        .timeout(const Duration(seconds: 12));

    if (response.statusCode != 200) {
      throw Exception(
        'OpenStreetMap search failed (${response.statusCode}). Try again in a moment.',
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! List) return const [];

    return decoded
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .where(_isGolfCourseResult)
        .toList();
  }

  Future<List<OsmGolfCourseSummary>> _summariesFromOverpassQuery(String query) async {
    final payload = await _runOverpassQuery(query);
    final elements = (payload['elements'] as List?)?.cast<Map<String, dynamic>>() ??
        const [];

    final summaries = <OsmGolfCourseSummary>[];
    for (final element in elements) {
      final summary = _summaryFromOverpassElement(element);
      if (summary != null) {
        summaries.add(summary);
      }
    }

    summaries.sort((a, b) => a.name.compareTo(b.name));
    return summaries;
  }

  Future<Map<String, dynamic>> _runOverpassQuery(String query) async {
    Object? lastError;

    for (final endpoint in _overpassEndpoints) {
      try {
        final response = await _client
            .post(
              Uri.parse(endpoint),
              headers: {
                'User-Agent': _userAgent,
                'Content-Type': 'application/x-www-form-urlencoded',
                'Accept': 'application/json',
              },
              body: {'data': query},
            )
            .timeout(const Duration(seconds: 20));

        if (response.statusCode == 200) {
          return jsonDecode(response.body) as Map<String, dynamic>;
        }

        lastError = 'OpenStreetMap query failed (${response.statusCode}).';
      } catch (error) {
        lastError = error;
      }
    }

    throw Exception(
      lastError?.toString() ??
          'OpenStreetMap query failed. Try again in a moment.',
    );
  }

  List<String> _searchQueries(String raw) {
    final trimmed = raw.trim();
    final lower = trimmed.toLowerCase();
    final queries = <String>[];

    void add(String value) {
      final cleaned = value.trim().replaceAll(RegExp(r'\s+'), ' ');
      if (cleaned.isEmpty) return;
      if (queries.any((q) => q.toLowerCase() == cleaned.toLowerCase())) return;
      queries.add(cleaned);
    }

    add(trimmed);
    if (!lower.contains('golf')) {
      add('$trimmed golf');
    }
    if (!lower.contains('club')) {
      add(lower.contains('golf') ? '$trimmed Club' : '$trimmed Golf Club');
    }
    if (!lower.contains('course')) {
      add(lower.contains('golf') ? '$trimmed Course' : '$trimmed Golf Course');
    }

    final meaningful = trimmed
        .split(RegExp(r'\s+'))
        .where((token) => token.isNotEmpty && !_stopWords.contains(token.toLowerCase()))
        .toList();
    if (meaningful.isNotEmpty) {
      add('${meaningful.join(' ')} Golf Club');
      add('${meaningful.join(' ')} Golf Course');
    }

    return queries;
  }

  String? _overpassNamePattern(String raw) {
    final tokens = raw
        .trim()
        .split(RegExp(r'\s+'))
        .where((token) => token.isNotEmpty && !_stopWords.contains(token.toLowerCase()))
        .map(_escapeOverpassRegex)
        .where((token) => token.isNotEmpty)
        .toList();
    if (tokens.isEmpty) return null;
    return tokens.join('.*');
  }

  String _escapeOverpassRegex(String value) {
    return value.replaceAllMapped(
      RegExp(r'[.\\+*?\[\]^$(){}=!<>|:-]'),
      (match) => '\\${match.group(0)}',
    );
  }

  bool _isGolfCourseResult(Map<String, dynamic> item) {
    final type = item['type']?.toString();
    final category = item['category']?.toString() ?? item['class']?.toString();

    // Strict golf courses only — exclude rock quarries and disc golf.
    if (type == 'golf_course' &&
        (category == 'leisure' || category == null || category.isEmpty)) {
      return true;
    }

    if (type == 'disc_golf_course' ||
        type == 'quarry' ||
        category == 'landuse') {
      return false;
    }

    final haystack =
        '${item['name'] ?? ''} ${item['display_name'] ?? ''}'.toLowerCase();
    if (!haystack.contains('golf')) return false;
    if (haystack.contains('disc golf')) return false;
    return type == 'golf_course' || category == 'leisure';
  }

  OsmGolfCourseSummary? _summaryFromNominatim(Map<String, dynamic> item) {
    final name = item['name']?.toString().trim();
    if (name == null || name.isEmpty) return null;

    final lat = double.tryParse(item['lat']?.toString() ?? '');
    final lon = double.tryParse(item['lon']?.toString() ?? '');
    if (lat == null || lon == null) return null;

    final bbox = item['boundingbox'];
    OsmBounds? bounds;
    if (bbox is List && bbox.length >= 4) {
      bounds = OsmBounds(
        south: double.parse(bbox[0].toString()),
        north: double.parse(bbox[1].toString()),
        west: double.parse(bbox[2].toString()),
        east: double.parse(bbox[3].toString()),
      );
    }

    return OsmGolfCourseSummary(
      osmType: item['osm_type']?.toString() ?? 'way',
      osmId: int.tryParse(item['osm_id']?.toString() ?? '') ?? 0,
      name: name,
      displayName: item['display_name']?.toString(),
      latitude: lat,
      longitude: lon,
      bounds: bounds,
    );
  }

  OsmGolfCourseSummary? _summaryFromOverpassElement(Map<String, dynamic> element) {
    final tags = Map<String, dynamic>.from(element['tags'] as Map? ?? {});
    final name = tags['name']?.toString().trim();
    if (name == null || name.isEmpty) return null;

    final center = element['center'] as Map?;
    final bounds = element['bounds'] as Map?;
    final lat = (center?['lat'] as num?)?.toDouble();
    final lon = (center?['lon'] as num?)?.toDouble();

    OsmBounds? parsedBounds;
    if (bounds != null) {
      parsedBounds = OsmBounds(
        south: (bounds['minlat'] as num).toDouble(),
        west: (bounds['minlon'] as num).toDouble(),
        north: (bounds['maxlat'] as num).toDouble(),
        east: (bounds['maxlon'] as num).toDouble(),
      );
    }

    if (lat == null || lon == null) {
      if (parsedBounds == null) return null;
      return OsmGolfCourseSummary(
        osmType: element['type']?.toString() ?? 'way',
        osmId: (element['id'] as num).toInt(),
        name: name,
        latitude: (parsedBounds.north + parsedBounds.south) / 2,
        longitude: (parsedBounds.east + parsedBounds.west) / 2,
        bounds: parsedBounds,
      );
    }

    return OsmGolfCourseSummary(
      osmType: element['type']?.toString() ?? 'way',
      osmId: (element['id'] as num).toInt(),
      name: name,
      latitude: lat,
      longitude: lon,
      bounds: parsedBounds,
    );
  }

  List<GolfFeature> _featuresFromElements(
    List<Map<String, dynamic>> elements, {
    required String courseName,
  }) {
    final holeAnchors = <String, LatLng>{};
    final holePar = <String, int>{};

    for (final element in elements) {
      final tags = Map<String, dynamic>.from(element['tags'] as Map? ?? {});
      if (tags['golf']?.toString() != 'hole') continue;

      final holeNumber = _holeNumberFromTags(tags);
      final anchor = _centroidFromElement(element);
      if (holeNumber == null || anchor == null) continue;

      holeAnchors[holeNumber] = anchor;
      final par = _parseOptionalInt(tags['par']);
      if (par != null) {
        holePar[holeNumber] = par;
      }
    }

    final features = <GolfFeature>[];
    var idCounter = 0;

    for (final element in elements) {
      final tags = Map<String, dynamic>.from(element['tags'] as Map? ?? {});
      final golfTag = tags['golf']?.toString();
      if (golfTag == 'hole') continue;

      final featureType = _mapGolfTag(golfTag);
      if (featureType == null) continue;

      final geometry = _geometryFromElement(element);
      if (geometry == null) continue;

      var holeNumber = _holeNumberFromTags(tags);
      var par = _parseOptionalInt(tags['par']);
      final handicap = _parseOptionalInt(tags['handicap'] ?? tags['stroke']);

      if (holeNumber == null && holeAnchors.isNotEmpty) {
        final centroid = _centroidFromGeometry(geometry);
        if (centroid != null) {
          holeNumber = _nearestHoleNumber(centroid, holeAnchors);
        }
      }

      if (featureType == 'green' &&
          par == null &&
          holeNumber != null &&
          holePar.containsKey(holeNumber)) {
        par = holePar[holeNumber];
      }

      features.add(
        GolfFeature(
          id: 'osm-${element['type']}-${element['id']}-$idCounter',
          featureType: featureType,
          holeNumber: holeNumber,
          name: tags['name']?.toString(),
          par: par,
          handicap: handicap,
          courseName: courseName,
          geometry: geometry,
        ),
      );
      idCounter++;
    }

    return features;
  }

  LatLng? _centroidFromElement(Map<String, dynamic> element) {
    final geometry = element['geometry'];
    if (geometry is! List || geometry.isEmpty) return null;

    var latSum = 0.0;
    var lonSum = 0.0;
    var count = 0;
    for (final point in geometry) {
      if (point is! Map) continue;
      final lat = (point['lat'] as num?)?.toDouble();
      final lon = (point['lon'] as num?)?.toDouble();
      if (lat == null || lon == null) continue;
      latSum += lat;
      lonSum += lon;
      count++;
    }
    if (count == 0) return null;
    return LatLng(latSum / count, lonSum / count);
  }

  LatLng? _centroidFromGeometry(Map<String, dynamic> geometry) {
    final centroid = centroidOfFeature(geometry);
    if (centroid == null) return null;
    return LatLng(centroid[1], centroid[0]);
  }

  String? _nearestHoleNumber(LatLng point, Map<String, LatLng> holeAnchors) {
    String? nearestHole;
    var nearestDistance = double.infinity;

    for (final entry in holeAnchors.entries) {
      final distance = distanceMeters(point, entry.value);
      if (distance < nearestDistance) {
        nearestDistance = distance;
        nearestHole = entry.key;
      }
    }

    return nearestHole;
  }

  String? _mapGolfTag(String? golfTag) {
    switch (golfTag) {
      case 'tee':
      case 'teeing_ground':
        return 'tee';
      case 'fairway':
      case 'rough':
        return 'fairway';
      case 'green':
        return 'green';
      case 'bunker':
      case 'sand_trap':
        return 'bunker';
      default:
        return null;
    }
  }

  String? _holeNumberFromTags(Map<String, dynamic> tags) {
    for (final key in ['ref', 'hole', 'hole_number']) {
      final value = tags[key]?.toString().trim();
      if (value != null && value.isNotEmpty) {
        return value;
      }
    }
    return null;
  }

  Map<String, dynamic>? _geometryFromElement(Map<String, dynamic> element) {
    final geometry = element['geometry'];
    if (geometry is! List || geometry.isEmpty) return null;

    final ring = <List<double>>[];
    for (final point in geometry) {
      if (point is! Map) continue;
      final lat = (point['lat'] as num?)?.toDouble();
      final lon = (point['lon'] as num?)?.toDouble();
      if (lat == null || lon == null) continue;
      ring.add([lon, lat]);
    }

    if (ring.length < 3) return null;

    final first = ring.first;
    final last = ring.last;
    if (first[0] != last[0] || first[1] != last[1]) {
      ring.add([first[0], first[1]]);
    }

    return {
      'type': 'Polygon',
      'coordinates': [ring],
    };
  }

  OsmBounds _viewboxAround(
    double latitude,
    double longitude, {
    required double radiusKm,
  }) {
    final latDelta = radiusKm / 111.0;
    final lonDelta =
        radiusKm / (111.0 * math.cos(latitude * math.pi / 180.0).abs().clamp(0.2, 1.0));

    return OsmBounds(
      south: latitude - latDelta,
      north: latitude + latDelta,
      west: longitude - lonDelta,
      east: longitude + lonDelta,
    );
  }

  double _distanceMeters(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const earthRadius = 6371000.0;
    final dLat = (lat2 - lat1) * math.pi / 180.0;
    final dLon = (lon2 - lon1) * math.pi / 180.0;
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1 * math.pi / 180.0) *
            math.cos(lat2 * math.pi / 180.0) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadius * c;
  }

  int? _parseOptionalInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString());
  }

  static const _stopWords = {
    'the',
    'a',
    'an',
    'golf',
    'course',
    'club',
    'links',
    'country',
    'at',
    'of',
  };
}

class OsmBounds {
  const OsmBounds({
    required this.south,
    required this.west,
    required this.north,
    required this.east,
  });

  final double south;
  final double west;
  final double north;
  final double east;
}

class OsmGolfCourseSummary {
  const OsmGolfCourseSummary({
    required this.osmType,
    required this.osmId,
    required this.name,
    required this.latitude,
    required this.longitude,
    this.displayName,
    this.bounds,
  });

  final String osmType;
  final int osmId;
  final String name;
  final String? displayName;
  final double latitude;
  final double longitude;
  final OsmBounds? bounds;
}
