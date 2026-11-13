import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mycorvia/services/patient_emergency_intake_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'support/ws4_http_fixture.dart';
import 'support/ws4_patient_intake_fixture.dart';

Matcher fails(PatientEmergencyFailureKind kind) =>
    throwsA(isA<PatientEmergencyIntakeException>()
        .having((error) => error.kind, 'kind', kind));

void main() {
  test('request normalizes optional text and supports honest missing location',
      () {
    final blank = PatientEmergencyIntakeRequest(address: '  ', details: '  ');
    expect(blank.locationSource, 'unavailable');
    expect(blank.latitude, isNull);
    expect(blank.details, isNull);
    final manual = PatientEmergencyIntakeRequest(
        address: '  Test entrance  ', details: '  Test only  ');
    expect(manual.locationSource, 'manual');
    expect(manual.address, 'Test entrance');
    expect(manual.details, 'Test only');
  });

  test('GPS payload retains immutable original timestamp for idempotent replay',
      () {
    final input = PatientEmergencyIntakeRequest(
        latitude: -26.2,
        longitude: 28,
        accuracy: 15,
        capturedAt: DateTime.utc(2026, 10, 7, 10),
        address: 'Test entrance');
    expect(input.locationSource, 'gps');
    expect(input.toRpc(intakeOperation)['p_location_captured_at'],
        '2026-10-07T10:00:00.000Z');
    final result = intakeIncident(input: input);
    expect(result.request, input);
    expect(result.incidentId, '9007199254740993');
  });

  final invalidInputs = <PatientEmergencyIntakeRequest Function()>[
    () => PatientEmergencyIntakeRequest(latitude: 1),
    () => PatientEmergencyIntakeRequest(
        latitude: 91, longitude: 1, accuracy: 1, capturedAt: DateTime.now()),
    () => PatientEmergencyIntakeRequest(
        latitude: double.nan,
        longitude: 1,
        accuracy: 1,
        capturedAt: DateTime.now()),
    () => PatientEmergencyIntakeRequest(latitude: 1, longitude: 1),
    () => PatientEmergencyIntakeRequest(accuracy: 1),
    () => PatientEmergencyIntakeRequest(address: 'a' * 301),
    () => PatientEmergencyIntakeRequest(details: 'a' * 1001),
  ];
  for (var index = 0; index < invalidInputs.length; index++) {
    test('invalid input $index is rejected before sending', () {
      expect(invalidInputs[index],
          fails(PatientEmergencyFailureKind.invalidInput));
    });
  }

  final invalidFields = <String, Object?>{
    'operation_id': nextIntakeOperation,
    'user_id': nextIntakeOperation,
    'incident_id': 1,
    'version': '01',
    'status': 'dispatched',
    'created_at': '2026-02-31T12:00:00Z',
    'location_source': 'gps',
    'latitude': '0',
    'address': ' unnormalized ',
    'details': 3,
  };
  for (final field in invalidFields.entries) {
    test('response rejects inconsistent ${field.key}', () {
      expect(
          () => PatientEmergencyIncident.fromMap(
              {...intakeResponse(), field.key: field.value},
              expectedUserId: fixtureActor,
              expectedOperationId: intakeOperation),
          fails(PatientEmergencyFailureKind.unknown));
    });
  }
  test('response missing nullable fields is still a malformed contract', () {
    final response = intakeResponse()..remove('details');
    expect(
        () => PatientEmergencyIncident.fromMap(response,
            expectedUserId: fixtureActor, expectedOperationId: intakeOperation),
        fails(PatientEmergencyFailureKind.unknown));
  });

  test('service explicitly submits the same operation and exact payload',
      () async {
    final input = PatientEmergencyIntakeRequest(address: 'Test entrance');
    var writes = 0;
    final client = await fixtureClient((request) async {
      expect(request.method, 'POST');
      expect(request.url.path, '/rest/v1/rpc/corvia_patient_request_emergency');
      expect(jsonDecode(request.body), input.toRpc(intakeOperation));
      writes++;
      return jsonResponse(intakeResponse(input: input));
    });
    addTearDown(client.dispose);
    final result = await PatientEmergencyIntakeService(client: client).request(
        userId: fixtureActor, operationId: intakeOperation, input: input);
    expect(result.request, input);
    expect(writes, 1);
  });

  test('lookup null is authoritative absence and never creates an incident',
      () async {
    final client = await fixtureClient((request) async {
      expect(request.url.path, '/rest/v1/rpc/corvia_patient_request_status');
      expect(jsonDecode(request.body), {'p_operation_id': intakeOperation});
      return jsonResponse(null);
    });
    addTearDown(client.dispose);
    expect(
        await PatientEmergencyIntakeService(client: client)
            .lookup(userId: fixtureActor, operationId: intakeOperation),
        isNull);
  });

  for (final entry in {
    'PGRST202': PatientEmergencyFailureKind.configuration,
    '42883': PatientEmergencyFailureKind.configuration,
    '42501': PatientEmergencyFailureKind.authentication,
    'PGRST301': PatientEmergencyFailureKind.authentication,
    'PGRST302': PatientEmergencyFailureKind.authentication,
    'PGRST303': PatientEmergencyFailureKind.authentication,
    '22023': PatientEmergencyFailureKind.invalidInput,
    'XX000': PatientEmergencyFailureKind.unknown,
  }.entries) {
    test('typed failure ${entry.key} has a fixed safe message', () async {
      final client = await fixtureClient((_) async => jsonResponse(
          {'code': entry.key, 'message': 'private clinical payload'},
          status: 400));
      addTearDown(client.dispose);
      await expectLater(
          PatientEmergencyIntakeService(client: client).request(
              userId: fixtureActor,
              operationId: intakeOperation,
              input: PatientEmergencyIntakeRequest()),
          fails(entry.value));
      expect(PatientEmergencyIntakeException(entry.value).message,
          isNot(contains('private')));
    });
  }

  test('malformed successful write response remains unknown', () async {
    final client =
        await fixtureClient((_) async => jsonResponse({'status': 'pending'}));
    addTearDown(client.dispose);
    await expectLater(
        PatientEmergencyIntakeService(client: client).request(
            userId: fixtureActor,
            operationId: intakeOperation,
            input: PatientEmergencyIntakeRequest()),
        fails(PatientEmergencyFailureKind.unknown));
  });

  test('changed successful payload is not reported as our confirmed submission',
      () async {
    final client = await fixtureClient((_) async => jsonResponse(intakeResponse(
        input: PatientEmergencyIntakeRequest(address: 'Different location'))));
    addTearDown(client.dispose);
    await expectLater(
        PatientEmergencyIntakeService(client: client).request(
            userId: fixtureActor,
            operationId: intakeOperation,
            input: PatientEmergencyIntakeRequest()),
        fails(PatientEmergencyFailureKind.unknown));
  });

  for (final writing in [false, true]) {
    for (final signedOut in [false, true]) {
      test(
          '${writing ? 'write' : 'lookup'} result withheld after ${signedOut ? 'signout' : 'account change'}',
          () async {
        final pending = Completer<http.Response>();
        final started = Completer<void>();
        var requests = 0;
        final client = await fixtureClient((request) async {
          if (request.url.path.contains('/rest/v1/rpc/')) {
            requests++;
            started.complete();
            return pending.future;
          }
          return jsonResponse(null);
        });
        addTearDown(client.dispose);
        final service = PatientEmergencyIntakeService(client: client);
        final result = writing
            ? service.request(
                userId: fixtureActor,
                operationId: intakeOperation,
                input: PatientEmergencyIntakeRequest())
            : service.lookup(
                userId: fixtureActor, operationId: intakeOperation);
        await started.future;
        if (signedOut) {
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
            result, fails(PatientEmergencyFailureKind.authentication));
        pending.complete(jsonResponse(intakeResponse()));
        await assertion;
        expect(requests, 1);
      });
    }
  }
  test('wrong bound actor is rejected before network I/O', () async {
    var requests = 0;
    final client = await fixtureClient((_) async {
      requests++;
      return jsonResponse(null);
    });
    addTearDown(client.dispose);
    await expectLater(
        PatientEmergencyIntakeService(client: client)
            .lookup(userId: nextIntakeOperation, operationId: intakeOperation),
        fails(PatientEmergencyFailureKind.authentication));
    expect(requests, 0);
  });
}
