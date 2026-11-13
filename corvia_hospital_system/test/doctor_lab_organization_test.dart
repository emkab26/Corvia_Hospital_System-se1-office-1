import 'package:flutter_test/flutter_test.dart';
import 'package:mycorvia/services/doctor_clinical_service.dart';

void main() {
  test('DoctorClinicalLabOrganization identifies private laboratories', () {
    final organization = DoctorClinicalLabOrganization.fromJson({
      'id': 'lab-1',
      'name': '  Central Diagnostics  ',
      'lab_type': 'PRIVATE',
    });

    expect(organization.id, 'lab-1');
    expect(organization.name, 'Central Diagnostics');
    expect(organization.labType, 'private');
    expect(organization.typeLabel, 'Private laboratory');
  });

  test('DoctorClinicalLabOrganization uses a safe display fallback', () {
    final organization = DoctorClinicalLabOrganization.fromJson({
      'id': 'lab-2',
      'name': ' ',
      'lab_type': 'hospital',
    });

    expect(organization.name, 'Laboratory');
    expect(organization.typeLabel, 'Hospital laboratory');
  });
}
