
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mycorvia/pages/dispatch/response_progress_panel.dart';

void main() {
  Widget buildPanel(
    List<Map<String, dynamic>> assignments, {
    String status = 'in_progress',
  }) {
    return MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: ResponseProgressPanel(
            assignments: assignments,
            incidentStatus: status,
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
    'Shows recorded en-route response',
    (tester) async {
      await tester.pumpWidget(
        buildPanel([
          {
            'id': 'assignment-1',
            'unit': 'Ambulance 01',
            'crew': 'Alpha Team',
            'purpose': 'primary',
            'state': 'en_route',
            'active': true,
            'crew_available': true,
            'patient_confirmed': false,
          },
        ]),
      );

      expect(
        find.text('Paramedic response progress'),
        findsOneWidget,
      );

      expect(
        find.text('Ambulance 01'),
        findsOneWidget,
      );

      expect(
        find.text('Crew: Alpha Team'),
        findsOneWidget,
      );

      expect(
        find.text('Status: en route'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'Hospital arrival is not shown as completed handover',
    (tester) async {
      await tester.pumpWidget(
        buildPanel([
          {
            'id': 'assignment-2',
            'unit': 'Ambulance 02',
            'crew': 'Bravo Team',
            'purpose': 'primary',
            'state': 'at_hospital',
            'active': true,
            'patient_confirmed': true,
          },
        ]),
      );

      expect(
        find.textContaining(
          'This does not confirm that the patient was handed over',
        ),
        findsOneWidget,
      );

      expect(
        find.text('Status: at hospital'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'Handover request requires receiver confirmation',
    (tester) async {
      await tester.pumpWidget(
        buildPanel([
          {
            'id': 'assignment-3',
            'unit': 'Ambulance 03',
            'crew': 'Charlie Team',
            'purpose': 'primary',
            'state': 'handover_requested',
            'active': true,
            'patient_confirmed': true,
          },
        ]),
      );

      expect(
        find.text('1 handover requests'),
        findsOneWidget,
      );

      expect(
        find.textContaining(
          'Explicit confirmation by an authorised receiving',
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'Overdue assignment is flagged',
    (tester) async {
      await tester.pumpWidget(
        buildPanel([
          {
            'id': 'assignment-4',
            'unit': 'Ambulance 04',
            'crew': 'Delta Team',
            'purpose': 'backup',
            'state': 'offered',
            'active': true,
            'overdue': true,
            'crew_available': false,
          },
        ]),
      );

      expect(
        find.text('1 overdue'),
        findsOneWidget,
      );

      expect(
        find.textContaining(
          'Acknowledgement is overdue',
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'Empty response snapshot does not invent crew',
    (tester) async {
      await tester.pumpWidget(
        buildPanel([]),
      );

      expect(
        find.textContaining(
          'No response assignments were returned',
        ),
        findsOneWidget,
      );

      expect(
        find.text('0 active'),
        findsOneWidget,
      );
    },
  );
}
