import 'package:supabase_flutter/supabase_flutter.dart';

class NurseContext {
  const NurseContext({
    required this.signedIn,
    required this.profileFound,
    required this.isNurse,
    required this.isActive,
    required this.hospitalFound,
    required this.profileId,
    required this.nurseUserId,
    required this.hospitalId,
    required this.hospitalName,
    required this.nurseName,
    required this.email,
    required this.role,
  });

  final bool signedIn;
  final bool profileFound;
  final bool isNurse;
  final bool isActive;
  final bool hospitalFound;

  final String profileId;
  final String nurseUserId;

  final String hospitalId;
  final String hospitalName;

  final String nurseName;
  final String email;
  final String role;

  factory NurseContext.fromJson(
    Map<String, dynamic> json,
  ) {
    return NurseContext(
      signedIn: _boolValue(
        json['signed_in'],
      ),
      profileFound: _boolValue(
        json['profile_found'],
      ),
      isNurse: _boolValue(
        json['is_nurse'],
      ),
      isActive: _boolValue(
        json['is_active'],
      ),
      hospitalFound: _boolValue(
        json['hospital_found'],
      ),
      profileId: _text(
        json['profile_id'],
      ),
      nurseUserId: _text(
        json['nurse_user_id'],
      ),
      hospitalId: _text(
        json['hospital_id'],
      ),
      hospitalName: _text(
        json['hospital_name'],
        fallback: 'Corvia Medical Hospital',
      ),
      nurseName: _text(
        json['nurse_name'],
        fallback: 'Nurse',
      ),
      email: _text(
        json['email'],
      ),
      role: _normalise(
        json['role'],
      ),
    );
  }
}

/// Demographics already resolved by the nurse-scoped database read model.
class NursePatient {
  NursePatient.fromJson(Map<String, dynamic> json)
      : id = _text(json['id']),
        patientNumber = _text(json['patient_number']),
        firstName = _text(json['first_name']),
        surname = _text(json['surname']),
        phone = _text(json['phone']),
        email = _text(json['email']),
        idNumber = _text(json['id_number']),
        dateOfBirth = DateTime.tryParse(_text(json['date_of_birth'])),
        gender = _text(json['gender']),
        medicalAidProvider = _text(json['medical_aid_provider']),
        medicalAidMemberNumber = _text(json['medical_aid_member_number']),
        medicalAidPlan = _text(json['medical_aid_plan']);

  final String id;
  final String patientNumber;
  final String firstName;
  final String surname;
  final String phone;
  final String email;
  final String idNumber;
  final DateTime? dateOfBirth;
  final String gender;
  final String medicalAidProvider;
  final String medicalAidMemberNumber;
  final String medicalAidPlan;

  String get displayName {
    final name = '$firstName $surname'.trim();
    if (name.isNotEmpty) return name;
    final reference = patientNumber.isNotEmpty
        ? patientNumber
        : id.substring(0, id.length > 8 ? 8 : id.length);
    return reference.isEmpty ? 'Patient record' : 'Patient $reference';
  }

  String get dropdownLabel =>
      patientNumber.isEmpty || firstName.isEmpty && surname.isEmpty
          ? displayName
          : '$displayName · $patientNumber';
}

class NurseWard {
  NurseWard.fromJson(Map<String, dynamic> json)
      : id = _text(json['id']),
        name = _text(json['name']),
        code = _text(json['code']),
        floorName = _text(json['floor_name']),
        buildingName = _text(json['building_name']);

  final String id;
  final String name;
  final String code;
  final String floorName;
  final String buildingName;

  // Existing shift logs store a text ward. Keep that contract and distinguish
  // identically named wards in different parts of the hospital.
  String get label => [name, if (code.isNotEmpty) code, floorName, buildingName]
      .where((part) => part.isNotEmpty)
      .join(' · ');
}

class NurseWorkspace {
  NurseWorkspace.fromJson(Map<String, dynamic> json)
      : context = NurseContext.fromJson(_workspaceMap(json['context'])),
        assignments = _workspaceRows(json['assignments']),
        tasks = _workspaceRows(json['tasks']),
        patientsById = {
          for (final row in _workspaceRows(json['patients']))
            _text(row['id']): NursePatient.fromJson(row),
        },
        wards = _workspaceRows(json['wards']).map(NurseWard.fromJson).toList() {
    if (patientsById.containsKey('') ||
        assignments.any((row) =>
            _text(row['hospital_id']) != context.hospitalId ||
            _text(row['nurse_user_id']) != context.nurseUserId ||
            !patientsById.containsKey(_text(row['patient_id']))) ||
        wards.any((ward) => ward.id.isEmpty || ward.name.isEmpty)) {
      throw const FormatException(
          'The nurse workspace returned incomplete data.');
    }
  }

  final NurseContext context;
  final List<Map<String, dynamic>> assignments;
  final List<Map<String, dynamic>> tasks;
  final Map<String, NursePatient> patientsById;
  final List<NurseWard> wards;

  List<String> get assignedPatientIds =>
      assignments.map((row) => _text(row['patient_id'])).toSet().toList();

  List<NursePatient> get assignedPatients =>
      assignedPatientIds.map((id) => patientsById[id]!).toList();

  NursePatient patient(String? id) =>
      patientsById[id] ?? NursePatient.fromJson({'id': id ?? ''});
}

Map<String, dynamic> _workspaceMap(dynamic value) {
  if (value is! Map) {
    throw const FormatException('The nurse workspace returned invalid data.');
  }
  return Map<String, dynamic>.from(value);
}

List<Map<String, dynamic>> _workspaceRows(dynamic value) {
  if (value is! List) {
    throw const FormatException('The nurse workspace returned invalid data.');
  }
  return value.map(_workspaceMap).toList();
}

class NurseWorkspaceCounts {
  const NurseWorkspaceCounts({
    required this.assignedPatients,
    required this.activeTasks,
    required this.activeMedications,
  });

  final int assignedPatients;
  final int activeTasks;

  /// Null means the count could not be retrieved; zero is a successful empty count.
  final int? activeMedications;
}

class NurseLabCollectionOrder {
  const NurseLabCollectionOrder({
    required this.labResultId,
    required this.patientId,
    required this.patientName,
    required this.patientNumber,
    required this.testName,
    required this.status,
    required this.createdAt,
    required this.labOrganizationId,
    required this.labName,
    required this.labType,
  });

  final String labResultId;
  final String patientId;
  final String patientName;
  final String patientNumber;
  final String testName;
  final String status;
  final DateTime? createdAt;
  final String labOrganizationId;
  final String labName;
  final String labType;

  bool get isOutsourced => labType == 'private';

  factory NurseLabCollectionOrder.fromJson(Map<String, dynamic> json) {
    return NurseLabCollectionOrder(
      labResultId: _text(json['lab_result_id']),
      patientId: _text(json['patient_id']),
      patientName: _text(json['patient_name'], fallback: 'Patient record'),
      patientNumber: _text(json['patient_number']),
      testName: _text(json['test_name'], fallback: 'Laboratory test'),
      status: _normalise(json['status']),
      createdAt: DateTime.tryParse(_text(json['created_at'])),
      labOrganizationId: _text(json['lab_organization_id']),
      labName: _text(json['lab_name'], fallback: 'Receiving laboratory'),
      labType: _normalise(json['lab_type']),
    );
  }
}

class NurseSampleInput {
  const NurseSampleInput({
    required this.specimenType,
    this.externalLabelReference = '',
  });

  final String specimenType;
  final String externalLabelReference;

  Map<String, dynamic> toJson() => {
        'specimen_type': specimenType.trim(),
        'external_label_reference': externalLabelReference.trim().isEmpty
            ? null
            : externalLabelReference.trim(),
      };
}

class NurseCollectedSpecimen {
  const NurseCollectedSpecimen({
    required this.containerId,
    required this.containerCode,
    required this.specimenType,
    required this.labelSource,
    required this.externalLabelReference,
  });

  final String containerId;
  final String containerCode;
  final String specimenType;
  final String labelSource;
  final String externalLabelReference;

  bool get usesCorviaLabel => labelSource == 'corvia';

  factory NurseCollectedSpecimen.fromJson(Map<String, dynamic> json) {
    return NurseCollectedSpecimen(
      containerId: _text(json['container_id']),
      containerCode: _text(json['container_code']),
      specimenType: _text(json['specimen_type']),
      labelSource: _normalise(json['label_source']),
      externalLabelReference: _text(json['external_label_reference']),
    );
  }
}

class NurseSpecimenBag {
  const NurseSpecimenBag({
    required this.bagId,
    required this.bagCode,
    required this.labelSource,
    required this.externalLabelReference,
  });

  final String bagId;
  final String bagCode;
  final String labelSource;
  final String externalLabelReference;

  bool get usesCorviaLabel => labelSource == 'corvia';

  factory NurseSpecimenBag.fromJson(Map<String, dynamic> json) {
    return NurseSpecimenBag(
      bagId: _text(json['bag_id']),
      bagCode: _text(json['bag_code']),
      labelSource: _normalise(json['label_source']),
      externalLabelReference: _text(json['external_label_reference']),
    );
  }
}

class NurseSpecimenCollection {
  const NurseSpecimenCollection({
    required this.collectionId,
    required this.labOrganizationId,
    required this.labName,
    required this.labType,
    required this.labelSource,
    required this.specimens,
    required this.bag,
  });

  final String collectionId;
  final String labOrganizationId;
  final String labName;
  final String labType;
  final String labelSource;
  final List<NurseCollectedSpecimen> specimens;
  final NurseSpecimenBag? bag;

  bool get isOutsourced => labType == 'private';

  factory NurseSpecimenCollection.fromJson(Map<String, dynamic> json) {
    final specimenRows = json['specimens'];
    final bagRow = json['bag'];
    return NurseSpecimenCollection(
      collectionId: _text(json['collection_id']),
      labOrganizationId: _text(json['lab_organization_id']),
      labName: _text(json['lab_name'], fallback: 'Receiving laboratory'),
      labType: _normalise(json['lab_type']),
      labelSource: _normalise(json['label_source']),
      specimens: specimenRows is List
          ? specimenRows
              .whereType<Map>()
              .map(
                (row) => NurseCollectedSpecimen.fromJson(
                  Map<String, dynamic>.from(row),
                ),
              )
              .toList()
          : const [],
      bag: bagRow is Map
          ? NurseSpecimenBag.fromJson(Map<String, dynamic>.from(bagRow))
          : null,
    );
  }
}

class NurseService {
  NurseService({
    SupabaseClient? client,
  }) : _supabase = client ?? Supabase.instance.client;

  final SupabaseClient _supabase;

  // ==========================================================================
  // CURRENT NURSE
  // ==========================================================================

  Future<NurseContext> currentContext() async {
    final response = await _supabase.rpc(
      'corvia_current_nurse_context',
    );

    final map = _mapResponse(
      response,
      label: 'Nurse context',
    );

    return NurseContext.fromJson(
      map,
    );
  }

  Future<NurseContext> requireCurrentContext() async {
    final context = await currentContext();
    _requireContext(context);
    return context;
  }

  Future<NurseWorkspace> loadWorkspace() async {
    try {
      final response = await _supabase.rpc('corvia_nurse_workspace_v1');
      final workspace = NurseWorkspace.fromJson(
        _mapResponse(response, label: 'Nurse workspace'),
      );
      _requireContext(workspace.context);
      if (workspace.context.nurseUserId != _supabase.auth.currentUser?.id) {
        throw Exception('Your nurse session changed. Please reload this page.');
      }
      return workspace;
    } on PostgrestException catch (error) {
      if (error.code == 'PGRST202' || error.code == '42883') {
        throw Exception(
            'The nurse workspace database update has not been installed. '
            'Please contact the hospital administrator.');
      }
      rethrow;
    }
  }

  void _requireContext(NurseContext context) {
    if (!context.signedIn) {
      throw Exception(
        'Your Corvia session has expired.',
      );
    }

    if (!context.profileFound) {
      throw Exception(
        'No Corvia profile was found for this nurse account.',
      );
    }

    if (!context.isActive) {
      throw Exception(
        'This nurse account is inactive. '
        'Contact the hospital administrator.',
      );
    }

    if (!context.isNurse) {
      throw Exception(
        'This account is not registered as a nurse.',
      );
    }

    if (!context.hospitalFound || context.hospitalId.trim().isEmpty) {
      throw Exception(
        'This nurse account is not linked to an active hospital. '
        'A hospital administrator must link the nurse first.',
      );
    }

    if (context.nurseUserId.trim().isEmpty) {
      throw Exception(
        'The nurse account has no authenticated user link.',
      );
    }
  }

  // ==========================================================================
  // SHIFTS
  // ==========================================================================

  Future<Map<String, dynamic>?> loadActiveShift(
    NurseContext context,
  ) async {
    final response = await _supabase
        .from('nurse_shift_logs')
        .select()
        .eq(
          'nurse_user_id',
          context.nurseUserId,
        )
        .eq(
          'hospital_id',
          context.hospitalId,
        )
        .or(
          'status.eq.active,status.eq.on_break',
        )
        .order(
          'clock_in_at',
          ascending: false,
        )
        .limit(1);

    final rows = _rows(
      response,
    );

    if (rows.isEmpty) {
      return null;
    }

    return rows.first;
  }

  Future<List<Map<String, dynamic>>> loadShiftHistory(
    NurseContext context, {
    int limit = 15,
  }) async {
    final response = await _supabase
        .from('nurse_shift_logs')
        .select()
        .eq(
          'nurse_user_id',
          context.nurseUserId,
        )
        .eq(
          'hospital_id',
          context.hospitalId,
        )
        .order(
          'clock_in_at',
          ascending: false,
        )
        .limit(limit);

    return _rows(
      response,
    );
  }

  Future<void> clockIn({
    required NurseContext context,
    required String wardId,
    required String shiftType,
    required String note,
  }) async {
    final workspace = await loadWorkspace();
    if (workspace.context.hospitalId != context.hospitalId ||
        workspace.context.nurseUserId != context.nurseUserId) {
      throw Exception(
          'Your hospital context changed. Please reload your shift.');
    }
    final availableWards = workspace.wards.where((ward) => ward.id == wardId);
    if (availableWards.isEmpty) {
      throw Exception('Select an active ward from your hospital.');
    }
    final ward = availableWards.first;
    final existing = await loadActiveShift(
      context,
    );

    if (existing != null) {
      throw Exception(
        'You already have an active shift.',
      );
    }

    final now = DateTime.now().toUtc().toIso8601String();

    await _supabase.from('nurse_shift_logs').insert({
      'hospital_id': context.hospitalId,
      'nurse_user_id': context.nurseUserId,
      'nurse_profile_id': context.profileId,
      'nurse_name': context.nurseName,
      'ward': ward.label,
      'shift_type': shiftType.trim(),
      'status': 'active',
      'clock_in_at': now,
      'clock_in_note': note.trim(),
      'total_break_minutes': 0,
      'created_at': now,
      'updated_at': now,
    });
  }

  Future<void> startBreak({
    required NurseContext context,
    required Map<String, dynamic> shift,
  }) async {
    _validateShiftOwnership(
      context,
      shift,
    );

    final shiftId = _requiredId(
      shift['id'],
      'Shift',
    );

    final status = _normalise(
      shift['status'],
    );

    if (status != 'active') {
      throw Exception(
        'A break can only start from an active shift.',
      );
    }

    final now = DateTime.now().toUtc().toIso8601String();

    await _supabase
        .from('nurse_shift_logs')
        .update({
          'status': 'on_break',
          'break_started_at': now,
          'updated_at': now,
        })
        .eq(
          'id',
          shiftId,
        )
        .eq(
          'hospital_id',
          context.hospitalId,
        )
        .eq(
          'nurse_user_id',
          context.nurseUserId,
        );
  }

  Future<void> endBreak({
    required NurseContext context,
    required Map<String, dynamic> shift,
  }) async {
    _validateShiftOwnership(
      context,
      shift,
    );

    final shiftId = _requiredId(
      shift['id'],
      'Shift',
    );

    final breakStart = DateTime.tryParse(
      shift['break_started_at']?.toString() ?? '',
    );

    if (breakStart == null) {
      throw Exception(
        'No active break was found.',
      );
    }

    final currentBreakMinutes = _intValue(
      shift['total_break_minutes'],
    );

    final additionalMinutes = DateTime.now()
        .toUtc()
        .difference(
          breakStart.toUtc(),
        )
        .inMinutes;

    final now = DateTime.now().toUtc().toIso8601String();

    await _supabase
        .from('nurse_shift_logs')
        .update({
          'status': 'active',
          'break_started_at': null,
          'total_break_minutes': currentBreakMinutes +
              (additionalMinutes < 0 ? 0 : additionalMinutes),
          'updated_at': now,
        })
        .eq(
          'id',
          shiftId,
        )
        .eq(
          'hospital_id',
          context.hospitalId,
        )
        .eq(
          'nurse_user_id',
          context.nurseUserId,
        );
  }

  Future<void> saveHandover({
    required NurseContext context,
    required Map<String, dynamic> shift,
    required String note,
  }) async {
    _validateShiftOwnership(
      context,
      shift,
    );

    final shiftId = _requiredId(
      shift['id'],
      'Shift',
    );

    await _supabase
        .from('nurse_shift_logs')
        .update({
          'handover_note': note.trim(),
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq(
          'id',
          shiftId,
        )
        .eq(
          'hospital_id',
          context.hospitalId,
        )
        .eq(
          'nurse_user_id',
          context.nurseUserId,
        );
  }

  Future<void> clockOut({
    required NurseContext context,
    required Map<String, dynamic> shift,
    required String handoverNote,
  }) async {
    _validateShiftOwnership(
      context,
      shift,
    );

    final shiftId = _requiredId(
      shift['id'],
      'Shift',
    );

    var totalBreakMinutes = _intValue(
      shift['total_break_minutes'],
    );

    if (_normalise(
          shift['status'],
        ) ==
        'on_break') {
      final breakStarted = DateTime.tryParse(
        shift['break_started_at']?.toString() ?? '',
      );

      if (breakStarted != null) {
        final extra = DateTime.now()
            .toUtc()
            .difference(
              breakStarted.toUtc(),
            )
            .inMinutes;

        if (extra > 0) {
          totalBreakMinutes += extra;
        }
      }
    }

    final now = DateTime.now().toUtc().toIso8601String();

    await _supabase
        .from('nurse_shift_logs')
        .update({
          'status': 'completed',
          'clock_out_at': now,
          'break_started_at': null,
          'total_break_minutes': totalBreakMinutes,
          'handover_note': handoverNote.trim(),
          'updated_at': now,
        })
        .eq(
          'id',
          shiftId,
        )
        .eq(
          'hospital_id',
          context.hospitalId,
        )
        .eq(
          'nurse_user_id',
          context.nurseUserId,
        );
  }

  // ==========================================================================
  // DASHBOARD COUNTS
  // ==========================================================================

  Future<NurseWorkspaceCounts> loadWorkspaceCounts(
    NurseWorkspace workspace,
  ) async {
    final assignments = workspace.assignments;
    final taskCount = workspace.tasks
        .where((task) =>
            {'pending', 'in_progress'}.contains(_normalise(task['status'])))
        .length;
    int? medicationCount;
    try {
      medicationCount = await loadActivePrescriptionCount(workspace);
    } catch (_) {
      // Preserve the other metrics while explicitly marking this count unavailable.
      medicationCount = null;
    }

    return NurseWorkspaceCounts(
      assignedPatients: assignments.length,
      activeTasks: taskCount,
      activeMedications: medicationCount,
    );
  }

  Future<int> loadActivePrescriptionCount(NurseWorkspace workspace) async {
    if (workspace.assignedPatientIds.isEmpty) return 0;
    final response = await _supabase.rpc(
      'corvia_nurse_active_prescription_count_v1',
    );
    final result = _mapResponse(response, label: 'Active prescription count');
    final count = int.tryParse(_text(result['active_prescriptions']));
    if (_text(result['hospital_id']) != workspace.context.hospitalId ||
        _text(result['nurse_user_id']) != workspace.context.nurseUserId ||
        count == null ||
        count < 0) {
      throw const FormatException(
          'The active prescription count returned invalid data.');
    }
    return count;
  }

  // ========================================================================
  // LAB SPECIMEN COLLECTION
  // ========================================================================

  Future<List<NurseLabCollectionOrder>> loadLabCollectionQueue() async {
    final response = await _supabase.rpc(
      'corvia_nurse_lab_collection_queue_v3',
    );

    return _rows(response)
        .map(NurseLabCollectionOrder.fromJson)
        .where(
          (order) => order.labResultId.isNotEmpty && order.patientId.isNotEmpty,
        )
        .toList();
  }

  Future<NurseSpecimenCollection> collectLabSpecimens({
    required String labResultId,
    required List<NurseSampleInput> samples,
    required bool useTransportBag,
    required String externalBagReference,
    required String collectionNote,
  }) async {
    if (labResultId.trim().isEmpty) {
      throw Exception('The laboratory order ID is missing.');
    }

    if (samples.isEmpty || samples.length > 10) {
      throw Exception('Add between 1 and 10 specimen samples.');
    }

    if (samples.any((sample) => sample.specimenType.trim().isEmpty)) {
      throw Exception('Select a specimen type for every sample.');
    }

    final response = await _supabase.rpc(
      'corvia_nurse_collect_lab_specimens',
      params: {
        'p_lab_result_id': labResultId.trim(),
        'p_samples': samples.map((sample) => sample.toJson()).toList(),
        'p_use_transport_bag': useTransportBag,
        'p_external_bag_reference': externalBagReference.trim().isEmpty
            ? null
            : externalBagReference.trim(),
        'p_collection_note':
            collectionNote.trim().isEmpty ? null : collectionNote.trim(),
      },
    );

    final collection = NurseSpecimenCollection.fromJson(
      _mapResponse(response, label: 'Specimen collection'),
    );

    if (collection.collectionId.isEmpty ||
        collection.labOrganizationId.isEmpty ||
        collection.specimens.length != samples.length ||
        collection.specimens.any((specimen) => specimen.containerId.isEmpty)) {
      throw Exception('The database did not return the full collection.');
    }

    return collection;
  }

  // ==========================================================================
  // HOSPITAL ADMIN
  // ==========================================================================

  Future<String> adminHospitalId() async {
    final response = await _supabase.rpc(
      'corvia_admin_hospital_id',
    );

    final id = _text(
      response,
    );

    if (id.isEmpty) {
      throw Exception(
        'Hospital admin context could not be resolved.',
      );
    }

    return id;
  }

  Future<List<Map<String, dynamic>>> loadAdminHospitalNurses() async {
    final response = await _supabase.rpc(
      'corvia_admin_hospital_nurses',
    );

    return _rows(
      response,
    );
  }

  Future<List<Map<String, dynamic>>> loadAdminUnlinkedNurses() async {
    final response = await _supabase.rpc(
      'corvia_admin_unlinked_nurses',
    );

    return _rows(
      response,
    );
  }

  Future<void> linkNurseToAdminHospital({
    required String profileId,
  }) async {
    if (profileId.trim().isEmpty) {
      throw Exception(
        'Nurse profile ID is missing.',
      );
    }

    await _supabase.rpc(
      'corvia_admin_link_nurse',
      params: {
        'p_profile_id': profileId.trim(),
      },
    );
  }

  Future<void> assignNurse({
    required String patientId,
    required String nurseProfileId,
    required String ward,
    required String shiftType,
    required String notes,
  }) async {
    await _supabase.rpc(
      'corvia_admin_assign_nurse',
      params: {
        'p_patient_id': patientId.trim(),
        'p_nurse_profile_id': nurseProfileId.trim(),
        'p_ward': ward.trim(),
        'p_shift_type': shiftType.trim(),
        'p_notes': notes.trim(),
      },
    );
  }

  Future<void> endAssignment({
    required String assignmentId,
  }) async {
    await _supabase.rpc(
      'corvia_admin_end_nurse_assignment',
      params: {
        'p_assignment_id': assignmentId.trim(),
      },
    );
  }

  Future<List<Map<String, dynamic>>> loadAdminAssignments(
    String hospitalId,
  ) async {
    final response = await _supabase
        .from('nurse_patient_assignments')
        .select()
        .eq(
          'hospital_id',
          hospitalId,
        )
        .eq(
          'status',
          'active',
        )
        .order(
          'assigned_at',
          ascending: false,
        );

    return _rows(
      response,
    );
  }

  // ==========================================================================
  // VALIDATION
  // ==========================================================================

  void _validateShiftOwnership(
    NurseContext context,
    Map<String, dynamic> shift,
  ) {
    final hospitalId = _text(
      shift['hospital_id'],
    );

    final nurseUserId = _text(
      shift['nurse_user_id'],
    );

    if (hospitalId != context.hospitalId ||
        nurseUserId != context.nurseUserId) {
      throw Exception(
        'This shift does not belong to the current nurse '
        'and hospital.',
      );
    }
  }

  // ==========================================================================
  // RESPONSE HELPERS
  // ==========================================================================

  Map<String, dynamic> _mapResponse(
    dynamic response, {
    required String label,
  }) {
    if (response is Map<String, dynamic>) {
      return response;
    }

    if (response is Map) {
      return Map<String, dynamic>.from(
        response,
      );
    }

    if (response is List && response.isNotEmpty && response.first is Map) {
      return Map<String, dynamic>.from(
        response.first as Map,
      );
    }

    throw Exception(
      '$label returned invalid data.',
    );
  }

  List<Map<String, dynamic>> _rows(
    dynamic response,
  ) {
    if (response is! List) {
      return [];
    }

    return response
        .whereType<Map>()
        .map(
          (row) => Map<String, dynamic>.from(
            row,
          ),
        )
        .toList();
  }

  String _requiredId(
    dynamic value,
    String label,
  ) {
    final id = _text(
      value,
    );

    if (id.isEmpty) {
      throw Exception(
        '$label ID is missing.',
      );
    }

    return id;
  }
}

String _text(
  dynamic value, {
  String fallback = '',
}) {
  final text = value?.toString().trim() ?? '';

  return text.isEmpty ? fallback : text;
}

bool _boolValue(
  dynamic value, {
  bool fallback = false,
}) {
  if (value is bool) {
    return value;
  }

  if (value == null) {
    return fallback;
  }

  final text = value.toString().trim().toLowerCase();

  if ({
    'true',
    '1',
    'yes',
  }.contains(text)) {
    return true;
  }

  if ({
    'false',
    '0',
    'no',
  }.contains(text)) {
    return false;
  }

  return fallback;
}

int _intValue(
  dynamic value, {
  int fallback = 0,
}) {
  if (value is int) {
    return value;
  }

  if (value is num) {
    return value.toInt();
  }

  return int.tryParse(
        value?.toString() ?? '',
      ) ??
      fallback;
}

String _normalise(
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
