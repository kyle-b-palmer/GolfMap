class ClubDistance {
  const ClubDistance({
    required this.name,
    required this.carryYards,
  });

  final String name;
  final int carryYards;

  Map<String, dynamic> toJson() => {
        'name': name,
        'carryYards': carryYards,
      };

  factory ClubDistance.fromJson(Map<String, dynamic> json) {
    return ClubDistance(
      name: json['name'] as String,
      carryYards: (json['carryYards'] as num).toInt(),
    );
  }
}

/// Default carry distances; customize in My Club Bag.
class ClubBag {
  static const defaultClubs = [
    ClubDistance(name: 'DR', carryYards: 235),
    ClubDistance(name: '3W', carryYards: 215),
    ClubDistance(name: '5W', carryYards: 200),
    ClubDistance(name: '4H', carryYards: 190),
    ClubDistance(name: '5I', carryYards: 175),
    ClubDistance(name: '6I', carryYards: 165),
    ClubDistance(name: '7I', carryYards: 155),
    ClubDistance(name: '8I', carryYards: 145),
    ClubDistance(name: '9I', carryYards: 135),
    ClubDistance(name: 'PW', carryYards: 120),
    ClubDistance(name: 'GW', carryYards: 105),
    ClubDistance(name: 'SW', carryYards: 90),
    ClubDistance(name: 'LW', carryYards: 75),
  ];

  static List<ClubDistance> fromJsonList(List<dynamic>? raw) {
    if (raw == null || raw.isEmpty) return List.from(defaultClubs);
    return raw
        .whereType<Map>()
        .map((e) => ClubDistance.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  static List<Map<String, dynamic>> toJsonList(List<ClubDistance> clubs) {
    return clubs.map((c) => c.toJson()).toList();
  }
}
