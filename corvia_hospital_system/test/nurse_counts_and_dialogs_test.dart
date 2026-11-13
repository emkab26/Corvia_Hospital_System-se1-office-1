import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:mycorvia/pages/nurse/nurse_dashboard_page.dart';
import 'package:mycorvia/pages/nurse/nurse_tasks_page.dart';
import 'package:mycorvia/pages/nurse/nurse_lab_collection_page.dart';
import 'package:mycorvia/services/nurse_service.dart';

import 'support/nurse_workspace_fixture.dart';

class DashboardService extends FakeNurseService {
  DashboardService(this.counts) : super(NurseWorkspace.fromJson(payload()));
  final List<int?> counts;
  int loads = 0;

  @override
  Future<NurseWorkspaceCounts> loadWorkspaceCounts(
      NurseWorkspace workspace) async {
    final count = counts[loads < counts.length ? loads++ : counts.length - 1];
    return NurseWorkspaceCounts(
        assignedPatients: 1, activeTasks: 2, activeMedications: count);
  }
}

class LabService extends FakeNurseService {
  LabService({required this.outsourced})
      : super(NurseWorkspace.fromJson(payload()));
  final bool outsourced;
  final collections = <Map<String, dynamic>>[];

  @override
  Future<NurseContext> requireCurrentContext() async => workspace.context;

  @override
  Future<List<NurseLabCollectionOrder>> loadLabCollectionQueue() async => [
        NurseLabCollectionOrder.fromJson({
          'lab_result_id': 'order-a',
          'patient_id': 'patient-a',
          'patient_name': 'Alex Patient',
          'patient_number': 'PAT-001',
          'lab_name': 'Test lab',
          'lab_organization_id': 'lab-a',
          'lab_type': outsourced ? 'private' : 'hospital',
          'test_name': 'Test order',
        }),
      ];

  @override
  Future<NurseSpecimenCollection> collectLabSpecimens({
    required String labResultId,
    required List<NurseSampleInput> samples,
    required bool useTransportBag,
    required String externalBagReference,
    required String collectionNote,
  }) async {
    collections.add({
      'samples': samples,
      'bag': useTransportBag,
      'bag_reference': externalBagReference,
      'note': collectionNote
    });
    return NurseSpecimenCollection.fromJson({
      'collection_id': 'collection-a',
      'lab_organization_id': 'lab-a',
      'lab_name': 'Test lab',
      'lab_type': outsourced ? 'private' : 'hospital',
      'label_source': outsourced ? 'external' : 'corvia',
      'specimens': [
        for (var i = 0; i < samples.length; i++)
          {
            'container_id': 'container-$i',
            'container_code': 'CVS-$i',
            'specimen_type': samples[i].specimenType,
            'label_source': outsourced ? 'external' : 'corvia',
            'external_label_reference': samples[i].externalLabelReference,
          }
      ],
      'bag': useTransportBag
          ? {
              'bag_id': 'bag-a',
              'bag_code': 'CVB-A',
              'label_source': outsourced ? 'external' : 'corvia',
              'external_label_reference': externalBagReference
            }
          : null,
    });
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final writes = <Map<String, dynamic>>[];
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://example.test',
      publishableKey: 'synthetic-test-key',
      authOptions: const FlutterAuthClientOptions(
          localStorage: EmptyLocalStorage(), autoRefreshToken: false),
      httpClient: MockClient((request) async {
        if (request.method == 'PATCH' &&
            request.url.path.endsWith('/nursing_tasks')) {
          writes.add(jsonDecode(request.body) as Map<String, dynamic>);
          return http.Response('', 204, request: request);
        }
        throw StateError('Unexpected request: ${request.url}');
      }),
    );
  });
  tearDownAll(() => Supabase.instance.dispose());
  setUp(writes.clear);

  NurseWorkspace workspace() {
    final data = payload()
      ..['tasks'] = [
        {
          'id': 'task-a',
          'patient_id': 'patient-a',
          'title': 'Test task',
          'hospital_id': 'hospital-a',
          'assigned_nurse_user_id': 'auth-user',
          'status': 'pending'
        },
        {'id': 'task-b', 'status': 'in_progress'},
        {'id': 'task-c', 'status': 'completed'},
      ];
    return NurseWorkspace.fromJson(data);
  }

  Future<NurseWorkspaceCounts> countWith(
      http.Response Function(http.Request) respond) async {
    final requests = <http.Request>[];
    final client = SupabaseClient(
      'https://example.test',
      'test',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        requests.add(request);
        return respond(request);
      }),
    );
    addTearDown(client.dispose);
    final counts =
        await NurseService(client: client).loadWorkspaceCounts(workspace());
    expect(counts.assignedPatients, 1);
    expect(counts.activeTasks, 2);
    expect(requests.length, 1);
    expect(requests.single.url.path,
        endsWith('/rpc/corvia_nurse_active_prescription_count_v1'));
    return counts;
  }

  for (final value in [0, 7]) {
    test(
        'successful prescription count $value remains distinct from unavailable',
        () async {
      final counts = await countWith((request) => http.Response(
          jsonEncode({
            'hospital_id': 'hospital-a',
            'nurse_user_id': 'auth-user',
            'active_prescriptions': value,
          }),
          200,
          request: request));
      expect(counts.activeMedications, value);
    });
  }
  for (final code in ['42501', 'PGRST202']) {
    test(
        'failed prescription count $code is unavailable without an unfiltered fallback',
        () async {
      final counts = await countWith((request) => http.Response(
            jsonEncode({'code': code, 'message': 'Count unavailable'}),
            code == '42501' ? 403 : 404,
            request: request,
          ));
      expect(counts.activeMedications, isNull);
    });
  }
  test('invalid or stale-hospital count is unavailable', () async {
    final counts = await countWith((request) => http.Response(
        jsonEncode({
          'hospital_id': 'another-hospital',
          'nurse_user_id': 'auth-user',
          'active_prescriptions': 4,
        }),
        200,
        request: request));
    expect(counts.activeMedications, isNull);
  });
  test(
      'network failure preserves other counts and marks prescriptions unavailable',
      () async {
    final client = SupabaseClient(
      'https://example.test',
      'test',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient:
          MockClient((request) async => throw http.ClientException('offline')),
    );
    addTearDown(client.dispose);
    final counts =
        await NurseService(client: client).loadWorkspaceCounts(workspace());
    expect(counts.activeMedications, isNull);
    expect(counts.assignedPatients, 1);
    expect(counts.activeTasks, 2);
  });
  test('no assigned patients is a genuine zero without a database request',
      () async {
    final data = payload()..['assignments'] = [];
    final client = SupabaseClient(
      'https://example.test',
      'test',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient(
          (request) async => throw StateError('Unexpected count request')),
    );
    addTearDown(client.dispose);
    final counts = await NurseService(client: client)
        .loadWorkspaceCounts(NurseWorkspace.fromJson(data));
    expect(counts.activeMedications, 0);
  });

  Future<void> showPage(WidgetTester tester, Widget page) async {
    tester.view.physicalSize = const Size(1000, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(home: page));
    await tester.pumpAndSettle();
  }

  Future<void> reveal(WidgetTester tester, Finder finder) async {
    await tester.scrollUntilVisible(finder, 400,
        scrollable: find.byType(Scrollable).last);
    await tester.pumpAndSettle();
  }

  testWidgets(
      'dashboard shows unavailable and retry restores the prescription count',
      (tester) async {
    final service = DashboardService([null, 3]);
    await showPage(tester, NurseDashboardPage(service: service));
    await reveal(tester, find.text('Retry prescription count'));
    expect(find.text('Active prescription count unavailable.'), findsOneWidget);
    expect(find.text('0 active prescription(s) for assigned patients.'),
        findsNothing);
    await tester.tap(find.text('Retry prescription count'));
    await tester.pumpAndSettle();
    await reveal(
        tester, find.text('3 active prescription(s) for assigned patients.'));
    expect(service.loads, 2);
    expect(find.text('Retry prescription count'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'dashboard displays a genuine zero without an unavailable message',
      (tester) async {
    await showPage(tester, NurseDashboardPage(service: DashboardService([0])));
    await reveal(
        tester, find.text('0 active prescription(s) for assigned patients.'));
    expect(find.text('Retry prescription count'), findsNothing);
    expect(find.text('Active prescription count unavailable.'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  Finder field(String label) => find.byWidgetPredicate(
      (widget) => widget is TextField && widget.decoration?.labelText == label);

  Future<void> dismiss(WidgetTester tester, String action) async {
    if (action == 'Cancel') {
      await tester.tap(find.text('Cancel'));
    } else if (action == 'back') {
      await tester.binding.handlePopRoute();
    } else {
      await tester.tapAt(const Offset(5, 5));
    }
    // Exercise the closing animation before the dialog widgets are unmounted.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(tester.takeException(), isNull);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }

  for (final action in ['Cancel', 'back', 'barrier']) {
    testWidgets('task dialog $action closes safely without saving',
        (tester) async {
      final data = payload()..['tasks'] = [(workspace().tasks.first)];
      await showPage(
          tester,
          NurseTasksPage(
              service: FakeNurseService(NurseWorkspace.fromJson(data))));
      await tester.tap(find.text('Complete'));
      await tester.pumpAndSettle();
      await tester.enterText(field('Completion Notes'), 'Unsaved note');
      await dismiss(tester, action);
      expect(find.text('Complete Nursing Task'), findsNothing);
      expect(writes, isEmpty);
    });
  }
  for (final note in ['Saved note', '']) {
    testWidgets(
        'task confirmation preserves note ${note.isEmpty ? 'empty' : 'text'} during closing',
        (tester) async {
      final data = payload()..['tasks'] = [workspace().tasks.first];
      await showPage(
          tester,
          NurseTasksPage(
              service: FakeNurseService(NurseWorkspace.fromJson(data))));
      await tester.tap(find.text('Complete'));
      await tester.pumpAndSettle();
      await tester.enterText(field('Completion Notes'), note);
      await tester.tap(find.descendant(
          of: find.byType(AlertDialog), matching: find.text('Complete')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(tester.takeException(), isNull);
      await tester.pumpAndSettle();
      expect(writes.single['completion_notes'], note);
      expect(writes.single['status'], 'completed');
      expect(tester.takeException(), isNull);
    });
  }

  for (final action in ['Cancel', 'back', 'barrier']) {
    testWidgets('specimen dialog $action safely closes both controllers',
        (tester) async {
      final service = LabService(outsourced: true);
      await showPage(tester, NurseLabCollectionPage(service: service));
      await tester.tap(find.text('Collect and label'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Place samples in a transport bag'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(field('External bag label/reference'));
      await tester.enterText(
          field('External bag label/reference'), 'UNSAVED-BAG');
      await tester.ensureVisible(field('Collection note (optional)'));
      await tester.enterText(
          field('Collection note (optional)'), 'Unsaved collection');
      await dismiss(tester, action);
      expect(service.collections, isEmpty);
      expect(find.text('Collect specimens'), findsNothing);
    });
  }
  for (final outsourced in [false, true]) {
    testWidgets(
        '${outsourced ? 'external' : 'internal'} specimen confirmation captures notes and bag before closing',
        (tester) async {
      final service = LabService(outsourced: outsourced);
      await showPage(tester, NurseLabCollectionPage(service: service));
      await tester.tap(find.text('Collect and label'));
      await tester.pumpAndSettle();
      tester
          .widget<DropdownButton<String>>(find.byType(DropdownButton<String>))
          .onChanged!('Serum');
      await tester.pumpAndSettle();
      if (outsourced) {
        await tester.enterText(
            field('External lab label/reference'), 'EXT-SAMPLE');
      }
      await tester.tap(find.text('Place samples in a transport bag'));
      await tester.pumpAndSettle();
      if (outsourced) {
        await tester.ensureVisible(field('External bag label/reference'));
        await tester.enterText(
            field('External bag label/reference'), 'EXT-BAG');
      }
      await tester.ensureVisible(field('Collection note (optional)'));
      await tester.enterText(
          field('Collection note (optional)'), 'Collection captured');
      await tester
          .tap(find.text(outsourced ? 'Record collection' : 'Create labels'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(tester.takeException(), isNull);
      await tester.pumpAndSettle();
      expect(service.collections.single['note'], 'Collection captured');
      expect(service.collections.single['bag'], isTrue);
      expect(service.collections.single['bag_reference'],
          outsourced ? 'EXT-BAG' : '');
      expect(
          (service.collections.single['samples'] as List<NurseSampleInput>)
              .single
              .specimenType,
          'Serum');
      expect(
          find.text(outsourced
              ? 'External collection recorded'
              : 'Collection labels created'),
          findsOneWidget);
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
