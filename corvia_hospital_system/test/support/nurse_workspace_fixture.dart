import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:mycorvia/services/nurse_service.dart';

Map<String, dynamic> payload(
        {bool duplicate = false, bool secondPatient = false}) =>
    {
      'context': {
        'signed_in': true,
        'profile_found': true,
        'is_nurse': true,
        'is_active': true,
        'hospital_found': true,
        'profile_id': 'profile-row',
        'nurse_user_id': 'auth-user',
        'hospital_id': 'hospital-a',
        'hospital_name': 'Hospital A',
        'nurse_name': 'Test Nurse',
        'role': 'nurse',
      },
      'assignments': [
        assignment('assignment-a', 'patient-a'),
        if (duplicate) assignment('assignment-a2', 'patient-a'),
        if (secondPatient) assignment('assignment-b', 'patient-b'),
      ],
      'tasks': [],
      'patients': [
        {
          'id': 'patient-a',
          'patient_number': 'PAT-001',
          'first_name': 'Alex',
          'surname': 'Patient',
          'phone': '0123456789',
          'email': 'alex@example.test',
          'id_number': 'SYNTHETIC-ID',
          'date_of_birth': '1990-03-12',
          'medical_aid_provider': 'Test provider',
          'medical_aid_member_number': 'MEMBER-1',
          'medical_aid_plan': 'Test plan',
        },
        if (secondPatient)
          {
            'id': 'patient-b',
            'patient_number': 'PAT-002',
            'first_name': 'Other',
            'surname': 'Patient'
          },
      ],
      'wards': [
        {
          'id': 'ward-a',
          'name': 'ICU',
          'code': 'A',
          'floor_name': 'First floor',
          'building_name': 'Main building'
        },
        {
          'id': 'ward-b',
          'name': 'ICU',
          'code': 'B',
          'floor_name': 'Second floor',
          'building_name': 'Main building'
        },
      ],
    };

Map<String, dynamic> assignment(String id, String patient) => {
      'id': id,
      'patient_id': patient,
      'hospital_id': 'hospital-a',
      'nurse_user_id': 'auth-user',
      'ward': 'Existing ward',
      'shift_type': 'Day Shift',
    };

class FakeNurseService extends NurseService {
  FakeNurseService(this.workspace) : super(client: Supabase.instance.client);
  NurseWorkspace workspace;
  Map<String, dynamic>? activeShift;

  @override
  Future<NurseWorkspace> loadWorkspace() async => workspace;

  @override
  Future<Map<String, dynamic>?> loadActiveShift(NurseContext context) async =>
      activeShift;

  @override
  Future<List<Map<String, dynamic>>> loadShiftHistory(NurseContext context,
          {int limit = 15}) async =>
      [];
}
