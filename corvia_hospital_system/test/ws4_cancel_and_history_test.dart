import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mycorvia/controllers/patient_emergency_intake_controller.dart';
import 'package:mycorvia/services/incident_history_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/ws4_http_fixture.dart';
import 'support/ws4_patient_intake_fixture.dart';

const _incidentId = '9007199254740993';

Map<String, dynamic> _cancelled({String version = '2'}) =>
    {...intakeResponse(status: 'cancelled'), 'version': version};

PatientEmergencyIncident _incident(Map<String, dynamic> response) =>
    PatientEmergencyIncident.fromMap(response,
        expectedUserId: fixtureActor, expectedOperationId: intakeOperation);

Map<String, dynamic> _event({String version = '1', String type = 'created'}) =>
    {
      'version': version,
      'event_type': type,
      'recorded_at': '2026-10-07T12:00:00Z',
      'status': type == 'created'
          ? 'pending'
          : type == 'claimed'
              ? 'in_progress'
              : type,
      'previous_status': type == 'created'
          ? null
          : type == 'resolved'
              ? 'in_progress'
              : 'pending',
    };

Map<String, dynamic> _history({String incidentId = _incidentId}) => {
      'incident_id': incidentId,
      'events': [_event(), _event(version: '2', type: 'cancelled')],
    };

Matcher _intakeFails(PatientEmergencyFailureKind kind) =>
    throwsA(isA<PatientEmergencyIntakeException>()
        .having((error) => error.kind, 'kind', kind));
Matcher _historyFails(IncidentHistoryFailureKind kind) =>
    throwsA(isA<IncidentHistoryException>()
        .having((error) => error.kind, 'kind', kind));

class _Store implements PatientEmergencyOperationStore {
  String? operation = intakeOperation;
  var writes = 0;
  @override
  Future<String?> read(String userId) async => operation;
  @override
  Future<void> write(String userId, String operationId) async {
    writes++;
    operation = operationId;
  }

  @override
  Future<void> remove(String userId) async => operation = null;
}

class _Gateway implements PatientEmergencyIntakeGateway {
  String? actor = fixtureActor;
  final cancellations = <(String, String, String)>[];
  var lookups = 0;
  var requests = 0;
  Future<PatientEmergencyIncident> Function()? onCancel;
  Future<PatientEmergencyIncident?> Function()? onLookup;
  @override
  String? get currentUserId => actor;
  @override
  Future<PatientEmergencyIncident> cancel(
      {required String userId,
      required String operationId,
      required String expectedVersion}) {
    cancellations.add((userId, operationId, expectedVersion));
    return onCancel?.call() ?? Future.value(_incident(_cancelled()));
  }

  @override
  Future<PatientEmergencyIncident?> lookup(
      {required String userId, required String operationId}) {
    lookups++;
    return onLookup?.call() ?? Future.value(intakeIncident());
  }

  @override
  Future<PatientEmergencyIncident> request(
      {required String userId,
      required String operationId,
      required PatientEmergencyIntakeRequest input}) {
    requests++;
    return Future.value(intakeIncident());
  }
}

Future<PatientEmergencyIntakeController> _controller(_Gateway gateway,
    {Duration timeout = const Duration(seconds: 15), _Store? store}) async {
  final controller = PatientEmergencyIntakeController(
      gateway: gateway, operationStore: store ?? _Store(), timeout: timeout);
  addTearDown(controller.dispose);
  await controller.initialize();
  return controller;
}

void main() {
  test('cancel sends the existing operation and bigint version as strings',
      () async {
    var calls = 0;
    final client = await fixtureClient((request) async {
      calls++;
      expect(request.url.path, '/rest/v1/rpc/corvia_patient_cancel_emergency');
      expect(jsonDecode(request.body), {
        'p_operation_id': intakeOperation,
        'p_expected_version': '9007199254740993'
      });
      return jsonResponse(_cancelled(version: '9007199254740994'));
    });
    addTearDown(client.dispose);
    final result = await PatientEmergencyIntakeService(client: client).cancel(
        userId: fixtureActor,
        operationId: intakeOperation,
        expectedVersion: '9007199254740993');
    expect(result.status, 'cancelled');
    expect(result.version, '9007199254740994');
    expect(calls, 1);
  });

  for (final field in <String, Object?>{
    'operation_id': nextIntakeOperation,
    'user_id': nextIntakeOperation,
    'incident_id': 1,
    'status': 'pending',
    'version': '1',
    'created_at': '2026-02-31T12:00:00Z',
  }.entries) {
    test('cancel rejects malformed or mismatched ${field.key}', () async {
      final client = await fixtureClient(
          (_) async => jsonResponse({..._cancelled(), field.key: field.value}));
      addTearDown(client.dispose);
      await expectLater(
          PatientEmergencyIntakeService(client: client).cancel(
              userId: fixtureActor,
              operationId: intakeOperation,
              expectedVersion: '1'),
          _intakeFails(PatientEmergencyFailureKind.unknown));
    });
  }

  for (final entry in {
    'P0001': PatientEmergencyFailureKind.conflict,
    '22023': PatientEmergencyFailureKind.invalidInput,
    '42501': PatientEmergencyFailureKind.authentication,
    'PGRST301': PatientEmergencyFailureKind.authentication,
    'PGRST302': PatientEmergencyFailureKind.authentication,
    'PGRST303': PatientEmergencyFailureKind.authentication,
    'PGRST202': PatientEmergencyFailureKind.configuration,
    '42883': PatientEmergencyFailureKind.configuration,
    'XX000': PatientEmergencyFailureKind.unknown,
  }.entries) {
    test('cancellation classifies ${entry.key} using a safe fixed error',
        () async {
      final client = await fixtureClient((_) async => jsonResponse(
          {'code': entry.key, 'message': 'private patient detail'},
          status: 400));
      addTearDown(client.dispose);
      await expectLater(
          PatientEmergencyIntakeService(client: client).cancel(
              userId: fixtureActor,
              operationId: intakeOperation,
              expectedVersion: '1'),
          _intakeFails(entry.value));
      expect(PatientEmergencyIntakeException(entry.value).message,
          isNot(contains('private')));
    });
  }

  test('invalid cancel version and wrong bound actor send no request',
      () async {
    var calls = 0;
    final client = await fixtureClient((_) async {
      calls++;
      return jsonResponse(_cancelled());
    });
    addTearDown(client.dispose);
    final service = PatientEmergencyIntakeService(client: client);
    for (final version in [
      '0',
      '01',
      '-1',
      '9223372036854775807',
      '9223372036854775808'
    ]) {
      await expectLater(
          service.cancel(
              userId: fixtureActor,
              operationId: intakeOperation,
              expectedVersion: version),
          _intakeFails(PatientEmergencyFailureKind.invalidInput));
    }
    await expectLater(
        service.cancel(
            userId: nextIntakeOperation,
            operationId: intakeOperation,
            expectedVersion: '1'),
        _intakeFails(PatientEmergencyFailureKind.authentication));
    expect(calls, 0);
  });

  test(
      'controller cancels only pending confirmation and serializes double taps',
      () async {
    final response = Completer<PatientEmergencyIncident>();
    final gateway = _Gateway()..onCancel = () => response.future;
    final store = _Store();
    final controller = await _controller(gateway, store: store);
    expect(gateway.cancellations, isEmpty);
    expect(controller.canCancel, isTrue);
    final pending = controller.cancel();
    await controller.cancel();
    expect(controller.phase, PatientEmergencyIntakePhase.cancelling);
    expect(controller.isBusy, isTrue);
    expect(controller.incident!.status, 'pending');
    expect(gateway.cancellations, [(fixtureActor, intakeOperation, '1')]);
    response.complete(_incident(_cancelled()));
    await pending;
    expect(controller.incident!.status, 'cancelled');
    expect(controller.canCancel, isFalse);
    expect(controller.canStartNewRequest, isTrue);
    expect(controller.cancellationUnconfirmed, isFalse);
    expect(store.operation, intakeOperation);
    expect(store.writes, 0);
    expect(gateway.requests, 0);
  });

  for (final status in ['in_progress', 'resolved', 'cancelled']) {
    test('controller never cancels $status requests', () async {
      final gateway = _Gateway()
        ..onLookup = () async => intakeIncident(status: status);
      final controller = await _controller(gateway);
      await controller.cancel();
      expect(controller.canCancel, isFalse);
      expect(gateway.cancellations, isEmpty);
    });
  }

  test('conflict recovers dispatcher claim without reporting cancellation',
      () async {
    final gateway = _Gateway()
      ..onCancel = () async => throw const PatientEmergencyIntakeException(
          PatientEmergencyFailureKind.conflict);
    final controller = await _controller(gateway);
    gateway.onLookup = () async =>
        _incident({...intakeResponse(status: 'in_progress'), 'version': '2'});
    await controller.cancel();
    expect(controller.phase, PatientEmergencyIntakePhase.confirmed);
    expect(controller.incident!.status, 'in_progress');
    expect(controller.canCancel, isFalse);
    expect(controller.errorMessage, contains('not cancelled'));
    expect(gateway.cancellations, hasLength(1));
    expect(gateway.lookups, 2);
  });

  test(
      'uncertain cancellation retains snapshot until lookup then explicit same-version retry',
      () async {
    final gateway = _Gateway()
      ..onCancel = () async => throw StateError('private response lost');
    final controller = await _controller(gateway);
    await controller.cancel();
    expect(controller.phase, PatientEmergencyIntakePhase.unknown);
    expect(controller.incident!.status, 'pending');
    expect(controller.errorMessage,
        startsWith('Cancellation could not be confirmed'));
    expect(controller.errorMessage, isNot(contains('private')));
    expect(controller.canCancel, isFalse);
    await controller.cancel();
    expect(gateway.cancellations, hasLength(1));
    await controller.reconcile();
    expect(controller.canCancel, isTrue);
    expect(gateway.cancellations, hasLength(1));
    gateway.onCancel = null;
    await controller.cancel();
    expect(gateway.cancellations, [
      (fixtureActor, intakeOperation, '1'),
      (fixtureActor, intakeOperation, '1')
    ]);
    expect(controller.incident!.status, 'cancelled');
  });

  test('absent lookup after cancellation never permits a new submission',
      () async {
    final gateway = _Gateway()
      ..onCancel = () async => throw const PatientEmergencyIntakeException(
          PatientEmergencyFailureKind.conflict);
    final controller = await _controller(gateway);
    gateway.onLookup = () async => null;
    await controller.cancel();
    expect(controller.phase, PatientEmergencyIntakePhase.unknown);
    expect(controller.incident!.status, 'pending');
    expect(controller.canSubmit, isFalse);
    expect(controller.canCancel, isFalse);
    expect(controller.canStartNewRequest, isFalse);
    await controller.retry();
    expect(gateway.cancellations, hasLength(1));
    expect(gateway.requests, 0);
  });

  test(
      'absent refresh of an existing incident keeps its last confirmed snapshot',
      () async {
    final gateway = _Gateway();
    final controller = await _controller(gateway);
    gateway.onLookup = () async => null;
    await controller.reconcile();
    expect(controller.phase, PatientEmergencyIntakePhase.unknown);
    expect(controller.incident!.incidentId, _incidentId);
    expect(controller.canSubmit, isFalse);
    expect(controller.canCancel, isFalse);
    expect(gateway.requests, 0);
  });

  for (final changes in <Map<String, dynamic>>[
    {'incident_id': '7'},
    {'status': 'in_progress'},
    {'version': '1'},
    {'created_at': '2026-10-07T12:01:00Z'},
    {'address': 'Changed', 'location_source': 'manual'},
  ]) {
    test(
        'refresh rejects changed identity, data, or nonmonotonic status $changes',
        () async {
      final original = {...intakeResponse(), 'version': '2'};
      final gateway = _Gateway()..onLookup = () async => _incident(original);
      final controller = await _controller(gateway);
      gateway.onLookup = () async => _incident({...original, ...changes});
      await controller.reconcile();
      expect(controller.phase, PatientEmergencyIntakePhase.unknown);
      expect(controller.incident!.incidentId, _incidentId);
      expect(controller.incident!.status, 'pending');
      expect(controller.incident!.version, '2');
      expect(controller.canSubmit, isFalse);
      expect(controller.canCancel, isFalse);
    });
  }

  test('timed-out cancellation ignores late result after authoritative lookup',
      () async {
    final response = Completer<PatientEmergencyIncident>();
    final gateway = _Gateway()..onCancel = () => response.future;
    final controller =
        await _controller(gateway, timeout: const Duration(milliseconds: 1));
    await controller.cancel();
    expect(controller.phase, PatientEmergencyIntakePhase.unknown);
    expect(controller.cancellationUnconfirmed, isTrue);
    expect(controller.incident!.status, 'pending');
    gateway.onLookup = () async =>
        _incident({...intakeResponse(status: 'in_progress'), 'version': '2'});
    await controller.reconcile();
    response.complete(_incident(_cancelled()));
    await Future<void>.delayed(Duration.zero);
    expect(controller.incident!.status, 'in_progress');
    expect(gateway.cancellations, hasLength(1));
  });

  for (final changes in <Map<String, dynamic>>[
    {'incident_id': '7'},
    {'version': '3'},
    {'status': 'in_progress'},
    {'address': 'Changed', 'location_source': 'manual'}
  ]) {
    test('controller rejects inconsistent cancellation $changes', () async {
      final gateway = _Gateway()
        ..onCancel = () async => _incident({..._cancelled(), ...changes});
      final controller = await _controller(gateway);
      await controller.cancel();
      expect(controller.phase, PatientEmergencyIntakePhase.unknown);
      expect(controller.incident!.status, 'pending');
      expect(controller.canStartNewRequest, isFalse);
    });
  }

  test('denial clears prior sensitive snapshot and blocks cancellation',
      () async {
    final gateway = _Gateway()
      ..onCancel = () async => throw const PatientEmergencyIntakeException(
          PatientEmergencyFailureKind.authentication);
    final controller = await _controller(gateway);
    await controller.cancel();
    expect(controller.phase, PatientEmergencyIntakePhase.blocked);
    expect(controller.incident, isNull);
    expect(controller.submittedRequest, isNull);
    expect(controller.canCancel, isFalse);
  });

  for (final disposed in [false, true]) {
    test(
        'late cancel response after ${disposed ? 'dispose' : 'actor change'} cannot restore state',
        () async {
      final response = Completer<PatientEmergencyIncident>();
      final gateway = _Gateway()..onCancel = () => response.future;
      final controller = PatientEmergencyIntakeController(
          gateway: gateway, operationStore: _Store());
      await controller.initialize();
      var notifications = 0;
      controller.addListener(() => notifications++);
      final pending = controller.cancel();
      if (disposed) {
        controller.dispose();
      } else {
        gateway.actor = null;
      }
      final before = notifications;
      response.complete(_incident(_cancelled()));
      await pending;
      expect(controller.incident, isNull);
      if (disposed) {
        expect(notifications, before);
      } else {
        expect(controller.phase, PatientEmergencyIntakePhase.blocked);
        controller.dispose();
      }
    });
  }

  test('history preserves bigint strings and immutable ordered events', () {
    final value =
        IncidentHistory.fromMap(_history(), expectedIncidentId: _incidentId);
    expect(value.incidentId, _incidentId);
    expect(value.events.map((event) => event.version), ['1', '2']);
    expect(value.events.last.eventType, 'cancelled');
    expect(value.events.last.recordedAt.isUtc, isTrue);
    expect(() => value.events.clear(), throwsUnsupportedError);
    expect(
        () => IncidentHistory.fromMap(
            {'incident_id': _incidentId, 'events': []},
            expectedIncidentId: _incidentId),
        _historyFails(IncidentHistoryFailureKind.invalidResponse));
  });

  for (final changes in <Map<String, dynamic>>[
    {'version': 1},
    {'version': '0'},
    {'version': '01'},
    {'version': '9223372036854775808'},
    {'event_type': 'assigned'},
    {'status': 'resolved'},
    {'previous_status': 'pending'},
    {'recorded_at': '2026-02-31T12:00:00Z'},
    {'recorded_at': '2026-10-07T25:00:00Z'},
    {'recorded_at': '2026-10-07T12:00:00+02:00'},
    {'recorded_at': '2026-10-07T12:00:00'},
    {'actor_user_id': fixtureActor},
  ]) {
    test('history rejects malformed event $changes', () {
      expect(
          () => IncidentHistory.fromMap({
                'incident_id': _incidentId,
                'events': [
                  {..._event(), ...changes}
                ]
              }, expectedIncidentId: _incidentId),
          _historyFails(IncidentHistoryFailureKind.invalidResponse));
    });
  }

  test(
      'history rejects wrong incident, duplicate or reversed versions, missing keys and oversize',
      () {
    for (final response in [
      {..._history(), 'incident_id': '7'},
      {..._history(), 'incident_id': 7},
      {..._history(), 'unexpected': true},
      {
        'incident_id': _incidentId,
        'events': [_event(), _event()]
      },
      {
        'incident_id': _incidentId,
        'events': [_event(version: '2', type: 'claimed'), _event()]
      },
      {
        'incident_id': _incidentId,
        'events': [_event()..remove('previous_status')]
      },
      {
        'incident_id': _incidentId,
        'events': List.generate(
            101, (index) => _event(version: '${index + 1}', type: 'claimed'))
      },
    ]) {
      expect(
          () => IncidentHistory.fromMap(response,
              expectedIncidentId: _incidentId),
          _historyFails(IncidentHistoryFailureKind.invalidResponse));
    }
  });

  for (final entry in <String, List<Map<String, dynamic>>>{
    'missing creation': [_event(version: '2', type: 'claimed')],
    'resolution as first event': [_event(type: 'resolved')],
    'version gap': [_event(), _event(version: '3', type: 'cancelled')],
    'resolution without claim': [
      _event(),
      _event(version: '2', type: 'resolved')
    ],
    'claim after cancellation': [
      _event(),
      _event(version: '2', type: 'cancelled'),
      _event(version: '3', type: 'claimed'),
    ],
    'cancellation after claim': [
      _event(),
      _event(version: '2', type: 'claimed'),
      _event(version: '3', type: 'cancelled'),
    ],
    'claim after resolution': [
      _event(),
      _event(version: '2', type: 'claimed'),
      _event(version: '3', type: 'resolved'),
      _event(version: '4', type: 'claimed'),
    ],
  }.entries) {
    test('complete history rejects ${entry.key}', () {
      expect(
          () => IncidentHistory.fromMap(
              {'incident_id': _incidentId, 'events': entry.value},
              expectedIncidentId: _incidentId),
          _historyFails(IncidentHistoryFailureKind.invalidResponse));
    });
  }

  test('history accepts supported event transitions and zero-offset UTC', () {
    final result = IncidentHistory.fromMap({
      'incident_id': _incidentId,
      'events': [
        _event(),
        _event(version: '2', type: 'claimed'),
        {
          ..._event(version: '3', type: 'resolved'),
          'recorded_at': '2026-10-07T12:00:00.123456+00:00'
        },
      ]
    }, expectedIncidentId: _incidentId);
    expect(result.events.last.status, 'resolved');
  });

  test(
      'history load calls only scoped RPC and supports independent concurrent loads',
      () async {
    final firstResponse = Completer<http.Response>();
    final firstStarted = Completer<void>();
    final client = await fixtureClient((request) async {
      expect(request.url.path, '/rest/v1/rpc/corvia_incident_history');
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      expect(body.keys, ['p_incident_id']);
      if (body['p_incident_id'] == _incidentId) {
        firstStarted.complete();
        return firstResponse.future;
      }
      return jsonResponse(_history(incidentId: '7'));
    });
    addTearDown(client.dispose);
    final service = IncidentHistoryService(client: client);
    final first = service.load(_incidentId);
    await firstStarted.future;
    final second = await service.load('7');
    expect(second.incidentId, '7');
    firstResponse.complete(jsonResponse(_history()));
    expect((await first).incidentId, _incidentId);
  });

  for (final entry in {
    '42501': IncidentHistoryFailureKind.authentication,
    'PGRST301': IncidentHistoryFailureKind.authentication,
    'PGRST302': IncidentHistoryFailureKind.authentication,
    'PGRST303': IncidentHistoryFailureKind.authentication,
    'PGRST202': IncidentHistoryFailureKind.configuration,
    '42883': IncidentHistoryFailureKind.configuration,
    'XX000': IncidentHistoryFailureKind.unavailable,
  }.entries) {
    test('history classifies ${entry.key} without exposing diagnostics',
        () async {
      final client = await fixtureClient((_) async => jsonResponse(
          {'code': entry.key, 'message': 'private history detail'},
          status: 400));
      addTearDown(client.dispose);
      await expectLater(
          IncidentHistoryService(client: client).load(_incidentId),
          _historyFails(entry.value));
      expect(IncidentHistoryException(entry.value).message,
          isNot(contains('private')));
    });
  }

  for (final history in [false, true]) {
    for (final signOut in [false, true]) {
      test(
          '${history ? 'history' : 'cancel'} withholds response after ${signOut ? 'signout' : 'account switch'}',
          () async {
        final response = Completer<http.Response>();
        final started = Completer<void>();
        final client = await fixtureClient((request) async {
          if (request.url.path.contains('/rest/v1/rpc/')) {
            started.complete();
            return response.future;
          }
          return jsonResponse(null);
        });
        addTearDown(client.dispose);
        final Future<Object> pending = history
            ? IncidentHistoryService(client: client).load(_incidentId)
            : PatientEmergencyIntakeService(client: client).cancel(
                userId: fixtureActor,
                operationId: intakeOperation,
                expectedVersion: '1');
        await started.future;
        if (signOut) {
          await client.auth.signOut(scope: SignOutScope.local);
        } else {
          final session = client.auth.currentSession!.toJson();
          session['user'] = {
            ...client.auth.currentUser!.toJson(),
            'id': nextIntakeOperation
          };
          await client.auth.setInitialSession(jsonEncode(session));
        }
        final assertion = expectLater(
            pending,
            history
                ? _historyFails(IncidentHistoryFailureKind.authentication)
                : _intakeFails(PatientEmergencyFailureKind.authentication));
        response.complete(jsonResponse(history ? _history() : _cancelled()));
        await assertion;
      });
    }
  }

  test('unauthenticated history and invalid identifier perform no network read',
      () async {
    var reads = 0;
    final client = await fixtureClient((_) async {
      reads++;
      return jsonResponse(null);
    });
    addTearDown(client.dispose);
    final service = IncidentHistoryService(client: client);
    await expectLater(service.load('01'),
        _historyFails(IncidentHistoryFailureKind.invalidResponse));
    await client.auth.signOut(scope: SignOutScope.local);
    final before = reads;
    await expectLater(service.load(_incidentId),
        _historyFails(IncidentHistoryFailureKind.authentication));
    expect(reads, before);
  });

  test('history timeout has a safe error and no automatic retry', () async {
    final response = Completer<http.Response>();
    var reads = 0;
    final client = await fixtureClient((_) {
      reads++;
      return response.future;
    });
    addTearDown(client.dispose);
    await expectLater(
        IncidentHistoryService(
                client: client, timeout: const Duration(milliseconds: 1))
            .load(_incidentId),
        _historyFails(IncidentHistoryFailureKind.unavailable));
    response.complete(jsonResponse(_history()));
    await Future<void>.delayed(Duration.zero);
    expect(reads, 1);
  });
}
