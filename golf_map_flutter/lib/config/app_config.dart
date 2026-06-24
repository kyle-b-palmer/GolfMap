/// How the map background is rendered.
enum MapBackground {
  /// Course polygons on a solid rough-colored background. Free and fully offline.
  courseOnly,

  /// OpenStreetMap street map tiles. Free, but needs network and OSM attribution.
  openStreetMap,
}

class AppConfig {
  static const supabaseUrl = 'https://xycsxghpvylyquigzdje.supabase.co';
  static const supabaseAnonKey =
      'sb_publishable_cp2hvysVtLbO_7ke0uk5NQ_CvBN4AoB';

  /// Bundled San Antonio course geometry (tees, fairways, greens, bunkers).
  static const bundledCoursesAsset =
      'assets/courses/san_antonio_courses.json';

  /// When true, load course GPS from the bundled asset instead of Supabase.
  static const useBundledCourseData = true;

  /// No Mapbox — use course-only (default) or free OpenStreetMap tiles.
  static const mapBackground = MapBackground.courseOnly;

  static const openStreetMapTileUrl =
      'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

  static const defaultCenter = [29.4795, -98.4715]; // lat, lng
}
