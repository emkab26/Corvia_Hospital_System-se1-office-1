import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

class DoctorClinicalContext {
  const DoctorClinicalContext({
    required this.doctorId,
    required this.profileId,
    required this.authUserId,
    required this.doctorName,
    required this.hospitalId,
    required this.departmentId,
  });

  final String doctorId;
  final String profileId;
  final String authUserId;

  final String doctorName;

  final String? hospitalId;
  final String? departmentId;
}

class DoctorClinicalPatient {
  const DoctorClinicalPatient({
    required this.id,
    required this.name,
    required this.profileId,
  });

  final String id;
  final String name;
  final String profileId;
}

class DoctorClinicalCatalog {
  const DoctorClinicalCatalog({
    required this.treatments,
    required this.labTests,
  });

  final List<String> treatments;
  final List<String> labTests;
}

class DoctorClinicalLabOrganization {
  const DoctorClinicalLabOrganization({
    required this.id,
    required this.name,
    required this.labType,
  });

  final String id;
  final String name;
  final String labType;

  factory DoctorClinicalLabOrganization.fromJson(Map<String, dynamic> json) {
    final type = json['lab_type']?.toString().trim().toLowerCase() ?? '';
    return DoctorClinicalLabOrganization(
      id: json['id']?.toString().trim() ?? '',
      name: json['name']?.toString().trim().isEmpty ?? true
          ? 'Laboratory'
          : json['name'].toString().trim(),
      labType: type,
    );
  }

  String get typeLabel =>
      labType == 'private' ? 'Private laboratory' : 'Hospital laboratory';
}

class DoctorClinicalLabResult {
  const DoctorClinicalLabResult({
    required this.id,
    required this.testName,
    required this.result,
    required this.status,
    required this.createdAt,
    required this.fileUrl,
  });

  final String id;
  final String testName;
  final String result;
  final String status;
  final DateTime? createdAt;
  final String? fileUrl;
}

class DoctorClinicalService {
  DoctorClinicalService({
    SupabaseClient? client,
  }) : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  static const List<String> _fallbackTreatments = [
    'Medication',
    'Physical Therapy',
    'Occupational Therapy',
    'Speech Therapy',
    'Surgery',
    'Wound Care',
    'Pain Management',
    'Antibiotic Therapy',
    'Antiviral Therapy',
    'Antifungal Therapy',
    'Intravenous (IV) Therapy',
    'Oxygen Therapy',
    'Inhalation Therapy',
    'Dialysis',
    'Chemotherapy',
    'Radiation Therapy',
    'Immunotherapy',
    'Hormone Therapy',
    'Nutritional Therapy',
    'Counselling / Psychotherapy',
    'Rehabilitation',
    'Palliative Care',
    'Observation / Monitoring',
    'Lifestyle Modification',
  ];

  static const List<String> _fallbackLabTests = [
    'Full Blood Count',
    'Blood Glucose',
    'HbA1c',
    'Lipid Profile',
    'Liver Function Test',
    'Kidney Function Test',
    'Thyroid Function Test',
    'C-Reactive Protein',
    'Coagulation Studies',
    'Blood Culture',
    'Urinalysis',
    'Pregnancy Test',
    'Histology',
    'Cytology',
    'X-Ray',
    'Ultrasound',
    'CT Scan',
    'MRI Scan',
    'ECG',
  ];

  // ==========================================================================
  // CURRENT DOCTOR
  // ==========================================================================

  Future<DoctorClinicalContext> currentContext() async {
    final user = _client.auth.currentUser;

    if (user == null) {
      throw Exception(
        'No active Corvia session was found.',
      );
    }

    final profileResponse = await _client
        .from('profiles')
        .select()
        .eq(
          'user_id',
          user.id,
        )
        .maybeSingle();

    if (profileResponse == null) {
      throw Exception(
        'No Corvia profile was found for this account.',
      );
    }

    final profile = Map<String, dynamic>.from(
      profileResponse,
    );

    if (profile['is_active'] == false) {
      throw Exception(
        'This doctor account is inactive.',
      );
    }

    final profileId = profile['id']?.toString().trim() ?? '';

    Map<String, dynamic>? doctor;

    try {
      final response = await _client
          .from('doctors')
          .select()
          .eq(
            'profile_id',
            user.id,
          )
          .maybeSingle();

      if (response != null) {
        doctor = Map<String, dynamic>.from(
          response,
        );
      }
    } catch (_) {}

    if (doctor == null && profileId.isNotEmpty) {
      try {
        final response = await _client
            .from('doctors')
            .select()
            .eq(
              'profile_id',
              profileId,
            )
            .maybeSingle();

        if (response != null) {
          doctor = Map<String, dynamic>.from(
            response,
          );
        }
      } catch (_) {}
    }

    if (doctor == null) {
      throw Exception(
        'No doctor record is linked to this account.',
      );
    }

    final doctorId = doctor['id']?.toString().trim() ?? '';

    if (doctorId.isEmpty) {
      throw Exception(
        'The doctor record has no valid doctor ID.',
      );
    }

    final doctorName = _doctorName(
      profile,
      user.email,
    );

    final hospitalId = _firstText(
      [
        doctor['hospital_id'],
        profile['hospital_id'],
      ],
    );

    final departmentId = _firstText(
      [
        doctor['department_id'],
      ],
    );

    return DoctorClinicalContext(
      doctorId: doctorId,
      profileId: profileId,
      authUserId: user.id,
      doctorName: doctorName,
      hospitalId: hospitalId.isEmpty ? null : hospitalId,
      departmentId: departmentId.isEmpty ? null : departmentId,
    );
  }

  // ==========================================================================
  // DOCTOR PATIENTS
  // ==========================================================================

  Future<List<DoctorClinicalPatient>> loadDoctorPatients(
    DoctorClinicalContext context,
  ) async {
    final patientIds = <String>{};

    const tableDoctorColumns = <String, String>{
      'appointments': 'doctor_id',
      'prescriptions': 'doctor_id',
      'lab_results': 'doctor_id',
      'doctor_patient_assignments': 'doctor_id',
      'reception_checkins': 'assigned_doctor_id',
    };

    for (final entry in tableDoctorColumns.entries) {
      try {
        final response = await _client
            .from(entry.key)
            .select(
              'patient_id',
            )
            .eq(
              entry.value,
              context.doctorId,
            );

        for (final row in _rows(
          response,
        )) {
          final patientId = row['patient_id']?.toString().trim();

          if (patientId != null && patientId.isNotEmpty) {
            patientIds.add(
              patientId,
            );
          }
        }
      } catch (_) {
        // Optional/legacy relationship table.
      }
    }

    if (patientIds.isEmpty) {
      return [];
    }

    final patientResponse = await _client.from('patients').select().inFilter(
          'id',
          patientIds.toList(),
        );

    final patientRows = _rows(
      patientResponse,
    );

    final profileKeys = <String>{};

    for (final patient in patientRows) {
      final profileId = patient['profile_id']?.toString().trim();

      if (profileId != null && profileId.isNotEmpty) {
        profileKeys.add(
          profileId,
        );
      }
    }

    final profiles = <String, Map<String, dynamic>>{};

    if (profileKeys.isNotEmpty) {
      try {
        final response = await _client.from('profiles').select().inFilter(
              'id',
              profileKeys.toList(),
            );

        for (final profile in _rows(
          response,
        )) {
          final id = profile['id']?.toString().trim();

          if (id != null && id.isNotEmpty) {
            profiles[id] = profile;
          }
        }
      } catch (_) {}

      final missing = profileKeys
          .where(
            (id) => !profiles.containsKey(
              id,
            ),
          )
          .toList();

      if (missing.isNotEmpty) {
        try {
          final response = await _client.from('profiles').select().inFilter(
                'user_id',
                missing,
              );

          for (final profile in _rows(
            response,
          )) {
            final userId = profile['user_id']?.toString().trim();

            if (userId != null && userId.isNotEmpty) {
              profiles[userId] = profile;
            }
          }
        } catch (_) {}
      }
    }

    final patients = <DoctorClinicalPatient>[];

    for (final patient in patientRows) {
      final id = patient['id']?.toString().trim();

      if (id == null || id.isEmpty) {
        continue;
      }

      final patientHospitalId = patient['hospital_id']?.toString().trim();

      if (context.hospitalId != null &&
          patientHospitalId != null &&
          patientHospitalId.isNotEmpty &&
          patientHospitalId != context.hospitalId) {
        continue;
      }

      final profileId = patient['profile_id']?.toString().trim() ?? '';

      final profile = profiles[profileId];

      final directName = _firstText(
        [
          patient['full_name'],
          patient['display_name'],
          patient['name'],
          profile?['full_name'],
          profile?['display_name'],
          profile?['name'],
        ],
      );

      String name = directName;

      if (name.isEmpty) {
        final firstName = _firstText(
          [
            patient['first_name'],
            profile?['first_name'],
          ],
        );

        final surname = _firstText(
          [
            patient['surname'],
            patient['last_name'],
            profile?['surname'],
            profile?['last_name'],
          ],
        );

        name = '$firstName $surname'.trim();
      }

      if (name.isEmpty) {
        name = 'Patient ${_shortId(id)}';
      }

      patients.add(
        DoctorClinicalPatient(
          id: id,
          name: name,
          profileId: profileId,
        ),
      );
    }

    patients.sort(
      (
        first,
        second,
      ) =>
          first.name.toLowerCase().compareTo(
                second.name.toLowerCase(),
              ),
    );

    return patients;
  }

  // ==========================================================================
  // CATALOG
  // ==========================================================================

  Future<DoctorClinicalCatalog> loadCatalog(
    DoctorClinicalContext context,
  ) async {
    final treatments = <String>{};

    final tests = <String>{};

    treatments.addAll(
      _fallbackTreatments,
    );

    tests.addAll(
      _fallbackLabTests,
    );

    // ------------------------------------------------------------------------
    // Existing Corvia Config/List.json
    // ------------------------------------------------------------------------

    try {
      final data = await _downloadConfigJson(
        'List.json',
      );

      final dynamicValues = <String>{};

      _collectStrings(
        data,
        dynamicValues,
      );

      for (final value in dynamicValues) {
        if (_usefulCatalogValue(
          value,
        )) {
          tests.add(
            value.trim(),
          );
        }
      }
    } catch (_) {
      // Keep safe fallback.
    }

    // ------------------------------------------------------------------------
    // Optional future treatment config files
    // ------------------------------------------------------------------------

    const treatmentFiles = [
      'Treatments.json',
      'treatments.json',
      'TreatmentList.json',
      'ClinicalTreatments.json',
    ];

    for (final file in treatmentFiles) {
      try {
        final data = await _downloadConfigJson(
          file,
        );

        final values = <String>{};

        _collectStrings(
          data,
          values,
        );

        for (final value in values) {
          if (_usefulCatalogValue(
            value,
          )) {
            treatments.add(
              value.trim(),
            );
          }
        }

        break;
      } catch (_) {}
    }

    // ------------------------------------------------------------------------
    // Add options already used in the hospital/doctor records.
    // This makes the list data-driven even if no treatment JSON exists yet.
    // ------------------------------------------------------------------------

    try {
      final response = await _client
          .from(
            'medical_records',
          )
          .select(
            'title, description, record_type',
          )
          .eq(
            'doctor_id',
            context.doctorId,
          )
          .limit(
            500,
          );

      for (final row in _rows(
        response,
      )) {
        final description = row['description']?.toString() ?? '';

        for (final line in description.split(
          '\n',
        )) {
          final trimmed = line.trim();

          if (trimmed.toLowerCase().startsWith(
                'treatment:',
              )) {
            final treatment = trimmed
                .substring(
                  'treatment:'.length,
                )
                .trim();

            if (_usefulCatalogValue(
              treatment,
            )) {
              treatments.add(
                treatment,
              );
            }
          }
        }

        final type = _normalise(
          row['record_type'],
        );

        if (type == 'treatment_plan' || type == 'treatment') {
          final title = row['title']?.toString().trim() ?? '';

          final cleaned = title
              .replaceFirst(
                RegExp(
                  r'^Treatment:\s*',
                  caseSensitive: false,
                ),
                '',
              )
              .trim();

          if (_usefulCatalogValue(
            cleaned,
          )) {
            treatments.add(
              cleaned,
            );
          }
        }
      }
    } catch (_) {}

    try {
      final response = await _client
          .from(
            'lab_results',
          )
          .select(
            'test_name',
          )
          .eq(
            'doctor_id',
            context.doctorId,
          )
          .limit(
            500,
          );

      for (final row in _rows(
        response,
      )) {
        final test = row['test_name']?.toString().trim() ?? '';

        if (_usefulCatalogValue(
          test,
        )) {
          tests.add(
            test,
          );
        }
      }
    } catch (_) {}

    final treatmentList = treatments.toList()
      ..sort(
        _compareText,
      );

    final testList = tests.toList()
      ..sort(
        _compareText,
      );

    return DoctorClinicalCatalog(
      treatments: treatmentList,
      labTests: testList,
    );
  }

  Future<dynamic> _downloadConfigJson(
    String path,
  ) async {
    final bytes = await _client.storage
        .from(
          'Config',
        )
        .download(
          path,
        );

    return jsonDecode(
      utf8.decode(
        bytes,
      ),
    );
  }

  void _collectStrings(
    dynamic value,
    Set<String> output,
  ) {
    if (value is String) {
      final text = value.trim();

      if (text.isNotEmpty) {
        output.add(
          text,
        );
      }

      return;
    }

    if (value is List) {
      for (final item in value) {
        _collectStrings(
          item,
          output,
        );
      }

      return;
    }

    if (value is Map) {
      for (final item in value.values) {
        _collectStrings(
          item,
          output,
        );
      }
    }
  }

  bool _usefulCatalogValue(
    String value,
  ) {
    final text = value.trim();

    if (text.length < 3 || text.length > 120) {
      return false;
    }

    final lower = text.toLowerCase();

    if (lower.startsWith(
          'http://',
        ) ||
        lower.startsWith(
          'https://',
        )) {
      return false;
    }

    if (RegExp(
      r'^\d+$',
    ).hasMatch(text)) {
      return false;
    }

    return true;
  }

  // ==========================================================================
  // MEDICAL RECORDS
  // ==========================================================================

  Future<List<Map<String, dynamic>>> loadMedicalRecords({
    required String patientId,
    required bool newestFirst,
  }) async {
    final response = await _client
        .from(
          'medical_records',
        )
        .select()
        .eq(
          'patient_id',
          patientId,
        )
        .order(
          'record_date',
          ascending: !newestFirst,
        );

    return _rows(
      response,
    );
  }

  Future<String> saveMedicalRecord({
    required DoctorClinicalContext context,
    required String patientId,
    required String recordType,
    required String title,
    required String description,
    DateTime? recordDate,
  }) async {
    final payload = <String, dynamic>{
      'patient_id': patientId,
      'doctor_id': context.doctorId,
      'record_type': recordType,
      'title': title.trim(),
      'description': description.trim(),
      'record_date': (recordDate ?? DateTime.now()).toUtc().toIso8601String(),
      'created_at': DateTime.now().toUtc().toIso8601String(),
    };

    if (context.hospitalId != null && context.hospitalId!.isNotEmpty) {
      payload['hospital_id'] = context.hospitalId;
    }

    final response = await _client
        .from(
          'medical_records',
        )
        .insert(
          payload,
        )
        .select(
          'id',
        )
        .single();

    final id = response['id']?.toString().trim() ?? '';

    if (id.isEmpty) {
      throw Exception(
        'The medical record was saved but no record ID was returned.',
      );
    }

    return id;
  }

  Future<void> updateMedicalRecord({
    required DoctorClinicalContext context,
    required String recordId,
    required String title,
    required String description,
  }) async {
    if (recordId.trim().isEmpty) {
      throw Exception(
        'Medical record ID is missing.',
      );
    }

    await _client
        .from(
          'medical_records',
        )
        .update({
          'title': title.trim(),
          'description': description.trim(),
        })
        .eq(
          'id',
          recordId,
        )
        .eq(
          'doctor_id',
          context.doctorId,
        );
  }

  // ==========================================================================
  // LEGACY RISK INFORMATION
  // ==========================================================================

  Future<List<String>> loadLegacyMedicalConditions(
    String patientId,
  ) async {
    try {
      final patient = await _client
          .from(
            'patients',
          )
          .select(
            'profile_id',
          )
          .eq(
            'id',
            patientId,
          )
          .maybeSingle();

      final profileId = patient?['profile_id']?.toString().trim();

      if (profileId == null || profileId.isEmpty) {
        return [];
      }

      final details = await _client
          .from(
            'medical_details',
          )
          .select(
            'medical_conditions',
          )
          .eq(
            'user_id',
            profileId,
          )
          .maybeSingle();

      return _stringList(
        details?['medical_conditions'],
      );
    } catch (_) {
      return [];
    }
  }

  // ==========================================================================
  // LAB ORDER / RESULT LIFECYCLE
  // ==========================================================================

  Future<List<DoctorClinicalLabResult>> loadPatientCompletedLabResults({
    required String patientId,
  }) async {
    final response = await _client
        .from('lab_results')
        .select(
          'id, test_name, result, file_url, status, created_at',
        )
        .eq('patient_id', patientId)
        .order('created_at', ascending: false)
        .limit(100);

    final results = <DoctorClinicalLabResult>[];

    for (final row in _rows(response)) {
      final id = row['id']?.toString().trim() ?? '';
      final testName = row['test_name']?.toString().trim() ?? '';
      final result = row['result']?.toString().trim() ?? '';
      final status = _normalise(row['status']);

      if (id.isEmpty ||
          testName.isEmpty ||
          result.isEmpty ||
          !{
            'completed',
            'complete',
            'done',
            'resulted',
            'finalised',
            'finalized',
          }.contains(status)) {
        continue;
      }

      final rawFileUrl = row['file_url']?.toString().trim();

      results.add(
        DoctorClinicalLabResult(
          id: id,
          testName: testName,
          result: result,
          status: 'completed',
          createdAt: DateTime.tryParse(
            row['created_at']?.toString() ?? '',
          ),
          fileUrl: rawFileUrl == null || rawFileUrl.isEmpty ? null : rawFileUrl,
        ),
      );
    }

    return results;
  }

  Future<String> createLabOrder({
    required DoctorClinicalContext context,
    required String patientId,
    required String testName,
    required String labOrganizationId,
    bool requiresDoctorReview = true,
  }) async {
    final response = await _client.rpc(
      'corvia_doctor_create_lab_order_v2',
      params: {
        'p_patient_id': patientId.trim(),
        'p_test_name': testName.trim(),
        'p_lab_organization_id': labOrganizationId.trim(),
        'p_requires_doctor_review': requiresDoctorReview,
      },
    );

    if (response is! Map ||
        response['lab_result_id']?.toString().trim().isEmpty != false) {
      throw StateError('The database did not confirm the lab request.');
    }

    return response['lab_result_id'].toString();
  }

  Future<List<DoctorClinicalLabOrganization>>
      loadAvailableLabOrganizations() async {
    final response =
        await _client.rpc('corvia_doctor_available_lab_organizations');
    return _rows(response)
        .map(DoctorClinicalLabOrganization.fromJson)
        .where((organization) => organization.id.isNotEmpty)
        .toList();
  }

  Future<List<Map<String, dynamic>>> loadDoctorLabOrders() async {
    final response = await _client.rpc('corvia_doctor_lab_orders_v2');
    if (response is! List) {
      throw StateError(
          'The laboratory workspace returned an invalid response.');
    }
    return _rows(response);
  }

  Future<void> releaseVerifiedLabResult(String labResultId) async {
    final response = await _client.rpc(
      'corvia_doctor_release_verified_lab_result',
      params: {'p_lab_result_id': labResultId},
    );
    if (response is! Map || response['released'] != true) {
      throw StateError('The database did not confirm patient release.');
    }
  }

  Future<void> startLabOrder({
    required String labResultId,
  }) async {
    final response = await _client.rpc(
      'corvia_doctor_start_lab_result',
      params: {
        'p_lab_result_id': labResultId,
      },
    );

    if (response is! Map || response['status']?.toString() != 'in_progress') {
      throw StateError(
        'The database did not confirm the lab order status change.',
      );
    }
  }

  Future<void> completeLabOrder({
    required String labResultId,
    required String result,
    String? fileUrl,
  }) async {
    await _client.rpc(
      'corvia_doctor_complete_lab_result',
      params: {
        'p_lab_result_id': labResultId,
        'p_result': result.trim(),
        'p_file_url': fileUrl?.trim().isEmpty == true ? null : fileUrl?.trim(),
      },
    );
  }

  Future<void> completeOrCreateLabResult({
    required DoctorClinicalContext context,
    required String patientId,
    required String testName,
    required String result,
  }) async {
    final cleanTest = testName.trim();

    final response = await _client
        .from(
          'lab_results',
        )
        .select()
        .eq(
          'patient_id',
          patientId,
        )
        .eq(
          'doctor_id',
          context.doctorId,
        )
        .eq(
          'test_name',
          cleanTest,
        )
        .order(
          'created_at',
          ascending: false,
        )
        .limit(
          20,
        );

    final rows = _rows(
      response,
    );

    Map<String, dynamic>? existingOrder;

    for (final row in rows) {
      final status = _normalise(
        row['status'],
      );

      if (!{
        'completed',
        'complete',
        'done',
        'finalised',
        'finalized',
      }.contains(
        status,
      )) {
        existingOrder = row;

        break;
      }
    }

    if (existingOrder != null) {
      final id = existingOrder['id']?.toString();

      if (id != null && id.isNotEmpty) {
        await _client
            .from(
          'lab_results',
        )
            .update({
          'result': result.trim(),
          'status': 'completed',
        }).eq(
          'id',
          id,
        );

        return;
      }
    }

    final payload = <String, dynamic>{
      'patient_id': patientId,
      'doctor_id': context.doctorId,
      'test_name': cleanTest,
      'result': result.trim(),
      'status': 'completed',
      'created_at': DateTime.now().toUtc().toIso8601String(),
    };

    if (context.hospitalId != null && context.hospitalId!.isNotEmpty) {
      payload['hospital_id'] = context.hospitalId;
    }

    if (context.departmentId != null && context.departmentId!.isNotEmpty) {
      payload['department_id'] = context.departmentId;
    }

    await _client
        .from(
          'lab_results',
        )
        .insert(
          payload,
        );
  }

  // ==========================================================================
  // HELPERS
  // ==========================================================================

  List<Map<String, dynamic>> _rows(
    dynamic response,
  ) {
    if (response is! List) {
      return [];
    }

    return response
        .whereType<Map>()
        .map(
          (
            row,
          ) =>
              Map<String, dynamic>.from(
            row,
          ),
        )
        .toList();
  }

  List<String> _stringList(
    dynamic value,
  ) {
    if (value == null) {
      return [];
    }

    if (value is List) {
      return value
          .map(
            (
              item,
            ) =>
                item?.toString().trim(),
          )
          .whereType<String>()
          .where(
            (
              item,
            ) =>
                item.isNotEmpty,
          )
          .toSet()
          .toList();
    }

    final text = value.toString().trim();

    if (text.isEmpty) {
      return [];
    }

    return text
        .split(
          RegExp(
            r'[,|;]',
          ),
        )
        .map(
          (
            item,
          ) =>
              item.trim(),
        )
        .where(
          (
            item,
          ) =>
              item.isNotEmpty,
        )
        .toSet()
        .toList();
  }

  String _doctorName(
    Map<String, dynamic> profile,
    String? email,
  ) {
    String value = _firstText(
      [
        profile['full_name'],
        profile['display_name'],
        profile['name'],
      ],
    );

    if (value.isEmpty) {
      final firstName = _firstText(
        [
          profile['first_name'],
        ],
      );

      final surname = _firstText(
        [
          profile['surname'],
          profile['last_name'],
        ],
      );

      value = '$firstName $surname'.trim();
    }

    if (value.isEmpty && email != null) {
      value = email
          .split('@')
          .first
          .replaceAll(
            '.',
            ' ',
          )
          .replaceAll(
            '_',
            ' ',
          );
    }

    if (value.isEmpty) {
      return 'Doctor';
    }

    final lower = value.toLowerCase();

    if (lower.startsWith(
          'dr ',
        ) ||
        lower.startsWith(
          'dr.',
        )) {
      return value;
    }

    return 'Dr. $value';
  }

  String _firstText(
    List<dynamic> values,
  ) {
    for (final value in values) {
      final text = value?.toString().trim();

      if (text != null && text.isNotEmpty) {
        return text;
      }
    }

    return '';
  }

  String _shortId(
    String id,
  ) {
    if (id.length <= 8) {
      return id;
    }

    return id.substring(
      0,
      8,
    );
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

  int _compareText(
    String first,
    String second,
  ) {
    return first.toLowerCase().compareTo(
          second.toLowerCase(),
        );
  }
}
