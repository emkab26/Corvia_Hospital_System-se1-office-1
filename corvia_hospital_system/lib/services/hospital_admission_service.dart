import 'package:supabase_flutter/supabase_flutter.dart';

import 'hospital_structure_service.dart';

class HospitalAdmissionService {
  HospitalAdmissionService({
    SupabaseClient? supabase,
    HospitalStructureService? structureService,
  })  : _supabase = supabase ?? Supabase.instance.client,
        _structureService =
            structureService ?? HospitalStructureService(supabase: supabase);

  final SupabaseClient _supabase;
  final HospitalStructureService _structureService;

  // ---------------------------------------------------------------------------
  // GENERAL HELPERS
  // ---------------------------------------------------------------------------

  List<Map<String, dynamic>> _mapList(dynamic data) {
    if (data is! List) {
      return [];
    }

    return data
        .whereType<Map>()
        .map(
          (item) => Map<String, dynamic>.from(item),
        )
        .toList();
  }

  String? _nullableText(String? value) {
    final cleaned = value?.trim();

    if (cleaned == null || cleaned.isEmpty) {
      return null;
    }

    return cleaned;
  }

  String? _extractScalarString(dynamic value) {
    if (value == null) {
      return null;
    }

    if (value is String) {
      return value;
    }

    if (value is Map) {
      if (value.isEmpty) {
        return null;
      }

      return value.values.first?.toString();
    }

    if (value is List && value.isNotEmpty) {
      return _extractScalarString(value.first);
    }

    return value.toString();
  }

  bool _extractScalarBool(dynamic value) {
    if (value is bool) {
      return value;
    }

    if (value is Map && value.isNotEmpty) {
      return _extractScalarBool(value.values.first);
    }

    if (value is List && value.isNotEmpty) {
      return _extractScalarBool(value.first);
    }

    final text = value?.toString().toLowerCase();

    return text == 'true' || text == '1';
  }

  DateTime? _dateTime(dynamic value) {
    if (value == null) {
      return null;
    }

    return DateTime.tryParse(value.toString())?.toLocal();
  }

  List<List<String>> _chunks(
    Iterable<String> values, {
    int size = 100,
  }) {
    final source = values.toSet().toList();
    final result = <List<String>>[];

    for (var index = 0; index < source.length; index += size) {
      final end = index + size > source.length ? source.length : index + size;

      result.add(source.sublist(index, end));
    }

    return result;
  }

  String _patientDisplayName(
    Map<String, dynamic>? patient,
    Map<String, dynamic>? profile,
  ) {
    for (final source in [patient, profile]) {
      final firstName = source?['first_name']?.toString().trim() ?? '';
      final surname = source?['surname']?.toString().trim() ?? '';
      final fullName = '$firstName $surname'.trim();
      if (fullName.isNotEmpty) return fullName;
    }
    for (final source in [patient, profile]) {
      final email = source?['email']?.toString().trim() ?? '';
      if (email.isNotEmpty) return email;
    }

    return 'Unknown patient';
  }

  // ---------------------------------------------------------------------------
  // HOSPITALS
  // ---------------------------------------------------------------------------

  Future<List<Map<String, dynamic>>> getAdminHospitals() {
    return _structureService.getAdminHospitals();
  }

  // ---------------------------------------------------------------------------
  // PATIENTS AVAILABLE TO THIS HOSPITAL
  // ---------------------------------------------------------------------------

  Future<List<HospitalAdmissionPatient>> getHospitalPatients(
    String hospitalId,
  ) async {
    final linkData = await _supabase
        .from('patient_hospital_links')
        .select(
          'id, hospital_id, patient_id, local_patient_number, '
          'status, linked_at, last_treated_at, discharged_at',
        )
        .eq('hospital_id', hospitalId);

    final links = _mapList(linkData);

    final patientIds = links
        .map(
          (link) => link['patient_id']?.toString(),
        )
        .whereType<String>()
        .where((id) => id.trim().isNotEmpty)
        .toSet();

    /*
     * Keep support for existing Corvia patient records that still use
     * patients.hospital_id directly.
     */
    try {
      final legacyPatientData = await _supabase
          .from('patients')
          .select(
            'id, profile_id, hospital_id, patient_number, date_of_birth, '
            'gender, blood_type, phone, email, is_active',
          )
          .eq('hospital_id', hospitalId);

      final legacyPatients = _mapList(legacyPatientData);

      for (final patient in legacyPatients) {
        final id = patient['id']?.toString();

        if (id != null && id.isNotEmpty) {
          patientIds.add(id);
        }
      }
    } catch (_) {
      // The patient-hospital link table remains the source of truth.
    }

    if (patientIds.isEmpty) {
      return [];
    }

    final patients = await _fetchPatients(patientIds);
    final profileIds = patients
        .map(
          (patient) => patient['profile_id']?.toString(),
        )
        .whereType<String>()
        .where((id) => id.trim().isNotEmpty)
        .toSet();

    final profiles = await _fetchProfiles(profileIds);

    final linkByPatientId = <String, Map<String, dynamic>>{
      for (final link in links)
        if (link['patient_id'] != null) link['patient_id'].toString(): link,
    };

    final profileById = <String, Map<String, dynamic>>{
      for (final profile in profiles)
        if (profile['user_id'] != null) profile['user_id'].toString(): profile,
    };

    final result = <HospitalAdmissionPatient>[];

    for (final patient in patients) {
      final patientId = patient['id']?.toString();

      if (patientId == null || patientId.isEmpty) {
        continue;
      }

      final profileId = patient['profile_id']?.toString();
      final profile = profileId == null ? null : profileById[profileId];

      final link = linkByPatientId[patientId];

      result.add(
        HospitalAdmissionPatient(
          patientId: patientId,
          profileId: profileId,
          patientHospitalLinkId: link?['id']?.toString(),
          hospitalId: hospitalId,
          patientName: _patientDisplayName(patient, profile),
          patientNumber: patient['patient_number']?.toString(),
          localPatientNumber: link?['local_patient_number']?.toString(),
          dateOfBirth: _dateTime(patient['date_of_birth']),
          gender: patient['gender']?.toString(),
          bloodType: patient['blood_type']?.toString(),
          phone: patient['phone']?.toString() ??
              profile?['phone']?.toString() ??
              profile?['phone_number']?.toString(),
          email: patient['email']?.toString() ?? profile?['email']?.toString(),
          linkStatus: link?['status']?.toString() ?? 'active',
          isActive: patient['is_active'] != false,
          linkedAt: _dateTime(link?['linked_at']),
          lastTreatedAt: _dateTime(link?['last_treated_at']),
          dischargedAt: _dateTime(link?['discharged_at']),
        ),
      );
    }

    result.sort(
      (a, b) => a.patientName.toLowerCase().compareTo(
            b.patientName.toLowerCase(),
          ),
    );

    return result;
  }

  Future<List<Map<String, dynamic>>> _fetchPatients(
    Iterable<String> patientIds,
  ) async {
    final result = <Map<String, dynamic>>[];

    for (final chunk in _chunks(patientIds)) {
      final data = await _supabase
          .from('patients')
          .select(
            'id, profile_id, hospital_id, patient_number, first_name, surname, date_of_birth, '
            'gender, blood_type, phone, email, is_active',
          )
          .inFilter('id', chunk);

      result.addAll(_mapList(data));
    }

    return result;
  }

  Future<List<Map<String, dynamic>>> _fetchProfiles(
    Iterable<String> profileIds,
  ) async {
    final result = <Map<String, dynamic>>[];

    for (final chunk in _chunks(profileIds)) {
      final data = await _supabase
          .from('profiles')
          .select(
            'user_id, first_name, surname, email, phone, phone_number',
          )
          .inFilter('user_id', chunk);

      result.addAll(_mapList(data));
    }

    return result;
  }

  // ---------------------------------------------------------------------------
  // ADMISSIONS
  // ---------------------------------------------------------------------------

  Future<List<HospitalAdmissionRecord>> getAdmissions(
    String hospitalId, {
    Set<String>? statuses,
  }) async {
    dynamic query = _supabase
        .from('hospital_admissions')
        .select(
          'id, hospital_id, patient_id, patient_hospital_link_id, '
          'admission_number, admission_type, status, admission_reason, '
          'admitting_diagnosis, admitting_doctor_profile_id, source_type, '
          'source_transfer_id, admitted_at, expected_discharge_at, '
          'discharged_at, discharge_reason, visitor_status, '
          'created_at, updated_at',
        )
        .eq('hospital_id', hospitalId);

    if (statuses != null && statuses.isNotEmpty) {
      query = query.inFilter(
        'status',
        statuses.toList(),
      );
    }

    final admissionData = await query.order(
      'created_at',
      ascending: false,
    );

    final admissions = _mapList(admissionData);

    if (admissions.isEmpty) {
      return [];
    }

    final admissionIds = admissions
        .map(
          (admission) => admission['id']?.toString(),
        )
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .toSet();

    final patientIds = admissions
        .map(
          (admission) => admission['patient_id']?.toString(),
        )
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .toSet();

    final results = await Future.wait([
      _fetchPatients(patientIds),
      _fetchActiveAssignments(
        hospitalId: hospitalId,
        admissionIds: admissionIds,
      ),
      _structureService.loadSnapshot(hospitalId),
    ]);

    final patients = results[0] as List<Map<String, dynamic>>;

    final assignments = results[1] as List<Map<String, dynamic>>;

    final structure = results[2] as HospitalStructureSnapshot;

    final profileIds = patients
        .map(
          (patient) => patient['profile_id']?.toString(),
        )
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .toSet();

    final profiles = await _fetchProfiles(profileIds);

    final patientById = <String, Map<String, dynamic>>{
      for (final patient in patients)
        if (patient['id'] != null) patient['id'].toString(): patient,
    };

    final profileById = <String, Map<String, dynamic>>{
      for (final profile in profiles)
        if (profile['user_id'] != null) profile['user_id'].toString(): profile,
    };

    final assignmentByAdmissionId = <String, Map<String, dynamic>>{
      for (final assignment in assignments)
        if (assignment['admission_id'] != null)
          assignment['admission_id'].toString(): assignment,
    };

    final buildingById = <String, Map<String, dynamic>>{
      for (final building in structure.buildings)
        if (building['id'] != null) building['id'].toString(): building,
    };

    final floorById = <String, Map<String, dynamic>>{
      for (final floor in structure.floors)
        if (floor['id'] != null) floor['id'].toString(): floor,
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

    final result = <HospitalAdmissionRecord>[];

    for (final admission in admissions) {
      final admissionId = admission['id']?.toString();
      final patientId = admission['patient_id']?.toString();

      if (admissionId == null ||
          admissionId.isEmpty ||
          patientId == null ||
          patientId.isEmpty) {
        continue;
      }

      final patient = patientById[patientId];
      final profileId = patient?['profile_id']?.toString();
      final profile = profileId == null ? null : profileById[profileId];

      final assignment = assignmentByAdmissionId[admissionId];

      final bedId = assignment?['bed_id']?.toString();
      final bed = bedId == null ? null : bedById[bedId];

      final roomId =
          assignment?['room_id']?.toString() ?? bed?['room_id']?.toString();

      final wardId =
          assignment?['ward_id']?.toString() ?? bed?['ward_id']?.toString();

      final room = roomId == null ? null : roomById[roomId];

      final ward = wardId == null ? null : wardById[wardId];

      final floorId = ward?['floor_id']?.toString();
      final buildingId = ward?['building_id']?.toString();

      final floor = floorId == null ? null : floorById[floorId];

      final building = buildingId == null ? null : buildingById[buildingId];

      result.add(
        HospitalAdmissionRecord(
          admissionId: admissionId,
          hospitalId: hospitalId,
          patientId: patientId,
          patientHospitalLinkId:
              admission['patient_hospital_link_id']?.toString(),
          patientName: _patientDisplayName(patient, profile),
          patientNumber: patient?['patient_number']?.toString(),
          admissionNumber: admission['admission_number']?.toString(),
          admissionType: admission['admission_type']?.toString() ?? 'elective',
          status: admission['status']?.toString() ?? 'planned',
          admissionReason: admission['admission_reason']?.toString(),
          admittingDiagnosis: admission['admitting_diagnosis']?.toString(),
          admittingDoctorProfileId:
              admission['admitting_doctor_profile_id']?.toString(),
          sourceType: admission['source_type']?.toString() ?? 'direct',
          sourceTransferId: admission['source_transfer_id']?.toString(),
          visitorStatus: admission['visitor_status']?.toString() ??
              'approved_visitors_only',
          admittedAt: _dateTime(admission['admitted_at']),
          expectedDischargeAt: _dateTime(admission['expected_discharge_at']),
          dischargedAt: _dateTime(admission['discharged_at']),
          dischargeReason: admission['discharge_reason']?.toString(),
          createdAt: _dateTime(admission['created_at']),
          updatedAt: _dateTime(admission['updated_at']),
          assignmentId: assignment?['id']?.toString(),
          assignedAt: _dateTime(assignment?['assigned_at']),
          bedId: bedId,
          bedNumber: bed?['bed_number']?.toString(),
          bedLabel: bed?['bed_label']?.toString(),
          bedType: bed?['bed_type']?.toString(),
          bedStatus: bed?['status']?.toString(),
          roomId: roomId,
          roomNumber: room?['room_number']?.toString(),
          roomName: room?['room_name']?.toString(),
          roomType: room?['room_type']?.toString(),
          wardId: wardId,
          wardName: ward?['name']?.toString(),
          wardType: ward?['ward_type']?.toString(),
          floorId: floorId,
          floorName: floor?['name']?.toString(),
          buildingId: buildingId,
          buildingName: building?['name']?.toString(),
        ),
      );
    }

    return result;
  }

  Future<HospitalAdmissionRecord?> getAdmissionById({
    required String hospitalId,
    required String admissionId,
  }) async {
    final admissions = await getAdmissions(hospitalId);

    for (final admission in admissions) {
      if (admission.admissionId == admissionId) {
        return admission;
      }
    }

    return null;
  }

  Future<List<Map<String, dynamic>>> _fetchActiveAssignments({
    required String hospitalId,
    required Iterable<String> admissionIds,
  }) async {
    final result = <Map<String, dynamic>>[];

    for (final chunk in _chunks(admissionIds)) {
      final data = await _supabase
          .from('patient_bed_assignments')
          .select(
            'id, hospital_id, admission_id, patient_id, '
            'ward_id, room_id, bed_id, status, assigned_at, '
            'assigned_by, ended_at',
          )
          .eq('hospital_id', hospitalId)
          .inFilter('admission_id', chunk)
          .eq('status', 'active')
          .isFilter('ended_at', null);

      result.addAll(_mapList(data));
    }

    return result;
  }

  // ---------------------------------------------------------------------------
  // AVAILABLE BEDS
  // ---------------------------------------------------------------------------

  Future<List<HospitalAdmissionBedOption>> getAvailableBeds(
    String hospitalId, {
    String? includeCurrentBedId,
  }) async {
    final boardEntries = await _structureService.getBedBoard(hospitalId);

    final result = boardEntries
        .where((entry) {
          if (!entry.bedActive) {
            return false;
          }

          if (includeCurrentBedId != null &&
              entry.bedId == includeCurrentBedId) {
            return true;
          }

          return !entry.isOccupied && entry.bedStatus == 'available';
        })
        .map(
          (entry) => HospitalAdmissionBedOption(
            hospitalId: entry.hospitalId,
            buildingId: entry.buildingId,
            buildingName: entry.buildingName,
            floorId: entry.floorId,
            floorName: entry.floorName,
            wardId: entry.wardId,
            wardName: entry.wardName,
            wardType: entry.wardType,
            roomId: entry.roomId,
            roomNumber: entry.roomNumber,
            roomName: entry.roomName,
            roomType: entry.roomType,
            bedId: entry.bedId,
            bedNumber: entry.bedNumber,
            bedLabel: entry.bedLabel,
            bedType: entry.bedType,
            bedStatus: entry.bedStatus,
          ),
        )
        .toList();

    result.sort((a, b) {
      final buildingCompare =
          a.buildingName.toLowerCase().compareTo(b.buildingName.toLowerCase());

      if (buildingCompare != 0) {
        return buildingCompare;
      }

      final floorCompare =
          a.floorName.toLowerCase().compareTo(b.floorName.toLowerCase());

      if (floorCompare != 0) {
        return floorCompare;
      }

      final wardCompare =
          a.wardName.toLowerCase().compareTo(b.wardName.toLowerCase());

      if (wardCompare != 0) {
        return wardCompare;
      }

      final roomCompare =
          a.roomNumber.toLowerCase().compareTo(b.roomNumber.toLowerCase());

      if (roomCompare != 0) {
        return roomCompare;
      }

      return a.bedNumber.toLowerCase().compareTo(b.bedNumber.toLowerCase());
    });

    return result;
  }

  // ---------------------------------------------------------------------------
  // CREATE ADMISSION
  // ---------------------------------------------------------------------------

  Future<String> createAdmission({
    required String hospitalId,
    required String patientId,
    String admissionType = 'elective',
    String status = 'admitted',
    String? admissionReason,
    String? admittingDiagnosis,
    String? admittingDoctorProfileId,
    DateTime? expectedDischargeAt,
    String visitorStatus = 'approved_visitors_only',
    String sourceType = 'direct',
  }) async {
    const validAdmissionTypes = {
      'elective',
      'emergency',
      'day_case',
      'transfer',
      'maternity',
      'paediatric',
      'mental_health',
      'observation',
    };

    const validStatuses = {
      'planned',
      'admitted',
    };

    const validSourceTypes = {
      'direct',
      'emergency',
      'referral',
      'interhospital_transfer',
    };

    const validVisitorStatuses = {
      'visitors_allowed',
      'family_only',
      'approved_visitors_only',
      'primary_contact_only',
      'ward_approval_required',
      'icu_approval_required',
      'temporarily_restricted',
      'infection_isolation',
      'no_visitors',
      'security_restricted',
      'end_of_life_exception',
    };

    if (!validAdmissionTypes.contains(admissionType)) {
      throw Exception('Invalid admission type.');
    }

    if (!validStatuses.contains(status)) {
      throw Exception(
        'A new admission must be planned or admitted.',
      );
    }

    if (!validSourceTypes.contains(sourceType)) {
      throw Exception('Invalid admission source.');
    }

    if (!validVisitorStatuses.contains(visitorStatus)) {
      throw Exception('Invalid visitor status.');
    }

    final result = await _supabase.rpc(
      'corvia_mh_create_admission',
      params: {
        'p_hospital_id': hospitalId,
        'p_patient_id': patientId,
        'p_admission_type': admissionType,
        'p_status': status,
        'p_admission_reason': _nullableText(admissionReason),
        'p_admitting_diagnosis': _nullableText(admittingDiagnosis),
        'p_admitting_doctor_profile_id':
            _nullableText(admittingDoctorProfileId),
        'p_expected_discharge_at':
            expectedDischargeAt?.toUtc().toIso8601String(),
        'p_visitor_status': visitorStatus,
        'p_source_type': sourceType,
      },
    );

    final admissionId = _extractScalarString(result);

    if (admissionId == null || admissionId.trim().isEmpty) {
      throw Exception(
        'Admission was created without a valid ID.',
      );
    }

    return admissionId;
  }

  // ---------------------------------------------------------------------------
  // ADMIT PLANNED ADMISSION
  // ---------------------------------------------------------------------------

  Future<void> admitPlannedAdmission(
    String admissionId,
  ) async {
    final result = await _supabase.rpc(
      'corvia_mh_admit_planned_admission',
      params: {
        'p_admission_id': admissionId,
      },
    );

    if (!_extractScalarBool(result)) {
      throw Exception(
        'The planned admission could not be admitted.',
      );
    }
  }

  // ---------------------------------------------------------------------------
  // ASSIGN BED
  // ---------------------------------------------------------------------------

  Future<String> assignBed({
    required String admissionId,
    required String bedId,
  }) async {
    final result = await _supabase.rpc(
      'corvia_mh_assign_bed',
      params: {
        'p_admission_id': admissionId,
        'p_bed_id': bedId,
      },
    );

    final assignmentId = _extractScalarString(result);

    if (assignmentId == null || assignmentId.trim().isEmpty) {
      throw Exception(
        'The bed was assigned without a valid assignment ID.',
      );
    }

    return assignmentId;
  }

  /// Sets the planned discharge date shown on the admission card. There is
  /// no dedicated RPC, so this relies on the admin's update permission.
  Future<void> setExpectedDischarge({
    required String admissionId,
    required DateTime expectedDischargeAt,
  }) async {
    await _supabase
        .from('hospital_admissions')
        .update({
          'expected_discharge_at':
              expectedDischargeAt.toUtc().toIso8601String(),
        })
        .eq('id', admissionId);
  }

  // ---------------------------------------------------------------------------
  // TRANSFER BED
  // ---------------------------------------------------------------------------

  Future<String> transferBed({
    required String admissionId,
    required String newBedId,
    required String transferReason,
  }) async {
    final reason = transferReason.trim();

    if (reason.isEmpty) {
      throw Exception(
        'A transfer reason is required.',
      );
    }

    final result = await _supabase.rpc(
      'corvia_mh_transfer_bed',
      params: {
        'p_admission_id': admissionId,
        'p_new_bed_id': newBedId,
        'p_transfer_reason': reason,
      },
    );

    final assignmentId = _extractScalarString(result);

    if (assignmentId == null || assignmentId.trim().isEmpty) {
      throw Exception(
        'The transfer completed without a valid assignment ID.',
      );
    }

    return assignmentId;
  }

  // ---------------------------------------------------------------------------
  // DISCHARGE
  // ---------------------------------------------------------------------------

  Future<void> dischargeAdmission({
    required String admissionId,
    required String dischargeReason,
  }) async {
    final reason = dischargeReason.trim();

    if (reason.isEmpty) {
      throw Exception(
        'A discharge reason is required.',
      );
    }

    final result = await _supabase.rpc(
      'corvia_mh_discharge_admission',
      params: {
        'p_admission_id': admissionId,
        'p_discharge_reason': reason,
      },
    );

    if (!_extractScalarBool(result)) {
      throw Exception(
        'The patient could not be discharged.',
      );
    }
  }

  // ---------------------------------------------------------------------------
  // CANCEL PLANNED ADMISSION
  // ---------------------------------------------------------------------------

  Future<void> cancelAdmission({
    required String admissionId,
    required String cancellationReason,
  }) async {
    final reason = cancellationReason.trim();

    if (reason.isEmpty) {
      throw Exception(
        'A cancellation reason is required.',
      );
    }

    final result = await _supabase.rpc(
      'corvia_mh_cancel_admission',
      params: {
        'p_admission_id': admissionId,
        'p_cancellation_reason': reason,
      },
    );

    if (!_extractScalarBool(result)) {
      throw Exception(
        'The planned admission could not be cancelled.',
      );
    }
  }

  // ---------------------------------------------------------------------------
  // WORKSPACE SNAPSHOT
  // ---------------------------------------------------------------------------

  Future<HospitalAdmissionWorkspace> loadWorkspace(
    String hospitalId, {
    Set<String>? admissionStatuses,
  }) async {
    final results = await Future.wait([
      getHospitalPatients(hospitalId),
      getAdmissions(
        hospitalId,
        statuses: admissionStatuses,
      ),
      getAvailableBeds(hospitalId),
    ]);

    return HospitalAdmissionWorkspace(
      hospitalId: hospitalId,
      patients: results[0] as List<HospitalAdmissionPatient>,
      admissions: results[1] as List<HospitalAdmissionRecord>,
      availableBeds: results[2] as List<HospitalAdmissionBedOption>,
    );
  }
}

// =============================================================================
// PATIENT MODEL
// =============================================================================

class HospitalAdmissionPatient {
  const HospitalAdmissionPatient({
    required this.patientId,
    required this.profileId,
    required this.patientHospitalLinkId,
    required this.hospitalId,
    required this.patientName,
    required this.patientNumber,
    required this.localPatientNumber,
    required this.dateOfBirth,
    required this.gender,
    required this.bloodType,
    required this.phone,
    required this.email,
    required this.linkStatus,
    required this.isActive,
    required this.linkedAt,
    required this.lastTreatedAt,
    required this.dischargedAt,
  });

  final String patientId;
  final String? profileId;
  final String? patientHospitalLinkId;
  final String hospitalId;

  final String patientName;
  final String? patientNumber;
  final String? localPatientNumber;

  final DateTime? dateOfBirth;
  final String? gender;
  final String? bloodType;

  final String? phone;
  final String? email;

  final String linkStatus;
  final bool isActive;

  final DateTime? linkedAt;
  final DateTime? lastTreatedAt;
  final DateTime? dischargedAt;

  String get displayPatientNumber {
    final localNumber = localPatientNumber?.trim();

    if (localNumber != null && localNumber.isNotEmpty) {
      return localNumber;
    }

    final globalNumber = patientNumber?.trim();

    if (globalNumber != null && globalNumber.isNotEmpty) {
      return globalNumber;
    }

    return 'No patient number';
  }

  String get searchText {
    return [
      patientName,
      patientNumber,
      localPatientNumber,
      phone,
      email,
      dateOfBirth?.toIso8601String(),
    ].whereType<String>().join(' ').toLowerCase();
  }
}

// =============================================================================
// ADMISSION MODEL
// =============================================================================

class HospitalAdmissionRecord {
  const HospitalAdmissionRecord({
    required this.admissionId,
    required this.hospitalId,
    required this.patientId,
    required this.patientHospitalLinkId,
    required this.patientName,
    required this.patientNumber,
    required this.admissionNumber,
    required this.admissionType,
    required this.status,
    required this.admissionReason,
    required this.admittingDiagnosis,
    required this.admittingDoctorProfileId,
    required this.sourceType,
    required this.sourceTransferId,
    required this.visitorStatus,
    required this.admittedAt,
    required this.expectedDischargeAt,
    required this.dischargedAt,
    required this.dischargeReason,
    required this.createdAt,
    required this.updatedAt,
    required this.assignmentId,
    required this.assignedAt,
    required this.bedId,
    required this.bedNumber,
    required this.bedLabel,
    required this.bedType,
    required this.bedStatus,
    required this.roomId,
    required this.roomNumber,
    required this.roomName,
    required this.roomType,
    required this.wardId,
    required this.wardName,
    required this.wardType,
    required this.floorId,
    required this.floorName,
    required this.buildingId,
    required this.buildingName,
  });

  final String admissionId;
  final String hospitalId;

  final String patientId;
  final String? patientHospitalLinkId;

  final String patientName;
  final String? patientNumber;

  final String? admissionNumber;
  final String admissionType;
  final String status;

  final String? admissionReason;
  final String? admittingDiagnosis;
  final String? admittingDoctorProfileId;

  final String sourceType;
  final String? sourceTransferId;

  final String visitorStatus;

  final DateTime? admittedAt;
  final DateTime? expectedDischargeAt;
  final DateTime? dischargedAt;

  final String? dischargeReason;

  final DateTime? createdAt;
  final DateTime? updatedAt;

  final String? assignmentId;
  final DateTime? assignedAt;

  final String? bedId;
  final String? bedNumber;
  final String? bedLabel;
  final String? bedType;
  final String? bedStatus;

  final String? roomId;
  final String? roomNumber;
  final String? roomName;
  final String? roomType;

  final String? wardId;
  final String? wardName;
  final String? wardType;

  final String? floorId;
  final String? floorName;

  final String? buildingId;
  final String? buildingName;

  bool get isPlanned {
    return status == 'planned';
  }

  bool get isAdmitted {
    return status == 'admitted';
  }

  bool get isDischarged {
    return status == 'discharged';
  }

  bool get hasBedAssignment {
    return assignmentId != null && bedId != null;
  }

  String get displayAdmissionNumber {
    final value = admissionNumber?.trim();

    if (value != null && value.isNotEmpty) {
      return value;
    }

    return admissionId.length >= 8
        ? 'ADM-${admissionId.substring(0, 8).toUpperCase()}'
        : admissionId;
  }

  String get displayBed {
    final label = bedLabel?.trim();

    if (label != null && label.isNotEmpty) {
      return label;
    }

    final number = bedNumber?.trim();

    if (number != null && number.isNotEmpty) {
      return 'Bed $number';
    }

    return 'No bed assigned';
  }

  String get displayRoom {
    final name = roomName?.trim();
    final number = roomNumber?.trim();

    if (name != null &&
        name.isNotEmpty &&
        number != null &&
        number.isNotEmpty) {
      return '$name • Room $number';
    }

    if (number != null && number.isNotEmpty) {
      return 'Room $number';
    }

    return 'No room assigned';
  }

  String get displayLocation {
    final parts = <String>[
      if (buildingName != null && buildingName!.trim().isNotEmpty)
        buildingName!,
      if (floorName != null && floorName!.trim().isNotEmpty) floorName!,
      if (wardName != null && wardName!.trim().isNotEmpty) wardName!,
      if (roomNumber != null && roomNumber!.trim().isNotEmpty) displayRoom,
      if (bedId != null) displayBed,
    ];

    if (parts.isEmpty) {
      return 'No bed assigned';
    }

    return parts.join(' • ');
  }

  String get searchText {
    return [
      admissionNumber,
      patientName,
      patientNumber,
      admissionType,
      status,
      admissionReason,
      admittingDiagnosis,
      buildingName,
      floorName,
      wardName,
      roomName,
      roomNumber,
      bedLabel,
      bedNumber,
    ].whereType<String>().join(' ').toLowerCase();
  }
}

// =============================================================================
// BED OPTION MODEL
// =============================================================================

class HospitalAdmissionBedOption {
  const HospitalAdmissionBedOption({
    required this.hospitalId,
    required this.buildingId,
    required this.buildingName,
    required this.floorId,
    required this.floorName,
    required this.wardId,
    required this.wardName,
    required this.wardType,
    required this.roomId,
    required this.roomNumber,
    required this.roomName,
    required this.roomType,
    required this.bedId,
    required this.bedNumber,
    required this.bedLabel,
    required this.bedType,
    required this.bedStatus,
  });

  final String hospitalId;

  final String? buildingId;
  final String buildingName;

  final String? floorId;
  final String floorName;

  final String? wardId;
  final String wardName;
  final String wardType;

  final String? roomId;
  final String roomNumber;
  final String? roomName;
  final String roomType;

  final String bedId;
  final String bedNumber;
  final String? bedLabel;
  final String bedType;
  final String bedStatus;

  String get displayBed {
    final label = bedLabel?.trim();

    if (label != null && label.isNotEmpty) {
      return label;
    }

    return 'Bed $bedNumber';
  }

  String get displayRoom {
    final name = roomName?.trim();

    if (name != null && name.isNotEmpty) {
      return '$name • Room $roomNumber';
    }

    return 'Room $roomNumber';
  }

  String get displayLocation {
    return '$buildingName • $floorName • $wardName • '
        '$displayRoom • $displayBed';
  }

  String get searchText {
    return [
      buildingName,
      floorName,
      wardName,
      wardType,
      roomName,
      roomNumber,
      roomType,
      bedLabel,
      bedNumber,
      bedType,
      bedStatus,
    ].whereType<String>().join(' ').toLowerCase();
  }
}

// =============================================================================
// WORKSPACE MODEL
// =============================================================================

class HospitalAdmissionWorkspace {
  const HospitalAdmissionWorkspace({
    required this.hospitalId,
    required this.patients,
    required this.admissions,
    required this.availableBeds,
  });

  final String hospitalId;

  final List<HospitalAdmissionPatient> patients;
  final List<HospitalAdmissionRecord> admissions;
  final List<HospitalAdmissionBedOption> availableBeds;

  int get plannedAdmissions {
    return admissions.where((item) => item.isPlanned).length;
  }

  int get activeAdmissions {
    return admissions.where((item) => item.isAdmitted).length;
  }

  int get admittedWithoutBed {
    return admissions
        .where(
          (item) => item.isAdmitted && !item.hasBedAssignment,
        )
        .length;
  }

  int get dischargedAdmissions {
    return admissions.where((item) => item.isDischarged).length;
  }
}
