import 'package:flutter_test/flutter_test.dart';

import 'package:mycorvia/services/account_mode_service.dart';
import 'package:mycorvia/services/supabase_service.dart';

void main() {
  group('Patient first-login bootstrap metadata', () {
    test('accepts only the explicit patient self-registration marker', () {
      expect(
        SupabaseService.isPatientSelfRegistrationMetadata({
          'corvia_registration_type': 'patient_self_registration',
        }),
        isTrue,
      );

      expect(
        SupabaseService.isPatientSelfRegistrationMetadata({
          'corvia_registration_type': ' Patient_Self_Registration ',
        }),
        isTrue,
      );
    });

    test('does not bootstrap an unmarked or staff-labelled account', () {
      expect(
        SupabaseService.isPatientSelfRegistrationMetadata(null),
        isFalse,
      );
      expect(
        SupabaseService.isPatientSelfRegistrationMetadata({}),
        isFalse,
      );
      expect(
        SupabaseService.isPatientSelfRegistrationMetadata({
          'role': 'doctor',
        }),
        isFalse,
      );
    });
  });

  group('Account mode response parsing', () {
    test('normalises role and keeps relationship flags authoritative', () {
      final access = AccountModeAccess.fromMap({
        'signed_in': true,
        'profile_found': true,
        'auth_user_id': 'auth-user-id',
        'profile_id': 'profile-id',
        'role': ' Registered Nurse ',
        'is_active': true,
        'has_doctor_profile': false,
        'has_nurse_profile': true,
        'has_pharmacist_profile': false,
        'has_patient_profile': true,
        'can_switch_doctor_patient': false,
        'can_switch_nurse_patient': true,
        'can_switch_clinical_patient': true,
      });

      expect(access.role, 'registered_nurse');
      expect(access.hasNurseAccess, isTrue);
      expect(access.hasPatientAccess, isTrue);
      expect(access.canSwitchNursePatient, isTrue);
      expect(access.canSwitchClinicalPatient, isTrue);
    });
  });
}
