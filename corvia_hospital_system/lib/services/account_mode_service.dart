import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AccountModeAccess {
  const AccountModeAccess({
    required this.signedIn,
    required this.profileFound,
    required this.authUserId,
    required this.profileId,
    required this.role,
    required this.isActive,
    required this.hasDoctorProfile,
    required this.hasNurseProfile,
    required this.hasPharmacistProfile,
    required this.hasLabWorkerProfile,
    required this.hasPatientProfile,
    required this.canSwitchDoctorPatient,
    required this.canSwitchNursePatient,
    required this.canSwitchClinicalPatient,
    required this.canSwitchLabPatient,
  });

  const AccountModeAccess.signedOut()
      : signedIn = false,
        profileFound = false,
        authUserId = '',
        profileId = '',
        role = '',
        isActive = true,
        hasDoctorProfile = false,
        hasNurseProfile = false,
        hasPharmacistProfile = false,
        hasLabWorkerProfile = false,
        hasPatientProfile = false,
        canSwitchDoctorPatient = false,
        canSwitchNursePatient = false,
        canSwitchClinicalPatient = false,
        canSwitchLabPatient = false;

  final bool signedIn;
  final bool profileFound;

  final String authUserId;
  final String profileId;
  final String role;

  final bool isActive;

  final bool hasDoctorProfile;
  final bool hasNurseProfile;
  final bool hasPharmacistProfile;
  final bool hasLabWorkerProfile;
  final bool hasPatientProfile;

  final bool canSwitchDoctorPatient;
  final bool canSwitchNursePatient;
  final bool canSwitchClinicalPatient;
  final bool canSwitchLabPatient;

  bool get isHospitalAdmin {
    return {
      'hospital_admin',
      'hospitaladmin',
      'admin',
    }.contains(role);
  }

  bool get isReception {
    return {
      'reception',
      'receptionist',
      'reception_staff',
      'receptionist_staff',
    }.contains(role);
  }

  bool get isDoctorRole {
    return {
      'doctor',
      'medical_doctor',
      'general_practitioner',
      'gp',
    }.contains(role);
  }

  bool get isSpecialistRole {
    return {
      'specialist',
      'medical_specialist',
      'specialist_doctor',
    }.contains(role);
  }

  bool get isNurseRole {
    return {
      'nurse',
      'registered_nurse',
      'staff_nurse',
      'nursing_staff',
    }.contains(role);
  }

  bool get isPharmacistRole {
    return {
      'pharmacist',
      'hospital_pharmacist',
      'pharmacy_staff',
      'pharmacy',
    }.contains(role);
  }

  bool get isPatientRole {
    return {
      'patient',
      'member',
      'user',
    }.contains(role);
  }

  bool get hasDoctorAccess {
    return hasDoctorProfile || isDoctorRole || isSpecialistRole;
  }

  bool get hasNurseAccess {
    return hasNurseProfile || isNurseRole;
  }

  bool get hasPharmacistAccess {
    return hasPharmacistProfile || isPharmacistRole;
  }

  bool get hasPatientAccess {
    return hasPatientProfile;
  }

  bool get hasLabAccess {
    return hasLabWorkerProfile ||
        {
          'lab_worker',
          'lab_admin',
          'private_lab_admin',
          'private_lab_administrator'
        }.contains(role);
  }

  bool get hasClinicalStaffAccess {
    return hasDoctorAccess || hasNurseAccess || hasPharmacistAccess;
  }

  factory AccountModeAccess.fromMap(
    Map<String, dynamic> map,
  ) {
    return AccountModeAccess(
      signedIn: _boolValue(
        map['signed_in'],
        fallback: true,
      ),
      profileFound: _boolValue(
        map['profile_found'],
      ),
      authUserId: _stringValue(
        map['auth_user_id'],
      ),
      profileId: _stringValue(
        map['profile_id'],
      ),
      role: _normaliseRole(
        map['role'],
      ),
      isActive: _boolValue(
        map['is_active'],
        fallback: true,
      ),
      hasDoctorProfile: _boolValue(
        map['has_doctor_profile'],
      ),
      hasNurseProfile: _boolValue(
        map['has_nurse_profile'],
      ),
      hasPharmacistProfile: _boolValue(
        map['has_pharmacist_profile'],
      ),
      hasLabWorkerProfile: _boolValue(
        map['has_lab_worker_profile'],
      ),
      hasPatientProfile: _boolValue(
        map['has_patient_profile'],
      ),
      canSwitchDoctorPatient: _boolValue(
        map['can_switch_doctor_patient'],
      ),
      canSwitchNursePatient: _boolValue(
        map['can_switch_nurse_patient'],
      ),
      canSwitchClinicalPatient: _boolValue(
        map['can_switch_clinical_patient'],
      ),
      canSwitchLabPatient: _boolValue(
        map['can_switch_lab_patient'],
      ),
    );
  }

  static String _stringValue(
    dynamic value,
  ) {
    return value?.toString().trim() ?? '';
  }

  static bool _boolValue(
    dynamic value, {
    bool fallback = false,
  }) {
    if (value == null) {
      return fallback;
    }

    if (value is bool) {
      return value;
    }

    if (value is num) {
      return value != 0;
    }

    final text = value.toString().trim().toLowerCase();

    if ({
      'true',
      '1',
      'yes',
      'y',
    }.contains(text)) {
      return true;
    }

    if ({
      'false',
      '0',
      'no',
      'n',
    }.contains(text)) {
      return false;
    }

    return fallback;
  }

  static String _normaliseRole(
    dynamic value,
  ) {
    return value
            ?.toString()
            .trim()
            .toLowerCase()
            .replaceAll(
              '-',
              '_',
            )
            .replaceAll(
              ' ',
              '_',
            ) ??
        '';
  }
}

class AccountModeService {
  AccountModeService._();

  static final SupabaseClient _supabase = Supabase.instance.client;

  static Future<AccountModeAccess> current() async {
    final user = _supabase.auth.currentUser;

    if (user == null) {
      return const AccountModeAccess.signedOut();
    }

    try {
      final response = await _supabase.rpc(
        'corvia_current_mode_access',
      );

      return _parseResponse(response);
    } catch (error, stackTrace) {
      // Keep login usable while an older server build still references the
      // removed public.nurses table. The database RPC remains authoritative
      // whenever it succeeds; this direct lookup is only a compatibility path.
      debugPrint(
        'Mode access RPC failed; using direct relationship lookup: '
        '$error\n$stackTrace',
      );

      return _loadDirect(user);
    }
  }

  static AccountModeAccess _parseResponse(
    dynamic response,
  ) {
    if (response == null) {
      throw StateError(
        'Corvia mode access RPC returned no data.',
      );
    }

    if (response is Map<String, dynamic>) {
      return AccountModeAccess.fromMap(
        response,
      );
    }

    if (response is Map) {
      return AccountModeAccess.fromMap(
        Map<String, dynamic>.from(
          response,
        ),
      );
    }

    if (response is List && response.isNotEmpty) {
      final first = response.first;

      if (first is Map<String, dynamic>) {
        return AccountModeAccess.fromMap(
          first,
        );
      }

      if (first is Map) {
        return AccountModeAccess.fromMap(
          Map<String, dynamic>.from(
            first,
          ),
        );
      }
    }

    throw StateError(
      'Corvia mode access RPC returned an unsupported response.',
    );
  }

  static Future<AccountModeAccess> _loadDirect(
    User user,
  ) async {
    final rawProfile = await _supabase
        .from('profiles')
        .select()
        .eq('user_id', user.id)
        .maybeSingle();

    if (rawProfile == null) {
      return AccountModeAccess(
        signedIn: true,
        profileFound: false,
        authUserId: user.id,
        profileId: '',
        role: '',
        isActive: true,
        hasDoctorProfile: false,
        hasNurseProfile: false,
        hasPharmacistProfile: false,
        hasLabWorkerProfile: false,
        hasPatientProfile: false,
        canSwitchDoctorPatient: false,
        canSwitchNursePatient: false,
        canSwitchClinicalPatient: false,
        canSwitchLabPatient: false,
      );
    }

    final profile = Map<String, dynamic>.from(rawProfile);
    final legacyProfileId = _stringValue(profile['id']);
    final canonicalProfileId = _stringValue(profile['user_id']).isNotEmpty
        ? _stringValue(profile['user_id'])
        : user.id;
    final profileCandidates = <String>{
      user.id,
      legacyProfileId,
    }..removeWhere((value) => value.trim().isEmpty);

    final relationships = await Future.wait<bool>([
      _recordExists('doctors', profileCandidates),
      _recordExists('hospital_nurses', profileCandidates),
      _recordExists('pharmacists', profileCandidates),
      _recordExists('lab_worker_accounts', profileCandidates),
      _recordExists('patients', profileCandidates),
    ]);

    final hasDoctorProfile = relationships[0];
    final hasNurseProfile = relationships[1];
    final hasPharmacistProfile = relationships[2];
    final hasLabWorkerProfile = relationships[3];
    final hasPatientProfile = relationships[4];
    final hasClinicalProfile =
        hasDoctorProfile || hasNurseProfile || hasPharmacistProfile;

    return AccountModeAccess(
      signedIn: true,
      profileFound: true,
      authUserId: user.id,
      profileId:
          legacyProfileId.isNotEmpty ? legacyProfileId : canonicalProfileId,
      role: _normaliseRole(profile['role'] ?? profile['user_type']),
      isActive: profile['is_active'] != false,
      hasDoctorProfile: hasDoctorProfile,
      hasNurseProfile: hasNurseProfile,
      hasPharmacistProfile: hasPharmacistProfile,
      hasLabWorkerProfile: hasLabWorkerProfile,
      hasPatientProfile: hasPatientProfile,
      canSwitchDoctorPatient: hasDoctorProfile && hasPatientProfile,
      canSwitchNursePatient: hasNurseProfile && hasPatientProfile,
      canSwitchClinicalPatient: hasClinicalProfile && hasPatientProfile,
      canSwitchLabPatient: hasLabWorkerProfile && hasPatientProfile,
    );
  }

  static Future<bool> _recordExists(
    String table,
    Set<String> profileCandidates,
  ) async {
    if (profileCandidates.isEmpty) {
      return false;
    }

    try {
      final response = await _supabase
          .from(table)
          .select('profile_id, is_active')
          .inFilter('profile_id', profileCandidates.toList())
          .limit(20);

      return response.any(
        (record) => record['is_active'] != false,
      );
    } catch (error) {
      debugPrint(
        'Direct mode relationship lookup failed for $table: $error',
      );

      return false;
    }
  }

  static String _stringValue(dynamic value) {
    return value?.toString().trim() ?? '';
  }

  static String _normaliseRole(dynamic value) {
    return value
            ?.toString()
            .trim()
            .toLowerCase()
            .replaceAll('-', '_')
            .replaceAll(' ', '_') ??
        '';
  }
}
