import 'package:supabase_flutter/supabase_flutter.dart';

class HospitalStructureService {
  HospitalStructureService({
    SupabaseClient? supabase,
  }) : _supabase = supabase ?? Supabase.instance.client;

  final SupabaseClient _supabase;

  String? _cachedProfileId;

  Future<String> currentProfileId() async {
    if (_cachedProfileId != null) {
      return _cachedProfileId!;
    }

    final user = _supabase.auth.currentUser;

    if (user == null) {
      throw Exception('You are not signed in.');
    }

    final profile = await _supabase
        .from('profiles')
        .select('id')
        .eq('user_id', user.id)
        .maybeSingle();

    final profileId = profile?['id']?.toString();

    if (profileId != null && profileId.trim().isNotEmpty) {
      _cachedProfileId = profileId;
      return profileId;
    }

    final fallbackProfile = await _supabase
        .from('profiles')
        .select('id')
        .eq('id', user.id)
        .maybeSingle();

    final fallbackId = fallbackProfile?['id']?.toString();

    if (fallbackId == null || fallbackId.trim().isEmpty) {
      throw Exception('No Corvia profile was found for this account.');
    }

    _cachedProfileId = fallbackId;
    return fallbackId;
  }

  List<Map<String, dynamic>> _mapList(dynamic data) {
    if (data is! List) {
      return [];
    }

    return data
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  String? _nullableText(String? value) {
    final cleaned = value?.trim();

    if (cleaned == null || cleaned.isEmpty) {
      return null;
    }

    return cleaned;
  }

  DateTime? _dateTime(dynamic value) {
    final text = value?.toString();
    if (text == null || text.isEmpty) return null;
    return DateTime.tryParse(text)?.toLocal();
  }

  String? _normaliseTime(String? value) {
    final cleaned = value?.trim();

    if (cleaned == null || cleaned.isEmpty) {
      return null;
    }

    if (RegExp(r'^\d{2}:\d{2}$').hasMatch(cleaned)) {
      return '$cleaned:00';
    }

    if (RegExp(r'^\d{2}:\d{2}:\d{2}$').hasMatch(cleaned)) {
      return cleaned;
    }

    throw Exception('Time must use the HH:mm format, for example 15:00.');
  }

  Future<List<Map<String, dynamic>>> getAdminHospitals() async {
    final profileId = await currentProfileId();

    final data = await _supabase
        .from('hospital_admins')
        .select(
          'hospital_id, role, hospitals('
          'id, name, code, address, city, province, country, '
          'logo_url, is_active'
          ')',
        )
        .eq('profile_id', profileId);

    final links = _mapList(data);
    final hospitals = <Map<String, dynamic>>[];

    for (final link in links) {
      final joinedHospital = link['hospitals'];

      if (joinedHospital is! Map) {
        continue;
      }

      final hospital = Map<String, dynamic>.from(joinedHospital);

      final hospitalId =
          hospital['id']?.toString() ?? link['hospital_id']?.toString();

      if (hospitalId == null || hospitalId.trim().isEmpty) {
        continue;
      }

      hospitals.add({
        ...hospital,
        'id': hospitalId,
        'admin_role': link['role']?.toString() ?? 'hospital_admin',
      });
    }

    hospitals.sort(
      (a, b) => (a['name']?.toString() ?? '').toLowerCase().compareTo(
            (b['name']?.toString() ?? '').toLowerCase(),
          ),
    );

    return hospitals;
  }

  Future<List<Map<String, dynamic>>> getBuildings(
    String hospitalId,
  ) async {
    final data = await _supabase
        .from('hospital_buildings')
        .select()
        .eq('hospital_id', hospitalId)
        .order('name');

    return _mapList(data);
  }

  Future<List<Map<String, dynamic>>> getFloors(
    String hospitalId,
  ) async {
    final data = await _supabase
        .from('hospital_floors')
        .select()
        .eq('hospital_id', hospitalId)
        .order('floor_number')
        .order('name');

    return _mapList(data);
  }

  Future<List<Map<String, dynamic>>> getWards(
    String hospitalId,
  ) async {
    final data = await _supabase
        .from('hospital_wards')
        .select()
        .eq('hospital_id', hospitalId)
        .order('name');

    return _mapList(data);
  }

  Future<List<Map<String, dynamic>>> getWardVisitorRules(
    String hospitalId,
  ) async {
    final data = await _supabase
        .from('ward_visitor_rules')
        .select()
        .eq('hospital_id', hospitalId);

    return _mapList(data);
  }

  Future<List<Map<String, dynamic>>> getRooms(
    String hospitalId,
  ) async {
    final data = await _supabase
        .from('hospital_rooms')
        .select()
        .eq('hospital_id', hospitalId)
        .order('room_number');

    return _mapList(data);
  }

  Future<List<Map<String, dynamic>>> getBeds(
    String hospitalId,
  ) async {
    final data = await _supabase
        .from('hospital_beds')
        .select()
        .eq('hospital_id', hospitalId)
        .order('bed_number');

    return _mapList(data);
  }

  Future<HospitalStructureSnapshot> loadSnapshot(
    String hospitalId,
  ) async {
    final results = await Future.wait([
      getBuildings(hospitalId),
      getFloors(hospitalId),
      getWards(hospitalId),
      getWardVisitorRules(hospitalId),
      getRooms(hospitalId),
      getBeds(hospitalId),
    ]);

    return HospitalStructureSnapshot(
      buildings: results[0],
      floors: results[1],
      wards: results[2],
      visitorRules: results[3],
      rooms: results[4],
      beds: results[5],
    );
  }

  Future<Map<String, dynamic>> addBuilding({
    required String hospitalId,
    required String name,
    String? code,
    String? description,
    String? addressNote,
    String? receptionLocation,
  }) async {
    final profileId = await currentProfileId();

    final data = await _supabase
        .from('hospital_buildings')
        .insert({
          'hospital_id': hospitalId,
          'name': name.trim(),
          'code': _nullableText(code),
          'description': _nullableText(description),
          'address_note': _nullableText(addressNote),
          'reception_location': _nullableText(receptionLocation),
          'created_by': profileId,
          'updated_by': profileId,
        })
        .select()
        .single();

    return Map<String, dynamic>.from(data);
  }

  Future<Map<String, dynamic>> updateBuilding({
    required String hospitalId,
    required String buildingId,
    required String name,
    String? code,
    String? description,
    String? addressNote,
    String? receptionLocation,
  }) async {
    final profileId = await currentProfileId();

    final data = await _supabase
        .from('hospital_buildings')
        .update({
          'name': name.trim(),
          'code': _nullableText(code),
          'description': _nullableText(description),
          'address_note': _nullableText(addressNote),
          'reception_location': _nullableText(receptionLocation),
          'updated_by': profileId,
        })
        .eq('id', buildingId)
        .eq('hospital_id', hospitalId)
        .select()
        .single();

    return Map<String, dynamic>.from(data);
  }

  Future<Map<String, dynamic>> addFloor({
    required String hospitalId,
    required String buildingId,
    required String name,
    int? floorNumber,
    String? code,
    String? description,
  }) async {
    final profileId = await currentProfileId();

    final data = await _supabase
        .from('hospital_floors')
        .insert({
          'hospital_id': hospitalId,
          'building_id': buildingId,
          'name': name.trim(),
          'floor_number': floorNumber,
          'code': _nullableText(code),
          'description': _nullableText(description),
          'created_by': profileId,
          'updated_by': profileId,
        })
        .select()
        .single();

    return Map<String, dynamic>.from(data);
  }

  Future<Map<String, dynamic>> updateFloor({
    required String hospitalId,
    required String floorId,
    required String buildingId,
    required String name,
    int? floorNumber,
    String? code,
    String? description,
  }) async {
    final profileId = await currentProfileId();

    final data = await _supabase
        .from('hospital_floors')
        .update({
          'building_id': buildingId,
          'name': name.trim(),
          'floor_number': floorNumber,
          'code': _nullableText(code),
          'description': _nullableText(description),
          'updated_by': profileId,
        })
        .eq('id', floorId)
        .eq('hospital_id', hospitalId)
        .select()
        .single();

    return Map<String, dynamic>.from(data);
  }

  Future<Map<String, dynamic>> addWard({
    required String hospitalId,
    required String buildingId,
    required String floorId,
    required String name,
    required String wardType,
    required String visitorMode,
    required int maximumVisitors,
    required bool requiresStaffApproval,
    required bool showRoomNumber,
    required bool showBedLabel,
    String? code,
    String? description,
    String? phoneExtension,
    String? nurseStationLocation,
    String? visitingStart,
    String? visitingEnd,
    String? visitorInstructions,
  }) async {
    final profileId = await currentProfileId();

    final data = await _supabase
        .from('hospital_wards')
        .insert({
          'hospital_id': hospitalId,
          'building_id': buildingId,
          'floor_id': floorId,
          'name': name.trim(),
          'code': _nullableText(code),
          'ward_type': wardType,
          'description': _nullableText(description),
          'phone_extension': _nullableText(phoneExtension),
          'nurse_station_location': _nullableText(nurseStationLocation),
          'created_by': profileId,
          'updated_by': profileId,
        })
        .select()
        .single();

    final ward = Map<String, dynamic>.from(data);
    final wardId = ward['id']?.toString();

    if (wardId == null || wardId.isEmpty) {
      throw Exception('Ward was created without a valid ID.');
    }

    await upsertWardVisitorRule(
      hospitalId: hospitalId,
      wardId: wardId,
      visitorMode: visitorMode,
      maximumVisitors: maximumVisitors,
      requiresStaffApproval: requiresStaffApproval,
      showRoomNumber: showRoomNumber,
      showBedLabel: showBedLabel,
      visitingStart: visitingStart,
      visitingEnd: visitingEnd,
      specialInstructions: visitorInstructions,
    );

    return ward;
  }

  Future<Map<String, dynamic>> updateWard({
    required String hospitalId,
    required String wardId,
    required String buildingId,
    required String floorId,
    required String name,
    required String wardType,
    required String visitorMode,
    required int maximumVisitors,
    required bool requiresStaffApproval,
    required bool showRoomNumber,
    required bool showBedLabel,
    String? code,
    String? description,
    String? phoneExtension,
    String? nurseStationLocation,
    String? visitingStart,
    String? visitingEnd,
    String? visitorInstructions,
  }) async {
    final profileId = await currentProfileId();

    final data = await _supabase
        .from('hospital_wards')
        .update({
          'building_id': buildingId,
          'floor_id': floorId,
          'name': name.trim(),
          'code': _nullableText(code),
          'ward_type': wardType,
          'description': _nullableText(description),
          'phone_extension': _nullableText(phoneExtension),
          'nurse_station_location': _nullableText(nurseStationLocation),
          'updated_by': profileId,
        })
        .eq('id', wardId)
        .eq('hospital_id', hospitalId)
        .select()
        .single();

    await upsertWardVisitorRule(
      hospitalId: hospitalId,
      wardId: wardId,
      visitorMode: visitorMode,
      maximumVisitors: maximumVisitors,
      requiresStaffApproval: requiresStaffApproval,
      showRoomNumber: showRoomNumber,
      showBedLabel: showBedLabel,
      visitingStart: visitingStart,
      visitingEnd: visitingEnd,
      specialInstructions: visitorInstructions,
    );

    return Map<String, dynamic>.from(data);
  }

  Future<void> upsertWardVisitorRule({
    required String hospitalId,
    required String wardId,
    required String visitorMode,
    required int maximumVisitors,
    required bool requiresStaffApproval,
    required bool showRoomNumber,
    required bool showBedLabel,
    String? visitingStart,
    String? visitingEnd,
    String? specialInstructions,
  }) async {
    final profileId = await currentProfileId();

    await _supabase.from('ward_visitor_rules').upsert(
      {
        'hospital_id': hospitalId,
        'ward_id': wardId,
        'visitor_mode': visitorMode,
        'visiting_start': _normaliseTime(visitingStart),
        'visiting_end': _normaliseTime(visitingEnd),
        'maximum_visitors': maximumVisitors,
        'requires_check_in': true,
        'requires_id_verification': true,
        'requires_staff_approval': requiresStaffApproval,
        'show_room_number': showRoomNumber,
        'show_bed_label': showBedLabel,
        'special_instructions': _nullableText(specialInstructions),
        'is_active': true,
        'created_by': profileId,
        'updated_by': profileId,
      },
      onConflict: 'ward_id',
    );
  }

  Future<Map<String, dynamic>> addRoom({
    required String hospitalId,
    required String wardId,
    required String roomNumber,
    required String roomType,
    required int capacity,
    required String genderPolicy,
    required bool isIsolation,
    required bool visitorAccessAllowed,
    String? roomName,
    String? notes,
  }) async {
    final profileId = await currentProfileId();

    final data = await _supabase
        .from('hospital_rooms')
        .insert({
          'hospital_id': hospitalId,
          'ward_id': wardId,
          'room_number': roomNumber.trim(),
          'room_name': _nullableText(roomName),
          'room_type': roomType,
          'capacity': capacity,
          'gender_policy': genderPolicy,
          'is_isolation': isIsolation,
          'visitor_access_allowed': visitorAccessAllowed,
          'notes': _nullableText(notes),
          'created_by': profileId,
          'updated_by': profileId,
        })
        .select()
        .single();

    return Map<String, dynamic>.from(data);
  }

  Future<Map<String, dynamic>> updateRoom({
    required String hospitalId,
    required String roomId,
    required String wardId,
    required String roomNumber,
    required String roomType,
    required int capacity,
    required String genderPolicy,
    required bool isIsolation,
    required bool visitorAccessAllowed,
    String? roomName,
    String? notes,
  }) async {
    final profileId = await currentProfileId();

    final data = await _supabase
        .from('hospital_rooms')
        .update({
          'ward_id': wardId,
          'room_number': roomNumber.trim(),
          'room_name': _nullableText(roomName),
          'room_type': roomType,
          'capacity': capacity,
          'gender_policy': genderPolicy,
          'is_isolation': isIsolation,
          'visitor_access_allowed': visitorAccessAllowed,
          'notes': _nullableText(notes),
          'updated_by': profileId,
        })
        .eq('id', roomId)
        .eq('hospital_id', hospitalId)
        .select()
        .single();

    return Map<String, dynamic>.from(data);
  }

  Future<Map<String, dynamic>> addBed({
    required String hospitalId,
    required String wardId,
    required String roomId,
    required String bedNumber,
    required String bedType,
    String? bedLabel,
    String? notes,
  }) async {
    final profileId = await currentProfileId();

    final data = await _supabase
        .from('hospital_beds')
        .insert({
          'hospital_id': hospitalId,
          'ward_id': wardId,
          'room_id': roomId,
          'bed_number': bedNumber.trim(),
          'bed_label': _nullableText(bedLabel),
          'bed_type': bedType,
          'status': 'available',
          'notes': _nullableText(notes),
          'created_by': profileId,
          'updated_by': profileId,
        })
        .select()
        .single();

    return Map<String, dynamic>.from(data);
  }

  Future<Map<String, dynamic>> updateBed({
    required String hospitalId,
    required String bedId,
    required String wardId,
    required String roomId,
    required String bedNumber,
    required String bedType,
    String? bedLabel,
    String? notes,
  }) async {
    final profileId = await currentProfileId();

    final data = await _supabase
        .from('hospital_beds')
        .update({
          'ward_id': wardId,
          'room_id': roomId,
          'bed_number': bedNumber.trim(),
          'bed_label': _nullableText(bedLabel),
          'bed_type': bedType,
          'notes': _nullableText(notes),
          'updated_by': profileId,
        })
        .eq('id', bedId)
        .eq('hospital_id', hospitalId)
        .select()
        .single();

    return Map<String, dynamic>.from(data);
  }

  Future<void> setActive({
    required String table,
    required String recordId,
    required String hospitalId,
    required bool active,
  }) async {
    const allowedTables = {
      'hospital_buildings',
      'hospital_floors',
      'hospital_wards',
      'hospital_rooms',
      'hospital_beds',
    };

    if (!allowedTables.contains(table)) {
      throw Exception('Unsupported hospital structure table.');
    }

    final profileId = await currentProfileId();

    await _supabase
        .from(table)
        .update({
          'is_active': active,
          'updated_by': profileId,
        })
        .eq('id', recordId)
        .eq('hospital_id', hospitalId);
  }

  Future<void> updateBedStatus({
    required String hospitalId,
    required String bedId,
    required String newStatus,
    String? reason,
    DateTime? reservedUntil,
    String? sanitationNotes,
  }) async {
    const validStatuses = {
      'available',
      'reserved',
      'cleaning',
      'maintenance',
      'blocked',
    };

    if (!validStatuses.contains(newStatus)) {
      throw Exception('Invalid bed status.');
    }

    try {
      await _supabase.rpc(
        'corvia_mh_set_bed_status',
        params: {
          'p_hospital_id': hospitalId,
          'p_bed_id': bedId,
          'p_new_status': newStatus,
          'p_reason': reason,
          'p_reserved_until': reservedUntil?.toUtc().toIso8601String(),
          'p_sanitation_notes': sanitationNotes,
        },
      );
    } on PostgrestException catch (error) {
      if (error.code == 'PGRST202') {
        throw Exception(
          'Install the Ward & Bed Supabase migration before changing bed status.',
        );
      }
      rethrow;
    }
  }

  Future<List<HospitalBedBoardEntry>> getBedBoard(
    String hospitalId,
  ) async {
    try {
      await _supabase.rpc(
        'corvia_mh_expire_bed_reservations',
        params: {'p_hospital_id': hospitalId},
      );
    } on PostgrestException catch (error) {
      if (error.code == 'PGRST202') {
        throw Exception(
          'Install the Ward & Bed Supabase migration before opening the Live Bed Board.',
        );
      }
      rethrow;
    }

    final snapshot = await loadSnapshot(hospitalId);

    final assignmentData = await _supabase
        .from('patient_bed_assignments')
        .select(
          'id, admission_id, patient_id, ward_id, room_id, bed_id, assigned_at',
        )
        .eq('hospital_id', hospitalId)
        .eq('status', 'active')
        .isFilter('ended_at', null);

    final assignments = _mapList(assignmentData);

    final patientIds = assignments
        .map((row) => row['patient_id']?.toString())
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();

    final admissionIds = assignments
        .map((row) => row['admission_id']?.toString())
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();

    final patients = <Map<String, dynamic>>[];
    final admissions = <Map<String, dynamic>>[];

    if (patientIds.isNotEmpty) {
      final patientData = await _supabase
          .from('patients')
          .select('id, profile_id, patient_number')
          .inFilter('id', patientIds);

      patients.addAll(_mapList(patientData));
    }

    if (admissionIds.isNotEmpty) {
      final admissionData = await _supabase
          .from('hospital_admissions')
          .select('id, admission_number, status, admitted_at')
          .eq('hospital_id', hospitalId)
          .inFilter('id', admissionIds);

      admissions.addAll(_mapList(admissionData));
    }

    final profileIds = patients
        .map((row) => row['profile_id']?.toString())
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();

    final profiles = <Map<String, dynamic>>[];

    if (profileIds.isNotEmpty) {
      final profileData = await _supabase
          .from('profiles')
          .select('id, first_name, surname, email')
          .inFilter('id', profileIds);

      profiles.addAll(_mapList(profileData));
    }

    final buildingById = {
      for (final item in snapshot.buildings) item['id'].toString(): item,
    };

    final floorById = {
      for (final item in snapshot.floors) item['id'].toString(): item,
    };

    final wardById = {
      for (final item in snapshot.wards) item['id'].toString(): item,
    };

    final roomById = {
      for (final item in snapshot.rooms) item['id'].toString(): item,
    };

    final assignmentByBed = <String, Map<String, dynamic>>{
      for (final item in assignments)
        if (item['bed_id'] != null) item['bed_id'].toString(): item,
    };

    final patientById = {
      for (final item in patients) item['id'].toString(): item,
    };

    final profileById = {
      for (final item in profiles) item['id'].toString(): item,
    };

    final admissionById = {
      for (final item in admissions) item['id'].toString(): item,
    };

    final entries = <HospitalBedBoardEntry>[];

    for (final bed in snapshot.beds) {
      final room = roomById[bed['room_id']?.toString()] ?? {};
      final ward = wardById[bed['ward_id']?.toString()] ?? {};
      final floor = floorById[ward['floor_id']?.toString()] ?? {};
      final building = buildingById[ward['building_id']?.toString()] ?? {};

      final assignment = assignmentByBed[bed['id']?.toString()];
      final patient = assignment == null
          ? null
          : patientById[assignment['patient_id']?.toString()];

      final profile = patient == null
          ? null
          : profileById[patient['profile_id']?.toString()];

      final admission = assignment == null
          ? null
          : admissionById[assignment['admission_id']?.toString()];

      final firstName = profile?['first_name']?.toString().trim() ?? '';
      final surname = profile?['surname']?.toString().trim() ?? '';

      final fullName = '$firstName $surname'.trim();

      entries.add(
        HospitalBedBoardEntry(
          hospitalId: hospitalId,
          buildingId: building['id']?.toString(),
          buildingName: building['name']?.toString() ?? 'Unknown Building',
          floorId: floor['id']?.toString(),
          floorName: floor['name']?.toString() ?? 'Unknown Floor',
          wardId: ward['id']?.toString(),
          wardName: ward['name']?.toString() ?? 'Unknown Ward',
          wardType: ward['ward_type']?.toString() ?? 'general',
          roomId: room['id']?.toString(),
          roomNumber: room['room_number']?.toString() ?? '',
          roomName: room['room_name']?.toString(),
          roomType: room['room_type']?.toString() ?? 'general',
          bedId: bed['id']?.toString() ?? '',
          bedNumber: bed['bed_number']?.toString() ?? '',
          bedLabel: bed['bed_label']?.toString(),
          bedType: bed['bed_type']?.toString() ?? 'standard',
          bedStatus: bed['status']?.toString() ?? 'available',
          bedActive: bed['is_active'] != false,
          reservedUntil: _dateTime(bed['reserved_until']),
          cleaningStartedAt: _dateTime(bed['cleaning_started_at']),
          cleanedAt: _dateTime(bed['cleaned_at']),
          sanitationNotes: bed['sanitation_notes']?.toString(),
          maintenanceReason: bed['maintenance_reason']?.toString(),
          evsNotifiedAt: _dateTime(bed['evs_notified_at']),
          assignmentId: assignment?['id']?.toString(),
          admissionId: assignment?['admission_id']?.toString(),
          admissionNumber: admission?['admission_number']?.toString(),
          patientId: patient?['id']?.toString(),
          patientNumber: patient?['patient_number']?.toString(),
          patientName: fullName.isEmpty ? null : fullName,
          assignedAt: assignment?['assigned_at']?.toString(),
        ),
      );
    }

    entries.sort((a, b) {
      final buildingCompare = a.buildingName.toLowerCase().compareTo(
            b.buildingName.toLowerCase(),
          );

      if (buildingCompare != 0) return buildingCompare;

      final floorCompare = a.floorName.toLowerCase().compareTo(
            b.floorName.toLowerCase(),
          );

      if (floorCompare != 0) return floorCompare;

      final wardCompare = a.wardName.toLowerCase().compareTo(
            b.wardName.toLowerCase(),
          );

      if (wardCompare != 0) return wardCompare;

      final roomCompare = a.roomNumber.toLowerCase().compareTo(
            b.roomNumber.toLowerCase(),
          );

      if (roomCompare != 0) return roomCompare;

      return a.bedNumber.toLowerCase().compareTo(
            b.bedNumber.toLowerCase(),
          );
    });

    return entries;
  }
}

class HospitalStructureSnapshot {
  const HospitalStructureSnapshot({
    required this.buildings,
    required this.floors,
    required this.wards,
    required this.visitorRules,
    required this.rooms,
    required this.beds,
  });

  final List<Map<String, dynamic>> buildings;
  final List<Map<String, dynamic>> floors;
  final List<Map<String, dynamic>> wards;
  final List<Map<String, dynamic>> visitorRules;
  final List<Map<String, dynamic>> rooms;
  final List<Map<String, dynamic>> beds;
}

class HospitalBedBoardEntry {
  const HospitalBedBoardEntry({
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
    required this.bedActive,
    required this.reservedUntil,
    required this.cleaningStartedAt,
    required this.cleanedAt,
    required this.sanitationNotes,
    required this.maintenanceReason,
    required this.evsNotifiedAt,
    required this.assignmentId,
    required this.admissionId,
    required this.admissionNumber,
    required this.patientId,
    required this.patientNumber,
    required this.patientName,
    required this.assignedAt,
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
  final bool bedActive;
  final DateTime? reservedUntil;
  final DateTime? cleaningStartedAt;
  final DateTime? cleanedAt;
  final String? sanitationNotes;
  final String? maintenanceReason;
  final DateTime? evsNotifiedAt;

  final String? assignmentId;
  final String? admissionId;
  final String? admissionNumber;

  final String? patientId;
  final String? patientNumber;
  final String? patientName;

  final String? assignedAt;

  bool get isOccupied {
    return assignmentId != null || bedStatus == 'occupied';
  }

  String get displayBedName {
    final label = bedLabel?.trim();

    if (label != null && label.isNotEmpty) {
      return label;
    }

    return 'Bed $bedNumber';
  }

  String get displayRoomName {
    final name = roomName?.trim();

    if (name != null && name.isNotEmpty) {
      return '$name • Room $roomNumber';
    }

    return 'Room $roomNumber';
  }
}
