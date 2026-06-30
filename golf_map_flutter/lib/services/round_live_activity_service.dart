import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:live_activities/live_activities.dart';
import 'package:live_activities/models/live_activity_state.dart';

class LiveActivityGpsPin {
  const LiveActivityGpsPin({
    required this.hole,
    required this.latitude,
    required this.longitude,
  });

  final String hole;
  final double latitude;
  final double longitude;
}

class SharedGpsYardage {
  const SharedGpsYardage({
    required this.yardsToGreen,
    required this.gpsRefreshRevision,
  });

  final int yardsToGreen;
  final int gpsRefreshRevision;
}

class LiveActivityWidgetChanges {
  const LiveActivityWidgetChanges({
    required this.courseName,
    required this.selectedHole,
    required this.scores,
    required this.putts,
    required this.revision,
    this.pendingGpsPins = const [],
    this.pendingGpsPinUndos = const [],
  });

  final String courseName;
  final String selectedHole;
  final Map<String, int> scores;
  final Map<String, int> putts;
  final int revision;
  final List<LiveActivityGpsPin> pendingGpsPins;
  final List<LiveActivityGpsPin> pendingGpsPinUndos;
}

/// Syncs in-round golf data to an iOS Live Activity (lock screen + Dynamic Island).
class RoundLiveActivityService {
  RoundLiveActivityService._();

  static final RoundLiveActivityService instance = RoundLiveActivityService._();

  static const appGroupId = 'group.com.golfmapapp.golfMapFlutter';
  static const activityId = 'golf-round-live';
  static const _bridge = MethodChannel('com.golfmapapp/live_activity_round');
  static const _foregroundEvents =
      EventChannel('com.golfmapapp/live_activity_round/events');

  final LiveActivities _plugin = LiveActivities();
  bool _initialized = false;
  int? _lastYardsToGreen;
  String? _lastSyncedHole;
  int _session = 0;
  String? _runningActivityId;
  Future<void> _operationLock = Future.value();
  int _interactiveRevision = 0;
  int _lastSeenNativeGpsRevision = 0;
  Future<bool>? _interactiveSupported;

  bool get isSupported => Platform.isIOS;
  int get session => _session;
  int get interactiveRevision => _interactiveRevision;

  Stream<String> get stateChangeStream => _foregroundEvents
      .receiveBroadcastStream()
      .map((event) => event is String ? event : 'foreground')
      .handleError((_) {});

  Future<void> init() async {
    if (!isSupported || _initialized) return;
    try {
      await _plugin.init(appGroupId: appGroupId);
      _initialized = true;
    } catch (_) {
      // App group / ActivityKit may be unavailable during development installs.
    }
  }

  /// Ends any prior round activity so a new round starts clean.
  Future<int> beginRound() async {
    if (!isSupported) return _session;
    return _withLock(() async {
      await init();
      _interactiveRevision = 0;
      await _clearSharedRoundState();
      await _endActivities();
      _session++;
      return _session;
    });
  }

  Future<bool> areActivitiesEnabled() async {
    if (!isSupported || !_initialized) return false;
    return _plugin.areActivitiesEnabled();
  }

  Future<bool> supportsInteractiveControls() async {
    if (!isSupported) return false;
    _interactiveSupported ??= _bridge
        .invokeMethod<bool>('supportsInteractiveControls')
        .then((value) => value ?? false)
        .catchError((_) => false);
    return _interactiveSupported!;
  }

  Future<void> syncInteractiveRoundState({
    required List<String> holes,
    required String selectedHole,
    required Map<String, int> scores,
    required Map<String, int> putts,
    required Map<String, int> pars,
    required Map<String, int> handicaps,
    required String courseName,
    int? yardsToGreen,
    double? greenLatitude,
    double? greenLongitude,
    int? revision,
  }) async {
    if (!isSupported) return;
    if (!await supportsInteractiveControls()) return;

    final nextRevision = revision ?? await _nextInteractiveRevision();

    if (revision == null) {
      _interactiveRevision = nextRevision;
    } else {
      _interactiveRevision = revision;
    }

    try {
      await _bridge.invokeMethod<void>('syncRoundState', {
        'holes': holes,
        'selectedHole': selectedHole,
        'scores': scores,
        'putts': putts,
        'pars': pars,
        'handicaps': handicaps,
        'courseName': courseName,
        'yardsToGreen': yardsToGreen ?? -1,
        'greenLatitude': greenLatitude ?? 0,
        'greenLongitude': greenLongitude ?? 0,
        'revision': nextRevision,
      });
      await pushWatchRoundState();
    } catch (_) {
      if (revision == null) {
        _interactiveRevision--;
      }
    }
  }

  Future<int> _nextInteractiveRevision() async {
    final shared = await sharedRevision();
    if (shared > _interactiveRevision) {
      _interactiveRevision = shared;
    }
    return _interactiveRevision + 1;
  }

  Future<void> pushWatchRoundState() async {
    if (!isSupported) return;
    try {
      await _bridge.invokeMethod<void>('pushWatchRoundState');
    } catch (_) {}
  }

  Future<LiveActivityWidgetChanges?> consumeWidgetChanges() async {
    if (!isSupported) return null;
    if (!await supportsInteractiveControls()) return null;

    try {
      final result = await _bridge.invokeMethod<Object?>('consumeWidgetChanges', {
        'revision': _interactiveRevision,
      });
      if (result is! Map) return null;

      final selectedHole = result['selectedHole'];
      final courseName = result['courseName'];
      final revision = result['revision'];
      if (selectedHole is! String ||
          courseName is! String ||
          revision is! num) {
        return null;
      }

      final scores = <String, int>{};
      final scoresRaw = result['scores'];
      if (scoresRaw is Map) {
        scoresRaw.forEach((key, value) {
          if (key is String && value is num) {
            scores[key] = value.toInt();
          }
        });
      }

      final putts = <String, int>{};
      final puttsRaw = result['putts'];
      if (puttsRaw is Map) {
        puttsRaw.forEach((key, value) {
          if (key is String && value is num) {
            putts[key] = value.toInt();
          }
        });
      }

      final pendingGpsPins = <LiveActivityGpsPin>[];
      final pinsRaw = result['pendingGpsPins'];
      if (pinsRaw is List) {
        for (final item in pinsRaw) {
          if (item is! Map) continue;
          final hole = item['hole'];
          final latitude = item['latitude'];
          final longitude = item['longitude'];
          if (hole is String && latitude is num && longitude is num) {
            pendingGpsPins.add(
              LiveActivityGpsPin(
                hole: hole,
                latitude: latitude.toDouble(),
                longitude: longitude.toDouble(),
              ),
            );
          }
        }
      }

      final pendingGpsPinUndos = <LiveActivityGpsPin>[];
      final undosRaw = result['pendingGpsPinUndos'];
      if (undosRaw is List) {
        for (final item in undosRaw) {
          if (item is! Map) continue;
          final hole = item['hole'];
          final latitude = item['latitude'];
          final longitude = item['longitude'];
          if (hole is String && latitude is num && longitude is num) {
            pendingGpsPinUndos.add(
              LiveActivityGpsPin(
                hole: hole,
                latitude: latitude.toDouble(),
                longitude: longitude.toDouble(),
              ),
            );
          }
        }
      }

      final changes = LiveActivityWidgetChanges(
        courseName: courseName,
        selectedHole: selectedHole,
        scores: scores,
        putts: putts,
        revision: revision.toInt(),
        pendingGpsPins: pendingGpsPins,
        pendingGpsPinUndos: pendingGpsPinUndos,
      );
      _interactiveRevision = changes.revision;
      return changes;
    } catch (_) {
      return null;
    }
  }

  Future<int> sharedRevision() async {
    if (!isSupported) return 0;
    try {
      final value = await _bridge.invokeMethod<int>('getSharedRevision');
      return value ?? 0;
    } catch (_) {
      return 0;
    }
  }

  Future<void> acknowledgePendingGpsPins() async {
    if (!isSupported) return;
    try {
      await _bridge.invokeMethod<void>('acknowledgePendingGpsPins');
    } catch (_) {}
  }

  Future<void> clearPendingGpsPinUndos() async {
    if (!isSupported) return;
    try {
      await _bridge.invokeMethod<void>('clearPendingGpsPinUndos');
    } catch (_) {}
  }

  Future<void> reportPinnedShotRemoved({
    required String hole,
    required double latitude,
    required double longitude,
    required Map<String, int> scores,
  }) async {
    if (!isSupported) return;
    if (!await supportsInteractiveControls()) return;

    try {
      await _bridge.invokeMethod<void>('reportPinnedShotRemoved', {
        'hole': hole,
        'latitude': latitude,
        'longitude': longitude,
        'scores': scores,
      });
      _interactiveRevision++;
      await pushWatchRoundState();
    } catch (_) {}
  }

  Future<void> updateGreenTarget({
    required double greenLatitude,
    required double greenLongitude,
  }) async {
    if (!isSupported) return;
    try {
      await _bridge.invokeMethod<void>('updateGreenTarget', {
        'greenLatitude': greenLatitude,
        'greenLongitude': greenLongitude,
      });
    } catch (_) {}
  }

  Future<SharedGpsYardage?> getSharedGpsYardage() async {
    if (!isSupported) return null;
    try {
      final result = await _bridge.invokeMethod<Object?>('getSharedGpsYardage');
      if (result is! Map) return null;
      final yards = result['yardsToGreen'];
      final revision = result['gpsRefreshRevision'];
      if (yards is! num || revision is! num) return null;
      return SharedGpsYardage(
        yardsToGreen: yards.toInt(),
        gpsRefreshRevision: revision.toInt(),
      );
    } catch (_) {
      return null;
    }
  }

  int get lastSeenNativeGpsRevision => _lastSeenNativeGpsRevision;

  void acknowledgeNativeGpsRevision(int revision) {
    if (revision > _lastSeenNativeGpsRevision) {
      _lastSeenNativeGpsRevision = revision;
    }
  }

  Future<void> syncRound({
    required String courseName,
    required String hole,
    required int par,
    required int holeScore,
    required int totalScore,
    required int relativeToPar,
    int? yardsToGreen,
    bool force = false,
    bool bypassWidgetRevisionGuard = false,
    int? session,
  }) async {
    if (!isSupported || !_initialized) return;
    await _withLock(() async {
      if (session != null && session != _session) return;
      if (!await areActivitiesEnabled()) return;
      if (!bypassWidgetRevisionGuard &&
          await sharedRevision() > _interactiveRevision) {
        return;
      }
      if (force) _lastYardsToGreen = null;

      final payload = <String, dynamic>{
        'courseName': courseName,
        'hole': hole,
        'par': par,
        'holeScore': holeScore,
        'totalScore': totalScore,
        'relativeToPar': relativeToPar,
        'yardsToGreen': yardsToGreen ?? -1,
      };

      await _createOrUpdate(payload);
      _lastYardsToGreen = yardsToGreen;
      _lastSyncedHole = hole;
    });
  }

  /// Throttles GPS-driven updates so we do not spam ActivityKit.
  Future<void> syncGpsYardage({
    required String courseName,
    required String hole,
    required int par,
    required int holeScore,
    required int totalScore,
    required int relativeToPar,
    int? yardsToGreen,
    double? greenLatitude,
    double? greenLongitude,
    bool force = false,
    int? session,
  }) async {
    if (session != null && session != _session) return;

    var effectiveYards = yardsToGreen;
    final shared = await getSharedGpsYardage();
    if (shared != null && shared.yardsToGreen >= 0) {
      if (shared.gpsRefreshRevision > _lastSeenNativeGpsRevision) {
        _lastSeenNativeGpsRevision = shared.gpsRefreshRevision;
        effectiveYards = shared.yardsToGreen;
        _lastYardsToGreen = effectiveYards;
      } else if (shared.gpsRefreshRevision == _lastSeenNativeGpsRevision &&
          effectiveYards != null &&
          (effectiveYards - shared.yardsToGreen).abs() > 5) {
        // Keep a recent widget GPS reading from being overwritten by stale app
        // values such as the full-hole tee yardage fallback.
        effectiveYards = shared.yardsToGreen;
        _lastYardsToGreen = effectiveYards;
      }
    }

    final holeChanged = _lastSyncedHole != null && _lastSyncedHole != hole;
    if (!force && !holeChanged) {
      if (effectiveYards == _lastYardsToGreen) return;
      if (_lastYardsToGreen != null &&
          effectiveYards != null &&
          (effectiveYards - _lastYardsToGreen!).abs() < 1) {
        return;
      }
    }

    if (greenLatitude != null &&
        greenLongitude != null &&
        greenLatitude != 0 &&
        greenLongitude != 0) {
      await updateGreenTarget(
        greenLatitude: greenLatitude,
        greenLongitude: greenLongitude,
      );
    }

    await syncRound(
      courseName: courseName,
      hole: hole,
      par: par,
      holeScore: holeScore,
      totalScore: totalScore,
      relativeToPar: relativeToPar,
      yardsToGreen: effectiveYards,
      bypassWidgetRevisionGuard: true,
      session: session,
    );
  }

  void resetGpsThrottle() {
    _lastYardsToGreen = null;
    _lastSyncedHole = null;
    _lastSeenNativeGpsRevision = 0;
  }

  Future<void> end() async {
    if (!isSupported || !_initialized) return;
    await _withLock(() async {
      _session++;
      _interactiveRevision = 0;
      await _clearSharedRoundState();
      await _endActivities();
    });
  }

  Future<void> _clearSharedRoundState() async {
    if (!isSupported) return;
    try {
      await _bridge.invokeMethod<void>('clearSharedState');
    } catch (_) {}
  }

  Future<void> _createOrUpdate(Map<String, dynamic> payload) async {
    if (_runningActivityId != null) {
      final state = await _plugin.getActivityState(_runningActivityId!);
      if (state == LiveActivityState.active || state == LiveActivityState.stale) {
        await _plugin.updateActivity(_runningActivityId!, payload);
        return;
      }
      _runningActivityId = null;
    }

    _runningActivityId = await _plugin.createActivity(
      activityId,
      payload,
      iOSEnableRemoteUpdates: false,
      removeWhenAppIsKilled: true,
    );
  }

  Future<void> _endActivities() async {
    try {
      await _plugin.endAllActivities();
    } catch (_) {}
    _runningActivityId = null;
    _lastYardsToGreen = null;
    _lastSyncedHole = null;
  }

  Future<T> _withLock<T>(Future<T> Function() action) {
    final result = _operationLock.then((_) => action());
    _operationLock = result.then((_) {}, onError: (_) {});
    return result;
  }
}
