
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mycorvia/pages/dispatch/gps_location_panel.dart';

void main() {
  Widget makeScreen({
    Map<String, dynamic> incidentLocation = const {},
    List<Map<String, dynamic>> assignments = const [],
  }) {
    return MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: GpsLocationPanel(
            incidentLocation: incidentLocation,
            assignments: assignments,
            snapshotVerifiedAt: DateTime.utc(
              2026,
              10,
              12,
              10,
            ),
          ),
        ),
      ),
    );
  }

  testWidgets(
    'Missing GPS coordinates are not shown as valid',
    (tester) async {
      await tester.pumpWidget(
        makeScreen(),
      );

      expect(
        find.text('GPS & location monitoring'),
        findsOneWidget,
      );

      expect(
        find.text(
          'Coordinates: No valid coordinates recorded',
        ),
        findsOneWidget,
      );

      expect(
        find.text(
          'Freshness: Location unavailable or invalid',
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'Stale unit location shows a warning',
    (tester) async {
      await tester.pumpWidget(
        makeScreen(
          // Valid scene data isolates the stale-unit warning.
          incidentLocation: {
            'latitude': -26.2000,
            'longitude': 28.0400,
            'location_fresh': true,
            'location_source': 'device',
          },
          assignments: [
            {
              'id': 'assignment-1',
              'unit': 'Ambulance 01',
              'crew': 'Alpha',
              'active': true,
              'latitude': -26.2041,
              'longitude': 28.0473,
              'location_fresh': false,
              'location_source': 'device',
              'location_at': '2026-10-12T08:00:00Z',
            },
          ],
        ),
      );

      expect(
        find.text('1 location alerts'),
        findsOneWidget,
      );

      expect(
        find.text(
          'Freshness: STALE - backend flag',
        ),
        findsOneWidget,
      );

      expect(
        find.textContaining(
          'Do not assume this is the current',
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'Backend freshness does not claim live GPS',
    (tester) async {
      await tester.pumpWidget(
        makeScreen(
          incidentLocation: {
            'latitude': -26.2,
            'longitude': 28.04,
            'location_fresh': true,
            'location_source': 'device',
          },
        ),
      );

      expect(
        find.text(
          'Freshness: Backend reports fresh - not live GPS',
        ),
        findsOneWidget,
      );

      expect(
        find.text(
          'Coordinates: -26.20000, 28.04000',
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'Missing freshness flag stays unverified',
    (tester) async {
      await tester.pumpWidget(
        makeScreen(
          incidentLocation: {
            'latitude': -26.2,
            'longitude': 28.04,
          },
        ),
      );

      expect(
        find.text(
          'Freshness: Freshness not verified',
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'Out of range coordinates are rejected',
    (tester) async {
      await tester.pumpWidget(
        makeScreen(
          incidentLocation: {
            'latitude': 120.0,
            'longitude': 28.0,
            'location_fresh': true,
          },
        ),
      );

      expect(
        find.text(
          'Coordinates: No valid coordinates recorded',
        ),
        findsOneWidget,
      );

      expect(
        find.text(
          'Freshness: Location unavailable or invalid',
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'Conflicting backend flags require attention',
    (tester) async {
      await tester.pumpWidget(
        makeScreen(
          incidentLocation: {
            'latitude': -26.2,
            'longitude': 28.04,
            'location_stale': true,
            'location_fresh': true,
          },
        ),
      );

      expect(
        find.text(
          'Freshness: Conflicting backend freshness flags',
        ),
        findsOneWidget,
      );
    },
  );
}
