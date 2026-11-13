import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:mycorvia/config/env.dart';
import 'package:mycorvia/pages/shared/settings.dart';
import 'package:mycorvia/services/settings_service.dart';
import 'package:mycorvia/services/settings_workspace_access_service.dart';

import 'support/settings_workspace_access_fixture.dart';
import 'support/ws4_http_fixture.dart';

const _emergency = 'Emergency response workspace';
const _paramedic = 'Dispatch & Paramedic workspace';
const _bloodBank = 'Blood Bank';
const _all = SettingsWorkspaceAccess(
    emergencyResponse: true,
    paramedic: true,
    bloodBank: true,
    backupResponses: true,
    receivingHandovers: true);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('database access checks', () {
    test('malformed access responses cannot reveal shortcuts', () async {
      final client = await fixtureClient((request) async {
        switch (request.url.pathSegments.last) {
          case 'corvia_response_inbox':
            return jsonResponse({
              'incidents': ['invalid-incident']
            });
          case 'corvia_ems_access':
            return jsonResponse([
              {'id': ''}
            ]);
          case 'corvia_bb_access':
            return jsonResponse([
              {'hospital_id': 'invalid-hospital'}
            ]);
          default:
            return jsonResponse({
              'user_id': fixtureActor,
              'backup_responses': 'true',
              'receiving_handovers': 1
            });
        }
      });
      addTearDown(client.dispose);
      final result = await SettingsWorkspaceAccessService(client: client)
          .load(includeStaff: true, includeTeam: true);
      expect(result.emergencyResponse, isFalse);
      expect(result.hasStaffWorkspaces, isFalse);
      expect(result.backupResponses, isFalse);
      expect(result.receivingHandovers, isFalse);
    });

    test('no membership or denied response hides all three core workspaces',
        () async {
      final client = await fixtureClient((request) async =>
          request.url.path.endsWith('corvia_response_inbox')
              ? jsonResponse({'code': '42501', 'message': 'Access denied'},
                  status: 403)
              : jsonResponse([]));
      addTearDown(client.dispose);
      final result = await SettingsWorkspaceAccessService(client: client)
          .load(includeStaff: true, includeTeam: false);
      expect(result.emergencyResponse, isFalse);
      expect(result.hasStaffWorkspaces, isFalse);
    });

    test(
        'an authorised empty response inbox is visible and module errors are independent',
        () async {
      final client = await fixtureClient((request) async {
        switch (request.url.pathSegments.last) {
          case 'corvia_response_inbox':
            return jsonResponse({'incidents': []});
          case 'corvia_ems_access':
            return jsonResponse({'code': 'PGRST202', 'message': 'Missing'},
                status: 404);
          case 'corvia_bb_access':
            return jsonResponse([
              {'hospital_id': fixtureActor, 'role': 'viewer'}
            ]);
          default:
            throw StateError('Unexpected request ${request.url}');
        }
      });
      addTearDown(client.dispose);
      final result = await SettingsWorkspaceAccessService(client: client)
          .load(includeStaff: true, includeTeam: false);
      expect(result.emergencyResponse, isTrue);
      expect(result.paramedic, isFalse);
      expect(result.bloodBank, isTrue);
    });

    test('EMS membership and receiving membership do not grant other modules',
        () async {
      final client = await fixtureClient((request) async {
        switch (request.url.pathSegments.last) {
          case 'corvia_response_inbox':
            return jsonResponse({'code': '42501'}, status: 403);
          case 'corvia_ems_access':
            return jsonResponse([
              {'id': fixtureActor}
            ]);
          case 'corvia_bb_access':
            return jsonResponse([]);
          case 'corvia_ws4_team_settings_access':
            return jsonResponse({
              'user_id': fixtureActor,
              'backup_responses': false,
              'receiving_handovers': true
            });
          default:
            throw StateError('Unexpected request ${request.url}');
        }
      });
      addTearDown(client.dispose);
      final result = await SettingsWorkspaceAccessService(client: client)
          .load(includeStaff: true, includeTeam: true);
      expect(result.emergencyResponse, isFalse);
      expect(result.paramedic, isTrue);
      expect(result.bloodBank, isFalse);
      expect(result.backupResponses, isFalse);
      expect(result.receivingHandovers, isTrue);
    });

    test(
        'disabled groups are not queried; mismatched team identity cannot grant access',
        () async {
      final requests = <String>[];
      final client = await fixtureClient((request) async {
        requests.add(request.url.pathSegments.last);
        return jsonResponse(request.url.path.endsWith('corvia_response_inbox')
            ? {'incidents': []}
            : {
                'user_id': 'someone-else',
                'backup_responses': true,
                'receiving_handovers': true
              });
      });
      addTearDown(client.dispose);
      final service = SettingsWorkspaceAccessService(client: client);
      await service.load(includeStaff: false, includeTeam: false);
      expect(requests, ['corvia_response_inbox']);
      final result = await service.load(includeStaff: false, includeTeam: true);
      expect(result.backupResponses, isFalse);
      expect(result.receivingHandovers, isFalse);
      expect(result.hasStaffWorkspaces, isFalse);
    });

    test('pending access cannot be used after an account switch', () async {
      final pending = Completer<void>();
      final requested = Completer<void>();
      final client = await fixtureClient((request) async {
        if (!requested.isCompleted) requested.complete();
        await pending.future;
        return jsonResponse(request.url.path.endsWith('corvia_response_inbox')
            ? {'incidents': []}
            : [
                {'id': fixtureActor, 'hospital_id': fixtureActor}
              ]);
      });
      addTearDown(client.dispose);
      final load = SettingsWorkspaceAccessService(client: client)
          .load(includeStaff: true, includeTeam: false);
      await requested.future;
      final session = client.auth.currentSession!.toJson();
      session['user'] = {
        ...client.auth.currentUser!.toJson(),
        'id': '00000000-0000-4000-8000-000000000099'
      };
      await client.auth.setInitialSession(jsonEncode(session));
      pending.complete();
      final result = await load;
      expect(result.emergencyResponse, isFalse);
      expect(result.hasStaffWorkspaces, isFalse);
    });

    test('signed-out settings makes no database requests', () async {
      var requests = 0;
      final client = await fixtureClient((_) async {
        requests++;
        return jsonResponse(null);
      });
      addTearDown(client.dispose);
      await client.auth.signOut(scope: SignOutScope.local);
      requests = 0;
      final result = await SettingsWorkspaceAccessService(client: client)
          .load(includeStaff: true, includeTeam: true);
      expect(result.emergencyResponse, isFalse);
      expect(result.hasStaffWorkspaces, isFalse);
      expect(requests, 0);
    });
  });

  group('settings visibility', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await SettingsService.instance.init();
      PackageInfo.setMockInitialValues(
          appName: 'Corvia',
          packageName: 'test.corvia',
          version: '1',
          buildNumber: '1',
          buildSignature: '');
    });

    Future<void> open(WidgetTester tester, FakeSettingsAccess service,
        {bool staff = true}) async {
      addTearDown(service.changes.close);
      await tester.pumpWidget(MaterialApp(
          home: SettingsPage(
              showStaffWorkspaces: staff, workspaceAccessService: service)));
      await tester.pumpAndSettle();
    }

    void noCoreLinks() {
      for (final label in [
        _emergency,
        _paramedic,
        _bloodBank,
        'Staff workspaces'
      ]) {
        expect(find.text(label), findsNothing);
      }
    }

    testWidgets(
        'ordinary nurse settings hides all unauthorised links and empty group',
        (tester) async {
      await open(tester, FakeSettingsAccess());
      noCoreLinks();
      expect(find.text('Appearance & Accessibility'), findsOneWidget);
      expect(find.text('Privacy, Security & Permissions'), findsOneWidget);
    });

    for (final entry in <String, SettingsWorkspaceAccess>{
      _emergency: const SettingsWorkspaceAccess(emergencyResponse: true),
      _paramedic: const SettingsWorkspaceAccess(paramedic: true),
      _bloodBank: const SettingsWorkspaceAccess(bloodBank: true),
    }.entries) {
      testWidgets('only the authorised ${entry.key} link is shown',
          (tester) async {
        await open(tester, FakeSettingsAccess()..access = entry.value);
        for (final label in [_emergency, _paramedic, _bloodBank]) {
          expect(find.text(label),
              label == entry.key ? findsOneWidget : findsNothing);
        }
        expect(find.text('Staff workspaces'),
            entry.value.hasStaffWorkspaces ? findsOneWidget : findsNothing);
      });
    }

    testWidgets('loading and failed checks never flash workspace links',
        (tester) async {
      final pending = Completer<SettingsWorkspaceAccess>();
      await open(tester, FakeSettingsAccess()..onLoad = () => pending.future);
      noCoreLinks();
      pending.completeError(StateError('offline'));
      await tester.pumpAndSettle();
      noCoreLinks();
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'account switch removes granted links and rejects an old response',
        (tester) async {
      final service = FakeSettingsAccess()..access = _all;
      await open(tester, service);
      expect(find.text(_emergency), findsOneWidget);
      final old = Completer<SettingsWorkspaceAccess>();
      service.onLoad = () => old.future;
      service.changes.add(service.actor);
      await tester.pump();
      noCoreLinks();
      service.onLoad = null;
      service.access = const SettingsWorkspaceAccess();
      service.actor = 'account-b';
      service.changes.add(service.actor);
      await tester.pumpAndSettle();
      old.complete(_all);
      await tester.pumpAndSettle();
      noCoreLinks();
    });

    testWidgets('resuming rechecks removed membership', (tester) async {
      final service = FakeSettingsAccess()..access = _all;
      await open(tester, service);
      service.access = const SettingsWorkspaceAccess();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(service.loads, greaterThan(1));
      noCoreLinks();
    });

    testWidgets('surface and feature flags also restrict verified access',
        (tester) async {
      await open(tester, FakeSettingsAccess()..access = _all, staff: false);
      expect(find.text(_emergency), findsOneWidget);
      expect(find.text(_paramedic), findsNothing);
      expect(find.text(_bloodBank), findsNothing);
      for (final label in ['My backup responses', 'Receiving handovers']) {
        expect(find.text(label),
            Env.ws4TeamEmsHandoffEnabled ? findsOneWidget : findsNothing);
      }
    });

    testWidgets('team shortcuts require their individual verified membership',
        (tester) async {
      await open(
          tester,
          FakeSettingsAccess()
            ..access = const SettingsWorkspaceAccess(receivingHandovers: true));
      expect(find.text('My backup responses'), findsNothing);
      expect(find.text('Receiving handovers'),
          Env.ws4TeamEmsHandoffEnabled ? findsOneWidget : findsNothing);
    });
  });
}
