import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mycorvia/pages/dispatch/dispatch_dashboard.dart';
import 'package:mycorvia/services/emergency_dispatch_service.dart';
import 'package:mycorvia/theme/app_theme.dart';
import 'support/ws4_access_fixture.dart';
import 'support/ws4_http_fixture.dart';

Map<String, dynamic> _intake({bool gps = false}) => {
      ...fixtureIncident(42),
      'latitude': gps ? 0.0 : null,
      'longitude': gps ? 0.0 : null,
      'address': 'Synthetic entrance A',
      'details': 'Synthetic emergency details',
      'location_source': gps ? 'gps' : 'manual',
      'location_accuracy': gps ? 12.5 : null,
      'location_captured_at': gps ? '2026-10-07T10:00:00+00:00' : null,
    };

Map<String, dynamic> _legacyClaim(
        {String? patient, int id = 42, bool gps = false}) =>
    {
      ...fixtureIncident(id),
      'user_id': patient ?? fixtureActor,
      'latitude': gps ? 0.0 : null,
      'longitude': gps ? 0.0 : null,
      'status': 'in_progress',
      'assigned_dispatcher_user_id': 'dispatcher-1',
      'accepted_at': '2026-10-07T10:01:00+00:00',
    };

void main() {
  for (final includeIntake in [false, true]) {
    test('queue requests intake projection only when enabled: $includeIntake',
        () async {
      final client = await fixtureClient((request) async {
        final fields = request.url.queryParameters['select']!
            .split(',')
            .map((s) => s.trim())
            .toSet();
        expect(fields, {
          'id',
          'user_id',
          'latitude',
          'longitude',
          'status',
          'created_at',
          'assigned_dispatcher_user_id',
          'accepted_at',
          if (includeIntake) ...{
            'address',
            'details',
            'location_source',
            'location_accuracy',
            'location_captured_at'
          },
        });
        return jsonResponse([includeIntake ? _intake() : fixtureIncident(42)]);
      });
      addTearDown(client.dispose);
      final row = (await EmergencyDispatchService(client: client)
              .loadIncomingEmergencies(includeIntakeDetails: includeIntake))
          .single;
      expect(row.hasIntakeDetails, includeIntake);
      expect(row.intakeNeedsReview, isFalse);
      expect(row.address, includeIntake ? 'Synthetic entrance A' : isNull);
    });
  }

  test('requested intake fields missing in response require review', () {
    final row = DispatchEmergency.fromMap(fixtureIncident(42),
        expectIntakeDetails: true);
    expect(row.needsReview, isTrue);
    expect(row.canBeClaimed, isFalse);
  });

  test('unsafe numeric page boundary cannot become a rounded cursor', () async {
    var requests = 0;
    final client = await fixtureClient((request) async {
      requests++;
      if (requests > 1) return jsonResponse([]);
      expect(request.url.queryParameters['limit'], '2');
      return jsonResponse([
        fixtureIncident(42),
        // A web decoder can round the real ID 9007199254740995 up to this.
        {...fixtureIncident(43), 'id': 9007199254740996.0},
      ]);
    });
    addTearDown(client.dispose);
    await expectLater(
        EmergencyDispatchService(client: client)
            .loadIncomingEmergencies(limit: 2),
        throwsFormatException);
    expect(requests, 1);
  });

  test('exact bigint strings remain exact across pagination boundaries',
      () async {
    var requests = 0;
    final client = await fixtureClient((request) async {
      requests++;
      if (requests == 1) {
        expect(request.url.queryParameters['id'], isNull);
        return jsonResponse([
          {...fixtureIncident(42), 'id': '9007199254740993'},
        ]);
      }
      if (requests == 2) {
        expect(request.url.queryParameters['id'], 'gt.9007199254740993');
        return jsonResponse([
          {...fixtureIncident(43), 'id': '9007199254740994'},
        ]);
      }
      expect(request.url.queryParameters['id'], 'gt.9007199254740994');
      return jsonResponse([]);
    });
    addTearDown(client.dispose);
    final rows = await EmergencyDispatchService(client: client)
        .loadIncomingEmergencies(limit: 1);
    expect(rows.map((row) => row.id), ['9007199254740993', '9007199254740994']);
    expect(requests, 3);
  });

  test('numeric incident IDs must remain inside the exact web integer range',
      () {
    final safe = DispatchEmergency.fromMap(
        {...fixtureIncident(42), 'id': 9007199254740991});
    expect(safe.id, '9007199254740991');
    expect(safe.canBeClaimed, isTrue);
    for (final id in [
      9007199254740992,
      9007199254740992.0,
      1.5,
      double.nan,
      double.infinity
    ]) {
      final unsafe =
          DispatchEmergency.fromMap({...fixtureIncident(42), 'id': id});
      expect(unsafe.hasValidIdentity, isFalse);
      expect(unsafe.canBeClaimed, isFalse);
      expect(unsafe.needsReview, isTrue);
    }
    final exact = DispatchEmergency.fromMap(
        {...fixtureIncident(42), 'id': '9223372036854775807'});
    expect(exact.id, '9223372036854775807');
    expect(exact.hasValidIdentity, isTrue);
  });

  test('valid GPS at zero coordinates retains actual capture metadata', () {
    final row = DispatchEmergency.fromMap(_intake(gps: true));
    expect(row.coordinateLabel, '0.00000, 0.00000');
    expect(row.locationAccuracy, 12.5);
    expect(row.locationCapturedAt, DateTime.utc(2026, 10, 7, 10));
    expect(row.canBeClaimed, isTrue);
  });

  test('legacy coordinates never acquire invented capture metadata', () {
    final row = DispatchEmergency.fromMap({
      ..._intake(),
      'latitude': -26.2,
      'longitude': 28,
      'location_source': 'legacy',
      'address': null,
      'details': null,
    });
    expect(row.locationSource, 'legacy');
    expect(row.locationCapturedAt, isNull);
    expect(row.locationAccuracy, isNull);
    expect(row.needsReview, isFalse);
  });

  for (final patch in <Map<String, dynamic>>[
    {'location_source': 'invented'},
    {'location_accuracy': double.nan},
    {'location_accuracy': -1},
    {'location_captured_at': '2026-02-31T10:00:00Z'},
    {'location_captured_at': '2026-10-07T25:00:00Z'},
    {'location_captured_at': '2026-10-07T10:00:00'},
    {'details': 42},
    {'address': 'a' * 301},
    {'location_source': 'unavailable'},
  ]) {
    test(
        'malformed intake is review-only: ${patch.keys.single} ${patch.values.single}',
        () {
      final row = DispatchEmergency.fromMap({..._intake(gps: true), ...patch});
      expect(row.intakeNeedsReview, isTrue);
      expect(row.canBeClaimed, isFalse);
      expect(row.coordinateLabel, 'Location unavailable');
    });
  }

  test(
      'legacy claim retains matching immutable intake without mutating old row',
      () {
    final before = DispatchEmergency.fromMap(_intake(gps: true));
    final claimed = DispatchEmergency.fromMap(_legacyClaim(gps: true))
        .withRetainedIntakeDetailsFrom(before);
    expect(claimed.isAccepted, isTrue);
    expect(claimed.details, before.details);
    expect(claimed.address, before.address);
    expect(claimed.locationCapturedAt, before.locationCapturedAt);
    expect(claimed.locationAccuracy, before.locationAccuracy);
    expect(claimed.hasIntakeDetails, isTrue);
    expect(before.isPending, isTrue);
  });

  for (final kind in ['incident', 'patient', 'coordinates']) {
    test('claim cannot attach saved intake to a different $kind', () {
      final before = DispatchEmergency.fromMap(_intake(gps: true));
      final response = _legacyClaim(
          gps: true,
          id: kind == 'incident' ? 43 : 42,
          patient: kind == 'patient' ? 'different-patient' : null);
      if (kind == 'coordinates') {
        response['latitude'] = 12;
      }
      expect(
          () => DispatchEmergency.fromMap(response)
              .withRetainedIntakeDetailsFrom(before),
          throwsFormatException);
    });
  }

  test('manual intake cannot acquire coordinates through a contradictory claim',
      () {
    final before = DispatchEmergency.fromMap(_intake());
    final response = {..._legacyClaim(), 'latitude': -26.2, 'longitude': 28.0};
    expect(
        () => DispatchEmergency.fromMap(response)
            .withRetainedIntakeDetailsFrom(before),
        throwsFormatException);
  });

  Future<void> mount(
    WidgetTester tester, {
    required Future<List<DispatchEmergency>> Function() loader,
    DispatchAccessLoader? access,
    IncomingEmergencyAccepter? accept,
  }) async {
    CorviaColors.setPalette(CorviaPalette.modern);
    CorviaColors.setBrightness(Brightness.light);
    tester.view.physicalSize = const Size(1700, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      theme: CorviaTheme.resolve(),
      home: EmergencyDispatchDashboard(
        accessLoader:
            access ?? () async => fixtureDispatchAccess(canReadIntake: true),
        incomingEmergencyLoader: loader,
        incomingEmergencyAccepter: accept,
      ),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> disposeDashboard(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 15));
  }

  testWidgets('selected incident keeps patient details after legacy claim',
      (tester) async {
    await mount(
      tester,
      loader: () async => [DispatchEmergency.fromMap(_intake())],
      accept: (_) async => DispatchEmergency.fromMap(_legacyClaim()),
    );
    expect(find.text('Synthetic entrance A'), findsOneWidget);
    expect(find.text('Synthetic emergency details'), findsOneWidget);
    expect(find.text('Patient-reported address; no GPS fix supplied.'),
        findsOneWidget);
    await tester.ensureVisible(find.text('Accept emergency'));
    await tester.tap(find.text('Accept emergency'));
    await tester.pumpAndSettle();
    expect(find.text('Synthetic emergency details'), findsOneWidget);
    expect(find.text('Synthetic entrance A'), findsOneWidget);
    expect(find.text('Accept emergency'), findsNothing);
    await disposeDashboard(tester);
  });

  testWidgets('GPS display says recorded, not live, with original metadata',
      (tester) async {
    await mount(tester,
        loader: () async => [DispatchEmergency.fromMap(_intake(gps: true))]);
    expect(find.textContaining('Recorded GPS fix (not live)'), findsOneWidget);
    expect(find.textContaining('Reported accuracy 12.5 m.'), findsOneWidget);
    await disposeDashboard(tester);
  });

  testWidgets(
      'intake capability loss clears old details before replacement read',
      (tester) async {
    var hasCapability = true;
    var reads = 0;
    final replacement = Completer<List<DispatchEmergency>>();
    await mount(
      tester,
      access: () async => fixtureDispatchAccess(canReadIntake: hasCapability),
      loader: () async {
        reads++;
        if (reads == 1) {
          return [DispatchEmergency.fromMap(_intake())];
        }
        return replacement.future;
      },
    );
    hasCapability = false;
    await tester.pump(const Duration(seconds: 15));
    await tester.pump();
    expect(reads, 2);
    expect(find.text('Synthetic emergency details'), findsNothing);
    replacement.complete([DispatchEmergency.fromMap(fixtureIncident(42))]);
    await tester.pumpAndSettle();
    expect(find.text('Patient-reported details'), findsNothing);
    await disposeDashboard(tester);
  });

  testWidgets('malformed pending intake never displays accepted success',
      (tester) async {
    await mount(tester,
        loader: () async => [
              DispatchEmergency.fromMap(
                  {..._intake(), 'location_source': 'gps'})
            ]);
    expect(find.text('Incident data needs review. Claim is unavailable.'),
        findsOneWidget);
    expect(find.text('Accepted by dispatch'), findsNothing);
    expect(find.text('Accept emergency'), findsNothing);
    await disposeDashboard(tester);
  });
}
