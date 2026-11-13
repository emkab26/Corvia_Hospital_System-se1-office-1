import 'package:flutter_test/flutter_test.dart';
import 'package:mycorvia/models/dispatch/dispatch_access_context.dart';

const _actor = '00000000-0000-4000-8000-000000000001';
const _organisation = '00000000-0000-4000-8000-000000000002';

Map<String, dynamic> _context() => {
      'user_id': _actor,
      'memberships': [
        {'organisation_id': _organisation, 'role': 'dispatcher'}
      ],
      'capabilities': ['read_incidents', 'claim_incident'],
      'policy_version': 'ws4-dev-core-1',
      'server_time': '2026-10-07T12:34:56.123456+00:00',
    };

DispatchAccessContext _parse(Map<String, dynamic> map) =>
    DispatchAccessContext.fromMap(map, expectedUserId: _actor);

void main() {
  test('valid server context binds identity, scope, capabilities and UTC time',
      () {
    final result = _parse(_context());
    expect(result.userId, _actor);
    expect(result.memberships.single.organisationId, _organisation);
    expect(result.memberships.single.role, 'dispatcher');
    expect(result.policyVersion, 'ws4-dev-core-1');
    expect(result.serverTime, DateTime.utc(2026, 10, 7, 12, 34, 56, 123, 456));
    expect(result.serverTime.isUtc, isTrue);
    expect(result.canReadIncidents, isTrue);
    expect(result.canClaimIncident, isTrue);
    expect(result.canReadIntakeDetails, isFalse);
    expect(result.isSupervisor, isFalse);
    expect(() => result.memberships.clear(), throwsUnsupportedError);
  });

  test('supervisor membership is presentation, not an implicit claim grant',
      () {
    final result = _parse({
      ..._context(),
      'memberships': [
        {'organisation_id': _organisation, 'role': 'dispatch_supervisor'}
      ],
      'capabilities': ['read_incidents', 'unknown_future_action', 'claim_all'],
    });
    expect(result.isSupervisor, isTrue);
    expect(result.canReadIncidents, isTrue);
    expect(result.canClaimIncident, isFalse);
  });

  test('input mutation cannot change the validated authority', () {
    final input = _context();
    final result = _parse(input);
    (input['memberships'] as List).clear();
    (input['capabilities'] as List).clear();
    expect(result.memberships, hasLength(1));
    expect(result.canClaimIncident, isTrue);
  });

  test('intake projection is enabled only by its explicit capability', () {
    expect(
        _parse({
          ..._context(),
          'capabilities': ['read_incidents', 'read_intake_details']
        }).canReadIntakeDetails,
        isTrue);
    expect(
        _parse({
          ..._context(),
          'capabilities': ['read_incidents', 'read_details']
        }).canReadIntakeDetails,
        isFalse);
  });

  final invalidFields = <String, List<Object?>>{
    'user_id': [null, '', _organisation, 1],
    'memberships': [
      null,
      [],
      'dispatcher',
      [null],
      [{}],
      [
        {'organisation_id': 'bad-id', 'role': 'dispatcher'}
      ],
      [
        {'organisation_id': _organisation, 'role': 'patient'}
      ],
      [
        {'organisation_id': _organisation, 'role': 'Dispatch Supervisor'}
      ],
      [
        {'organisation_id': _organisation, 'role': 'dispatcher'},
        {'organisation_id': _organisation, 'role': 'dispatch_supervisor'},
      ],
    ],
    'capabilities': [
      null,
      [],
      'read_incidents',
      ['claim_incident'],
      ['READ_INCIDENTS'],
      ['read_incidents', null]
    ],
    'policy_version': [null, '', 'ws4-dev-core-2', 1],
    'server_time': [
      null,
      '',
      '2026-10-07',
      '2026-10-07T12:34:56',
      '2026-02-31T12:34:56Z',
      '2026-10-07T25:34:56Z',
      '2026-10-07T12:60:56Z',
      '2026-10-07T12:34:60Z',
      1
    ],
  };
  for (final entry in invalidFields.entries) {
    for (var i = 0; i < entry.value.length; i++) {
      test('rejects untrusted ${entry.key} variant $i', () {
        expect(
          () => _parse({..._context(), entry.key: entry.value[i]}),
          throwsA(isA<DispatchAccessException>()),
        );
      });
    }
  }

  test('a timezone-bearing server instant is normalized to UTC', () {
    final result =
        _parse({..._context(), 'server_time': '2026-10-07T14:34:56+02:00'});
    expect(result.serverTime, DateTime.utc(2026, 10, 7, 12, 34, 56));
  });

  test('an invalid expected actor cannot authorize a matching response', () {
    expect(
      () => DispatchAccessContext.fromMap({..._context(), 'user_id': ''},
          expectedUserId: ''),
      throwsA(isA<DispatchAccessException>()),
    );
  });

  test('authority errors expose only fixed safe text', () {
    expect(const DispatchAccessException().toString(), isNot(contains(_actor)));
    expect(const DispatchAccessException.configuration().message,
        'Dispatch access is not configured for this backend. Contact the Corvia team.');
  });
}
