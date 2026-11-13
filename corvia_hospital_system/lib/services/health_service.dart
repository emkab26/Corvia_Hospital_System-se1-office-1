import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:health/health.dart';

/// Pulls vitals from the OS-level health store:
/// • **Android** → Health Connect (which Samsung Health, Fitbit, Google Fit,
///   etc. all publish into — including readings from a paired Galaxy Watch).
/// • **iOS** → HealthKit (Apple Watch and any HealthKit-publishing app).
///
/// On Android 14+ Health Connect is built into the OS; on Android 13 and
/// below it ships as a standalone Play Store app. The user must have:
///   1. Health Connect installed (auto on A14+, downloadable on older)
///   2. Samsung Health → Settings → Health Connect → toggle on the data
///      types Corvia needs (Heart rate + Steps at minimum)
///   3. Granted Corvia read permission via the Health Connect dialog
///
/// This service is intentionally a thin wrapper — the UI owns the polling
/// cadence and refresh logic. We expose async snapshot methods rather than
/// streams because Health Connect doesn't push events; you query the store
/// for what's currently recorded.
class HealthService {
  HealthService._();

  static final HealthService instance = HealthService._();

  final Health _health = Health();
  bool _configured = false;

  /// The set of vitals Corvia will read. Keep this list narrow — Health
  /// Connect surfaces each requested type in the permission dialog, and a
  /// long list scares users off.
  // UPDATED:
  // Added ACTIVE_ENERGY_BURNED for calories
  static const List<HealthDataType> _readTypes = <HealthDataType>[
    HealthDataType.HEART_RATE,
    HealthDataType.STEPS,
    HealthDataType.ACTIVE_ENERGY_BURNED,
  ];

  static const List<HealthDataAccess> _readAccess = <HealthDataAccess>[
    HealthDataAccess.READ,
    HealthDataAccess.READ,
    HealthDataAccess.READ, // Added another one for ACTIVE_ENERGY_BURNED
  ];

  /// Idempotent — safe to call from `initState` and again before every read.
  Future<void> _ensureConfigured() async {
    if (_configured) return;
    try {
      await _health.configure();
      _configured = true;
    } catch (e) {
      debugPrint('HealthService.configure() failed: $e');
      rethrow;
    }
  }

  /// True when Health Connect (Android) or HealthKit (iOS) is installed and
  /// reachable. On Android, returns false when Health Connect isn't installed
  /// — the caller can prompt the user to install it from Play Store.
  Future<bool> isAvailable() async {
    if (!(Platform.isAndroid || Platform.isIOS)) return false;
    try {
      await _ensureConfigured();
      if (Platform.isAndroid) {
        final status = await _health.getHealthConnectSdkStatus();
        return status == HealthConnectSdkStatus.sdkAvailable;
      }
      // iOS: HealthKit is always present on a real device. The simulator
      // returns false on permission calls, which we surface elsewhere.
      return true;
    } catch (e) {
      debugPrint('HealthService.isAvailable() failed: $e');
      return false;
    }
  }

  /// Whether Health Connect is installed but in an outdated state — we can
  /// route the user to Play Store to update it.
  Future<bool> needsHealthConnectUpdate() async {
    if (!Platform.isAndroid) return false;
    try {
      await _ensureConfigured();
      final status = await _health.getHealthConnectSdkStatus();
      return status ==
          HealthConnectSdkStatus.sdkUnavailableProviderUpdateRequired;
    } catch (_) {
      return false;
    }
  }

  /// Opens the Play Store entry for Health Connect so the user can install
  /// or update it. No-op on iOS.
  Future<void> installHealthConnect() async {
    if (!Platform.isAndroid) return;
    try {
      await _ensureConfigured();
      await _health.installHealthConnect();
    } catch (e) {
      debugPrint('installHealthConnect() failed: $e');
    }
  }

  /// Checks whether the user has already granted us read access.
  /// Returns null when the platform can't answer (treat as "ask anyway").
  Future<bool?> hasPermissions() async {
    try {
      await _ensureConfigured();
      return await _health.hasPermissions(_readTypes, permissions: _readAccess);
    } catch (e) {
      debugPrint('hasPermissions() failed: $e');
      return null;
    }
  }

  /// Prompts the OS-level permission dialog. Returns true if every requested
  /// type was granted. The user can revoke later via system Settings.
  Future<bool> requestPermissions() async {
    try {
      await _ensureConfigured();
      return await _health.requestAuthorization(
        _readTypes,
        permissions: _readAccess,
      );
    } catch (e) {
      debugPrint('requestAuthorization() failed: $e');
      return false;
    }
  }

  /// Latest heart-rate reading from the last [window] (default 6 hours).
  /// Samsung Health syncs Galaxy Watch readings to Health Connect in batches
  /// that can be 15–60 min apart, so a 1-hour window frequently misses the
  /// most-recent reading. 6 hours ensures we always return the latest sample
  /// while the UI's 30-min freshness check still flags genuinely stale data.
  Future<HeartRateSample?> latestHeartRate({
    Duration window = const Duration(hours: 6),
  }) async {
    try {
      await _ensureConfigured();
      final now = DateTime.now();
      final start = now.subtract(window);
      final points = await _health.getHealthDataFromTypes(
        types: const [HealthDataType.HEART_RATE],
        startTime: start,
        endTime: now,
      );
      if (points.isEmpty) return null;
      // Most-recent first.
      points.sort((a, b) => b.dateTo.compareTo(a.dateTo));
      final latest = points.first;
      final value = latest.value;
      double bpm = 0;
      if (value is NumericHealthValue) {
        bpm = value.numericValue.toDouble();
      }
      if (bpm <= 0) return null;
      return HeartRateSample(
        bpm: bpm.round(),
        sampledAt: latest.dateTo,
        source: latest.sourceName,
      );
    } catch (e) {
      debugPrint('latestHeartRate() failed: $e');
      return null;
    }
  }

  /// Total steps recorded since local midnight. Health Connect aggregates
  /// across all sources (watch + phone), so this matches what Samsung Health
  /// shows. Returns 0 when no data is recorded yet today.
  // UPDATED:
  // Calculates total steps for today, preferring smartwatch-originated data
  // (Samsung Watch, Fitbit, Garmin, WearOS/Pixel Watch, etc.) over phone
  // pedometer data to avoid double-counting.
  Future<int> stepsToday() async {
    try {
      await _ensureConfigured();
      final now = DateTime.now();
      final start = DateTime.utc(now.year, now.month, now.day, 0, 0, 0);
      final end = DateTime.utc(now.year, now.month, now.day + 1, 0, 0, 0);

      final points = await _health.getHealthDataFromTypes(
        types: const [HealthDataType.STEPS],
        startTime: start,
        endTime: end,
      );

      if (points.isEmpty) return 0;

      double watchSteps = 0;
      double phoneSteps = 0;

      for (var point in points) {
        if (point.value is! NumericHealthValue) continue;
        final val = (point.value as NumericHealthValue).numericValue.toDouble();
        final sourceName = point.sourceName.toLowerCase();
        final sourceId = point.sourceId.toLowerCase();
        final sourceCombined = '$sourceName|$sourceId';

        final isWatch = sourceCombined.contains('garmin') ||
            sourceCombined.contains('watch') ||
            sourceCombined.contains('galaxy watch') ||
            sourceCombined.contains('fitbit') ||
            sourceCombined.contains('garmin') ||
            sourceCombined.contains('wear os') ||
            sourceCombined.contains('pixel watch');

        final isPhone =
            sourceName.contains('android') || sourceId.contains('android');

        if (isWatch) {
          watchSteps += val;
        } else if (!isPhone) {
          // Samsung Health might contain aggregated data - treat as watch if it's the main source
          if (sourceCombined.contains('samsung')) {
            watchSteps += val;
          } else {
            phoneSteps += val;
          }
        }
      }

      return watchSteps > 0 ? watchSteps.round() : phoneSteps.round();
    } catch (e) {
      debugPrint('stepsToday() failed: $e');
      return 0;
    }
  }

  // UPDATED:
  // Calculates the total kilocalories burned today.
  Future<int> caloriesToday() async {
    try {
      await _ensureConfigured();
      final now = DateTime.now();
      final start = DateTime(now.year, now.month, now.day);
      final points = await _health.getHealthDataFromTypes(
        types: const [HealthDataType.ACTIVE_ENERGY_BURNED],
        startTime: start,
        endTime: now,
      );

      double totalCalories = 0;
      for (var point in points) {
        if (point.value is NumericHealthValue) {
          totalCalories +=
              (point.value as NumericHealthValue).numericValue.toDouble();
        }
      }
      return totalCalories.round();
    } catch (e) {
      debugPrint('caloriesToday() failed: $e');
      return 0;
    }
  }

  /// Snapshot of the metrics the wearables dashboard needs in one call. Each
  /// query is independent — if heart-rate fails we still return the steps.
  // UPDATED:
  // Includes caloriesToday in the returned execution pipeline snapshot.
  Future<HealthSnapshot> snapshot() async {
    final results = await Future.wait<dynamic>([
      latestHeartRate(),
      stepsToday(),
      caloriesToday(),
    ]);
    return HealthSnapshot(
      heartRate: results[0] as HeartRateSample?,
      stepsToday: results[1] as int,
      caloriesToday: results[2] as int,
      sampledAt: DateTime.now(),
    );
  }

  // UPDATE:
  // used for steps for the graph
  Future<int> getStepsForRange(
    DateTime start,
    DateTime end,
  ) async {
    try {
      await _ensureConfigured();

      final points = await _health.getHealthDataFromTypes(
        types: const [HealthDataType.STEPS],
        startTime: start,
        endTime: end,
      );

      double total = 0;

      for (final point in points) {
        if (point.value is NumericHealthValue) {
          total += (point.value as NumericHealthValue).numericValue.toDouble();
        }
      }

      return total.round();
    } catch (e) {
      debugPrint('getStepsForRange() failed: $e');
      return 0;
    }
  }

  // UPDATE:
  // For more accurate calculation
  Future<int> getDailySteps(
    DateTime start,
    DateTime end,
  ) async {
    try {
      await _ensureConfigured();

      final startUtc = DateTime.utc(start.year, start.month, start.day);
      final endUtc = DateTime.utc(end.year, end.month, end.day);

      final points = await _health.getHealthDataFromTypes(
        types: const [HealthDataType.STEPS],
        startTime: startUtc,
        endTime: endUtc,
      );

      double watchSteps = 0;
      double phoneSteps = 0;

      for (final point in points) {
        if (point.value is! NumericHealthValue) continue;

        final value =
            (point.value as NumericHealthValue).numericValue.toDouble();
        final sourceName = point.sourceName.toLowerCase();
        final sourceId = point.sourceId.toLowerCase();
        final sourceCombined = '$sourceName|$sourceId';

        // Detect watch sources
        final isWatch = sourceCombined.contains('garmin') ||
            sourceCombined.contains('watch') ||
            sourceCombined.contains('galaxy watch') ||
            sourceCombined.contains('fitbit') ||
            sourceCombined.contains('wear os') ||
            sourceCombined.contains('pixel watch') ||
            sourceCombined.contains('amazfit') ||
            sourceCombined.contains('huawei');

        // Detect phone sources (Android's built-in pedometer)
        final isPhone = sourceName.contains('android') ||
            sourceId.contains('android') ||
            sourceName.contains('google fit');

        if (isWatch) {
          watchSteps += value;
        } else if (isPhone) {
          phoneSteps += value;
        } else {
          watchSteps += value;
        }
      }

      return watchSteps > 0 ? watchSteps.round() : phoneSteps.round();
    } catch (e) {
      debugPrint('getDailySteps failed: $e');
      return 0;
    }
  }
}

/// One heart-rate reading, with the source app name (e.g. "Samsung Health")
/// so we can show the user where the number came from.
@immutable
class HeartRateSample {
  const HeartRateSample({
    required this.bpm,
    required this.sampledAt,
    required this.source,
  });

  final int bpm;
  final DateTime sampledAt;
  final String source;

  /// How long ago the reading was recorded — used to flag stale data in the
  /// UI (e.g. "10 min ago" → fine; "3 h ago" → user took the watch off).
  Duration get age => DateTime.now().difference(sampledAt);
}

/// Combined snapshot returned by `HealthService.snapshot()`.
@immutable
class HealthSnapshot {
  const HealthSnapshot({
    required this.heartRate,
    required this.stepsToday,
    required this.caloriesToday, // NEW FIELD
    required this.sampledAt,
  });

  final HeartRateSample? heartRate;
  final int stepsToday;
  final int caloriesToday; // NEW FIELD
  final DateTime sampledAt;

  bool get hasHeartRate => heartRate != null;
}
