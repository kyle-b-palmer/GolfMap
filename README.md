# Golf Map App

Flutter golf course map with scoring, GPS yardages, and shot planning.

## Run the app

```bash
cd golf_map_flutter
flutter pub get
flutter run -d chrome
```

On Windows, if `build\flutter_assets` is locked (often due to OneDrive), use:

```powershell
.\run_chrome.ps1
```

## Course data

San Antonio course geometry is bundled at `golf_map_flutter/assets/courses/san_antonio_courses.json`.

To refresh from Supabase:

```bash
cd golf_map_flutter
dart run tool/export_courses.dart
```

## Platforms

The Flutter project supports web, Android, iOS, Windows, macOS, and Linux from `golf_map_flutter/`.
