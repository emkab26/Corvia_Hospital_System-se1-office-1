import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ============================================================================
// RECEPTION HOSPITAL CONTEXT
// ============================================================================

class ReceptionHospitalContext {
  const ReceptionHospitalContext({
    required this.signedIn,
    required this.profileFound,
    required this.profileId,
    required this.role,
    required this.hospitalFound,
    required this.hospitalId,
    required this.hospitalName,
  });

  final bool signedIn;
  final bool profileFound;

  final String profileId;
  final String role;

  final bool hospitalFound;

  final String hospitalId;
  final String hospitalName;

  factory ReceptionHospitalContext.fromJson(
    Map<String, dynamic> json,
  ) {
    return ReceptionHospitalContext(
      signedIn: _boolValue(
        json['signed_in'],
      ),
      profileFound: _boolValue(
        json['profile_found'],
      ),
      profileId: json['profile_id']?.toString().trim() ?? '',
      role: json['role']?.toString().trim() ?? '',
      hospitalFound: _boolValue(
        json['hospital_found'],
      ),
      hospitalId: json['hospital_id']?.toString().trim() ?? '',
      hospitalName:
          json['hospital_name']?.toString().trim().isNotEmpty == true
              ? json['hospital_name'].toString().trim()
              : 'Corvia Medical Hospital',
    );
  }
}

// ============================================================================
// DASHBOARD
// ============================================================================

class ReceptionDashboardData {
  const ReceptionDashboardData({
    required this.hospitalId,
    required this.hospitalName,
    required this.checkInsToday,
    required this.patientsWaiting,
    required this.urgentPatients,
    required this.walkInsToday,
    required this.appointmentsToday,
    required this.queuePreview,
  });

  final String hospitalId;
  final String hospitalName;

  final int checkInsToday;
  final int patientsWaiting;
  final int urgentPatients;
  final int walkInsToday;
  final int appointmentsToday;

  final List<ReceptionQueueItem> queuePreview;

  factory ReceptionDashboardData.fromJson(
    Map<String, dynamic> json,
  ) {
    return ReceptionDashboardData(
      hospitalId: (json['hospitalId'] ?? json['hospital_id'] ?? '').toString(),
      hospitalName: (
        json['hospitalName'] ??
            json['hospital_name'] ??
            'Corvia Medical Hospital'
      ).toString(),
      checkInsToday: _intValue(
        json['checkInsToday'] ?? json['check_ins_today'],
      ),
      patientsWaiting: _intValue(
        json['patientsWaiting'] ?? json['patients_waiting'],
      ),
      urgentPatients: _intValue(
        json['urgentPatients'] ?? json['urgent_patients'],
      ),
      walkInsToday: _intValue(
        json['walkInsToday'] ?? json['walk_ins_today'],
      ),
      appointmentsToday: _intValue(
        json['appointmentsToday'] ?? json['appointments_today'],
      ),
      queuePreview: _queueList(
        json['queuePreview'] ?? json['queue_preview'],
      ),
    );
  }

  ReceptionDashboardData copyWith({
    String? hospitalId,
    String? hospitalName,
  }) {
    return ReceptionDashboardData(
      hospitalId: hospitalId ?? this.hospitalId,
      hospitalName: hospitalName ?? this.hospitalName,
      checkInsToday: checkInsToday,
      patientsWaiting: patientsWaiting,
      urgentPatients: urgentPatients,
      walkInsToday: walkInsToday,
      appointmentsToday: appointmentsToday,
      queuePreview: queuePreview,
    );
  }

  static List<ReceptionQueueItem> _queueList(
    dynamic value,
  ) {
    if (value is! List) {
      return <ReceptionQueueItem>[];
    }

    return value
        .whereType<Map>()
        .map(
          (item) => ReceptionQueueItem.fromJson(
            Map<String, dynamic>.from(
              item,
            ),
          ),
        )
        .toList();
  }
}

// ============================================================================
// QUEUE
// ============================================================================

class ReceptionQueueItem {
  const ReceptionQueueItem({
    required this.id,
    required this.patientName,
    required this.patientNumber,
    required this.doctorName,
    required this.departmentName,
    required this.visitReason,
    required this.queueStatus,
    required this.isUrgent,
    required this.isWalkIn,
    this.checkedInAt,
    this.appointmentTime,
  });

  final String id;

  final String patientName;
  final String patientNumber;

  final String doctorName;
  final String departmentName;

  final String visitReason;
  final String queueStatus;

  final bool isUrgent;
  final bool isWalkIn;

  final DateTime? checkedInAt;
  final DateTime? appointmentTime;

  factory ReceptionQueueItem.fromJson(
    Map<String, dynamic> json,
  ) {
    return ReceptionQueueItem(
      id: (json['id'] ?? '').toString(),
      patientName: (
        json['patientName'] ??
            json['patient_name'] ??
            'Unknown patient'
      ).toString(),
      patientNumber: (
        json['patientNumber'] ??
            json['patient_number'] ??
            'Patient record'
      ).toString(),
      doctorName: (
        json['doctorName'] ??
            json['doctor_name'] ??
            'Unassigned'
      ).toString(),
      departmentName: (
        json['departmentName'] ??
            json['department_name'] ??
            'Unassigned'
      ).toString(),
      visitReason: (
        json['visitReason'] ??
            json['visit_reason'] ??
            'No reason supplied'
      ).toString(),
      queueStatus: (
        json['queueStatus'] ??
            json['queue_status'] ??
            'waiting'
      ).toString(),
      isUrgent: _boolValue(
        json['isUrgent'] ?? json['is_urgent'],
      ),
      isWalkIn: _boolValue(
        json['isWalkIn'] ?? json['is_walk_in'],
      ),
      checkedInAt: _dateValue(
        json['checkedInAt'] ?? json['checked_in_at'],
      ),
      appointmentTime: _dateValue(
        json['appointmentTime'] ?? json['appointment_time'],
      ),
    );
  }
}

// ============================================================================
// PATIENT
// ============================================================================

class ReceptionPatient {
  const ReceptionPatient({
    required this.id,
    required this.patientNumber,
    required this.firstName,
    required this.surname,
    required this.phoneNumber,
    this.dateOfBirth,
  });

  final String id;

  final String patientNumber;

  final String firstName;
  final String surname;

  final String phoneNumber;

  final DateTime? dateOfBirth;

  String get fullName {
    final name = '$firstName $surname'.trim();

    if (name.isEmpty) {
      return 'Unnamed patient';
    }

    return name;
  }

  factory ReceptionPatient.fromJson(
    Map<String, dynamic> json,
  ) {
    return ReceptionPatient(
      id: (
        json['patient_id'] ??
            json['id'] ??
            ''
      ).toString(),
      patientNumber: (
        json['patient_number'] ??
            json['patient_no'] ??
            'No patient number'
      ).toString(),
      firstName: (
        json['first_name'] ??
            ''
      ).toString(),
      surname: (
        json['surname'] ??
            json['last_name'] ??
            ''
      ).toString(),
      phoneNumber: (
        json['phone_number'] ??
            json['phone'] ??
            ''
      ).toString(),
      dateOfBirth: _dateValue(
        json['date_of_birth'],
      ),
    );
  }
}

// ============================================================================
// DEPARTMENT
// ============================================================================

class ReceptionDepartment {
  const ReceptionDepartment({
    required this.id,
    required this.name,
    required this.locationName,
  });

  final String id;
  final String name;
  final String locationName;

  factory ReceptionDepartment.fromJson(
    Map<String, dynamic> json,
  ) {
    return ReceptionDepartment(
      id: (
        json['department_id'] ??
            json['id'] ??
            ''
      ).toString(),
      name: (
        json['department_name'] ??
            json['name'] ??
            'Unnamed department'
      ).toString(),
      locationName: (
        json['location_name'] ??
            json['location'] ??
            ''
      ).toString(),
    );
  }

  @override
  bool operator ==(
    Object other,
  ) {
    return other is ReceptionDepartment && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}

// ============================================================================
// DOCTOR
// ============================================================================

class ReceptionDoctor {
  const ReceptionDoctor({
    required this.id,
    required this.name,
    required this.specialty,
    required this.departmentId,
    required this.status,
    required this.isAvailable,
    required this.slotDurationMinutes,
    required this.workStartMinutes,
    required this.workEndMinutes,
    required this.workingDays,
  });

  final String id;
  final String name;

  final String specialty;
  final String departmentId;

  final String status;

  final bool isAvailable;

  final int slotDurationMinutes;

  final int workStartMinutes;
  final int workEndMinutes;

  final List<int> workingDays;

  String get statusLabel {
    if (!isAvailable) {
      return 'Unavailable';
    }

    final value = status.trim();

    if (value.isEmpty) {
      return 'Available';
    }

    return value
        .replaceAll(
          '_',
          ' ',
        )
        .split(
          RegExp(r'\s+'),
        )
        .where(
          (part) => part.isNotEmpty,
        )
        .map(
          (part) =>
              '${part[0].toUpperCase()}'
              '${part.substring(1).toLowerCase()}',
        )
        .join(' ');
  }

  factory ReceptionDoctor.fromJson(
    Map<String, dynamic> json,
  ) {
    return ReceptionDoctor(
      id: (
        json['doctor_id'] ??
            json['id'] ??
            ''
      ).toString(),
      name: (
        json['doctor_name'] ??
            json['name'] ??
            'Unnamed doctor'
      ).toString(),
      specialty: (
        json['specialty'] ??
            json['specialization'] ??
            ''
      ).toString(),
      departmentId: (
        json['department_id'] ??
            ''
      ).toString(),
      status: (
        json['status'] ??
            'available'
      ).toString(),
      isAvailable: _boolValue(
        json['is_available'],
        fallback: true,
      ),
      slotDurationMinutes: _intValue(
        json['slot_duration_minutes'],
        fallback: 30,
      ),
      workStartMinutes: _timeToMinutes(
        json['work_start'],
        fallback: 8 * 60,
      ),
      workEndMinutes: _timeToMinutes(
        json['work_end'],
        fallback: 17 * 60,
      ),
      workingDays: _workingDays(
        json['working_days'],
      ),
    );
  }

  @override
  bool operator ==(
    Object other,
  ) {
    return other is ReceptionDoctor && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}

// ============================================================================
// BUSY SLOT
// ============================================================================

class ReceptionBusySlot {
  const ReceptionBusySlot({
    required this.appointmentId,
    required this.startTime,
    required this.durationMinutes,
  });

  final String appointmentId;
  final DateTime startTime;
  final int durationMinutes;

  DateTime get endTime {
    return startTime.add(
      Duration(
        minutes: durationMinutes,
      ),
    );
  }

  factory ReceptionBusySlot.fromJson(
    Map<String, dynamic> json,
  ) {
    final rawStart =
        json['start_time'] ??
        json['appointment_time'] ??
        json['scheduled_for'];

    final parsedStart = DateTime.tryParse(
      rawStart?.toString() ?? '',
    );

    if (parsedStart == null) {
      throw const FormatException(
        'Reception busy slot contains an invalid start time.',
      );
    }

    return ReceptionBusySlot(
      appointmentId: (
        json['appointment_id'] ??
            json['id'] ??
            ''
      ).toString(),
      startTime: parsedStart.toLocal(),
      durationMinutes: _intValue(
        json['duration_minutes'],
        fallback: 30,
      ),
    );
  }
}

// ============================================================================
// QR PREVIEW
// ============================================================================

class ReceptionQrPreview {
  const ReceptionQrPreview({
    required this.patientId,
    required this.patientName,
    required this.patientNumber,
    required this.appointmentId,
    required this.doctorName,
    required this.departmentName,
    required this.reason,
    required this.hasAppointment,
    this.appointmentTime,
  });

  final String patientId;

  final String patientName;
  final String patientNumber;

  final String appointmentId;

  final String doctorName;
  final String departmentName;

  final String reason;

  final bool hasAppointment;

  final DateTime? appointmentTime;

  factory ReceptionQrPreview.fromJson(
    Map<String, dynamic> json,
  ) {
    return ReceptionQrPreview(
      patientId: (
        json['patientId'] ??
            json['patient_id'] ??
            ''
      ).toString(),
      patientName: (
        json['patientName'] ??
            json['patient_name'] ??
            'Unknown patient'
      ).toString(),
      patientNumber: (
        json['patientNumber'] ??
            json['patient_number'] ??
            'Patient record'
      ).toString(),
      appointmentId: (
        json['appointmentId'] ??
            json['appointment_id'] ??
            ''
      ).toString(),
      doctorName: (
        json['doctorName'] ??
            json['doctor_name'] ??
            'Unassigned'
      ).toString(),
      departmentName: (
        json['departmentName'] ??
            json['department_name'] ??
            'Unassigned'
      ).toString(),
      reason: (
        json['reason'] ??
            'No reason supplied'
      ).toString(),
      hasAppointment: _boolValue(
        json['hasAppointment'] ?? json['has_appointment'],
      ),
      appointmentTime: _dateValue(
        json['appointmentTime'] ?? json['appointment_time'],
      ),
    );
  }
}

// ============================================================================
// SERVICE
// ============================================================================

class ReceptionService {
  ReceptionService({
    SupabaseClient? client,
  }) : _client =
            client ??
            Supabase.instance.client;

  final SupabaseClient _client;

  // ==========================================================================
  // HOSPITAL CONTEXT
  // ==========================================================================

  Future<ReceptionHospitalContext> resolveHospitalContext() async {
    final response = await _client.rpc(
      'corvia_reception_hospital_context',
    );

    final map = _mapResponse(
      response,
      label: 'Reception hospital context',
    );

    return ReceptionHospitalContext.fromJson(
      map,
    );
  }

  // ==========================================================================
  // DASHBOARD
  // ==========================================================================

  Future<ReceptionDashboardData> loadDashboard() async {
    final results = await Future.wait<dynamic>([
      resolveHospitalContext(),
      _client.rpc(
        'reception_dashboard_snapshot',
      ),
    ]);

    final hospitalContext =
        results[0] as ReceptionHospitalContext;

    final dashboardMap = _mapResponse(
      results[1],
      label: 'Reception dashboard',
    );

    var dashboard = ReceptionDashboardData.fromJson(
      dashboardMap,
    );

    /*
     * If the older dashboard RPC does not return hospital context,
     * use the new database-authoritative Reception context.
     *
     * This is NOT a hardcoded hospital.
     */
    if (dashboard.hospitalId.trim().isEmpty &&
        hospitalContext.hospitalFound) {
      dashboard = dashboard.copyWith(
        hospitalId: hospitalContext.hospitalId,
        hospitalName: hospitalContext.hospitalName,
      );
    }

    return dashboard;
  }

  // ==========================================================================
  // PATIENT SEARCH
  // ==========================================================================

  Future<List<ReceptionPatient>> searchPatients(
    String searchText,
  ) async {
    final search = searchText.trim();

    if (search.length < 2) {
      return <ReceptionPatient>[];
    }

    final response = await _client.rpc(
      'reception_search_patients',
      params: {
        'p_search': search,
      },
    );

    return _mapRows(
      response,
    )
        .map(
          ReceptionPatient.fromJson,
        )
        .where(
          (patient) => patient.id.trim().isNotEmpty,
        )
        .toList();
  }

  // ==========================================================================
  // DEPARTMENTS
  // ==========================================================================

  Future<List<ReceptionDepartment>> loadDepartments() async {
    final context =
        await resolveHospitalContext();

    if (!context.signedIn) {
      throw Exception(
        'Reception session has expired.',
      );
    }

    if (!context.profileFound) {
      throw Exception(
        'Reception profile could not be resolved.',
      );
    }

    if (!context.hospitalFound ||
        context.hospitalId.trim().isEmpty) {
      throw Exception(
        'Reception hospital context could not be resolved. '
        'This reception account must be linked to a hospital.',
      );
    }

    final response = await _client.rpc(
      'corvia_reception_departments',
    );

    final departments = _mapRows(
      response,
    )
        .map(
          ReceptionDepartment.fromJson,
        )
        .where(
          (department) =>
              department.id.trim().isNotEmpty,
        )
        .toList();

    departments.sort(
      (first, second) =>
          first.name.toLowerCase().compareTo(
                second.name.toLowerCase(),
              ),
    );

    return departments;
  }

  // ==========================================================================
  // DOCTORS
  // ==========================================================================

  Future<List<ReceptionDoctor>> loadDoctors(
    String? departmentId,
  ) async {
    final context =
        await resolveHospitalContext();

    if (!context.hospitalFound ||
        context.hospitalId.trim().isEmpty) {
      throw Exception(
        'Reception hospital context could not be resolved. '
        'Doctors cannot be loaded until the reception account '
        'is linked to a hospital.',
      );
    }

    final cleanDepartmentId =
        departmentId?.trim();

    final response = await _client.rpc(
      'corvia_reception_doctors',
      params: {
        'p_department_id':
            cleanDepartmentId == null ||
                    cleanDepartmentId.isEmpty
                ? null
                : cleanDepartmentId,
      },
    );

    final doctors = _mapRows(
      response,
    )
        .map(
          ReceptionDoctor.fromJson,
        )
        .where(
          (doctor) {
            if (doctor.id.trim().isEmpty) {
              return false;
            }

            if (cleanDepartmentId != null &&
                cleanDepartmentId.isNotEmpty &&
                doctor.departmentId != cleanDepartmentId) {
              return false;
            }

            return true;
          },
        )
        .toList();

    doctors.sort(
      (first, second) =>
          first.name.toLowerCase().compareTo(
                second.name.toLowerCase(),
              ),
    );

    return doctors;
  }

  // ==========================================================================
  // DOCTOR BUSY SLOTS
  // ==========================================================================

  Future<List<ReceptionBusySlot>> loadDoctorBusySlots({
    required String doctorId,
    required DateTime day,
  }) async {
    final response = await _client.rpc(
      'reception_doctor_busy_slots',
      params: {
        'p_doctor_id': doctorId,
        'p_day': DateFormat(
          'yyyy-MM-dd',
        ).format(
          day,
        ),
      },
    );

    final slots = <ReceptionBusySlot>[];

    for (final row in _mapRows(
      response,
    )) {
      try {
        slots.add(
          ReceptionBusySlot.fromJson(
            row,
          ),
        );
      } catch (_) {
        // Ignore malformed legacy busy-slot rows.
      }
    }

    return slots;
  }

  // ==========================================================================
  // QUEUE
  // ==========================================================================

  Future<List<ReceptionQueueItem>> loadTodayQueue() async {
    final response = await _client.rpc(
      'reception_queue_today',
    );

    return _mapRows(
      response,
    )
        .map(
          ReceptionQueueItem.fromJson,
        )
        .toList();
  }

  // ==========================================================================
  // WALK-IN
  // ==========================================================================

  Future<void> createWalkIn({
    required String patientId,
    required String departmentId,
    String? doctorId,
    required String reason,
    required String urgency,
  }) async {
    final context =
        await resolveHospitalContext();

    if (!context.hospitalFound) {
      throw Exception(
        'Reception hospital context could not be resolved.',
      );
    }

    await _client.rpc(
      'reception_create_walk_in',
      params: {
        'p_patient_id': patientId,
        'p_department_id': departmentId,
        'p_doctor_id':
            doctorId?.trim().isEmpty == true
                ? null
                : doctorId,
        'p_reason': reason.trim(),
        'p_urgency': urgency,
      },
    );
  }

  // ==========================================================================
  // APPOINTMENT
  // ==========================================================================

  Future<void> createAppointment({
    required String patientId,
    required String doctorId,
    required String departmentId,
    required DateTime startTime,
    required int durationMinutes,
    required String reason,
    required String appointmentType,
  }) async {
    final context =
        await resolveHospitalContext();

    if (!context.hospitalFound) {
      throw Exception(
        'Reception hospital context could not be resolved.',
      );
    }

    /*
     * Re-resolve the doctor through the safe hospital-scoped
     * doctor list immediately before booking.
     *
     * This prevents a stale/manually injected doctor ID from
     * bypassing Reception filtering.
     */
    final validDoctors =
        await loadDoctors(
      departmentId,
    );

    final validDoctor = validDoctors.any(
      (doctor) => doctor.id == doctorId,
    );

    if (!validDoctor) {
      throw Exception(
        'The selected doctor is not available for this '
        'hospital and department.',
      );
    }

    await _client.rpc(
      'reception_create_appointment',
      params: {
        'p_patient_id': patientId,
        'p_doctor_id': doctorId,
        'p_department_id': departmentId,
        'p_start_time':
            startTime.toUtc().toIso8601String(),
        'p_duration_minutes':
            durationMinutes,
        'p_reason':
            reason.trim(),
        'p_appointment_type':
            appointmentType,
      },
    );
  }

  // ==========================================================================
  // QR
  // ==========================================================================

  Future<ReceptionQrPreview> loadQrPreview({
    required String patientId,
    String? appointmentId,
  }) async {
    final response = await _client.rpc(
      'reception_qr_preview',
      params: {
        'p_patient_id': patientId,
        'p_appointment_id': appointmentId,
      },
    );

    return ReceptionQrPreview.fromJson(
      _mapResponse(
        response,
        label: 'QR preview',
      ),
    );
  }

  Future<void> confirmQrCheckIn({
    required String patientId,
    required String appointmentId,
  }) async {
    await _client.rpc(
      'reception_confirm_qr_checkin',
      params: {
        'p_patient_id': patientId,
        'p_appointment_id': appointmentId,
      },
    );
  }

  // ==========================================================================
  // QUEUE STATUS
  // ==========================================================================

  Future<void> updateQueueStatus({
    required String checkInId,
    required String newStatus,
    bool? makeUrgent,
    String? note,
  }) async {
    final params = <String, dynamic>{
      'p_checkin_id': checkInId,
      'p_new_status': newStatus,
    };

    if (makeUrgent != null) {
      params['p_make_urgent'] =
          makeUrgent;
    }

    if (note != null &&
        note.trim().isNotEmpty) {
      params['p_note'] =
          note.trim();
    }

    await _client.rpc(
      'reception_update_queue_status',
      params: params,
    );
  }

  // ==========================================================================
  // PRIVATE HELPERS
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

    if (response is List &&
        response.isNotEmpty) {
      final first = response.first;

      if (first is Map<String, dynamic>) {
        return first;
      }

      if (first is Map) {
        return Map<String, dynamic>.from(
          first,
        );
      }
    }

    throw Exception(
      '$label returned invalid data.',
    );
  }

  List<Map<String, dynamic>> _mapRows(
    dynamic response,
  ) {
    if (response is! List) {
      return <Map<String, dynamic>>[];
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
}

// ============================================================================
// SHARED PARSING HELPERS
// ============================================================================

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

  final text =
      value.toString().trim().toLowerCase();

  if (text == 'true' ||
      text == '1' ||
      text == 'yes') {
    return true;
  }

  if (text == 'false' ||
      text == '0' ||
      text == 'no') {
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

DateTime? _dateValue(
  dynamic value,
) {
  if (value == null) {
    return null;
  }

  return DateTime.tryParse(
    value.toString(),
  )?.toLocal();
}

List<int> _workingDays(
  dynamic value,
) {
  if (value is List) {
    final days = value
        .map(
          _dayNumber,
        )
        .whereType<int>()
        .where(
          (day) =>
              day >= 1 &&
              day <= 7,
        )
        .toSet()
        .toList()
      ..sort();

    if (days.isNotEmpty) {
      return days;
    }
  }

  return const [
    1,
    2,
    3,
    4,
    5,
  ];
}

int? _dayNumber(
  dynamic value,
) {
  final raw =
      value?.toString().trim().toLowerCase() ??
      '';

  final number =
      int.tryParse(
    raw,
  );

  if (number != null &&
      number >= 1 &&
      number <= 7) {
    return number;
  }

  const names = <String, int>{
    'monday': 1,
    'mon': 1,
    'tuesday': 2,
    'tue': 2,
    'tues': 2,
    'wednesday': 3,
    'wed': 3,
    'thursday': 4,
    'thu': 4,
    'thur': 4,
    'thurs': 4,
    'friday': 5,
    'fri': 5,
    'saturday': 6,
    'sat': 6,
    'sunday': 7,
    'sun': 7,
  };

  return names[raw];
}

int _timeToMinutes(
  dynamic value, {
  required int fallback,
}) {
  final text =
      value?.toString().trim() ?? '';

  if (text.isEmpty) {
    return fallback;
  }

  final cleanText =
      text.contains('T')
          ? text.split('T').last
          : text;

  final parts =
      cleanText.split(':');

  if (parts.length < 2) {
    return fallback;
  }

  final hour =
      int.tryParse(
    parts[0],
  );

  final minuteText =
      parts[1].replaceAll(
    RegExp(r'[^0-9]'),
    '',
  );

  final minute =
      int.tryParse(
    minuteText.length > 2
        ? minuteText.substring(0, 2)
        : minuteText,
  );

  if (hour == null ||
      minute == null ||
      hour < 0 ||
      hour > 23 ||
      minute < 0 ||
      minute > 59) {
    return fallback;
  }

  return (hour * 60) +
      minute;
}