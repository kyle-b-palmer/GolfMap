import 'dart:convert';
import 'dart:io';

/// Converts a GeoJSON FeatureCollection into the app's bundled row format
/// and merges it into [assets/courses/san_antonio_courses.json].
///
/// Usage:
///   dart run tool/import_geojson.dart /path/to/course.geojson
Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln(
      'Usage: dart run tool/import_geojson.dart <path-to-geojson>',
    );
    exit(1);
  }

  final geojsonFile = File(args.first);
  if (!await geojsonFile.exists()) {
    stderr.writeln('File not found: ${geojsonFile.path}');
    exit(1);
  }

  const bundlePath = 'assets/courses/san_antonio_courses.json';
  final bundleFile = File(bundlePath);

  final existingRows = bundleFile.existsSync()
      ? (jsonDecode(await bundleFile.readAsString()) as List)
          .cast<Map<String, dynamic>>()
      : <Map<String, dynamic>>[];

  final geojson =
      jsonDecode(await geojsonFile.readAsString()) as Map<String, dynamic>;
  final features = (geojson['features'] as List).cast<Map<String, dynamic>>();
  final converted = _convertGeoJsonFeatures(features, startId: _nextId(existingRows));

  final courseNames = converted
      .map((row) => row['course_name']?.toString())
      .whereType<String>()
      .toSet();

  final withoutCourses = existingRows
      .where((row) => !courseNames.contains(row['course_name']?.toString()))
      .toList();

  final merged = [...withoutCourses, ...converted]..sort((a, b) {
      final idA = a['id'];
      final idB = b['id'];
      if (idA is num && idB is num) {
        return idA.compareTo(idB);
      }
      return idA.toString().compareTo(idB.toString());
    });

  await bundleFile.parent.create(recursive: true);
  await bundleFile.writeAsString(
    const JsonEncoder.withIndent('  ').convert(merged),
  );

  stderr.writeln(
    'Imported ${converted.length} features for ${courseNames.join(', ')}',
  );
  stderr.writeln(
    'Bundled total: ${merged.length} features across '
    '${merged.map((r) => r['course_name']).toSet().length} courses',
  );
  stderr.writeln('Wrote $bundlePath (${await bundleFile.length()} bytes)');
}

int _nextId(List<Map<String, dynamic>> rows) {
  var maxId = 0;
  for (final row in rows) {
    final id = row['id'];
    if (id is int && id > maxId) {
      maxId = id;
    } else if (id is num) {
      maxId = maxId < id.toInt() ? id.toInt() : maxId;
    }
  }
  return maxId + 1;
}

List<Map<String, dynamic>> _convertGeoJsonFeatures(
  List<Map<String, dynamic>> features, {
  required int startId,
}) {
  final rows = <Map<String, dynamic>>[];
  var id = startId;

  for (final feature in features) {
    final properties =
        Map<String, dynamic>.from(feature['properties'] as Map? ?? {});
    final geometry = Map<String, dynamic>.from(feature['geometry'] as Map);
    geometry.remove('crs');

    final featureType = properties['feature_type']?.toString() ??
        properties['golf']?.toString();
    final holeNumber = properties['hole_number']?.toString() ??
        properties['hole']?.toString();
    final courseName = properties['course_name']?.toString();
    if (featureType == null || courseName == null || courseName.isEmpty) {
      continue;
    }

    final row = <String, dynamic>{
      'id': feature['id'] ?? id,
      'feature_type': featureType,
      'hole_number': holeNumber,
      'name': properties['name'],
      'geom': geometry,
      'course_name': courseName,
    };

    final par = _parseOptionalInt(properties['par']);
    final handicap = _parseOptionalInt(properties['handicap']);
    if (par != null) row['par'] = par;
    if (handicap != null) row['handicap'] = handicap;

    rows.add(row);
    if (feature['id'] == null) {
      id++;
    } else {
      id++;
    }
  }

  return rows;
}

int? _parseOptionalInt(dynamic value) {
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value.trim());
  return null;
}
