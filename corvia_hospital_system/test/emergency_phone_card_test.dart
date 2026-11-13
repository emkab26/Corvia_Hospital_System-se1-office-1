import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mycorvia/widgets/emergency_phone_card.dart';

class _PhoneLauncher {
  final urls = <String>[];
  final options = <Map<dynamic, dynamic>>[];
  Future<bool> Function() result = () async => true;

  Future<bool> handle(MethodCall call) {
    expect(call.method, 'launch');
    final args = call.arguments as Map<dynamic, dynamic>;
    urls.add(args['url'] as String);
    options.add(args);
    return result();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/url_launcher');
  late _PhoneLauncher launcher;

  setUp(() {
    launcher = _PhoneLauncher();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, launcher.handle);
  });
  tearDown(() => TestDefaultBinaryMessengerBinding
      .instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, null));

  Future<void> showCard(WidgetTester tester) => tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
              body: SingleChildScrollView(child: EmergencyPhoneCard())),
        ),
      );

  testWidgets('works without Auth, incident, location or microphone setup',
      (tester) async {
    await showCard(tester);
    expect(find.text('084 124'), findsOneWidget);
    expect(launcher.urls, isEmpty);
    await tester.tap(find.text('Call ER24'));
    await tester.pump();
    expect(launcher.urls, ['tel:084124']);
    expect(launcher.options.single['useSafariVC'], isFalse);
    expect(launcher.options.single['useWebView'], isFalse);
    expect(
        find.textContaining('does not send incident details'), findsOneWidget);
    expect(find.textContaining('Could not open'), findsNothing);
  });

  for (final throwsError in [false, true]) {
    testWidgets(
        'keeps manual number when launch ${throwsError ? 'throws' : 'fails'}',
        (tester) async {
      launcher.result = () async {
        if (throwsError) throw PlatformException(code: 'unsupported');
        return false;
      };
      await showCard(tester);
      await tester.tap(find.text('Call ER24'));
      await tester.pump();
      expect(find.text('Could not open a phone app. Dial 084 124 on a phone.'),
          findsOneWidget);
      expect(find.text('084 124'), findsOneWidget);
      expect(
          tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
          isNotNull);
    });
  }

  testWidgets('suppresses duplicate taps and survives leaving the screen',
      (tester) async {
    final pending = Completer<bool>();
    launcher.result = () => pending.future;
    await showCard(tester);
    await tester.tap(find.text('Call ER24'));
    await tester.tap(find.text('Call ER24'));
    await tester.pump();
    expect(launcher.urls, hasLength(1));
    await tester.pumpWidget(const SizedBox());
    pending.complete(false);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('fits a narrow screen with large text', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(2)),
          child: Scaffold(
            body: SingleChildScrollView(child: EmergencyPhoneCard()),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('Call ER24'));
    await tester.tap(find.text('Call ER24'));
    await tester.pump();
    expect(launcher.urls, ['tel:084124']);
  });
}
