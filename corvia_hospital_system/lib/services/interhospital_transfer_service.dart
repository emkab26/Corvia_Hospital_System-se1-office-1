import 'dart:convert';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

class InterhospitalTransferService {
  InterhospitalTransferService({
    SupabaseClient? supabase,
  }) : _supabase = supabase ?? Supabase.instance.client;

  final SupabaseClient _supabase;

  static const String defaultDocumentBucket = 'interhospital-transfers';

  // ===========================================================================
  // GENERAL HELPERS
  // ===========================================================================

  List<Map<String, dynamic>> _rows(dynamic value) {
    if (value is! List) {
      return [];
    }

    return value
        .whereType<Map>()
        .map(
          (row) => Map<String, dynamic>.from(row),
        )
        .toList();
  }

  Map<String, dynamic> _map(dynamic value) {
    if (value is Map<String, dynamic>) {
      return value;
    }

    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }

    if (value is List && value.isNotEmpty) {
      return _map(value.first);
    }

    if (value is String && value.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(value);
        return _map(decoded);
      } catch (_) {
        return {};
      }
    }

    return {};
  }

  Map<String, dynamic> _jsonMap(dynamic value) {
    if (value is Map<String, dynamic>) {
      return value;
    }

    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }

    if (value is String && value.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(value);

        if (decoded is Map) {
          return Map<String, dynamic>.from(decoded);
        }
      } catch (_) {
        return {};
      }
    }

    return {};
  }

  DateTime? _date(dynamic value) {
    if (value == null) {
      return null;
    }

    return DateTime.tryParse(
      value.toString(),
    )?.toLocal();
  }

  bool _boolean(dynamic value) {
    if (value is bool) {
      return value;
    }

    if (value is num) {
      return value != 0;
    }

    final text = value?.toString().trim().toLowerCase();

    return text == 'true' || text == '1' || text == 'yes';
  }

  String? _nullableText(String? value) {
    final text = value?.trim();

    if (text == null || text.isEmpty) {
      return null;
    }

    return text;
  }

  List<List<String>> _chunks(
    Iterable<String> values, {
    int size = 100,
  }) {
    final uniqueValues = values
        .map(
          (value) => value.trim(),
        )
        .where(
          (value) => value.isNotEmpty,
        )
        .toSet()
        .toList();

    final output = <List<String>>[];

    for (var index = 0; index < uniqueValues.length; index += size) {
      final end = index + size > uniqueValues.length
          ? uniqueValues.length
          : index + size;

      output.add(
        uniqueValues.sublist(
          index,
          end,
        ),
      );
    }

    return output;
  }

  String _safeFileName(String fileName) {
    final cleaned = fileName
        .trim()
        .replaceAll(
          RegExp(r'[^\w.\-]+'),
          '_',
        )
        .replaceAll(
          RegExp(r'_+'),
          '_',
        );

    if (cleaned.isEmpty) {
      return 'transfer_document';
    }

    return cleaned;
  }

  Future<void> _requireSignedIn() async {
    if (_supabase.auth.currentUser == null) {
      throw Exception(
        'You must be signed in to manage inter-hospital transfers.',
      );
    }
  }

  String _profileName(
    Map<String, dynamic>? profile,
  ) {
    if (profile == null) {
      return 'Unknown patient';
    }

    final fullName = profile['full_name']?.toString().trim();

    if (fullName != null && fullName.isNotEmpty) {
      return fullName;
    }

    final firstName = profile['first_name']?.toString().trim() ?? '';

    final surname = profile['surname']?.toString().trim() ??
        profile['last_name']?.toString().trim() ??
        '';

    final combined = '$firstName $surname'.trim();

    if (combined.isNotEmpty) {
      return combined;
    }

    final email = profile['email']?.toString().trim();

    if (email != null && email.isNotEmpty) {
      return email;
    }

    return 'Unknown patient';
  }

  String _hospitalName(
    Map<String, dynamic>? hospital,
  ) {
    if (hospital == null) {
      return 'Unknown hospital';
    }

    final name = hospital['name']?.toString().trim() ??
        hospital['hospital_name']?.toString().trim();

    if (name != null && name.isNotEmpty) {
      return name;
    }

    return 'Unknown hospital';
  }

  // ===========================================================================
  // ADMIN HOSPITALS
  // ===========================================================================

  Future<List<TransferHospitalOption>> getAdminHospitals() async {
    await _requireSignedIn();

    final userId = _supabase.auth.currentUser!.id;

    List<Map<String, dynamic>> rows = [];

    try {
      final response = await _supabase
          .from('hospital_admins')
          .select(
            'hospital_id, role, hospitals(id, name)',
          )
          .eq(
            'profile_id',
            userId,
          );

      rows = _rows(response);
    } catch (_) {
      final response = await _supabase
          .from('hospital_admins')
          .select(
            'hospital_id, role, hospitals(id, name)',
          )
          .eq(
            'user_id',
            userId,
          );

      rows = _rows(response);
    }

    final hospitals = <TransferHospitalOption>[];

    for (final row in rows) {
      final hospitalId = row['hospital_id']?.toString();

      if (hospitalId == null || hospitalId.trim().isEmpty) {
        continue;
      }

      final hospitalMap = _jsonMap(
        row['hospitals'],
      );

      hospitals.add(
        TransferHospitalOption(
          hospitalId: hospitalId,
          hospitalName: _hospitalName(
            hospitalMap,
          ),
          adminRole: row['role']?.toString() ?? 'hospital_admin',
          isCurrentAdminHospital: true,
        ),
      );
    }

    hospitals.sort(
      (
        first,
        second,
      ) =>
          first.hospitalName.toLowerCase().compareTo(
                second.hospitalName.toLowerCase(),
              ),
    );

    return hospitals;
  }

  Future<List<TransferHospitalOption>> getDestinationHospitals({
    required String sourceHospitalId,
  }) async {
    await _requireSignedIn();

    final response = await _supabase
        .from('hospitals')
        .select(
          'id, name',
        )
        .neq(
          'id',
          sourceHospitalId,
        )
        .order(
          'name',
        );

    return _rows(response)
        .map(
          (row) => TransferHospitalOption(
            hospitalId: row['id']?.toString() ?? '',
            hospitalName: row['name']?.toString() ?? 'Unknown hospital',
            adminRole: null,
            isCurrentAdminHospital: false,
          ),
        )
        .where(
          (hospital) => hospital.hospitalId.isNotEmpty,
        )
        .toList();
  }

  Future<Map<String, TransferHospitalOption>> _getHospitalsByIds(
    Iterable<String> hospitalIds,
  ) async {
    final result = <String, TransferHospitalOption>{};

    for (final chunk in _chunks(hospitalIds)) {
      if (chunk.isEmpty) {
        continue;
      }

      final response = await _supabase
          .from('hospitals')
          .select(
            'id, name',
          )
          .inFilter(
            'id',
            chunk,
          );

      for (final row in _rows(response)) {
        final id = row['id']?.toString();

        if (id == null || id.isEmpty) {
          continue;
        }

        result[id] = TransferHospitalOption(
          hospitalId: id,
          hospitalName: row['name']?.toString() ?? 'Unknown hospital',
          adminRole: null,
          isCurrentAdminHospital: false,
        );
      }
    }

    return result;
  }

  // ===========================================================================
  // PATIENTS
  // ===========================================================================

  Future<List<TransferPatientOption>> getPatientsForHospital(
    String hospitalId,
  ) async {
    if (hospitalId.trim().isEmpty) {
      throw Exception(
        'Hospital ID is required.',
      );
    }

    final patientIds = <String>{};

    try {
      final response = await _supabase
          .from('patients')
          .select(
            'id',
          )
          .eq(
            'hospital_id',
            hospitalId,
          );

      for (final row in _rows(response)) {
        final id = row['id']?.toString();

        if (id != null && id.isNotEmpty) {
          patientIds.add(id);
        }
      }
    } catch (_) {
      // patient_hospital_links is checked below.
    }

    try {
      final response = await _supabase
          .from('patient_hospital_links')
          .select(
            'patient_id',
          )
          .eq(
            'hospital_id',
            hospitalId,
          );

      for (final row in _rows(response)) {
        final id = row['patient_id']?.toString();

        if (id != null && id.isNotEmpty) {
          patientIds.add(id);
        }
      }
    } catch (_) {
      // patients.hospital_id may still provide records.
    }

    if (patientIds.isEmpty) {
      return [];
    }

    final patients = await _fetchPatients(
      patientIds,
    );

    final profileIds = patients
        .map(
          (patient) => patient['profile_id']?.toString(),
        )
        .whereType<String>()
        .toSet();

    final profiles = await _fetchProfiles(
      profileIds,
    );

    final profileById = <String, Map<String, dynamic>>{
      for (final profile in profiles)
        if (profile['id'] != null) profile['id'].toString(): profile,
    };

    final result = <TransferPatientOption>[];

    for (final patient in patients) {
      final patientId = patient['id']?.toString();

      if (patientId == null || patientId.isEmpty) {
        continue;
      }

      final profileId = patient['profile_id']?.toString();

      final profile = profileId == null ? null : profileById[profileId];

      result.add(
        TransferPatientOption(
          patientId: patientId,
          profileId: profileId,
          patientName: _profileName(
            profile,
          ),
          patientNumber: patient['patient_number']?.toString(),
          dateOfBirth: _date(
            patient['date_of_birth'],
          ),
          gender: patient['gender']?.toString(),
          phone: patient['phone']?.toString() ?? profile?['phone']?.toString(),
          email: patient['email']?.toString() ?? profile?['email']?.toString(),
          bloodType: patient['blood_type']?.toString(),
        ),
      );
    }

    result.sort(
      (
        first,
        second,
      ) =>
          first.patientName.toLowerCase().compareTo(
                second.patientName.toLowerCase(),
              ),
    );

    return result;
  }

  // ===========================================================================
  // ADMISSIONS
  // ===========================================================================

  Future<List<TransferAdmissionOption>> getAdmissionsForHospital(
    String hospitalId, {
    String? patientId,
    Set<String> statuses = const {
      'planned',
      'admitted',
    },
  }) async {
    dynamic query = _supabase
        .from('hospital_admissions')
        .select(
          'id, hospital_id, patient_id, admission_number, '
          'admission_type, status, admitted_at, '
          'expected_discharge_at, discharged_at, created_at',
        )
        .eq(
          'hospital_id',
          hospitalId,
        );

    if (patientId != null && patientId.trim().isNotEmpty) {
      query = query.eq(
        'patient_id',
        patientId,
      );
    }

    if (statuses.isNotEmpty) {
      query = query.inFilter(
        'status',
        statuses.toList(),
      );
    }

    final response = await query.order(
      'created_at',
      ascending: false,
    );

    final admissionRows = _rows(response);

    if (admissionRows.isEmpty) {
      return [];
    }

    final patients = await _fetchPatients(
      admissionRows
          .map(
            (row) => row['patient_id']?.toString(),
          )
          .whereType<String>(),
    );

    final profiles = await _fetchProfiles(
      patients
          .map(
            (patient) => patient['profile_id']?.toString(),
          )
          .whereType<String>(),
    );

    final assignments = await _fetchActiveAssignments(
      hospitalId: hospitalId,
      admissionIds: admissionRows
          .map(
            (row) => row['id']?.toString(),
          )
          .whereType<String>(),
    );

    final patientById = <String, Map<String, dynamic>>{
      for (final patient in patients)
        if (patient['id'] != null) patient['id'].toString(): patient,
    };

    final profileById = <String, Map<String, dynamic>>{
      for (final profile in profiles)
        if (profile['id'] != null) profile['id'].toString(): profile,
    };

    final assignmentByAdmissionId = <String, Map<String, dynamic>>{
      for (final assignment in assignments)
        if (assignment['admission_id'] != null)
          assignment['admission_id'].toString(): assignment,
    };

    final wards = await _fetchWards(
      assignments
          .map(
            (row) => row['ward_id']?.toString(),
          )
          .whereType<String>(),
    );

    final rooms = await _fetchRooms(
      assignments
          .map(
            (row) => row['room_id']?.toString(),
          )
          .whereType<String>(),
    );

    final beds = await _fetchBeds(
      assignments
          .map(
            (row) => row['bed_id']?.toString(),
          )
          .whereType<String>(),
    );

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

    final output = <TransferAdmissionOption>[];

    for (final row in admissionRows) {
      final admissionId = row['id']?.toString();

      final admissionPatientId = row['patient_id']?.toString();

      if (admissionId == null || admissionPatientId == null) {
        continue;
      }

      final patient = patientById[admissionPatientId];

      final profileId = patient?['profile_id']?.toString();

      final profile = profileId == null ? null : profileById[profileId];

      final assignment = assignmentByAdmissionId[admissionId];

      final wardId = assignment?['ward_id']?.toString();

      final roomId = assignment?['room_id']?.toString();

      final bedId = assignment?['bed_id']?.toString();

      final ward = wardId == null ? null : wardById[wardId];

      final room = roomId == null ? null : roomById[roomId];

      final bed = bedId == null ? null : bedById[bedId];

      output.add(
        TransferAdmissionOption(
          admissionId: admissionId,
          hospitalId: hospitalId,
          patientId: admissionPatientId,
          patientName: _profileName(
            profile,
          ),
          patientNumber: patient?['patient_number']?.toString(),
          admissionNumber: row['admission_number']?.toString(),
          admissionType: row['admission_type']?.toString() ?? 'general',
          status: row['status']?.toString() ?? 'planned',
          admittedAt: _date(
            row['admitted_at'],
          ),
          expectedDischargeAt: _date(
            row['expected_discharge_at'],
          ),
          dischargedAt: _date(
            row['discharged_at'],
          ),
          wardId: wardId,
          wardName: ward?['name']?.toString(),
          roomId: roomId,
          roomNumber: room?['room_number']?.toString(),
          roomName: room?['room_name']?.toString(),
          bedId: bedId,
          bedNumber: bed?['bed_number']?.toString(),
          bedLabel: bed?['bed_label']?.toString(),
        ),
      );
    }

    return output;
  }

  // ===========================================================================
  // DESTINATION BEDS
  // ===========================================================================

  Future<List<TransferBedOption>> getDestinationBeds(
    String hospitalId, {
    bool availableOnly = true,
  }) async {
    dynamic query = _supabase
        .from('hospital_beds')
        .select(
          'id, hospital_id, ward_id, room_id, '
          'bed_number, bed_label, bed_type, status, is_active',
        )
        .eq(
          'hospital_id',
          hospitalId,
        )
        .eq(
          'is_active',
          true,
        );

    if (availableOnly) {
      query = query.inFilter(
        'status',
        [
          'available',
          'reserved',
        ],
      );
    }

    final response = await query.order(
      'bed_number',
    );

    final bedRows = _rows(response);

    if (bedRows.isEmpty) {
      return [];
    }

    final wards = await _fetchWards(
      bedRows
          .map(
            (bed) => bed['ward_id']?.toString(),
          )
          .whereType<String>(),
    );

    final rooms = await _fetchRooms(
      bedRows
          .map(
            (bed) => bed['room_id']?.toString(),
          )
          .whereType<String>(),
    );

    final wardById = <String, Map<String, dynamic>>{
      for (final ward in wards)
        if (ward['id'] != null) ward['id'].toString(): ward,
    };

    final roomById = <String, Map<String, dynamic>>{
      for (final room in rooms)
        if (room['id'] != null) room['id'].toString(): room,
    };

    final bedsOutput = <TransferBedOption>[];

    for (final bed in bedRows) {
      final bedId = bed['id']?.toString();

      if (bedId == null || bedId.isEmpty) {
        continue;
      }

      final wardId = bed['ward_id']?.toString();

      final roomId = bed['room_id']?.toString();

      final ward = wardId == null ? null : wardById[wardId];

      final room = roomId == null ? null : roomById[roomId];

      bedsOutput.add(
        TransferBedOption(
          bedId: bedId,
          hospitalId: hospitalId,
          wardId: wardId,
          wardName: ward?['name']?.toString(),
          roomId: roomId,
          roomNumber: room?['room_number']?.toString(),
          roomName: room?['room_name']?.toString(),
          bedNumber: bed['bed_number']?.toString(),
          bedLabel: bed['bed_label']?.toString(),
          bedType: bed['bed_type']?.toString(),
          status: bed['status']?.toString() ?? 'available',
        ),
      );
    }

    bedsOutput.sort(
      (
        first,
        second,
      ) =>
          first.displayLocation.toLowerCase().compareTo(
                second.displayLocation.toLowerCase(),
              ),
    );

    return bedsOutput;
  }

  // ===========================================================================
  // DASHBOARD
  // ===========================================================================

  Future<InterhospitalTransferDashboardStats> getDashboardStats(
    String hospitalId,
  ) async {
    final response = await _supabase.rpc(
      'corvia_mh_interhospital_transfer_dashboard_stats',
      params: {
        'p_hospital_id': hospitalId,
      },
    );

    final data = _map(response);

    if (data.isEmpty) {
      return InterhospitalTransferDashboardStats.empty(
        hospitalId,
      );
    }

    return InterhospitalTransferDashboardStats.fromMap(
      data,
    );
  }

  // ===========================================================================
  // TRANSFER RECORDS
  // ===========================================================================

  Future<List<InterhospitalTransferRecord>> getTransfers(
    String hospitalId, {
    Set<String>? statuses,
    int limit = 500,
  }) async {
    dynamic query = _supabase
        .from('interhospital_transfers')
        .select(
          'id, transfer_number, patient_id, '
          'source_hospital_id, destination_hospital_id, '
          'source_admission_id, destination_admission_id, '
          'destination_ward_id, destination_room_id, '
          'destination_bed_id, status, priority, '
          'transfer_reason, clinical_summary, handover_summary, '
          'medication_summary, equipment_summary, patient_snapshot, '
          'transport_method, transport_provider, transport_reference, '
          'transport_contact, escort_required, escort_notes, '
          'estimated_departure_at, estimated_arrival_at, '
          'actual_departure_at, actual_arrival_at, '
          'consent_confirmed, patient_notified, requested_at, '
          'accepted_at, rejected_at, rejection_reason, prepared_at, '
          'completed_at, cancelled_at, cancellation_reason, '
          'destination_notes, notes, last_status_reason, '
          'created_at, updated_at',
        )
        .or(
          'source_hospital_id.eq.$hospitalId,'
          'destination_hospital_id.eq.$hospitalId',
        );

    if (statuses != null && statuses.isNotEmpty) {
      query = query.inFilter(
        'status',
        statuses.toList(),
      );
    }

    final response = await query
        .order(
          'created_at',
          ascending: false,
        )
        .limit(
          limit,
        );

    final transferRows = _rows(response);

    if (transferRows.isEmpty) {
      return [];
    }

    final hospitalIds = <String>{};

    for (final row in transferRows) {
      final sourceId = row['source_hospital_id']?.toString();

      final destinationId = row['destination_hospital_id']?.toString();

      if (sourceId != null) {
        hospitalIds.add(
          sourceId,
        );
      }

      if (destinationId != null) {
        hospitalIds.add(
          destinationId,
        );
      }
    }

    final hospitals = await _getHospitalsByIds(
      hospitalIds,
    );

    final patients = await _fetchPatients(
      transferRows
          .map(
            (row) => row['patient_id']?.toString(),
          )
          .whereType<String>(),
    );

    final profiles = await _fetchProfiles(
      patients
          .map(
            (patient) => patient['profile_id']?.toString(),
          )
          .whereType<String>(),
    );

    final patientById = <String, Map<String, dynamic>>{
      for (final patient in patients)
        if (patient['id'] != null) patient['id'].toString(): patient,
    };

    final profileById = <String, Map<String, dynamic>>{
      for (final profile in profiles)
        if (profile['id'] != null) profile['id'].toString(): profile,
    };

    final wards = await _fetchWards(
      transferRows
          .map(
            (row) => row['destination_ward_id']?.toString(),
          )
          .whereType<String>(),
    );

    final rooms = await _fetchRooms(
      transferRows
          .map(
            (row) => row['destination_room_id']?.toString(),
          )
          .whereType<String>(),
    );

    final beds = await _fetchBeds(
      transferRows
          .map(
            (row) => row['destination_bed_id']?.toString(),
          )
          .whereType<String>(),
    );

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

    final transferIds = transferRows
        .map(
          (row) => row['id']?.toString(),
        )
        .whereType<String>()
        .toSet();

    final documents = await _fetchDocumentsForTransfers(
      transferIds,
    );

    final history = await _fetchHistoryForTransfers(
      transferIds,
    );

    final documentsByTransfer = <String, List<TransferDocumentRecord>>{};

    for (final document in documents) {
      documentsByTransfer
          .putIfAbsent(
            document.transferId,
            () => [],
          )
          .add(
            document,
          );
    }

    final historyByTransfer = <String, List<TransferStatusHistoryRecord>>{};

    for (final historyItem in history) {
      historyByTransfer
          .putIfAbsent(
            historyItem.transferId,
            () => [],
          )
          .add(
            historyItem,
          );
    }

    final result = <InterhospitalTransferRecord>[];

    for (final row in transferRows) {
      final transferId = row['id']?.toString();

      final patientId = row['patient_id']?.toString();

      final sourceHospitalId = row['source_hospital_id']?.toString();

      final destinationHospitalId = row['destination_hospital_id']?.toString();

      if (transferId == null ||
          patientId == null ||
          sourceHospitalId == null ||
          destinationHospitalId == null) {
        continue;
      }

      final patient = patientById[patientId];

      final profileId = patient?['profile_id']?.toString();

      final profile = profileId == null ? null : profileById[profileId];

      final snapshot = _jsonMap(
        row['patient_snapshot'],
      );

      final snapshotName = snapshot['display_name']?.toString().trim();

      final patientName = snapshotName != null && snapshotName.isNotEmpty
          ? snapshotName
          : _profileName(
              profile,
            );

      final wardId = row['destination_ward_id']?.toString();

      final roomId = row['destination_room_id']?.toString();

      final bedId = row['destination_bed_id']?.toString();

      final ward = wardId == null ? null : wardById[wardId];

      final room = roomId == null ? null : roomById[roomId];

      final bed = bedId == null ? null : bedById[bedId];

      result.add(
        InterhospitalTransferRecord(
          transferId: transferId,
          transferNumber: row['transfer_number']?.toString() ?? transferId,
          patientId: patientId,
          patientName: patientName,
          patientNumber: snapshot['patient_number']?.toString() ??
              patient?['patient_number']?.toString(),
          sourceHospitalId: sourceHospitalId,
          sourceHospitalName: hospitals[sourceHospitalId]?.hospitalName ??
              'Unknown source hospital',
          destinationHospitalId: destinationHospitalId,
          destinationHospitalName:
              hospitals[destinationHospitalId]?.hospitalName ??
                  'Unknown destination hospital',
          sourceAdmissionId: row['source_admission_id']?.toString(),
          destinationAdmissionId: row['destination_admission_id']?.toString(),
          destinationWardId: wardId,
          destinationWardName: ward?['name']?.toString(),
          destinationRoomId: roomId,
          destinationRoomNumber: room?['room_number']?.toString(),
          destinationRoomName: room?['room_name']?.toString(),
          destinationBedId: bedId,
          destinationBedNumber: bed?['bed_number']?.toString(),
          destinationBedLabel: bed?['bed_label']?.toString(),
          status: row['status']?.toString() ?? 'requested',
          priority: row['priority']?.toString() ?? 'routine',
          transferReason: row['transfer_reason']?.toString() ?? '',
          clinicalSummary: row['clinical_summary']?.toString() ?? '',
          handoverSummary: row['handover_summary']?.toString(),
          medicationSummary: row['medication_summary']?.toString(),
          equipmentSummary: row['equipment_summary']?.toString(),
          patientSnapshot: snapshot,
          transportMethod: row['transport_method']?.toString(),
          transportProvider: row['transport_provider']?.toString(),
          transportReference: row['transport_reference']?.toString(),
          transportContact: row['transport_contact']?.toString(),
          escortRequired: _boolean(
            row['escort_required'],
          ),
          escortNotes: row['escort_notes']?.toString(),
          estimatedDepartureAt: _date(
            row['estimated_departure_at'],
          ),
          estimatedArrivalAt: _date(
            row['estimated_arrival_at'],
          ),
          actualDepartureAt: _date(
            row['actual_departure_at'],
          ),
          actualArrivalAt: _date(
            row['actual_arrival_at'],
          ),
          consentConfirmed: _boolean(
            row['consent_confirmed'],
          ),
          patientNotified: _boolean(
            row['patient_notified'],
          ),
          requestedAt: _date(
            row['requested_at'],
          ),
          acceptedAt: _date(
            row['accepted_at'],
          ),
          rejectedAt: _date(
            row['rejected_at'],
          ),
          rejectionReason: row['rejection_reason']?.toString(),
          preparedAt: _date(
            row['prepared_at'],
          ),
          completedAt: _date(
            row['completed_at'],
          ),
          cancelledAt: _date(
            row['cancelled_at'],
          ),
          cancellationReason: row['cancellation_reason']?.toString(),
          destinationNotes: row['destination_notes']?.toString(),
          notes: row['notes']?.toString(),
          lastStatusReason: row['last_status_reason']?.toString(),
          createdAt: _date(
            row['created_at'],
          ),
          updatedAt: _date(
            row['updated_at'],
          ),
          documents: documentsByTransfer[transferId] ?? [],
          statusHistory: historyByTransfer[transferId] ?? [],
        ),
      );
    }

    return result;
  }

  // ===========================================================================
  // CREATE TRANSFER
  // ===========================================================================

  Future<TransferActionResult> createTransfer({
    required String sourceHospitalId,
    required String destinationHospitalId,
    required String patientId,
    required String transferReason,
    required String clinicalSummary,
    String? sourceAdmissionId,
    String priority = 'routine',
    String? transportMethod,
    DateTime? estimatedDepartureAt,
    DateTime? estimatedArrivalAt,
    bool consentConfirmed = false,
    bool patientNotified = false,
    String? notes,
  }) async {
    if (sourceHospitalId.trim().isEmpty) {
      throw Exception(
        'Source hospital is required.',
      );
    }

    if (destinationHospitalId.trim().isEmpty) {
      throw Exception(
        'Destination hospital is required.',
      );
    }

    if (sourceHospitalId == destinationHospitalId) {
      throw Exception(
        'Source and destination hospitals must be different.',
      );
    }

    if (patientId.trim().isEmpty) {
      throw Exception(
        'Patient is required.',
      );
    }

    if (transferReason.trim().isEmpty) {
      throw Exception(
        'Transfer reason is required.',
      );
    }

    if (clinicalSummary.trim().isEmpty) {
      throw Exception(
        'Clinical summary is required.',
      );
    }

    final response = await _supabase.rpc(
      'corvia_mh_create_interhospital_transfer',
      params: {
        'p_source_hospital_id': sourceHospitalId,
        'p_destination_hospital_id': destinationHospitalId,
        'p_patient_id': patientId,
        'p_transfer_reason': transferReason.trim(),
        'p_clinical_summary': clinicalSummary.trim(),
        'p_source_admission_id': _nullableText(
          sourceAdmissionId,
        ),
        'p_priority': priority,
        'p_transport_method': _nullableText(
          transportMethod,
        ),
        'p_estimated_departure_at':
            estimatedDepartureAt?.toUtc().toIso8601String(),
        'p_estimated_arrival_at': estimatedArrivalAt?.toUtc().toIso8601String(),
        'p_consent_confirmed': consentConfirmed,
        'p_patient_notified': patientNotified,
        'p_notes': _nullableText(
          notes,
        ),
      },
    );

    return _requireSuccessfulResult(
      response,
      fallbackMessage: 'Transfer could not be created.',
    );
  }

  Future<TransferActionResult> acceptTransfer({
    required String transferId,
    String? destinationWardId,
    String? destinationRoomId,
    String? destinationBedId,
    DateTime? estimatedArrivalAt,
    String? destinationNotes,
  }) async {
    final response = await _supabase.rpc(
      'corvia_mh_accept_interhospital_transfer',
      params: {
        'p_transfer_id': transferId,
        'p_destination_ward_id': _nullableText(
          destinationWardId,
        ),
        'p_destination_room_id': _nullableText(
          destinationRoomId,
        ),
        'p_destination_bed_id': _nullableText(
          destinationBedId,
        ),
        'p_estimated_arrival_at': estimatedArrivalAt?.toUtc().toIso8601String(),
        'p_destination_notes': _nullableText(
          destinationNotes,
        ),
      },
    );

    return _requireSuccessfulResult(
      response,
      fallbackMessage: 'Transfer could not be accepted.',
    );
  }

  Future<TransferActionResult> rejectTransfer({
    required String transferId,
    required String rejectionReason,
  }) async {
    if (rejectionReason.trim().isEmpty) {
      throw Exception(
        'Rejection reason is required.',
      );
    }

    final response = await _supabase.rpc(
      'corvia_mh_reject_interhospital_transfer',
      params: {
        'p_transfer_id': transferId,
        'p_rejection_reason': rejectionReason.trim(),
      },
    );

    return _requireSuccessfulResult(
      response,
      fallbackMessage: 'Transfer could not be rejected.',
    );
  }

  Future<TransferActionResult> updateTransportDetails({
    required String transferId,
    required String transportMethod,
    String? transportProvider,
    String? transportReference,
    String? transportContact,
    bool escortRequired = false,
    String? escortNotes,
    DateTime? estimatedDepartureAt,
    DateTime? estimatedArrivalAt,
    String? handoverSummary,
    String? medicationSummary,
    String? equipmentSummary,
    bool consentConfirmed = false,
    bool patientNotified = false,
  }) async {
    if (transportMethod.trim().isEmpty) {
      throw Exception(
        'Transport method is required.',
      );
    }

    final response = await _supabase.rpc(
      'corvia_mh_update_transfer_transport',
      params: {
        'p_transfer_id': transferId,
        'p_transport_method': transportMethod.trim(),
        'p_transport_provider': _nullableText(
          transportProvider,
        ),
        'p_transport_reference': _nullableText(
          transportReference,
        ),
        'p_transport_contact': _nullableText(
          transportContact,
        ),
        'p_escort_required': escortRequired,
        'p_escort_notes': _nullableText(
          escortNotes,
        ),
        'p_estimated_departure_at':
            estimatedDepartureAt?.toUtc().toIso8601String(),
        'p_estimated_arrival_at': estimatedArrivalAt?.toUtc().toIso8601String(),
        'p_handover_summary': _nullableText(
          handoverSummary,
        ),
        'p_medication_summary': _nullableText(
          medicationSummary,
        ),
        'p_equipment_summary': _nullableText(
          equipmentSummary,
        ),
        'p_consent_confirmed': consentConfirmed,
        'p_patient_notified': patientNotified,
      },
    );

    return _requireSuccessfulResult(
      response,
      fallbackMessage: 'Transport details could not be updated.',
    );
  }

  Future<TransferActionResult> prepareTransfer({
    required String transferId,
    required String handoverSummary,
    String? medicationSummary,
    String? equipmentSummary,
    String? notes,
  }) async {
    if (handoverSummary.trim().isEmpty) {
      throw Exception(
        'Clinical handover summary is required.',
      );
    }

    final response = await _supabase.rpc(
      'corvia_mh_prepare_interhospital_transfer',
      params: {
        'p_transfer_id': transferId,
        'p_handover_summary': handoverSummary.trim(),
        'p_medication_summary': _nullableText(
          medicationSummary,
        ),
        'p_equipment_summary': _nullableText(
          equipmentSummary,
        ),
        'p_notes': _nullableText(
          notes,
        ),
      },
    );

    return _requireSuccessfulResult(
      response,
      fallbackMessage: 'Transfer could not be prepared.',
    );
  }

  Future<TransferActionResult> markTransferInTransit({
    required String transferId,
    DateTime? actualDepartureAt,
    String? transportReference,
    String? notes,
  }) async {
    final response = await _supabase.rpc(
      'corvia_mh_mark_transfer_in_transit',
      params: {
        'p_transfer_id': transferId,
        'p_actual_departure_at':
            (actualDepartureAt ?? DateTime.now()).toUtc().toIso8601String(),
        'p_transport_reference': _nullableText(
          transportReference,
        ),
        'p_notes': _nullableText(
          notes,
        ),
      },
    );

    return _requireSuccessfulResult(
      response,
      fallbackMessage: 'Patient could not be marked in transit.',
    );
  }

  Future<TransferActionResult> receiveTransfer({
    required String transferId,
    DateTime? actualArrivalAt,
    String? destinationNotes,
  }) async {
    final response = await _supabase.rpc(
      'corvia_mh_receive_interhospital_transfer',
      params: {
        'p_transfer_id': transferId,
        'p_actual_arrival_at':
            (actualArrivalAt ?? DateTime.now()).toUtc().toIso8601String(),
        'p_destination_notes': _nullableText(
          destinationNotes,
        ),
      },
    );

    return _requireSuccessfulResult(
      response,
      fallbackMessage: 'Patient could not be received.',
    );
  }

  Future<TransferActionResult> completeTransfer({
    required String transferId,
    required String destinationAdmissionId,
    String? completionNotes,
  }) async {
    if (destinationAdmissionId.trim().isEmpty) {
      throw Exception(
        'Destination admission is required.',
      );
    }

    final response = await _supabase.rpc(
      'corvia_mh_complete_interhospital_transfer',
      params: {
        'p_transfer_id': transferId,
        'p_destination_admission_id': destinationAdmissionId,
        'p_completion_notes': _nullableText(
          completionNotes,
        ),
      },
    );

    return _requireSuccessfulResult(
      response,
      fallbackMessage: 'Transfer could not be completed.',
    );
  }

  Future<TransferActionResult> cancelTransfer({
    required String transferId,
    required String cancellationReason,
  }) async {
    if (cancellationReason.trim().isEmpty) {
      throw Exception(
        'Cancellation reason is required.',
      );
    }

    final response = await _supabase.rpc(
      'corvia_mh_cancel_interhospital_transfer',
      params: {
        'p_transfer_id': transferId,
        'p_cancellation_reason': cancellationReason.trim(),
      },
    );

    return _requireSuccessfulResult(
      response,
      fallbackMessage: 'Transfer could not be cancelled.',
    );
  }

  TransferActionResult _requireSuccessfulResult(
    dynamic response, {
    required String fallbackMessage,
  }) {
    final result = TransferActionResult.fromMap(
      _map(response),
    );

    if (!result.success) {
      throw Exception(
        result.message ?? fallbackMessage,
      );
    }

    return result;
  }

  // ===========================================================================
  // DOCUMENTS
  // ===========================================================================

  Future<TransferDocumentRecord> uploadTransferDocument({
    required String transferId,
    required String hospitalId,
    required Uint8List bytes,
    required String fileName,
    required String documentType,
    String bucket = defaultDocumentBucket,
    String? mimeType,
    String? checksumSha256,
    String? description,
    bool isClinical = true,
    bool sharedWithDestination = true,
  }) async {
    if (bytes.isEmpty) {
      throw Exception(
        'The selected document is empty.',
      );
    }

    if (fileName.trim().isEmpty) {
      throw Exception(
        'File name is required.',
      );
    }

    if (documentType.trim().isEmpty) {
      throw Exception(
        'Document type is required.',
      );
    }

    final timestamp = DateTime.now().toUtc().millisecondsSinceEpoch;

    final safeName = _safeFileName(
      fileName,
    );

    final storagePath = '$hospitalId/$transferId/'
        '${timestamp}_$safeName';

    var uploaded = false;

    try {
      await _supabase.storage.from(bucket).uploadBinary(
            storagePath,
            bytes,
            fileOptions: FileOptions(
              cacheControl: '3600',
              upsert: false,
              contentType: mimeType,
            ),
          );

      uploaded = true;

      final response = await _supabase.rpc(
        'corvia_mh_add_transfer_document',
        params: {
          'p_transfer_id': transferId,
          'p_document_type': documentType.trim(),
          'p_file_name': fileName.trim(),
          'p_storage_path': storagePath,
          'p_storage_bucket': bucket,
          'p_mime_type': _nullableText(
            mimeType,
          ),
          'p_file_size_bytes': bytes.length,
          'p_checksum_sha256': _nullableText(
            checksumSha256,
          ),
          'p_description': _nullableText(
            description,
          ),
          'p_is_clinical': isClinical,
          'p_shared_with_destination': sharedWithDestination,
        },
      );

      final data = _map(response);

      final documentId =
          data['document_id']?.toString() ?? data['id']?.toString();

      if (documentId == null || documentId.isEmpty) {
        throw Exception(
          'Document metadata was not created.',
        );
      }

      return TransferDocumentRecord(
        documentId: documentId,
        transferId: transferId,
        hospitalId: hospitalId,
        documentType: documentType,
        fileName: fileName,
        storageBucket: bucket,
        storagePath: storagePath,
        mimeType: mimeType,
        fileSizeBytes: bytes.length,
        checksumSha256: checksumSha256,
        description: description,
        isClinical: isClinical,
        sharedWithDestination: sharedWithDestination,
        isActive: true,
        deactivationReason: null,
        createdAt: DateTime.now(),
      );
    } catch (_) {
      if (uploaded) {
        try {
          await _supabase.storage.from(bucket).remove(
            [
              storagePath,
            ],
          );
        } catch (_) {
          // Preserve original error.
        }
      }

      rethrow;
    }
  }

  Future<String> createSignedDocumentUrl({
    required TransferDocumentRecord document,
    int expiresInSeconds = 300,
  }) async {
    if (!document.isActive) {
      throw Exception(
        'This document is inactive.',
      );
    }

    return _supabase.storage
        .from(
          document.storageBucket,
        )
        .createSignedUrl(
          document.storagePath,
          expiresInSeconds,
        );
  }

  Future<Uint8List> downloadTransferDocument({
    required TransferDocumentRecord document,
  }) async {
    if (!document.isActive) {
      throw Exception(
        'This document is inactive.',
      );
    }

    return _supabase.storage
        .from(
          document.storageBucket,
        )
        .download(
          document.storagePath,
        );
  }

  Future<void> deactivateTransferDocument({
    required String documentId,
    required String reason,
  }) async {
    if (reason.trim().isEmpty) {
      throw Exception(
        'Deactivation reason is required.',
      );
    }

    final response = await _supabase.rpc(
      'corvia_mh_deactivate_transfer_document',
      params: {
        'p_document_id': documentId,
        'p_reason': reason.trim(),
      },
    );

    var success = false;

    if (response is bool) {
      success = response;
    } else {
      final data = _map(response);

      success = _boolean(
            data['success'],
          ) ||
          _boolean(
            data['result'],
          );
    }

    if (!success) {
      throw Exception(
        'Document could not be deactivated.',
      );
    }
  }

  // ===========================================================================
  // AUDIT
  // ===========================================================================

  Future<void> logTransferAccess({
    required String transferId,
    String action = 'view_transfer',
    Map<String, dynamic> details = const {},
  }) async {
    final response = await _supabase.rpc(
      'corvia_mh_log_transfer_access',
      params: {
        'p_transfer_id': transferId,
        'p_action': action,
        'p_details': details,
      },
    );

    if (response is bool && !response) {
      throw Exception(
        'Transfer access could not be logged.',
      );
    }
  }

  // ===========================================================================
  // WORKSPACE
  // ===========================================================================

  Future<InterhospitalTransferWorkspace> loadWorkspace(
    String hospitalId,
  ) async {
    final results = await Future.wait<dynamic>(
      [
        getDashboardStats(
          hospitalId,
        ),
        getTransfers(
          hospitalId,
        ),
        getPatientsForHospital(
          hospitalId,
        ),
        getAdmissionsForHospital(
          hospitalId,
        ),
        getDestinationHospitals(
          sourceHospitalId: hospitalId,
        ),
      ],
    );

    return InterhospitalTransferWorkspace(
      hospitalId: hospitalId,
      stats: results[0] as InterhospitalTransferDashboardStats,
      transfers: results[1] as List<InterhospitalTransferRecord>,
      patients: results[2] as List<TransferPatientOption>,
      admissions: results[3] as List<TransferAdmissionOption>,
      destinationHospitals: results[4] as List<TransferHospitalOption>,
    );
  }

  // ===========================================================================
  // INTERNAL FETCH METHODS
  // ===========================================================================

  Future<List<Map<String, dynamic>>> _fetchPatients(
    Iterable<String> ids,
  ) async {
    final output = <Map<String, dynamic>>[];

    for (final chunk in _chunks(ids)) {
      if (chunk.isEmpty) {
        continue;
      }

      final response = await _supabase
          .from('patients')
          .select(
            'id, profile_id, patient_number, hospital_id, '
            'phone, email, date_of_birth, gender, blood_type',
          )
          .inFilter(
            'id',
            chunk,
          );

      output.addAll(
        _rows(response),
      );
    }

    return output;
  }

  Future<List<Map<String, dynamic>>> _fetchProfiles(
    Iterable<String> ids,
  ) async {
    final output = <Map<String, dynamic>>[];

    for (final chunk in _chunks(ids)) {
      if (chunk.isEmpty) {
        continue;
      }

      /*
       * IMPORTANT:
       *
       * Do not explicitly request optional legacy columns such as:
       *
       * full_name
       * last_name
       *
       * because they do not exist in every Corvia profiles schema.
       *
       * select() returns the actual columns present on the table.
       */
      final response = await _supabase.from('profiles').select().inFilter(
            'id',
            chunk,
          );

      output.addAll(
        _rows(response),
      );
    }

    return output;
  }

  Future<List<Map<String, dynamic>>> _fetchActiveAssignments({
    required String hospitalId,
    required Iterable<String> admissionIds,
  }) async {
    final output = <Map<String, dynamic>>[];

    for (final chunk in _chunks(admissionIds)) {
      if (chunk.isEmpty) {
        continue;
      }

      final response = await _supabase
          .from('patient_bed_assignments')
          .select(
            'id, hospital_id, admission_id, patient_id, '
            'ward_id, room_id, bed_id, status, assigned_at, ended_at',
          )
          .eq(
            'hospital_id',
            hospitalId,
          )
          .inFilter(
            'admission_id',
            chunk,
          )
          .eq(
            'status',
            'active',
          )
          .isFilter(
            'ended_at',
            null,
          );

      output.addAll(
        _rows(response),
      );
    }

    return output;
  }

  Future<List<Map<String, dynamic>>> _fetchWards(
    Iterable<String> ids,
  ) async {
    final output = <Map<String, dynamic>>[];

    for (final chunk in _chunks(ids)) {
      if (chunk.isEmpty) {
        continue;
      }

      final response = await _supabase
          .from('hospital_wards')
          .select(
            'id, hospital_id, name, ward_type, is_active',
          )
          .inFilter(
            'id',
            chunk,
          );

      output.addAll(
        _rows(response),
      );
    }

    return output;
  }

  Future<List<Map<String, dynamic>>> _fetchRooms(
    Iterable<String> ids,
  ) async {
    final output = <Map<String, dynamic>>[];

    for (final chunk in _chunks(ids)) {
      if (chunk.isEmpty) {
        continue;
      }

      final response = await _supabase
          .from('hospital_rooms')
          .select(
            'id, hospital_id, ward_id, room_number, '
            'room_name, room_type, is_active',
          )
          .inFilter(
            'id',
            chunk,
          );

      output.addAll(
        _rows(response),
      );
    }

    return output;
  }

  Future<List<Map<String, dynamic>>> _fetchBeds(
    Iterable<String> ids,
  ) async {
    final output = <Map<String, dynamic>>[];

    for (final chunk in _chunks(ids)) {
      if (chunk.isEmpty) {
        continue;
      }

      final response = await _supabase
          .from('hospital_beds')
          .select(
            'id, hospital_id, ward_id, room_id, '
            'bed_number, bed_label, bed_type, status, is_active',
          )
          .inFilter(
            'id',
            chunk,
          );

      output.addAll(
        _rows(response),
      );
    }

    return output;
  }

  Future<List<TransferDocumentRecord>> _fetchDocumentsForTransfers(
    Iterable<String> transferIds,
  ) async {
    final output = <TransferDocumentRecord>[];

    for (final chunk in _chunks(transferIds)) {
      if (chunk.isEmpty) {
        continue;
      }

      final response = await _supabase
          .from(
            'interhospital_transfer_documents',
          )
          .select(
            'id, transfer_id, hospital_id, document_type, '
            'file_name, storage_bucket, storage_path, mime_type, '
            'file_size_bytes, checksum_sha256, description, '
            'is_clinical, shared_with_destination, is_active, '
            'deactivation_reason, created_at',
          )
          .inFilter(
            'transfer_id',
            chunk,
          )
          .order(
            'created_at',
            ascending: false,
          );

      output.addAll(
        _rows(response).map(
          TransferDocumentRecord.fromMap,
        ),
      );
    }

    return output;
  }

  Future<List<TransferStatusHistoryRecord>> _fetchHistoryForTransfers(
    Iterable<String> transferIds,
  ) async {
    final output = <TransferStatusHistoryRecord>[];

    for (final chunk in _chunks(transferIds)) {
      if (chunk.isEmpty) {
        continue;
      }

      final response = await _supabase
          .from(
            'interhospital_transfer_status_history',
          )
          .select(
            'id, transfer_id, source_hospital_id, '
            'destination_hospital_id, previous_status, new_status, '
            'reason, details, changed_by, changed_at',
          )
          .inFilter(
            'transfer_id',
            chunk,
          )
          .order(
            'changed_at',
            ascending: false,
          );

      output.addAll(
        _rows(response).map(
          TransferStatusHistoryRecord.fromMap,
        ),
      );
    }

    return output;
  }
}

// =============================================================================
// HOSPITAL OPTION
// =============================================================================

class TransferHospitalOption {
  const TransferHospitalOption({
    required this.hospitalId,
    required this.hospitalName,
    required this.adminRole,
    required this.isCurrentAdminHospital,
  });

  final String hospitalId;
  final String hospitalName;
  final String? adminRole;
  final bool isCurrentAdminHospital;
}

// =============================================================================
// PATIENT OPTION
// =============================================================================

class TransferPatientOption {
  const TransferPatientOption({
    required this.patientId,
    required this.profileId,
    required this.patientName,
    required this.patientNumber,
    required this.dateOfBirth,
    required this.gender,
    required this.phone,
    required this.email,
    required this.bloodType,
  });

  final String patientId;
  final String? profileId;

  final String patientName;
  final String? patientNumber;

  final DateTime? dateOfBirth;
  final String? gender;
  final String? phone;
  final String? email;
  final String? bloodType;

  String get displayPatientNumber {
    final number = patientNumber?.trim();

    if (number != null && number.isNotEmpty) {
      return number;
    }

    if (patientId.length >= 8) {
      return patientId
          .substring(
            0,
            8,
          )
          .toUpperCase();
    }

    return patientId;
  }
}

// =============================================================================
// ADMISSION OPTION
// =============================================================================

class TransferAdmissionOption {
  const TransferAdmissionOption({
    required this.admissionId,
    required this.hospitalId,
    required this.patientId,
    required this.patientName,
    required this.patientNumber,
    required this.admissionNumber,
    required this.admissionType,
    required this.status,
    required this.admittedAt,
    required this.expectedDischargeAt,
    required this.dischargedAt,
    required this.wardId,
    required this.wardName,
    required this.roomId,
    required this.roomNumber,
    required this.roomName,
    required this.bedId,
    required this.bedNumber,
    required this.bedLabel,
  });

  final String admissionId;
  final String hospitalId;
  final String patientId;

  final String patientName;
  final String? patientNumber;

  final String? admissionNumber;
  final String admissionType;
  final String status;

  final DateTime? admittedAt;
  final DateTime? expectedDischargeAt;
  final DateTime? dischargedAt;

  final String? wardId;
  final String? wardName;

  final String? roomId;
  final String? roomNumber;
  final String? roomName;

  final String? bedId;
  final String? bedNumber;
  final String? bedLabel;

  String get displayAdmissionNumber {
    final number = admissionNumber?.trim();

    if (number != null && number.isNotEmpty) {
      return number;
    }

    if (admissionId.length >= 8) {
      return 'ADM-${admissionId.substring(0, 8).toUpperCase()}';
    }

    return admissionId;
  }

  String get displayLocation {
    final values = <String>[
      if (wardName != null && wardName!.trim().isNotEmpty) wardName!,
      if (roomNumber != null && roomNumber!.trim().isNotEmpty)
        'Room $roomNumber',
      if (bedLabel != null && bedLabel!.trim().isNotEmpty)
        bedLabel!
      else if (bedNumber != null && bedNumber!.trim().isNotEmpty)
        'Bed $bedNumber',
    ];

    if (values.isEmpty) {
      return 'No bed assigned';
    }

    return values.join(
      ' • ',
    );
  }
}

// =============================================================================
// BED OPTION
// =============================================================================

class TransferBedOption {
  const TransferBedOption({
    required this.bedId,
    required this.hospitalId,
    required this.wardId,
    required this.wardName,
    required this.roomId,
    required this.roomNumber,
    required this.roomName,
    required this.bedNumber,
    required this.bedLabel,
    required this.bedType,
    required this.status,
  });

  final String bedId;
  final String hospitalId;

  final String? wardId;
  final String? wardName;

  final String? roomId;
  final String? roomNumber;
  final String? roomName;

  final String? bedNumber;
  final String? bedLabel;
  final String? bedType;

  final String status;

  String get displayLocation {
    final values = <String>[
      if (wardName != null && wardName!.trim().isNotEmpty) wardName!,
      if (roomNumber != null && roomNumber!.trim().isNotEmpty)
        'Room $roomNumber',
      if (bedLabel != null && bedLabel!.trim().isNotEmpty)
        bedLabel!
      else if (bedNumber != null && bedNumber!.trim().isNotEmpty)
        'Bed $bedNumber',
    ];

    if (values.isEmpty) {
      return 'Unknown bed';
    }

    return values.join(
      ' • ',
    );
  }
}

// =============================================================================
// TRANSFER RECORD
// =============================================================================

class InterhospitalTransferRecord {
  const InterhospitalTransferRecord({
    required this.transferId,
    required this.transferNumber,
    required this.patientId,
    required this.patientName,
    required this.patientNumber,
    required this.sourceHospitalId,
    required this.sourceHospitalName,
    required this.destinationHospitalId,
    required this.destinationHospitalName,
    required this.sourceAdmissionId,
    required this.destinationAdmissionId,
    required this.destinationWardId,
    required this.destinationWardName,
    required this.destinationRoomId,
    required this.destinationRoomNumber,
    required this.destinationRoomName,
    required this.destinationBedId,
    required this.destinationBedNumber,
    required this.destinationBedLabel,
    required this.status,
    required this.priority,
    required this.transferReason,
    required this.clinicalSummary,
    required this.handoverSummary,
    required this.medicationSummary,
    required this.equipmentSummary,
    required this.patientSnapshot,
    required this.transportMethod,
    required this.transportProvider,
    required this.transportReference,
    required this.transportContact,
    required this.escortRequired,
    required this.escortNotes,
    required this.estimatedDepartureAt,
    required this.estimatedArrivalAt,
    required this.actualDepartureAt,
    required this.actualArrivalAt,
    required this.consentConfirmed,
    required this.patientNotified,
    required this.requestedAt,
    required this.acceptedAt,
    required this.rejectedAt,
    required this.rejectionReason,
    required this.preparedAt,
    required this.completedAt,
    required this.cancelledAt,
    required this.cancellationReason,
    required this.destinationNotes,
    required this.notes,
    required this.lastStatusReason,
    required this.createdAt,
    required this.updatedAt,
    required this.documents,
    required this.statusHistory,
  });

  final String transferId;
  final String transferNumber;

  final String patientId;
  final String patientName;
  final String? patientNumber;

  final String sourceHospitalId;
  final String sourceHospitalName;

  final String destinationHospitalId;
  final String destinationHospitalName;

  final String? sourceAdmissionId;
  final String? destinationAdmissionId;

  final String? destinationWardId;
  final String? destinationWardName;

  final String? destinationRoomId;
  final String? destinationRoomNumber;
  final String? destinationRoomName;

  final String? destinationBedId;
  final String? destinationBedNumber;
  final String? destinationBedLabel;

  final String status;
  final String priority;

  final String transferReason;
  final String clinicalSummary;

  final String? handoverSummary;
  final String? medicationSummary;
  final String? equipmentSummary;

  final Map<String, dynamic> patientSnapshot;

  final String? transportMethod;
  final String? transportProvider;
  final String? transportReference;
  final String? transportContact;

  final bool escortRequired;
  final String? escortNotes;

  final DateTime? estimatedDepartureAt;
  final DateTime? estimatedArrivalAt;

  final DateTime? actualDepartureAt;
  final DateTime? actualArrivalAt;

  final bool consentConfirmed;
  final bool patientNotified;

  final DateTime? requestedAt;
  final DateTime? acceptedAt;
  final DateTime? rejectedAt;
  final String? rejectionReason;

  final DateTime? preparedAt;
  final DateTime? completedAt;

  final DateTime? cancelledAt;
  final String? cancellationReason;

  final String? destinationNotes;
  final String? notes;
  final String? lastStatusReason;

  final DateTime? createdAt;
  final DateTime? updatedAt;

  final List<TransferDocumentRecord> documents;

  final List<TransferStatusHistoryRecord> statusHistory;

  bool isOutgoingFor(
    String hospitalId,
  ) {
    return sourceHospitalId == hospitalId;
  }

  bool isIncomingFor(
    String hospitalId,
  ) {
    return destinationHospitalId == hospitalId;
  }

  bool get isTerminal {
    return {
      'completed',
      'rejected',
      'cancelled',
    }.contains(
      status,
    );
  }

  bool get isActive => !isTerminal;

  bool canAcceptFor(
    String hospitalId,
  ) {
    return isIncomingFor(
          hospitalId,
        ) &&
        status == 'requested';
  }

  bool canRejectFor(
    String hospitalId,
  ) {
    return isIncomingFor(
          hospitalId,
        ) &&
        status == 'requested';
  }

  bool canUpdateTransportFor(
    String hospitalId,
  ) {
    return isOutgoingFor(
          hospitalId,
        ) &&
        {
          'requested',
          'accepted',
          'ready_for_transfer',
        }.contains(
          status,
        );
  }

  bool canPrepareFor(
    String hospitalId,
  ) {
    return isOutgoingFor(
          hospitalId,
        ) &&
        status == 'accepted';
  }

  bool canDispatchFor(
    String hospitalId,
  ) {
    return isOutgoingFor(
          hospitalId,
        ) &&
        status == 'ready_for_transfer';
  }

  bool canReceiveFor(
    String hospitalId,
  ) {
    return isIncomingFor(
          hospitalId,
        ) &&
        status == 'in_transit';
  }

  bool canCompleteFor(
    String hospitalId,
  ) {
    return isIncomingFor(
          hospitalId,
        ) &&
        status == 'received';
  }

  bool canCancelFor(
    String hospitalId,
  ) {
    final belongsToHospital = isOutgoingFor(
          hospitalId,
        ) ||
        isIncomingFor(
          hospitalId,
        );

    return belongsToHospital &&
        !{
          'completed',
          'rejected',
          'cancelled',
          'in_transit',
        }.contains(
          status,
        );
  }

  String get destinationLocation {
    final values = <String>[
      if (destinationWardName != null && destinationWardName!.trim().isNotEmpty)
        destinationWardName!,
      if (destinationRoomNumber != null &&
          destinationRoomNumber!.trim().isNotEmpty)
        'Room $destinationRoomNumber',
      if (destinationBedLabel != null && destinationBedLabel!.trim().isNotEmpty)
        destinationBedLabel!
      else if (destinationBedNumber != null &&
          destinationBedNumber!.trim().isNotEmpty)
        'Bed $destinationBedNumber',
    ];

    if (values.isEmpty) {
      return 'Destination bed not allocated';
    }

    return values.join(
      ' • ',
    );
  }

  String get searchText {
    return [
      transferNumber,
      patientName,
      patientNumber,
      sourceHospitalName,
      destinationHospitalName,
      status,
      priority,
      transferReason,
      clinicalSummary,
      handoverSummary,
      transportMethod,
      transportProvider,
      transportReference,
      destinationWardName,
      destinationRoomName,
      destinationRoomNumber,
      destinationBedLabel,
      destinationBedNumber,
    ]
        .whereType<String>()
        .join(
          ' ',
        )
        .toLowerCase();
  }
}

// =============================================================================
// DOCUMENT RECORD
// =============================================================================

class TransferDocumentRecord {
  const TransferDocumentRecord({
    required this.documentId,
    required this.transferId,
    required this.hospitalId,
    required this.documentType,
    required this.fileName,
    required this.storageBucket,
    required this.storagePath,
    required this.mimeType,
    required this.fileSizeBytes,
    required this.checksumSha256,
    required this.description,
    required this.isClinical,
    required this.sharedWithDestination,
    required this.isActive,
    required this.deactivationReason,
    required this.createdAt,
  });

  final String documentId;
  final String transferId;
  final String hospitalId;

  final String documentType;
  final String fileName;

  final String storageBucket;
  final String storagePath;

  final String? mimeType;
  final int? fileSizeBytes;
  final String? checksumSha256;
  final String? description;

  final bool isClinical;
  final bool sharedWithDestination;
  final bool isActive;

  final String? deactivationReason;
  final DateTime? createdAt;

  factory TransferDocumentRecord.fromMap(
    Map<String, dynamic> map,
  ) {
    return TransferDocumentRecord(
      documentId: map['id']?.toString() ?? '',
      transferId: map['transfer_id']?.toString() ?? '',
      hospitalId: map['hospital_id']?.toString() ?? '',
      documentType: map['document_type']?.toString() ?? 'other',
      fileName: map['file_name']?.toString() ?? 'Document',
      storageBucket: map['storage_bucket']?.toString() ??
          InterhospitalTransferService.defaultDocumentBucket,
      storagePath: map['storage_path']?.toString() ?? '',
      mimeType: map['mime_type']?.toString(),
      fileSizeBytes: map['file_size_bytes'] is num
          ? (map['file_size_bytes'] as num).toInt()
          : int.tryParse(
              map['file_size_bytes']?.toString() ?? '',
            ),
      checksumSha256: map['checksum_sha256']?.toString(),
      description: map['description']?.toString(),
      isClinical: map['is_clinical'] != false,
      sharedWithDestination: map['shared_with_destination'] != false,
      isActive: map['is_active'] != false,
      deactivationReason: map['deactivation_reason']?.toString(),
      createdAt: DateTime.tryParse(
        map['created_at']?.toString() ?? '',
      )?.toLocal(),
    );
  }

  String get displaySize {
    final bytes = fileSizeBytes;

    if (bytes == null) {
      return 'Unknown size';
    }

    if (bytes < 1024) {
      return '$bytes B';
    }

    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }

    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

// =============================================================================
// STATUS HISTORY
// =============================================================================

class TransferStatusHistoryRecord {
  const TransferStatusHistoryRecord({
    required this.historyId,
    required this.transferId,
    required this.sourceHospitalId,
    required this.destinationHospitalId,
    required this.previousStatus,
    required this.newStatus,
    required this.reason,
    required this.details,
    required this.changedBy,
    required this.changedAt,
  });

  final String historyId;
  final String transferId;

  final String? sourceHospitalId;
  final String? destinationHospitalId;

  final String? previousStatus;
  final String newStatus;
  final String? reason;

  final Map<String, dynamic> details;

  final String? changedBy;
  final DateTime? changedAt;

  factory TransferStatusHistoryRecord.fromMap(
    Map<String, dynamic> map,
  ) {
    final detailsValue = map['details'];

    return TransferStatusHistoryRecord(
      historyId: map['id']?.toString() ?? '',
      transferId: map['transfer_id']?.toString() ?? '',
      sourceHospitalId: map['source_hospital_id']?.toString(),
      destinationHospitalId: map['destination_hospital_id']?.toString(),
      previousStatus: map['previous_status']?.toString(),
      newStatus: map['new_status']?.toString() ?? 'unknown',
      reason: map['reason']?.toString(),
      details: detailsValue is Map
          ? Map<String, dynamic>.from(
              detailsValue,
            )
          : {},
      changedBy: map['changed_by']?.toString(),
      changedAt: DateTime.tryParse(
        map['changed_at']?.toString() ?? '',
      )?.toLocal(),
    );
  }
}

// =============================================================================
// DASHBOARD STATS
// =============================================================================

class InterhospitalTransferDashboardStats {
  const InterhospitalTransferDashboardStats({
    required this.hospitalId,
    required this.outgoingTotal,
    required this.incomingTotal,
    required this.outgoingRequested,
    required this.incomingRequested,
    required this.accepted,
    required this.readyForTransfer,
    required this.inTransit,
    required this.received,
    required this.completed,
    required this.rejected,
    required this.cancelled,
    required this.urgentActive,
    required this.todayDepartures,
    required this.todayArrivals,
    required this.generatedAt,
  });

  final String hospitalId;

  final int outgoingTotal;
  final int incomingTotal;

  final int outgoingRequested;
  final int incomingRequested;

  final int accepted;
  final int readyForTransfer;
  final int inTransit;
  final int received;

  final int completed;
  final int rejected;
  final int cancelled;

  final int urgentActive;

  final int todayDepartures;
  final int todayArrivals;

  final DateTime? generatedAt;

  factory InterhospitalTransferDashboardStats.empty(
    String hospitalId,
  ) {
    return InterhospitalTransferDashboardStats(
      hospitalId: hospitalId,
      outgoingTotal: 0,
      incomingTotal: 0,
      outgoingRequested: 0,
      incomingRequested: 0,
      accepted: 0,
      readyForTransfer: 0,
      inTransit: 0,
      received: 0,
      completed: 0,
      rejected: 0,
      cancelled: 0,
      urgentActive: 0,
      todayDepartures: 0,
      todayArrivals: 0,
      generatedAt: DateTime.now(),
    );
  }

  factory InterhospitalTransferDashboardStats.fromMap(
    Map<String, dynamic> map,
  ) {
    int read(String key) {
      final value = map[key];

      if (value is num) {
        return value.toInt();
      }

      return int.tryParse(
            value?.toString() ?? '',
          ) ??
          0;
    }

    return InterhospitalTransferDashboardStats(
      hospitalId: map['hospital_id']?.toString() ?? '',
      outgoingTotal: read(
        'outgoing_total',
      ),
      incomingTotal: read(
        'incoming_total',
      ),
      outgoingRequested: read(
        'outgoing_requested',
      ),
      incomingRequested: read(
        'incoming_requested',
      ),
      accepted: read(
        'accepted',
      ),
      readyForTransfer: read(
        'ready_for_transfer',
      ),
      inTransit: read(
        'in_transit',
      ),
      received: read(
        'received',
      ),
      completed: read(
        'completed',
      ),
      rejected: read(
        'rejected',
      ),
      cancelled: read(
        'cancelled',
      ),
      urgentActive: read(
        'urgent_active',
      ),
      todayDepartures: read(
        'today_departures',
      ),
      todayArrivals: read(
        'today_arrivals',
      ),
      generatedAt: DateTime.tryParse(
        map['generated_at']?.toString() ?? '',
      )?.toLocal(),
    );
  }
}

// =============================================================================
// RPC RESULT
// =============================================================================

class TransferActionResult {
  const TransferActionResult({
    required this.success,
    required this.transferId,
    required this.transferNumber,
    required this.status,
    required this.message,
    required this.destinationAdmissionId,
    required this.rawData,
  });

  final bool success;

  final String? transferId;
  final String? transferNumber;
  final String? status;
  final String? message;

  final String? destinationAdmissionId;

  final Map<String, dynamic> rawData;

  factory TransferActionResult.fromMap(
    Map<String, dynamic> map,
  ) {
    final successValue = map['success'];

    final success = successValue is bool
        ? successValue
        : successValue?.toString().toLowerCase() == 'true';

    return TransferActionResult(
      success: success,
      transferId: map['transfer_id']?.toString(),
      transferNumber: map['transfer_number']?.toString(),
      status: map['status']?.toString(),
      message: map['message']?.toString() ?? map['reason']?.toString(),
      destinationAdmissionId: map['destination_admission_id']?.toString(),
      rawData: map,
    );
  }
}

// =============================================================================
// WORKSPACE
// =============================================================================

class InterhospitalTransferWorkspace {
  const InterhospitalTransferWorkspace({
    required this.hospitalId,
    required this.stats,
    required this.transfers,
    required this.patients,
    required this.admissions,
    required this.destinationHospitals,
  });

  final String hospitalId;

  final InterhospitalTransferDashboardStats stats;

  final List<InterhospitalTransferRecord> transfers;

  final List<TransferPatientOption> patients;

  final List<TransferAdmissionOption> admissions;

  final List<TransferHospitalOption> destinationHospitals;

  List<InterhospitalTransferRecord> get outgoingTransfers {
    return transfers
        .where(
          (transfer) => transfer.isOutgoingFor(
            hospitalId,
          ),
        )
        .toList();
  }

  List<InterhospitalTransferRecord> get incomingTransfers {
    return transfers
        .where(
          (transfer) => transfer.isIncomingFor(
            hospitalId,
          ),
        )
        .toList();
  }

  List<InterhospitalTransferRecord> get urgentTransfers {
    return transfers.where(
      (transfer) {
        return transfer.isActive &&
            {
              'urgent',
              'emergency',
              'critical',
            }.contains(
              transfer.priority,
            );
      },
    ).toList();
  }

  List<InterhospitalTransferRecord> get incomingRequests {
    return incomingTransfers
        .where(
          (transfer) => transfer.status == 'requested',
        )
        .toList();
  }

  List<InterhospitalTransferRecord> get patientsInTransit {
    return transfers
        .where(
          (transfer) => transfer.status == 'in_transit',
        )
        .toList();
  }
}
