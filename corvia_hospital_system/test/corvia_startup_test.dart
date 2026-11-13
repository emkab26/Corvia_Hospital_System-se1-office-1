import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mycorvia/widgets/corvia_startup.dart';
import 'package:mycorvia/config/env.dart';
import 'package:mycorvia/config/backend_environment.dart';

void main() {
  testWidgets('plain debug run loads hosted public configuration',
      (tester) async {
    await Env.initializeForStartup();
    expect(Env.backend.environment, CorviaEnvironment.testing);
    expect(Env.backend.url, startsWith('https://'));
    expect(Env.backend.publicKey, isNotEmpty);
  });

  testWidgets('startup reports a sanitized stage and retries to login',
      (tester) async {
    var attempts = 0;
    await tester.pumpWidget(CorviaStartup(
      initializeWithStage: (stage) async {
        stage(CorviaStartupStage.backend);
        if (attempts++ == 0) throw StateError('private backend detail');
      },
      ready: const MaterialApp(home: Text('AuthGate ready')),
    ));
    await tester.pump();
    expect(find.text('Call ER24'), findsOneWidget);
    expect(find.textContaining('backend and session'), findsOneWidget);
    expect(find.textContaining('private backend detail'), findsNothing);
    await tester.tap(find.text('Retry startup'));
    await tester.pumpAndSettle();
    expect(find.text('AuthGate ready'), findsOneWidget);
  });
}
