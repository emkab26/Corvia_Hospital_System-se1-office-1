
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mycorvia/pages/dispatch/incident_accountability_panel.dart';

void main() {
  Widget screen({
    List<Map<String, dynamic>> events = const [],
    List<Map<String, dynamic>> assignments = const [],
    bool olderEvents = false,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: IncidentAccountabilityPanel(
            incidentId: 'demo-incident',
            events: events,
            assignments: assignments,
            olderEvents: olderEvents,
            snapshotVerifiedAt: DateTime.utc(
              2026,
              10,
              12,
              9,
            ),
          ),
        ),
      ),
    );
  }

  testWidgets(
    'Empty audit does not invent exceptions',
    (tester) async {
      await tester.pumpWidget(screen());

      expect(
        find.text('Incident accountability'),
        findsOneWidget,
      );

      expect(
        find.text('0 exception-related events'),
        findsOneWidget,
      );

      expect(
        find.text(
          'No audit events were returned in this snapshot.',
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'Shows recorded event and assignment attention',
    (tester) async {
      await tester.pumpWidget(
        screen(
          events: [
            {
              'command': 'exception',
              'detail': 'Crew reported unsafe scene',
              'actor_role': 'crew',
              'actor_id': 'demo-user',
              'occurred_at': '2026-10-12T09:00:00Z',
              'recorded_at': '2026-10-12T09:01:00Z',
            },
          ],
          assignments: [
            {
              'unit': 'Demo ambulance',
              'state': 'on_scene',
              'attention': 'unsafe_scene',
              'active': true,
              'overdue': false,
            },
          ],
        ),
      );

      expect(
        find.text('1 exception-related events'),
        findsOneWidget,
      );

      expect(
        find.text('1 active assignment alerts'),
        findsOneWidget,
      );

      expect(
        find.textContaining('Crew reported unsafe scene'),
        findsOneWidget,
      );

      expect(
        find.textContaining(
          'Demo ambulance · unsafe_scene',
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'Older events are labelled as incomplete history',
    (tester) async {
      await tester.pumpWidget(
        screen(olderEvents: true),
      );

      expect(
        find.textContaining(
          'outside this loaded window',
        ),
        findsOneWidget,
      );
    },
  );
}
