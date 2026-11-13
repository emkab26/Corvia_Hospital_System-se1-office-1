
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mycorvia/pages/dispatch/completion_review_panel.dart';

void main() {
  Widget makeScreen(
    Map<String, dynamic> snapshot, {
    bool isStale = false,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: CompletionReviewPanel(
            snapshot: snapshot,
            isStale: isStale,
          ),
        ),
      ),
    );
  }

  testWidgets(
    'Displays unresolved safety exceptions',
    (tester) async {
      await tester.pumpWidget(
        makeScreen({
          'incident_number': 'EMS-100',
          'status': 'On Scene',
          'dispatch_state': 'escalated',
          'destination': null,
          'primary_overdue': true,
          'units': [
            {
              'unit_number': 'AMB-01',
            },
          ],
          'exceptions': [
            {
              'id': '51',
              'kind': 'unsafe_scene',
            },
          ],
        }),
      );

      expect(
        find.text('Incident completion review'),
        findsOneWidget,
      );

      expect(
        find.text('Incident: EMS-100'),
        findsOneWidget,
      );

      expect(
        find.text('Unresolved exception entries: 1'),
        findsOneWidget,
      );

      expect(
        find.text('PRIMARY ACKNOWLEDGEMENT OVERDUE'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'Recorded destination does not prove acceptance',
    (tester) async {
      await tester.pumpWidget(
        makeScreen({
          'incident_number': 'EMS-101',
          'status': 'Transporting',
          'dispatch_state': 'active',
          'destination': {
            'facility_id': '31',
          },
          'exceptions': [],
          'units': [
            {
              'unit_number': 'AMB-02',
            },
          ],
          'primary_overdue': false,
        }),
      );

      expect(
        find.text(
          'Destination recorded - acceptance not verified',
        ),
        findsOneWidget,
      );

      expect(
        find.textContaining(
          'Receiving acknowledgement is not verified',
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'Missing information is not treated as clear',
    (tester) async {
      await tester.pumpWidget(
        makeScreen({
          'incident_number': 'EMS-102',
          'status': 'Unknown',
        }),
      );

      expect(
        find.text('Unresolved exceptions: Not verified'),
        findsOneWidget,
      );

      expect(
        find.text('Team units: Not verified'),
        findsOneWidget,
      );

      expect(
        find.text(
          'Primary acknowledgement status not verified',
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'Closed status alone does not prove completion',
    (tester) async {
      await tester.pumpWidget(
        makeScreen({
          'incident_number': 'EMS-103',
          'status': 'Closed',
          'dispatch_state': 'completed',
          'destination': {
            'facility_id': '31',
          },
          'exceptions': [],
          'units': [
            {
              'unit_number': 'AMB-03',
            },
          ],
          'primary_overdue': false,
        }),
      );

      expect(
        find.textContaining(
          'Completion is not verified by this panel',
        ),
        findsOneWidget,
      );

      expect(
        find.text('Mark incident completed'),
        findsNothing,
      );
    },
  );

  testWidgets(
    'Stale snapshot displays warning',
    (tester) async {
      await tester.pumpWidget(
        makeScreen(
          {
            'incident_number': 'EMS-104',
          },
          isStale: true,
        ),
      );

      expect(
        find.textContaining(
          'latest incident state could not be',
        ),
        findsOneWidget,
      );
    },
  );
}
