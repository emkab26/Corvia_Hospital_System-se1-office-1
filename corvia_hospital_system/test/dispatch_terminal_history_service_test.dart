import 'package:flutter_test/flutter_test.dart';

import 'package:mycorvia/models/dispatch/incident_history.dart';
import 'package:mycorvia/pages/dispatch/dispatch_history_report_panel.dart';
import 'package:mycorvia/services/dispatch_terminal_history_service.dart';

IncidentHistory ledger(String id, String finalEvent) {
  final terminalStatus = finalEvent == 'resolved' ? 'resolved' : 'cancelled';
  final firstStatus = finalEvent == 'resolved' ? 'in_progress' : 'pending';
  final events = <Map<String, dynamic>>[
    {
      'version': '1',
      'event_type': 'created',
      'recorded_at': '2026-10-12T08:00:00Z',
      'status': 'pending',
      'previous_status': null,
    },
    if (finalEvent == 'resolved')
      {
        'version': '2',
        'event_type': 'claimed',
        'recorded_at': '2026-10-12T08:05:00Z',
        'status': 'in_progress',
        'previous_status': 'pending',
      },
    {
      'version': finalEvent == 'resolved' ? '3' : '2',
      'event_type': finalEvent,
      'recorded_at': '2026-10-12T08:30:00Z',
      'status': terminalStatus,
      'previous_status': firstStatus,
    },
  ];
  return IncidentHistory.fromMap(
    {'incident_id': id, 'events': events},
    expectedIncidentId: id,
  );
}

void main() {
  test('Verified ledger resolution is completed incident, not handover', () {
    final record = SupabaseDispatchTerminalHistoryService.recordFromLedger(
      incidentId: '42',
      databaseStatus: 'resolved',
      history: ledger('42', 'resolved'),
    );
    expect(record.completion, DispatchCompletionState.completed);
    expect(record.caseElapsed, const Duration(minutes: 30));
    expect(record.outcome, isNull);
  });

  test('Cancellation is never counted as completed', () {
    final record = SupabaseDispatchTerminalHistoryService.recordFromLedger(
      incidentId: '43',
      databaseStatus: 'cancelled',
      history: ledger('43', 'cancelled'),
    );
    expect(record.completion, DispatchCompletionState.notCompleted);
    expect(record.caseElapsed, isNull);
    expect(record.outcome, isNull);
  });

  test('Status inconsistent with authorised ledger fails closed', () {
    expect(
      () => SupabaseDispatchTerminalHistoryService.recordFromLedger(
        incidentId: '44',
        databaseStatus: 'resolved',
        history: ledger('44', 'cancelled'),
      ),
      throwsFormatException,
    );
  });

  test('Different incident ledger identity is rejected', () {
    expect(
      () => SupabaseDispatchTerminalHistoryService.recordFromLedger(
        incidentId: '55',
        databaseStatus: 'resolved',
        history: ledger('56', 'resolved'),
      ),
      throwsFormatException,
    );
  });
}
