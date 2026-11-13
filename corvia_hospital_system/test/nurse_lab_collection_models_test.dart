import 'package:flutter_test/flutter_test.dart';

import 'package:mycorvia/services/nurse_service.dart';

void main() {
  group('NurseLabCollectionOrder', () {
    test('normalises an order returned by the collection queue', () {
      final order = NurseLabCollectionOrder.fromJson({
        'lab_result_id': 'lab-order-1',
        'patient_id': 'patient-1',
        'test_name': ' Full Blood Count ',
        'status': 'Awaiting Collection',
        'created_at': '2026-09-15T08:00:00.000Z',
      });

      expect(order.labResultId, 'lab-order-1');
      expect(order.patientId, 'patient-1');
      expect(order.testName, 'Full Blood Count');
      expect(order.status, 'awaiting_collection');
      expect(order.createdAt, DateTime.parse('2026-09-15T08:00:00.000Z'));
    });

    test('uses a safe test-name fallback for incomplete data', () {
      final order = NurseLabCollectionOrder.fromJson({
        'lab_result_id': 'lab-order-1',
        'patient_id': 'patient-1',
      });

      expect(order.testName, 'Laboratory test');
      expect(order.status, '');
      expect(order.createdAt, isNull);
    });
  });

  test('NurseCollectedSpecimen reads the database-created label', () {
    final specimen = NurseCollectedSpecimen.fromJson({
      'container_id': 'container-1',
      'container_code': 'CVS-20260915-ABC1234567',
      'specimen_type': 'Serum',
    });

    expect(specimen.containerId, 'container-1');
    expect(specimen.containerCode, 'CVS-20260915-ABC1234567');
    expect(specimen.specimenType, 'Serum');
  });
}
