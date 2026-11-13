import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:mycorvia/services/nurse_service.dart';
import 'package:mycorvia/pages/nurse/nurse_assigned_patients_page.dart';
import 'package:mycorvia/pages/nurse/nurse_observations_page.dart';
import 'package:mycorvia/pages/nurse/nurse_shift_page.dart';
import 'package:mycorvia/pages/nurse/nurse_tasks_page.dart';
import 'package:mycorvia/pages/nurse/nurse_medication_rounds_page.dart';
import 'package:mycorvia/widgets/nurse_ward_picker.dart';
import 'support/nurse_workspace_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final requests = <Uri>[];
  final writes = <Map<String, dynamic>>[];
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://example.test',
      publishableKey: 'synthetic-test-key',
      authOptions: const FlutterAuthClientOptions(
          localStorage: EmptyLocalStorage(), autoRefreshToken: false),
      httpClient: MockClient((request) async {
        requests.add(request.url);
        if (request.url.path.endsWith('/nurse_shift_logs') &&
            request.method == 'POST') {
          writes.add(jsonDecode(request.body) as Map<String, dynamic>);
          return http.Response('', 201, request: request);
        }
        if (request.url.path.endsWith('/prescriptions')) {
          return http.Response(
              jsonEncode([
                {
                  'id': 'prescription-a',
                  'patient_id': 'patient-a',
                  'medication_name': 'Synthetic medicine',
                  'dosage': '1 dose',
                  'frequency': 'Once daily',
                  'status': 'active',
                }
              ]),
              200,
              request: request);
        }
        if (request.url.path.endsWith('/medication_administration_logs')) {
          return http.Response('[]', 200, request: request);
        }
        if (request.url.path.endsWith('/patient_observations')) {
          return http.Response('[]', 200,
              request: request, headers: {'content-type': 'application/json'});
        }
        throw StateError('Unexpected direct database lookup: ${request.url}');
      }),
    );
  });
  tearDownAll(() async => Supabase.instance.dispose());
  setUp(requests.clear);
  setUp(writes.clear);

  test('workspace deduplicates patient choices but retains assignment records',
      () {
    final workspace = NurseWorkspace.fromJson(payload(duplicate: true));
    expect(workspace.assignments.length, 2);
    expect(workspace.assignedPatientIds, ['patient-a']);
    expect(workspace.assignedPatients.single.dropdownLabel,
        'Alex Patient · PAT-001');
  });

  test('missing name falls back to a patient number, never another profile',
      () {
    final patient =
        NursePatient.fromJson({'id': 'patient-a', 'patient_number': 'PAT-001'});
    expect(patient.displayName, 'Patient PAT-001');
    expect(patient.dropdownLabel, 'Patient PAT-001');
  });

  test('incomplete or cross-hospital workspace data is rejected', () {
    final missing = payload()..remove('patients');
    expect(() => NurseWorkspace.fromJson(missing), throwsFormatException);
    final foreign = payload();
    (foreign['assignments'] as List).first['hospital_id'] = 'hospital-b';
    expect(() => NurseWorkspace.fromJson(foreign), throwsFormatException);
    final missingPatient = payload()..['patients'] = [];
    expect(
        () => NurseWorkspace.fromJson(missingPatient), throwsFormatException);
  });

  Future<void> showPage(WidgetTester tester, Widget page) async {
    tester.view.physicalSize = const Size(1000, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(home: page));
    await tester.pumpAndSettle();
  }

  testWidgets('assigned patient details render the shared resolved fields',
      (tester) async {
    await showPage(
        tester,
        NurseAssignedPatientsPage(
          service: FakeNurseService(NurseWorkspace.fromJson(payload())),
        ));
    await tester.tap(find.text('Alex Patient'));
    await tester.pumpAndSettle();
    for (final value in [
      'PAT-001',
      '0123456789',
      'alex@example.test',
      'SYNTHETIC-ID',
      '12/03/1990',
      'Test provider',
      'MEMBER-1',
      'Test plan'
    ]) {
      expect(find.textContaining(value, findRichText: true), findsWidgets);
    }
    expect(requests, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('vitals dropdown displays names and distinct patient choices',
      (tester) async {
    await showPage(
        tester,
        NurseObservationsPage(
          service: FakeNurseService(NurseWorkspace.fromJson(
              payload(duplicate: true, secondPatient: true))),
        ));
    final dropdown = tester
        .widget<DropdownButton<String>>(find.byType(DropdownButton<String>));
    expect(
        dropdown.items!.map((item) => item.value), ['patient-a', 'patient-b']);
    expect(
        (dropdown.items!.first.child as Text).data, 'Alex Patient · PAT-001');
    expect(
        (dropdown.items!.last.child as Text).data, 'Other Patient · PAT-002');
    expect(requests.single.queryParameters['hospital_id'], 'eq.hospital-a');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'refresh removes a stale patient selection and its entered vitals',
      (tester) async {
    final service =
        FakeNurseService(NurseWorkspace.fromJson(payload(secondPatient: true)));
    await showPage(tester, NurseObservationsPage(service: service));
    await tester.enterText(find.byType(TextField).first, '37.1');
    final next = payload(secondPatient: true);
    next['assignments'] = [assignment('assignment-b', 'patient-b')];
    next['patients'] = [(next['patients'] as List).last];
    service.workspace = NurseWorkspace.fromJson(next);
    await tester.tap(find.byTooltip('Refresh'));
    await tester.pumpAndSettle();
    final dropdown = tester
        .widget<DropdownButton<String>>(find.byType(DropdownButton<String>));
    expect(dropdown.value, 'patient-b');
    expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ward choices use IDs and distinguish identical ward names',
      (tester) async {
    final wards = NurseWorkspace.fromJson(payload()).wards;
    String? selected;
    await showPage(
        tester,
        Scaffold(
            body: NurseWardPicker(
          wards: wards,
          selectedWardId: 'ward-a',
          onChanged: (value) => selected = value,
        )));
    final dropdown = tester
        .widget<DropdownButton<String>>(find.byType(DropdownButton<String>));
    expect(dropdown.items!.map((item) => item.value), ['ward-a', 'ward-b']);
    expect((dropdown.items!.first.child as Text).data, contains('First floor'));
    expect((dropdown.items!.last.child as Text).data, contains('Second floor'));
    dropdown.onChanged!('ward-b');
    expect(selected, 'ward-b');
  });

  testWidgets('tasks use the same resolved patient name without profile reads',
      (tester) async {
    final data = payload()
      ..['tasks'] = [
        {
          'id': 'task-a',
          'patient_id': 'patient-a',
          'title': 'Record blood pressure',
          'hospital_id': 'hospital-a',
          'assigned_nurse_user_id': 'auth-user',
          'status': 'pending',
        }
      ];
    await showPage(
        tester,
        NurseTasksPage(
            service: FakeNurseService(NurseWorkspace.fromJson(data))));
    expect(find.textContaining('Alex Patient'), findsWidgets);
    expect(requests, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('medication rounds use the same patient names and assigned IDs',
      (tester) async {
    await showPage(
        tester,
        NurseMedicationRoundsPage(
          service: FakeNurseService(NurseWorkspace.fromJson(payload())),
        ));
    expect(find.textContaining('Alex Patient'), findsWidgets);
    final prescriptionRequest =
        requests.singleWhere((uri) => uri.path.endsWith('/prescriptions'));
    expect(
        prescriptionRequest.queryParameters['patient_id'], 'in.("patient-a")');
    expect(
        requests.any((uri) =>
            uri.path.endsWith('/profiles') || uri.path.endsWith('/patients')),
        isFalse);
    expect(tester.takeException(), isNull);
  });

  test('clock-in rejects a retired ward before writing a shift', () async {
    final service = FakeNurseService(NurseWorkspace.fromJson(payload()));
    await expectLater(
        service.clockIn(
            context: service.workspace.context,
            wardId: 'retired-ward',
            shiftType: 'Day Shift',
            note: ''),
        throwsA(predicate(
            (error) => error.toString().contains('Select an active ward'))));
    expect(writes, isEmpty);
  });

  test(
      'clock-in preserves the text ward contract using the selected database ward',
      () async {
    final service = FakeNurseService(NurseWorkspace.fromJson(payload()));
    await service.clockIn(
        context: service.workspace.context,
        wardId: 'ward-b',
        shiftType: 'Day Shift',
        note: 'Test shift');
    expect(writes.single['ward'], 'ICU · B · Second floor · Main building');
    expect(writes.single['hospital_id'], 'hospital-a');
    expect(writes.single['nurse_user_id'], 'auth-user');
    expect(writes.single['nurse_profile_id'], 'profile-row');
  });

  testWidgets('empty hospital ward list blocks clock-in without invented wards',
      (tester) async {
    final data = payload()..['wards'] = [];
    await showPage(
        tester,
        NurseShiftPage(
            service: FakeNurseService(NurseWorkspace.fromJson(data))));
    expect(
        find.textContaining('No active wards are configured'), findsOneWidget);
    final clockIn = tester
        .widget<FilledButton>(find.widgetWithText(FilledButton, 'Clock In'));
    expect(clockIn.onPressed, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('existing shift remains usable when its ward is retired',
      (tester) async {
    final data = payload()..['wards'] = [];
    final service = FakeNurseService(NurseWorkspace.fromJson(data))
      ..activeShift = {
        'id': 'shift-a',
        'ward': 'Retired legacy ward',
        'status': 'active',
        'shift_type': 'Day Shift',
        'clock_in_at': '2026-10-22T06:00:00Z'
      };
    await showPage(tester, NurseShiftPage(service: service));
    expect(find.text('Retired legacy ward'), findsWidgets);
    final clockOut = tester
        .widget<FilledButton>(find.widgetWithText(FilledButton, 'Clock Out'));
    expect(clockOut.onPressed, isNotNull);
    expect(find.byType(NurseWardPicker), findsNothing);
    expect(tester.takeException(), isNull);
  });

  test('missing database migration produces a clear error', () async {
    final client = SupabaseClient(
      'https://example.test',
      'test',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async => http.Response(
          jsonEncode({
            'code': 'PGRST202',
            'message': 'Missing function',
          }),
          404,
          request: request,
          headers: {'content-type': 'application/json'})),
    );
    addTearDown(client.dispose);
    await expectLater(
        NurseService(client: client).loadWorkspace(),
        throwsA(predicate((error) => error
            .toString()
            .contains('database update has not been installed'))));
  });
}
