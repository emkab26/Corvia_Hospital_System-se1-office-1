import 'package:flutter_test/flutter_test.dart';
import 'package:mycorvia/services/dispatch/fleet_availability_contract.dart';

// Simulator exists only in tests. Missing real integrations never use this fallback.
class FixtureFleet implements FleetAvailabilitySource {
  FixtureFleet(this.snapshot);
  final FleetAvailabilitySnapshot? snapshot;
  @override
  Future<FleetAvailabilitySnapshot> loadForIncident(String incidentId) async {
    if (snapshot == null || snapshot!.incidentId != incidentId) {
      throw const FleetAvailabilityUnavailable();
    }
    return snapshot!;
  }
}

void main() {
  final time = DateTime.utc(2026, 10, 5);
  FleetAvailabilitySnapshot snapshot(List<FleetResourceOption> resources) =>
      FleetAvailabilitySnapshot(
          incidentId: '42',
          evaluatedAt: time,
          validUntil: time.add(const Duration(seconds: 30)),
          resources: resources);
  FleetResourceOption resource({String crew = 'crew-1'}) => FleetResourceOption(
      unitId: 'unit-1',
      organisationId: 'org-1',
      crewManifestId: crew,
      revision: 'v1',
      eligible: false,
      reason: 'Readiness not verified');
  test('unavailable provider differs from an authoritative empty fleet',
      () async {
    await expectLater(FixtureFleet(null).loadForIncident('42'),
        throwsA(isA<FleetAvailabilityUnavailable>()));
    expect((await FixtureFleet(snapshot([])).loadForIncident('42')).resources,
        isEmpty);
  });
  test('selection expires at Fleet-supplied time without inventing eligibility',
      () {
    final result = snapshot([resource()]);
    expect(result.isCurrentAt(time), isTrue);
    expect(
        result.isCurrentAt(time.subtract(const Duration(seconds: 1))), isFalse);
    expect(result.isCurrentAt(result.validUntil), isFalse);
    expect(result.resources.single.eligible, isFalse);
    expect(() => result.resources.clear(), throwsUnsupportedError);
  });
  test('incomplete crew identity and duplicate units cannot form a snapshot',
      () {
    expect(() => resource(crew: ''), throwsArgumentError);
    expect(() => snapshot([resource(), resource()]), throwsArgumentError);
  });
}
