import 'support/ws4_access_fixture.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mycorvia/pages/dispatch/dispatch_dashboard.dart';
import 'package:mycorvia/services/emergency_dispatch_service.dart';
import 'package:mycorvia/theme/app_theme.dart';

Future<List<DispatchEmergency>> _loadNoEmergencies() async {
  return const [];
}

void main() {
  setUp(() {
    CorviaColors.setPalette(
      CorviaPalette.modern,
    );
    CorviaColors.setBrightness(
      Brightness.light,
    );
  });

  test('maps dispatcher role designations to the correct access level', () {
    expect(
      dispatchAccessLevelForRole('Dispatcher'),
      DispatchAccessLevel.dispatcher,
    );
    expect(
      dispatchAccessLevelForRole('dispatch'),
      DispatchAccessLevel.dispatcher,
    );
    expect(
      dispatchAccessLevelForRole('Dispatch Supervisor'),
      DispatchAccessLevel.supervisor,
    );
    expect(
      dispatchAccessLevelForRole('dispatchsupervisor'),
      DispatchAccessLevel.supervisor,
    );
    expect(
      dispatchAccessLevelForRole('patient'),
      isNull,
    );
  });

  test('parses an incoming incident row safely', () {
    final emergency = DispatchEmergency.fromMap({
      'id': 17,
      'user_id': 'patient-17',
      'status': 'In Progress',
      'latitude': '-26.2041',
      'longitude': 28.0473,
      'created_at': '2026-08-31T13:30:00Z',
      'accepted_at': '2026-08-31T13:31:00Z',
      'assigned_dispatcher_user_id': 'dispatcher-17',
    });

    expect(emergency.id, '17');
    expect(emergency.userId, 'patient-17');
    expect(emergency.status, 'in_progress');
    expect(emergency.latitude, -26.2041);
    expect(emergency.longitude, 28.0473);
    expect(emergency.createdAt, isNotNull);
    expect(emergency.acceptedAt, isNotNull);
    expect(emergency.assignedDispatcherUserId, 'dispatcher-17');
    expect(emergency.isAccepted, isTrue);
  });

  testWidgets('accepts a pending emergency and starts dispatch', (
    tester,
  ) async {
    String? acceptedIncidentId;
    final createdAt = DateTime(2026, 8, 31, 13, 30);
    final acceptedAt = DateTime(2026, 8, 31, 13, 31);

    tester.view.physicalSize = const Size(1500, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: CorviaTheme.resolve(),
        home: EmergencyDispatchDashboard(
          accessLoader: () async => fixtureDispatchAccess(),
          incomingEmergencyLoader: () async => [
            DispatchEmergency(
              id: '42',
              userId: 'patient-42',
              status: 'pending',
              createdAt: createdAt,
              latitude: -26.2041,
              longitude: 28.0473,
            ),
          ],
          incomingEmergencyAccepter: (incidentId) async {
            acceptedIncidentId = incidentId;
            return DispatchEmergency(
              id: incidentId,
              userId: 'patient-42',
              status: 'in_progress',
              createdAt: createdAt,
              acceptedAt: acceptedAt,
              assignedDispatcherUserId: 'dispatcher-1',
              latitude: -26.2041,
              longitude: 28.0473,
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Accept emergency'), findsOneWidget);
    await tester.tap(find.text('Accept emergency'));
    await tester.pumpAndSettle();

    expect(acceptedIncidentId, '42');
    expect(find.text('In Progress'), findsWidgets);
    expect(find.text('Accepted at 13:31'), findsOneWidget);
    expect(find.text('Accept emergency'), findsNothing);
  });

  testWidgets('reports when another dispatcher already accepted the emergency',
      (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1500, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: CorviaTheme.resolve(),
        home: EmergencyDispatchDashboard(
          accessLoader: () async => fixtureDispatchAccess(),
          incomingEmergencyLoader: () async => [
            DispatchEmergency(
              id: '43',
              userId: 'patient-43',
              status: 'pending',
              createdAt: DateTime(2026, 8, 31, 13, 32),
            ),
          ],
          incomingEmergencyAccepter: (_) async {
            throw Exception('This emergency has already been accepted.');
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Accept emergency'));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Another dispatcher has already accepted this emergency. '
        'The queue has been refreshed.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('renders the dispatcher live operations dashboard',
      (tester) async {
    tester.view.physicalSize = const Size(
      1500,
      1000,
    );
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: CorviaTheme.resolve(),
        home: EmergencyDispatchDashboard(
          accessLoader: () async => fixtureDispatchAccess(),
          incomingEmergencyLoader: _loadNoEmergencies,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Welcome, Dispatcher'),
      findsOneWidget,
    );
    expect(
      find.text('Live Operations'),
      findsOneWidget,
    );
    expect(
      find.text('Incident queue'),
      findsOneWidget,
    );
    expect(
      find.text('Incident location'),
      findsOneWidget,
    );
    expect(
      find.text('Selected incident'),
      findsOneWidget,
    );
    expect(
      find.text('There are no current incidents in this queue.'),
      findsOneWidget,
    );
  });

  testWidgets('profile supervisor hint cannot grant server supervisor access',
      (tester) async {
    tester.view.physicalSize = const Size(1500, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      theme: CorviaTheme.resolve(),
      home: EmergencyDispatchDashboard(
        accessLevel: DispatchAccessLevel.supervisor,
        accessLoader: () async => fixtureDispatchAccess(),
        incomingEmergencyLoader: _loadNoEmergencies,
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Welcome, Dispatcher'), findsOneWidget);
    expect(find.text('Supervisor access'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('shows supervisor-specific access state', (tester) async {
    tester.view.physicalSize = const Size(
      1500,
      1000,
    );
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: CorviaTheme.resolve(),
        home: EmergencyDispatchDashboard(
          accessLoader: () async => fixtureDispatchAccess(supervisor: true),
          accessLevel: DispatchAccessLevel.supervisor,
          incomingEmergencyLoader: _loadNoEmergencies,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Welcome, Dispatch Supervisor'),
      findsOneWidget,
    );
    expect(
      find.text('Supervisor access'),
      findsOneWidget,
    );
    expect(
      find.text('Incident queue'),
      findsOneWidget,
    );
  });

  testWidgets('requires confirmation before signing out', (tester) async {
    var didSignOut = false;

    tester.view.physicalSize = const Size(
      1500,
      1000,
    );
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: CorviaTheme.resolve(),
        home: EmergencyDispatchDashboard(
          accessLoader: () async => fixtureDispatchAccess(),
          incomingEmergencyLoader: _loadNoEmergencies,
          onSignOut: () async {
            didSignOut = true;
          },
        ),
      ),
    );

    await tester.tap(
      find.text('Sign out'),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Sign out?'),
      findsOneWidget,
    );
    expect(
      didSignOut,
      isFalse,
    );

    await tester.tap(
      find.widgetWithText(
        FilledButton,
        'Sign out',
      ),
    );
    await tester.pumpAndSettle();

    expect(
      didSignOut,
      isTrue,
    );
  });

  testWidgets('displays incoming emergencies from the backend loader', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(
      1500,
      1000,
    );
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: CorviaTheme.resolve(),
        home: EmergencyDispatchDashboard(
          accessLoader: () async => fixtureDispatchAccess(),
          incomingEmergencyLoader: () async {
            return [
              DispatchEmergency(
                id: '42',
                userId: 'patient-user-123456',
                status: 'pending',
                createdAt: DateTime.now(),
                latitude: -26.20410,
                longitude: 28.04730,
              ),
            ];
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('1 pending'),
      findsOneWidget,
    );
    expect(
      find.text('Emergency #42'),
      findsOneWidget,
    );
    expect(
      find.text('-26.20410, 28.04730'),
      findsNWidgets(3),
    );
    expect(
      find.textContaining('Patient account patient-user'),
      findsOneWidget,
    );
  });

  testWidgets(
      'keeps pending arrivals visible and sounds only for newly seen IDs',
      (tester) async {
    tester.view.physicalSize = const Size(1500, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    DispatchEmergency pending(String id) => DispatchEmergency(
          id: id,
          userId: 'patient-$id',
          status: 'pending',
          createdAt: DateTime(2026, 10, 8),
        );
    var rows = [
      pending('41'),
      DispatchEmergency(
        id: '40',
        userId: 'patient-40',
        status: 'in_progress',
        assignedDispatcherUserId: 'dispatcher-1',
        createdAt: DateTime(2026, 10, 8),
      ),
    ];
    var sounds = 0;
    await tester.pumpWidget(MaterialApp(
      theme: CorviaTheme.resolve(),
      home: EmergencyDispatchDashboard(
        accessLoader: () async => fixtureDispatchAccess(),
        incomingEmergencyLoader: () async => rows,
        playIncomingAlert: () async => sounds++,
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('1 pending'), findsOneWidget);
    expect(find.textContaining('1 pending incident'), findsOneWidget);
    expect(find.textContaining('1 newly received'), findsOneWidget);
    expect(sounds, 0);

    await tester.tap(find.byTooltip('Enable queue sound'));
    await tester.pump();
    rows = [pending('41'), pending('42'), rows.last];
    await tester.tap(find.byTooltip('Refresh incoming emergencies'));
    await tester.pumpAndSettle();
    expect(find.text('2 pending'), findsOneWidget);
    expect(find.textContaining('2 pending incidents'), findsOneWidget);
    expect(find.textContaining('2 newly received'), findsOneWidget);
    expect(sounds, 1);

    await tester.tap(find.byTooltip('Mark alerts seen'));
    await tester.pump();
    expect(find.textContaining('newly received'), findsNothing);
    expect(find.textContaining('2 pending incidents'), findsOneWidget);
    await tester.tap(find.byTooltip('Refresh incoming emergencies'));
    await tester.pumpAndSettle();
    expect(sounds, 1);
  });

  testWidgets('reports an unavailable alert sound without hiding the queue',
      (tester) async {
    tester.view.physicalSize = const Size(1500, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var rows = <DispatchEmergency>[];
    await tester.pumpWidget(MaterialApp(
      theme: CorviaTheme.resolve(),
      home: EmergencyDispatchDashboard(
        accessLoader: () async => fixtureDispatchAccess(),
        incomingEmergencyLoader: () async => rows,
        playIncomingAlert: () async => throw StateError('audio denied'),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Enable queue sound'));
    await tester.pump();
    rows = [
      DispatchEmergency(
        id: '43',
        userId: 'patient-43',
        status: 'pending',
        createdAt: DateTime(2026, 10, 8),
      ),
    ];
    await tester.tap(find.byTooltip('Refresh incoming emergencies'));
    await tester.pumpAndSettle();
    expect(find.text('Sound unavailable. Watch the visible emergency queue.'),
        findsOneWidget);
    expect(find.textContaining('1 pending incident'), findsOneWidget);
    expect(find.byTooltip('Enable queue sound'), findsOneWidget);
  });

  testWidgets('uses the compact command-centre shell on a phone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(
      390,
      844,
    );
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: CorviaTheme.resolve(),
        home: EmergencyDispatchDashboard(
          accessLoader: () async => fixtureDispatchAccess(),
          incomingEmergencyLoader: _loadNoEmergencies,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byTooltip('Open navigation menu'),
      findsOneWidget,
    );
    expect(
      find.byTooltip('Sign out'),
      findsOneWidget,
    );
    expect(
      find.text('Welcome, Dispatcher'),
      findsOneWidget,
    );

    await tester.tap(
      find.byTooltip('Open navigation menu'),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Emergency Dispatch\nCommand Centre'),
      findsOneWidget,
    );
    expect(
      find.text('Incoming Calls'),
      findsOneWidget,
    );
  });
}
