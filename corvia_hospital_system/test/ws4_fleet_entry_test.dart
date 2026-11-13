import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mycorvia/auth/fleet_entry_redirect.dart';

void main() {
  for (final initial in [false, true]) {
    testWidgets('fleet entry returns to the root gate: initial=$initial',
        (tester) async {
      final key = GlobalKey<NavigatorState>();
      await tester.pumpWidget(MaterialApp(
        navigatorKey: key,
        initialRoute: initial ? '/fleet-management' : '/',
        home: const Scaffold(body: Text('Root authentication gate')),
        routes: {'/fleet-management': (_) => const FleetEntryRedirect()},
      ));
      if (!initial) {
        key.currentState!.pushNamed('/fleet-management');
      }
      await tester.pumpAndSettle();
      expect(find.text('Root authentication gate'), findsOneWidget);
      expect(find.byType(FleetEntryRedirect), findsNothing);
      expect(key.currentState!.canPop(), isFalse);
    });
  }
}
