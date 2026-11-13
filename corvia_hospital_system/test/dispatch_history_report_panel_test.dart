
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mycorvia/pages/dispatch/dispatch_history_report_panel.dart';

void main() {
  const completed = DispatchHistoryRecord(
    incidentId: 'INC-COMPLETE',
    status: 'closed',
    completion: DispatchCompletionState.completed,
    outcome: 'Received by hospital',
    createdAt: null,
    completedAt: null,
  );
  const notCompleted = DispatchHistoryRecord(
    incidentId: 'INC-OPEN',
    status: 'in_progress',
    completion: DispatchCompletionState.notCompleted,
  );
  const unverified = DispatchHistoryRecord(
    incidentId: 'INC-UNKNOWN',
    status: 'closed',
    completion: DispatchCompletionState.unknown,
  );

  Widget screen(List<DispatchHistoryRecord> records) {
    return MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: DispatchHistoryReportPanel(records: records),
        ),
      ),
    );
  }

  testWidgets('Shows only loaded counts and marks partial scope',
      (tester) async {
    await tester.pumpWidget(screen([completed, notCompleted, unverified]));
    expect(find.text('3 loaded'), findsOneWidget);
    expect(find.text('1 completed'), findsOneWidget);
    expect(find.text('1 not completed'), findsOneWidget);
    expect(find.text('1 unverified'), findsOneWidget);
    expect(find.textContaining('PARTIAL / UNVERIFIED RESULT SET'),
        findsOneWidget);
  });

  testWidgets('A raw closed status does not establish completion',
      (tester) async {
    await tester.pumpWidget(screen([unverified]));
    expect(find.text('0 completed'), findsOneWidget);
    expect(find.text('1 unverified'), findsOneWidget);
    expect(find.textContaining('Completion: Not verified'), findsOneWidget);
  });

  testWidgets('Completed filter excludes open and unverified records',
      (tester) async {
    await tester.pumpWidget(screen([completed, notCompleted, unverified]));
    await tester.tap(find.text('Completed only'));
    await tester.pumpAndSettle();
    expect(find.text('1 matching loaded records'), findsOneWidget);
    expect(find.text('Incident INC-COMPLETE'), findsOneWidget);
    expect(find.text('Incident INC-OPEN'), findsNothing);
    expect(find.text('Incident INC-UNKNOWN'), findsNothing);
  });

  testWidgets('Search filters incident reference', (tester) async {
    await tester.pumpWidget(screen([completed, notCompleted]));
    await tester.enterText(
      find.byKey(const ValueKey('dispatch-history-search')), 'INC-OPEN');
    await tester.pump();
    expect(find.text('Incident INC-OPEN'), findsOneWidget);
    expect(find.text('Incident INC-COMPLETE'), findsNothing);
  });

  test('Only valid completed timestamp pairs contribute to elapsed time', () {
    final valid = DispatchHistoryRecord(
      incidentId: 'valid',
      status: 'closed',
      completion: DispatchCompletionState.completed,
      createdAt: DateTime.utc(2026, 10, 12, 9),
      completedAt: DateTime.utc(2026, 10, 12, 9, 30),
    );
    final reversed = DispatchHistoryRecord(
      incidentId: 'invalid',
      status: 'closed',
      completion: DispatchCompletionState.completed,
      createdAt: DateTime.utc(2026, 10, 12, 10),
      completedAt: DateTime.utc(2026, 10, 12, 9),
    );
    final open = DispatchHistoryRecord(
      incidentId: 'open',
      status: 'in_progress',
      completion: DispatchCompletionState.notCompleted,
      createdAt: DateTime.utc(2026, 10, 12, 9),
      completedAt: DateTime.utc(2026, 10, 12, 9, 30),
    );
    expect(valid.caseElapsed, const Duration(minutes: 30));
    expect(reversed.caseElapsed, isNull);
    expect(open.caseElapsed, isNull);
  });

  testWidgets('Missing timings are reported unavailable', (tester) async {
    await tester.pumpWidget(screen([completed]));
    expect(find.text('Average case elapsed (created to completed): Unavailable'),
        findsOneWidget);
    expect(find.textContaining('Valid timestamp pairs: 0 of 1'),
        findsOneWidget);
  });
}
