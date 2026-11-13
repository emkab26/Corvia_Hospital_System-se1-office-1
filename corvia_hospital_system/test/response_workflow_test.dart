import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mycorvia/pages/dispatch/response_workspace_page.dart';
import 'package:mycorvia/services/response_workflow_service.dart';
import 'package:mycorvia/services/incident_workspace_service.dart';
import 'package:mycorvia/services/ems_handoff_service.dart';
import 'support/ws4_http_fixture.dart';

const unit = '00000000-0000-4000-8000-000000000001';
const assignment = '00000000-0000-4000-8000-000000000002';
Map<String, dynamic> fixture(
        {String role = 'dispatcher', String state = 'offered'}) =>
    {
      'incident_id': '42',
      'version': '2',
      'role': role,
      'status': 'in_progress',
      'can_manage': role == 'dispatcher',
      'server_time': '2026-10-08T12:00:00Z',
      'older_events': false,
      'units': role == 'dispatcher'
          ? [
              <String, dynamic>{
                'id': unit,
                'label': 'Unit A',
                'version': '1',
                'reason': 'Eligible'
              }
            ]
          : [],
      'assignments': role == 'crew'
          ? [
              {
                'id': assignment,
                'unit_id': unit,
                'unit': 'Unit A',
                'crew': 'Crew A',
                'state': state,
                'active': true,
                'mine': true,
                'overdue': false,
                'purpose': 'primary',
                'deadline': '2026-10-08T12:02:00Z',
                'attention': null,
                'crew_available': true,
                'patient_confirmed': false,
                'location_fresh': false,
                'destination_id': null
              }
            ]
          : [],
      'destinations': [],
      'events': [],
    };

class FakeResponse implements ResponseWorkflowGateway {
  @override
  String? userId = 'user-a';
  final auth = StreamController<String?>.broadcast();
  @override
  Stream<String?> get users => auth.stream;
  Map<String, dynamic> data = fixture();
  Object? failure;
  Completer<ResponseWorkspace>? pendingRead;
  final calls = <({
    String id,
    String op,
    String version,
    String action,
    Map<String, dynamic> payload
  })>[];
  @override
  Future<List<String>> inbox({bool includeClosed = false}) async => ['42'];
  @override
  Future<Map<String, dynamic>?> unit() async => null;
  @override
  Future<void> unitLocation(String id, String operation, String version,
      Map<String, dynamic> payload) async {
    throw UnimplementedError();
  }

  @override
  Future<void> reviewReadiness(String id, String operation, String version,
      Map<String, dynamic> payload) async {
    calls.add((
      id: id,
      op: operation,
      version: version,
      action: 'readiness',
      payload: payload
    ));
  }

  @override
  Future<ResponseWorkspace> load(String id) async => pendingRead == null
      ? ResponseWorkspace.fromMap(data, id)
      : await pendingRead!.future;
  @override
  Future<void> command(String id, String operation, String version,
      String action, Map<String, dynamic> payload) async {
    calls.add((
      id: id,
      op: operation,
      version: version,
      action: action,
      payload: payload
    ));
    if (failure != null) throw failure!;
    data = {...data, 'version': '3'};
  }
}

class FakeHandoff implements EmsHandoffGateway {
  @override
  String? userId = 'user-a';
  Map<String, dynamic> status = {
    'mode': 'team',
    'linked': false,
    'team_access': true,
    'can_handoff': true,
    'hospital_id': 'aaaaaaaa-1111-4111-8111-111111111111'
  };
  int handoffs = 0;
  final operations = <String>[];
  WorkspaceFailure? nextFailure;
  @override
  Future<EmsHandoffStatus> load(String incidentId) async =>
      EmsHandoffStatus.fromMap(status);
  @override
  Future<EmsHandoffStatus> handoff(String incidentId, String hospitalId,
      String operationId, String priority, String requiredCapability) async {
    handoffs++;
    operations.add(operationId);
    final failure = nextFailure;
    nextFailure = null;
    if (failure != null) throw failure;
    status = {
      ...status,
      'linked': true,
      'can_handoff': false,
      'ems_incident_id': '82',
      'ems_number': 'EMS-TEST-82',
      'ems_status': 'Dispatched',
      'dispatch_state': 'pending'
    };
    return EmsHandoffStatus.fromMap(status);
  }
}

void main() {
  test('EMS bridge status rejects invalid or contradictory receipts', () {
    expect(() => EmsHandoffStatus.fromMap({'mode': 'team', 'linked': true}),
        throwsA(isA<WorkspaceFailure>()));
    expect(
        () =>
            EmsHandoffStatus.fromMap({'mode': 'unconfigured', 'linked': true}),
        throwsA(isA<WorkspaceFailure>()));
  });
  for (final code in ['42501', 'PGRST301', 'PGRST302', 'PGRST303']) {
    for (final mutation in [false, true]) {
      test('typed response denial $code on ${mutation ? 'command' : 'read'}',
          () async {
        final client = await fixtureClient((_) async => jsonResponse(
            {'code': code, 'message': 'private backend detail'},
            status: 403));
        addTearDown(client.dispose);
        final service = ResponseWorkflowService(client: client);
        await expectLater(
            mutation
                ? service.command('42', assignment, '2', 'acknowledge',
                    {'assignment_id': assignment})
                : service.load('42'),
            throwsA(isA<WorkspaceFailure>()
                .having((e) => e.denied, 'denied', true)));
      });
    }
  }
  test('incorrect command receipt remains an unknown outcome', () async {
    final client = await fixtureClient((_) async => jsonResponse({
          'incident_id': '42',
          'operation_id': assignment,
          'version': '2',
          'assignment_id': assignment
        }));
    addTearDown(client.dispose);
    await expectLater(
        ResponseWorkflowService(client: client).command('42', assignment, '2',
            'acknowledge', {'assignment_id': assignment}),
        throwsA(
            isA<WorkspaceFailure>().having((e) => e.kind, 'kind', 'unknown')));
  });
  test('rejects unknown response state', () {
    expect(
        () => ResponseWorkspace.fromMap(
            fixture(role: 'crew', state: 'invented'), '42'),
        throwsA(isA<WorkspaceFailure>()));
  });
  test('rejects mismatched incident and exposed dispatch units for crew', () {
    expect(() => ResponseWorkspace.fromMap(fixture(), '43'),
        throwsA(isA<WorkspaceFailure>()));
    expect(
        () => ResponseWorkspace.fromMap({...fixture(), 'role': 'crew'}, '42'),
        throwsA(isA<WorkspaceFailure>()));
  });
  test('rejects invalid map coordinates', () {
    expect(
        () => ResponseWorkspace.fromMap(
            {...fixture(), 'latitude': double.nan}, '42'),
        throwsA(isA<WorkspaceFailure>()));
  });
  Future<void> open(WidgetTester tester, FakeResponse fake,
      {double width = 1000}) async {
    tester.view.physicalSize = Size(width, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(fake.auth.close);
    await tester.pumpWidget(MaterialApp(
        home: ResponseWorkspacePage(incidentId: '42', gateway: fake)));
    await tester.pumpAndSettle();
  }

  testWidgets('team route hides legacy allocation and links one EMS case',
      (tester) async {
    final response = FakeResponse();
    final team = FakeHandoff();
    tester.view.physicalSize = const Size(1000, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(response.auth.close);
    await tester.pumpWidget(MaterialApp(
        home: ResponseWorkspacePage(
            incidentId: '42', gateway: response, handoffGateway: team)));
    await tester.pumpAndSettle();
    expect(find.text('Fleet & Paramedic handoff'), findsOneWidget);
    expect(find.text('Units'), findsNothing);
    await tester.ensureVisible(find.text('Response priority'));
    await tester.tap(find.text('Response priority'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('High').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Minimum crew capability'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ALS').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Create linked team EMS incident'));
    await tester.tap(find.text('Create linked team EMS incident'));
    await tester.pumpAndSettle();
    expect(team.handoffs, 1);
    expect(find.textContaining('EMS-TEST-82'), findsOneWidget);
    expect(find.text('Units'), findsNothing);
  });

  testWidgets('rejected team handoff permits a new operation', (tester) async {
    final response = FakeResponse();
    final team = FakeHandoff()
      ..nextFailure = const WorkspaceFailure('conflict');
    tester.view.physicalSize = const Size(1000, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(response.auth.close);
    await tester.pumpWidget(MaterialApp(
        home: ResponseWorkspacePage(
            incidentId: '42', gateway: response, handoffGateway: team)));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Response priority'));
    await tester.tap(find.text('Response priority'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('High').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Minimum crew capability'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ALS').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Create linked team EMS incident'));
    await tester.tap(find.text('Create linked team EMS incident'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Handoff was rejected'), findsOneWidget);
    expect(team.handoffs, 1);
    await tester.ensureVisible(find.text('Create linked team EMS incident'));
    await tester.tap(find.text('Create linked team EMS incident'));
    await tester.pumpAndSettle();
    expect(team.handoffs, 2);
    expect(team.operations[1], isNot(team.operations[0]));
  });

  testWidgets('assigns only an eligible unit through the versioned command',
      (tester) async {
    final fake = FakeResponse();
    await open(tester, fake);
    await tester.ensureVisible(find.text('Assign'));
    await tester.tap(find.text('Assign'));
    await tester.pumpAndSettle();
    expect(fake.calls.single.action, 'assign');
    expect(fake.calls.single.version, '2');
    expect(fake.calls.single.payload['unit_id'], unit);
    expect(fake.calls.single.payload['unit_version'], '1');
    expect(find.textContaining('Saved to Corvia'), findsOneWidget);
  });
  testWidgets('ineligible unit is visible but cannot be assigned',
      (tester) async {
    final fake = FakeResponse();
    fake.data = fixture();
    (fake.data['units'] as List).first['reason'] =
        'Readiness missing or expired';
    await open(tester, fake);
    expect(
        tester
            .widget<OutlinedButton>(
                find.widgetWithText(OutlinedButton, 'Assign'))
            .onPressed,
        isNull);
  });
  testWidgets(
      'unknown outcome keeps exact operation and payload for explicit retry',
      (tester) async {
    final fake = FakeResponse()..failure = const WorkspaceFailure('unknown');
    await open(tester, fake);
    await tester.ensureVisible(find.text('Assign'));
    await tester.tap(find.text('Assign'));
    await tester.pumpAndSettle();
    final first = fake.calls.single;
    expect(find.textContaining('Outcome unknown'), findsOneWidget);
    await tester.tap(find.byTooltip('Refresh response'));
    await tester.pumpAndSettle();
    expect(fake.calls, hasLength(1));
    fake.failure = null;
    await tester.ensureVisible(find.text('Retry same response action'));
    await tester.tap(find.text('Retry same response action'));
    await tester.pumpAndSettle();
    expect(fake.calls, hasLength(2));
    expect(fake.calls.last.op, first.op);
    expect(fake.calls.last.payload, first.payload);
    expect(fake.calls.last.version, first.version);
  });
  testWidgets('account change clears protected data and pending action',
      (tester) async {
    final fake = FakeResponse()..failure = const WorkspaceFailure('unknown');
    await open(tester, fake);
    await tester.ensureVisible(find.text('Assign'));
    await tester.tap(find.text('Assign'));
    await tester.pumpAndSettle();
    fake.userId = 'user-b';
    fake.auth.add('user-b');
    await tester.pumpAndSettle();
    expect(find.text('Unit A'), findsNothing);
    expect(find.text('Retry same response action'), findsNothing);
    expect(find.textContaining('Access could not be verified'), findsOneWidget);
  });
  testWidgets(
      'crew can acknowledge but cannot allocate or confirm hospital receipt',
      (tester) async {
    final fake = FakeResponse()..data = fixture(role: 'crew');
    await open(tester, fake, width: 390);
    expect(find.text('Assign'), findsNothing);
    expect(find.text('Confirm patient received'), findsNothing);
    await tester.scrollUntilVisible(find.text('Acknowledge'), 200,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Acknowledge'));
    await tester.pumpAndSettle();
    expect(fake.calls.single.action, 'acknowledge');
    expect(fake.calls.single.payload['assignment_id'], assignment);
    expect(tester.takeException(), isNull);
  });
  testWidgets('crew must record patient match before transport',
      (tester) async {
    final fake = FakeResponse()
      ..data = fixture(role: 'crew', state: 'on_scene');
    fake.data['assignments'][0]['destination_id'] = unit;
    await open(tester, fake);
    expect(
        tester
            .widget<OutlinedButton>(
                find.widgetWithText(OutlinedButton, 'Record transporting'))
            .onPressed,
        isNull);
    await tester.enterText(
        find.byType(TextField), 'Synthetic identity checked against incident');
    await tester.scrollUntilVisible(
        find.text('Record patient match with evidence'), 200,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Record patient match with evidence'));
    await tester.pumpAndSettle();
    expect(fake.calls.single.action, 'confirm_patient');
    expect(fake.calls.single.payload['text'], contains('Synthetic identity'));
  });
  testWidgets('readiness review records unchecked checks as failed on mobile',
      (tester) async {
    final fake = FakeResponse();
    fake.data['units'][0]['can_review'] = true;
    await open(tester, fake, width: 390);
    await tester.enterText(
        find.byType(TextField), 'Synthetic inspection incomplete');
    await tester.scrollUntilVisible(find.text('Review readiness'), 200,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Review readiness'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Record review'));
    await tester.pumpAndSettle();
    expect(fake.calls.single.action, 'readiness');
    expect(fake.calls.single.payload['oxygen'], false);
    expect(fake.calls.single.payload['no_faults'], false);
    expect(tester.takeException(), isNull);
  });
}
