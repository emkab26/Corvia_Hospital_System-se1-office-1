import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mycorvia/pages/paramedic/fleet_live_unit_card.dart';

void main() {
  test('classifies backend readiness without treating every unit as ready', () {
    expect(
        classifyFleetUnit({'status': 'Available', 'readiness_status': 'ready'}),
        FleetUnitFilter.available);
    expect(
        classifyFleetUnit(
            {'status': 'Assigned', 'readiness_status': 'en_route'}),
        FleetUnitFilter.assigned);
    expect(
        classifyFleetUnit(
            {'status': 'Out of Service', 'readiness_status': 'maintenance'}),
        FleetUnitFilter.maintenance);
    expect(
        classifyFleetUnit(
            {'status': 'Available', 'readiness_status': 'off_duty'}),
        FleetUnitFilter.offDuty);
    expect(classifyFleetUnit({'status': 'Available'}), FleetUnitFilter.other);
    expect(
        classifyFleetUnit({
          'status': 'Available',
          'readiness_status': 'ready',
          'is_active': false
        }),
        FleetUnitFilter.other);
  });

  testWidgets('shows authorised real Fleet fields, not sample fuel or driver',
      (tester) async {
    var edits = 0;
    var readinessChanges = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: FleetLiveUnitCard(
            unit: const {
              'unit_id': 7,
              'unit_number': 'COR-EMS-7',
              'registration_number': 'TEST-007',
              'vehicle_type': 'Ambulance',
              'status': 'Available',
              'readiness_status': 'idle',
              'response_capability': 'BLS',
              'base_location': 'Depot 1',
            },
            onEdit: () => edits++,
            onChangeReadiness: () => readinessChanges++,
          ),
        ),
      ),
    ));
    expect(find.text('COR-EMS-7'), findsOneWidget);
    expect(find.text('Ambulance • TEST-007'), findsOneWidget);
    expect(find.text('Readiness: idle'), findsOneWidget);
    expect(find.text('Capability: BLS'), findsOneWidget);
    expect(find.textContaining('Fuel:'), findsNothing);
    await tester.tap(find.text('Edit details'));
    await tester.tap(find.text('Change readiness'));
    expect(edits, 1);
    expect(readinessChanges, 1);
    expect(tester.takeException(), isNull);
  });
}
