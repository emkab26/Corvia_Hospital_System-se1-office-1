import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mycorvia/controllers/patient_emergency_intake_controller.dart';
import 'package:mycorvia/pages/patient/emergency.dart';
import 'package:mycorvia/pages/patient/emergency_intake_page.dart';
import 'package:mycorvia/widgets/incident_history_panel.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/ws4_http_fixture.dart';
import 'support/ws4_patient_intake_fixture.dart';

class _OperationStore implements PatientEmergencyOperationStore {
  final values = <String, String>{};
  final writes = <String>[];
  @override
  Future<String?> read(String userId) async => values[userId];
  @override
  Future<void> write(String userId, String operationId) async {
    values[userId] = operationId;
    writes.add(operationId);
  }

  @override
  Future<void> remove(String userId) async {
    values.remove(userId);
  }
}

class _Gateway implements PatientEmergencyIntakeGateway {
  String? actor = fixtureActor;
  final operations = <String>[];
  final inputs = <PatientEmergencyIntakeRequest>[];
  final lookups = <String>[];
  final cancellations = <String>[];
  Future<PatientEmergencyIncident> Function(
      String, String, PatientEmergencyIntakeRequest)? onRequest;
  Future<PatientEmergencyIncident?> Function(String, String)? onLookup;
  Future<PatientEmergencyIncident> Function(String, String, String)? onCancel;

  @override
  Future<PatientEmergencyIncident> cancel(
      {required String userId,
      required String operationId,
      required String expectedVersion}) {
    cancellations.add('$operationId:$expectedVersion');
    return onCancel?.call(userId, operationId, expectedVersion) ??
        Future.value(intakeIncident(
            userId: userId,
            operation: operationId,
            status: 'cancelled',
            version: (BigInt.parse(expectedVersion) + BigInt.one).toString(),
            input: inputs.isEmpty ? null : inputs.last));
  }

  @override
  String? get currentUserId => actor;
  @override
  Future<PatientEmergencyIncident> request({
    required String userId,
    required String operationId,
    required PatientEmergencyIntakeRequest input,
  }) {
    operations.add(operationId);
    inputs.add(input);
    return onRequest?.call(userId, operationId, input) ??
        Future.value(intakeIncident(
            operation: operationId, userId: userId, input: input));
  }

  @override
  Future<PatientEmergencyIncident?> lookup({
    required String userId,
    required String operationId,
  }) {
    lookups.add(operationId);
    return onLookup?.call(userId, operationId) ?? Future.value(null);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/url_launcher');
  final address =
      find.widgetWithText(TextField, 'Address or landmark (optional)');
  final details = find.widgetWithText(TextField, 'What happened? (optional)');
  late _Gateway gateway;
  late _OperationStore store;
  late List<String> phoneLaunches;
  final backendRequests = <String>[];

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'http://127.0.0.1:54321',
      publishableKey: 'synthetic-test-key',
      httpClient: MockClient((request) async {
        backendRequests.add(request.url.path);
        return http.Response('{}', 500);
      }),
      authOptions: const FlutterAuthClientOptions(
        localStorage: EmptyLocalStorage(),
        autoRefreshToken: false,
      ),
    );
  });
  tearDownAll(() => Supabase.instance.dispose());

  setUp(() {
    gateway = _Gateway();
    store = _OperationStore();
    phoneLaunches = [];
    backendRequests.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'launch');
      final arguments = call.arguments as Map<dynamic, dynamic>;
      phoneLaunches.add(arguments['url'] as String);
      return true;
    });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  Future<void> showPage(WidgetTester tester,
      {Future<Position?> Function()? readLocation,
      Stream<String?>? userChanges,
      IncidentHistoryLoader? historyLoader,
      String Function()? operationIdFactory}) async {
    tester.view.physicalSize = const Size(1000, 1500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      home: EmergencyIntakePage(
        controller: PatientEmergencyIntakeController(
          gateway: gateway,
          operationStore: store,
          operationIdFactory: operationIdFactory ?? () => intakeOperation,
          userChanges: userChanges,
        ),
        readLocation: readLocation ?? () async => null,
        historyLoader: historyLoader ??
            (id) async => IncidentHistory.fromMap({
                  'incident_id': id,
                  'events': [
                    {
                      'version': '1',
                      'event_type': 'created',
                      'recorded_at': '2026-10-07T12:00:00Z',
                      'status': 'pending',
                      'previous_status': null
                    }
                  ],
                }, expectedIncidentId: id),
      ),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> tapText(WidgetTester tester, String text) async {
    final target = find.text(text);
    await tester.ensureVisible(target);
    await tester.tap(target);
    await tester.pump();
  }

  Future<void> closePage(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  }

  testWidgets(
      'enabled real entry routes to explicit intake and retains unauthenticated phone fallback',
      (tester) async {
    await tester.pumpWidget(
        const MaterialApp(home: EmergencyPage(dispatchEnabled: true)));
    await tester.pumpAndSettle();
    expect(find.byType(EmergencyIntakePage), findsOneWidget);
    expect(find.byType(LegacyDispatchEmergencyPage), findsNothing);
    expect(find.text('Emergency help'), findsOneWidget);
    expect(
        find.textContaining('Sign in again or call directly'), findsOneWidget);
    expect(find.text('Preparing emergency...'), findsNothing);
    expect(backendRequests, isEmpty);
    expect(phoneLaunches, isEmpty);
    await tapText(tester, 'Call ER24');
    expect(phoneLaunches, ['tel:084124']);
    expect(backendRequests, isEmpty);
    await closePage(tester);
  });

  testWidgets(
      'opening the page neither requests location nor creates an incident',
      (tester) async {
    var locationReads = 0;
    await showPage(tester, readLocation: () async {
      locationReads++;
      return null;
    });
    expect(find.text('Emergency help'), findsOneWidget);
    expect(find.text('084 124'), findsOneWidget);
    expect(locationReads, 0);
    expect(gateway.operations, isEmpty);
    expect(gateway.lookups, isEmpty);
    expect(store.writes, isEmpty);
    expect(phoneLaunches, isEmpty);
    await closePage(tester);
  });

  testWidgets(
      'explicit submission preserves a manual address and reported details',
      (tester) async {
    await showPage(tester);
    await tester.enterText(address, '  Synthetic north entrance  ');
    await tester.enterText(details, '  Synthetic incident details  ');
    await tapText(tester, 'Send request to Corvia');
    await tester.pumpAndSettle();
    expect(gateway.operations, [intakeOperation]);
    expect(store.writes, [intakeOperation]);
    expect(gateway.inputs.single.address, 'Synthetic north entrance');
    expect(gateway.inputs.single.details, 'Synthetic incident details');
    expect(gateway.inputs.single.locationSource, 'manual');
    expect(gateway.inputs.single.latitude, isNull);
    expect(gateway.inputs.single.longitude, isNull);
    expect(find.text('Corvia request #9007199254740993'), findsOneWidget);
    expect(find.text('Address: Synthetic north entrance'), findsOneWidget);
    expect(find.text('Details: Synthetic incident details'), findsOneWidget);
    expect(find.text('Waiting for a Corvia dispatcher'), findsOneWidget);
    expect(find.textContaining('does not confirm that ER24'), findsOneWidget);
    expect(phoneLaunches, isEmpty);
    await closePage(tester);
  });

  testWidgets(
      'no-location submission remains explicit and never invents coordinates',
      (tester) async {
    await showPage(tester);
    await tapText(tester, 'Send request to Corvia');
    await tester.pumpAndSettle();
    expect(gateway.inputs.single.locationSource, 'unavailable');
    expect(gateway.inputs.single.latitude, isNull);
    expect(gateway.inputs.single.longitude, isNull);
    expect(
        find.text(
            'No location was available. Tell the operator where you are.'),
        findsOneWidget);
    expect(phoneLaunches, isEmpty);
    await closePage(tester);
  });

  testWidgets(
      'combining-character input over the backend limit is rejected without a write',
      (tester) async {
    await showPage(tester);
    // 200 visible graphemes fit the field but contain 400 Unicode code points.
    final overLimit = List.filled(200, 'a\u0301').join();
    await tester.enterText(address, overLimit);
    expect(tester.widget<TextField>(address).controller!.text, overLimit);
    await tapText(tester, 'Send request to Corvia');
    await tester.pumpAndSettle();
    expect(
        find.text(const PatientEmergencyIntakeException(
                PatientEmergencyFailureKind.invalidInput)
            .message),
        findsOneWidget);
    expect(gateway.operations, isEmpty);
    expect(store.writes, isEmpty);
    expect(tester.takeException(), isNull);
    await tester.enterText(address, 'Corrected synthetic entrance');
    await tapText(tester, 'Send request to Corvia');
    await tester.pumpAndSettle();
    expect(gateway.inputs.single.address, 'Corrected synthetic entrance');
    await closePage(tester);
  });

  testWidgets('double taps freeze the input and send only one request',
      (tester) async {
    final pending = Completer<PatientEmergencyIncident>();
    gateway.onRequest = (_, __, ___) => pending.future;
    await showPage(tester);
    await tester.enterText(address, 'Synthetic original location');
    await tester.tap(find.text('Send request to Corvia'));
    await tester.tap(find.text('Send request to Corvia'));
    await tester.pump();
    expect(gateway.operations, [intakeOperation]);
    expect(tester.widget<TextField>(address).enabled, isFalse);
    expect(tester.widget<TextField>(details).enabled, isFalse);
    expect(
        tester
            .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Send request to Corvia'))
            .onPressed,
        isNull);
    expect(find.text('Sending your request...'), findsOneWidget);
    pending.complete(intakeIncident(input: gateway.inputs.single));
    await tester.pumpAndSettle();
    expect(find.text('Waiting for a Corvia dispatcher'), findsOneWidget);
    await closePage(tester);
  });

  testWidgets('saved request is restored by lookup without another submission',
      (tester) async {
    store.values[fixtureActor] = nextIntakeOperation;
    gateway.onLookup = (user, operation) async => intakeIncident(
          userId: user,
          operation: operation,
          status: 'in_progress',
          input: PatientEmergencyIntakeRequest(
              address: 'Saved synthetic entrance'),
        );
    await showPage(tester);
    expect(gateway.lookups, [nextIntakeOperation]);
    expect(gateway.operations, isEmpty);
    expect(store.writes, isEmpty);
    expect(find.text('Accepted by Corvia dispatch'), findsOneWidget);
    expect(find.text('Address: Saved synthetic entrance'), findsOneWidget);
    expect(find.text('Send request to Corvia'), findsNothing);
    expect(find.text('Start a new request'), findsNothing);
    expect(phoneLaunches, isEmpty);
    await closePage(tester);
  });

  testWidgets(
      'lost response offers manual calling and lookup without automatic dialling',
      (tester) async {
    gateway.onRequest = (_, __, ___) async =>
        throw const PatientEmergencyIntakeException(
            PatientEmergencyFailureKind.unknown);
    await showPage(tester);
    await tester.enterText(details, 'Synthetic retained details');
    await tapText(tester, 'Send request to Corvia');
    await tester.pumpAndSettle();
    expect(find.text('Request confirmation unavailable'), findsOneWidget);
    expect(find.textContaining('may have reached Corvia'), findsOneWidget);
    expect(gateway.operations, [intakeOperation]);
    expect(gateway.lookups, isEmpty);
    expect(phoneLaunches, isEmpty);
    final dialogCall = find.descendant(
        of: find.byType(AlertDialog), matching: find.text('Call ER24'));
    await tester.ensureVisible(dialogCall);
    await tester.tap(dialogCall);
    await tester.pumpAndSettle();
    expect(phoneLaunches, ['tel:084124']);
    expect(gateway.operations, hasLength(1));
    await tapText(tester, 'Return to request');
    await tester.pumpAndSettle();
    gateway.onLookup = (_, operation) async =>
        intakeIncident(operation: operation, input: gateway.inputs.single);
    await tapText(tester, 'Check request status');
    await tester.pumpAndSettle();
    expect(gateway.lookups, [intakeOperation]);
    expect(gateway.operations, [intakeOperation]);
    expect(find.text('Details: Synthetic retained details'), findsOneWidget);
    expect(find.text('Waiting for a Corvia dispatcher'), findsOneWidget);
    await closePage(tester);
  });

  testWidgets(
      'retry action reconciles before resending the same frozen request',
      (tester) async {
    gateway.onRequest = (_, __, ___) async =>
        throw const PatientEmergencyIntakeException(
            PatientEmergencyFailureKind.unknown);
    await showPage(tester);
    await tester.enterText(address, 'Synthetic original entrance');
    await tapText(tester, 'Send request to Corvia');
    await tester.pumpAndSettle();
    await tapText(tester, 'Return to request');
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(address).enabled, isFalse);
    gateway.onRequest = (user, operation, input) async {
      expect(gateway.lookups, [intakeOperation]);
      return intakeIncident(userId: user, operation: operation, input: input);
    };
    await tapText(tester, 'Retry same request');
    await tester.pumpAndSettle();
    expect(gateway.operations, [intakeOperation, intakeOperation]);
    expect(gateway.inputs[1], gateway.inputs[0]);
    expect(store.writes, [intakeOperation]);
    expect(phoneLaunches, isEmpty);
    await closePage(tester);
  });

  testWidgets(
      'confirmed request with failed refresh offers status recovery without another submission',
      (tester) async {
    store.values[fixtureActor] = intakeOperation;
    gateway.onLookup = (_, operation) async => intakeIncident(
        operation: operation,
        status: 'in_progress',
        input: PatientEmergencyIntakeRequest(
            address: 'Confirmed synthetic entrance'));
    await showPage(tester);
    expect(find.text('Accepted by Corvia dispatch'), findsOneWidget);
    gateway.onLookup = (_, __) async =>
        throw const PatientEmergencyIntakeException(
            PatientEmergencyFailureKind.unknown);
    await tapText(tester, 'Check request status');
    await tester.pumpAndSettle();
    expect(find.text('Request confirmation unavailable'), findsOneWidget);
    await tapText(tester, 'Return to request');
    await tester.pumpAndSettle();
    expect(find.text('Address: Confirmed synthetic entrance'), findsOneWidget);
    expect(find.textContaining('Last confirmed information.'), findsOneWidget);
    expect(find.text('Check request status'), findsOneWidget);
    expect(find.text('Retry same request'), findsNothing);
    expect(find.text('Send request to Corvia'), findsNothing);
    expect(find.text('Start a new request'), findsNothing);
    expect(gateway.operations, isEmpty);
    expect(phoneLaunches, isEmpty);
    gateway.onLookup = (_, operation) async => intakeIncident(
        operation: operation,
        status: 'resolved',
        version: '2',
        input: PatientEmergencyIntakeRequest(
            address: 'Confirmed synthetic entrance'));
    await tapText(tester, 'Check request status');
    await tester.pumpAndSettle();
    expect(find.text('Request closed'), findsOneWidget);
    expect(find.textContaining('Last confirmed information.'), findsNothing);
    expect(gateway.operations, isEmpty);
    await closePage(tester);
  });

  testWidgets(
      'failure prompt is shown once per operation and resets for an explicit new request',
      (tester) async {
    final operationIds = [intakeOperation, nextIntakeOperation].iterator;
    gateway.onRequest = (_, __, ___) async =>
        throw const PatientEmergencyIntakeException(
            PatientEmergencyFailureKind.unknown);
    await showPage(tester, operationIdFactory: () {
      expect(operationIds.moveNext(), isTrue);
      return operationIds.current;
    });
    await tapText(tester, 'Send request to Corvia');
    await tester.pumpAndSettle();
    expect(find.text('Request confirmation unavailable'), findsOneWidget);
    await tapText(tester, 'Return to request');
    await tester.pumpAndSettle();

    gateway.onLookup = (_, __) async =>
        throw const PatientEmergencyIntakeException(
            PatientEmergencyFailureKind.unknown);
    await tapText(tester, 'Check request status');
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(gateway.operations, [intakeOperation]);

    gateway.onLookup = (_, operation) async => intakeIncident(
        operation: operation, status: 'resolved', input: gateway.inputs.first);
    await tapText(tester, 'Check request status');
    await tester.pumpAndSettle();
    expect(find.text('Request closed'), findsOneWidget);
    await tapText(tester, 'Start a new request');
    await tester.pumpAndSettle();
    expect(gateway.operations, [intakeOperation]);
    expect(find.byType(AlertDialog), findsNothing);

    await tapText(tester, 'Send request to Corvia');
    await tester.pumpAndSettle();
    expect(gateway.operations, [intakeOperation, nextIntakeOperation]);
    expect(store.writes, [intakeOperation, nextIntakeOperation]);
    expect(find.text('Request confirmation unavailable'), findsOneWidget);
    expect(phoneLaunches, isEmpty);
    await tapText(tester, 'Return to request');
    await tester.pumpAndSettle();
    await closePage(tester);
  });

  testWidgets(
      'queued failure dialog is suppressed when the account changes before the next frame',
      (tester) async {
    final changes = StreamController<String?>.broadcast(sync: true);
    gateway.onRequest = (_, __, ___) async =>
        throw const PatientEmergencyIntakeException(
            PatientEmergencyFailureKind.unknown);
    await showPage(tester, userChanges: changes.stream);
    final state = tester
        .widget<EmergencyIntakePage>(find.byType(EmergencyIntakePage))
        .controller!;
    var switched = false;
    // This listener runs after the page queues its post-frame failure dialog.
    state.addListener(() {
      if (!switched && state.phase == PatientEmergencyIntakePhase.unknown) {
        switched = true;
        gateway.actor = nextIntakeOperation;
        changes.add(nextIntakeOperation);
      }
    });
    await tester.enterText(details, 'Previous synthetic session detail');
    await tapText(tester, 'Send request to Corvia');
    await tester.pumpAndSettle();
    expect(switched, isTrue);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('Request confirmation unavailable'), findsNothing);
    expect(tester.widget<TextField>(details).controller!.text, isEmpty);
    expect(state.activeUserId, nextIntakeOperation);
    expect(state.phase, PatientEmergencyIntakePhase.ready);
    expect(gateway.operations, [intakeOperation]);
    expect(phoneLaunches, isEmpty);
    await closePage(tester);
    await changes.close();
  });

  for (final throwsError in [false, true]) {
    testWidgets(
        'location ${throwsError ? 'failure' : 'denial'} leaves calling and manual intake usable',
        (tester) async {
      var locationReads = 0;
      await showPage(tester, readLocation: () async {
        locationReads++;
        if (throwsError) throw StateError('private location diagnostic');
        return null;
      });
      await tapText(tester, 'Add device location');
      await tester.pumpAndSettle();
      expect(locationReads, 1);
      expect(
          find.text(
              'Location unavailable. Enter a landmark or tell the operator.'),
          findsOneWidget);
      expect(find.textContaining('private location diagnostic'), findsNothing);
      expect(gateway.operations, isEmpty);
      expect(tester.widget<TextField>(address).enabled, isTrue);
      await tapText(tester, 'Call ER24');
      expect(phoneLaunches, ['tel:084124']);
      expect(gateway.operations, isEmpty);
      await tester.enterText(address, 'Synthetic manual fallback');
      await tapText(tester, 'Send request to Corvia');
      await tester.pumpAndSettle();
      expect(gateway.inputs.single.locationSource, 'manual');
      expect(gateway.inputs.single.latitude, isNull);
      await closePage(tester);
    });
  }

  testWidgets('a location timeout does not block direct calling or submission',
      (tester) async {
    final pendingLocation = Completer<Position?>();
    await showPage(tester, readLocation: () => pendingLocation.future);
    await tapText(tester, 'Add device location');
    expect(find.text('Finding location...'), findsOneWidget);
    await tapText(tester, 'Call ER24');
    expect(phoneLaunches, ['tel:084124']);
    await tester.pump(const Duration(seconds: 16));
    await tester.pump();
    expect(
        find.text(
            'Location unavailable. Enter a landmark or tell the operator.'),
        findsOneWidget);
    expect(
        tester
            .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Send request to Corvia'))
            .onPressed,
        isNotNull);
    expect(gateway.operations, isEmpty);
    pendingLocation.complete(null);
    await closePage(tester);
  });

  testWidgets(
      'GPS is acquired only on request and submitted as a captured snapshot',
      (tester) async {
    final captured = DateTime.now().toUtc();
    var locationReads = 0;
    await showPage(tester, readLocation: () async {
      locationReads++;
      return Position(
        longitude: 28.0,
        latitude: -26.2,
        timestamp: captured,
        accuracy: 12.5,
        altitude: 0,
        altitudeAccuracy: 0,
        heading: 0,
        headingAccuracy: 0,
        speed: 0,
        speedAccuracy: 0,
      );
    });
    expect(locationReads, 0);
    await tapText(tester, 'Add device location');
    await tester.pumpAndSettle();
    expect(locationReads, 1);
    expect(gateway.operations, isEmpty);
    expect(
        find.textContaining('Location snapshot: -26.2, 28.0'), findsOneWidget);
    await tapText(tester, 'Send request to Corvia');
    await tester.pumpAndSettle();
    final input = gateway.inputs.single;
    expect(input.locationSource, 'gps');
    expect(input.latitude, -26.2);
    expect(input.longitude, 28.0);
    expect(input.accuracy, 12.5);
    expect(input.capturedAt, captured);
    expect(find.textContaining('Accuracy: 12.5 m;'), findsOneWidget);
    expect(phoneLaunches, isEmpty);
    await closePage(tester);
  });

  testWidgets('narrow-screen intake scrolls to submit without layout errors',
      (tester) async {
    await showPage(tester);
    tester.view.physicalSize = const Size(320, 640);
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(address);
    await tester.enterText(address, 'Synthetic narrow-screen entrance');
    await tapText(tester, 'Send request to Corvia');
    await tester.pumpAndSettle();
    expect(gateway.inputs.single.address, 'Synthetic narrow-screen entrance');
    expect(tester.takeException(), isNull);
    await closePage(tester);
  });

  testWidgets(
      'switching accounts clears typed details before the new session can submit',
      (tester) async {
    final changes = StreamController<String?>.broadcast(sync: true);
    await showPage(tester, userChanges: changes.stream);
    await tester.enterText(address, 'Previous synthetic address');
    await tester.enterText(details, 'Previous synthetic private details');
    gateway.actor = nextIntakeOperation;
    changes.add(nextIntakeOperation);
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(address).controller!.text, isEmpty);
    expect(tester.widget<TextField>(details).controller!.text, isEmpty);
    expect(find.text('Previous synthetic private details'), findsNothing);
    expect(gateway.operations, isEmpty);
    await tapText(tester, 'Send request to Corvia');
    await tester.pumpAndSettle();
    expect(gateway.inputs.single.address, isNull);
    expect(gateway.inputs.single.details, isNull);
    expect(store.values.keys, [nextIntakeOperation]);
    await closePage(tester);
    await changes.close();
  });

  testWidgets(
      'terminal request requires explicit new-request action and another submit',
      (tester) async {
    store.values[fixtureActor] = nextIntakeOperation;
    gateway.onLookup = (_, operation) async => intakeIncident(
        operation: operation,
        status: 'resolved',
        input:
            PatientEmergencyIntakeRequest(details: 'Closed synthetic details'));
    await showPage(tester);
    expect(find.text('Request closed'), findsOneWidget);
    expect(gateway.operations, isEmpty);
    expect(store.values[fixtureActor], nextIntakeOperation);
    await tapText(tester, 'Start a new request');
    await tester.pumpAndSettle();
    expect(store.values[fixtureActor], isNull);
    expect(gateway.operations, isEmpty);
    expect(tester.widget<TextField>(details).controller!.text, isEmpty);
    await tapText(tester, 'Send request to Corvia');
    await tester.pumpAndSettle();
    expect(gateway.operations, [intakeOperation]);
    expect(store.writes, [intakeOperation]);
    expect(gateway.inputs.single.details, isNull);
    await closePage(tester);
  });

  testWidgets('a pending location result is ignored after leaving the page',
      (tester) async {
    final pendingLocation = Completer<Position?>();
    await showPage(tester, readLocation: () => pendingLocation.future);
    await tapText(tester, 'Add device location');
    await closePage(tester);
    pendingLocation.complete(null);
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(gateway.operations, isEmpty);
    expect(phoneLaunches, isEmpty);
  });

  testWidgets(
      'cancellation requires confirmation and keeps phone arrangements separate',
      (tester) async {
    await showPage(tester);
    await tapText(tester, 'Send request to Corvia');
    await tester.pumpAndSettle();
    await tapText(tester, 'Cancel request');
    await tester.pumpAndSettle();
    expect(find.textContaining('does not cancel a phone call'), findsOneWidget);
    expect(gateway.cancellations, isEmpty);
    await tapText(tester, 'Keep request');
    await tester.pumpAndSettle();
    expect(gateway.cancellations, isEmpty);
    expect(find.text('Waiting for a Corvia dispatcher'), findsOneWidget);
    await tapText(tester, 'Cancel request');
    await tester.pumpAndSettle();
    await tapText(tester, 'Confirm cancellation');
    await tester.pumpAndSettle();
    expect(gateway.cancellations, ['$intakeOperation:1']);
    expect(find.text('Request cancelled'), findsOneWidget);
    expect(find.text('Cancel request'), findsNothing);
    expect(find.text('Start a new request'), findsOneWidget);
    expect(phoneLaunches, isEmpty);
    await closePage(tester);
  });

  testWidgets(
      'a competing claim is reconciled instead of reporting cancellation',
      (tester) async {
    gateway.onCancel = (_, __, ___) async =>
        throw const PatientEmergencyIntakeException(
            PatientEmergencyFailureKind.conflict);
    gateway.onLookup = (user, op) async => intakeIncident(
        userId: user, operation: op, status: 'in_progress', version: '2');
    await showPage(tester);
    await tapText(tester, 'Send request to Corvia');
    await tester.pumpAndSettle();
    await tapText(tester, 'Cancel request');
    await tester.pumpAndSettle();
    await tapText(tester, 'Confirm cancellation');
    await tester.pumpAndSettle();
    expect(gateway.cancellations, ['$intakeOperation:1']);
    expect(gateway.lookups, [intakeOperation]);
    expect(find.text('Request cancelled'), findsNothing);
    expect(find.text('Accepted by Corvia dispatch'), findsOneWidget);
    expect(find.text('Cancel request'), findsNothing);
    expect(phoneLaunches, isEmpty);
    await closePage(tester);
  });

  testWidgets(
      'unconfirmed cancellation requires status recovery without claiming success',
      (tester) async {
    gateway.onCancel = (_, __, ___) async =>
        throw const PatientEmergencyIntakeException(
            PatientEmergencyFailureKind.unknown);
    await showPage(tester);
    await tapText(tester, 'Send request to Corvia');
    await tester.pumpAndSettle();
    await tapText(tester, 'Cancel request');
    await tester.pumpAndSettle();
    await tapText(tester, 'Confirm cancellation');
    await tester.pumpAndSettle();
    expect(find.textContaining('Cancellation could not be confirmed'),
        findsOneWidget);
    expect(find.text('Request cancelled'), findsNothing);
    expect(find.text('Cancel request'), findsNothing);
    expect(find.text('Start a new request'), findsNothing);
    expect(find.text('Request confirmation unavailable'), findsNothing);
    expect(find.text('Call ER24'), findsOneWidget);
    gateway.onLookup = (user, op) async => intakeIncident(
        userId: user, operation: op, status: 'cancelled', version: '2');
    await tapText(tester, 'Check request status');
    await tester.pumpAndSettle();
    expect(gateway.cancellations, hasLength(1));
    expect(find.text('Request cancelled'), findsOneWidget);
    expect(phoneLaunches, isEmpty);
    await closePage(tester);
  });

  testWidgets(
      'account change during confirmation cannot cancel the next account request',
      (tester) async {
    final changes = StreamController<String?>.broadcast(sync: true);
    await showPage(tester, userChanges: changes.stream);
    await tapText(tester, 'Send request to Corvia');
    await tester.pumpAndSettle();
    await tapText(tester, 'Cancel request');
    await tester.pumpAndSettle();
    gateway.actor = nextIntakeOperation;
    changes.add(nextIntakeOperation);
    await tester.pumpAndSettle();
    await tapText(tester, 'Confirm cancellation');
    await tester.pumpAndSettle();
    expect(gateway.cancellations, isEmpty);
    expect(find.textContaining('The request changed.'), findsOneWidget);
    await closePage(tester);
    await changes.close();
  });
}
