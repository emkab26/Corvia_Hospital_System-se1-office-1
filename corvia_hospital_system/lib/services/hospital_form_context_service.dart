import 'package:supabase_flutter/supabase_flutter.dart';

class HospitalFormContextService {
  HospitalFormContextService({
    SupabaseClient? client,
  }) : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Future<HospitalFormLaunchContext> resolve({
    String? hospitalId,
    String? patientId,
    String? admissionId,
    String? contextType,
    String? contextId,
  }) async {
    final user = _client.auth.currentUser;

    if (user == null) {
      throw const HospitalFormContextException(
        'No signed-in Corvia account was found.',
      );
    }

    final profile = await _loadProfile(
      user.id,
    );

    if (profile == null) {
      throw const HospitalFormContextException(
        'No Corvia profile is linked to this account.',
      );
    }

    if (profile['is_active'] == false) {
      throw const HospitalFormContextException(
        'This Corvia account is inactive.',
      );
    }

    final profileId = _firstText(
      [
        profile['id'],
        user.id,
      ],
    );

    final role = _normaliseRole(
      profile['role'] ?? profile['user_type'],
    );

    final displayName = _firstText(
      [
        profile['full_name'],
        profile['display_name'],
        profile['name'],
        profile['first_name'],
        profile['email'],
        user.email,
      ],
      fallback: 'Corvia User',
    );

    String? resolvedPatientId = _clean(patientId);

    if (resolvedPatientId == null && _isPatientCapableRole(role)) {
      resolvedPatientId = await _resolveCurrentPatientId(
        authUserId: user.id,
        profileId: profileId,
      );
    }

    String? resolvedHospitalId = _clean(hospitalId);

    resolvedHospitalId ??= _clean(profile['hospital_id']);

    resolvedHospitalId ??= await _resolveHospitalFromRole(
      authUserId: user.id,
      profileId: profileId,
      role: role,
    );

    resolvedHospitalId ??= await _resolveHospitalFromPatient(
      resolvedPatientId,
    );

    if (resolvedHospitalId == null) {
      throw const HospitalFormContextException(
        'No hospital could be resolved for this Corvia account.',
      );
    }

    String? resolvedAdmissionId = _clean(admissionId);

    if (resolvedAdmissionId == null && resolvedPatientId != null) {
      resolvedAdmissionId = await _resolveActiveAdmission(
        hospitalId: resolvedHospitalId,
        patientId: resolvedPatientId,
      );
    }

    return HospitalFormLaunchContext(
      authUserId: user.id,
      profileId: profileId,
      role: role,
      displayName: displayName,
      hospitalId: resolvedHospitalId,
      patientId: resolvedPatientId,
      admissionId: resolvedAdmissionId,
      contextType: _clean(contextType),
      contextId: _clean(contextId),
      patientVisibleOnly: _isPatientOnlyRole(role),
      allowCreate: _roleMayCreateForms(role),
    );
  }

  Future<Map<String, dynamic>?> _loadProfile(
    String authUserId,
  ) async {
    try {
      final response = await _client
          .from('profiles')
          .select()
          .eq(
            'user_id',
            authUserId,
          )
          .limit(1);

      final rows = _rows(response);

      if (rows.isNotEmpty) {
        return rows.first;
      }
    } on PostgrestException {
      // Use legacy ID lookup below.
    }

    try {
      final response = await _client
          .from('profiles')
          .select()
          .eq(
            'id',
            authUserId,
          )
          .limit(1);

      final rows = _rows(response);

      if (rows.isNotEmpty) {
        return rows.first;
      }
    } on PostgrestException {
      return null;
    }

    return null;
  }

  Future<String?> _resolveCurrentPatientId({
    required String authUserId,
    required String profileId,
  }) async {
    final profileCandidates = {
      authUserId,
      profileId,
    };

    for (final candidate in profileCandidates) {
      final result = await _firstValue(
        table: 'patients',
        column: 'profile_id',
        value: candidate,
        resultColumn: 'id',
      );

      if (result != null) {
        return result;
      }
    }

    return null;
  }

  Future<String?> _resolveHospitalFromRole({
    required String authUserId,
    required String profileId,
    required String role,
  }) async {
    final candidates = {
      authUserId,
      profileId,
    };

    final tableNames = <String>[];

    if (_isAdminRole(role)) {
      tableNames.add('hospital_admins');
    }

    if (_isDoctorRole(role)) {
      tableNames.add('doctors');
    }

    if (_isNurseRole(role)) {
      tableNames.addAll(
        const [
          'nurses',
          'hospital_nurses',
        ],
      );
    }

    if (_isReceptionRole(role)) {
      tableNames.addAll(
        const [
          'receptionists',
          'reception_staff',
          'hospital_receptionists',
        ],
      );
    }

    if (_isPharmacistRole(role)) {
      tableNames.add('pharmacists');
    }

    tableNames.addAll(
      const [
        'hospital_admins',
        'doctors',
        'nurses',
        'pharmacists',
        'receptionists',
      ],
    );

    for (final table in tableNames.toSet()) {
      for (final candidate in candidates) {
        final hospitalId = await _firstValue(
          table: table,
          column: 'profile_id',
          value: candidate,
          resultColumn: 'hospital_id',
        );

        if (hospitalId != null) {
          return hospitalId;
        }
      }
    }

    return null;
  }

  Future<String?> _resolveHospitalFromPatient(
    String? patientId,
  ) async {
    if (patientId == null) {
      return null;
    }

    try {
      final response = await _client.from('patient_hospital_links').select().eq(
            'patient_id',
            patientId,
          );

      final rows = _rows(response);

      if (rows.isNotEmpty) {
        rows.sort(
          (
            first,
            second,
          ) {
            final firstActive = _isActiveLink(first);
            final secondActive = _isActiveLink(second);

            if (firstActive != secondActive) {
              return firstActive ? -1 : 1;
            }

            final firstDate = _date(
              first['updated_at'] ?? first['linked_at'] ?? first['created_at'],
            );

            final secondDate = _date(
              second['updated_at'] ??
                  second['linked_at'] ??
                  second['created_at'],
            );

            return secondDate.compareTo(
              firstDate,
            );
          },
        );

        for (final row in rows) {
          final hospitalId = _clean(row['hospital_id']);

          if (hospitalId != null) {
            return hospitalId;
          }
        }
      }
    } on PostgrestException {
      // Use legacy patient hospital column below.
    }

    return _firstValue(
      table: 'patients',
      column: 'id',
      value: patientId,
      resultColumn: 'hospital_id',
    );
  }

  Future<String?> _resolveActiveAdmission({
    required String hospitalId,
    required String patientId,
  }) async {
    try {
      final response = await _client
          .from('hospital_admissions')
          .select()
          .eq(
            'hospital_id',
            hospitalId,
          )
          .eq(
            'patient_id',
            patientId,
          );

      final rows = _rows(response);

      if (rows.isEmpty) {
        return null;
      }

      const statusPriority = <String, int>{
        'admitted': 0,
        'active': 1,
        'in_progress': 2,
        'observation': 3,
        'planned': 4,
        'pending': 5,
      };

      rows.sort(
        (
          first,
          second,
        ) {
          final firstStatus = _normaliseStatus(
            first['status'],
          );

          final secondStatus = _normaliseStatus(
            second['status'],
          );

          final firstPriority = statusPriority[firstStatus] ?? 100;

          final secondPriority = statusPriority[secondStatus] ?? 100;

          if (firstPriority != secondPriority) {
            return firstPriority.compareTo(
              secondPriority,
            );
          }

          final firstDate = _date(
            first['admitted_at'] ??
                first['planned_admission_at'] ??
                first['updated_at'] ??
                first['created_at'],
          );

          final secondDate = _date(
            second['admitted_at'] ??
                second['planned_admission_at'] ??
                second['updated_at'] ??
                second['created_at'],
          );

          return secondDate.compareTo(
            firstDate,
          );
        },
      );

      for (final row in rows) {
        final status = _normaliseStatus(
          row['status'],
        );

        if (statusPriority.containsKey(
          status,
        )) {
          return _clean(row['id']);
        }
      }
    } on PostgrestException {
      return null;
    }

    return null;
  }

  Future<String?> _firstValue({
    required String table,
    required String column,
    required String value,
    required String resultColumn,
  }) async {
    try {
      final response = await _client
          .from(table)
          .select()
          .eq(
            column,
            value,
          )
          .limit(1);

      final rows = _rows(response);

      if (rows.isEmpty) {
        return null;
      }

      return _clean(
        rows.first[resultColumn],
      );
    } on PostgrestException {
      return null;
    }
  }

  static bool _isActiveLink(
    Map<String, dynamic> row,
  ) {
    if (row['is_active'] == true) {
      return true;
    }

    final status = _normaliseStatus(
      row['status'],
    );

    return {
      'active',
      'current',
      'linked',
      'admitted',
    }.contains(status);
  }

  static bool _roleMayCreateForms(
    String role,
  ) {
    return {
      'patient',
      'doctor',
      'specialist',
      'nurse',
      'reception',
      'receptionist',
      'pharmacist',
      'hospital_admin',
      'admin',
    }.contains(role);
  }

  static bool _isPatientCapableRole(
    String role,
  ) {
    return {
      'patient',
      'doctor',
      'specialist',
      'nurse',
    }.contains(role);
  }

  static bool _isPatientOnlyRole(
    String role,
  ) {
    return role == 'patient';
  }

  static bool _isAdminRole(
    String role,
  ) {
    return {
      'hospital_admin',
      'admin',
    }.contains(role);
  }

  static bool _isDoctorRole(
    String role,
  ) {
    return {
      'doctor',
      'specialist',
    }.contains(role);
  }

  static bool _isNurseRole(
    String role,
  ) {
    return role == 'nurse';
  }

  static bool _isReceptionRole(
    String role,
  ) {
    return {
      'reception',
      'receptionist',
    }.contains(role);
  }

  static bool _isPharmacistRole(
    String role,
  ) {
    return role == 'pharmacist';
  }

  static String _normaliseRole(
    dynamic value,
  ) {
    final role = value
            ?.toString()
            .trim()
            .toLowerCase()
            .replaceAll('-', '_')
            .replaceAll(' ', '_') ??
        '';

    switch (role) {
      case 'hospitaladmin':
      case 'hospital_administrator':
        return 'hospital_admin';

      case 'reception_staff':
        return 'reception';

      case 'medical_specialist':
        return 'specialist';

      default:
        return role;
    }
  }

  static String _normaliseStatus(
    dynamic value,
  ) {
    return value
            ?.toString()
            .trim()
            .toLowerCase()
            .replaceAll('-', '_')
            .replaceAll(' ', '_') ??
        '';
  }

  static String? _clean(
    dynamic value,
  ) {
    if (value == null) {
      return null;
    }

    final clean = value.toString().trim();

    if (clean.isEmpty || clean.toLowerCase() == 'null') {
      return null;
    }

    return clean;
  }

  static String _firstText(
    List<dynamic> values, {
    String fallback = '',
  }) {
    for (final value in values) {
      final clean = _clean(value);

      if (clean != null) {
        return clean;
      }
    }

    return fallback;
  }

  static DateTime _date(
    dynamic value,
  ) {
    if (value is DateTime) {
      return value;
    }

    return DateTime.tryParse(
          value?.toString() ?? '',
        ) ??
        DateTime.fromMillisecondsSinceEpoch(
          0,
        );
  }

  static List<Map<String, dynamic>> _rows(
    dynamic value,
  ) {
    if (value is! List) {
      return const [];
    }

    return value
        .whereType<Map>()
        .map(
          (row) => Map<String, dynamic>.from(
            row,
          ),
        )
        .toList();
  }
}

class HospitalFormLaunchContext {
  const HospitalFormLaunchContext({
    required this.authUserId,
    required this.profileId,
    required this.role,
    required this.displayName,
    required this.hospitalId,
    required this.patientVisibleOnly,
    required this.allowCreate,
    this.patientId,
    this.admissionId,
    this.contextType,
    this.contextId,
  });

  final String authUserId;
  final String profileId;

  final String role;
  final String displayName;

  final String hospitalId;
  final String? patientId;
  final String? admissionId;

  final String? contextType;
  final String? contextId;

  final bool patientVisibleOnly;
  final bool allowCreate;

  bool get hasPatient {
    return patientId != null && patientId!.trim().isNotEmpty;
  }

  bool get hasAdmission {
    return admissionId != null && admissionId!.trim().isNotEmpty;
  }

  bool get isPatient {
    return role == 'patient';
  }

  bool get isDoctorOrSpecialist {
    return role == 'doctor' || role == 'specialist';
  }

  bool get isNurse {
    return role == 'nurse';
  }

  bool get isReception {
    return role == 'reception' || role == 'receptionist';
  }

  bool get isPharmacist {
    return role == 'pharmacist';
  }

  bool get isHospitalAdmin {
    return role == 'hospital_admin' || role == 'admin';
  }

  String get formsTitle {
    if (isPatient) {
      return 'My Hospital Forms';
    }

    if (isReception) {
      return 'Admission and Consent Forms';
    }

    if (isPharmacist) {
      return 'Pharmacy Forms';
    }

    if (isNurse) {
      return 'Nursing Forms';
    }

    if (isDoctorOrSpecialist) {
      return 'Clinical Patient Forms';
    }

    if (isHospitalAdmin) {
      return 'Hospital Form Library';
    }

    return 'Hospital Forms';
  }
}

class HospitalFormContextException implements Exception {
  const HospitalFormContextException(
    this.message,
  );

  final String message;

  @override
  String toString() {
    return message;
  }
}
