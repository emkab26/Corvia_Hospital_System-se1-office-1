import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mycorvia/pages/dispatch/dispatch_dashboard.dart';
import 'package:mycorvia/services/emergency_dispatch_service.dart';
import 'package:mycorvia/services/incident_history_service.dart';
import 'package:mycorvia/theme/app_theme.dart';
import 'package:mycorvia/widgets/incident_history_panel.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/ws4_access_fixture.dart';
import 'support/ws4_http_fixture.dart';

IncidentHistory _history(String id, {bool claimed = false}) =>
    IncidentHistory.fromMap({
      'incident_id': id,
      'events': [
        {
          'version': '1',
          'event_type': 'created',
          'recorded_at': '2026-10-07T10:00:00.123456Z',
          'status': 'pending',
          'previous_status': null,
        },
        if (claimed)
          {
            'version': '2',
            'event_type': 'claimed',
            'recorded_at': '2026-10-07T10:01:00Z',
            'status': 'in_progress',
            'previous_status': 'pending',
          },
      ],
    }, expectedIncidentId: id);

class _SessionHistoryService extends IncidentHistoryService {
  _SessionHistoryService(SupabaseClient client, this.reader)
      : super(client: client);

  final IncidentHistoryLoader reader;
  final changes = StreamController<String?>.broadcast(sync: true);
  String? actor = fixtureActor;
  @override
  String? get currentUserId => actor;
  @override
  Stream<String?> get userChanges => changes.stream;
  @override
  Future<IncidentHistory> load(String incidentId) => reader(incidentId);
}

Future<void> _panel(WidgetTester tester,
    {String incidentId = '42',
    Object revision = 1,
    IncidentHistoryLoader? loader,
    IncidentHistoryService? service}) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: IncidentHistoryPanel(
        incidentId: incidentId,
        revision: revision,
        loader: loader,
        service: service,
      ),
    ),
  ));
  await tester.pump();
}

Future<void> _dashboard(WidgetTester tester,
    {required DispatchAccessLoader access,
    required IncidentHistoryLoader history,
    IncomingEmergencyLoader? queue,
    IncomingEmergencyAccepter? accept}) async {
  CorviaColors.setPalette(CorviaPalette.modern);
  CorviaColors.setBrightness(Brightness.light);
  tester.view.physicalSize = const Size(1700, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(
    theme: CorviaTheme.resolve(),
    home: EmergencyDispatchDashboard(
      accessLoader: access,
      incomingEmergencyLoader:
          queue ?? () async => [DispatchEmergency.fromMap(fixtureIncident(42))],
      incomingEmergencyAccepter: accept,
      historyLoader: history,
    ),
  ));
  await tester.pumpAndSettle();
}

Future<void> _dispose(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 16));
}

void main() {
  testWidgets('renders only recorded events with original UTC instants',
      (tester) async {
    await _panel(tester, loader: (id) async => _history(id, claimed: true));
    await tester.pumpAndSettle();
    expect(find.text('Request recorded'), findsOneWidget);
    expect(find.text('Accepted by Corvia dispatch'), findsOneWidget);
    expect(find.text('2026-10-07T10:00:00.123456Z (UTC)'), findsOneWidget);
    expect(find.text('2026-10-07T10:01:00.000Z (UTC)'), findsOneWidget);
    expect(find.textContaining('ER24'), findsNothing);
    expect(find.text('Request cancelled'), findsNothing);
    expect(find.text('Request closed'), findsNothing);
    await _dispose(tester);
  });

  testWidgets('manual refresh clears old events while loading and on failure',
      (tester) async {
    final replacement = Completer<IncidentHistory>();
    var reads = 0;
    await _panel(tester,
        loader: (id) => ++reads == 1
            ? Future.value(_history(id, claimed: true))
            : replacement.future);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Refresh history'));
    await tester.pump();
    expect(reads, 2);
    expect(find.text('Accepted by Corvia dispatch'), findsNothing);
    expect(find.text('Loading request history…'), findsOneWidget);
    replacement.completeError(StateError('private server details'));
    await tester.pumpAndSettle();
    expect(find.text('Request recorded'), findsNothing);
    expect(find.textContaining('private server details'), findsNothing);
    expect(find.text('Request history is unavailable. Try loading it again.'),
        findsOneWidget);
    await _dispose(tester);
  });

  testWidgets('incident switch discards the old incident completion',
      (tester) async {
    final first = Completer<IncidentHistory>();
    final second = Completer<IncidentHistory>();
    final requested = <String>[];
    Future<IncidentHistory> loader(String id) {
      requested.add(id);
      return id == '42' ? first.future : second.future;
    }

    await _panel(tester, loader: loader);
    await _panel(tester, loader: loader, incidentId: '43');
    first.complete(_history('42', claimed: true));
    await tester.pump();
    expect(find.text('Accepted by Corvia dispatch'), findsNothing);
    expect(find.text('Loading request history…'), findsOneWidget);
    second.complete(_history('43'));
    await tester.pumpAndSettle();
    expect(requested, ['42', '43']);
    expect(find.text('Request recorded'), findsOneWidget);
    expect(find.text('Accepted by Corvia dispatch'), findsNothing);
    await _dispose(tester);
  });

  testWidgets('revision refresh rejects an older same-incident completion',
      (tester) async {
    final first = Completer<IncidentHistory>();
    var reads = 0;
    Future<IncidentHistory> loader(String id) =>
        ++reads == 1 ? first.future : Future.value(_history(id, claimed: true));
    await _panel(tester, loader: loader);
    await _panel(tester, loader: loader, revision: 2);
    await tester.pumpAndSettle();
    first.complete(_history('42'));
    await tester.pumpAndSettle();
    expect(reads, 2);
    expect(find.text('Accepted by Corvia dispatch'), findsOneWidget);
    await _dispose(tester);
  });

  testWidgets('mismatched incident result is unavailable without its events',
      (tester) async {
    await _panel(tester, loader: (_) async => _history('43', claimed: true));
    await tester.pumpAndSettle();
    expect(find.text('Accepted by Corvia dispatch'), findsNothing);
    expect(
        find.text(const IncidentHistoryException(
          IncidentHistoryFailureKind.invalidResponse,
        ).message),
        findsOneWidget);
    await _dispose(tester);
  });

  testWidgets('hung reads time out and later completion remains hidden',
      (tester) async {
    final pending = Completer<IncidentHistory>();
    await _panel(tester, loader: (_) => pending.future);
    await tester.pump(const Duration(seconds: 15));
    await tester.pumpAndSettle();
    expect(find.text('Loading request history…'), findsNothing);
    expect(find.text('Request history is unavailable. Try loading it again.'),
        findsOneWidget);
    pending.complete(_history('42', claimed: true));
    await tester.pumpAndSettle();
    expect(find.text('Accepted by Corvia dispatch'), findsNothing);
    await _dispose(tester);
  });

  testWidgets('disposed panel ignores pending completion', (tester) async {
    final pending = Completer<IncidentHistory>();
    await _panel(tester, loader: (_) => pending.future);
    await tester.pumpWidget(const SizedBox.shrink());
    pending.complete(_history('42'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  for (final kind in IncidentHistoryFailureKind.values) {
    testWidgets('typed $kind error clears a successful history',
        (tester) async {
      var reads = 0;
      await _panel(tester, loader: (id) async {
        if (++reads == 1) return _history(id, claimed: true);
        throw IncidentHistoryException(kind);
      });
      await tester.pumpAndSettle();
      await tester.tap(find.text('Refresh history'));
      await tester.pumpAndSettle();
      expect(find.text('Accepted by Corvia dispatch'), findsNothing);
      expect(find.text(IncidentHistoryException(kind).message), findsOneWidget);
      await _dispose(tester);
    });
  }

  for (final pendingRead in [false, true]) {
    testWidgets('account change clears history with pending read: $pendingRead',
        (tester) async {
      final client = await tester.runAsync(
        () => fixtureClient((_) async => jsonResponse(null)),
      );
      final pending = Completer<IncidentHistory>();
      var reads = 0;
      final service = _SessionHistoryService(client!, (id) {
        reads++;
        return pendingRead ? pending.future : Future.value(_history(id));
      });
      await _panel(tester, service: service);
      if (!pendingRead) await tester.pumpAndSettle();
      service.actor = '00000000-0000-4000-8000-000000000099';
      service.changes.add(service.actor);
      await tester.pumpAndSettle();
      expect(find.text('Request recorded'), findsNothing);
      expect(
          find.text(const IncidentHistoryException(
            IncidentHistoryFailureKind.authentication,
          ).message),
          findsOneWidget);
      if (pendingRead) pending.complete(_history('42', claimed: true));
      await tester.pumpAndSettle();
      expect(find.text('Accepted by Corvia dispatch'), findsNothing);
      await tester.tap(find.text('Refresh history'));
      await tester.pumpAndSettle();
      expect(reads, 1);
      await _dispose(tester);
      await service.changes.close();
      await tester.runAsync(client.dispose);
    });
  }

  testWidgets('absent legacy capability never makes a history lookup',
      (tester) async {
    var reads = 0;
    await _dashboard(tester,
        access: () async => fixtureDispatchAccess(),
        history: (id) async {
          reads++;
          return _history(id);
        });
    expect(reads, 0);
    expect(find.byType(IncidentHistoryPanel), findsNothing);
    await _dispose(tester);
  });

  testWidgets('history capability enables the selected valid incident only',
      (tester) async {
    final requested = <String>[];
    await _dashboard(tester,
        access: () async => fixtureDispatchAccess(canReadHistory: true),
        history: (id) async {
          requested.add(id);
          return _history(id);
        });
    expect(requested, ['42']);
    expect(find.text('Request recorded'), findsOneWidget);
    await _dispose(tester);
  });

  for (final revoke in [false, true]) {
    testWidgets('queue refresh clears history; capability revoked: $revoke',
        (tester) async {
      var allowed = true;
      var queueReads = 0;
      var historyReads = 0;
      final pending = Completer<List<DispatchEmergency>>();
      await _dashboard(tester,
          access: () async => fixtureDispatchAccess(canReadHistory: allowed),
          history: (id) async {
            historyReads++;
            return _history(id);
          },
          queue: () async {
            if (++queueReads == 1) {
              return [DispatchEmergency.fromMap(fixtureIncident(42))];
            }
            return pending.future;
          });
      if (revoke) allowed = false;
      await tester.pump(const Duration(seconds: 15));
      await tester.pump();
      expect(queueReads, 2);
      expect(find.byType(IncidentHistoryPanel), findsNothing);
      expect(find.text('Request recorded'), findsNothing);
      pending.complete([DispatchEmergency.fromMap(fixtureIncident(42))]);
      await tester.pumpAndSettle();
      expect(historyReads, revoke ? 1 : 2);
      expect(find.byType(IncidentHistoryPanel),
          revoke ? findsNothing : findsOneWidget);
      await _dispose(tester);
    });
  }

  testWidgets('invalid selected record cannot fetch history', (tester) async {
    var reads = 0;
    await _dashboard(tester,
        access: () async => fixtureDispatchAccess(canReadHistory: true),
        history: (id) async {
          reads++;
          return _history(id);
        },
        queue: () async => [
              DispatchEmergency.fromMap({...fixtureIncident(42), 'id': 'bad'})
            ]);
    expect(reads, 0);
    expect(find.byType(IncidentHistoryPanel), findsNothing);
    await _dispose(tester);
  });

  testWidgets('claim reloads persisted history after queue state changes',
      (tester) async {
    var claimed = false;
    var reads = 0;
    await _dashboard(tester,
        access: () async => fixtureDispatchAccess(canReadHistory: true),
        history: (id) async {
          reads++;
          return _history(id, claimed: claimed);
        },
        accept: (_) async {
          claimed = true;
          return DispatchEmergency.fromMap({
            ...fixtureIncident(42),
            'status': 'in_progress',
            'assigned_dispatcher_user_id': fixtureActor,
            'accepted_at': '2026-10-07T10:01:00Z',
          });
        });
    await tester.ensureVisible(find.text('Accept emergency'));
    await tester.tap(find.text('Accept emergency'));
    await tester.pumpAndSettle();
    expect(reads, 2);
    expect(find.text('Accepted by Corvia dispatch'), findsOneWidget);
    await _dispose(tester);
  });
}
