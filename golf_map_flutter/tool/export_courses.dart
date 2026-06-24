import 'dart:convert';
import 'dart:io';

import 'package:supabase/supabase.dart';

Future<void> main() async {
  const url = 'https://xycsxghpvylyquigzdje.supabase.co';
  const key = 'sb_publishable_cp2hvysVtLbO_7ke0uk5NQ_CvBN4AoB';

  final client = SupabaseClient(url, key);
  final data = await client
      .from('golf_features')
      .select(
        'id, feature_type, hole_number, name, geom, par, handicap, course_name',
      );

  final rows = (data as List).cast<Map<String, dynamic>>();
  final courses = rows
      .map((r) => r['course_name']?.toString())
      .whereType<String>()
      .toSet()
      .toList()
    ..sort();

  stderr.writeln('Fetched ${rows.length} features for ${courses.length} courses:');
  for (final course in courses) {
    stderr.writeln('  - $course');
  }

  final outFile = File('assets/courses/san_antonio_courses.json');
  await outFile.parent.create(recursive: true);
  await outFile.writeAsString(const JsonEncoder.withIndent('  ').convert(rows));

  stderr.writeln('Wrote ${outFile.path} (${await outFile.length()} bytes)');
}
