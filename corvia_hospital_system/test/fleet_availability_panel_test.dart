
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mycorvia/pages/dispatch/fleet_availability_panel.dart';

void main() {
  Widget makeScreen({
    required List<Map<String, dynamic>> units,
    required bool canAct,
    required void Function(Map<String, dynamic>) onPrimary,
    List<Map<String, dynamic>> assignments = const [],
  }) {
    return MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: FleetAvailabilityPanel(
            units: units,
            assignments: assignments,
            canAct: canAct,
            hasReviewReason: false,
            onReviewReadiness: (_) {},
            onAssignPrimary: onPrimary,
            onAssignBackup: (_) {},
          ),
        ),
      ),
    );
  }

  testWidgets(
    'Ineligible ambulance cannot be assigned',
    (tester) async {
      var assigned = false;

      await tester.pumpWidget(
        makeScreen(
          units: [
            {
              'id': 'unit-a',
              'version': 'v1',
              'label': 'Ambulance A',
              'reason': 'Readiness expired',
            },
          ],
          canAct: true,
          onPrimary: (_) {
            assigned = true;
          },
        ),
      );

      expect(
        find.text('Not eligible: Readiness expired'),
        findsOneWidget,
      );

      final button = tester.widget<FilledButton>(
        find.ancestor(
          of: find.text('Assign primary'),
          matching: find.byType(FilledButton),
        ),
      );

      expect(button.onPressed, isNull);
      expect(assigned, isFalse);
    },
  );

  testWidgets(
    'Eligible ambulance uses existing assignment callback',
    (tester) async {
      Map<String, dynamic>? selected;

      await tester.pumpWidget(
        makeScreen(
          units: [
            {
              'id': 'unit-b',
              'version': 'v2',
              'label': 'Ambulance B',
              'reason': 'Eligible',
            },
          ],
          canAct: true,
          onPrimary: (unit) {
            selected = unit;
          },
        ),
      );

      await tester.tap(
        find.text('Assign primary'),
      );

      expect(selected?['id'], 'unit-b');
      expect(selected?['version'], 'v2');
    },
  );

  testWidgets(
    'Existing active primary prevents another primary assignment',
    (tester) async {
      var assigned = false;

      await tester.pumpWidget(
        makeScreen(
          units: [
            {
              'id': 'unit-c',
              'version': 'v3',
              'label': 'Ambulance C',
              'reason': 'Eligible',
            },
          ],
          assignments: [
            {
              'id': 'assignment-1',
              'active': true,
              'purpose': 'primary',
            },
          ],
          canAct: true,
          onPrimary: (_) {
            assigned = true;
          },
        ),
      );

      final button = tester.widget<FilledButton>(
        find.ancestor(
          of: find.text('Assign primary'),
          matching: find.byType(FilledButton),
        ),
      );

      expect(button.onPressed, isNull);
      expect(assigned, isFalse);
    },
  );

  testWidgets(
    'Dispatcher cannot assign during a locked state',
    (tester) async {
      var assigned = false;

      await tester.pumpWidget(
        makeScreen(
          units: [
            {
              'id': 'unit-d',
              'version': 'v4',
              'label': 'Ambulance D',
              'reason': 'Eligible',
            },
          ],
          canAct: false,
          onPrimary: (_) {
            assigned = true;
          },
        ),
      );

      final button = tester.widget<FilledButton>(
        find.ancestor(
          of: find.text('Assign primary'),
          matching: find.byType(FilledButton),
        ),
      );

      expect(button.onPressed, isNull);
      expect(assigned, isFalse);
    },
  );
}
