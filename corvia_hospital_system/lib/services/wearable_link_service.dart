import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Common wearable brands the user can link. The list is intentionally
/// small — most users only own one type, and "Other" handles the long tail.
// UPDATE:
// I added: pixelWatch, amazfit, huaweiWatch
enum WearableType {
  samsungWatch,
  appleWatch,
  fitbit,
  garmin,
  pixelWatch,
  amazfit,
  huaweiWatch,
  miBand,
  other
}

extension WearableTypeMeta on WearableType {
  // UPDATE:
  // Added: pixelWatch,amazfit,huaweiWatch
  String get label => switch (this) {
        WearableType.samsungWatch => 'Samsung Galaxy Watch',
        WearableType.appleWatch => 'Apple Watch',
        WearableType.fitbit => 'Fitbit',
        WearableType.garmin => 'Garmin',
        WearableType.pixelWatch => 'Google Pixel Watch',
        WearableType.amazfit => 'Amazfit',
        WearableType.huaweiWatch => 'Huawei Watch',
        WearableType.miBand => 'Mi Band',
        WearableType.other => 'Other Device',
      };

  // UPDATE:
  // Added: pixelWatch,amazfit,huaweiWatch
  IconData get icon => switch (this) {
        WearableType.samsungWatch => Icons.watch,
        WearableType.appleWatch => Icons.watch,
        WearableType.fitbit => Icons.directions_run,
        WearableType.garmin => Icons.terrain,
        WearableType.pixelWatch => Icons.watch, // NEW
        WearableType.amazfit => Icons.watch, // NEW
        WearableType.huaweiWatch => Icons.watch, // NEW
        WearableType.miBand => Icons.fitness_center,
        WearableType.other => Icons.devices_other,
      };

  /// Which sync source this brand publishes to by default. Used to suggest
  /// the right pipeline when the user adds a new device.
  // UPDATE:
  // Added: pixelWatch, amazfit, huaweiWatch
  SyncSource get suggestedSource => switch (this) {
        WearableType.appleWatch => SyncSource.appleHealth,
        WearableType.samsungWatch => SyncSource.healthConnect,
        WearableType.fitbit => SyncSource.healthConnect,
        WearableType.garmin => SyncSource.healthConnect,
        WearableType.pixelWatch => SyncSource.healthConnect,
        WearableType.amazfit => SyncSource.healthConnect,
        WearableType.huaweiWatch => SyncSource.healthConnect,
        WearableType.miBand => SyncSource.healthConnect,
        WearableType.other => SyncSource.healthConnect,
      };
}

/// Where Corvia pulls vitals data from. On Android we read from Health
/// Connect (which Samsung Health, Fitbit, Google Fit, etc. all publish into).
/// On iOS we read from Apple HealthKit. "None" means manual data entry only.
// UPDATE:
// I updated it to make android devices connect to healthConnect and apple devices connect to appleHealth
// Apparently it is more optimal this way
enum SyncSource {
  none,
  healthConnect,
  appleHealth,
}

// UPDATE:
// Ensure that the description lets users know that active calorie data is gathered
extension SyncSourceMeta on SyncSource {
  String get label => switch (this) {
        SyncSource.none => 'Not syncing',
        SyncSource.healthConnect => 'Health Connect (Android)',
        SyncSource.appleHealth => 'Apple Health (iOS)',
      };

  String get description => switch (this) {
        SyncSource.none => 'Choose a source to start syncing health data.',
        SyncSource.healthConnect =>
          'Reads heart rate, steps, and calories from Garmin, Samsung, Fitbit, Pixel Watch, Amazfit and other Android wearables.',
        SyncSource.appleHealth =>
          'Reads heart rate, steps, and calories from Apple HealthKit.',
      };

  IconData get icon => switch (this) {
        SyncSource.none => Icons.sync_disabled,
        SyncSource.healthConnect => Icons.health_and_safety,
        SyncSource.appleHealth => Icons.favorite,
      };
}

/// A linked wearable. Stored locally; can later be mirrored to a `devices`
/// table in Supabase for cross-device sync.
@immutable
class LinkedDevice {
  final String id;
  final String name;
  final WearableType type;
  final DateTime addedAt;
  final DateTime? lastSyncedAt;

  const LinkedDevice({
    required this.id,
    required this.name,
    required this.type,
    required this.addedAt,
    this.lastSyncedAt,
  });

  LinkedDevice copyWith({DateTime? lastSyncedAt}) => LinkedDevice(
        id: id,
        name: name,
        type: type,
        addedAt: addedAt,
        lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'type': type.name,
        'addedAt': addedAt.toIso8601String(),
        'lastSyncedAt': lastSyncedAt?.toIso8601String(),
      };

  static LinkedDevice fromJson(Map<String, dynamic> json) => LinkedDevice(
        id: json['id'] as String,
        name: json['name'] as String,
        type: WearableType.values.firstWhere(
          (e) => e.name == json['type'],
          orElse: () => WearableType.other,
        ),
        addedAt: DateTime.parse(json['addedAt'] as String),
        lastSyncedAt: json['lastSyncedAt'] != null
            ? DateTime.tryParse(json['lastSyncedAt'] as String)
            : null,
      );
}

/// Manages the user's linked wearables and chosen sync source. Persists to
/// SharedPreferences so the state survives app restarts.
class WearableLinkService extends ChangeNotifier {
  WearableLinkService._();
  static final instance = WearableLinkService._();

  static const _kDevices = 'wearable_devices';
  static const _kSyncSource = 'wearable_sync_source';
  static const _kLastSync = 'wearable_last_sync';

  SharedPreferences? _prefs;
  bool _initialized = false;

  List<LinkedDevice> _devices = const [];
  SyncSource _syncSource = SyncSource.none;
  DateTime? _lastSyncAt;

  // ── Getters ────────────────────────────────────────────────────────────────

  bool get isInitialized => _initialized;
  List<LinkedDevice> get devices => List.unmodifiable(_devices);
  bool get hasLinkedDevice => _devices.isNotEmpty;
  SyncSource get syncSource => _syncSource;
  DateTime? get lastSyncAt => _lastSyncAt;
  bool get isReadyToSync =>
      _devices.isNotEmpty && _syncSource != SyncSource.none;

  // ── Init ───────────────────────────────────────────────────────────────────

  Future<void> init() async {
    if (_initialized) return;
    _prefs = await SharedPreferences.getInstance();

    final devicesJson = _prefs!.getString(_kDevices);
    if (devicesJson != null && devicesJson.isNotEmpty) {
      try {
        final list = jsonDecode(devicesJson) as List;
        _devices = list
            .map((e) => LinkedDevice.fromJson(e as Map<String, dynamic>))
            .toList();
      } catch (_) {
        _devices = const [];
      }
    }

    final sourceName = _prefs!.getString(_kSyncSource);
    if (sourceName != null) {
      _syncSource = SyncSource.values.firstWhere(
        (e) => e.name == sourceName,
        orElse: () => SyncSource.none,
      );
    }

    final lastSyncRaw = _prefs!.getString(_kLastSync);
    if (lastSyncRaw != null) _lastSyncAt = DateTime.tryParse(lastSyncRaw);

    _initialized = true;
    notifyListeners();
  }

  // ── Mutations ──────────────────────────────────────────────────────────────

  Future<void> addDevice({
    required String name,
    required WearableType type,
  }) async {
    await _ensureInit();
    final device = LinkedDevice(
      id: '${DateTime.now().millisecondsSinceEpoch}',
      name: name.trim().isEmpty ? type.label : name.trim(),
      type: type,
      addedAt: DateTime.now(),
    );
    _devices = [..._devices, device];

    // First device added — auto-suggest its native sync source so the user
    // doesn't have to hunt for the dropdown.
    if (_syncSource == SyncSource.none) {
      _syncSource = type.suggestedSource;
      await _prefs!.setString(_kSyncSource, _syncSource.name);
    }

    await _persist();
  }

  Future<void> removeDevice(String id) async {
    await _ensureInit();
    _devices = _devices.where((d) => d.id != id).toList();
    await _persist();
  }

  Future<void> setSyncSource(SyncSource source) async {
    await _ensureInit();
    if (_syncSource == source) return;
    _syncSource = source;
    await _prefs!.setString(_kSyncSource, source.name);
    notifyListeners();
  }

  /// Marks all linked devices as freshly synced. The actual data transfer
  /// happens on the native side via the existing `corvia/heart_rate` channel
  /// (or any future Health Connect/HealthKit bridge). This just records that
  /// the user triggered a sync.
  Future<bool> markSynced() async {
    await _ensureInit();
    if (!isReadyToSync) return false;
    final now = DateTime.now();
    _devices = _devices.map((d) => d.copyWith(lastSyncedAt: now)).toList();
    _lastSyncAt = now;
    await _prefs!.setString(_kLastSync, now.toIso8601String());
    await _persist();
    return true;
  }

  // ── Internal ───────────────────────────────────────────────────────────────

  Future<void> _ensureInit() async {
    if (!_initialized) await init();
  }

  Future<void> _persist() async {
    await _prefs!.setString(
      _kDevices,
      jsonEncode(_devices.map((d) => d.toJson()).toList()),
    );
    notifyListeners();
  }
}
