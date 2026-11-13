/// Proposed WS4 consumer contract. No production Fleet adapter is registered yet.
/// Server allocation must revalidate every selection; these DTOs grant no authority.
abstract interface class FleetAvailabilitySource {
  Future<FleetAvailabilitySnapshot> loadForIncident(String incidentId);
}

class FleetAvailabilityUnavailable implements Exception {
  const FleetAvailabilityUnavailable();
}

class FleetResourceOption {
  FleetResourceOption({
    required this.unitId,
    required this.organisationId,
    required this.crewManifestId,
    required this.revision,
    required this.eligible,
    required this.reason,
  }) {
    if ([unitId, organisationId, crewManifestId, revision, reason]
        .any((value) => value.trim().isEmpty)) {
      throw ArgumentError(
          'Fleet identity, revision and eligibility reason are required.');
    }
  }
  final String unitId;
  final String organisationId;
  final String crewManifestId;
  final String revision;
  final bool eligible;
  final String reason;
}

class FleetAvailabilitySnapshot {
  FleetAvailabilitySnapshot({
    required this.incidentId,
    required this.evaluatedAt,
    required this.validUntil,
    required List<FleetResourceOption> resources,
  }) : resources = List.unmodifiable(resources) {
    if (incidentId.trim().isEmpty || !validUntil.isAfter(evaluatedAt)) {
      throw ArgumentError(
          'Incident identity and a valid Fleet-supplied time window are required.');
    }
    if (resources.map((r) => r.unitId).toSet().length != resources.length) {
      throw ArgumentError('Fleet returned duplicate unit identities.');
    }
  }
  final String incidentId;
  final DateTime evaluatedAt;
  final DateTime validUntil;
  final List<FleetResourceOption> resources;

  /// Display/selection guard only. The server still owns allocation and policy.
  bool isCurrentAt(DateTime now) =>
      !now.isBefore(evaluatedAt) && now.isBefore(validUntil);
}
