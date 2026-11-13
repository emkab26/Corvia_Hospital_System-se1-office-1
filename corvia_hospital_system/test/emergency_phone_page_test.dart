import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mycorvia/pages/patient/emergency.dart';
import 'package:mycorvia/pages/patient/emergency_phone_page.dart';

Position fix({double latitude = -26, DateTime? timestamp}) => Position(
      latitude: latitude,
      longitude: 28,
      timestamp: timestamp ?? DateTime.now(),
      accuracy: 12,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    );

void main() {
  const phoneChannel = MethodChannel('plugins.flutter.io/url_launcher');
  final launched = <String>[];
  setUp(() {
    launched.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(phoneChannel, (call) async {
      launched.add((call.arguments as Map)['url'] as String);
      return true;
    });
  });
  tearDown(() => TestDefaultBinaryMessengerBinding
      .instance.defaultBinaryMessenger
      .setMockMethodCallHandler(phoneChannel, null));

  testWidgets('default entry opens without Supabase, dispatch or permissions',
      (tester) async {
    // Deliberately no Supabase initialization or microphone/location handlers.
    await tester.pumpWidget(const MaterialApp(home: EmergencyPage()));
    await tester.pumpAndSettle();
    expect(find.byType(EmergencyPhonePage), findsOneWidget);
    expect(find.text('Emergency help'), findsOneWidget);
    expect(find.text('Call Dispatch'), findsNothing);
    expect(find.text('Chat with Dispatch'), findsNothing);
    expect(find.textContaining('Preparing emergency'), findsNothing);
    expect(launched, isEmpty);
    await tester.tap(find.text('Call ER24'));
    await tester.pump();
    expect(launched, ['tel:084124']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('location is optional; calling remains available during lookup',
      (tester) async {
    final pending = Completer<Position?>();
    var reads = 0;
    await tester.pumpWidget(MaterialApp(
      home: EmergencyPhonePage(readLocation: () {
        reads++;
        return pending.future;
      }),
    ));
    await tester.pumpAndSettle();
    expect(reads, 0);
    await tester.tap(find.text('Get my location'));
    await tester.pump();
    await tester.tap(find.text('Finding location…'));
    expect(reads, 1);
    await tester.tap(find.text('Call ER24'));
    await tester.pump();
    expect(launched, ['tel:084124']);
    pending.complete(fix());
    await tester.pumpAndSettle();
    expect(find.textContaining('Latitude: -26.000000'), findsOneWidget);
    expect(find.textContaining('Estimated accuracy: 12 m'), findsOneWidget);
    expect(find.textContaining('Recorded:'), findsOneWidget);
    expect(find.textContaining('not live tracking'), findsOneWidget);
  });

  for (final outcome in ['denied', 'error', 'stale', 'invalid']) {
    testWidgets('$outcome location keeps manual details and phone available',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: EmergencyPhonePage(readLocation: () async {
          if (outcome == 'error') throw StateError('private diagnostic');
          if (outcome == 'denied') return null;
          if (outcome == 'stale') return fix(timestamp: DateTime.utc(2020));
          return fix(latitude: double.nan);
        }),
      ));
      await tester.tap(find.text('Get my location'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Location unavailable.'), findsOneWidget);
      expect(find.textContaining('private diagnostic'), findsNothing);
      expect(find.textContaining('Latitude:'), findsNothing);
      await tester.tap(find.text('Call ER24'));
      await tester.pump();
      expect(launched, ['tel:084124']);
    });
  }

  testWidgets('timeout ends busy state and late result cannot replace retry',
      (tester) async {
    final pending = Completer<Position?>();
    var reads = 0;
    await tester.pumpWidget(MaterialApp(
      home: EmergencyPhonePage(readLocation: () {
        reads++;
        return reads == 1 ? pending.future : Future.value(fix(latitude: -27));
      }),
    ));
    await tester.tap(find.text('Get my location'));
    await tester.pump(const Duration(seconds: 16));
    expect(find.textContaining('Location unavailable.'), findsOneWidget);
    await tester.ensureVisible(find.text('Get my location'));
    await tester.tap(find.text('Get my location'));
    await tester.pumpAndSettle();
    pending.complete(fix());
    await tester.pumpAndSettle();
    expect(find.textContaining('Latitude: -27.000000'), findsOneWidget);
    expect(find.textContaining('Latitude: -26.000000'), findsNothing);
  });

  testWidgets('leaving during lookup is safe and notes are not retained',
      (tester) async {
    final pending = Completer<Position?>();
    await tester.pumpWidget(MaterialApp(
        home: EmergencyPhonePage(readLocation: () => pending.future)));
    await tester.tap(find.text('Get my location'));
    await tester.pump();
    expect(find.text('Finding location…'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, 'Synthetic landmark');
    await tester.enterText(find.byType(TextField).last, 'Synthetic notes');
    await tester.pumpWidget(const SizedBox());
    pending.complete(fix());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const MaterialApp(home: EmergencyPhonePage()));
    expect(find.text('Synthetic landmark'), findsNothing);
    expect(find.text('Synthetic notes'), findsNothing);
  });

  testWidgets('phone and manual details fit a narrow screen with large text',
      (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(2)),
        child: EmergencyPhonePage(),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Call ER24'));
    await tester.tap(find.text('Call ER24'));
    await tester.pump();
    expect(launched, ['tel:084124']);
    await tester.ensureVisible(find.byType(TextField).last);
    expect(tester.takeException(), isNull);
  });
}
