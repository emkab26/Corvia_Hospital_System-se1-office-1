import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

enum CorviaStaffMode {
  none,
  hospitalAdmin,
  reception,
  doctor,
  nurse,
  pharmacist,
}

class CorviaAccountAccess {
  const CorviaAccountAccess({
    required this.userId,
    required this.profileId,
    required this.role,
    required this.isActive,
    required this.profileFound,
    required this.hasDoctorProfile,
    required this.hasPharmacistProfile,
    required this.hasPatientProfile,
  });

  const CorviaAccountAccess.signedOut()
      : userId = '',
        profileId = '',
        role = '',
        isActive = true,
        profileFound = false,
        hasDoctorProfile = false,
        hasPharmacistProfile = false,
        hasPatientProfile = false;

  final String userId;
  final String profileId;
  final String role;

  final bool isActive;
  final bool profileFound;

  final bool hasDoctorProfile;
  final bool hasPharmacistProfile;
  final bool hasPatientProfile;

  bool get isSignedIn => userId.trim().isNotEmpty;

  bool get isHospitalAdmin {
    return role == 'hospital_admin' ||
        role == 'hospitaladmin' ||
        role == 'admin';
  }

  bool get isReception {
    return role == 'reception' ||
        role == 'receptionist' ||
        role == 'reception_staff' ||
        role == 'receptionist_staff';
  }

  bool get isDoctor {
    return role == 'doctor' ||
        role == 'medical_doctor' ||
        role == 'general_practitioner' ||
        role == 'gp';
  }

  bool get isSpecialist {
    return role == 'specialist' ||
        role == 'medical_specialist' ||
        role == 'specialist_doctor';
  }

  bool get isNurse {
    return role == 'nurse' ||
        role == 'registered_nurse' ||
        role == 'staff_nurse' ||
        role == 'nursing_staff';
  }

  bool get isPharmacist {
    return role == 'pharmacist' ||
        role == 'registered_pharmacist' ||
        role == 'pharmacy_staff' ||
        role == 'pharmacist_staff';
  }

  bool get isPatient {
    return role == 'patient' || role == 'member' || role == 'user';
  }

  bool get hasDoctorAccess {
    return isDoctor || isSpecialist || hasDoctorProfile;
  }

  bool get hasNurseAccess {
    return isNurse;
  }

  bool get hasPharmacistAccess {
    return isPharmacist || hasPharmacistProfile;
  }

  bool get hasClinicalStaffAccess {
    return hasDoctorAccess || hasNurseAccess || hasPharmacistAccess;
  }

  bool get hasPatientAccess {
    return isPatient || hasPatientProfile;
  }

  bool get hasDualModeAccess {
    return hasClinicalStaffAccess && hasPatientProfile;
  }

  CorviaStaffMode get staffMode {
    if (isHospitalAdmin) {
      return CorviaStaffMode.hospitalAdmin;
    }

    if (isReception) {
      return CorviaStaffMode.reception;
    }

    if (hasNurseAccess) {
      return CorviaStaffMode.nurse;
    }

    if (hasPharmacistAccess) {
      return CorviaStaffMode.pharmacist;
    }

    if (hasDoctorAccess) {
      return CorviaStaffMode.doctor;
    }

    return CorviaStaffMode.none;
  }
}

class AccountAccessService {
  AccountAccessService._();

  static final AccountAccessService instance = AccountAccessService._();

  final SupabaseClient _supabase = Supabase.instance.client;

  String normaliseRole(dynamic value) {
    return value
            ?.toString()
            .trim()
            .toLowerCase()
            .replaceAll('-', '_')
            .replaceAll(' ', '_') ??
        '';
  }

  String _firstRoleValue(
    Map<String, dynamic> profile,
  ) {
    final role = profile['role']?.toString().trim();

    if (role != null && role.isNotEmpty) {
      return normaliseRole(role);
    }

    return normaliseRole(
      profile['user_type'],
    );
  }

  Future<Map<String, dynamic>?> _loadProfile(
    String userId,
  ) async {
    final result = await _supabase
        .from('profiles')
        .select()
        .eq('user_id', userId)
        .maybeSingle();

    if (result == null) {
      return null;
    }

    return Map<String, dynamic>.from(
      result,
    );
  }

  Future<bool> _recordExists({
    required String table,
    required String authUserId,
    required String legacyProfileId,
  }) async {
    final candidates = <String>{
      authUserId.trim(),
      legacyProfileId.trim(),
    }..removeWhere(
        (value) => value.isEmpty,
      );

    for (final candidate in candidates) {
      try {
        final response = await _supabase
            .from(table)
            .select('id')
            .eq('profile_id', candidate)
            .limit(1);

        final rows = response as List<dynamic>;

        if (rows.isNotEmpty) {
          return true;
        }
      } catch (error) {
        debugPrint(
          'Could not check $table.profile_id '
          'using $candidate: $error',
        );
      }
    }

    return false;
  }

  Future<CorviaAccountAccess> load() async {
    final user = _supabase.auth.currentUser;

    if (user == null) {
      return const CorviaAccountAccess.signedOut();
    }

    final profile = await _loadProfile(
      user.id,
    );

    if (profile == null) {
      return CorviaAccountAccess(
        userId: user.id,
        profileId: user.id,
        role: '',
        isActive: true,
        profileFound: false,
        hasDoctorProfile: false,
        hasPharmacistProfile: false,
        hasPatientProfile: false,
      );
    }

    /*
     * profiles.user_id is the current canonical profile key.
     *
     * The id fallback remains temporarily for older Corvia
     * database builds that may still contain profiles.id.
     */
    final legacyProfileId = profile['id']?.toString().trim() ?? '';

    final canonicalProfileId = profile['user_id']?.toString().trim() ?? user.id;

    final hasDoctorProfile = await _recordExists(
      table: 'doctors',
      authUserId: user.id,
      legacyProfileId: legacyProfileId,
    );

    final hasPharmacistProfile = await _recordExists(
      table: 'pharmacists',
      authUserId: user.id,
      legacyProfileId: legacyProfileId,
    );

    final hasPatientProfile = await _recordExists(
      table: 'patients',
      authUserId: user.id,
      legacyProfileId: legacyProfileId,
    );

    return CorviaAccountAccess(
      userId: user.id,
      profileId: canonicalProfileId,
      role: _firstRoleValue(profile),
      isActive: profile['is_active'] != false,
      profileFound: true,
      hasDoctorProfile: hasDoctorProfile,
      hasPharmacistProfile: hasPharmacistProfile,
      hasPatientProfile: hasPatientProfile,
    );
  }
}
