import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mycorvia/services/dispatch_call_controller.dart';
import 'support/ws4_http_fixture.dart';

void main() {
  late SupabaseClient client;
  setUpAll(() async {
    client = await fixtureClient((_) async => jsonResponse([]));
  });
  tearDownAll(() => client.dispose());
  Future<BuildContext> mount(WidgetTester tester) async {
    late BuildContext context;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (c) {
      context = c;
      return const SizedBox();
    })));
    return context;
  }

  testWidgets('repeated countdown starts do not accelerate the real controller',
      (tester) async {
    final controller = DispatchCallController(
        context: await mount(tester), onStateChanged: () {}, client: client);
    await controller.startCallWithCountdown();
    await tester.pump(const Duration(seconds: 1));
    await controller.startCallWithCountdown();
    await tester.pump(const Duration(seconds: 1));
    expect(controller.countdown, 1);
    await tester.pump(const Duration(seconds: 1));
    expect(controller.statusMessage, 'No incident');
    controller.cancelCountdown();
  });
  testWidgets('dispose during countdown prevents later notifications or calls',
      (tester) async {
    var notifications = 0;
    final controller = DispatchCallController(
        context: await mount(tester),
        onStateChanged: () {
          notifications++;
        },
        client: client);
    await controller.startCallWithCountdown();
    controller.dispose();
    final before = notifications;
    await controller.startCallWithCountdown();
    await tester.pump(const Duration(seconds: 10));
    expect(controller.isCountingDown, isFalse);
    expect(notifications, before);
    expect(controller.isCalling, isFalse);
  });
  testWidgets(
      'failed cancellation is not success and duplicate submit is blocked',
      (tester) async {
    final request = Completer<void>();
    var calls = 0;
    final controller = DispatchCallController(
        incidentId: 1,
        context: await mount(tester),
        onStateChanged: () {},
        client: client,
        cancelIncident: (id) {
          calls++;
          return request.future;
        });
    controller.startCancelTimer();
    final result = controller.cancelDispatch('1234');
    expect(await controller.cancelDispatch('1234'), isFalse);
    request.completeError(StateError('private server detail'));
    expect(await result, isFalse);
    expect(calls, 1);
    expect(controller.statusMessage, contains('could not be confirmed'));
    expect(controller.statusMessage, isNot(contains('private')));
    controller.dispose();
    await tester.pump();
  });
  testWidgets(
      'location failure returns unavailable rather than a fabricated fix',
      (tester) async {
    final controller = DispatchCallController(
        context: await mount(tester),
        onStateChanged: () {},
        client: client,
        lastPosition: () async => null,
        currentPosition: () async => throw StateError('denied'));
    expect(await controller.getLastKnownOrFetchLocation(), isNull);
  });
  testWidgets('unsupported last-known lookup still tries current GPS',
      (tester) async {
    final fix = Position(
        latitude: -26,
        longitude: 28,
        timestamp: DateTime.utc(2026),
        accuracy: 10,
        altitude: 0,
        altitudeAccuracy: 0,
        heading: 0,
        headingAccuracy: 0,
        speed: 0,
        speedAccuracy: 0);
    final controller = DispatchCallController(
        context: await mount(tester),
        onStateChanged: () {},
        client: client,
        lastPosition: () async => throw UnsupportedError('last-known'),
        currentPosition: () async => fix);
    expect(await controller.getLastKnownOrFetchLocation(), same(fix));
  });

  testWidgets('last-known position retains its actual timestamp and accuracy',
      (tester) async {
    final fix = Position(
        latitude: -26,
        longitude: 28,
        timestamp: DateTime.utc(2020),
        accuracy: 80,
        altitude: 0,
        altitudeAccuracy: 0,
        heading: 0,
        headingAccuracy: 0,
        speed: 0,
        speedAccuracy: 0);
    final controller = DispatchCallController(
        context: await mount(tester),
        onStateChanged: () {},
        client: client,
        lastPosition: () async => fix,
        currentPosition: () async => throw StateError('unexpected'));
    expect(await controller.getLastKnownOrFetchLocation(), same(fix));
  });
}
