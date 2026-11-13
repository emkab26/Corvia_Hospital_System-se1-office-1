class CorviaWearableSnapshot {
  const CorviaWearableSnapshot({
    this.snapshotVersion = 1,
    this.profileLabel = 'Corvia Patient',
    this.heartRateBpm,
    this.heartRateRecordedAt,
    this.nextMedicationName,
    this.nextMedicationAt,
    this.nextAppointmentTitle,
    this.nextAppointmentAt,
    this.pharmacyStatus,
    this.collectionReference,
    this.unreadNotifications = 0,
    this.emergencyProfileAvailable = false,
    this.sensitiveDetailsVisible = false,
    required this.syncedAt,
  });

  final int snapshotVersion;

  final String profileLabel;

  final double? heartRateBpm;
  final DateTime? heartRateRecordedAt;

  final String? nextMedicationName;
  final DateTime? nextMedicationAt;

  final String? nextAppointmentTitle;
  final DateTime? nextAppointmentAt;

  final String? pharmacyStatus;
  final String? collectionReference;

  final int unreadNotifications;

  final bool emergencyProfileAvailable;

  /// When false, the watch hides medication names, appointment
  /// information and collection references.
  final bool sensitiveDetailsVisible;

  final DateTime syncedAt;

  Map<String, Object> toPlatformMap() {
    return {
      'snapshotVersion': snapshotVersion,
      'profileLabel': _text(
        profileLabel,
        fallback: 'Corvia Patient',
      ),
      'heartRateBpm': heartRateBpm ?? -1.0,
      'heartRateRecordedAtEpochMs':
          heartRateRecordedAt?.millisecondsSinceEpoch ?? 0,
      'nextMedicationName': _text(
        nextMedicationName,
      ),
      'nextMedicationAtEpochMs': nextMedicationAt?.millisecondsSinceEpoch ?? 0,
      'nextAppointmentTitle': _text(
        nextAppointmentTitle,
      ),
      'nextAppointmentAtEpochMs':
          nextAppointmentAt?.millisecondsSinceEpoch ?? 0,
      'pharmacyStatus': _text(
        pharmacyStatus,
      ),
      'collectionReference': _text(
        collectionReference,
      ),
      'unreadNotifications': unreadNotifications < 0 ? 0 : unreadNotifications,
      'emergencyProfileAvailable': emergencyProfileAvailable,
      'sensitiveDetailsVisible': sensitiveDetailsVisible,
      'syncedAtEpochMs': syncedAt.millisecondsSinceEpoch,
    };
  }

  CorviaWearableSnapshot copyWith({
    int? snapshotVersion,
    String? profileLabel,
    double? heartRateBpm,
    DateTime? heartRateRecordedAt,
    String? nextMedicationName,
    DateTime? nextMedicationAt,
    String? nextAppointmentTitle,
    DateTime? nextAppointmentAt,
    String? pharmacyStatus,
    String? collectionReference,
    int? unreadNotifications,
    bool? emergencyProfileAvailable,
    bool? sensitiveDetailsVisible,
    DateTime? syncedAt,
  }) {
    return CorviaWearableSnapshot(
      snapshotVersion: snapshotVersion ?? this.snapshotVersion,
      profileLabel: profileLabel ?? this.profileLabel,
      heartRateBpm: heartRateBpm ?? this.heartRateBpm,
      heartRateRecordedAt: heartRateRecordedAt ?? this.heartRateRecordedAt,
      nextMedicationName: nextMedicationName ?? this.nextMedicationName,
      nextMedicationAt: nextMedicationAt ?? this.nextMedicationAt,
      nextAppointmentTitle: nextAppointmentTitle ?? this.nextAppointmentTitle,
      nextAppointmentAt: nextAppointmentAt ?? this.nextAppointmentAt,
      pharmacyStatus: pharmacyStatus ?? this.pharmacyStatus,
      collectionReference: collectionReference ?? this.collectionReference,
      unreadNotifications: unreadNotifications ?? this.unreadNotifications,
      emergencyProfileAvailable:
          emergencyProfileAvailable ?? this.emergencyProfileAvailable,
      sensitiveDetailsVisible:
          sensitiveDetailsVisible ?? this.sensitiveDetailsVisible,
      syncedAt: syncedAt ?? this.syncedAt,
    );
  }

  static String _text(
    String? value, {
    String fallback = '',
  }) {
    final cleaned = value?.trim();

    if (cleaned == null || cleaned.isEmpty) {
      return fallback;
    }

    return cleaned;
  }
}
