import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

class WeatherConditions {
  const WeatherConditions({
    required this.temperatureF,
    required this.windMph,
    required this.windDirectionDeg,
    this.elevationFeet,
  });

  final double temperatureF;
  final double windMph;
  final double windDirectionDeg;
  final double? elevationFeet;
}

class WeatherService {
  WeatherConditions? _cached;
  LatLng? _cachedPoint;
  DateTime? _cachedAt;

  Future<WeatherConditions?> fetchForLocation(LatLng point) async {
    final now = DateTime.now();
    if (_cached != null &&
        _cachedPoint != null &&
        _cachedAt != null &&
        now.difference(_cachedAt!) < const Duration(minutes: 15) &&
        _distanceMeters(_cachedPoint!, point) < 500) {
      return _cached;
    }

    try {
      final uri = Uri.parse(
        'https://api.open-meteo.com/v1/forecast'
        '?latitude=${point.latitude}'
        '&longitude=${point.longitude}'
        '&current=temperature_2m,wind_speed_10m,wind_direction_10m'
        '&temperature_unit=fahrenheit'
        '&wind_speed_unit=mph'
        '&timezone=auto',
      );
      final response = await http.get(uri).timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return _cached;

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final current = json['current'] as Map<String, dynamic>?;
      if (current == null) return _cached;

      final temp = (current['temperature_2m'] as num?)?.toDouble();
      final wind = (current['wind_speed_10m'] as num?)?.toDouble();
      final windDir = (current['wind_direction_10m'] as num?)?.toDouble();
      if (temp == null || wind == null || windDir == null) return _cached;

      final elevation = (json['elevation'] as num?)?.toDouble();

      _cached = WeatherConditions(
        temperatureF: temp,
        windMph: wind,
        windDirectionDeg: windDir,
        elevationFeet: elevation != null ? elevation * 3.28084 : null,
      );
      _cachedPoint = point;
      _cachedAt = now;
      return _cached;
    } catch (_) {
      return _cached;
    }
  }

  double _distanceMeters(LatLng a, LatLng b) {
    const earthRadius = 6378137.0;
    final dLat = (b.latitude - a.latitude) * math.pi / 180;
    final dLng = (b.longitude - a.longitude) * math.pi / 180;
    final lat1 = a.latitude * math.pi / 180;
    final lat2 = b.latitude * math.pi / 180;
    final h = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.sin(dLng / 2) *
            math.sin(dLng / 2) *
            math.cos(lat1) *
            math.cos(lat2);
    return earthRadius * 2 * math.atan2(math.sqrt(h), math.sqrt(1 - h));
  }
}
