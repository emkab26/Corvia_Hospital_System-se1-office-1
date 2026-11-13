enum IncidentHistoryFailureKind {
  authentication,
  configuration,
  invalidResponse,
  unavailable,
}

/// Backend diagnostic text may contain private information and is never shown.
class IncidentHistoryException implements Exception {
  const IncidentHistoryException(this.kind);
  final IncidentHistoryFailureKind kind;
  String get message => switch (kind) {
        IncidentHistoryFailureKind.authentication =>
          'Your access to this request history could not be verified. Sign in again.',
        IncidentHistoryFailureKind.configuration =>
          'Request history is not configured for this backend.',
        IncidentHistoryFailureKind.invalidResponse =>
          'The request history could not be verified. Try loading it again.',
        IncidentHistoryFailureKind.unavailable =>
          'Request history is unavailable. Try loading it again.',
      };
  @override
  String toString() => message;
}

bool isIncidentHistoryId(Object? value) =>
    value is String &&
    RegExp(r'^[1-9][0-9]*$').hasMatch(value) &&
    value.length <= 19 &&
    BigInt.parse(value) <= BigInt.parse('9223372036854775807');

DateTime? _utcInstant(Object? value) {
  if (value is! String) return null;
  final match = RegExp(
          r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.\d{1,6})?(?:Z|\+00:00)$')
      .firstMatch(value);
  if (match == null) return null;
  final parts = [for (var i = 1; i <= 6; i++) int.parse(match.group(i)!)];
  final date = DateTime.utc(parts[0], parts[1], parts[2]);
  if (parts[0] == 0 ||
      date.year != parts[0] ||
      date.month != parts[1] ||
      date.day != parts[2] ||
      parts[3] > 23 ||
      parts[4] > 59 ||
      parts[5] > 59) {
    return null;
  }
  return DateTime.tryParse(value)?.toUtc();
}

class IncidentHistoryEvent {
  const IncidentHistoryEvent._({
    required this.version,
    required this.eventType,
    required this.recordedAt,
    required this.status,
    required this.previousStatus,
  });

  factory IncidentHistoryEvent.fromMap(Map<String, dynamic> map) {
    const invalid =
        IncidentHistoryException(IncidentHistoryFailureKind.invalidResponse);
    const keys = {
      'version',
      'event_type',
      'recorded_at',
      'status',
      'previous_status'
    };
    final recordedAt = _utcInstant(map['recorded_at']);
    if (map.length != keys.length ||
        !keys.every(map.containsKey) ||
        !isIncidentHistoryId(map['version']) ||
        recordedAt == null) {
      throw invalid;
    }
    final consistent = switch (map['event_type']) {
      'created' => map['status'] == 'pending' && map['previous_status'] == null,
      'claimed' =>
        map['status'] == 'in_progress' && map['previous_status'] == 'pending',
      'cancelled' =>
        map['status'] == 'cancelled' && map['previous_status'] == 'pending',
      'resolved' =>
        map['status'] == 'resolved' && map['previous_status'] == 'in_progress',
      'updated' => const {'pending', 'in_progress'}.contains(map['status']) &&
          map['previous_status'] == map['status'],
      _ => false,
    };
    if (!consistent ||
        (map['event_type'] == 'created' && map['version'] != '1')) {
      throw invalid;
    }
    return IncidentHistoryEvent._(
      version: map['version'] as String,
      eventType: map['event_type'] as String,
      recordedAt: recordedAt,
      status: map['status'] as String,
      previousStatus: map['previous_status'] as String?,
    );
  }

  final String version;
  final String eventType;
  final DateTime recordedAt;
  final String status;
  final String? previousStatus;
}

class IncidentHistory {
  IncidentHistory._(
      {required this.incidentId, required List<IncidentHistoryEvent> events})
      : events = List.unmodifiable(events);

  factory IncidentHistory.fromMap(Map<String, dynamic> map,
      {required String expectedIncidentId}) {
    const invalid =
        IncidentHistoryException(IncidentHistoryFailureKind.invalidResponse);
    if (map.length != 2 ||
        !map.containsKey('incident_id') ||
        !map.containsKey('events') ||
        !isIncidentHistoryId(expectedIncidentId) ||
        map['incident_id'] != expectedIncidentId ||
        map['events'] is! List ||
        (map['events'] as List).isEmpty ||
        (map['events'] as List).length > 100) {
      throw invalid;
    }
    final events = <IncidentHistoryEvent>[];
    var previousVersion = BigInt.zero;
    for (final raw in map['events'] as List) {
      if (raw is! Map<String, dynamic>) throw invalid;
      final event = IncidentHistoryEvent.fromMap(raw);
      final version = BigInt.parse(event.version);
      // The RPC returns the complete ledger, not a page or a partial history.
      if (version != previousVersion + BigInt.one ||
          (events.isEmpty && event.eventType != 'created') ||
          (events.isNotEmpty && event.previousStatus != events.last.status)) {
        throw invalid;
      }
      events.add(event);
      previousVersion = version;
    }
    return IncidentHistory._(incidentId: expectedIncidentId, events: events);
  }

  final String incidentId;
  final List<IncidentHistoryEvent> events;
}
