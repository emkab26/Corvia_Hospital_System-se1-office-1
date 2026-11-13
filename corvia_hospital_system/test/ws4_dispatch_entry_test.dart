import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mycorvia/auth/dispatch_entry_redirect.dart';

void main() {
  for (final initial in [false, true]) {
    testWidgets('dispatch entry returns to the root gate: initial=$initial',
        (tester) async {
      final key = GlobalKey<NavigatorState>();
      await tester.pumpWidget(MaterialApp(
        navigatorKey: key,
        initialRoute: initial ? '/dispatch' : '/',
        home: const Scaffold(body: Text('Root authentication gate')),
        routes: {'/dispatch': (_) => const DispatchEntryRedirect()},
      ));
      if (!initial) {
        key.currentState!.pushNamed('/dispatch');
      }
      await tester.pumpAndSettle();
      expect(find.text('Root authentication gate'), findsOneWidget);
      expect(find.byType(DispatchEntryRedirect), findsNothing);
      expect(key.currentState!.canPop(), isFalse);
    });
  }
}
