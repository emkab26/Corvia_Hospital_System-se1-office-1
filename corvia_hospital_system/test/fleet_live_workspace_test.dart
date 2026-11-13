import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:mycorvia/pages/paramedic/paramedic_workspace_page.dart';
import 'package:mycorvia/services/paramedic_workspace_service.dart';

import 'support/ws4_http_fixture.dart';

EmsRow snapshot({bool empty = false}) => {
      'is_admin': true,
      'units_actual': empty
          ? []
          : [
              {
                'unit_id': 42,
                'unit_number': 'LIVE-42',
                'registration_number': 'LIVE-REG',
                'vehicle_type': 'Ambulance',
                'status': 'Available',
                'readiness_status': 'ready',
                'is_active': true,
              }
            ],
    };

class _WorkspaceFixture extends ParamedicWorkspaceService {
  _WorkspaceFixture(SupabaseClient client) : super(client: client);
  bool empty = false;
  @override
  Future<List<EmsRow>> access() async => [
        {'id': 'hospital-a', 'name': 'Authorised hospital'}
      ];
  @override
  Future<void> open(String hospital) async {
    hospitalId = hospital;
    userId = client.auth.currentUser!.id;
    session = 'session-a';
  }

  @override
  Future<EmsRow> load([int? incident]) async => snapshot(empty: empty);
}

void main() {
  late SupabaseClient client;
  final requests = <String>[];
  setUpAll(() async {
    client = await fixtureClient((request) async {
      requests.add(request.url.path);
      final payload =
          request.body.isEmpty ? {} : (jsonDecode(request.body) as Map?) ?? {};
      switch (request.url.path) {
        case '/rest/v1/rpc/corvia_ems_access':
          return jsonResponse([
            {'id': 'hospital-a', 'name': 'Authorised hospital'}
          ]);
        case '/rest/v1/rpc/corvia_ems_open':
          expect(payload['h'], 'hospital-a');
          return jsonResponse('session-a');
        case '/rest/v1/rpc/corvia_ems_workspace':
          expect(payload['h'], 'hospital-a');
          expect(payload['s'], 'session-a');
          return jsonResponse(snapshot());
        default:
          throw StateError('Unexpected data source: ${request.url.path}');
      }
    });
  });
  tearDownAll(() => client.dispose());

  test('live Fleet gateway uses hospital and session scoped EMS RPCs',
      () async {
    final service = ParamedicWorkspaceService(client: client);
    expect((await service.access()).single['id'], 'hospital-a');
    await service.open('hospital-a');
    final data = await service.load();
    expect(emsRows(data['units_actual']).single['unit_number'], 'LIVE-42');
    expect(requests, [
      '/rest/v1/rpc/corvia_ems_access',
      '/rest/v1/rpc/corvia_ems_open',
      '/rest/v1/rpc/corvia_ems_workspace',
    ]);
    service.dispose();
  });

  testWidgets('Vehicles renders workspace records, filters and refreshes empty',
      (tester) async {
    final service = _WorkspaceFixture(client);
    await tester.pumpWidget(MaterialApp(
      home:
          ParamedicWorkspacePage(initialSection: 'Vehicles', service: service),
    ));
    await tester.pumpAndSettle();
    expect(find.text('LIVE-42'), findsOneWidget);
    expect(find.text('AMB-01'), findsNothing);
    expect(find.text('Edit details'), findsOneWidget);
    expect(find.text('Change readiness'), findsOneWidget);
    await tester.tap(find.widgetWithText(ChoiceChip, 'Maintenance'));
    await tester.pumpAndSettle();
    expect(find.text('LIVE-42'), findsNothing);
    expect(find.text('No vehicles match this status filter.'), findsOneWidget);
    await tester.tap(find.widgetWithText(ChoiceChip, 'All'));
    await tester.pumpAndSettle();
    service.empty = true;
    await tester.tap(find.text('Refresh'));
    await tester.pumpAndSettle();
    expect(
        find.text('No vehicles returned for this hospital.'), findsOneWidget);
    expect(find.text('LIVE-42'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
