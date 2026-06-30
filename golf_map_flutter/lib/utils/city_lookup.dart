import 'package:latlong2/latlong.dart';

import '../data/us_cities.dart';

USCity nearestCity(double latitude, double longitude) {
  final point = LatLng(latitude, longitude);
  const distance = Distance();

  USCity? closest;
  var closestMeters = double.infinity;

  for (final city in kUsCities) {
    final meters = distance.as(
      LengthUnit.Meter,
      point,
      LatLng(city.latitude, city.longitude),
    );
    if (meters < closestMeters) {
      closestMeters = meters;
      closest = city;
    }
  }

  return closest ?? kUsCities.first;
}
