import 'pin_type.dart';

class PinnedShot {
  const PinnedShot({
    required this.shotNumber,
    required this.latitude,
    required this.longitude,
    required this.fromLatitude,
    required this.fromLongitude,
    this.teeLabel,
    this.shotYards,
    this.yardsToPin,
    this.pinType = PinType.shot,
  });

  final int shotNumber;
  final double latitude;
  final double longitude;
  final double fromLatitude;
  final double fromLongitude;
  final String? teeLabel;
  /// Distance of this shot segment (from tee or previous pin).
  final int? shotYards;
  final int? yardsToPin;
  final PinType pinType;

  factory PinnedShot.fromJson(Map<String, dynamic> json) {
    final lat = (json['latitude'] as num).toDouble();
    final lng = (json['longitude'] as num).toDouble();
    return PinnedShot(
      shotNumber: (json['shotNumber'] as num).toInt(),
      latitude: lat,
      longitude: lng,
      fromLatitude: (json['fromLatitude'] as num?)?.toDouble() ?? lat,
      fromLongitude: (json['fromLongitude'] as num?)?.toDouble() ?? lng,
      teeLabel: json['teeLabel'] as String?,
      shotYards: (json['shotYards'] as num?)?.toInt() ??
          (json['yardsFromTee'] as num?)?.toInt(),
      yardsToPin: (json['yardsToPin'] as num?)?.toInt(),
      pinType: PinType.fromJson(json['pinType'] as String?),
    );
  }

  Map<String, dynamic> toJson() => {
        'shotNumber': shotNumber,
        'latitude': latitude,
        'longitude': longitude,
        'fromLatitude': fromLatitude,
        'fromLongitude': fromLongitude,
        if (teeLabel != null) 'teeLabel': teeLabel,
        if (shotYards != null) 'shotYards': shotYards,
        if (yardsToPin != null) 'yardsToPin': yardsToPin,
        if (pinType != PinType.shot) 'pinType': pinType.toJson(),
      };
}
