
import 'package:flutter_test/flutter_test.dart';

import 'package:mycorvia/pages/dispatch/dispatch_history_report_panel.dart';
import 'package:mycorvia/pages/dispatch/dispatch_report_integrity.dart';

void main() {
  test(
    'Empty result cannot imply complete hospital history',
    () {
      final result = DispatchReportIntegrity.inspect([]);

      expect(result.countedRecordCount, 0);
      expect(result.canPublishScopedCounts, isFalse);
      expect(result.findings.first, contains('not confirmed'));
    },
  );

  test(
    'Confirmed completion is separate from raw closed status',
    () {
      final result = DispatchReportIntegrity.inspect([
        const DispatchHistoryRecord(
          incidentId: 'case-1',
          status: 'closed',
          completion: DispatchCompletionState.unknown,
        ),
        const DispatchHistoryRecord(
          incidentId: 'case-2',
          status: 'in_progress',
          completion: DispatchCompletionState.notCompleted,
        ),
      ]);

      expect(result.confirmedCompletedCount, 0);
      expect(result.confirmedNotCompletedCount, 1);
      expect(result.unknownCompletionCount, 1);
    },
  );

  test(
    'All records with duplicate IDs are excluded',
    () {
      final result = DispatchReportIntegrity.inspect([
        const DispatchHistoryRecord(
          incidentId: 'CASE-1',
          status: 'closed',
          completion: DispatchCompletionState.completed,
        ),
        const DispatchHistoryRecord(
          incidentId: 'case-1',
          status: 'in_progress',
          completion: DispatchCompletionState.notCompleted,
        ),
        const DispatchHistoryRecord(
          incidentId: 'case-2',
          status: 'in_progress',
          completion: DispatchCompletionState.notCompleted,
        ),
      ]);

      expect(result.originalRecordCount, 3);
      expect(result.countedRecordCount, 1);
      expect(result.excludedRecordCount, 2);
      expect(result.duplicateIncidentIds, ['case-1']);
      expect(result.confirmedCompletedCount, 0);
      expect(result.canPublishScopedCounts, isFalse);
    },
  );

  test(
    'Missing identity is excluded',
    () {
      final result = DispatchReportIntegrity.inspect([
        const DispatchHistoryRecord(
          incidentId: ' ',
          status: 'closed',
          completion: DispatchCompletionState.completed,
        ),
        const DispatchHistoryRecord(
          incidentId: 'case-3',
          status: 'open',
          completion: DispatchCompletionState.notCompleted,
        ),
      ]);

      expect(result.invalidIdentityCount, 1);
      expect(result.countedRecordCount, 1);
      expect(result.hasIdentityProblems, isTrue);
    },
  );

  test(
    'Missing outcome and timestamps are reported',
    () {
      final result = DispatchReportIntegrity.inspect([
        const DispatchHistoryRecord(
          incidentId: 'case-4',
          status: 'closed',
          completion: DispatchCompletionState.completed,
        ),
      ]);

      expect(result.confirmedCompletedCount, 1);
      expect(result.missingOutcomeCount, 1);
      expect(result.missingTimingCount, 1);
      expect(result.averageCaseElapsed, isNull);
      expect(result.hasReportingGaps, isTrue);
    },
  );

  test(
    'Reversed timestamps are excluded from average duration',
    () {
      final result = DispatchReportIntegrity.inspect([
        DispatchHistoryRecord(
          incidentId: 'case-5',
          status: 'closed',
          completion: DispatchCompletionState.completed,
          outcome: 'Received',
          createdAt: DateTime.utc(2026, 10, 12, 10),
          completedAt: DateTime.utc(2026, 10, 12, 9),
        ),
        DispatchHistoryRecord(
          incidentId: 'case-6',
          status: 'closed',
          completion: DispatchCompletionState.completed,
          outcome: 'Received',
          createdAt: DateTime.utc(2026, 10, 12, 9),
          completedAt: DateTime.utc(2026, 10, 12, 9, 30),
        ),
      ]);

      expect(result.invalidTimingCount, 1);
      expect(result.validTimingCount, 1);
      expect(
        result.averageCaseElapsed,
        const Duration(minutes: 30),
      );
    },
  );

  test(
    'Complete and unique scope permits scoped counts',
    () {
      final result = DispatchReportIntegrity.inspect(
        [
          const DispatchHistoryRecord(
            incidentId: 'case-7',
            status: 'closed',
            completion: DispatchCompletionState.completed,
            outcome: 'Handover confirmed',
          ),
        ],
        serverConfirmedComplete: true,
      );

      expect(result.canPublishScopedCounts, isTrue);
      expect(result.confirmedCompletedCount, 1);
      expect(result.missingTimingCount, 1);
      expect(result.hasReportingGaps, isTrue);
    },
  );
}
