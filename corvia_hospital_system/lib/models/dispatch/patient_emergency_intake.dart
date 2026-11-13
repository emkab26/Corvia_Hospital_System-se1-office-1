enum PatientEmergencyFailureKind {
  authentication,
  configuration,
  invalidInput,
  conflict,
  unknown
}

/// Fixed messages only: RPC diagnostics can contain private information.
class PatientEmergencyIntakeException implements Exception {
  const PatientEmergencyIntakeException(this.kind);
  final PatientEmergencyFailureKind kind;
  String get message => switch (kind) {
        PatientEmergencyFailureKind.authentication =>
          'Your emergency access could not be verified. Sign in again or call directly.',
        PatientEmergencyFailureKind.configuration =>
          'Emergency requests are not configured for this backend. Call directly for help.',
        PatientEmergencyFailureKind.invalidInput =>
          'Check the emergency details and location before trying again.',
        PatientEmergencyFailureKind.conflict =>
          'The request has changed. Check its current status before trying again.',
        PatientEmergencyFailureKind.unknown =>
          'The request outcome could not be confirmed. Check its status before retrying.',
      };
  @override
  String toString() => message;
}

bool isEmergencyUuid(Object? value) =>
    value is String &&
    RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
      caseSensitive: false,
    ).hasMatch(value);

DateTime? _instant(Object? value) {
  if (value is! String) return null;
  final match = RegExp(
          r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.\d{1,6})?(?:Z|[+-](?:0\d|1[0-4]):[0-5]\d)$')
      .firstMatch(value);
  if (match == null) return null;
  final parts = [for (var i = 1; i <= 6; i++) int.parse(match.group(i)!)];
  final date = DateTime.utc(parts[0], parts[1], parts[2]);
  if (date.year != parts[0] ||
      date.month != parts[1] ||
      date.day != parts[2] ||
      parts[3] > 23 ||
      parts[4] > 59 ||
      parts[5] > 59) {
    return null;
  }
  return DateTime.tryParse(value)?.toUtc();
}

String? _text(String? value, int limit) {
  final clean = value?.trim();
  if (clean != null && clean.runes.length > limit) {
    throw const PatientEmergencyIntakeException(
        PatientEmergencyFailureKind.invalidInput);
  }
  return clean == null || clean.isEmpty ? null : clean;
}

/// Immutable request. GPS freshness is checked by the server only on creation;
/// replaying the same operation must keep its original GPS capture metadata.
class PatientEmergencyIntakeRequest {
  PatientEmergencyIntakeRequest(
      {this.latitude,
      this.longitude,
      this.accuracy,
      DateTime? capturedAt,
      String? address,
      String? details})
      : capturedAt = capturedAt?.toUtc(),
        address = _text(address, 300),
        details = _text(details, 1000) {
    final gps = latitude != null && longitude != null;
    if ((latitude == null) != (longitude == null) ||
        (gps &&
            (!latitude!.isFinite ||
                latitude!.abs() > 90 ||
                !longitude!.isFinite ||
                longitude!.abs() > 180 ||
                accuracy == null ||
                !accuracy!.isFinite ||
                accuracy! < 0 ||
                capturedAt == null)) ||
        (!gps && (accuracy != null || capturedAt != null))) {
      throw const PatientEmergencyIntakeException(
          PatientEmergencyFailureKind.invalidInput);
    }
  }
  final double? latitude;
  final double? longitude;
  final double? accuracy;
  final DateTime? capturedAt;
  final String? address;
  final String? details;
  String get locationSource => latitude != null
      ? 'gps'
      : address != null
          ? 'manual'
          : 'unavailable';

  Map<String, dynamic> toRpc(String operationId) => {
        'p_operation_id': operationId,
        'p_latitude': latitude,
        'p_longitude': longitude,
        'p_location_accuracy': accuracy,
        'p_location_captured_at': capturedAt?.toIso8601String(),
        'p_address': address,
        'p_details': details,
      };
  @override
  bool operator ==(Object other) =>
      other is PatientEmergencyIntakeRequest &&
      latitude == other.latitude &&
      longitude == other.longitude &&
      accuracy == other.accuracy &&
      capturedAt == other.capturedAt &&
      address == other.address &&
      details == other.details;
  @override
  int get hashCode =>
      Object.hash(latitude, longitude, accuracy, capturedAt, address, details);
}

class PatientEmergencyIncident {
  PatientEmergencyIncident._(
      {required this.operationId,
      required this.incidentId,
      required this.userId,
      required this.status,
      required this.version,
      required this.createdAt,
      required this.request});
  factory PatientEmergencyIncident.fromMap(Map<String, dynamic> map,
      {required String expectedUserId, required String expectedOperationId}) {
    const invalid =
        PatientEmergencyIntakeException(PatientEmergencyFailureKind.unknown);
    if (!const [
          'operation_id',
          'incident_id',
          'user_id',
          'status',
          'version',
          'created_at',
          'latitude',
          'longitude',
          'location_source',
          'location_accuracy',
          'location_captured_at',
          'address',
          'details'
        ].every(map.containsKey) ||
        !isEmergencyUuid(expectedUserId) ||
        !isEmergencyUuid(expectedOperationId) ||
        map['user_id'] != expectedUserId ||
        map['operation_id'] != expectedOperationId ||
        !_positiveBigInt(map['incident_id']) ||
        !_positiveBigInt(map['version']) ||
        !const {'pending', 'in_progress', 'resolved', 'cancelled'}
            .contains(map['status'])) {
      throw invalid;
    }
    final createdAt = _instant(map['created_at']);
    final capturedAt = map['location_captured_at'] == null
        ? null
        : _instant(map['location_captured_at']);
    if (createdAt == null ||
        (map['location_captured_at'] != null && capturedAt == null) ||
        (map['address'] != null && map['address'] is! String) ||
        (map['details'] != null && map['details'] is! String)) {
      throw invalid;
    }
    for (final key in ['latitude', 'longitude', 'location_accuracy']) {
      if (map[key] != null && map[key] is! num) throw invalid;
    }
    try {
      final request = PatientEmergencyIntakeRequest(
        latitude: (map['latitude'] as num?)?.toDouble(),
        longitude: (map['longitude'] as num?)?.toDouble(),
        accuracy: (map['location_accuracy'] as num?)?.toDouble(),
        capturedAt: capturedAt,
        address: map['address'] as String?,
        details: map['details'] as String?,
      );
      if (request.locationSource != map['location_source'] ||
          request.address != map['address'] ||
          request.details != map['details']) {
        throw invalid;
      }
      return PatientEmergencyIncident._(
          operationId: expectedOperationId,
          incidentId: map['incident_id'] as String,
          userId: expectedUserId,
          status: map['status'] as String,
          version: map['version'] as String,
          createdAt: createdAt,
          request: request);
    } on PatientEmergencyIntakeException {
      throw invalid;
    }
  }
  final String operationId;
  final String incidentId;
  final String userId;
  final String status;
  final String version;
  final DateTime createdAt;
  final PatientEmergencyIntakeRequest request;
  double? get latitude => request.latitude;
  double? get longitude => request.longitude;
  String get locationSource => request.locationSource;
  double? get locationAccuracy => request.accuracy;
  DateTime? get locationCapturedAt => request.capturedAt;
  String? get address => request.address;
  String? get details => request.details;
  bool get isTerminal => status == 'resolved' || status == 'cancelled';

  static bool _positiveBigInt(Object? value) =>
      value is String &&
      RegExp(r'^[1-9][0-9]*$').hasMatch(value) &&
      BigInt.parse(value) <= BigInt.parse('9223372036854775807');
}
