import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mycorvia/widgets/staff_workspace_shell.dart';
import 'package:mycorvia/widgets/workspace_navigation.dart';

class _Dashboard extends StatefulWidget {
  const _Dashboard();
  @override
  State<_Dashboard> createState() => _DashboardState();
}

class _DashboardState extends State<_Dashboard>
    with WorkspaceNavigation<_Dashboard> {
  int revision = 0;
  bool? saved;

  Future<void> open(String label) async {
    final result = await pushWorkspace<bool>(
        MaterialPageRoute<bool>(builder: (_) => _Editor(label)),
        label: label);
    if (mounted && result == true) setState(() => saved = result);
  }

  @override
  Widget build(BuildContext context) => StaffWorkspaceShell(
        workspaceName: 'Test Workspace',
        breadcrumb: 'Test',
        pageTitle: workspaceTitle ?? 'Dashboard',
        headerActions: [if (workspaceCanPop) workspaceBackButton],
        items: [
          StaffShellItem(
              label: 'Dashboard',
              icon: Icons.home,
              selected: !workspaceCanPop,
              onTap: workspaceHome),
          for (final label in ['First', 'Second'])
            StaffShellItem(
                label: label,
                icon: Icons.edit,
                selected: workspaceSelection == label,
                onTap: () => open(label)),
          StaffShellItem(
              label: 'Switch dashboard',
              icon: Icons.swap_horiz,
              onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => Scaffold(
                      appBar: AppBar(),
                      body: const Text('Another dashboard'))))),
        ],
        body: workspaceBody(Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Home revision $revision'),
          Text('Saved: $saved'),
          FilledButton(
              onPressed: () => setState(() => revision++),
              child: const Text('Update home')),
        ]))),
      );
}

class _Editor extends StatelessWidget {
  const _Editor(this.label);
  final String label;
  @override
  Widget build(BuildContext context) => Scaffold(
        body: Column(children: [
          Text('$label editor'),
          const TextField(
              key: ValueKey('draft'),
              decoration: InputDecoration(labelText: 'Draft')),
          TextButton(
              onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                      builder: (_) => Scaffold(
                          appBar: AppBar(title: const Text('Detail')),
                          body: const Text('Nested detail')))),
              child: const Text('Open detail')),
          TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Save')),
        ]),
      );
}

void main() {
  Future<void> open(WidgetTester tester, {double width = 1400}) async {
    tester.view.physicalSize = Size(width, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaterialApp(home: _Dashboard()));
    await tester.pumpAndSettle();
  }

  Future<void> select(WidgetTester tester, String label,
      {bool drawer = false}) async {
    if (drawer) {
      await tester.tap(find.byTooltip('Menu'));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.widgetWithText(InkWell, label));
    await tester.pumpAndSettle();
  }

  String selected(WidgetTester tester) => tester
      .widget<StaffWorkspaceShell>(find.byType(StaffWorkspaceShell))
      .items
      .singleWhere((item) => item.selected)
      .label;

  testWidgets(
      'menu switches replace the child and Back returns to home in one step',
      (tester) async {
    await open(tester);
    await select(tester, 'First');
    final sidebar = find.text('Test Workspace').evaluate().single;
    expect(find.text('First editor'), findsOneWidget);
    expect(selected(tester), 'First');
    await select(tester, 'Second');
    expect(find.text('Second editor'), findsOneWidget);
    expect(find.text('First editor'), findsNothing);
    expect(find.text('Test Workspace').evaluate().single, same(sidebar));
    await tester.tap(find.widgetWithText(OutlinedButton, 'Back'));
    await tester.pumpAndSettle();
    expect(find.text('Home revision 0'), findsOneWidget);
    expect(selected(tester), 'Dashboard');
  });

  testWidgets('secondary routes and system Back stay inside the workspace',
      (tester) async {
    await open(tester);
    await select(tester, 'First');
    await tester.tap(find.text('Open detail'));
    await tester.pumpAndSettle();
    expect(find.text('Nested detail'), findsOneWidget);
    expect(selected(tester), 'First');
    expect(find.text('Test Workspace'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('First editor'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Home revision 0'), findsOneWidget);
  });

  testWidgets('resize preserves child route, entered data and selection',
      (tester) async {
    await open(tester);
    await select(tester, 'First');
    await tester.enterText(
        find.byKey(const ValueKey('draft')), 'Unsaved draft');
    tester.view.physicalSize = const Size(800, 1000);
    await tester.pumpAndSettle();
    expect(find.text('First editor'), findsOneWidget);
    expect(find.text('Unsaved draft'), findsOneWidget);
    expect(selected(tester), 'First');
    await tester.tap(find.byTooltip('Menu'));
    await tester.pumpAndSettle();
    expect(find.text('Test Workspace'), findsOneWidget);
    await tester.tapAt(const Offset(700, 300));
    await tester.pumpAndSettle();
    tester.view.physicalSize = const Size(1400, 1000);
    await tester.pumpAndSettle();
    expect(find.text('Unsaved draft'), findsOneWidget);
    expect(find.text('Test Workspace'), findsOneWidget);
  });

  testWidgets(
      'drawer can switch sections from a child without leaving the shell',
      (tester) async {
    await open(tester, width: 800);
    await select(tester, 'First', drawer: true);
    await select(tester, 'Second', drawer: true);
    expect(find.text('Second editor'), findsOneWidget);
    expect(selected(tester), 'Second');
    await select(tester, 'Dashboard', drawer: true);
    expect(find.text('Home revision 0'), findsOneWidget);
  });

  testWidgets('route results and rebuilt home state are retained',
      (tester) async {
    await open(tester);
    await tester.tap(find.text('Update home'));
    await tester.pumpAndSettle();
    expect(find.text('Home revision 1'), findsOneWidget);
    await select(tester, 'First');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Home revision 1'), findsOneWidget);
    expect(find.text('Saved: true'), findsOneWidget);
  });

  testWidgets(
      'switching dashboards uses the app navigator and returns to the saved child',
      (tester) async {
    await open(tester);
    await select(tester, 'First');
    await tester.enterText(find.byKey(const ValueKey('draft')), 'Keep this');
    await select(tester, 'Switch dashboard');
    expect(find.text('Another dashboard'), findsOneWidget);
    expect(find.text('Test Workspace'), findsNothing);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Keep this'), findsOneWidget);
    expect(find.text('Test Workspace'), findsOneWidget);
  });
}
