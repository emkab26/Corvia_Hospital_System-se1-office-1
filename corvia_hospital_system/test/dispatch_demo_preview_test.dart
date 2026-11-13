import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mycorvia/pages/dispatch/dispatch_demo_preview_page.dart';

void main() {
  testWidgets('dispatch preview is labelled and has no dispatch action',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: DispatchDemoPreviewPage()));
    expect(find.textContaining('DEMO DATA — no real EMS dispatch'),
        findsOneWidget);
    expect(find.text('DEMO-001'), findsOneWidget);
    expect(find.text('DEMO-002'), findsOneWidget);
    expect(find.textContaining('ambulance has been assigned'), findsOneWidget);
    expect(find.byType(FilledButton), findsNothing);
  });

  testWidgets('staff can sign out of the dispatch preview', (tester) async {
    var signedOut = false;
    await tester.pumpWidget(MaterialApp(
      home: DispatchDemoPreviewPage(
        onSignOut: () => signedOut = true,
      ),
    ));

    await tester.tap(find.text('Sign out'));
    expect(signedOut, isTrue);
  });
}
