import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../theme/app_theme.dart';
import '../forms/role_hospital_forms_page.dart';
import '../admin/controlled_hospital_forms_page.dart';
import '../admin/hospital_admissions_page.dart';
import '../admin/hospital_bed_board_page.dart';
import '../admin/hospital_structure_page.dart';
import 'hospital_admin_shell.dart';
import 'hospital_ai_booking_queue_page.dart';
import 'hospital_appointments_page.dart';
import 'hospital_billing_page.dart';
import 'hospital_departments_page.dart';
import 'hospital_doctors_page.dart';
import 'hospital_emergency_page.dart';
import 'hospital_locations_page.dart';
import 'hospital_patients_page.dart';
import 'hospital_qr_checkins_page.dart';
import 'hospital_reports_page.dart';
import 'hospital_settings_page.dart';
import 'widgets/hospital_operations_dashboard_panel.dart';

class HospitalDashboardPage extends StatefulWidget {
  const HospitalDashboardPage({
    super.key,
    this.embedded = false,
  });

  final bool embedded;

  @override
  State<HospitalDashboardPage> createState() => _HospitalDashboardPageState();
}

class _HospitalDashboardPageState extends State<HospitalDashboardPage> {
  final SupabaseClient _supabase = Supabase.instance.client;

  bool _loading = true;
  bool _actionBusy = false;
  bool _openingFormLibrary = false;
  bool _openingControlledForms = false;

  String? _error;

  String? _hospitalId;
  String _hospitalName = 'Hospital Dashboard';
  String _adminRole = 'hospital_admin';

  int _totalPatients = 0;
  int _totalDoctors = 0;
  int _availableDoctors = 0;
  int _totalDepartments = 0;
  int _appointmentsToday = 0;
  int _waitingPatients = 0;
  int _emergencyProfiles = 0;
  int _aiBookingRequests = 0;
  int _pendingAiBookings = 0;

  List<Map<String, dynamic>> _recentPatients = [];
  List<Map<String, dynamic>> _todayAppointments = [];
  List<Map<String, dynamic>> _recentCheckins = [];
  List<Map<String, dynamic>> _recentAiIntakes = [];
  List<Map<String, dynamic>> _doctorsOnDuty = [];
  List<Map<String, dynamic>> _departments = [];
  List<Map<String, dynamic>> _aiBookingQueue = [];

  @override
  void initState() {
    super.initState();
    _loadDashboard();
  }

  Future<void> _loadHospitalContext() async {
    final user = _supabase.auth.currentUser;

    if (user == null) {
      throw Exception(
        'You are not signed in.',
      );
    }

    final adminLink = await _supabase
        .from('hospital_admins')
        .select(
          'hospital_id, role, hospitals(name)',
        )
        .eq(
          'profile_id',
          user.id,
        )
        .maybeSingle();

    if (adminLink == null) {
      throw Exception(
        'This account is not linked to a hospital admin record.',
      );
    }

    final hospitalId = adminLink['hospital_id']?.toString();

    if (hospitalId == null || hospitalId.trim().isEmpty) {
      throw Exception(
        'Hospital admin record has no hospital ID.',
      );
    }

    String hospitalName = 'Hospital Dashboard';

    final hospitalJoin = adminLink['hospitals'];

    if (hospitalJoin is Map && hospitalJoin['name'] != null) {
      hospitalName = hospitalJoin['name'].toString();
    } else {
      final hospital = await _supabase
          .from('hospitals')
          .select('name')
          .eq(
            'id',
            hospitalId,
          )
          .maybeSingle();

      hospitalName = hospital?['name']?.toString() ?? hospitalName;
    }

    _hospitalId = hospitalId;
    _hospitalName = hospitalName;

    _adminRole = adminLink['role']?.toString() ?? 'hospital_admin';
  }

  Future<void> _loadDashboard() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      await _loadHospitalContext();

      if (_hospitalId == null) {
        throw Exception(
          'No hospital selected for this admin account.',
        );
      }

      final now = DateTime.now();

      final todayStart = DateTime(
        now.year,
        now.month,
        now.day,
      );

      final tomorrowStart = todayStart.add(
        const Duration(
          days: 1,
        ),
      );

      final results = await Future.wait([
        _safeCountHospital(
          'patients',
        ),
        _safeCountHospital(
          'doctors',
        ),
        _safeCountWhereHospital(
          'doctors',
          'status',
          'available',
        ),
        _safeCountHospital(
          'departments',
        ),
        _safeCountTodayAppointments(
          todayStart,
          tomorrowStart,
        ),
        _safeCountWhereHospital(
          'reception_checkins',
          'queue_status',
          'waiting',
        ),
        _safeCountEmergencyProfiles(),
        _safeCountHospital(
          'ai_symptom_intakes',
        ),
        _safeCountHospital(
          'hospital_ai_booking_requests',
        ),
        _safeCountWhereHospital(
          'hospital_ai_booking_requests',
          'status',
          'new',
        ),
        _safeSelectNewestHospital(
          'patients',
          limit: 8,
        ),
        _safeSelectTodayAppointments(
          todayStart,
          tomorrowStart,
          limit: 8,
        ),
        _safeSelectNewestHospital(
          'reception_checkins',
          limit: 8,
        ),
        _safeSelectNewestHospital(
          'ai_symptom_intakes',
          limit: 6,
        ),
        _safeSelectNewestHospital(
          'doctors',
          limit: 10,
        ),
        _safeSelectNewestHospital(
          'departments',
          limit: 10,
        ),
        _safeSelectNewestHospital(
          'hospital_ai_booking_requests',
          limit: 10,
        ),
      ]);

      if (!mounted) {
        return;
      }

      setState(() {
        _totalPatients = results[0] as int;

        _totalDoctors = results[1] as int;

        _availableDoctors = results[2] as int;

        _totalDepartments = results[3] as int;

        _appointmentsToday = results[4] as int;

        _waitingPatients = results[5] as int;

        _emergencyProfiles = results[6] as int;

        _aiBookingRequests = results[8] as int;

        _pendingAiBookings = results[9] as int;

        _recentPatients = results[10] as List<Map<String, dynamic>>;

        _todayAppointments = results[11] as List<Map<String, dynamic>>;

        _recentCheckins = results[12] as List<Map<String, dynamic>>;

        _recentAiIntakes = results[13] as List<Map<String, dynamic>>;

        _doctorsOnDuty = results[14] as List<Map<String, dynamic>>;

        _departments = results[15] as List<Map<String, dynamic>>;

        _aiBookingQueue = results[16] as List<Map<String, dynamic>>;

        _loading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _error = error.toString();

        _loading = false;
      });
    }
  }

  bool _tableHasHospitalId(
    String table,
  ) {
    return table == 'patients' ||
        table == 'doctors' ||
        table == 'departments' ||
        table == 'appointments' ||
        table == 'reception_checkins' ||
        table == 'ai_symptom_intakes' ||
        table == 'hospital_ai_booking_requests';
  }

  Future<int> _safeCountHospital(
    String table,
  ) async {
    try {
      dynamic query = _supabase.from(table).select('id');

      if (_tableHasHospitalId(
            table,
          ) &&
          _hospitalId != null) {
        query = query.eq(
          'hospital_id',
          _hospitalId!,
        );
      }

      final data = await query;

      return data is List ? data.length : 0;
    } catch (_) {
      return 0;
    }
  }

  Future<int> _safeCountWhereHospital(
    String table,
    String column,
    dynamic value,
  ) async {
    try {
      dynamic query = _supabase.from(table).select('id');

      if (_tableHasHospitalId(
            table,
          ) &&
          _hospitalId != null) {
        query = query.eq(
          'hospital_id',
          _hospitalId!,
        );
      }

      query = query.eq(
        column,
        value,
      );

      final data = await query;

      return data is List ? data.length : 0;
    } catch (_) {
      return 0;
    }
  }

  Future<int> _safeCountEmergencyProfiles() async {
    try {
      final data = await _supabase
          .from(
            'emergency_profiles',
          )
          .select('id');

      return data.length;
    } catch (_) {
      return 0;
    }
  }

  Future<int> _safeCountTodayAppointments(
    DateTime todayStart,
    DateTime tomorrowStart,
  ) async {
    final dateColumns = [
      'scheduled_for',
      'appointment_date',
      'scheduled_at',
      'created_at',
    ];

    for (final column in dateColumns) {
      try {
        final data = await _supabase
            .from(
              'appointments',
            )
            .select('id')
            .eq(
              'hospital_id',
              _hospitalId!,
            )
            .gte(
              column,
              todayStart.toIso8601String(),
            )
            .lt(
              column,
              tomorrowStart.toIso8601String(),
            );

        return data.length;
      } catch (_) {
        continue;
      }
    }

    return 0;
  }

  Future<List<Map<String, dynamic>>> _safeSelectHospital(
    String table, {
    int limit = 8,
  }) async {
    try {
      dynamic query = _supabase.from(table).select();

      if (_tableHasHospitalId(
            table,
          ) &&
          _hospitalId != null) {
        query = query.eq(
          'hospital_id',
          _hospitalId!,
        );
      }

      query = query.limit(limit);

      final data = await query;

      if (data is List) {
        return data
            .whereType<Map>()
            .map(
              (item) => Map<String, dynamic>.from(
                item,
              ),
            )
            .toList();
      }

      return [];
    } catch (_) {
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> _safeSelectNewestHospital(
    String table, {
    int limit = 8,
  }) async {
    try {
      dynamic query = _supabase.from(table).select();

      if (_tableHasHospitalId(
            table,
          ) &&
          _hospitalId != null) {
        query = query.eq(
          'hospital_id',
          _hospitalId!,
        );
      }

      query = query
          .order(
            'created_at',
            ascending: false,
          )
          .limit(limit);

      final data = await query;

      if (data is List) {
        return data
            .whereType<Map>()
            .map(
              (item) => Map<String, dynamic>.from(
                item,
              ),
            )
            .toList();
      }

      return [];
    } catch (_) {
      return _safeSelectHospital(
        table,
        limit: limit,
      );
    }
  }

  Future<List<Map<String, dynamic>>> _safeSelectTodayAppointments(
    DateTime todayStart,
    DateTime tomorrowStart, {
    int limit = 8,
  }) async {
    final dateColumns = [
      'scheduled_for',
      'appointment_date',
      'scheduled_at',
      'created_at',
    ];

    for (final column in dateColumns) {
      try {
        final data = await _supabase
            .from(
              'appointments',
            )
            .select()
            .eq(
              'hospital_id',
              _hospitalId!,
            )
            .gte(
              column,
              todayStart.toIso8601String(),
            )
            .lt(
              column,
              tomorrowStart.toIso8601String(),
            )
            .order(
              column,
              ascending: true,
            )
            .limit(
              limit,
            );

        return data
            .whereType<Map>()
            .map(
              (item) => Map<String, dynamic>.from(
                item,
              ),
            )
            .toList();
      } catch (_) {
        continue;
      }
    }

    return [];
  }

  Map<String, dynamic> _withoutNulls(
    Map<String, dynamic> values,
  ) {
    final cleaned = <String, dynamic>{};

    values.forEach(
      (
        key,
        value,
      ) {
        if (value == null) {
          return;
        }

        if (value is String && value.trim().isEmpty) {
          return;
        }

        cleaned[key] = value;
      },
    );

    return cleaned;
  }

  String _displayName(
    Map<String, dynamic> row,
  ) {
    final directName = row['full_name'] ??
        row['name'] ??
        row['display_name'] ??
        row['patient_name'] ??
        row['doctor_name'];

    if (directName != null && directName.toString().trim().isNotEmpty) {
      return directName.toString();
    }

    final firstName = row['first_name']?.toString() ?? '';

    final surname = row['surname']?.toString() ?? '';

    final lastName = row['last_name']?.toString() ?? '';

    final combined = '$firstName '
            '${surname.isNotEmpty ? surname : lastName}'
        .trim();

    if (combined.isNotEmpty) {
      return combined;
    }

    final email = row['email']?.toString();

    if (email != null && email.trim().isNotEmpty) {
      return email;
    }

    final id = row['id']?.toString();

    if (id != null && id.length > 8) {
      return 'Record '
          '${id.substring(0, 8)}';
    }

    return 'Unknown record';
  }

  String _subtitleFromRow(
    Map<String, dynamic> row,
  ) {
    final value = row['status'] ??
        row['appointment_status'] ??
        row['checkin_status'] ??
        row['queue_status'] ??
        row['role'] ??
        row['department'] ??
        row['phone'] ??
        row['created_at'];

    return value?.toString() ?? 'No extra details yet';
  }

  String _formatDateValue(
    dynamic value,
  ) {
    if (value == null) {
      return 'No date';
    }

    final date = DateTime.tryParse(
      value.toString(),
    );

    if (date == null) {
      return value.toString();
    }

    final local = date.toLocal();

    return '${local.year}-'
        '${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')} '
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }

  Color _statusColor(
    BuildContext context,
    String value,
  ) {
    final lower = value.toLowerCase();

    if (lower.contains(
          'emergency',
        ) ||
        lower.contains(
          'critical',
        ) ||
        lower.contains(
          'urgent',
        ) ||
        lower.contains(
          'danger',
        )) {
      return CorviaColors.danger;
    }

    if (lower.contains(
          'medium',
        ) ||
        lower.contains(
          'waiting',
        ) ||
        lower.contains(
          'pending',
        ) ||
        lower.contains(
          'review',
        ) ||
        lower.contains(
          'new',
        ) ||
        lower.contains(
          'busy',
        )) {
      return CorviaColors.warning;
    }

    if (lower.contains(
          'done',
        ) ||
        lower.contains(
          'active',
        ) ||
        lower.contains(
          'stable',
        ) ||
        lower.contains(
          'paid',
        ) ||
        lower.contains(
          'available',
        ) ||
        lower.contains(
          'confirmed',
        ) ||
        lower.contains(
          'completed',
        )) {
      return CorviaColors.success;
    }

    return context.cAccentReadable;
  }

  String _departmentNameById(
    dynamic departmentId,
  ) {
    if (departmentId == null) {
      return 'No department';
    }

    for (final department in _departments) {
      if (department['id']?.toString() == departmentId.toString()) {
        return department['name']?.toString() ?? 'No department';
      }
    }

    return 'Department linked';
  }

  dynamic _departmentIdByName(
    String? departmentName,
  ) {
    if (departmentName == null || departmentName.trim().isEmpty) {
      return null;
    }

    final target = departmentName.toLowerCase().trim();

    for (final department in _departments) {
      final name = department['name']?.toString().toLowerCase().trim() ?? '';

      if (name == target ||
          name.contains(
            target,
          ) ||
          target.contains(
            name,
          )) {
        return department['id'];
      }
    }

    if (target == 'general practice') {
      return null;
    }

    if (target.contains(
          'heart',
        ) ||
        target.contains(
          'blood pressure',
        )) {
      return _departmentIdByName(
        'Cardiology',
      );
    }

    if (target.contains(
          'scan',
        ) ||
        target.contains(
          'x-ray',
        ) ||
        target.contains(
          'xray',
        ) ||
        target.contains(
          'imaging',
        )) {
      return _departmentIdByName(
        'Radiology',
      );
    }

    if (target.contains(
          'blood test',
        ) ||
        target.contains(
          'lab',
        ) ||
        target.contains(
          'pathology',
        )) {
      return _departmentIdByName(
        'Pathology',
      );
    }

    if (target.contains(
          'child',
        ) ||
        target.contains(
          'children',
        ) ||
        target.contains(
          'baby',
        ) ||
        target.contains(
          'paediatric',
        )) {
      return _departmentIdByName(
        'Paediatrics',
      );
    }

    if (target.contains(
          'emergency',
        ) ||
        target.contains(
          'urgent',
        ) ||
        target.contains(
          'critical',
        )) {
      return _departmentIdByName(
        'Emergency',
      );
    }

    return _departmentIdByName(
      'General Practice',
    );
  }

  String _doctorNameById(
    dynamic doctorId,
  ) {
    if (doctorId == null) {
      return 'No doctor assigned';
    }

    for (final doctor in _doctorsOnDuty) {
      if (doctor['id']?.toString() == doctorId.toString()) {
        return _displayName(
          doctor,
        );
      }
    }

    return 'Doctor linked';
  }

  Map<String, dynamic>? _findDoctorForBooking(
    Map<String, dynamic> booking,
    dynamic departmentId,
  ) {
    final assignedDoctorId = booking['assigned_doctor_id'];

    if (assignedDoctorId != null) {
      for (final doctor in _doctorsOnDuty) {
        if (doctor['id']?.toString() == assignedDoctorId.toString()) {
          return doctor;
        }
      }
    }

    final activeDoctors = _doctorsOnDuty.where(
      (doctor) {
        return doctor['is_active'] != false;
      },
    ).toList();

    final availableDoctors = activeDoctors.where(
      (doctor) {
        final status = doctor['status']?.toString().toLowerCase() ?? '';

        return status == 'available';
      },
    ).toList();

    if (departmentId != null) {
      for (final doctor in availableDoctors) {
        if (doctor['department_id']?.toString() == departmentId.toString()) {
          return doctor;
        }
      }

      for (final doctor in activeDoctors) {
        if (doctor['department_id']?.toString() == departmentId.toString()) {
          return doctor;
        }
      }
    }

    if (availableDoctors.isNotEmpty) {
      return availableDoctors.first;
    }

    if (activeDoctors.isNotEmpty) {
      return activeDoctors.first;
    }

    return null;
  }

  String _appointmentTitle(
    Map<String, dynamic> appointment,
  ) {
    final title = appointment['title'] ??
        appointment['reason'] ??
        appointment['appointment_reason'] ??
        appointment['patient_name'];

    if (title != null && title.toString().trim().isNotEmpty) {
      return title.toString();
    }

    final patientId = appointment['patient_id'];

    if (patientId != null) {
      for (final patient in _recentPatients) {
        if (patient['id']?.toString() == patientId.toString()) {
          return _displayName(
            patient,
          );
        }
      }
    }

    return 'Appointment';
  }

  void _showSnack(
    String message, {
    bool isError = false,
  }) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor:
            isError ? CorviaColors.danger : CorviaColors.accentDark,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _openPage(
    Widget page,
  ) {
    HospitalAdminSection? section;

    if (page is HospitalPatientsPage) {
      section = HospitalAdminSection.patients;
    } else if (page is HospitalDoctorsPage) {
      section = HospitalAdminSection.doctors;
    } else if (page is HospitalAppointmentsPage) {
      section = HospitalAdminSection.appointments;
    } else if (page is HospitalAdmissionsPage) {
      section = HospitalAdminSection.admissions;
    } else if (page is HospitalBedBoardPage) {
      section = HospitalAdminSection.bedBoard;
    } else if (page is HospitalStructurePage) {
      section = HospitalAdminSection.structure;
    } else if (page is HospitalQrCheckinsPage) {
      section = HospitalAdminSection.qrCheckins;
    } else if (page is HospitalAiBookingQueuePage) {
      section = HospitalAdminSection.aiBookingQueue;
    } else if (page is HospitalDepartmentsPage) {
      section = HospitalAdminSection.departments;
    } else if (page is HospitalLocationsPage) {
      section = HospitalAdminSection.locations;
    } else if (page is HospitalEmergencyPage) {
      section = HospitalAdminSection.emergency;
    } else if (page is HospitalBillingPage) {
      section = HospitalAdminSection.billing;
    } else if (page is HospitalReportsPage) {
      section = HospitalAdminSection.reports;
    } else if (page is HospitalSettingsPage) {
      section = HospitalAdminSection.settings;
    }

    if (section != null) {
      HospitalAdminShell.openSection(
        context,
        section: section,
        fallbackPage: page,
      );
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => page,
      ),
    );
  }

  Future<void> _escalateAiBooking(
    Map<String, dynamic> booking,
  ) async {
    if (_actionBusy) {
      return;
    }

    final hospitalId = _hospitalId;

    final bookingId = booking['id'];

    if (hospitalId == null || bookingId == null) {
      _showSnack(
        'Booking request is incomplete.',
        isError: true,
      );

      return;
    }

    setState(() {
      _actionBusy = true;
    });

    try {
      final emergencyDepartmentId = _departmentIdByName(
        'Emergency',
      );

      final selectedDoctor = _findDoctorForBooking(
        booking,
        emergencyDepartmentId,
      );

      final doctorId = selectedDoctor?['id'];

      await _supabase
          .from(
            'hospital_ai_booking_requests',
          )
          .update(
            _withoutNulls({
              'status': 'emergency_escalation',
              'ai_urgency': 'emergency',
              'ai_recommended_department': 'Emergency',
              'requested_department_id': emergencyDepartmentId,
              'assigned_doctor_id': doctorId,
              'ai_notes': '${booking['ai_notes'] ?? ''}\n'
                  'Manually escalated from hospital dashboard. '
                  'Send patient to emergency staff immediately.',
              'updated_at': DateTime.now().toIso8601String(),
            }),
          )
          .eq(
            'id',
            bookingId,
          )
          .eq(
            'hospital_id',
            hospitalId,
          );

      final checkinId = booking['checkin_id'];

      if (checkinId != null) {
        await _supabase
            .from(
              'reception_checkins',
            )
            .update(
              _withoutNulls({
                'checkin_status': 'emergency_escalation',
                'ai_booking_status': 'emergency_escalation',
                'department_id': emergencyDepartmentId,
                'assigned_doctor_id': doctorId,
                'updated_at': DateTime.now().toIso8601String(),
              }),
            )
            .eq(
              'id',
              checkinId,
            )
            .eq(
              'hospital_id',
              hospitalId,
            );
      }

      _showSnack(
        'Patient escalated to emergency queue.',
      );

      await _loadDashboard();
    } catch (error) {
      _showSnack(
        'Could not escalate booking: $error',
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          _actionBusy = false;
        });
      }
    }
  }

  Future<void> _confirmAiBooking(
    Map<String, dynamic> booking,
  ) async {
    if (_actionBusy) {
      return;
    }

    final hospitalId = _hospitalId;

    final bookingId = booking['id'];

    if (hospitalId == null || bookingId == null) {
      _showSnack(
        'Booking request is incomplete.',
        isError: true,
      );

      return;
    }

    setState(() {
      _actionBusy = true;
    });

    try {
      final departmentId = booking['requested_department_id'] ??
          _departmentIdByName(
            booking['ai_recommended_department']?.toString(),
          );

      final selectedDoctor = _findDoctorForBooking(
        booking,
        departmentId,
      );

      final doctorId = selectedDoctor?['id'];

      await _supabase
          .from(
            'hospital_ai_booking_requests',
          )
          .update(
            _withoutNulls({
              'status': 'confirmed',
              'requested_department_id': departmentId,
              'assigned_doctor_id': doctorId,
              'updated_at': DateTime.now().toIso8601String(),
            }),
          )
          .eq(
            'id',
            bookingId,
          )
          .eq(
            'hospital_id',
            hospitalId,
          );

      final checkinId = booking['checkin_id'];

      if (checkinId != null) {
        await _supabase
            .from(
              'reception_checkins',
            )
            .update(
              _withoutNulls({
                'checkin_status': 'confirmed',
                'ai_booking_status': 'confirmed',
                'department_id': departmentId,
                'assigned_doctor_id': doctorId,
                'updated_at': DateTime.now().toIso8601String(),
              }),
            )
            .eq(
              'id',
              checkinId,
            )
            .eq(
              'hospital_id',
              hospitalId,
            );
      }

      _showSnack(
        'Booking confirmed and assigned.',
      );

      await _loadDashboard();
    } catch (error) {
      _showSnack(
        'Could not confirm booking: $error',
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          _actionBusy = false;
        });
      }
    }
  }

  Future<void> _openHospitalFormLibrary() async {
    if (_openingFormLibrary) {
      return;
    }

    final hospitalId = _hospitalId;

    if (hospitalId == null || hospitalId.trim().isEmpty) {
      _showSnack(
        'Hospital context is unavailable. '
        'The form library cannot be opened.',
        isError: true,
      );

      return;
    }

    setState(() {
      _openingFormLibrary = true;
    });

    try {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) {
            return const RoleHospitalFormsPage(
              title: 'Hospital Form Library',
              patientVisibleOnly: false,
              allowCreate: true,
            );
          },
        ),
      );
    } catch (error) {
      _showSnack(
        'Could not open Hospital Form Library: $error',
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          _openingFormLibrary = false;
        });
      }
    }
  }

  Future<void> _openControlledOfficialForms() async {
    if (_openingControlledForms) {
      return;
    }

    final hospitalId = _hospitalId;

    if (hospitalId == null || hospitalId.trim().isEmpty) {
      _showSnack(
        'Hospital context is unavailable. '
        'Controlled Official Forms cannot be opened.',
        isError: true,
      );

      return;
    }

    setState(() {
      _openingControlledForms = true;
    });

    try {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) {
            return ControlledHospitalFormsPage(
              hospitalId: hospitalId,
            );
          },
        ),
      );
    } catch (error) {
      _showSnack(
        'Could not open Controlled Official Forms: $error',
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          _openingControlledForms = false;
        });
      }
    }
  }

  Future<void> _signOut() async {
    await _supabase.auth.signOut();
  }

  @override
  Widget build(
    BuildContext context,
  ) {
    if (!widget.embedded) {
      return HospitalAdminShell(
        initialSection: HospitalAdminSection.dashboard,
        dashboardPage: const HospitalDashboardPage(
          embedded: true,
        ),
      );
    }

    return LayoutBuilder(
      builder: (
        context,
        constraints,
      ) {
        final isWide = constraints.maxWidth >= 900;

        return _buildBody(
          isWide: isWide,
        );
      },
    );
  }

  Widget _buildBody({
    required bool isWide,
  }) {
    if (_loading) {
      return Center(
        child: CircularProgressIndicator(
          color: context.cAccentReadable,
        ),
      );
    }

    return RefreshIndicator(
      color: context.cAccentReadable,
      onRefresh: _loadDashboard,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.all(
          isWide ? 28 : 16,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildTopHeader(
              isWide,
            ),
            const SizedBox(
              height: 22,
            ),
            if (_error != null) _buildErrorBox(),
            _buildKpiGrid(
              isWide,
            ),
            const SizedBox(
              height: 22,
            ),
            if (isWide)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 7,
                    child: Column(
                      children: [
                        _buildOperationsPanel(),
                        const SizedBox(
                          height: 18,
                        ),
                        _buildFormsLibraryPanel(),
                        const SizedBox(
                          height: 18,
                        ),
                        _buildAiBookingPanel(),
                        const SizedBox(
                          height: 18,
                        ),
                        _buildAppointmentsPanel(),
                        const SizedBox(
                          height: 18,
                        ),
                        _buildPatientsPanel(),
                      ],
                    ),
                  ),
                  const SizedBox(
                    width: 18,
                  ),
                  Expanded(
                    flex: 5,
                    child: Column(
                      children: [
                        _buildDoctorsPanel(),
                        const SizedBox(
                          height: 18,
                        ),
                        _buildHospitalFlowPanel(),
                        const SizedBox(
                          height: 18,
                        ),
                        _buildAiEmergencyPanel(),
                        const SizedBox(
                          height: 18,
                        ),
                        _buildDepartmentsPanel(),
                      ],
                    ),
                  ),
                ],
              )
            else
              Column(
                children: [
                  _buildOperationsPanel(),
                  const SizedBox(
                    height: 18,
                  ),
                  _buildFormsLibraryPanel(),
                  const SizedBox(
                    height: 18,
                  ),
                  _buildAiBookingPanel(),
                  const SizedBox(
                    height: 18,
                  ),
                  _buildDoctorsPanel(),
                  const SizedBox(
                    height: 18,
                  ),
                  _buildAppointmentsPanel(),
                  const SizedBox(
                    height: 18,
                  ),
                  _buildPatientsPanel(),
                  const SizedBox(
                    height: 18,
                  ),
                  _buildHospitalFlowPanel(),
                  const SizedBox(
                    height: 18,
                  ),
                  _buildAiEmergencyPanel(),
                  const SizedBox(
                    height: 18,
                  ),
                  _buildDepartmentsPanel(),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopHeader(
    bool isWide,
  ) {
    return LayoutBuilder(
      builder: (
        context,
        constraints,
      ) {
        final compact = constraints.maxWidth < 650;

        final heading = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _hospitalName,
              style: TextStyle(
                color: context.cTextPrimary,
                fontSize: 28,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(
              height: 6,
            ),
            Text(
              'Hospital Dashboard • '
              '${_adminRole.toUpperCase()} • '
              'Live doctors, departments, QR check-ins, '
              'appointments and AI booking flow.',
              style: TextStyle(
                color: context.cTextSecondary,
                fontSize: isWide ? 15 : 13,
              ),
            ),
          ],
        );

        final actions = Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _HeaderButton(
              icon: Icons.policy_outlined,
              label: _openingControlledForms
                  ? 'Opening Controls...'
                  : 'Controlled Forms',
              onTap: _openingControlledForms
                  ? () {}
                  : _openControlledOfficialForms,
            ),
            _HeaderButton(
              icon: Icons.description_outlined,
              label: _openingFormLibrary ? 'Opening Forms...' : 'Form Library',
              onTap: _openingFormLibrary ? () {} : _openHospitalFormLibrary,
            ),
            _HeaderButton(
              icon: Icons.refresh_rounded,
              label: 'Refresh',
              onTap: _loadDashboard,
            ),
            _HeaderButton(
              icon: Icons.logout_rounded,
              label: 'Sign out',
              onTap: _signOut,
              danger: true,
            ),
          ],
        );

        if (compact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              heading,
              const SizedBox(
                height: 14,
              ),
              actions,
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: heading,
            ),
            const SizedBox(
              width: 16,
            ),
            actions,
          ],
        );
      },
    );
  }

  Widget _buildErrorBox() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(
        bottom: 18,
      ),
      padding: const EdgeInsets.all(
        14,
      ),
      decoration: BoxDecoration(
        color: CorviaColors.danger.withValues(
          alpha: 0.08,
        ),
        borderRadius: BorderRadius.circular(
          16,
        ),
        border: Border.all(
          color: CorviaColors.danger.withValues(
            alpha: 0.18,
          ),
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.info_outline_rounded,
            color: CorviaColors.danger,
          ),
          const SizedBox(
            width: 10,
          ),
          Expanded(
            child: Text(
              'Some dashboard data could not load. '
              '$_error',
              style: TextStyle(
                color: context.cTextPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildKpiGrid(
    bool isWide,
  ) {
    final cards = [
      _KpiData(
        title: 'Total Patients',
        value: _totalPatients.toString(),
        subtitle: 'Registered patient records',
        icon: Icons.people_alt_rounded,
        color: context.cAccentReadable,
      ),
      _KpiData(
        title: 'Doctors',
        value: _totalDoctors.toString(),
        subtitle: 'Doctors in this hospital',
        icon: Icons.medical_services_rounded,
        color: CorviaColors.success,
      ),
      _KpiData(
        title: 'Available Doctors',
        value: _availableDoctors.toString(),
        subtitle: 'Ready for assignment',
        icon: Icons.assignment_ind_rounded,
        color: CorviaColors.success,
      ),
      _KpiData(
        title: 'Departments',
        value: _totalDepartments.toString(),
        subtitle: 'Hospital departments',
        icon: Icons.local_hospital_rounded,
        color: context.cAccentReadable,
      ),
      _KpiData(
        title: 'Appointments',
        value: _appointmentsToday.toString(),
        subtitle: 'Scheduled today',
        icon: Icons.calendar_month_rounded,
        color: context.cAccentReadable,
      ),
      _KpiData(
        title: 'Reception Queue',
        value: _waitingPatients.toString(),
        subtitle: 'Waiting QR/check-ins',
        icon: Icons.qr_code_scanner_rounded,
        color: CorviaColors.warning,
      ),
      _KpiData(
        title: 'AI Booking',
        value: _pendingAiBookings.toString(),
        subtitle: 'New AI booking requests',
        icon: Icons.auto_awesome_rounded,
        color: context.cAccentReadable,
      ),
      _KpiData(
        title: 'Emergency Profiles',
        value: _emergencyProfiles.toString(),
        subtitle: 'Emergency-ready records',
        icon: Icons.emergency_rounded,
        color: CorviaColors.danger,
      ),
    ];

    return GridView.builder(
      itemCount: cards.length,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: isWide ? 4 : 2,
        crossAxisSpacing: 14,
        mainAxisSpacing: 14,
        mainAxisExtent: isWide ? 215 : 190,
      ),
      itemBuilder: (
        context,
        index,
      ) {
        final card = cards[index];

        return Container(
          padding: const EdgeInsets.all(
            18,
          ),
          decoration: BoxDecoration(
            color: context.cBgSecondary,
            borderRadius: BorderRadius.circular(
              22,
            ),
            border: Border.all(
              color: context.cDivider,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: 44,
                width: 44,
                decoration: BoxDecoration(
                  color: card.color.withValues(
                    alpha: 0.10,
                  ),
                  borderRadius: BorderRadius.circular(
                    15,
                  ),
                ),
                child: Icon(
                  card.icon,
                  color: card.color,
                ),
              ),
              const Spacer(),
              Text(
                card.value,
                style: TextStyle(
                  color: context.cTextPrimary,
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(
                height: 3,
              ),
              Text(
                card.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: context.cTextPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(
                height: 3,
              ),
              Text(
                card.subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: context.cTextSecondary,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildOperationsPanel() {
    final hospitalId = _hospitalId;

    if (hospitalId == null || hospitalId.trim().isEmpty) {
      return const SizedBox.shrink();
    }

    return HospitalOperationsDashboardPanel(
      hospitalId: hospitalId,
      onOpenAdmissions: () {
        _openPage(
          HospitalAdmissionsPage(
            initialHospitalId: hospitalId,
          ),
        );
      },
      onOpenBedBoard: () {
        _openPage(
          HospitalBedBoardPage(
            initialHospitalId: hospitalId,
          ),
        );
      },
      onOpenStructure: () {
        _openPage(
          const HospitalStructurePage(),
        );
      },
    );
  }

  Widget _buildFormsLibraryPanel() {
    return _HospitalPanel(
      title: 'Digital Hospital Forms',
      subtitle: 'Hospital-scoped digital forms plus controlled official '
          'master-document governance, approvals and audit history.',
      icon: Icons.description_outlined,
      actionLabel: _openingFormLibrary ? 'Opening...' : 'Open Library',
      onAction: _openingFormLibrary ? () {} : _openHospitalFormLibrary,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(
          15,
        ),
        decoration: BoxDecoration(
          color: context.cBgPrimary,
          borderRadius: BorderRadius.circular(
            18,
          ),
          border: Border.all(
            color: context.cDivider,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 44,
                  width: 44,
                  decoration: BoxDecoration(
                    color: context.cAccentReadable.withValues(
                      alpha: 0.10,
                    ),
                    borderRadius: BorderRadius.circular(
                      14,
                    ),
                  ),
                  child: Icon(
                    Icons.library_books_outlined,
                    color: context.cAccentReadable,
                  ),
                ),
                const SizedBox(
                  width: 12,
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Hospital Form Library',
                        style: TextStyle(
                          color: context.cTextPrimary,
                          fontWeight: FontWeight.w900,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(
                        height: 4,
                      ),
                      Text(
                        'Open the digital form workspace for this hospital. '
                        'Access is still enforced by the Form Engine and Supabase RLS.',
                        style: TextStyle(
                          color: context.cTextSecondary,
                          fontSize: 12,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(
              height: 14,
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: const [
                _FormFeatureChip(
                  icon: Icons.account_tree_outlined,
                  label: 'Versioned Templates',
                ),
                _FormFeatureChip(
                  icon: Icons.admin_panel_settings_outlined,
                  label: 'Role Permissions',
                ),
                _FormFeatureChip(
                  icon: Icons.draw_outlined,
                  label: 'Signatures',
                ),
                _FormFeatureChip(
                  icon: Icons.history_outlined,
                  label: 'Audit History',
                ),
                _FormFeatureChip(
                  icon: Icons.policy_outlined,
                  label: 'Official Controls',
                ),
              ],
            ),
            const SizedBox(
              height: 14,
            ),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed:
                    _openingFormLibrary ? null : _openHospitalFormLibrary,
                icon: _openingFormLibrary
                    ? const SizedBox(
                        width: 17,
                        height: 17,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                        ),
                      )
                    : const Icon(
                        Icons.description_outlined,
                      ),
                label: Text(
                  _openingFormLibrary
                      ? 'Opening Form Library...'
                      : 'Open Hospital Form Library',
                ),
              ),
            ),
            const SizedBox(
              height: 10,
            ),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _openingControlledForms
                    ? null
                    : _openControlledOfficialForms,
                icon: _openingControlledForms
                    ? const SizedBox(
                        width: 17,
                        height: 17,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                        ),
                      )
                    : const Icon(
                        Icons.policy_outlined,
                      ),
                label: Text(
                  _openingControlledForms
                      ? 'Opening Controlled Forms...'
                      : 'Open Controlled Official Forms',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAiBookingPanel() {
    return _HospitalPanel(
      title: 'AI Booking Assistant',
      subtitle: 'New QR-scanned patients, suggested department, '
          'urgency and doctor assignment',
      icon: Icons.auto_awesome_rounded,
      actionLabel: '$_aiBookingRequests total',
      onAction: () {
        _openPage(
          const HospitalAiBookingQueuePage(),
        );
      },
      child: _aiBookingQueue.isEmpty
          ? const _EmptyState(
              icon: Icons.auto_awesome_outlined,
              title: 'No AI booking requests yet',
              message: 'When a QR-scanned patient completes intake, '
                  'the booking request will appear here.',
            )
          : Column(
              children: _aiBookingQueue.map(
                (
                  booking,
                ) {
                  final urgency = booking['ai_urgency']?.toString() ?? 'normal';

                  final status = booking['status']?.toString() ?? 'new';

                  final patientName = _displayName(
                    booking,
                  );

                  final departmentId = booking['requested_department_id'] ??
                      _departmentIdByName(
                        booking['ai_recommended_department']?.toString(),
                      );

                  final selectedDoctor = _findDoctorForBooking(
                    booking,
                    departmentId,
                  );

                  final recommendedDepartment =
                      booking['ai_recommended_department']?.toString() ??
                          _departmentNameById(
                            departmentId,
                          );

                  return _AiBookingCard(
                    patientName: patientName,
                    phone: booking['patient_phone']?.toString() ?? 'No phone',
                    reason:
                        booking['reason']?.toString() ?? 'No reason captured',
                    symptoms: booking['symptoms']?.toString() ??
                        'No symptoms captured',
                    aiSummary: booking['ai_summary']?.toString() ??
                        'No AI summary yet',
                    recommendedDepartment: recommendedDepartment,
                    suggestedDoctor: selectedDoctor != null
                        ? _displayName(
                            selectedDoctor,
                          )
                        : _doctorNameById(
                            booking['assigned_doctor_id'],
                          ),
                    urgency: urgency,
                    status: status,
                    confidence: booking['ai_confidence']?.toString(),
                    createdAt: _formatDateValue(
                      booking['created_at'],
                    ),
                    statusColor: _statusColor(
                      context,
                      '$urgency $status',
                    ),
                    busy: _actionBusy,
                    onConfirm: () {
                      _confirmAiBooking(
                        booking,
                      );
                    },
                    onEmergency: () {
                      _escalateAiBooking(
                        booking,
                      );
                    },
                  );
                },
              ).toList(),
            ),
    );
  }

  Widget _buildDoctorsPanel() {
    return _HospitalPanel(
      title: 'Doctors On Duty',
      subtitle: 'Available doctors, specialties, departments and rooms',
      icon: Icons.medical_services_rounded,
      actionLabel: 'Manage',
      onAction: () {
        _openPage(
          const HospitalDoctorsPage(),
        );
      },
      child: _doctorsOnDuty.isEmpty
          ? const _EmptyState(
              icon: Icons.medical_services_outlined,
              title: 'No doctors found',
              message: 'Doctors linked to this hospital will appear '
                  'on the dashboard.',
            )
          : Column(
              children: _doctorsOnDuty.map(
                (
                  doctor,
                ) {
                  final name = _displayName(
                    doctor,
                  );

                  final specialty = doctor['specialty']?.toString() ??
                      doctor['specialization']?.toString() ??
                      'No specialty';

                  final status = doctor['status']?.toString() ?? 'available';

                  final room = doctor['room_name']?.toString() ??
                      doctor['room_number']?.toString() ??
                      'No room';

                  final location =
                      doctor['location_name']?.toString() ?? 'No location';

                  final department = _departmentNameById(
                    doctor['department_id'],
                  );

                  return _DoctorRecord(
                    name: name,
                    specialty: specialty,
                    department: department,
                    room: room,
                    location: location,
                    status: status,
                    color: _statusColor(
                      context,
                      status,
                    ),
                  );
                },
              ).toList(),
            ),
    );
  }

  Widget _buildAppointmentsPanel() {
    return _HospitalPanel(
      title: 'Today’s Appointments',
      subtitle: 'Scheduled patient visits and consultations',
      icon: Icons.calendar_month_rounded,
      actionLabel: 'Schedule',
      onAction: () {
        _openPage(
          const HospitalAppointmentsPage(),
        );
      },
      child: _todayAppointments.isEmpty
          ? const _EmptyState(
              icon: Icons.event_busy_rounded,
              title: 'No appointments loaded',
              message: 'Appointments for today will show here.',
            )
          : Column(
              children: _todayAppointments.map(
                (
                  appointment,
                ) {
                  final status = appointment['status'] ??
                      appointment['appointment_status'] ??
                      'Scheduled';

                  return _RecordTile(
                    icon: Icons.event_note_rounded,
                    title: _appointmentTitle(
                      appointment,
                    ),
                    subtitle: status.toString(),
                    trailing: _formatDateValue(
                      appointment['scheduled_for'] ??
                          appointment['appointment_date'] ??
                          appointment['scheduled_at'] ??
                          appointment['created_at'],
                    ),
                    color: _statusColor(
                      context,
                      status.toString(),
                    ),
                  );
                },
              ).toList(),
            ),
    );
  }

  Widget _buildPatientsPanel() {
    return _HospitalPanel(
      title: 'Recent Patients',
      subtitle: 'Latest patient records in this hospital',
      icon: Icons.people_alt_rounded,
      actionLabel: 'View all',
      onAction: () {
        _openPage(
          const HospitalPatientsPage(),
        );
      },
      child: _recentPatients.isEmpty
          ? const _EmptyState(
              icon: Icons.people_outline_rounded,
              title: 'No patients found',
              message: 'Once patients are linked to this hospital, '
                  'they will appear here.',
            )
          : Column(
              children: _recentPatients.map(
                (
                  patient,
                ) {
                  final subtitle = _subtitleFromRow(
                    patient,
                  );

                  return _RecordTile(
                    icon: Icons.person_rounded,
                    title: _displayName(
                      patient,
                    ),
                    subtitle: subtitle,
                    trailing: _formatDateValue(
                      patient['created_at'] ?? patient['createdAt'],
                    ),
                    color: _statusColor(
                      context,
                      subtitle,
                    ),
                  );
                },
              ).toList(),
            ),
    );
  }

  Widget _buildHospitalFlowPanel() {
    final flowItems = [
      _FlowItem(
        label: 'Reception',
        value: _waitingPatients,
        icon: Icons.assignment_turned_in_rounded,
        color: CorviaColors.warning,
      ),
      _FlowItem(
        label: 'Consultation',
        value: _appointmentsToday,
        icon: Icons.medical_services_rounded,
        color: context.cAccentReadable,
      ),
      _FlowItem(
        label: 'Doctors',
        value: _availableDoctors,
        icon: Icons.assignment_ind_rounded,
        color: CorviaColors.success,
      ),
      _FlowItem(
        label: 'AI Booking',
        value: _pendingAiBookings,
        icon: Icons.auto_awesome_rounded,
        color: context.cAccentReadable,
      ),
      _FlowItem(
        label: 'Emergency',
        value: _emergencyProfiles,
        icon: Icons.emergency_rounded,
        color: CorviaColors.danger,
      ),
    ];

    final maxValue = flowItems
        .map(
          (
            item,
          ) =>
              item.value,
        )
        .fold<int>(
          1,
          (
            max,
            value,
          ) =>
              value > max ? value : max,
        );

    return _HospitalPanel(
      title: 'Hospital Flow',
      subtitle: 'Live hospital queue and operational overview',
      icon: Icons.account_tree_rounded,
      actionLabel: 'Locations',
      onAction: () {
        _openPage(
          const HospitalLocationsPage(),
        );
      },
      child: Column(
        children: flowItems.map(
          (
            item,
          ) {
            final progress = item.value <= 0 ? 0.06 : item.value / maxValue;

            return Container(
              margin: const EdgeInsets.only(
                bottom: 14,
              ),
              child: Row(
                children: [
                  Container(
                    height: 42,
                    width: 42,
                    decoration: BoxDecoration(
                      color: item.color.withValues(
                        alpha: 0.10,
                      ),
                      borderRadius: BorderRadius.circular(
                        14,
                      ),
                    ),
                    child: Icon(
                      item.icon,
                      color: item.color,
                    ),
                  ),
                  const SizedBox(
                    width: 12,
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                item.label,
                                style: TextStyle(
                                  color: context.cTextPrimary,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            Text(
                              item.value.toString(),
                              style: TextStyle(
                                color: context.cTextPrimary,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(
                          height: 8,
                        ),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(
                            99,
                          ),
                          child: LinearProgressIndicator(
                            value: progress.clamp(
                              0.0,
                              1.0,
                            ),
                            minHeight: 8,
                            backgroundColor: const Color(
                              0xFFE2E8F0,
                            ),
                            valueColor: AlwaysStoppedAnimation<Color>(
                              item.color,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ).toList(),
      ),
    );
  }

  Widget _buildAiEmergencyPanel() {
    return _HospitalPanel(
      title: 'AI + Emergency Watch',
      subtitle: 'Recent AI intakes and urgent patient flags',
      icon: Icons.monitor_heart_rounded,
      actionLabel: 'Review',
      onAction: () {
        _openPage(
          const HospitalEmergencyPage(),
        );
      },
      child: Column(
        children: [
          if (_recentAiIntakes.isEmpty)
            const _EmptyState(
              icon: Icons.auto_awesome_outlined,
              title: 'No AI intakes yet',
              message: 'AI symptom summaries and doctor-ready notes '
                  'will show here.',
            )
          else
            ..._recentAiIntakes.map(
              (
                intake,
              ) {
                final title = intake['summary'] ??
                    intake['main_complaint'] ??
                    intake['symptoms'] ??
                    intake['patient_name'] ??
                    'AI symptom intake';

                final status = intake['urgency'] ??
                    intake['priority'] ??
                    intake['status'] ??
                    'Needs review';

                return _RecordTile(
                  icon: Icons.auto_awesome_rounded,
                  title: title.toString(),
                  subtitle: status.toString(),
                  trailing: _formatDateValue(
                    intake['created_at'],
                  ),
                  color: _statusColor(
                    context,
                    status.toString(),
                  ),
                );
              },
            ),
          if (_recentCheckins.isNotEmpty) ...[
            const SizedBox(
              height: 14,
            ),
            Divider(
              color: context.cDivider,
            ),
            const SizedBox(
              height: 12,
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Recent QR / Reception Check-ins',
                style: TextStyle(
                  color: context.cTextPrimary,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const SizedBox(
              height: 10,
            ),
            ..._recentCheckins
                .take(
              4,
            )
                .map(
              (
                checkin,
              ) {
                final status = checkin['status'] ??
                    checkin['checkin_status'] ??
                    checkin['queue_status'] ??
                    'Checked in';

                return _RecordTile(
                  icon: Icons.qr_code_scanner_rounded,
                  title: _displayName(
                    checkin,
                  ),
                  subtitle: status.toString(),
                  trailing: _formatDateValue(
                    checkin['created_at'],
                  ),
                  color: _statusColor(
                    context,
                    status.toString(),
                  ),
                );
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDepartmentsPanel() {
    return _HospitalPanel(
      title: 'Departments',
      subtitle: 'Hospital departments and locations',
      icon: Icons.local_hospital_rounded,
      actionLabel: 'Manage',
      onAction: () {
        _openPage(
          const HospitalDepartmentsPage(),
        );
      },
      child: _departments.isEmpty
          ? const _EmptyState(
              icon: Icons.local_hospital_outlined,
              title: 'No departments found',
              message: 'Departments such as Emergency and '
                  'General Practice will appear here.',
            )
          : Column(
              children: _departments.map(
                (
                  department,
                ) {
                  return _RecordTile(
                    icon: Icons.local_hospital_rounded,
                    title: department['name']?.toString() ?? 'Department',
                    subtitle: department['description']?.toString() ??
                        'No description',
                    trailing: department['location_name']?.toString() ??
                        'No location',
                    color: context.cAccentReadable,
                  );
                },
              ).toList(),
            ),
    );
  }
}

class _KpiData {
  const _KpiData({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.icon,
    required this.color,
  });

  final String title;
  final String value;
  final String subtitle;
  final IconData icon;
  final Color color;
}

class _FlowItem {
  const _FlowItem({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final int value;
  final IconData icon;
  final Color color;
}

class _HeaderButton extends StatelessWidget {
  const _HeaderButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(
    BuildContext context,
  ) {
    final color = danger ? CorviaColors.danger : context.cAccentReadable;

    return Material(
      color: context.cBgSecondary,
      borderRadius: BorderRadius.circular(
        14,
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(
          14,
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: 15,
            vertical: 12,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(
              14,
            ),
            border: Border.all(
              color: context.cDivider,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                color: color,
                size: 19,
              ),
              const SizedBox(
                width: 8,
              ),
              Text(
                label,
                style: TextStyle(
                  color: context.cTextPrimary,
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HospitalPanel extends StatelessWidget {
  const _HospitalPanel({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.actionLabel,
    required this.onAction,
    required this.child,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final String actionLabel;
  final VoidCallback onAction;
  final Widget child;

  @override
  Widget build(
    BuildContext context,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(
        18,
      ),
      decoration: BoxDecoration(
        color: context.cBgSecondary,
        borderRadius: BorderRadius.circular(
          24,
        ),
        border: Border.all(
          color: context.cDivider,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (
              context,
              constraints,
            ) {
              final compact = constraints.maxWidth < 520;

              final titleBlock = Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: context.cTextPrimary,
                        fontWeight: FontWeight.w900,
                        fontSize: 17,
                      ),
                    ),
                    const SizedBox(
                      height: 3,
                    ),
                    Text(
                      subtitle,
                      maxLines: compact ? 3 : 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: context.cTextSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              );

              if (compact) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          height: 42,
                          width: 42,
                          decoration: BoxDecoration(
                            color: context.cAccentReadable.withValues(
                              alpha: 0.10,
                            ),
                            borderRadius: BorderRadius.circular(
                              14,
                            ),
                          ),
                          child: Icon(
                            icon,
                            color: context.cAccentReadable,
                          ),
                        ),
                        const SizedBox(
                          width: 12,
                        ),
                        titleBlock,
                      ],
                    ),
                    const SizedBox(
                      height: 8,
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: onAction,
                        child: Text(
                          actionLabel,
                          style: TextStyle(
                            color: context.cAccentReadable,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              }

              return Row(
                children: [
                  Container(
                    height: 42,
                    width: 42,
                    decoration: BoxDecoration(
                      color: context.cAccentReadable.withValues(
                        alpha: 0.10,
                      ),
                      borderRadius: BorderRadius.circular(
                        14,
                      ),
                    ),
                    child: Icon(
                      icon,
                      color: context.cAccentReadable,
                    ),
                  ),
                  const SizedBox(
                    width: 12,
                  ),
                  titleBlock,
                  TextButton(
                    onPressed: onAction,
                    child: Text(
                      actionLabel,
                      style: TextStyle(
                        color: context.cAccentReadable,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(
            height: 16,
          ),
          child,
        ],
      ),
    );
  }
}

class _FormFeatureChip extends StatelessWidget {
  const _FormFeatureChip({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(
    BuildContext context,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 9,
        vertical: 7,
      ),
      decoration: BoxDecoration(
        color: context.cAccentReadable.withValues(
          alpha: 0.08,
        ),
        borderRadius: BorderRadius.circular(
          999,
        ),
        border: Border.all(
          color: context.cAccentReadable.withValues(
            alpha: 0.18,
          ),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 14,
            color: context.cAccentReadable,
          ),
          const SizedBox(
            width: 5,
          ),
          Text(
            label,
            style: TextStyle(
              color: context.cTextPrimary,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _AiBookingCard extends StatelessWidget {
  const _AiBookingCard({
    required this.patientName,
    required this.phone,
    required this.reason,
    required this.symptoms,
    required this.aiSummary,
    required this.recommendedDepartment,
    required this.suggestedDoctor,
    required this.urgency,
    required this.status,
    required this.confidence,
    required this.createdAt,
    required this.statusColor,
    required this.busy,
    required this.onConfirm,
    required this.onEmergency,
  });

  final String patientName;
  final String phone;
  final String reason;
  final String symptoms;
  final String aiSummary;
  final String recommendedDepartment;
  final String suggestedDoctor;
  final String urgency;
  final String status;
  final String? confidence;
  final String createdAt;
  final Color statusColor;
  final bool busy;
  final VoidCallback onConfirm;
  final VoidCallback onEmergency;

  bool get _isFinal {
    final value = status.toLowerCase();

    return value.contains(
          'confirmed',
        ) ||
        value.contains(
          'completed',
        ) ||
        value.contains(
          'cancelled',
        ) ||
        value.contains(
          'emergency_escalation',
        );
  }

  @override
  Widget build(
    BuildContext context,
  ) {
    return Container(
      margin: const EdgeInsets.only(
        bottom: 14,
      ),
      padding: const EdgeInsets.all(
        14,
      ),
      decoration: BoxDecoration(
        color: context.cBgPrimary,
        borderRadius: BorderRadius.circular(
          18,
        ),
        border: Border.all(
          color: statusColor.withValues(
            alpha: 0.22,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                height: 42,
                width: 42,
                decoration: BoxDecoration(
                  color: statusColor.withValues(
                    alpha: 0.10,
                  ),
                  borderRadius: BorderRadius.circular(
                    14,
                  ),
                ),
                child: Icon(
                  Icons.qr_code_scanner_rounded,
                  color: statusColor,
                ),
              ),
              const SizedBox(
                width: 12,
              ),
              Expanded(
                child: Text(
                  patientName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: context.cTextPrimary,
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                  ),
                ),
              ),
              const SizedBox(
                width: 8,
              ),
              _StatusPill(
                label: urgency,
                color: statusColor,
              ),
            ],
          ),
          const SizedBox(
            height: 12,
          ),
          _InfoLine(
            label: 'Phone',
            value: phone,
          ),
          _InfoLine(
            label: 'Reason',
            value: reason,
          ),
          _InfoLine(
            label: 'Symptoms',
            value: symptoms,
          ),
          _InfoLine(
            label: 'AI summary',
            value: aiSummary,
          ),
          _InfoLine(
            label: 'Department',
            value: recommendedDepartment,
          ),
          _InfoLine(
            label: 'Suggested doctor',
            value: suggestedDoctor,
          ),
          _InfoLine(
            label: 'Status',
            value: status,
          ),
          if (confidence != null)
            _InfoLine(
              label: 'AI confidence',
              value: confidence!,
            ),
          _InfoLine(
            label: 'Received',
            value: createdAt,
          ),
          const SizedBox(
            height: 12,
          ),
          LayoutBuilder(
            builder: (
              context,
              constraints,
            ) {
              final compact = constraints.maxWidth < 380;

              final emergencyButton = OutlinedButton.icon(
                onPressed: busy || _isFinal ? null : onEmergency,
                icon: const Icon(
                  Icons.emergency_rounded,
                ),
                label: const Text(
                  'Emergency',
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: CorviaColors.danger,
                  side: const BorderSide(
                    color: CorviaColors.danger,
                  ),
                ),
              );

              final confirmButton = ElevatedButton.icon(
                onPressed: busy || _isFinal ? null : onConfirm,
                icon: const Icon(
                  Icons.check_circle_rounded,
                ),
                label: const Text(
                  'Confirm',
                ),
              );

              if (compact) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    emergencyButton,
                    const SizedBox(
                      height: 10,
                    ),
                    confirmButton,
                  ],
                );
              }

              return Row(
                children: [
                  Expanded(
                    child: emergencyButton,
                  ),
                  const SizedBox(
                    width: 10,
                  ),
                  Expanded(
                    child: confirmButton,
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _DoctorRecord extends StatelessWidget {
  const _DoctorRecord({
    required this.name,
    required this.specialty,
    required this.department,
    required this.room,
    required this.location,
    required this.status,
    required this.color,
  });

  final String name;
  final String specialty;
  final String department;
  final String room;
  final String location;
  final String status;
  final Color color;

  @override
  Widget build(
    BuildContext context,
  ) {
    return Container(
      margin: const EdgeInsets.only(
        bottom: 10,
      ),
      padding: const EdgeInsets.all(
        12,
      ),
      decoration: BoxDecoration(
        color: context.cBgPrimary,
        borderRadius: BorderRadius.circular(
          16,
        ),
        border: Border.all(
          color: context.cDivider,
        ),
      ),
      child: LayoutBuilder(
        builder: (
          context,
          constraints,
        ) {
          final compact = constraints.maxWidth < 360;

          final text = Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: context.cTextPrimary,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(
                  height: 3,
                ),
                Text(
                  '$specialty • '
                  '$department',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: context.cTextSecondary,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(
                  height: 3,
                ),
                Text(
                  '$room • $location',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: context.cTextSecondary,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          );

          final icon = Container(
            height: 43,
            width: 43,
            decoration: BoxDecoration(
              color: color.withValues(
                alpha: 0.10,
              ),
              borderRadius: BorderRadius.circular(
                14,
              ),
            ),
            child: Icon(
              Icons.medical_services_rounded,
              color: color,
            ),
          );

          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    icon,
                    const SizedBox(
                      width: 12,
                    ),
                    text,
                  ],
                ),
                const SizedBox(
                  height: 10,
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: _StatusPill(
                    label: status,
                    color: color,
                  ),
                ),
              ],
            );
          }

          return Row(
            children: [
              icon,
              const SizedBox(
                width: 12,
              ),
              text,
              const SizedBox(
                width: 8,
              ),
              _StatusPill(
                label: status,
                color: color,
              ),
            ],
          );
        },
      ),
    );
  }
}

class _RecordTile extends StatelessWidget {
  const _RecordTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.trailing,
    required this.color,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String trailing;
  final Color color;

  @override
  Widget build(
    BuildContext context,
  ) {
    return Container(
      margin: const EdgeInsets.only(
        bottom: 10,
      ),
      padding: const EdgeInsets.all(
        12,
      ),
      decoration: BoxDecoration(
        color: context.cBgPrimary,
        borderRadius: BorderRadius.circular(
          16,
        ),
        border: Border.all(
          color: context.cDivider,
        ),
      ),
      child: LayoutBuilder(
        builder: (
          context,
          constraints,
        ) {
          final compact = constraints.maxWidth < 390;

          final details = Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: context.cTextPrimary,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(
                  height: 3,
                ),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: context.cTextSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          );

          final leading = Container(
            height: 39,
            width: 39,
            decoration: BoxDecoration(
              color: color.withValues(
                alpha: 0.10,
              ),
              borderRadius: BorderRadius.circular(
                13,
              ),
            ),
            child: Icon(
              icon,
              color: color,
            ),
          );

          final date = Text(
            trailing,
            maxLines: compact ? 1 : 2,
            overflow: TextOverflow.ellipsis,
            textAlign: compact ? TextAlign.left : TextAlign.right,
            style: TextStyle(
              color: context.cTextSecondary,
              fontSize: 11,
            ),
          );

          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    leading,
                    const SizedBox(
                      width: 12,
                    ),
                    details,
                  ],
                ),
                const SizedBox(
                  height: 8,
                ),
                Padding(
                  padding: const EdgeInsets.only(
                    left: 51,
                  ),
                  child: date,
                ),
              ],
            );
          }

          return Row(
            children: [
              leading,
              const SizedBox(
                width: 12,
              ),
              details,
              const SizedBox(
                width: 8,
              ),
              SizedBox(
                width: 100,
                child: date,
              ),
            ],
          );
        },
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.label,
    required this.color,
  });

  final String label;
  final Color color;

  @override
  Widget build(
    BuildContext context,
  ) {
    return ConstrainedBox(
      constraints: const BoxConstraints(
        maxWidth: 130,
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: 10,
          vertical: 6,
        ),
        decoration: BoxDecoration(
          color: color.withValues(
            alpha: 0.10,
          ),
          borderRadius: BorderRadius.circular(
            999,
          ),
          border: Border.all(
            color: color.withValues(
              alpha: 0.22,
            ),
          ),
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.w900,
            fontSize: 11,
          ),
        ),
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(
    BuildContext context,
  ) {
    return Padding(
      padding: const EdgeInsets.only(
        bottom: 6,
      ),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '$label: ',
              style: TextStyle(
                color: context.cTextPrimary,
                fontWeight: FontWeight.w900,
                fontSize: 12,
              ),
            ),
            TextSpan(
              text: value,
              style: TextStyle(
                color: context.cTextSecondary,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(
    BuildContext context,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: 18,
        vertical: 26,
      ),
      decoration: BoxDecoration(
        color: context.cBgPrimary,
        borderRadius: BorderRadius.circular(
          18,
        ),
        border: Border.all(
          color: context.cDivider,
        ),
      ),
      child: Column(
        children: [
          Icon(
            icon,
            color: context.cAccentReadable,
            size: 34,
          ),
          const SizedBox(
            height: 10,
          ),
          Text(
            title,
            style: TextStyle(
              color: context.cTextPrimary,
              fontWeight: FontWeight.w900,
              fontSize: 15,
            ),
          ),
          const SizedBox(
            height: 5,
          ),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: context.cTextSecondary,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}
