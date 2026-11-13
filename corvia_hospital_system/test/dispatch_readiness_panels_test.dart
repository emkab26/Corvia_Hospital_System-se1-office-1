
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mycorvia/pages/dispatch/fleet_readiness_panel.dart';
import 'package:mycorvia/pages/dispatch/crew_readiness_panel.dart';

void main() {
  testWidgets(
    'fleet readiness does not treat missing identity as eligible',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: FleetReadinessPanel(
                units: [
                  {
                    'label': 'Ambulance A',
                    'reason': 'Eligible',
                  },
                ],
              ),
            ),
          ),
        ),
      );

      expect(
        find.text('0 eligible'),
        findsOneWidget,
      );

      expect(
        find.textContaining('Unit identity or version is missing'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'fleet readiness shows the server reason',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: FleetReadinessPanel(
                units: [
                  {
                    'id': 'unit-1',
                    'version': 'version-1',
                    'label': 'Ambulance B',
                    'reason': 'Readiness expired',
                  },
                ],
              ),
            ),
          ),
        ),
      );

      expect(
        find.text('Not verified eligible: Readiness expired'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'crew panel displays recorded assignment status',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: CrewReadinessPanel(
                assignments: [
                  {
                    'crew': 'Crew Alpha',
                    'unit': 'Ambulance A',
                    'state': 'en_route',
                    'purpose': 'primary',
                    'active': true,
                    'crew_available': true,
                  },
                ],
              ),
            ),
          ),
        ),
      );

      expect(
        find.text('Crew Alpha'),
        findsOneWidget,
      );

      expect(
        find.text('State: en route'),
        findsOneWidget,
      );

      expect(
        find.text('Crew availability reported by WS4'),
        findsOneWidget,
      );

      expect(
        find.textContaining('Shift verification: Not provided'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'missing crew availability is not treated as available',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: CrewReadinessPanel(
                assignments: [
                  {
                    'crew': 'Crew Bravo',
                    'unit': 'Ambulance B',
                    'state': 'offered',
                    'purpose': 'backup',
                    'active': true,
                  },
                ],
              ),
            ),
          ),
        ),
      );

      expect(
        find.text('Crew availability not verified'),
        findsOneWidget,
      );

      expect(
        find.text('0 active with crew availability reported'),
        findsOneWidget,
      );
    },
  );
}
