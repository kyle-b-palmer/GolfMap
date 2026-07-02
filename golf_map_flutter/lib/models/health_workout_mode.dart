enum HealthWorkoutMode {
  always,
  ask,
  never;

  String get label => switch (this) {
        always => 'Always start',
        ask => 'Ask each round',
        never => 'Never',
      };

  String get description => switch (this) {
        always => 'Start a golf workout in Apple Health when you begin a round',
        ask => 'Prompt before starting a workout each round',
        never => 'Do not start Apple Health workouts',
      };

  static HealthWorkoutMode fromStorage(String? value) {
    return switch (value) {
      'ask' => ask,
      'never' => never,
      _ => always,
    };
  }
}
