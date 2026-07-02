import 'dart:io';

import 'package:flutter/services.dart';

class HealthWorkoutService {
  HealthWorkoutService._();

  static final HealthWorkoutService instance = HealthWorkoutService._();

  static const _channel = MethodChannel('com.golfmapapp/health_workout');

  bool get isSupported => Platform.isIOS;

  Future<bool> isAvailable() async {
    if (!isSupported) return false;
    try {
      final value = await _channel.invokeMethod<bool>('isAvailable');
      return value ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> startGolfWorkout() async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod<void>('startGolfWorkout');
    } catch (_) {}
  }

  Future<void> endGolfWorkout() async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod<void>('endGolfWorkout');
    } catch (_) {}
  }
}
