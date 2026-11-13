import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'hospital_structure_service.dart';

class HospitalVisitorService {
  HospitalVisitorService({
    SupabaseClient? supabase,
    HospitalStructureService? structureService,
  })  : _supabase = supabase ?? Supabase.instance.client,
        _structureService = structureService ?? HospitalStructureService();

  final SupabaseClient _supabase;
  final HospitalStructureService _structureService;

  // ---------------------------------------------------------------------------
  // GENERAL HELPERS
  // ---------------------------------------------------------------------------

  List<Map<String, dynamic>> _mapList(dynamic value) {
    if (value is! List) {
      return [];
    }

    return value
        .whereType<Map>()
        .map(
          (item) => Map<String, dynamic>.from(item),
        )
        .toList();
  }

  Map<String, dynamic> _mapValue(dynamic value) {
    if (value is Map<String, dynamic>) {
      return value;
    }

    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }

    if (value is List && value.isNotEmpty) {
      return _mapValue(value.first);
    }

    if (value is String && value.trim().isNotEmpty) {
      try {
        return _mapValue(jsonDecode(value));
      } catch (_) {
        return {};
      }
    }

    return {};
  }

  String? _nullableText(String? value) {
    final cleaned = value?.trim();

    if (cleaned == null || cleaned.isEmpty) {
      return null;
    }

    return cleaned;
  }

  DateTime? _dateTime(dynamic value) {
    if (value == null) {
      return null;
    }

    return DateTime.tryParse(
      value.toString(),
    )?.toLocal();
  }

  int _intValue(dynamic value) {
    if (value is int) {
      return value;
    }

    if (value is num) {
      return value.toInt();
    }

    return int.tryParse(
          value?.toString() ?? '',
        ) ??
        0;
  }

  bool _boolValue(dynamic value) {
    if (value is bool) {
      return value;
    }

    if (value is num) {
      return value != 0;
    }

    final text = value?.toString().trim().toLowerCase();

    return text == 'true' || text == '1' || text == 'yes';
  }

  String? _extractScalarString(dynamic value) {
    if (value == null) {
      return null;
    }

    if (value is String) {
      return value;
    }

    if (value is Map && value.isNotEmpty) {
      return _extractScalarString(
        value.values.first,
      );
    }

    if (value is List && value.isNotEmpty) {
      return _extractScalarString(
        value.first,
      );
    }

    return value.toString();
  }

  bool _extractScalarBool(dynamic value) {
    if (value is bool) {
      return value;
    }

    if (value is Map && value.isNotEmpty) {
      return _extractScalarBool(
        value.values.first,
      );
    }

    if (value is List && value.isNotEmpty) {
      return _extractScalarBool(
        value.first,
      );
    }

    return _boolValue(value);
  }

  List<List<String>> _chunks(
    Iterable<String> source, {
    int size = 100,
  }) {
    final values =
        source.where((value) => value.trim().isNotEmpty).toSet().toList();

    final chunks = <List<String>>[];

    for (var index = 0; index < values.length; index += size) {
      final end = index + size > values.length ? values.length : index + size;

      chunks.add(
        values.sublist(index, end),
      );
    }

    return chunks;
  }

  String _profileName(
    Map<String, dynamic>? profile,
  ) {
    if (profile == null) {
      return 'Unknown patient';
    }

    final firstName = profile['first_name']?.toString().trim() ?? '';

    final surname = profile['surname']?.toString().trim() ?? '';

    final name = '$firstName $surname'.trim();

    // "Corvia Patient" is a placeholder some accounts carry, not a name.
    if (name.isNotEmpty && name.toLowerCase() != 'corvia patient') {
      return name;
    }

    return 'Name not on file';
  }

  // ---------------------------------------------------------------------------
  // HOSPITALS
  // ---------------------------------------------------------------------------

  Future<List<Map<String, dynamic>>> getAdminHospitals() {
    return _structureService.getAdminHospitals();
  }

  // ---------------------------------------------------------------------------
  // DASHBOARD STATISTICS
  // ---------------------------------------------------------------------------

  Future<VisitorDashboardStats> getDashboardStats(
    String hospitalId,
  ) async {
    if (hospitalId.trim().isEmpty) {
      throw Exception('Hospital ID is required.');
    }

    final response = await _supabase.rpc(
      'corvia_mh_visitor_dashboard_stats',
      params: {
        'p_hospital_id': hospitalId,
      },
    );

    final data = _mapValue(response);

    if (data.isEmpty) {
      throw Exception(
        'Visitor dashboard returned no data.',
      );
    }

    return VisitorDashboardStats.fromMap(data);
  }

  // ---------------------------------------------------------------------------
  // VISITOR RECORDS
  // ---------------------------------------------------------------------------

  Future<List<HospitalVisitorRecord>> getVisitors(
    String hospitalId, {
    String? search,
    bool includeBlocked = true,
    int limit = 500,
  }) async {
    dynamic query = _supabase
        .from('hospital_visitors')
        .select(
          'id, hospital_id, first_name, surname, id_type, '
          'id_number, phone, email, vehicle_registration, '
          'photo_url, is_blocked, blocked_reason, blocked_at, '
          'blocked_by, notes, created_by, updated_by, '
          'created_at, updated_at',
        )
        .eq('hospital_id', hospitalId);

    if (!includeBlocked) {
      query = query.eq('is_blocked', false);
    }

    final response =
        await query.order('surname').order('first_name').limit(limit);

    final visitors =
        _mapList(response).map(HospitalVisitorRecord.fromMap).toList();

    final cleanedSearch = search?.trim().toLowerCase() ?? '';

    if (cleanedSearch.isEmpty) {
      return visitors;
    }

    return visitors.where((visitor) {
      return visitor.searchText.contains(
        cleanedSearch,
      );
    }).toList();
  }

  Future<String> upsertVisitor({
    required String hospitalId,
    required String firstName,
    required String surname,
    String idType = 'south_african_id',
    String? idNumber,
    String? phone,
    String? email,
    String? vehicleRegistration,
    String? photoUrl,
    String? notes,
  }) async {
    if (firstName.trim().isEmpty) {
      throw Exception(
        'Visitor first name is required.',
      );
    }

    if (surname.trim().isEmpty) {
      throw Exception(
        'Visitor surname is required.',
      );
    }

    const validIdTypes = {
      'south_african_id',
      'passport',
      'drivers_licence',
      'birth_certificate',
      'temporary_document',
      'other',
    };

    if (!validIdTypes.contains(idType)) {
      throw Exception(
        'Invalid visitor identity type.',
      );
    }

    final response = await _supabase.rpc(
      'corvia_mh_upsert_visitor',
      params: {
        'p_hospital_id': hospitalId,
        'p_first_name': firstName.trim(),
        'p_surname': surname.trim(),
        'p_id_type': idType,
        'p_id_number': _nullableText(idNumber),
        'p_phone': _nullableText(phone),
        'p_email': _nullableText(email),
        'p_vehicle_registration': _nullableText(vehicleRegistration),
        'p_photo_url': _nullableText(photoUrl),
        'p_notes': _nullableText(notes),
      },
    );

    final visitorId = _extractScalarString(response);

    if (visitorId == null || visitorId.trim().isEmpty) {
      throw Exception(
        'Visitor was saved without a valid ID.',
      );
    }

    return visitorId;
  }

  Future<void> setVisitorBlocked({
    required String visitorId,
    required bool blocked,
    String? reason,
  }) async {
    if (blocked && (reason == null || reason.trim().isEmpty)) {
      throw Exception(
        'A reason is required when blocking a visitor.',
      );
    }

    final response = await _supabase.rpc(
      'corvia_mh_set_visitor_blocked',
      params: {
        'p_visitor_id': visitorId,
        'p_blocked': blocked,
        'p_reason': _nullableText(reason),
      },
    );

    if (!_extractScalarBool(response)) {
      throw Exception(
        blocked
            ? 'Visitor could not be blocked.'
            : 'Visitor could not be unblocked.',
      );
    }
  }

  // ---------------------------------------------------------------------------
  // ADMISSIONS AVAILABLE FOR VISITOR PASSES
  // ---------------------------------------------------------------------------

  Future<List<VisitorAdmissionOption>> getVisitorAdmissionOptions(
    String hospitalId, {
    bool includePlanned = true,
  }) async {
    dynamic query = _supabase
        .from('hospital_admissions')
        .select(
          'id, hospital_id, patient_id, admission_number, '
          'admission_type, status, visitor_status, '
          'admitted_at, expected_discharge_at',
        )
        .eq('hospital_id', hospitalId);

    query = query.inFilter(
      'status',
      includePlanned ? ['planned', 'admitted'] : ['admitted'],
    );

    final admissionResponse = await query.order(
      'created_at',
      ascending: false,
    );

    final admissions = _mapList(admissionResponse);

    if (admissions.isEmpty) {
      return [];
    }

    final patientIds = admissions
        .map(
          (row) => row['patient_id']?.toString(),
        )
        .whereType<String>()
        .toSet();

    final admissionIds = admissions
        .map(
          (row) => row['id']?.toString(),
        )
        .whereType<String>()
        .toSet();

    final patients = await _fetchPatients(patientIds);

    final profileIds = patients
        .map(
          (row) => row['profile_id']?.toString(),
        )
        .whereType<String>()
        .toSet();

    final profiles = await _fetchProfiles(profileIds);

    final assignments = await _fetchActiveAssignments(
      hospitalId: hospitalId,
      admissionIds: admissionIds,
    );

    final structure = await _structureService.loadSnapshot(
      hospitalId,
    );

    final patientById = <String, Map<String, dynamic>>{
      for (final patient in patients)
        if (patient['id'] != null) patient['id'].toString(): patient,
    };

    // patients.profile_id references profiles.user_id (the auth uid).
    final profileById = <String, Map<String, dynamic>>{
      for (final profile in profiles)
        if (profile['user_id'] != null) profile['user_id'].toString(): profile,
    };

    final assignmentByAdmissionId = <String, Map<String, dynamic>>{
      for (final assignment in assignments)
        if (assignment['admission_id'] != null)
          assignment['admission_id'].toString(): assignment,
    };

    final wardById = <String, Map<String, dynamic>>{
      for (final ward in structure.wards)
        if (ward['id'] != null) ward['id'].toString(): ward,
    };

    final roomById = <String, Map<String, dynamic>>{
      for (final room in structure.rooms)
        if (room['id'] != null) room['id'].toString(): room,
    };

    final bedById = <String, Map<String, dynamic>>{
      for (final bed in structure.beds)
        if (bed['id'] != null) bed['id'].toString(): bed,
    };

    final result = <VisitorAdmissionOption>[];

    for (final admission in admissions) {
      final admissionId = admission['id']?.toString();

      final patientId = admission['patient_id']?.toString();

      if (admissionId == null || patientId == null) {
        continue;
      }

      final patient = patientById[patientId];

      final profileId = patient?['profile_id']?.toString();

      final profile = profileId == null ? null : profileById[profileId];

      final assignment = assignmentByAdmissionId[admissionId];

      final wardId = assignment?['ward_id']?.toString();

      final roomId = assignment?['room_id']?.toString();

      final bedId = assignment?['bed_id']?.toString();

      final ward = wardId == null ? null : wardById[wardId];

      final room = roomId == null ? null : roomById[roomId];

      final bed = bedId == null ? null : bedById[bedId];

      result.add(
        VisitorAdmissionOption(
          hospitalId: hospitalId,
          admissionId: admissionId,
          admissionNumber: admission['admission_number']?.toString(),
          admissionType: admission['admission_type']?.toString() ?? 'elective',
          admissionStatus: admission['status']?.toString() ?? 'planned',
          visitorStatus: admission['visitor_status']?.toString() ??
              'approved_visitors_only',
          patientId: patientId,
          patientName: _profileName(profile),
          patientNumber: patient?['patient_number']?.toString(),
          wardId: wardId,
          wardName: ward?['name']?.toString(),
          wardType: ward?['ward_type']?.toString(),
          roomId: roomId,
          roomNumber: room?['room_number']?.toString(),
          roomName: room?['room_name']?.toString(),
          bedId: bedId,
          bedNumber: bed?['bed_number']?.toString(),
          bedLabel: bed?['bed_label']?.toString(),
          admittedAt: _dateTime(admission['admitted_at']),
          expectedDischargeAt: _dateTime(
            admission['expected_discharge_at'],
          ),
        ),
      );
    }

    result.sort((a, b) {
      final statusCompare = a.admissionStatus == b.admissionStatus
          ? 0
          : a.admissionStatus == 'admitted'
              ? -1
              : 1;

      if (statusCompare != 0) {
        return statusCompare;
      }

      return a.patientName.toLowerCase().compareTo(
            b.patientName.toLowerCase(),
          );
    });

    return result;
  }

  // ---------------------------------------------------------------------------
  // PATIENT VISITOR RESTRICTIONS
  // ---------------------------------------------------------------------------

  Future<List<PatientVisitorRestrictionRecord>> getRestrictions(
    String hospitalId, {
    bool activeOnly = false,
    int limit = 500,
  }) async {
    dynamic query = _supabase
        .from('patient_visitor_restrictions')
        .select(
          'id, hospital_id, patient_id, admission_id, '
          'restriction_type, reason, starts_at, ends_at, '
          'is_active, created_by, approved_by, revoked_by, '
          'revoked_at, revocation_reason, created_at, updated_at',
        )
        .eq('hospital_id', hospitalId);

    if (activeOnly) {
      query = query.eq('is_active', true);
    }

    final response =
        await query.order('created_at', ascending: false).limit(limit);

    final restrictions = _mapList(response);

    if (restrictions.isEmpty) {
      return [];
    }

    final patientIds = restrictions
        .map(
          (row) => row['patient_id']?.toString(),
        )
        .whereType<String>()
        .toSet();

    final admissionIds = restrictions
        .map(
          (row) => row['admission_id']?.toString(),
        )
        .whereType<String>()
        .toSet();

    final patients = await _fetchPatients(patientIds);

    final profiles = await _fetchProfiles(
      patients
          .map(
            (row) => row['profile_id']?.toString(),
          )
          .whereType<String>(),
    );

    final admissions = await _fetchAdmissions(admissionIds);

    final patientById = <String, Map<String, dynamic>>{
      for (final patient in patients)
        if (patient['id'] != null) patient['id'].toString(): patient,
    };

    // patients.profile_id references profiles.user_id (the auth uid).
    final profileById = <String, Map<String, dynamic>>{
      for (final profile in profiles)
        if (profile['user_id'] != null) profile['user_id'].toString(): profile,
    };

    final admissionById = <String, Map<String, dynamic>>{
      for (final admission in admissions)
        if (admission['id'] != null) admission['id'].toString(): admission,
    };

    return restrictions.map((row) {
      final patientId = row['patient_id']?.toString() ?? '';

      final patient = patientById[patientId];

      final profile = patient == null
          ? null
          : profileById[patient['profile_id']?.toString()];

      final admissionId = row['admission_id']?.toString();

      final admission = admissionId == null ? null : admissionById[admissionId];

      return PatientVisitorRestrictionRecord(
        restrictionId: row['id']?.toString() ?? '',
        hospitalId: row['hospital_id']?.toString() ?? hospitalId,
        patientId: patientId,
        patientName: _profileName(profile),
        patientNumber: patient?['patient_number']?.toString(),
        admissionId: admissionId,
        admissionNumber: admission?['admission_number']?.toString(),
        restrictionType: row['restriction_type']?.toString() ?? 'approved_only',
        reason: row['reason']?.toString() ?? '',
        startsAt: _dateTime(row['starts_at']),
        endsAt: _dateTime(row['ends_at']),
        isActive: row['is_active'] != false,
        revokedAt: _dateTime(row['revoked_at']),
        revocationReason: row['revocation_reason']?.toString(),
        createdAt: _dateTime(row['created_at']),
        updatedAt: _dateTime(row['updated_at']),
      );
    }).toList();
  }

  Future<String> createRestriction({
    required String hospitalId,
    required String patientId,
    required String restrictionType,
    required String reason,
    String? admissionId,
    DateTime? startsAt,
    DateTime? endsAt,
  }) async {
    const validTypes = {
      'no_visitors',
      'approved_only',
      'family_only',
      'primary_contact_only',
      'security_restricted',
      'infection_control',
      'court_order',
      'patient_request',
      'staff_discretion',
    };

    if (!validTypes.contains(restrictionType)) {
      throw Exception(
        'Invalid visitor restriction type.',
      );
    }

    if (reason.trim().isEmpty) {
      throw Exception(
        'Visitor restriction reason is required.',
      );
    }

    final effectiveStart = startsAt ?? DateTime.now();

    if (endsAt != null && !endsAt.isAfter(effectiveStart)) {
      throw Exception(
        'Restriction end date must be after its start date.',
      );
    }

    final response = await _supabase.rpc(
      'corvia_mh_create_visitor_restriction',
      params: {
        'p_hospital_id': hospitalId,
        'p_patient_id': patientId,
        'p_restriction_type': restrictionType,
        'p_reason': reason.trim(),
        'p_admission_id': _nullableText(admissionId),
        'p_starts_at': effectiveStart.toUtc().toIso8601String(),
        'p_ends_at': endsAt?.toUtc().toIso8601String(),
      },
    );

    final restrictionId = _extractScalarString(response);

    if (restrictionId == null || restrictionId.trim().isEmpty) {
      throw Exception(
        'Visitor restriction was created without a valid ID.',
      );
    }

    return restrictionId;
  }

  Future<void> revokeRestriction({
    required String restrictionId,
    required String reason,
  }) async {
    if (reason.trim().isEmpty) {
      throw Exception(
        'A revocation reason is required.',
      );
    }

    final response = await _supabase.rpc(
      'corvia_mh_revoke_visitor_restriction',
      params: {
        'p_restriction_id': restrictionId,
        'p_reason': reason.trim(),
      },
    );

    if (!_extractScalarBool(response)) {
      throw Exception(
        'Visitor restriction could not be revoked.',
      );
    }
  }

  // ---------------------------------------------------------------------------
  // VISITOR PASSES
  // ---------------------------------------------------------------------------

  Future<List<HospitalVisitorPassRecord>> getVisitorPasses(
    String hospitalId, {
    Set<String>? statuses,
    int limit = 500,
  }) async {
    dynamic query = _supabase
        .from('visitor_passes')
        .select(
          'id, hospital_id, visitor_id, patient_id, admission_id, '
          'requested_ward_id, pass_number, qr_token, pass_type, '
          'status, relationship_to_patient, visit_purpose, '
          'valid_from, valid_until, max_entries, entries_used, '
          'requires_identity_verification, restriction_override, '
          'override_reason, issued_by, approved_by, approved_at, '
          'revoked_by, revoked_at, revocation_reason, notes, '
          'created_at, updated_at',
        )
        .eq('hospital_id', hospitalId);

    if (statuses != null && statuses.isNotEmpty) {
      query = query.inFilter(
        'status',
        statuses.toList(),
      );
    }

    final response =
        await query.order('created_at', ascending: false).limit(limit);

    final passRows = _mapList(response);

    if (passRows.isEmpty) {
      return [];
    }

    final visitorIds = passRows
        .map(
          (row) => row['visitor_id']?.toString(),
        )
        .whereType<String>()
        .toSet();

    final patientIds = passRows
        .map(
          (row) => row['patient_id']?.toString(),
        )
        .whereType<String>()
        .toSet();

    final admissionIds = passRows
        .map(
          (row) => row['admission_id']?.toString(),
        )
        .whereType<String>()
        .toSet();

    final wardIds = passRows
        .map(
          (row) => row['requested_ward_id']?.toString(),
        )
        .whereType<String>()
        .toSet();

    final visitors = await _fetchVisitors(visitorIds);

    final patients = await _fetchPatients(patientIds);

    final profiles = await _fetchProfiles(
      patients
          .map(
            (row) => row['profile_id']?.toString(),
          )
          .whereType<String>(),
    );

    final admissions = await _fetchAdmissions(admissionIds);

    final wards = await _fetchWards(wardIds);

    final openCheckins = await _fetchOpenCheckinsForPasses(
      hospitalId: hospitalId,
      passIds: passRows
          .map(
            (row) => row['id']?.toString(),
          )
          .whereType<String>()
          .toSet(),
    );

    final visitorById = <String, Map<String, dynamic>>{
      for (final visitor in visitors)
        if (visitor['id'] != null) visitor['id'].toString(): visitor,
    };

    final patientById = <String, Map<String, dynamic>>{
      for (final patient in patients)
        if (patient['id'] != null) patient['id'].toString(): patient,
    };

    // patients.profile_id references profiles.user_id (the auth uid).
    final profileById = <String, Map<String, dynamic>>{
      for (final profile in profiles)
        if (profile['user_id'] != null) profile['user_id'].toString(): profile,
    };

    final admissionById = <String, Map<String, dynamic>>{
      for (final admission in admissions)
        if (admission['id'] != null) admission['id'].toString(): admission,
    };

    final wardById = <String, Map<String, dynamic>>{
      for (final ward in wards)
        if (ward['id'] != null) ward['id'].toString(): ward,
    };

    final checkinByPassId = <String, Map<String, dynamic>>{
      for (final checkin in openCheckins)
        if (checkin['visitor_pass_id'] != null)
          checkin['visitor_pass_id'].toString(): checkin,
    };

    return passRows.map((row) {
      final visitorId = row['visitor_id']?.toString() ?? '';

      final patientId = row['patient_id']?.toString() ?? '';

      final admissionId = row['admission_id']?.toString() ?? '';

      final wardId = row['requested_ward_id']?.toString();

      final visitor = visitorById[visitorId];
      final patient = patientById[patientId];

      final profile = patient == null
          ? null
          : profileById[patient['profile_id']?.toString()];

      final admission = admissionById[admissionId];

      final ward = wardId == null ? null : wardById[wardId];

      final passId = row['id']?.toString() ?? '';

      final openCheckin = checkinByPassId[passId];

      return HospitalVisitorPassRecord(
        visitorPassId: passId,
        hospitalId: row['hospital_id']?.toString() ?? hospitalId,
        visitorId: visitorId,
        visitorName: [
          visitor?['first_name']?.toString(),
          visitor?['surname']?.toString(),
        ]
            .whereType<String>()
            .where((value) => value.trim().isNotEmpty)
            .join(' '),
        visitorIdType: visitor?['id_type']?.toString(),
        visitorIdNumber: visitor?['id_number']?.toString(),
        visitorPhone: visitor?['phone']?.toString(),
        visitorBlocked: visitor?['is_blocked'] == true,
        patientId: patientId,
        patientName: _profileName(profile),
        patientNumber: patient?['patient_number']?.toString(),
        admissionId: admissionId,
        admissionNumber: admission?['admission_number']?.toString(),
        requestedWardId: wardId,
        requestedWardName: ward?['name']?.toString(),
        passNumber: row['pass_number']?.toString() ?? '',
        qrToken: row['qr_token']?.toString() ?? '',
        passType: row['pass_type']?.toString() ?? 'single_visit',
        status: row['status']?.toString() ?? 'pending',
        relationshipToPatient: row['relationship_to_patient']?.toString() ?? '',
        visitPurpose: row['visit_purpose']?.toString(),
        validFrom: _dateTime(row['valid_from']),
        validUntil: _dateTime(row['valid_until']),
        maxEntries:
            row['max_entries'] == null ? null : _intValue(row['max_entries']),
        entriesUsed: _intValue(row['entries_used']),
        requiresIdentityVerification:
            row['requires_identity_verification'] != false,
        restrictionOverride: row['restriction_override'] == true,
        overrideReason: row['override_reason']?.toString(),
        approvedAt: _dateTime(row['approved_at']),
        revokedAt: _dateTime(row['revoked_at']),
        revocationReason: row['revocation_reason']?.toString(),
        notes: row['notes']?.toString(),
        createdAt: _dateTime(row['created_at']),
        updatedAt: _dateTime(row['updated_at']),
        openCheckinId: openCheckin?['id']?.toString(),
        checkedInAt: _dateTime(openCheckin?['checkin_at']),
      );
    }).toList();
  }

  Future<VisitorPassCreationResult> createVisitorPass({
    required String hospitalId,
    required String visitorId,
    required String patientId,
    required String admissionId,
    required String relationshipToPatient,
    required DateTime validFrom,
    required DateTime validUntil,
    String? visitPurpose,
    String passType = 'single_visit',
    int? maxEntries = 1,
    String? requestedWardId,
    bool requiresIdentityVerification = true,
    bool approveNow = true,
    bool restrictionOverride = false,
    String? overrideReason,
    String? notes,
  }) async {
    if (relationshipToPatient.trim().isEmpty) {
      throw Exception(
        'Relationship to patient is required.',
      );
    }

    if (!validUntil.isAfter(validFrom)) {
      throw Exception(
        'Visitor pass expiry must be after its start date.',
      );
    }

    if (maxEntries != null && maxEntries < 1) {
      throw Exception(
        'Maximum entries must be at least one.',
      );
    }

    if (restrictionOverride &&
        (overrideReason == null || overrideReason.trim().isEmpty)) {
      throw Exception(
        'An override reason is required.',
      );
    }

    const validTypes = {
      'single_visit',
      'temporary',
      'daily',
      'recurring',
      'family',
      'primary_contact',
      'end_of_life',
      'staff_authorised',
    };

    if (!validTypes.contains(passType)) {
      throw Exception(
        'Invalid visitor pass type.',
      );
    }

    final response = await _supabase.rpc(
      'corvia_mh_create_visitor_pass',
      params: {
        'p_hospital_id': hospitalId,
        'p_visitor_id': visitorId,
        'p_patient_id': patientId,
        'p_admission_id': admissionId,
        'p_relationship_to_patient': relationshipToPatient.trim(),
        'p_visit_purpose': _nullableText(visitPurpose),
        'p_pass_type': passType,
        'p_valid_from': validFrom.toUtc().toIso8601String(),
        'p_valid_until': validUntil.toUtc().toIso8601String(),
        'p_max_entries': maxEntries,
        'p_requested_ward_id': _nullableText(requestedWardId),
        'p_requires_identity_verification': requiresIdentityVerification,
        'p_approve_now': approveNow,
        'p_restriction_override': restrictionOverride,
        'p_override_reason': _nullableText(overrideReason),
        'p_notes': _nullableText(notes),
      },
    );

    final data = _mapValue(response);

    final result = VisitorPassCreationResult.fromMap(data);

    if (result.visitorPassId.isEmpty || result.qrToken.isEmpty) {
      throw Exception(
        'Visitor pass was created without valid pass details.',
      );
    }

    return result;
  }

  Future<void> approveVisitorPass(
    String visitorPassId,
  ) async {
    final response = await _supabase.rpc(
      'corvia_mh_approve_visitor_pass',
      params: {
        'p_visitor_pass_id': visitorPassId,
      },
    );

    if (!_extractScalarBool(response)) {
      throw Exception(
        'Visitor pass could not be approved.',
      );
    }
  }

  Future<void> revokeVisitorPass({
    required String visitorPassId,
    required String reason,
  }) async {
    if (reason.trim().isEmpty) {
      throw Exception(
        'A revocation reason is required.',
      );
    }

    final response = await _supabase.rpc(
      'corvia_mh_revoke_visitor_pass',
      params: {
        'p_visitor_pass_id': visitorPassId,
        'p_reason': reason.trim(),
      },
    );

    if (!_extractScalarBool(response)) {
      throw Exception(
        'Visitor pass could not be revoked.',
      );
    }
  }

  // ---------------------------------------------------------------------------
  // QR LOOKUP AND CHECK-IN
  // ---------------------------------------------------------------------------

  Future<VisitorPassEvaluation> lookupVisitorPassByQr({
    required String qrToken,
    bool identityVerified = false,
  }) async {
    final cleanedToken = qrToken.trim();

    if (cleanedToken.isEmpty) {
      throw Exception('QR token is required.');
    }

    final response = await _supabase.rpc(
      'corvia_mh_lookup_visitor_pass_by_qr',
      params: {
        'p_qr_token': cleanedToken,
        'p_identity_verified': identityVerified,
      },
    );

    return VisitorPassEvaluation.fromMap(
      _mapValue(response),
    );
  }

  Future<VisitorCheckinResult> checkinVisitor({
    required String qrToken,
    required bool identityVerified,
    String? verificationMethod,
    String checkinMethod = 'qr',
    String? notes,
  }) async {
    final cleanedToken = qrToken.trim();

    if (cleanedToken.isEmpty) {
      throw Exception('QR token is required.');
    }

    const validCheckinMethods = {
      'qr',
      'manual',
      'reception',
      'security_desk',
    };

    if (!validCheckinMethods.contains(checkinMethod)) {
      throw Exception(
        'Invalid visitor check-in method.',
      );
    }

    const validVerificationMethods = {
      'south_african_id',
      'passport',
      'drivers_licence',
      'birth_certificate',
      'temporary_document',
      'visual_confirmation',
      'staff_override',
      'not_required',
    };

    if (verificationMethod != null &&
        !validVerificationMethods.contains(
          verificationMethod,
        )) {
      throw Exception(
        'Invalid identity verification method.',
      );
    }

    final response = await _supabase.rpc(
      'corvia_mh_checkin_visitor',
      params: {
        'p_qr_token': cleanedToken,
        'p_identity_verified': identityVerified,
        'p_verification_method': _nullableText(verificationMethod),
        'p_checkin_method': checkinMethod,
        'p_notes': _nullableText(notes),
      },
    );

    return VisitorCheckinResult.fromMap(
      _mapValue(response),
    );
  }

  Future<VisitorCheckoutResult> checkoutVisitor({
    required String checkinId,
    String? notes,
  }) async {
    final response = await _supabase.rpc(
      'corvia_mh_checkout_visitor',
      params: {
        'p_checkin_id': checkinId,
        'p_notes': _nullableText(notes),
      },
    );

    return VisitorCheckoutResult.fromMap(
      _mapValue(response),
    );
  }

  // ---------------------------------------------------------------------------
  // VISITOR CHECK-INS
  // ---------------------------------------------------------------------------

  Future<List<HospitalVisitorCheckinRecord>> getVisitorCheckins(
    String hospitalId, {
    bool openOnly = false,
    int limit = 500,
  }) async {
    dynamic query = _supabase
        .from('visitor_checkins')
        .select(
          'id, hospital_id, visitor_pass_id, visitor_id, '
          'patient_id, admission_id, ward_id, room_id, bed_id, '
          'checkin_method, identity_verified, verification_method, '
          'verified_by, checkin_at, checkout_at, checkout_by, '
          'notes, created_at, updated_at',
        )
        .eq('hospital_id', hospitalId);

    if (openOnly) {
      query = query.isFilter(
        'checkout_at',
        null,
      );
    }

    final response =
        await query.order('checkin_at', ascending: false).limit(limit);

    final checkinRows = _mapList(response);

    if (checkinRows.isEmpty) {
      return [];
    }

    final visitorIds = checkinRows
        .map(
          (row) => row['visitor_id']?.toString(),
        )
        .whereType<String>()
        .toSet();

    final patientIds = checkinRows
        .map(
          (row) => row['patient_id']?.toString(),
        )
        .whereType<String>()
        .toSet();

    final admissionIds = checkinRows
        .map(
          (row) => row['admission_id']?.toString(),
        )
        .whereType<String>()
        .toSet();

    final passIds = checkinRows
        .map(
          (row) => row['visitor_pass_id']?.toString(),
        )
        .whereType<String>()
        .toSet();

    final wardIds = checkinRows
        .map(
          (row) => row['ward_id']?.toString(),
        )
        .whereType<String>()
        .toSet();

    final roomIds = checkinRows
        .map(
          (row) => row['room_id']?.toString(),
        )
        .whereType<String>()
        .toSet();

    final bedIds = checkinRows
        .map(
          (row) => row['bed_id']?.toString(),
        )
        .whereType<String>()
        .toSet();

    final visitors = await _fetchVisitors(visitorIds);

    final patients = await _fetchPatients(patientIds);

    final profiles = await _fetchProfiles(
      patients
          .map(
            (row) => row['profile_id']?.toString(),
          )
          .whereType<String>(),
    );

    final admissions = await _fetchAdmissions(admissionIds);

    final passes = await _fetchPasses(passIds);

    final wards = await _fetchWards(wardIds);

    final rooms = await _fetchRooms(roomIds);

    final beds = await _fetchBeds(bedIds);

    final visitorById = <String, Map<String, dynamic>>{
      for (final visitor in visitors)
        if (visitor['id'] != null) visitor['id'].toString(): visitor,
    };

    final patientById = <String, Map<String, dynamic>>{
      for (final patient in patients)
        if (patient['id'] != null) patient['id'].toString(): patient,
    };

    // patients.profile_id references profiles.user_id (the auth uid).
    final profileById = <String, Map<String, dynamic>>{
      for (final profile in profiles)
        if (profile['user_id'] != null) profile['user_id'].toString(): profile,
    };

    final admissionById = <String, Map<String, dynamic>>{
      for (final admission in admissions)
        if (admission['id'] != null) admission['id'].toString(): admission,
    };

    final passById = <String, Map<String, dynamic>>{
      for (final pass in passes)
        if (pass['id'] != null) pass['id'].toString(): pass,
    };

    final wardById = <String, Map<String, dynamic>>{
      for (final ward in wards)
        if (ward['id'] != null) ward['id'].toString(): ward,
    };

    final roomById = <String, Map<String, dynamic>>{
      for (final room in rooms)
        if (room['id'] != null) room['id'].toString(): room,
    };

    final bedById = <String, Map<String, dynamic>>{
      for (final bed in beds)
        if (bed['id'] != null) bed['id'].toString(): bed,
    };

    return checkinRows.map((row) {
      final visitorId = row['visitor_id']?.toString() ?? '';

      final patientId = row['patient_id']?.toString() ?? '';

      final admissionId = row['admission_id']?.toString() ?? '';

      final passId = row['visitor_pass_id']?.toString() ?? '';

      final wardId = row['ward_id']?.toString();

      final roomId = row['room_id']?.toString();

      final bedId = row['bed_id']?.toString();

      final visitor = visitorById[visitorId];
      final patient = patientById[patientId];

      final profile = patient == null
          ? null
          : profileById[patient['profile_id']?.toString()];

      final admission = admissionById[admissionId];

      final pass = passById[passId];

      final ward = wardId == null ? null : wardById[wardId];

      final room = roomId == null ? null : roomById[roomId];

      final bed = bedId == null ? null : bedById[bedId];

      return HospitalVisitorCheckinRecord(
        checkinId: row['id']?.toString() ?? '',
        hospitalId: row['hospital_id']?.toString() ?? hospitalId,
        visitorPassId: passId,
        passNumber: pass?['pass_number']?.toString(),
        visitorId: visitorId,
        visitorName: [
          visitor?['first_name']?.toString(),
          visitor?['surname']?.toString(),
        ]
            .whereType<String>()
            .where((value) => value.trim().isNotEmpty)
            .join(' '),
        visitorIdType: visitor?['id_type']?.toString(),
        visitorIdNumber: visitor?['id_number']?.toString(),
        patientId: patientId,
        patientName: _profileName(profile),
        patientNumber: patient?['patient_number']?.toString(),
        admissionId: admissionId,
        admissionNumber: admission?['admission_number']?.toString(),
        wardId: wardId,
        wardName: ward?['name']?.toString(),
        roomId: roomId,
        roomNumber: room?['room_number']?.toString(),
        roomName: room?['room_name']?.toString(),
        bedId: bedId,
        bedNumber: bed?['bed_number']?.toString(),
        bedLabel: bed?['bed_label']?.toString(),
        checkinMethod: row['checkin_method']?.toString() ?? 'qr',
        identityVerified: row['identity_verified'] == true,
        verificationMethod: row['verification_method']?.toString(),
        checkinAt: _dateTime(row['checkin_at']),
        checkoutAt: _dateTime(row['checkout_at']),
        notes: row['notes']?.toString(),
      );
    }).toList();
  }

  // ---------------------------------------------------------------------------
  // WORKSPACE
  // ---------------------------------------------------------------------------

  Future<HospitalVisitorWorkspace> loadWorkspace(
    String hospitalId,
  ) async {
    final results = await Future.wait([
      getDashboardStats(hospitalId),
      getVisitors(hospitalId),
      getVisitorAdmissionOptions(hospitalId),
      getVisitorPasses(hospitalId),
      getVisitorCheckins(hospitalId),
      getRestrictions(hospitalId),
    ]);

    return HospitalVisitorWorkspace(
      hospitalId: hospitalId,
      stats: results[0] as VisitorDashboardStats,
      visitors: results[1] as List<HospitalVisitorRecord>,
      admissions: results[2] as List<VisitorAdmissionOption>,
      passes: results[3] as List<HospitalVisitorPassRecord>,
      checkins: results[4] as List<HospitalVisitorCheckinRecord>,
      restrictions: results[5] as List<PatientVisitorRestrictionRecord>,
    );
  }

  // ---------------------------------------------------------------------------
  // INTERNAL FETCH HELPERS
  // ---------------------------------------------------------------------------

  Future<List<Map<String, dynamic>>> _fetchPatients(
    Iterable<String> ids,
  ) async {
    final result = <Map<String, dynamic>>[];

    for (final chunk in _chunks(ids)) {
      final response = await _supabase
          .from('patients')
          .select(
            'id, profile_id, patient_number, phone, email, '
            'date_of_birth, gender, blood_type',
          )
          .inFilter('id', chunk);

      result.addAll(_mapList(response));
    }

    return result;
  }

  Future<List<Map<String, dynamic>>> _fetchProfiles(
    Iterable<String> ids,
  ) async {
    final result = <Map<String, dynamic>>[];

    for (final chunk in _chunks(ids)) {
      final response = await _supabase
          .from('profiles')
          .select(
            'id, user_id, first_name, surname, email, phone, phone_number',
          )
          .inFilter('user_id', chunk);

      result.addAll(_mapList(response));
    }

    return result;
  }

  Future<List<Map<String, dynamic>>> _fetchAdmissions(
    Iterable<String> ids,
  ) async {
    final result = <Map<String, dynamic>>[];

    for (final chunk in _chunks(ids)) {
      final response = await _supabase
          .from('hospital_admissions')
          .select(
            'id, hospital_id, patient_id, admission_number, '
            'admission_type, status, visitor_status, admitted_at, '
            'expected_discharge_at, discharged_at',
          )
          .inFilter('id', chunk);

      result.addAll(_mapList(response));
    }

    return result;
  }

  Future<List<Map<String, dynamic>>> _fetchVisitors(
    Iterable<String> ids,
  ) async {
    final result = <Map<String, dynamic>>[];

    for (final chunk in _chunks(ids)) {
      final response = await _supabase
          .from('hospital_visitors')
          .select(
            'id, hospital_id, first_name, surname, id_type, '
            'id_number, phone, email, is_blocked, blocked_reason',
          )
          .inFilter('id', chunk);

      result.addAll(_mapList(response));
    }

    return result;
  }

  Future<List<Map<String, dynamic>>> _fetchPasses(
    Iterable<String> ids,
  ) async {
    final result = <Map<String, dynamic>>[];

    for (final chunk in _chunks(ids)) {
      final response = await _supabase
          .from('visitor_passes')
          .select(
            'id, pass_number, status, pass_type, '
            'relationship_to_patient, valid_from, valid_until',
          )
          .inFilter('id', chunk);

      result.addAll(_mapList(response));
    }

    return result;
  }

  Future<List<Map<String, dynamic>>> _fetchWards(
    Iterable<String> ids,
  ) async {
    final result = <Map<String, dynamic>>[];

    for (final chunk in _chunks(ids)) {
      final response = await _supabase
          .from('hospital_wards')
          .select(
            'id, hospital_id, name, ward_type',
          )
          .inFilter('id', chunk);

      result.addAll(_mapList(response));
    }

    return result;
  }

  Future<List<Map<String, dynamic>>> _fetchRooms(
    Iterable<String> ids,
  ) async {
    final result = <Map<String, dynamic>>[];

    for (final chunk in _chunks(ids)) {
      final response = await _supabase
          .from('hospital_rooms')
          .select(
            'id, hospital_id, ward_id, room_number, room_name, room_type',
          )
          .inFilter('id', chunk);

      result.addAll(_mapList(response));
    }

    return result;
  }

  Future<List<Map<String, dynamic>>> _fetchBeds(
    Iterable<String> ids,
  ) async {
    final result = <Map<String, dynamic>>[];

    for (final chunk in _chunks(ids)) {
      final response = await _supabase
          .from('hospital_beds')
          .select(
            'id, hospital_id, ward_id, room_id, bed_number, '
            'bed_label, bed_type, status',
          )
          .inFilter('id', chunk);

      result.addAll(_mapList(response));
    }

    return result;
  }

  Future<List<Map<String, dynamic>>> _fetchActiveAssignments({
    required String hospitalId,
    required Iterable<String> admissionIds,
  }) async {
    final result = <Map<String, dynamic>>[];

    for (final chunk in _chunks(admissionIds)) {
      final response = await _supabase
          .from('patient_bed_assignments')
          .select(
            'id, hospital_id, admission_id, patient_id, '
            'ward_id, room_id, bed_id, status, assigned_at, ended_at',
          )
          .eq('hospital_id', hospitalId)
          .inFilter('admission_id', chunk)
          .eq('status', 'active')
          .isFilter('ended_at', null);

      result.addAll(_mapList(response));
    }

    return result;
  }

  Future<List<Map<String, dynamic>>> _fetchOpenCheckinsForPasses({
    required String hospitalId,
    required Iterable<String> passIds,
  }) async {
    final result = <Map<String, dynamic>>[];

    for (final chunk in _chunks(passIds)) {
      final response = await _supabase
          .from('visitor_checkins')
          .select(
            'id, visitor_pass_id, checkin_at, checkout_at',
          )
          .eq('hospital_id', hospitalId)
          .inFilter('visitor_pass_id', chunk)
          .isFilter('checkout_at', null);

      result.addAll(_mapList(response));
    }

    return result;
  }
}

// =============================================================================
// VISITOR RECORD
// =============================================================================

class HospitalVisitorRecord {
  const HospitalVisitorRecord({
    required this.visitorId,
    required this.hospitalId,
    required this.firstName,
    required this.surname,
    required this.idType,
    required this.idNumber,
    required this.phone,
    required this.email,
    required this.vehicleRegistration,
    required this.photoUrl,
    required this.isBlocked,
    required this.blockedReason,
    required this.blockedAt,
    required this.notes,
    required this.createdAt,
    required this.updatedAt,
  });

  final String visitorId;
  final String hospitalId;

  final String firstName;
  final String surname;

  final String idType;
  final String? idNumber;

  final String? phone;
  final String? email;
  final String? vehicleRegistration;
  final String? photoUrl;

  final bool isBlocked;
  final String? blockedReason;
  final DateTime? blockedAt;

  final String? notes;

  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory HospitalVisitorRecord.fromMap(
    Map<String, dynamic> map,
  ) {
    return HospitalVisitorRecord(
      visitorId: map['id']?.toString() ?? '',
      hospitalId: map['hospital_id']?.toString() ?? '',
      firstName: map['first_name']?.toString() ?? '',
      surname: map['surname']?.toString() ?? '',
      idType: map['id_type']?.toString() ?? 'south_african_id',
      idNumber: map['id_number']?.toString(),
      phone: map['phone']?.toString(),
      email: map['email']?.toString(),
      vehicleRegistration: map['vehicle_registration']?.toString(),
      photoUrl: map['photo_url']?.toString(),
      isBlocked: map['is_blocked'] == true,
      blockedReason: map['blocked_reason']?.toString(),
      blockedAt: DateTime.tryParse(
        map['blocked_at']?.toString() ?? '',
      )?.toLocal(),
      notes: map['notes']?.toString(),
      createdAt: DateTime.tryParse(
        map['created_at']?.toString() ?? '',
      )?.toLocal(),
      updatedAt: DateTime.tryParse(
        map['updated_at']?.toString() ?? '',
      )?.toLocal(),
    );
  }

  String get fullName {
    final result = '$firstName $surname'.trim();

    return result.isEmpty ? 'Unknown visitor' : result;
  }

  String get searchText {
    return [
      fullName,
      idType,
      idNumber,
      phone,
      email,
      vehicleRegistration,
      blockedReason,
      notes,
    ].whereType<String>().join(' ').toLowerCase();
  }
}

// =============================================================================
// ADMISSION OPTION
// =============================================================================

class VisitorAdmissionOption {
  const VisitorAdmissionOption({
    required this.hospitalId,
    required this.admissionId,
    required this.admissionNumber,
    required this.admissionType,
    required this.admissionStatus,
    required this.visitorStatus,
    required this.patientId,
    required this.patientName,
    required this.patientNumber,
    required this.wardId,
    required this.wardName,
    required this.wardType,
    required this.roomId,
    required this.roomNumber,
    required this.roomName,
    required this.bedId,
    required this.bedNumber,
    required this.bedLabel,
    required this.admittedAt,
    required this.expectedDischargeAt,
  });

  final String hospitalId;

  final String admissionId;
  final String? admissionNumber;
  final String admissionType;
  final String admissionStatus;
  final String visitorStatus;

  final String patientId;
  final String patientName;
  final String? patientNumber;

  final String? wardId;
  final String? wardName;
  final String? wardType;

  final String? roomId;
  final String? roomNumber;
  final String? roomName;

  final String? bedId;
  final String? bedNumber;
  final String? bedLabel;

  final DateTime? admittedAt;
  final DateTime? expectedDischargeAt;

  String get displayAdmissionNumber {
    final value = admissionNumber?.trim();

    if (value != null && value.isNotEmpty) {
      return value;
    }

    return admissionId.length >= 8
        ? 'ADM-${admissionId.substring(0, 8).toUpperCase()}'
        : admissionId;
  }

  String get displayLocation {
    final parts = <String>[
      if (wardName != null && wardName!.trim().isNotEmpty) wardName!,
      if (roomNumber != null && roomNumber!.trim().isNotEmpty)
        'Room $roomNumber',
      if (bedLabel != null && bedLabel!.trim().isNotEmpty)
        bedLabel!
      else if (bedNumber != null && bedNumber!.trim().isNotEmpty)
        'Bed $bedNumber',
    ];

    return parts.isEmpty ? 'No bed assigned' : parts.join(' • ');
  }

  String get searchText {
    return [
      patientName,
      patientNumber,
      admissionNumber,
      admissionType,
      admissionStatus,
      visitorStatus,
      wardName,
      roomName,
      roomNumber,
      bedLabel,
      bedNumber,
    ].whereType<String>().join(' ').toLowerCase();
  }
}

// =============================================================================
// VISITOR RESTRICTION
// =============================================================================

class PatientVisitorRestrictionRecord {
  const PatientVisitorRestrictionRecord({
    required this.restrictionId,
    required this.hospitalId,
    required this.patientId,
    required this.patientName,
    required this.patientNumber,
    required this.admissionId,
    required this.admissionNumber,
    required this.restrictionType,
    required this.reason,
    required this.startsAt,
    required this.endsAt,
    required this.isActive,
    required this.revokedAt,
    required this.revocationReason,
    required this.createdAt,
    required this.updatedAt,
  });

  final String restrictionId;
  final String hospitalId;

  final String patientId;
  final String patientName;
  final String? patientNumber;

  final String? admissionId;
  final String? admissionNumber;

  final String restrictionType;
  final String reason;

  final DateTime? startsAt;
  final DateTime? endsAt;

  final bool isActive;

  final DateTime? revokedAt;
  final String? revocationReason;

  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get isCurrentlyActive {
    if (!isActive) {
      return false;
    }

    final now = DateTime.now();

    if (startsAt != null && startsAt!.isAfter(now)) {
      return false;
    }

    if (endsAt != null && !endsAt!.isAfter(now)) {
      return false;
    }

    return true;
  }

  String get searchText {
    return [
      patientName,
      patientNumber,
      admissionNumber,
      restrictionType,
      reason,
      revocationReason,
    ].whereType<String>().join(' ').toLowerCase();
  }
}

// =============================================================================
// VISITOR PASS
// =============================================================================

class HospitalVisitorPassRecord {
  const HospitalVisitorPassRecord({
    required this.visitorPassId,
    required this.hospitalId,
    required this.visitorId,
    required this.visitorName,
    required this.visitorIdType,
    required this.visitorIdNumber,
    required this.visitorPhone,
    required this.visitorBlocked,
    required this.patientId,
    required this.patientName,
    required this.patientNumber,
    required this.admissionId,
    required this.admissionNumber,
    required this.requestedWardId,
    required this.requestedWardName,
    required this.passNumber,
    required this.qrToken,
    required this.passType,
    required this.status,
    required this.relationshipToPatient,
    required this.visitPurpose,
    required this.validFrom,
    required this.validUntil,
    required this.maxEntries,
    required this.entriesUsed,
    required this.requiresIdentityVerification,
    required this.restrictionOverride,
    required this.overrideReason,
    required this.approvedAt,
    required this.revokedAt,
    required this.revocationReason,
    required this.notes,
    required this.createdAt,
    required this.updatedAt,
    required this.openCheckinId,
    required this.checkedInAt,
  });

  final String visitorPassId;
  final String hospitalId;

  final String visitorId;
  final String visitorName;
  final String? visitorIdType;
  final String? visitorIdNumber;
  final String? visitorPhone;
  final bool visitorBlocked;

  final String patientId;
  final String patientName;
  final String? patientNumber;

  final String admissionId;
  final String? admissionNumber;

  final String? requestedWardId;
  final String? requestedWardName;

  final String passNumber;
  final String qrToken;

  final String passType;
  final String status;

  final String relationshipToPatient;
  final String? visitPurpose;

  final DateTime? validFrom;
  final DateTime? validUntil;

  final int? maxEntries;
  final int entriesUsed;

  final bool requiresIdentityVerification;
  final bool restrictionOverride;
  final String? overrideReason;

  final DateTime? approvedAt;
  final DateTime? revokedAt;
  final String? revocationReason;

  final String? notes;

  final DateTime? createdAt;
  final DateTime? updatedAt;

  final String? openCheckinId;
  final DateTime? checkedInAt;

  bool get isCurrentlyCheckedIn {
    return openCheckinId != null;
  }

  bool get isExpired {
    final expiry = validUntil;

    if (expiry == null) {
      return status == 'expired';
    }

    return status == 'expired' || !expiry.isAfter(DateTime.now());
  }

  bool get canApprove {
    return status == 'draft' || status == 'pending';
  }

  bool get canRevoke {
    return !isCurrentlyCheckedIn &&
        !{
          'revoked',
          'expired',
          'used',
        }.contains(status);
  }

  String get searchText {
    return [
      passNumber,
      visitorName,
      visitorIdNumber,
      visitorPhone,
      patientName,
      patientNumber,
      admissionNumber,
      requestedWardName,
      passType,
      status,
      relationshipToPatient,
      visitPurpose,
    ].whereType<String>().join(' ').toLowerCase();
  }
}

// =============================================================================
// VISITOR CHECK-IN
// =============================================================================

class HospitalVisitorCheckinRecord {
  const HospitalVisitorCheckinRecord({
    required this.checkinId,
    required this.hospitalId,
    required this.visitorPassId,
    required this.passNumber,
    required this.visitorId,
    required this.visitorName,
    required this.visitorIdType,
    required this.visitorIdNumber,
    required this.patientId,
    required this.patientName,
    required this.patientNumber,
    required this.admissionId,
    required this.admissionNumber,
    required this.wardId,
    required this.wardName,
    required this.roomId,
    required this.roomNumber,
    required this.roomName,
    required this.bedId,
    required this.bedNumber,
    required this.bedLabel,
    required this.checkinMethod,
    required this.identityVerified,
    required this.verificationMethod,
    required this.checkinAt,
    required this.checkoutAt,
    required this.notes,
  });

  final String checkinId;
  final String hospitalId;

  final String visitorPassId;
  final String? passNumber;

  final String visitorId;
  final String visitorName;
  final String? visitorIdType;
  final String? visitorIdNumber;

  final String patientId;
  final String patientName;
  final String? patientNumber;

  final String admissionId;
  final String? admissionNumber;

  final String? wardId;
  final String? wardName;

  final String? roomId;
  final String? roomNumber;
  final String? roomName;

  final String? bedId;
  final String? bedNumber;
  final String? bedLabel;

  final String checkinMethod;
  final bool identityVerified;
  final String? verificationMethod;

  final DateTime? checkinAt;
  final DateTime? checkoutAt;

  final String? notes;

  bool get isOpen {
    return checkoutAt == null;
  }

  String get displayLocation {
    final parts = <String>[
      if (wardName != null && wardName!.trim().isNotEmpty) wardName!,
      if (roomNumber != null && roomNumber!.trim().isNotEmpty)
        'Room $roomNumber',
      if (bedLabel != null && bedLabel!.trim().isNotEmpty)
        bedLabel!
      else if (bedNumber != null && bedNumber!.trim().isNotEmpty)
        'Bed $bedNumber',
    ];

    return parts.isEmpty ? 'Location not recorded' : parts.join(' • ');
  }

  String get searchText {
    return [
      passNumber,
      visitorName,
      visitorIdNumber,
      patientName,
      patientNumber,
      admissionNumber,
      wardName,
      roomName,
      roomNumber,
      bedLabel,
      bedNumber,
      checkinMethod,
      verificationMethod,
    ].whereType<String>().join(' ').toLowerCase();
  }
}

// =============================================================================
// VISITOR DASHBOARD STATS
// =============================================================================

class VisitorDashboardStats {
  const VisitorDashboardStats({
    required this.hospitalId,
    required this.totalVisitors,
    required this.blockedVisitors,
    required this.pendingPasses,
    required this.approvedPasses,
    required this.activePasses,
    required this.expiredPasses,
    required this.revokedPasses,
    required this.currentlyCheckedIn,
    required this.checkinsToday,
    required this.checkoutsToday,
    required this.deniedToday,
    required this.activeRestrictions,
    required this.generatedAt,
  });

  final String hospitalId;

  final int totalVisitors;
  final int blockedVisitors;

  final int pendingPasses;
  final int approvedPasses;
  final int activePasses;
  final int expiredPasses;
  final int revokedPasses;

  final int currentlyCheckedIn;
  final int checkinsToday;
  final int checkoutsToday;
  final int deniedToday;

  final int activeRestrictions;

  final DateTime? generatedAt;

  factory VisitorDashboardStats.fromMap(
    Map<String, dynamic> map,
  ) {
    int readInt(String key) {
      final value = map[key];

      if (value is int) {
        return value;
      }

      if (value is num) {
        return value.toInt();
      }

      return int.tryParse(
            value?.toString() ?? '',
          ) ??
          0;
    }

    return VisitorDashboardStats(
      hospitalId: map['hospital_id']?.toString() ?? '',
      totalVisitors: readInt('total_visitors'),
      blockedVisitors: readInt('blocked_visitors'),
      pendingPasses: readInt('pending_passes'),
      approvedPasses: readInt('approved_passes'),
      activePasses: readInt('active_passes'),
      expiredPasses: readInt('expired_passes'),
      revokedPasses: readInt('revoked_passes'),
      currentlyCheckedIn: readInt('currently_checked_in'),
      checkinsToday: readInt('checkins_today'),
      checkoutsToday: readInt('checkouts_today'),
      deniedToday: readInt('denied_today'),
      activeRestrictions: readInt('active_restrictions'),
      generatedAt: DateTime.tryParse(
        map['generated_at']?.toString() ?? '',
      )?.toLocal(),
    );
  }
}

// =============================================================================
// PASS CREATION RESULT
// =============================================================================

class VisitorPassCreationResult {
  const VisitorPassCreationResult({
    required this.visitorPassId,
    required this.passNumber,
    required this.qrToken,
    required this.status,
    required this.validFrom,
    required this.validUntil,
  });

  final String visitorPassId;
  final String passNumber;
  final String qrToken;
  final String status;

  final DateTime? validFrom;
  final DateTime? validUntil;

  factory VisitorPassCreationResult.fromMap(
    Map<String, dynamic> map,
  ) {
    return VisitorPassCreationResult(
      visitorPassId: map['visitor_pass_id']?.toString() ?? '',
      passNumber: map['pass_number']?.toString() ?? '',
      qrToken: map['qr_token']?.toString() ?? '',
      status: map['status']?.toString() ?? 'pending',
      validFrom: DateTime.tryParse(
        map['valid_from']?.toString() ?? '',
      )?.toLocal(),
      validUntil: DateTime.tryParse(
        map['valid_until']?.toString() ?? '',
      )?.toLocal(),
    );
  }
}

// =============================================================================
// PASS EVALUATION
// =============================================================================

class VisitorPassEvaluation {
  const VisitorPassEvaluation({
    required this.allowed,
    required this.reason,
    required this.hospitalId,
    required this.visitorPassId,
    required this.passNumber,
    required this.passStatus,
    required this.passType,
    required this.visitorId,
    required this.visitorName,
    required this.visitorIdType,
    required this.visitorIdNumber,
    required this.patientId,
    required this.patientName,
    required this.patientNumber,
    required this.admissionId,
    required this.relationshipToPatient,
    required this.wardId,
    required this.wardName,
    required this.roomId,
    required this.roomNumber,
    required this.bedId,
    required this.bedLabel,
    required this.requiresIdentityVerification,
    required this.identityVerified,
    required this.visitorMode,
    required this.maximumVisitors,
    required this.currentOpenVisitors,
    required this.showRoomNumber,
    required this.showBedLabel,
    required this.specialInstructions,
    required this.validFrom,
    required this.validUntil,
    required this.entriesUsed,
    required this.maxEntries,
    required this.restrictionOverride,
  });

  final bool allowed;
  final String reason;

  final String? hospitalId;

  final String? visitorPassId;
  final String? passNumber;
  final String? passStatus;
  final String? passType;

  final String? visitorId;
  final String? visitorName;
  final String? visitorIdType;
  final String? visitorIdNumber;

  final String? patientId;
  final String? patientName;
  final String? patientNumber;

  final String? admissionId;
  final String? relationshipToPatient;

  final String? wardId;
  final String? wardName;

  final String? roomId;
  final String? roomNumber;

  final String? bedId;
  final String? bedLabel;

  final bool requiresIdentityVerification;
  final bool identityVerified;

  final String? visitorMode;

  final int maximumVisitors;
  final int currentOpenVisitors;

  final bool showRoomNumber;
  final bool showBedLabel;

  final String? specialInstructions;

  final DateTime? validFrom;
  final DateTime? validUntil;

  final int entriesUsed;
  final int? maxEntries;

  final bool restrictionOverride;

  factory VisitorPassEvaluation.fromMap(
    Map<String, dynamic> map,
  ) {
    int intValue(dynamic value) {
      if (value is int) {
        return value;
      }

      if (value is num) {
        return value.toInt();
      }

      return int.tryParse(
            value?.toString() ?? '',
          ) ??
          0;
    }

    bool boolValue(dynamic value) {
      if (value is bool) {
        return value;
      }

      return value?.toString().toLowerCase() == 'true';
    }

    return VisitorPassEvaluation(
      allowed: boolValue(map['allowed']),
      reason: map['reason']?.toString() ?? 'No reason supplied',
      hospitalId: map['hospital_id']?.toString(),
      visitorPassId: map['visitor_pass_id']?.toString(),
      passNumber: map['pass_number']?.toString(),
      passStatus: map['pass_status']?.toString(),
      passType: map['pass_type']?.toString(),
      visitorId: map['visitor_id']?.toString(),
      visitorName: map['visitor_name']?.toString(),
      visitorIdType: map['visitor_id_type']?.toString(),
      visitorIdNumber: map['visitor_id_number']?.toString(),
      patientId: map['patient_id']?.toString(),
      patientName: map['patient_name']?.toString(),
      patientNumber: map['patient_number']?.toString(),
      admissionId: map['admission_id']?.toString(),
      relationshipToPatient: map['relationship_to_patient']?.toString(),
      wardId: map['ward_id']?.toString(),
      wardName: map['ward_name']?.toString(),
      roomId: map['room_id']?.toString(),
      roomNumber: map['room_number']?.toString(),
      bedId: map['bed_id']?.toString(),
      bedLabel: map['bed_label']?.toString(),
      requiresIdentityVerification: boolValue(
        map['requires_identity_verification'],
      ),
      identityVerified: boolValue(map['identity_verified']),
      visitorMode: map['visitor_mode']?.toString(),
      maximumVisitors: intValue(map['maximum_visitors']),
      currentOpenVisitors: intValue(map['current_open_visitors']),
      showRoomNumber: boolValue(map['show_room_number']),
      showBedLabel: boolValue(map['show_bed_label']),
      specialInstructions: map['special_instructions']?.toString(),
      validFrom: DateTime.tryParse(
        map['valid_from']?.toString() ?? '',
      )?.toLocal(),
      validUntil: DateTime.tryParse(
        map['valid_until']?.toString() ?? '',
      )?.toLocal(),
      entriesUsed: intValue(map['entries_used']),
      maxEntries:
          map['max_entries'] == null ? null : intValue(map['max_entries']),
      restrictionOverride: boolValue(map['restriction_override']),
    );
  }
}

// =============================================================================
// CHECK-IN RESULT
// =============================================================================

class VisitorCheckinResult {
  const VisitorCheckinResult({
    required this.success,
    required this.reason,
    required this.checkinId,
    required this.passStatus,
    required this.entriesUsed,
    required this.evaluation,
  });

  final bool success;
  final String? reason;
  final String? checkinId;
  final String? passStatus;
  final int entriesUsed;
  final VisitorPassEvaluation? evaluation;

  factory VisitorCheckinResult.fromMap(
    Map<String, dynamic> map,
  ) {
    final evaluationValue = map['evaluation'];

    return VisitorCheckinResult(
      success: map['success'] == true || map['success']?.toString() == 'true',
      reason: map['reason']?.toString(),
      checkinId: map['checkin_id']?.toString(),
      passStatus: map['pass_status']?.toString(),
      entriesUsed: map['entries_used'] is num
          ? (map['entries_used'] as num).toInt()
          : int.tryParse(
                map['entries_used']?.toString() ?? '',
              ) ??
              0,
      evaluation: evaluationValue is Map
          ? VisitorPassEvaluation.fromMap(
              Map<String, dynamic>.from(
                evaluationValue,
              ),
            )
          : null,
    );
  }
}

// =============================================================================
// CHECKOUT RESULT
// =============================================================================

class VisitorCheckoutResult {
  const VisitorCheckoutResult({
    required this.success,
    required this.reason,
    required this.checkinId,
    required this.checkoutAt,
  });

  final bool success;
  final String? reason;
  final String? checkinId;
  final DateTime? checkoutAt;

  factory VisitorCheckoutResult.fromMap(
    Map<String, dynamic> map,
  ) {
    return VisitorCheckoutResult(
      success: map['success'] == true || map['success']?.toString() == 'true',
      reason: map['reason']?.toString(),
      checkinId: map['checkin_id']?.toString(),
      checkoutAt: DateTime.tryParse(
        map['checkout_at']?.toString() ?? '',
      )?.toLocal(),
    );
  }
}

// =============================================================================
// COMPLETE VISITOR WORKSPACE
// =============================================================================

class HospitalVisitorWorkspace {
  const HospitalVisitorWorkspace({
    required this.hospitalId,
    required this.stats,
    required this.visitors,
    required this.admissions,
    required this.passes,
    required this.checkins,
    required this.restrictions,
  });

  final String hospitalId;

  final VisitorDashboardStats stats;

  final List<HospitalVisitorRecord> visitors;
  final List<VisitorAdmissionOption> admissions;
  final List<HospitalVisitorPassRecord> passes;
  final List<HospitalVisitorCheckinRecord> checkins;
  final List<PatientVisitorRestrictionRecord> restrictions;

  List<HospitalVisitorCheckinRecord> get openCheckins {
    return checkins.where((checkin) => checkin.isOpen).toList();
  }

  List<HospitalVisitorPassRecord> get pendingPasses {
    return passes.where((pass) => pass.status == 'pending').toList();
  }

  List<HospitalVisitorPassRecord> get usablePasses {
    return passes.where((pass) {
      return {
            'approved',
            'active',
          }.contains(pass.status) &&
          !pass.isExpired &&
          !pass.visitorBlocked;
    }).toList();
  }

  List<PatientVisitorRestrictionRecord> get activeRestrictions {
    return restrictions
        .where(
          (restriction) => restriction.isCurrentlyActive,
        )
        .toList();
  }
}
