import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mycorvia/services/emergency_dispatch_service.dart';
import 'package:mycorvia/services/patient_incident_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'support/ws4_http_fixture.dart';

void main() {
  test('access context uses the authenticated RPC and validates its response',
      () async {
    final client = await fixtureClient((request) async {
      expect(request.method, 'POST');
      expect(request.url.path, '/rest/v1/rpc/corvia_dispatch_access_context');
      return jsonResponse(_accessContext());
    });
    addTearDown(client.dispose);
    final result =
        await EmergencyDispatchService(client: client).loadAccessContext();
    expect(result.userId, fixtureActor);
    expect(result.canClaimIncident, isTrue);
  });

  test('signed out caller cannot request dispatch authority', () async {
    final client = SupabaseClient(
        'http://127.0.0.1:54321', 'synthetic-test-key',
        authOptions: const AuthClientOptions(autoRefreshToken: false));
    addTearDown(client.dispose);
    await expectLater(
      EmergencyDispatchService(client: client).loadAccessContext(),
      throwsA(isA<AuthException>()
          .having((e) => e.statusCode, 'statusCode', '401')),
    );
  });

  for (final code in ['42501', 'PGRST301', 'PGRST302', 'PGRST303']) {
    test('access RPC preserves typed denial $code', () async {
      final client = await fixtureClient((_) async => jsonResponse(
          {'code': code, 'message': 'private backend detail'},
          status: 403));
      addTearDown(client.dispose);
      await expectLater(
        EmergencyDispatchService(client: client).loadAccessContext(),
        throwsA(isA<PostgrestException>().having((e) => e.code, 'code', code)),
      );
    });
  }

  for (final code in ['PGRST202', '42883']) {
    test('missing access RPC $code becomes a safe configuration failure',
        () async {
      final client = await fixtureClient((_) async => jsonResponse(
          {'code': code, 'message': 'private schema detail'},
          status: 404));
      addTearDown(client.dispose);
      await expectLater(
        EmergencyDispatchService(client: client).loadAccessContext(),
        throwsA(isA<DispatchAccessException>().having(
            (e) => e.message,
            'safe message',
            const DispatchAccessException.configuration().message)),
      );
    });
  }

  for (final response in <Object?>[
    null,
    [],
    'private invalid response',
    {..._accessContext(), 'user_id': '00000000-0000-4000-8000-000000000099'}
  ]) {
    test(
        'invalid access response cannot authorize a queue read: ${response.runtimeType}',
        () async {
      final client = await fixtureClient((_) async => jsonResponse(response));
      addTearDown(client.dispose);
      await expectLater(
        EmergencyDispatchService(client: client).loadAccessContext(),
        throwsA(isA<DispatchAccessException>()),
      );
    });
  }

  for (final signedOut in [false, true]) {
    test(
        'pending context is rejected after ${signedOut ? 'sign out' : 'account change'}',
        () async {
      final pending = Completer<http.Response>();
      final requested = Completer<void>();
      final client = await fixtureClient((request) async {
        if (request.url.path == '/rest/v1/rpc/corvia_dispatch_access_context') {
          requested.complete();
          return pending.future;
        }
        return jsonResponse(null);
      });
      addTearDown(client.dispose);
      final load = EmergencyDispatchService(client: client).loadAccessContext();
      await requested.future;
      if (signedOut) {
        await client.auth.signOut(scope: SignOutScope.local);
      } else {
        final session = client.auth.currentSession!.toJson();
        session['user'] = {
          ...client.auth.currentUser!.toJson(),
          'id': '00000000-0000-4000-8000-000000000099',
        };
        await client.auth.setInitialSession(jsonEncode(session));
      }
      final assertion = expectLater(
          load,
          throwsA(isA<AuthException>()
              .having((e) => e.statusCode, 'statusCode', '401')));
      pending.complete(jsonResponse(_accessContext()));
      await assertion;
    });
  }

  test('filters before limiting and pages all open incidents with an ID cursor',
      () async {
    final database = [
      for (var id = 1; id <= 155; id++)
        fixtureIncident(id,
            status: id > 5
                ? 'resolved'
                : id == 3
                    ? null
                    : 'pending')
    ];
    var requests = 0;
    final client = await fixtureClient((request) async {
      requests++;
      final q = request.url.queryParameters;
      expect(q['or'], contains('status.is.null'));
      expect(q['or'], contains('status.not.ilike.resolved'));
      expect(q['or'], contains('status.not.ilike.cancelled'));
      expect(q['order'], 'id.asc.nullslast');
      final cursor = int.parse((q['id'] ?? 'gt.0').substring(3));
      final limit = int.parse(q['limit']!);
      // Model the requested server filtering, then pagination, over synthetic rows.
      return jsonResponse(database
          .where((r) =>
              r['status'] != 'resolved' &&
              r['status'] != 'cancelled' &&
              (r['id'] as int) > cursor)
          .take(limit)
          .toList());
    });
    addTearDown(client.dispose);
    final result = await EmergencyDispatchService(client: client)
        .loadIncomingEmergencies(limit: 2);
    expect(result.map((r) => r.id), ['1', '2', '3', '4', '5']);
    expect(result[2].status, 'unknown');
    expect(result[2].canBeClaimed, isFalse);
    expect(requests, 3);
  });

  test('invalidated read stops fetching further pages', () async {
    var current = true;
    var requests = 0;
    final client = await fixtureClient((_) async {
      requests++;
      current = false;
      return jsonResponse([fixtureIncident(1)]);
    });
    addTearDown(client.dispose);
    await expectLater(
        EmergencyDispatchService(client: client)
            .loadIncomingEmergencies(limit: 1, isCurrent: () => current),
        throwsStateError);
    expect(requests, 1);
  });

  test('repeated cursor fails rather than presenting a truncated queue',
      () async {
    final client =
        await fixtureClient((_) async => jsonResponse([fixtureIncident(1)]));
    addTearDown(client.dispose);
    await expectLater(
        EmergencyDispatchService(client: client)
            .loadIncomingEmergencies(limit: 1),
        throwsFormatException);
  });

  for (final status in [null, '', 'mystery']) {
    test('unknown status $status never grants claim or accepted state', () {
      final row = DispatchEmergency.fromMap({
        ...fixtureIncident(1, status: status),
        'assigned_dispatcher_user_id': fixtureActor
      });
      expect(row.canBeClaimed, isFalse);
      expect(row.isAccepted, isFalse);
      expect(row.needsReview, isTrue);
    });
  }
  test('bad identity/time, pre-owned pending and invalid coordinates are safe',
      () {
    for (final patch in <Map<String, dynamic>>[
      {'id': ''},
      {'id': -1},
      {'created_at': 'invalid'},
      {'assigned_dispatcher_user_id': fixtureActor},
    ]) {
      expect(
          DispatchEmergency.fromMap({...fixtureIncident(1), ...patch})
              .canBeClaimed,
          isFalse);
    }
    for (final latitude in [double.nan, double.infinity, 91, -91]) {
      final row = DispatchEmergency.fromMap(
          {...fixtureIncident(1), 'latitude': latitude});
      expect(row.coordinateLabel, 'Location unavailable');
    }
  });

  for (final signedOut in [false, true]) {
    test(
        'claim result is withheld after ${signedOut ? 'sign out' : 'account change'}',
        () async {
      final pending = Completer<http.Response>();
      final requested = Completer<void>();
      var claimRequests = 0;
      final client = await fixtureClient((request) async {
        if (request.url.path ==
            '/rest/v1/rpc/corvia_dispatch_accept_incident') {
          claimRequests++;
          expect(jsonDecode(request.body), {'p_incident_id': 1});
          requested.complete();
          return pending.future;
        }
        return jsonResponse(null);
      });
      addTearDown(client.dispose);
      final claim =
          EmergencyDispatchService(client: client).acceptEmergency('1');
      await requested.future;
      if (signedOut) {
        await client.auth.signOut(scope: SignOutScope.local);
      } else {
        final session = client.auth.currentSession!.toJson();
        session['user'] = {
          ...client.auth.currentUser!.toJson(),
          'id': '00000000-0000-4000-8000-000000000099',
        };
        await client.auth.setInitialSession(jsonEncode(session));
      }
      final assertion = expectLater(
          claim,
          throwsA(isA<AuthException>()
              .having((e) => e.statusCode, 'statusCode', '401')));
      // A valid committed response must still be withheld from the new session.
      pending.complete(jsonResponse({
        ...fixtureIncident(1),
        'status': 'in_progress',
        'assigned_dispatcher_user_id': fixtureActor,
        'accepted_at': '2026-01-01T00:01:00Z',
      }));
      await assertion;
      expect(claimRequests, 1);
    });
  }

  for (final kind in [
    'valid',
    'wrong-id',
    'wrong-owner',
    'pending',
    'missing-time'
  ]) {
    test('claim validates authoritative response: $kind', () async {
      final client = await fixtureClient((request) async {
        expect(
            request.url.path, '/rest/v1/rpc/corvia_dispatch_accept_incident');
        expect(jsonDecode(request.body), {'p_incident_id': 1});
        return jsonResponse({
          ...fixtureIncident(kind == 'wrong-id' ? 2 : 1),
          'status': kind == 'pending' ? 'pending' : 'in_progress',
          'assigned_dispatcher_user_id':
              kind == 'wrong-owner' ? 'other' : fixtureActor,
          'accepted_at': kind == 'missing-time' ? null : '2026-01-01T00:01:00Z'
        });
      });
      addTearDown(client.dispose);
      final action =
          EmergencyDispatchService(client: client).acceptEmergency('1');
      if (kind == 'valid') {
        expect((await action).isAccepted, isTrue);
      } else {
        await expectLater(action, throwsFormatException);
      }
    });
  }
  for (final result in [
    'confirmed',
    'empty',
    'wrong-id',
    'wrong-state',
    'denied'
  ]) {
    test('patient cancellation requires a confirmed matching row: $result',
        () async {
      final client = await fixtureClient((request) async {
        expect(request.method, 'PATCH');
        final q = request.url.queryParameters;
        expect(q['id'], 'eq.1');
        expect(q['user_id'], 'eq.$fixtureActor');
        expect(q['status'], 'eq.pending');
        expect(q['assigned_dispatcher_user_id'], 'is.null');
        if (result == 'denied') {
          return jsonResponse({'code': '42501', 'message': 'private'},
              status: 403);
        }
        return jsonResponse(result == 'empty'
            ? null
            : {
                'id': result == 'wrong-id' ? 2 : 1,
                'status': result == 'wrong-state' ? 'pending' : 'cancelled',
              });
      });
      addTearDown(client.dispose);
      final action = PatientIncidentService(client).cancelUnclaimedIncident(1);
      if (result == 'confirmed') {
        await action;
      } else {
        await expectLater(action, throwsA(anything));
      }
    });
  }
}

Map<String, dynamic> _accessContext() => {
      'user_id': fixtureActor,
      'memberships': [
        {
          'organisation_id': '00000000-0000-4000-8000-000000000002',
          'role': 'dispatcher'
        }
      ],
      'capabilities': ['read_incidents', 'claim_incident'],
      'policy_version': 'ws4-dev-core-1',
      'server_time': '2026-10-07T12:00:00+00:00',
    };
