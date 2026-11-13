import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:mycorvia/services/paramedic_offline_queue.dart';
import 'package:mycorvia/services/paramedic_workspace_service.dart';
import 'package:mycorvia/pages/paramedic/paramedic_forms.dart';
import 'package:mycorvia/pages/paramedic/paramedic_incident_page.dart';

class FakeEmsService extends ParamedicWorkspaceService {
  FakeEmsService()
      : super(
            client: SupabaseClient('http://localhost', 'test-key',
                authOptions: const AuthClientOptions(autoRefreshToken: false)));
  @override
  Future<EmsRow> load([int? incident]) async => {
        'is_admin': true,
        'incident': {
          'incident_id': 1,
          'incident_number': 'EMS-1',
          'status': 'Dispatched',
          'revision': 1,
          'priority': 'High',
          'incident_type': 'Trauma',
          'scene_address': 'Scene address'
        },
        'patients_actual': [
          {
            'patient_id': 1,
            'first_name': 'Patient',
            'last_name': 'Example',
            'patient_number': 'EMS-P-1'
          }
        ],
      };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('SAST display is independent of device time zone', () {
    expect(emsTime('2026-10-08T08:15:00Z'), '2026-10-08 10:15 SAST');
  });
  test('invalid dates and incomplete timestamps cannot enter the RPC', () {
    expect(emsInputDate('2026-02-30', time: false), isNull);
    expect(emsInputDate('2026-10-08', time: true), isNull);
    expect(emsInputDate('2026-10-08 24:00', time: true), isNull);
    expect(emsInputDate('2026-10-08 10:15', time: true),
        DateTime.utc(2026, 10, 8, 8, 15));
  });
  test('vehicle capture requires registration and explains capability codes', () {
    final fields = emsFields('unit');
    final registration =
        fields.singleWhere((field) => field.key == 'registration_number');
    final capability =
        fields.singleWhere((field) => field.key == 'response_capability');

    expect(registration.required, isTrue);
    expect(capability.options?['BLS'], contains('Basic Life Support'));
    expect(capability.options?['ILS'], contains('Intermediate Life Support'));
    expect(capability.options?['ALS'], contains('Advanced Life Support'));
  });
  test('offline queue is encrypted, scoped and survives unlock', () async {
    SharedPreferences.setMockInitialValues({});
    final queue = ParamedicOfflineQueue();
    await queue.unlock('account:hospital', 'a-long-private-passphrase');
    await queue.add('op-1', 'note', {
      'note_text': 'PRIVATE CLINICAL TEXT',
      'recorded_at': '2026-10-08T08:15:00Z'
    });
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(prefs.getKeys().single)!;
    expect(stored.contains('PRIVATE'), false);
    expect(
        (jsonDecode(stored) as Map).keys, containsAll(['iv', 'salt', 'data']));
    queue.lock();
    expect(queue.unlocked, false);
    expect(queue.items, isEmpty);
    await expectLater(queue.unlock('account:hospital', 'incorrect-passphrase'),
        throwsStateError);
    await queue.unlock(
        'different-account:hospital', 'a-long-private-passphrase');
    expect(queue.items, isEmpty);
    queue.lock();
    await queue.unlock('account:hospital', 'a-long-private-passphrase');
    expect(queue.items.single['op'], 'op-1');
    await queue.add('op-1', 'note', {'note_text': 'PRIVATE CLINICAL TEXT'});
    expect(queue.items.length, 1);
    await queue.fail('op-1', 'Connection unavailable');
    expect(queue.items.single['state'], 'Failed');
    await queue.remove('op-1');
    queue.lock();
    await queue.unlock('account:hospital', 'a-long-private-passphrase');
    expect(queue.items, isEmpty);
  });
  testWidgets(
      'invalid form stays open and unchanged retries keep operation identity',
      (tester) async {
    final ops = <String>[];
    var attempt = 0;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Builder(
                builder: (context) => TextButton(
                    onPressed: () => showDialog<EmsRow>(
                        context: context,
                        builder: (_) => EmsFormDialog(
                            title: 'Note',
                            fields: emsFields('note'),
                            save: (p, op) async {
                              ops.add(op);
                              if (attempt++ == 0) {
                                throw StateError('Temporary failure');
                              }
                              return {'saved': true};
                            })),
                    child: const Text('Open'))))));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(ops, isEmpty);
    expect(find.text('Required'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField), 'Observed findings');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Outcome unknown'), findsOneWidget);
    await tester.tap(find.text('Retry same action'));
    await tester.pumpAndSettle();
    expect(ops.length, 2);
    expect(ops[0], ops[1]);
  });
  testWidgets(
      'incident tabs render on narrow and dark screens without overflow',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
        theme: ThemeData.dark(),
        home: ParamedicIncidentPage(
            service: FakeEmsService(),
            incidentId: 1,
            catalog: const {},
            onActivity: () {})));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Patient'));
    await tester.pumpAndSettle();
    expect(find.text('Patient Example'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('Clinical record'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clinical record'));
    await tester.pumpAndSettle();
    expect(find.text('Add observation'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
