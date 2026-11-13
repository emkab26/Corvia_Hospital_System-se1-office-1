import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mycorvia/pages/blood_bank/blood_bank_page.dart';
import 'package:mycorvia/pages/blood_bank/blood_bank_picker.dart';
import 'package:mycorvia/pages/blood_bank/blood_bank_scan_panel.dart';
import 'package:mycorvia/services/blood_bank_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  testWidgets('picker ignores stale searches and editing clears a selection',
      (tester) async {
    final first = Completer<List<BloodBankRow>>();
    final second = Completer<List<BloodBankRow>>();
    BloodBankRow? selection;
    final form = GlobalKey<FormState>();
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Form(
                key: form,
                child: BloodBankPicker(
                  label: 'Patient',
                  load: (q) => q == 'Old' ? first.future : second.future,
                  describe: (r) => r['name'] as String,
                  onSelected: (r) => selection = r,
                  onDenied: (_) => fail('Unexpected denial'),
                )))));
    await tester.enterText(find.byType(TextField), 'Old');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.enterText(find.byType(TextField), 'New');
    await tester.pump(const Duration(milliseconds: 400));
    second.complete([
      {'id': 'new', 'name': 'New patient'}
    ]);
    await tester.pumpAndSettle();
    first.complete([
      {'id': 'old', 'name': 'Old patient'}
    ]);
    await tester.pumpAndSettle();
    expect(find.text('Old patient'), findsNothing);
    await tester.tap(find.text('New patient'));
    await tester.pumpAndSettle();
    expect(selection?['id'], 'new');
    expect(form.currentState!.validate(), isTrue);
    await tester.enterText(find.byType(TextField), 'N');
    await tester.pumpAndSettle();
    expect(selection, isNull);
    expect(form.currentState!.validate(), isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('scan retry uses identical operation without changing stock',
      (tester) async {
    final service = _FixtureService();
    String? found;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: BloodBankScanPanel(
      service: service,
      hospitalId: 'h',
      onFound: (n) => found = n,
      onDenied: (_) => fail('Unexpected denial'),
      onBack: () {},
    ))));
    await tester.enterText(find.byType(TextField), 'SYNTHETIC-UNIT');
    await tester.tap(find.widgetWithText(FilledButton, 'Find unit'));
    await tester.pumpAndSettle();
    expect(find.text('Retry lookup'), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
    await tester.tap(find.text('Retry lookup'));
    await tester.pumpAndSettle();
    expect(found, 'SYNTHETIC-UNIT');
    expect(service.scanCommands.length, 2);
    expect(service.scanCommands[0].operationId,
        service.scanCommands[1].operationId);
    expect(service.dashboardCalls, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('new request opens a patient search instead of manual UUID entry',
      (tester) async {
    final service = _FixtureService();
    await tester.pumpWidget(MaterialApp(home: BloodBankPage(service: service)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('New request'));
    await tester.pumpAndSettle();
    expect(find.byType(BloodBankPicker), findsOneWidget);
    expect(find.text('Patient UUID in this hospital'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test('uncertain retries reuse the same operation and immutable payload',
      () async {
    final calls = <Map<String, dynamic>>[];
    final client = SupabaseClient('https://example.test', 'public-test-key',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient((request) async {
      calls.add(jsonDecode(request.body) as Map<String, dynamic>);
      if (calls.length == 1) throw TimeoutException('Lost response');
      return http.Response('{"id":"saved-unit"}', 200,
          request: request, headers: {'content-type': 'application/json'});
    }));
    final service = BloodBankService(client: client);
    final input = {'unit_number': 'SYNTHETIC'};
    final command = BloodBankCommand('hospital', 'receive', input);
    input['unit_number'] = 'CHANGED';
    await expectLater(
        service.execute(command), throwsA(isA<TimeoutException>()));
    expect((await service.execute(command))['id'], 'saved-unit');
    expect(calls[0], calls[1]);
    expect((calls[1]['p_payload'] as Map)['unit_number'], 'SYNTHETIC');
    expect(command.operationId, matches(RegExp(r'^[a-f0-9-]{36}$')));
    expect(() => command.payload['reason'] = 'mutated', throwsUnsupportedError);
    await client.dispose();
  });

  test('missing migration is distinct from denied access and transport errors',
      () {
    expect(
        BloodBankService.message(
            const PostgrestException(message: 'missing', code: 'PGRST202')),
        contains('not installed'));
    for (final code in ['42501', 'PGRST301', 'PGRST302', 'PGRST303']) {
      expect(
          BloodBankService.accessDenied(
              PostgrestException(message: 'denied', code: code)),
          isTrue);
    }
    expect(
        BloodBankService.message(const PostgrestException(message: 'no code')),
        'no code');
    expect(
        BloodBankService.definitelyRejected(TimeoutException('lost')), isFalse);
    expect(
        BloodBankService.definitelyRejected(
            const PostgrestException(message: 'stale', code: '40001')),
        isTrue);
  });

  testWidgets('no membership shows explicit denial and no operational controls',
      (tester) async {
    final service = _FixtureService()..memberships = [];
    await tester.pumpWidget(MaterialApp(home: BloodBankPage(service: service)));
    await tester.pumpAndSettle();
    expect(find.textContaining('No blood-bank membership'), findsOneWidget);
    expect(find.text('Receive unit'), findsNothing);
    expect(service.dashboardCalls, 0);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(service.client.dispose);
  });

  testWidgets('narrow inventory shows real stock and clinical gate',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final service = _FixtureService();
    await tester.pumpWidget(MaterialApp(home: BloodBankPage(service: service)));
    await tester.pumpAndSettle();
    expect(find.textContaining('Reservation and issue are disabled'),
        findsOneWidget);
    expect(find.textContaining('SYNTHETIC-UNIT'), findsOneWidget);
    expect(find.text('Receive unit'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(service.client.dispose);
  });

  testWidgets(
      'membership revocation clears protected stock on next access check',
      (tester) async {
    final service = _FixtureService();
    await tester.pumpWidget(MaterialApp(home: BloodBankPage(service: service)));
    await tester.pumpAndSettle();
    expect(find.textContaining('SYNTHETIC-UNIT'), findsOneWidget);
    service.memberships = [];
    await tester.pump(const Duration(seconds: 31));
    await tester.pumpAndSettle();
    expect(find.textContaining('SYNTHETIC-UNIT'), findsNothing);
    expect(find.textContaining('access changed'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(service.client.dispose);
  });

  testWidgets('late dashboard response cannot restore data after page disposal',
      (tester) async {
    final service = _FixtureService();
    await tester.pumpWidget(MaterialApp(home: BloodBankPage(service: service)));
    await tester.pumpAndSettle();
    final pending = Completer<BloodBankRow>();
    service.pending = pending;
    await tester.tap(find.byTooltip('Refresh'));
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    pending.complete(service.board);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.runAsync(service.client.dispose);
  });
}

class _FixtureService extends BloodBankService {
  _FixtureService() : super(client: _fixtureClient());
  @override
  String? get userId => 'synthetic-user';
  int dashboardCalls = 0;
  final List<BloodBankCommand> scanCommands = [];
  @override
  Future<BloodBankRow> lookupScan(BloodBankCommand command) async {
    scanCommands.add(command);
    if (scanCommands.length == 1) throw TimeoutException('Lost scan response');
    return {
      'status': 'matched',
      'unit_id': 'u',
      'unit_number': 'SYNTHETIC-UNIT'
    };
  }

  Completer<BloodBankRow>? pending;
  List<BloodBankRow> memberships = [
    {
      'hospital_id': 'h',
      'hospital_name': 'Synthetic Hospital',
      'role': 'manager'
    }
  ];
  final BloodBankRow board = {
    'role': 'manager',
    'server_time': '2026-10-08T08:00:00Z',
    'settings': {'clinical_issue_enabled': false, 'operating_mode': 'receiver'},
    'products': <BloodBankRow>[],
    'locations': <BloodBankRow>[],
    'units': [
      {
        'id': 'u',
        'unit_number': 'SYNTHETIC-UNIT',
        'abo': 'O',
        'rhd': 'positive',
        'status': 'available',
        'product_name': 'Test cells',
        'location_name': 'Test fridge',
        'expires_at': '2026-11-01T00:00:00Z',
        'expired': false,
        'expires_within_24h': false,
        'group_source_reference': 'Synthetic label'
      }
    ],
    'counts': {'total': 1, 'available': 1, 'expired': 0, 'held': 0},
    'matching_count': 1,
  };
  @override
  Future<List<BloodBankRow>> access() async => memberships;
  @override
  Future<BloodBankRow> dashboard(String hospitalId,
      {String search = '', String status = '', int offset = 0}) async {
    dashboardCalls++;
    return pending == null ? board : await pending!.future;
  }

  @override
  Future<List<BloodBankRow>> requests(String hospitalId,
          {int offset = 0}) async =>
      [];
}

class _MockClient extends Mock implements SupabaseClient {}

class _MockAuth extends Mock implements GoTrueClient {}

SupabaseClient _fixtureClient() {
  final client = _MockClient();
  final auth = _MockAuth();
  when(() => client.auth).thenReturn(auth);
  when(() => auth.onAuthStateChange)
      .thenAnswer((_) => const Stream<AuthState>.empty());
  when(client.dispose).thenAnswer((_) async {});
  return client;
}
