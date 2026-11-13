import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:mycorvia/pages/paramedic/paramedic_incident_page.dart';
import 'package:mycorvia/pages/paramedic/paramedic_operations_panel.dart';
import 'package:mycorvia/services/paramedic_workspace_service.dart';
import 'package:mycorvia/widgets/payment_website_card.dart';

class DispatchFixture extends ParamedicWorkspaceService {
  DispatchFixture()
      : super(
            client: SupabaseClient('http://localhost', 'test',
                authOptions: const AuthClientOptions(autoRefreshToken: false)));
  @override
  Future<EmsRow> load([int? incident]) async => {
        'operations_role': 'dispatcher',
        'can_dispatch': true,
        'is_admin': false,
        'incident': {
          'incident_id': 1,
          'incident_number': 'EMS-1',
          'status': 'Dispatched',
          'revision': 1,
          'priority': 'High',
          'incident_type': 'Medical',
          'dispatch_state': 'claimed',
          'required_capability': 'BLS'
        },
        'messages': [
          {
            'message_id': 1,
            'sender': 'someone',
            'message': 'Confirm the scene address',
            'acknowledged': false,
            'received_at': '2026-10-09T08:00:00Z'
          }
        ]
      };
}

void main() {
  test(
      'website URL permits local debug previews but requires HTTPS for release',
      () {
    expect(PaymentWebsiteCard.website(debug: true).toString(),
        'http://127.0.0.1:8080');
    expect(PaymentWebsiteCard.website(debug: false), isNull);
    expect(
        PaymentWebsiteCard.website(
            configured: 'http://127.0.0.1:8080', debug: false),
        isNull);
    expect(
        PaymentWebsiteCard.website(
            configured: 'http://untrusted.example', debug: true),
        isNull);
    expect(
        PaymentWebsiteCard.website(
            configured: 'https://user:secret@example.test', debug: false),
        isNull);
    expect(
        PaymentWebsiteCard.website(
            configured: 'https://pay.example.test/checkout?token=secret',
            debug: false),
        isNull);
    expect(
        PaymentWebsiteCard.website(
                configured: 'https://pay.example.test', debug: false)
            ?.host,
        'pay.example.test');
  });
  testWidgets(
      'fleet inspection requires six explicit results and no silent pass defaults',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var count = 0;
    await tester.pumpWidget(MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
            body: SingleChildScrollView(
                child: ParamedicOperationsPanel(
                    data: const {
              'operations_role': 'admin',
              'units_actual': [
                {
                  'unit_id': 1,
                  'unit_number': 'AMB-1',
                  'response_capability': 'BLS',
                  'eligibility_reason':
                      'A current readiness inspection is required',
                  'location_stale': true
                }
              ]
            },
                    admin: true,
                    onForm: (action, title, fields, extra, initial) async {
                      expect(action, 'readiness');
                      expect(
                          fields.where((f) => f.key.endsWith('_ok')).length, 6);
                      expect(
                          fields
                              .where((f) => f.key.endsWith('_ok'))
                              .every((f) => f.required),
                          true);
                      expect(initial, isEmpty);
                      count++;
                      return null;
                    })))));
    await tester.tap(find.text('Record inspection'));
    await tester.pumpAndSettle();
    expect(count, 1);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'dispatcher sees claim and messages but no clinical edit controls',
      (tester) async {
    final service = DispatchFixture();
    addTearDown(service.dispose);
    await tester.pumpWidget(MaterialApp(
        home: ParamedicIncidentPage(
            service: service,
            incidentId: 1,
            catalog: const {},
            onActivity: () {})));
    await tester.pumpAndSettle();
    expect(find.text('Claim / take over'), findsOneWidget);
    expect(find.text('Mark Accepted'), findsNothing);
    expect(find.text('Clinical record'), findsNothing);
    await tester.tap(find.text('Messages'));
    await tester.pumpAndSettle();
    expect(find.text('Confirm the scene address'), findsOneWidget);
    expect(find.text('Awaiting acknowledgement'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
