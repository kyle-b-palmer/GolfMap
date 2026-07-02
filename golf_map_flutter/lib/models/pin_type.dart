enum PinType {
  shot,
  lostBall;

  String get label => switch (this) {
        PinType.shot => 'shot',
        PinType.lostBall => 'lost ball',
      };

  static PinType fromJson(String? value) {
    if (value == 'lostBall') return PinType.lostBall;
    return PinType.shot;
  }

  String toJson() => name;
}
