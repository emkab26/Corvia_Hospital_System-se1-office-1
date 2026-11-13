import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mycorvia/models/dispatch/dispatch_emergency.dart';
import 'package:mycorvia/models/dispatch/incident_history.dart';
import 'package:mycorvia/services/incident_workspace_service.dart';
import 'package:mycorvia/config/env.dart';
import 'package:mycorvia/widgets/incident_workspace_panel.dart';
import 'package:mycorvia/widgets/incident_location_panel.dart';
import 'package:mycorvia/widgets/corvia_startup.dart';
import 'package:mycorvia/pages/dispatch/dispatch_dashboard.dart';
import 'package:mycorvia/theme/app_theme.dart';
import 'support/ws4_http_fixture.dart';
import 'support/ws4_access_fixture.dart';

Map<String, dynamic> snapshot({bool patient = false}) => {
      'incident_id': '42',
      'version': '2',
      'status': 'in_progress',
      'can_manage': !patient,
      'is_patient': patient,
      'priority': 'untriaged',
      'provider_state': 'not_requested',
      'provider_demo': false,
      'demo_available': false,
      'cancellation_requested': false,
      'recent_actions': <dynamic>[],
    };
Map<String, dynamic> messagePage() => {
      'incident_id': '42',
      'next_cursor': null,
      'messages': [
        {
          'id': '1',
          'sender': 'patient',
          'body': 'Synthetic message',
          'recorded_at': '2026-10-07T10:00:00Z'
        }
      ]
    };

class Gateway implements IncidentWorkspaceGateway {
  String? actor = fixtureActor;
  final changes = StreamController<String?>.broadcast(sync: true);
  final sends = <(String, String)>[];
  final commands = <String>[];
  bool uncertain = false;
  bool patient = false;
  bool denied = false;
  bool conflict = false;
  @override
  String? get userId => actor;
  @override
  Stream<String?> get users => changes.stream;
  @override
  Future<IncidentWorkspace> load(String id) async {
    if (denied) throw const WorkspaceFailure('denied');
    return IncidentWorkspace.fromMap(snapshot(patient: patient), id);
  }

  @override
  Future<IncidentMessagePage> messages(String id, {String? before}) async =>
      IncidentMessagePage.fromMap(messagePage(), id);
  @override
  Future<void> command(String id, String op, String version, String command,
      Map<String, dynamic> payload) async {
    if (conflict) throw const WorkspaceFailure('conflict');
    commands.add(command);
  }

  @override
  Future<void> send(String id, String op, String body) async {
    sends.add((op, body));
    if (uncertain) throw const WorkspaceFailure('unknown');
  }
}

Future<void> panel(WidgetTester tester, Gateway gateway) async {
  await tester.pumpWidget(MaterialApp(
      home: Scaffold(
          body: SingleChildScrollView(
              child: IncidentWorkspacePanel(
                  incidentId: '42', gateway: gateway)))));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
      'dashboard polling preserves drafts while hiding unverified tools',
      (tester) async {
    tester.view.physicalSize = const Size(1500, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final g = Gateway();
    addTearDown(g.changes.close);
    final rows = [DispatchEmergency.fromMap(fixtureIncident(42))];
    Completer<List<DispatchEmergency>>? pending;
    await tester.pumpWidget(MaterialApp(
        theme: CorviaTheme.resolve(),
        home: EmergencyDispatchDashboard(
          accessLoader: () async => fixtureDispatchAccess(
              canReadHistory: true, canUseWorkspace: true),
          incomingEmergencyLoader: () => pending?.future ?? Future.value(rows),
          workspaceGateway: g,
          historyLoader: (id) async => IncidentHistory.fromMap({
            'incident_id': id,
            'events': [
              {
                'version': '1',
                'event_type': 'created',
                'recorded_at': '2026-10-07T10:00:00Z',
                'status': 'pending',
                'previous_status': null
              },
            ]
          }, expectedIncidentId: id),
        )));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Draft survives refresh');
    pending = Completer<List<DispatchEmergency>>();
    await tester.pump(const Duration(seconds: 15));
    await tester.pump();
    expect(find.byType(TextField), findsNothing);
    pending.complete(rows);
    await tester.pumpAndSettle();
    expect(find.text('Draft survives refresh'), findsOneWidget);
    expect(g.sends, isEmpty);
    g.uncertain = true;
    await tester.ensureVisible(find.text('Send message'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Send message'));
    await tester.pumpAndSettle();
    final originalSend = g.sends.single;
    pending = Completer<List<DispatchEmergency>>();
    await tester.pump(const Duration(seconds: 15));
    await tester.pump();
    pending.complete(rows);
    await tester.pumpAndSettle();
    expect(find.text('Retry same action'), findsOneWidget);
    expect(g.sends.length, 1);
    g.uncertain = false;
    await tester.ensureVisible(find.text('Retry same action'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Retry same action'));
    await tester.pumpAndSettle();
    expect(g.sends.last, originalSend);
    await tester.pumpWidget(const SizedBox());
  });
  test('workspace rejects forged patient authority or internal notes', () {
    expect(
        () => IncidentWorkspace.fromMap(
            {...snapshot(patient: true), 'can_manage': true}, '42'),
        throwsA(isA<WorkspaceFailure>()));
    expect(
        () => IncidentWorkspace.fromMap({
              ...snapshot(patient: true),
              'recent_actions': [
                {
                  'action': 'note',
                  'text': 'private',
                  'recorded_at': '2026-10-07T10:00:00Z'
                }
              ]
            }, '42'),
        throwsA(isA<WorkspaceFailure>()));
    expect(
        () => IncidentWorkspace.fromMap(
            {...snapshot(patient: true), 'callback_number': '+27110000000'},
            '42'),
        throwsA(isA<WorkspaceFailure>()));
  });
  for (final change in [
    {'version': 2},
    {'incident_id': '43'},
    {'status': 'accepted'},
    {'priority': 'critical'},
    {'provider_state': 'sent'},
    {'demo_available': 'true'},
    {'callback_number': 'tel:084124'}
  ]) {
    test(
        'workspace validates $change',
        () => expect(
            () => IncidentWorkspace.fromMap({...snapshot(), ...change}, '42'),
            throwsA(isA<WorkspaceFailure>())));
  }
  test('message pages reject identity, sender and ordering corruption', () {
    final page = messagePage();
    final first = (page['messages'] as List).first as Map<String, dynamic>;
    for (final changed in [
      {'sender': 'admin'},
      {'actor_id': fixtureActor},
      {'body': ''},
      {'id': 1},
      {'recorded_at': 'bad'}
    ]) {
      expect(
          () => IncidentMessagePage.fromMap({
                ...page,
                'messages': [
                  {...first, ...changed}
                ]
              }, '42'),
          throwsA(isA<WorkspaceFailure>()));
    }
    expect(
        () => IncidentMessagePage.fromMap({
              ...page,
              'messages': [first, first]
            }, '42'),
        throwsA(isA<WorkspaceFailure>()));
  });
  test('history accepts actual operational update without another claim', () {
    final history = IncidentHistory.fromMap({
      'incident_id': '42',
      'events': [
        {
          'version': '1',
          'event_type': 'created',
          'recorded_at': '2026-10-07T10:00:00Z',
          'status': 'pending',
          'previous_status': null
        },
        {
          'version': '2',
          'event_type': 'claimed',
          'recorded_at': '2026-10-07T10:01:00Z',
          'status': 'in_progress',
          'previous_status': 'pending'
        },
        {
          'version': '3',
          'event_type': 'updated',
          'recorded_at': '2026-10-07T10:02:00Z',
          'status': 'in_progress',
          'previous_status': 'in_progress'
        },
      ]
    }, expectedIncidentId: '42');
    expect(history.events.last.eventType, 'updated');
  });
  for (final code in [
    '42501',
    '401',
    '403',
    'PGRST301',
    'PGRST302',
    'PGRST303'
  ]) {
    test('workspace typed denial $code', () async {
      final client = await fixtureClient((_) async => jsonResponse(
          {'code': code, 'message': 'private diagnostic'},
          status: 403));
      addTearDown(client.dispose);
      await expectLater(
          IncidentWorkspaceService(client: client).load('42'),
          throwsA(
              isA<WorkspaceFailure>().having((e) => e.denied, 'denied', true)));
    });
  }
  test('service uses exact string IDs and verifies receipt', () async {
    Map<String, dynamic>? sent;
    final client = await fixtureClient((r) async {
      sent = jsonDecode(r.body) as Map<String, dynamic>;
      return jsonResponse({
        'incident_id': '9007199254740993',
        'operation_id': fixtureActor,
        'version': '3',
        'command': 'note'
      });
    });
    addTearDown(client.dispose);
    await IncidentWorkspaceService(client: client).command(
        '9007199254740993', fixtureActor, '2', 'note', {'text': 'Synthetic'});
    expect(sent!['p_incident_id'], '9007199254740993');
    expect(sent!['p_expected_version'], '2');
    expect(sent!.containsKey('actor_id'), false);
  });
  test('close command selects the reviewed team completion RPC when enabled',
      () async {
    String? path;
    final client = await fixtureClient((request) async {
      path = request.url.path;
      return jsonResponse({
        'incident_id': '42',
        'operation_id': fixtureActor,
        'version': '3',
        'command': 'close'
      });
    });
    addTearDown(client.dispose);
    await IncidentWorkspaceService(client: client).command(
        '42', fixtureActor, '2', 'close', {'text': 'Synthetic completion'});
    expect(
        path,
        endsWith(Env.ws4TeamEmsHandoffEnabled
            ? '/corvia_ws4_close_incident'
            : '/corvia_dispatch_command'));
  });
  testWidgets(
      'uncertain message retries frozen identity and body without automatic send',
      (tester) async {
    final g = Gateway()..uncertain = true;
    addTearDown(g.changes.close);
    await panel(tester, g);
    await tester.enterText(find.byType(TextField), 'Synthetic new message');
    await tester.tap(find.text('Send message'));
    await tester.pumpAndSettle();
    expect(g.sends.length, 1);
    expect(find.text('Retry same action'), findsOneWidget);
    await tester.tap(find.text('Refresh saved state'));
    await tester.pumpAndSettle();
    expect(g.sends.length, 1);
    g.uncertain = false;
    await tester.tap(find.text('Retry same action'));
    await tester.pumpAndSettle();
    expect(g.sends.length, 2);
    expect(g.sends.first, g.sends.last);
    expect(find.text('Saved to Corvia. Read receipt is not available.'),
        findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('signout clears messages and unsent text', (tester) async {
    final g = Gateway();
    addTearDown(g.changes.close);
    await panel(tester, g);
    await tester.enterText(find.byType(TextField), 'private unsent');
    g.actor = null;
    g.changes.add(null);
    await tester.pump();
    expect(find.textContaining('Synthetic message'), findsNothing);
    expect(find.text('private unsent'), findsNothing);
    expect(find.text('Access could not be verified. Sign in again.'),
        findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('patient requests cancellation without internal commands',
      (tester) async {
    final g = Gateway()..patient = true;
    addTearDown(g.changes.close);
    await panel(tester, g);
    expect(find.text('Save internal note'), findsNothing);
    expect(find.text('Close with reason'), findsNothing);
    await tester.enterText(find.byType(TextField), 'Synthetic reason');
    await tester.tap(find.text('Ask dispatch to cancel'));
    await tester.pumpAndSettle();
    expect(g.commands, ['request_cancellation']);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('empty text never sends', (tester) async {
    final g = Gateway();
    addTearDown(g.changes.close);
    await panel(tester, g);
    await tester.tap(find.text('Send message'));
    await tester.pump();
    expect(g.sends, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('conflict explanation survives saved-state recovery',
      (tester) async {
    final g = Gateway()..conflict = true;
    addTearDown(g.changes.close);
    await panel(tester, g);
    await tester.enterText(find.byType(TextField), 'Synthetic note');
    await tester.tap(find.text('Save internal note'));
    await tester.pumpAndSettle();
    expect(
        find.textContaining(
            'The request changed or this action is not allowed'),
        findsOneWidget);
    expect(find.text('Retry same action'), findsNothing);
    expect(g.commands, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('startup exposes calling before a stalled initializer',
      (tester) async {
    final pending = Completer<void>();
    await tester.pumpWidget(CorviaStartup(
        initialize: () => pending.future, ready: const Text('Ready')));
    expect(find.text('Call ER24'), findsOneWidget);
    expect(find.text('Ready'), findsNothing);
    await tester.pump(const Duration(seconds: 31));
    expect(find.textContaining('could not finish starting'), findsOneWidget);
    expect(find.text('Call ER24'), findsOneWidget);
    pending.complete();
    await tester.pump();
    expect(find.text('Ready'), findsNothing);
  });
  testWidgets('startup enters full app on success', (tester) async {
    await tester.pumpWidget(CorviaStartup(
        initialize: () async {},
        ready: const MaterialApp(home: Text('Ready'))));
    await tester.pumpAndSettle();
    expect(find.text('Ready'), findsOneWidget);
  });
  testWidgets('map is explicit and uses selected incident coordinates',
      (tester) async {
    Uri? opened;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: IncidentLocationPanel(
                incident: DispatchEmergency.fromMap(fixtureIncident(42)),
                openMap: (uri) async {
                  opened = uri;
                  return false;
                }))));
    expect(opened, isNull);
    await tester.tap(find.text('Open recorded location in map'));
    await tester.pumpAndSettle();
    expect(opened!.queryParameters['mlat'], '-26.2');
    expect(opened!.queryParameters['mlon'], '28.0');
    expect(find.textContaining('map could not open'), findsOneWidget);
  });
}
