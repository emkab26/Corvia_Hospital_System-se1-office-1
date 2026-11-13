import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mycorvia/widgets/staff_workspace_shell.dart';

Widget _shell({VoidCallback? onQueue, VoidCallback? onSignOut}) {
  return MaterialApp(
    home: StaffWorkspaceShell(
      workspaceName: 'Reception Desk',
      breadcrumb: 'Reception',
      pageTitle: 'Dashboard',
      subtitle: 'Corvia Medical Hospital 1',
      onSignOut: onSignOut,
      items: [
        const StaffShellItem(
          label: 'Dashboard',
          icon: Icons.dashboard_rounded,
          selected: true,
        ),
        StaffShellItem(
          label: 'View Queue',
          icon: Icons.groups_rounded,
          onTap: onQueue,
        ),
      ],
      body: const Center(child: Text('Body content')),
    ),
  );
}

void main() {
  testWidgets('wide layout shows the sidebar beside the content',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    var queueOpened = false;
    var signedOut = false;
    await tester.pumpWidget(_shell(
      onQueue: () => queueOpened = true,
      onSignOut: () => signedOut = true,
    ));

    expect(find.text('Reception / Dashboard'), findsOneWidget);
    expect(find.text('Reception Desk'), findsOneWidget);
    expect(find.text('Body content'), findsOneWidget);
    expect(find.byTooltip('Menu'), findsNothing);

    await tester.tap(find.text('View Queue'));
    expect(queueOpened, isTrue);

    await tester.tap(find.text('Sign out'));
    expect(signedOut, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('narrow layout moves the sidebar into a drawer',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    var queueOpened = false;
    await tester.pumpWidget(_shell(onQueue: () => queueOpened = true));

    expect(find.text('View Queue'), findsNothing);
    await tester.tap(find.byTooltip('Menu'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('View Queue'));
    await tester.pumpAndSettle();
    expect(queueOpened, isTrue);
    // Choosing an item closes the drawer.
    expect(find.text('View Queue'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
