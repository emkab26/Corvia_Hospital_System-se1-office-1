/// Server-issued dispatch authority. Profile roles and UI routes do not grant it.
class DispatchAccessContext {
  DispatchAccessContext._({
    required this.userId,
    required List<DispatchMembership> memberships,
    required Set<String> capabilities,
    required this.policyVersion,
    required this.serverTime,
  })  : memberships = List.unmodifiable(memberships),
        _capabilities = Set.unmodifiable(capabilities);

  factory DispatchAccessContext.fromMap(
    Map<String, dynamic> map, {
    required String expectedUserId,
  }) {
    final userId = map['user_id'];
    final rawMemberships = map['memberships'];
    final rawCapabilities = map['capabilities'];
    final policyVersion = map['policy_version'];
    final serverTime = _parseServerTime(map['server_time']);
    if (!_isUuid(expectedUserId) ||
        userId != expectedUserId ||
        rawMemberships is! List ||
        rawMemberships.isEmpty ||
        rawCapabilities is! List ||
        rawCapabilities.any((value) => value is! String || value.isEmpty) ||
        policyVersion != 'ws4-dev-core-1' ||
        serverTime == null) {
      throw const DispatchAccessException();
    }

    final memberships = <DispatchMembership>[];
    final organisations = <String>{};
    for (final raw in rawMemberships) {
      if (raw is! Map) throw const DispatchAccessException();
      final organisationId = raw['organisation_id'];
      final role = raw['role'];
      if (!_isUuid(organisationId) ||
          !const {'dispatcher', 'dispatch_supervisor'}.contains(role) ||
          !organisations.add((organisationId as String).toLowerCase())) {
        throw const DispatchAccessException();
      }
      memberships.add(DispatchMembership._(organisationId, role as String));
    }

    // Unknown capabilities never grant an action. Read access is mandatory;
    // claim may be absent so a valid read-only context remains usable.
    final capabilities = rawCapabilities
        .whereType<String>()
        .where(const {
          'read_incidents',
          'claim_incident',
          'read_intake_details',
          'read_incident_history',
          'incident_workspace',
        }.contains)
        .toSet();
    if (!capabilities.contains('read_incidents')) {
      throw const DispatchAccessException();
    }
    return DispatchAccessContext._(
      userId: userId as String,
      memberships: memberships,
      capabilities: capabilities,
      policyVersion: policyVersion as String,
      serverTime: serverTime,
    );
  }

  final String userId;
  final List<DispatchMembership> memberships;
  final Set<String> _capabilities;
  final String policyVersion;
  final DateTime serverTime;

  bool get canReadIncidents => _capabilities.contains('read_incidents');
  bool get canClaimIncident => _capabilities.contains('claim_incident');
  bool get canReadIntakeDetails =>
      _capabilities.contains('read_intake_details');
  bool get canReadIncidentHistory =>
      _capabilities.contains('read_incident_history');
  bool get canUseIncidentWorkspace =>
      _capabilities.contains('incident_workspace');

  /// Presentation only. A supervisor in one organisation is not authority to
  /// override another organisation; future commands require scoped capabilities.
  bool get isSupervisor =>
      memberships.any((membership) => membership.role == 'dispatch_supervisor');

  static bool _isUuid(Object? value) =>
      value is String &&
      RegExp(
        r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
        caseSensitive: false,
      ).hasMatch(value);

  static DateTime? _parseServerTime(Object? value) {
    if (value is! String) return null;
    final match = RegExp(
      r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.\d{1,6})?(?:Z|[+-](?:0\d|1[0-4]):[0-5]\d)$',
    ).firstMatch(value);
    if (match == null) return null;
    final parts = [for (var i = 1; i <= 6; i++) int.parse(match.group(i)!)];
    final calendar = DateTime.utc(parts[0], parts[1], parts[2]);
    // DateTime.parse normalizes invalid dates; authority responses must not.
    if (calendar.year != parts[0] ||
        calendar.month != parts[1] ||
        calendar.day != parts[2] ||
        parts[3] > 23 ||
        parts[4] > 59 ||
        parts[5] > 59) {
      return null;
    }
    return DateTime.tryParse(value)?.toUtc();
  }
}

class DispatchMembership {
  const DispatchMembership._(this.organisationId, this.role);

  final String organisationId;
  final String role;
}

/// Deliberately fixed messages: untrusted RPC data never reaches UI diagnostics.
class DispatchAccessException implements Exception {
  const DispatchAccessException()
      : message =
            'Dispatch access could not be verified. Refresh or sign in again.';

  const DispatchAccessException.configuration()
      : message = 'Dispatch access is not configured for this backend. '
            'Contact the Corvia team.';

  final String message;

  @override
  String toString() => message;
}
