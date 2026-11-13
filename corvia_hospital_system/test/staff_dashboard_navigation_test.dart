import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:mycorvia/pages/reception/reception_dashboard.dart';
import 'package:mycorvia/pages/reception/reception_queue_page.dart';
import 'package:mycorvia/pages/pharmacist/pharmacist_dashboard_page.dart';
import 'package:mycorvia/pages/pharmacist/pharmacist_prescription_detail_page.dart';
import 'package:mycorvia/pages/forms/role_hospital_forms_page.dart';
import 'package:mycorvia/pages/lab/lab_worker_dashboard_page.dart';
import 'package:mycorvia/pages/lab/lab_verifier_dashboard_page.dart';
import 'package:mycorvia/pages/lab/hospital_lab_admin_page.dart';
import 'package:mycorvia/pages/hospital/hospital_admin_shell.dart';
import 'package:mycorvia/pages/dispatch/dispatch_dashboard.dart';
import 'package:mycorvia/pages/dispatch/response_workspace_page.dart';
import 'package:mycorvia/pages/shared/settings.dart';
import 'package:mycorvia/services/settings_service.dart';
import 'package:mycorvia/widgets/staff_workspace_shell.dart';
import 'support/ws4_access_fixture.dart';
import 'support/ws4_http_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final tableResponses = <String, Object>{};
  setUp(tableResponses.clear);
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await SettingsService.instance.init();
    PackageInfo.setMockInitialValues(
        appName: 'Corvia',
        packageName: 'test.corvia',
        version: '1',
        buildNumber: '1',
        buildSignature: '');
    await Supabase.initialize(
        url: 'https://example.test',
        publishableKey: 'synthetic-key',
        authOptions: const FlutterAuthClientOptions(
            localStorage: EmptyLocalStorage(), autoRefreshToken: false),
        httpClient: MockClient((request) async {
          final name = request.url.pathSegments.last;
          final Object response;
          switch (name) {
            case 'corvia_reception_hospital_context':
              response = {
                'signed_in': true,
                'profile_found': true,
                'hospital_found': true,
                'hospital_id': 'hospital-a',
                'hospital_name': 'Test hospital'
              };
            case 'reception_dashboard_snapshot':
              response = <String, dynamic>{};
            case 'corvia_current_lab_technician_context':
            case 'corvia_current_lab_verifier_context':
              response = {
                'lab_name': 'Test laboratory',
                'lab_type': 'hospital'
              };
            case 'corvia_lab_admin_settings_v2':
              response = {
                'lab_name': 'Test laboratory',
                'workers': [],
                'recent_activity': []
              };
            default:
              response = [];
          }
          return http.Response(
              jsonEncode(tableResponses[name] ?? response), 200,
              headers: {'content-type': 'application/json'}, request: request);
        }));
  });
  tearDownAll(() => Supabase.instance.dispose());

  Future<void> open(WidgetTester tester, Widget page,
      {double width = 1400}) async {
    tester.view.physicalSize = Size(width, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(home: page));
    await tester.pumpAndSettle();
  }

  Future<void> select(WidgetTester tester, String label) async {
    final finder = find.widgetWithText(InkWell, label).first;
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  for (final entry in <String, Widget>{
    'Reception': const ReceptionDashboard(),
    'Pharmacy': const PharmacistDashboardPage(),
    'Laboratory worker': const LabWorkerDashboardPage(),
    'Laboratory verifier': const LabVerifierDashboardPage(),
    'Laboratory administrator': const HospitalLabAdminPage(),
  }.entries) {
    testWidgets(
        '${entry.key} keeps its sidebar on Settings and returns to its queue',
        (tester) async {
      await open(tester, entry.value);
      final initialShell =
          tester.widget<StaffWorkspaceShell>(find.byType(StaffWorkspaceShell));
      final rootLabel = initialShell.items.first.label;
      final sidebar = find.text(initialShell.workspaceName).evaluate().first;
      await select(tester, 'Settings');
      expect(find.byType(SettingsPage), findsOneWidget);
      expect(find.text(initialShell.workspaceName).evaluate().first,
          same(sidebar));
      final shell =
          tester.widget<StaffWorkspaceShell>(find.byType(StaffWorkspaceShell));
      expect(shell.pageTitle, 'Settings');
      expect(
          shell.items.singleWhere((item) => item.selected).label, 'Settings');
      expect(find.byType(Navigator), findsNWidgets(2));
      await select(tester, rootLabel);
      expect(find.byType(SettingsPage), findsNothing);
      expect(
          tester
              .widget<StaffWorkspaceShell>(find.byType(StaffWorkspaceShell))
              .items
              .first
              .selected,
          isTrue);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Pharmacy details and dispensing forms stay inside the sidebar',
      (tester) async {
    tableResponses.addAll({
      'profiles': [
        {
          'id': fixtureActor,
          'user_id': fixtureActor,
          'first_name': 'Synthetic',
          'surname': 'Pharmacist',
          'role': 'pharmacist',
          'is_active': true
        }
      ],
      'pharmacists': [
        {'id': 'pharmacist-a', 'hospital_id': 'hospital-a', 'is_active': true}
      ],
      'hospitals': [
        {'id': 'hospital-a', 'name': 'Test hospital'}
      ],
      'prescription_dispenses': [
        {
          'id': 'dispense-a',
          'hospital_id': 'hospital-a',
          'patient_id': 'patient-a',
          'prescription_id': 'prescription-a',
          'status': 'received'
        }
      ],
      'prescriptions': [
        {
          'id': 'prescription-a',
          'medication_name': 'Synthetic medicine',
          'status': 'active'
        }
      ],
      'patients': [
        {
          'id': 'patient-a',
          'patient_number': 'TEST-001',
          'first_name': 'Test',
          'surname': 'Patient'
        }
      ],
    });
    await tester.runAsync(() async {
      final authFixture = await fixtureClient((_) async => jsonResponse(null));
      await Supabase.instance.client.auth.setInitialSession(
          jsonEncode(authFixture.auth.currentSession!.toJson()));
      await authFixture.dispose();
    });
    addTearDown(
        () => Supabase.instance.client.auth.signOut(scope: SignOutScope.local));
    await open(tester, const PharmacistDashboardPage());
    final details = find.widgetWithText(OutlinedButton, 'View Details');
    await tester.ensureVisible(details);
    await tester.tap(details);
    await tester.pumpAndSettle();
    expect(find.byType(PharmacistPrescriptionDetailPage), findsOneWidget);
    expect(find.byType(StaffWorkspaceShell), findsOneWidget);
    await select(tester, 'Received');
    expect(find.byType(PharmacistPrescriptionDetailPage), findsNothing);
    final form = find.widgetWithText(FilledButton, 'Pharmacy Form');
    await tester.ensureVisible(form);
    await tester.tap(form);
    await tester.pumpAndSettle();
    expect(find.byType(RoleHospitalFormsPage), findsOneWidget);
    expect(find.byType(StaffWorkspaceShell), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(RoleHospitalFormsPage), findsNothing);
    expect(
        tester
            .widget<StaffWorkspaceShell>(find.byType(StaffWorkspaceShell))
            .pageTitle,
        'Prescriptions · Received');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'Reception queue, search and booking keep the sidebar and one-step Back',
      (tester) async {
    await open(tester, const ReceptionDashboard());
    for (final label in [
      'View Queue',
      'Search Patient',
      'Book Appointment',
      'Specialist Requests'
    ]) {
      await select(tester, label);
      expect(find.byType(StaffWorkspaceShell), findsOneWidget);
      expect(
          tester
              .widget<StaffWorkspaceShell>(find.byType(StaffWorkspaceShell))
              .pageTitle,
          label);
      if (label == 'View Queue') {
        expect(find.byType(ReceptionQueuePage), findsOneWidget);
      }
    }
    await tester.tap(find.widgetWithText(OutlinedButton, 'Back'));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<StaffWorkspaceShell>(find.byType(StaffWorkspaceShell))
            .pageTitle,
        'Dashboard');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'laboratory admin preserves entered account search across Settings and resizing',
      (tester) async {
    await open(tester, const HospitalLabAdminPage());
    await select(tester, 'Add account');
    await tester.enterText(
        find.byType(TextField), 'Unsubmitted account search');
    await select(tester, 'Settings');
    tester.view.physicalSize = const Size(800, 1000);
    await tester.pumpAndSettle();
    expect(find.byType(SettingsPage), findsOneWidget);
    await tester.tap(find.byTooltip('Menu'));
    await tester.pumpAndSettle();
    await select(tester, 'Add account');
    expect(find.text('Unsubmitted account search'), findsOneWidget);
    tester.view.physicalSize = const Size(1400, 1000);
    await tester.pumpAndSettle();
    expect(find.text('Unsubmitted account search'), findsOneWidget);
    expect(find.text('Laboratory Administration'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'Dispatch response sections keep command navigation and return to live operations',
      (tester) async {
    await open(
        tester,
        EmergencyDispatchDashboard(
          accessLoader: () async =>
              fixtureDispatchAccess(canUseWorkspace: true),
          incomingEmergencyLoader: () async => [],
        ));
    for (final label in [
      'Active Incidents',
      'Live Map',
      'Fleet Availability',
      'Hospitals',
      'Completed Incidents'
    ]) {
      await select(tester, label);
      expect(find.byType(ResponseWorkspacePage), findsOneWidget);
      expect(find.widgetWithText(InkWell, 'Live Operations'), findsOneWidget);
      expect(find.byType(Navigator), findsNWidgets(2));
    }
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(ResponseWorkspacePage), findsNothing);
    await select(tester, 'Settings');
    expect(find.byType(SettingsPage), findsOneWidget);
    expect(find.widgetWithText(InkWell, 'Live Operations'), findsOneWidget);
    await select(tester, 'Live Operations');
    expect(find.byType(SettingsPage), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'Hospital Administration keeps its existing sidebar and consumes child Back',
      (tester) async {
    await open(
        tester,
        HospitalAdminShell(
            dashboardPage: Builder(
                builder: (context) => Center(
                    child: FilledButton(
                        onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                                builder: (_) => const Scaffold(
                                    body: Text('Hospital detail')))),
                        child: const Text('Open hospital detail'))))));
    await tester.tap(find.text('Open hospital detail'));
    await tester.pumpAndSettle();
    expect(find.text('Hospital detail'), findsOneWidget);
    expect(find.text('Open hospital detail'), findsNothing);
    expect(find.byType(HospitalAdminShell), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Open hospital detail'), findsOneWidget);
    expect(find.byType(HospitalAdminShell), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
