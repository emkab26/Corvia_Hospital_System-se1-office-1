import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mycorvia/pages/shared/settings.dart';
import 'package:mycorvia/services/settings_service.dart';
import 'package:mycorvia/services/settings_workspace_access_service.dart';
import 'support/settings_workspace_access_fixture.dart';

Future<void> _pumpSettings(WidgetTester tester) async {
  await tester.pumpWidget(MaterialApp(
      home: SettingsPage(workspaceAccessService: FakeSettingsAccess())));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await SettingsService.instance.init();
    PackageInfo.setMockInitialValues(
      appName: 'mycorvia',
      packageName: 'co.za.corvia.mycorvia',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  testWidgets('renders without the ListTile/DecoratedBox assertion',
      (tester) async {
    // The section cards paint their own background, and the rows inside are
    // ListTile-based (ExpansionTile, SwitchListTile). If the card's background
    // sits on a DecoratedBox instead of a Material, the framework asserts and
    // the whole page fails to build. This is that regression guard.
    await _pumpSettings(tester);

    expect(tester.takeException(), isNull);
    expect(find.text('Reading Tools'), findsOneWidget);
  });

  testWidgets('shows the running build version', (tester) async {
    PackageInfo.setMockInitialValues(
      appName: 'mycorvia',
      packageName: 'co.za.corvia.mycorvia',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );

    await _pumpSettings(tester);

    // The whole point of the line is telling support which build a user is on,
    // so it has to carry the real version and build number, not a literal.
    expect(find.text('Version 1.0.0 (1)'), findsOneWidget);
  });

  testWidgets('tracks the version rather than hardcoding one', (tester) async {
    PackageInfo.setMockInitialValues(
      appName: 'mycorvia',
      packageName: 'co.za.corvia.mycorvia',
      version: '2.4.1',
      buildNumber: '77',
      buildSignature: '',
    );

    await _pumpSettings(tester);

    expect(find.text('Version 2.4.1 (77)'), findsOneWidget);
    expect(find.text('Version 1.0.0 (1)'), findsNothing);
  });

  testWidgets('keeps the reset control alongside the version', (tester) async {
    PackageInfo.setMockInitialValues(
      appName: 'mycorvia',
      packageName: 'co.za.corvia.mycorvia',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );

    await _pumpSettings(tester);

    // These two land on the same line of the widget tree, so a careless merge
    // drops one of them. Both belong.
    expect(find.text('Reset to default'), findsOneWidget);
    expect(find.text('Version 1.0.0 (1)'), findsOneWidget);
  });

  group('Staff workspaces (#236)', () {
    Future<void> pumpWith(
      WidgetTester tester,
      Future<SettingsWorkspaceAccess> Function() access,
    ) async {
      final service = FakeSettingsAccess()..onLoad = access;
      addTearDown(service.changes.close);
      await tester.pumpWidget(MaterialApp(
        home: SettingsPage(
          showStaffWorkspaces: true,
          workspaceAccessService: service,
        ),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
    }

    Future<void> scrollToPrivacy(WidgetTester tester) =>
        tester.scrollUntilVisible(
          find.text('Privacy, Security & Permissions'),
          300,
          scrollable: find.byType(Scrollable).first,
        );

    testWidgets('hides the section when the user has no workspace access',
        (tester) async {
      await pumpWith(tester, () async => const SettingsWorkspaceAccess());
      await scrollToPrivacy(tester);

      expect(find.text('Staff workspaces'), findsNothing);
      expect(find.text('Dispatch & Paramedic workspace'), findsNothing);
      expect(find.text('Blood Bank'), findsNothing);
    });

    testWidgets('shows only the workspaces the user can open', (tester) async {
      await pumpWith(
          tester, () async => const SettingsWorkspaceAccess(bloodBank: true));
      await scrollToPrivacy(tester);

      expect(find.text('Staff workspaces'), findsOneWidget);
      expect(find.text('Blood Bank'), findsOneWidget);
      expect(find.text('Dispatch & Paramedic workspace'), findsNothing);
    });

    testWidgets('stays hidden while access is still loading', (tester) async {
      final pending = Completer<SettingsWorkspaceAccess>();
      await pumpWith(tester, () => pending.future);
      await scrollToPrivacy(tester);

      expect(find.text('Staff workspaces'), findsNothing);

      pending.complete(
          const SettingsWorkspaceAccess(paramedic: true, bloodBank: true));
      await tester.pump();
      expect(find.text('Dispatch & Paramedic workspace'), findsOneWidget);
    });
  });
}
