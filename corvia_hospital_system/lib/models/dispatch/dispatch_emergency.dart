class DispatchEmergency {
  const DispatchEmergency({
    required this.id,
    required this.userId,
    required this.status,
    required this.createdAt,
    this.acceptedAt,
    this.assignedDispatcherUserId,
    this.latitude,
    this.longitude,
    this.address,
    this.details,
    this.locationSource,
    this.locationAccuracy,
    this.locationCapturedAt,
    this.hasIntakeDetails = false,
    this.intakeNeedsReview = false,
  });

  final String id;
  final String userId;
  final String status;
  final DateTime? createdAt;
  final DateTime? acceptedAt;
  final String? assignedDispatcherUserId;
  final double? latitude;
  final double? longitude;
  final String? address;
  final String? details;
  final String? locationSource;
  final double? locationAccuracy;
  final DateTime? locationCapturedAt;
  final bool hasIntakeDetails;
  final bool intakeNeedsReview;

  bool get isPending => status == 'pending';
  bool get isAccepted =>
      status == 'in_progress' &&
      assignedDispatcherUserId != null &&
      assignedDispatcherUserId!.isNotEmpty;

  String get coordinateLabel {
    final lat = latitude;
    final lng = longitude;

    if (intakeNeedsReview ||
        lat == null ||
        lng == null ||
        (lat == 0 && lng == 0 && locationSource != 'gps')) {
      return 'Location unavailable';
    }

    return '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}';
  }

  factory DispatchEmergency.fromMap(Map<String, dynamic> map,
      {bool expectIntakeDetails = false}) {
    const intakeKeys = {
      'address',
      'details',
      'location_source',
      'location_accuracy',
      'location_captured_at'
    };
    final hasIntake = expectIntakeDetails || intakeKeys.any(map.containsKey);
    final latitude = _coordinate(map['latitude'], 90);
    final longitude = _coordinate(map['longitude'], 180);
    final address = _boundedText(map['address'], 300);
    final details = _boundedText(map['details'], 1000);
    final source = map['location_source'] is String &&
            const {'gps', 'manual', 'unavailable', 'legacy'}
                .contains(map['location_source'])
        ? map['location_source'] as String
        : null;
    final accuracy = _accuracy(map['location_accuracy']);
    final captured = _capturedAt(map['location_captured_at']);
    final noCoordinates = map['latitude'] == null && map['longitude'] == null;
    final noMetadata =
        map['location_accuracy'] == null && map['location_captured_at'] == null;
    final validShape = source == 'gps'
        ? latitude != null &&
            longitude != null &&
            accuracy != null &&
            captured != null
        : source == 'legacy'
            ? latitude != null && longitude != null && noMetadata
            : source == 'manual'
                ? noCoordinates && noMetadata && address != null
                : source == 'unavailable' &&
                    noCoordinates &&
                    noMetadata &&
                    address == null;
    final invalidIntake = hasIntake &&
        (!intakeKeys.every(map.containsKey) ||
            (map['address'] != null && address == null) ||
            (map['details'] != null && details == null) ||
            !validShape);
    return DispatchEmergency(
      id: _incidentId(map['id']),
      userId: map['user_id']?.toString().trim() ?? '',
      status: _normaliseStatus(map['status']),
      createdAt: DateTime.tryParse(
        map['created_at']?.toString() ?? '',
      )?.toLocal(),
      acceptedAt: DateTime.tryParse(
        map['accepted_at']?.toString() ?? '',
      )?.toLocal(),
      assignedDispatcherUserId: _text(
        map['assigned_dispatcher_user_id'],
      ),
      latitude: latitude,
      longitude: longitude,
      address: address,
      details: details,
      locationSource: source,
      locationAccuracy: accuracy,
      locationCapturedAt: captured,
      hasIntakeDetails: hasIntake,
      intakeNeedsReview: invalidIntake,
    );
  }

  static String _normaliseStatus(dynamic value) {
    final status = value
        ?.toString()
        .trim()
        .toLowerCase()
        .replaceAll('-', '_')
        .replaceAll(' ', '_');

    return status == null || status.isEmpty ? 'unknown' : status;
  }

  static double? _coordinate(dynamic value, double bound) {
    final parsed = value is num ? value.toDouble() : double.tryParse('$value');
    return parsed != null && parsed.isFinite && parsed.abs() <= bound
        ? parsed
        : null;
  }

  bool get hasValidIdentity =>
      RegExp(r'^[1-9][0-9]*$').hasMatch(id) &&
      BigInt.tryParse(id) != null &&
      BigInt.parse(id) <= BigInt.parse('9223372036854775807');

  bool get canBeClaimed =>
      isPending &&
      !intakeNeedsReview &&
      hasValidIdentity &&
      userId.isNotEmpty &&
      createdAt != null &&
      (assignedDispatcherUserId == null || assignedDispatcherUserId!.isEmpty);

  bool get needsReview =>
      intakeNeedsReview ||
      !hasValidIdentity ||
      userId.isEmpty ||
      createdAt == null ||
      !const {'pending', 'in_progress', 'resolved', 'cancelled'}
          .contains(status) ||
      (isPending && assignedDispatcherUserId?.isNotEmpty == true);

  /// The legacy claim response omits additive immutable intake fields. Preserve
  /// them only on a confirmed claim for this exact incident and patient.
  DispatchEmergency withRetainedIntakeDetailsFrom(DispatchEmergency previous) {
    if (id != previous.id ||
        userId != previous.userId ||
        !isAccepted ||
        acceptedAt == null ||
        needsReview ||
        (previous.hasIntakeDetails &&
            (latitude != previous.latitude ||
                longitude != previous.longitude))) {
      throw const FormatException('The claim result could not be reconciled.');
    }
    if (hasIntakeDetails || !previous.hasIntakeDetails) {
      return this;
    }
    return DispatchEmergency(
      id: id,
      userId: userId,
      status: status,
      createdAt: createdAt,
      acceptedAt: acceptedAt,
      assignedDispatcherUserId: assignedDispatcherUserId,
      latitude: latitude,
      longitude: longitude,
      address: previous.address,
      details: previous.details,
      locationSource: previous.locationSource,
      locationAccuracy: previous.locationAccuracy,
      locationCapturedAt: previous.locationCapturedAt,
      hasIntakeDetails: previous.hasIntakeDetails,
      intakeNeedsReview: previous.intakeNeedsReview,
    );
  }

  static String? _boundedText(Object? value, int limit) {
    if (value is! String) {
      return null;
    }
    final text = value.trim();
    return text.isNotEmpty && text.runes.length <= limit ? text : null;
  }

  static String _incidentId(Object? value) {
    if (value is String) {
      return value.trim();
    }
    // Legacy PostgREST numbers can already be rounded by JavaScript JSON
    // parsing. Only exact strings may represent bigint IDs beyond this bound.
    if (value is num &&
        value.isFinite &&
        value > 0 &&
        value <= 9007199254740991 &&
        value == value.truncateToDouble()) {
      return value.toInt().toString();
    }
    return '';
  }

  static double? _accuracy(Object? value) {
    final number = value is num ? value.toDouble() : null;
    return number != null && number.isFinite && number >= 0 ? number : null;
  }

  static DateTime? _capturedAt(Object? value) {
    if (value is! String) {
      return null;
    }
    final date = RegExp(
      r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.\d{1,6})?(?:Z|[+-](?:0\d|1[0-4]):[0-5]\d)$',
    ).firstMatch(value);
    if (date == null) {
      return null;
    }
    final parsed = DateTime.tryParse(value);
    if (parsed == null) {
      return null;
    }
    final year = int.parse(date.group(1)!);
    final month = int.parse(date.group(2)!);
    final day = int.parse(date.group(3)!);
    final calendar = DateTime.utc(year, month, day);
    return calendar.year == year &&
            calendar.month == month &&
            calendar.day == day &&
            int.parse(date.group(4)!) < 24 &&
            int.parse(date.group(5)!) < 60 &&
            int.parse(date.group(6)!) < 60
        ? parsed.toUtc()
        : null;
  }

  static String? _text(dynamic value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }
}
