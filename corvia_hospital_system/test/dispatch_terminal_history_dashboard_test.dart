
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mycorvia/pages/dispatch/dispatch_dashboard.dart';
import 'package:mycorvia/pages/dispatch/dispatch_history_report_panel.dart';
import 'package:mycorvia/services/dispatch_terminal_history_service.dart';
import 'package:mycorvia/theme/app_theme.dart';

import 'support/ws4_access_fixture.dart';

class _HistoryGateway implements DispatchTerminalHistoryGateway {
  int loads = 0;

  @override
  String? get currentUserId =>
      '00000000-0000-4000-8000-000000000001';

  @override
  Stream<String?> get userChanges =>
      const Stream<String?>.empty();

  @override
  Future<DispatchTerminalHistorySnapshot> loadRecent() async {
    loads++;

    return DispatchTerminalHistorySnapshot(
      receivedAt: DateTime.utc(2026, 10, 12, 13),
      hasMore: false,
      records: [
        DispatchHistoryRecord(
          incidentId: '42',
          status: 'resolved',
          completion: DispatchCompletionState.completed,
          createdAt: DateTime.utc(2026, 10, 12, 10),
          completedAt: DateTime.utc(2026, 10, 12, 11),
        ),
      ],
    );
  }
}

void main() {
  setUp(() {
    CorviaColors.setPalette(CorviaPalette.modern);
    CorviaColors.setBrightness(Brightness.light);
  });

  testWidgets(
    'Reports retains queue summary and shows verified recent ledger',
    (tester) async {
      tester.view.physicalSize = const Size(1500, 1000);
      tester.view.devicePixelRatio = 1;

      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final gateway = _HistoryGateway();

      await tester.pumpWidget(
        MaterialApp(
          theme: CorviaTheme.resolve(),
          home: EmergencyDispatchDashboard(
            accessLoader: () async =>
                fixtureDispatchAccess(
                  canReadHistory: true,
                ),
            incomingEmergencyLoader: () async => [],
            terminalHistoryGateway: gateway,
          ),
        ),
      );

      await tester.pumpAndSettle();
      await tester.tap(find.text('Reports'));
      await tester.pumpAndSettle();

      expect(
        find.text('Current queue snapshot'),
        findsOneWidget,
      );

      expect(
        find.text('Recent resolved / cancelled incidents'),
        findsOneWidget,
      );

      expect(
        find.text('Incident 42'),
        findsOneWidget,
      );

      expect(
        find.text('1 completed'),
        findsOneWidget,
      );

      expect(
        find.textContaining('PARTIAL / UNVERIFIED RESULT SET'),
        findsOneWidget,
      );

      expect(gateway.loads, 1);
      expect(tester.takeException(), isNull);
    },
  );
}
