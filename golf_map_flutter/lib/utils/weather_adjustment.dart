import 'dart:math' as math;

/// Adjusts playing distance for temperature, wind, and elevation.
int playsLikeYards({
  required int actualYards,
  double? temperatureF,
  double? windMph,
  double? windDirectionDeg,
  double? shotBearingDeg,
  double? elevationFeet,
}) {
  var adjusted = actualYards.toDouble();

  if (temperatureF != null) {
    adjusted += (70 - temperatureF) / 10.0;
  }

  if (elevationFeet != null) {
    adjusted *= 1.0 - (elevationFeet / 1000.0) * 0.005;
  }

  if (windMph != null &&
      windMph > 2 &&
      windDirectionDeg != null &&
      shotBearingDeg != null) {
    final windRad = windDirectionDeg * math.pi / 180;
    final shotRad = shotBearingDeg * math.pi / 180;
    final headFactor = -(windMph * math.cos(windRad - shotRad));
    adjusted += headFactor * 0.8;
  }

  return adjusted.round().clamp(1, 999);
}
