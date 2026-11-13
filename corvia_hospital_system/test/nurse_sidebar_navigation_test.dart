import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:mycorvia/pages/nurse/nurse_dashboard_page.dart';
import 'package:mycorvia/services/nurse_service.dart';
import 'package:mycorvia/widgets/staff_workspace_shell.dart';

import 'support/nurse_workspace_fixture.dart';

class NavigationService extends FakeNurseService {
  NavigationService() : super(NurseWorkspace.fromJson(payload()));
  int workspaceLoads = 0;
  int dashboardLoads = 0;

  @override
  Future<NurseWorkspace> loadWorkspace() async {
    workspaceLoads++;
    return workspace;
  }

  @override
  Future<NurseWorkspaceCounts> loadWorkspaceCounts(
      NurseWorkspace workspace) async {
    dashboardLoads++;
    return const NurseWorkspaceCounts(
        assignedPatients: 1, activeTasks: 0, activeMedications: 2);
  }

  @override
  Future<NurseContext> requireCurrentContext() async => workspace.context;

  @override
  Future<List<NurseLabCollectionOrder>> loadLabCollectionQueue() async => [];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://example.test',
      publishableKey: 'synthetic-test-key',
      authOptions: const FlutterAuthClientOptions(
          localStorage: EmptyLocalStorage(), autoRefreshToken: false),
      httpClient: MockClient((request) async {
        if ([
          'patient_observations',
          'prescriptions',
          'medication_administration_logs'
        ].contains(request.url.pathSegments.last)) {
          return http.Response('[]', 200, request: request);
        }
        throw StateError('Unexpected request: ${request.url}');
      }),
    );
  });
  tearDownAll(() => Supabase.instance.dispose());

  Future<NavigationService> open(WidgetTester tester,
      {double width = 1400}) async {
    tester.view.physicalSize = Size(width, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final service = NavigationService();
    await tester
        .pumpWidget(MaterialApp(home: NurseDashboardPage(service: service)));
    await tester.pumpAndSettle();
    return service;
  }

  Finder sidebar() => find
      .ancestor(
        of: find.text('Nursing Station'),
        matching: find.byType(Container),
      )
      .first;

  Finder contentNavigator() => find.descendant(
        of: find.byType(NurseDashboardPage),
        matching: find.byType(Navigator),
      );

  StaffWorkspaceShell testerShell() =>
      find.byType(StaffWorkspaceShell).evaluate().single.widget
          as StaffWorkspaceShell;

  String selected() =>
      (testerShell().items.singleWhere((item) => item.selected)).label;
  Future<void> select(WidgetTester tester, String label,
      {bool narrow = false}) async {
    if (narrow) {
      await tester.tap(find.byTooltip('Menu'));
      await tester.pumpAndSettle();
    }
    final tile = find.descendant(
        of: sidebar(), matching: find.widgetWithText(InkWell, label));
    await tester.ensureVisible(tile);
    await tester.tap(tile);
    await tester.pumpAndSettle();
  }

  Finder temperature() => find.byWidgetPredicate((widget) =>
      widget is TextField && widget.decoration?.labelText == 'Temperature');

  testWidgets('desktop sidebar remains mounted through all nurse menu pages',
      (tester) async {
    await open(tester);
    final shellState = tester.state(find.byType(StaffWorkspaceShell));
    final navigatorState = tester.state(contentNavigator());
    for (final label in [
      'Shift Management',
      'Assigned Patients',
      'Observations & Vitals',
      'Specimen Collection',
      'Nursing Tasks',
      'Medication Rounds',
      'Settings'
    ]) {
      await select(tester, label);
      expect(find.text('Nursing Station'), findsOneWidget);
      expect(find.text('Nurse / $label'), findsOneWidget);
      expect(selected(), label);
      expect(tester.state(find.byType(StaffWorkspaceShell)), same(shellState));
      expect(tester.state(contentNavigator()), same(navigatorState));
      expect(find.byType(AppBar), findsNothing);
      expect(find.byTooltip('Menu'), findsNothing);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets(
      'switching menu pages keeps a single Back step to refreshed Dashboard',
      (tester) async {
    final service = await open(tester);
    await select(tester, 'Shift Management');
    await select(tester, 'Assigned Patients');
    await select(tester, 'Nursing Tasks');
    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();
    expect(selected(), 'Dashboard');
    expect(find.text('Nurse / Dashboard'), findsOneWidget);
    expect(tester.state<NavigatorState>(contentNavigator()).canPop(), isFalse);
    expect(service.dashboardLoads, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'phone drawer can be reopened from a child page and changes selection',
      (tester) async {
    await open(tester, width: 390);
    await select(tester, 'Assigned Patients', narrow: true);
    expect(find.text('Nurse / Assigned Patients'), findsOneWidget);
    expect(find.text('Nursing Station'), findsNothing);
    expect(find.byTooltip('Menu'), findsOneWidget);
    await select(tester, 'Observations & Vitals', narrow: true);
    expect(find.text('Nurse / Observations & Vitals'), findsOneWidget);
    expect(selected(), 'Observations & Vitals');
    expect(find.text('Nursing Station'), findsNothing);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(selected(), 'Dashboard');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'resizing across sidebar breakpoint preserves route and entered vitals',
      (tester) async {
    await open(tester);
    await select(tester, 'Observations & Vitals');
    await tester.enterText(temperature(), '37.2');
    final controller = tester.widget<TextField>(temperature()).controller;
    final navigatorState = tester.state(contentNavigator());

    tester.view.physicalSize = const Size(390, 1000);
    await tester.pumpAndSettle();
    expect(find.byTooltip('Menu'), findsOneWidget);
    expect(
        tester.widget<TextField>(temperature()).controller, same(controller));
    expect(controller!.text, '37.2');

    tester.view.physicalSize = const Size(1400, 1000);
    await tester.pumpAndSettle();
    expect(find.text('Nursing Station'), findsOneWidget);
    expect(find.byTooltip('Menu'), findsNothing);
    expect(selected(), 'Observations & Vitals');
    expect(tester.state(contentNavigator()), same(navigatorState));
    expect(
        tester.widget<TextField>(temperature()).controller, same(controller));
    expect(controller.text, '37.2');
    expect(tester.takeException(), isNull);
  });

  testWidgets('Refresh reloads the current nurse page inside the sidebar',
      (tester) async {
    final service = await open(tester);
    await select(tester, 'Observations & Vitals');
    await tester.enterText(temperature(), '37.2');
    final previousLoads = service.workspaceLoads;
    await tester.tap(find.text('Refresh'));
    await tester.pumpAndSettle();
    expect(service.workspaceLoads, previousLoads + 1);
    expect(tester.widget<TextField>(temperature()).controller!.text, isEmpty);
    expect(find.text('Nursing Station'), findsOneWidget);
    expect(selected(), 'Observations & Vitals');
    expect(service.dashboardLoads, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'secondary routes stay inside the sidebar and return to their menu page',
      (tester) async {
    await open(tester);
    await select(tester, 'Observations & Vitals');
    await tester.enterText(temperature(), '37.2');
    final navigator = tester.state<NavigatorState>(contentNavigator());
    navigator.push(MaterialPageRoute<void>(
        builder: (_) => Scaffold(
              appBar: AppBar(title: const Text('Test detail')),
              body: const Text('Secondary content'),
            )));
    await tester.pumpAndSettle();
    expect(find.text('Nursing Station'), findsOneWidget);
    expect(find.text('Secondary content'), findsOneWidget);
    expect(selected(), 'Observations & Vitals');
    // Choosing the current menu item returns from its nested detail route.
    await select(tester, 'Observations & Vitals');
    expect(find.text('Secondary content'), findsNothing);
    expect(tester.widget<TextField>(temperature()).controller!.text, '37.2');
    expect(tester.takeException(), isNull);
  });

  testWidgets('Dashboard action cards open the same persistent workspace',
      (tester) async {
    await open(tester);
    final card = find.descendant(
        of: contentNavigator(), matching: find.text('Assigned Patients'));
    await tester.ensureVisible(card);
    await tester.tap(card);
    await tester.pumpAndSettle();
    expect(find.text('Nurse / Assigned Patients'), findsOneWidget);
    expect(find.text('Nursing Station'), findsOneWidget);
    expect(selected(), 'Assigned Patients');
    expect(tester.takeException(), isNull);
  });
}
