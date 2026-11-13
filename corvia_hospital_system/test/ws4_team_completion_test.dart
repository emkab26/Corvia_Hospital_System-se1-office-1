import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mycorvia/pages/dispatch/team_completion_page.dart';
import 'package:mycorvia/pages/dispatch/team_operations_page.dart';
import 'package:mycorvia/services/incident_workspace_service.dart';
import 'package:mycorvia/services/team_completion_service.dart';
import 'support/ws4_http_fixture.dart';

class FakeTeamCompletion implements Ws4TeamCompletionGateway {
  @override
  String? userId = 'staff-a';
  bool offered = false, acknowledged = false, received = false;
  String crewState = 'offered';
  String crewVersion = '1';
  bool failOnce = false;
  final operations = <String>[];

  @override
  Future<Map<String, dynamic>> backupOverview(String? id) async => id == null
      ? {
          'items': [
            {
              'backup_id': '11',
              'version': crewVersion,
              'state': crewState,
              'incident_number': 'EMS-SYNTH',
              'priority': 'High',
              'reason': 'Scene requires support',
              'scene_address': 'Test scene'
            }
          ]
        }
      : {
          'ems_revision': offered ? '5' : '4',
          'incident_number': 'EMS-SYNTH',
          'status': 'On Scene',
          'backup_requested': true,
          'backups': offered
              ? [
                  {
                    'backup_id': '11',
                    'version': '1',
                    'state': 'offered',
                    'crew_code': 'BACKUP-1',
                    'unit_number': 'UNIT-2',
                    'reason': 'Scene requires support'
                  }
                ]
              : [],
          'candidates': [
            {
              'crew_id': '22',
              'crew_code': 'BACKUP-1',
              'unit_number': 'UNIT-2',
              'eligibility_reason': null
            }
          ]
        };

  @override
  Future<Map<String, dynamic>> backupDispatch(String id, String op,
      String revision, String action, String? crewId, String reason) async {
    operations.add(op);
    if (failOnce) {
      failOnce = false;
      throw const WorkspaceFailure('unknown');
    }
    offered = action == 'offer';
    return {
      'backup_id': '11',
      'operation_id': op,
      'state': offered ? 'offered' : 'released'
    };
  }

  @override
  Future<Map<String, dynamic>> backupCrew(
      String id, String op, String version, String action) async {
    operations.add(op);
    acknowledged = action == 'acknowledge';
    crewState = switch (action) {
      'acknowledge' => 'acknowledged',
      'decline' => 'declined',
      _ => action,
    };
    crewVersion = (int.parse(crewVersion) + 1).toString();
    return {'backup_id': id, 'operation_id': op, 'state': crewState};
  }

  @override
  Future<Map<String, dynamic>> receiverInbox() async => {
        'items': [
          {
            'handover_id': '31',
            'incident_number': 'EMS-SYNTH',
            'facility_name': 'Test ED',
            'receiver_name': 'Test Receiver',
            'handover_summary': 'Synthetic summary',
            'acknowledged': received
          }
        ]
      };

  @override
  Future<Map<String, dynamic>> receiverAck(
      String id, String op, String reason) async {
    operations.add(op);
    received = true;
    return {'handover_id': id, 'operation_id': op, 'acknowledged': true};
  }
}

class FakeTeamOps implements Ws4TeamOperationsGateway {
  @override
  String? userId = 'staff-a';
  bool failOnce = false, sent = false, read = false;
  String revision = '4';
  final operations = <String>[];

  @override
  Future<String> linkedId(String hospitalId, String emsIncidentId) async => '42';

  @override
  Future<Map<String, dynamic>> teamSnapshot(String id) async => {
    'ws4_incident_id': id, 'revision': revision, 'role': 'supervisor',
    'status': 'On Scene', 'dispatch_state': 'escalated',
    'incident_number': 'EMS-SYNTH', 'scene_address': 'Test scene',
    'units': [
      {'unit_id': '12', 'unit_number': 'UNIT-1', 'role': 'primary',
       'latitude': -26.2, 'longitude': 28.1, 'location_stale': true,
       'location_at': '2026-10-11T00:00:00Z',
       'position_source': 'Fleet recorded location'}
    ],
    'facilities': [
      {'facility_id': '31', 'name': 'Synthetic ED',
       'address': 'Test road', 'phone': '0000000000'}
    ],
    'destination': null,
    'exceptions': [
      {'id': '51', 'kind': 'unsafe_scene', 'reason': 'Road blocked',
       'recorded_at': '2026-10-11T00:00:00Z'}
    ],
    'primary_overdue': true
  };

  @override
  Future<Map<String, dynamic>> teamCommand(String id, String op,
      String expected, String action, Map<String, dynamic> payload) async {
    operations.add(op);
    if (failOnce) {
      failOnce = false;
      throw const WorkspaceFailure('unknown');
    }
    revision = (int.parse(revision) + 1).toString();
    return {'operation_id': op, 'action': action, 'revision': revision};
  }

  @override
  Future<Map<String, dynamic>> backupDeadlines(String? id) async =>
      {'items': []};

  @override
  Future<Map<String, dynamic>> backupConversation(String id) async => {
    'backup_id': id,
    'messages': sent ? [
      {'id': '71', 'sender': read ? 'you' : 'team',
       'body': 'Scene update saved', 'saved_at': '2026-10-11T00:00:00Z',
       'read_by_other': read}
    ] : []
  };

  @override
  Future<Map<String, dynamic>> backupMessage(
      String id, String op, String body) async {
    operations.add(op);
    sent = true;
    return {'backup_id': id, 'operation_id': op,
      'message_id': '71', 'saved': true};
  }

  @override
  Future<Map<String, dynamic>> backupMarkRead(
      String id, String op) async {
    operations.add(op);
    read = true;
    return {'message_id': id, 'operation_id': op, 'read': true};
  }
}

void main() {
  test('backup service uses the scoped RPC and verifies its receipt', () async {
    String? path;
    Map<String, dynamic>? sent;
    const operation = 'aaaaaaaa-1111-4111-8111-111111111111';
    final client = await fixtureClient((request) async {
      path = request.url.path;
      sent = jsonDecode(request.body) as Map<String, dynamic>;
      return jsonResponse(
          {'backup_id': '11', 'operation_id': operation, 'state': 'offered'});
    });
    addTearDown(client.dispose);
    await SupabaseWs4TeamCompletionService(client: client).backupDispatch(
        '42', operation, '4', 'offer', '22', 'Synthetic support required');
    expect(path, endsWith('/corvia_ws4_backup_dispatch'));
    expect(sent!['p_ws4_incident_id'], '42');
    expect(sent!['p_expected_revision'], '4');
    expect(sent!['p_crew_id'], '22');
    expect(sent!.containsKey('actor_id'), false);
  });

  test('receiver service rejects an unverified success body', () async {
    final client = await fixtureClient((_) async => jsonResponse({
          'handover_id': '31',
          'operation_id': 'aaaaaaaa-1111-4111-8111-111111111111',
          'acknowledged': false
        }));
    addTearDown(client.dispose);
    await expectLater(
        SupabaseWs4TeamCompletionService(client: client).receiverAck(
            '31',
            'aaaaaaaa-1111-4111-8111-111111111111',
            'Synthetic handover received'),
        throwsA(
            isA<WorkspaceFailure>().having((e) => e.kind, 'kind', 'unknown')));
  });

  test('team command rejects a mismatched operation receipt', () async {
    final client = await fixtureClient((_) async => jsonResponse({
      'operation_id': 'bbbbbbbb-1111-4111-8111-111111111111',
      'action': 'destination', 'revision': '5'
    }));
    addTearDown(client.dispose);
    await expectLater(
      SupabaseWs4TeamCompletionService(client: client).teamCommand(
        '42', 'aaaaaaaa-1111-4111-8111-111111111111', '4',
        'destination', {'facility_id': '31', 'reason': 'Reviewed destination'}),
      throwsA(isA<WorkspaceFailure>()
        .having((e) => e.kind, 'kind', 'unknown')));
  });

  Future<void> open(WidgetTester tester, Widget page) async {
    tester.view.physicalSize = const Size(1100, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(home: page));
    await tester.pumpAndSettle();
  }

  testWidgets('dispatch offers a separate backup and retries an unknown result',
      (tester) async {
    final fake = FakeTeamCompletion()..failOnce = true;
    await open(tester, Ws4BackupPage(incidentId: '42', gateway: fake));
    await tester.tap(find.text('Eligible backup crew'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('BACKUP-1 · UNIT-2').last);
    await tester.enterText(find.byType(TextField), 'Scene requires support');
    await tester.tap(find.text('Offer backup crew'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Outcome unknown'), findsOneWidget);
    await tester.tap(find.text('Retry the same backup action'));
    await tester.pumpAndSettle();
    expect(fake.operations, hasLength(2));
    expect(fake.operations[0], fake.operations[1]);
    expect(find.text('State: offered'), findsOneWidget);
  });

  testWidgets('assigned backup medic acknowledges own offer', (tester) async {
    final fake = FakeTeamCompletion();
    await open(tester, Ws4BackupPage(gateway: fake));
    await tester.tap(find.text('Acknowledge backup'));
    await tester.pumpAndSettle();
    expect(fake.acknowledged, true);
    expect(find.text('State: acknowledged'), findsOneWidget);
    await tester.tap(find.text('Mark en route'));
    await tester.pumpAndSettle();
    expect(find.text('State: en_route'), findsOneWidget);
    await tester.tap(find.text('Mark on scene'));
    await tester.pumpAndSettle();
    expect(find.text('State: on_scene'), findsOneWidget);
  });

  testWidgets('receiving user selects and confirms one handover',
      (tester) async {
    final fake = FakeTeamCompletion();
    await open(tester, Ws4ReceivingInboxPage(gateway: fake));
    await tester.tap(find.text('Review this handover'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Received in test ED');
    await tester.tap(find.text('Confirm handover received'));
    await tester.pumpAndSettle();
    expect(fake.received, true);
    expect(find.text('Confirmed'), findsOneWidget);
  });

  testWidgets('linked operations show team locations and retain an unknown action',
      (tester) async {
    final fake = FakeTeamOps()..failOnce = true;
    await open(tester, Ws4TeamOperationsPage(
        ws4IncidentId: '42', gateway: fake));
    expect(find.textContaining('STALE'), findsOneWidget);
    expect(find.textContaining('PRIMARY ACKNOWLEDGEMENT OVERDUE'),
        findsOneWidget);
    await tester.tap(find.text('Team receiving facility'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Synthetic ED').last);
    await tester.enterText(find.byType(TextField).last,
        'Synthetic receiving facility selected');
    await tester.tap(find.text('Record destination with reason'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Outcome unknown'), findsOneWidget);
    await tester.tap(find.text('Retry the same team action'));
    await tester.pumpAndSettle();
    expect(fake.operations, hasLength(2));
    expect(fake.operations[0], fake.operations[1]);
  });

  testWidgets('backup conversation saves and explicitly reads a message',
      (tester) async {
    final fake = FakeTeamOps();
    await open(tester, Ws4BackupConversationPage(
        backupId: '11', gateway: fake));
    await tester.enterText(find.byType(TextField), 'Scene update saved');
    await tester.tap(find.text('Save and send message'));
    await tester.pumpAndSettle();
    expect(fake.sent, true);
    await tester.tap(find.text('Mark read'));
    await tester.pumpAndSettle();
    expect(fake.read, true);
  });

  testWidgets('linked team view clears incident details on account change',
      (tester) async {
    final fake = FakeTeamOps();
    await open(tester, Ws4TeamOperationsPage(
        ws4IncidentId: '42', gateway: fake));
    expect(find.textContaining('Test scene'), findsOneWidget);
    fake.userId = 'other-account';
    await tester.tap(find.byTooltip('Refresh linked response'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Test scene'), findsNothing);
    expect(find.textContaining('Access could not be verified'), findsOneWidget);
  });
}
