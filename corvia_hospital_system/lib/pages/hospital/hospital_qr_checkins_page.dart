import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../theme/app_theme.dart';

import 'hospital_ai_booking_queue_page.dart';

class HospitalQrCheckinsPage extends StatefulWidget {
  const HospitalQrCheckinsPage({super.key});

  @override
  State<HospitalQrCheckinsPage> createState() => _HospitalQrCheckinsPageState();
}

class _HospitalQrCheckinsPageState extends State<HospitalQrCheckinsPage> {
  final SupabaseClient _supabase = Supabase.instance.client;
  final TextEditingController _searchController = TextEditingController();
  Color get primary =>
      context.isDarkTheme ? context.cBgSecondary : context.cTextPrimary;
  Color get accent => CorviaColors.accent;
  Color get success => CorviaColors.success;
  Color get warning => CorviaColors.warning;
  Color get error => CorviaColors.danger;
  Color get background => context.cBgPrimary;
  Color get textDark => context.cTextPrimary;
  Color get mutedText => context.cTextMuted;
  Color get borderColor => context.cDivider;

  bool _loading = true;
  final bool _saving = false;
  String? _error;

  String? _hospitalId;
  String _hospitalName = 'Hospital QR Check-ins';
  String _selectedStatus = 'All';

  List<Map<String, dynamic>> _checkins = [];
  List<Map<String, dynamic>> _patients = [];
  List<Map<String, dynamic>> _doctors = [];
  List<Map<String, dynamic>> _departments = [];

  final Map<String, Map<String, dynamic>> _profilesByKey = {};

  @override
  void initState() {
    super.initState();
    _loadQrCheckinsPage();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadQrCheckinsPage() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      await _loadHospitalContext();
      await _loadHospitalData();
      await _loadProfiles();
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _loadHospitalContext() async {
    final user = _supabase.auth.currentUser;

    if (user == null) {
      throw Exception('You are not signed in.');
    }

    final adminLink = await _supabase
        .from('hospital_admins')
        .select('hospital_id, hospitals(name)')
        .eq('profile_id', user.id)
        .maybeSingle();

    if (adminLink == null) {
      throw Exception('This account is not linked to a hospital admin record.');
    }

    final hospitalId = adminLink['hospital_id']?.toString();

    if (hospitalId == null || hospitalId.trim().isEmpty) {
      throw Exception('No hospital is linked to this admin account.');
    }

    String hospitalName = 'Hospital QR Check-ins';
    final hospital = adminLink['hospitals'];

    if (hospital is Map && hospital['name'] != null) {
      hospitalName = hospital['name'].toString();
    }

    _hospitalId = hospitalId;
    _hospitalName = hospitalName;
  }

  Future<void> _loadHospitalData() async {
    final hospitalId = _hospitalId;

    if (hospitalId == null) {
      throw Exception('Hospital ID could not be found.');
    }

    final results = await Future.wait([
      _safeLoadCheckins(hospitalId),
      _safeLoadPatients(hospitalId),
      _safeLoadDoctors(hospitalId),
      _safeLoadDepartments(hospitalId),
    ]);

    _checkins = results[0];
    _patients = results[1];
    _doctors = results[2];
    _departments = results[3];
  }

  Future<List<Map<String, dynamic>>> _safeLoadCheckins(
    String hospitalId,
  ) async {
    try {
      final rows = await _supabase
          .from('reception_checkins')
          .select()
          .eq('hospital_id', hospitalId)
          .order('created_at', ascending: false)
          .limit(500);

      return _mapRows(rows);
    } catch (_) {
      try {
        final rows = await _supabase
            .from('reception_checkins')
            .select()
            .eq('hospital_id', hospitalId)
            .limit(500);

        return _mapRows(rows);
      } catch (e) {
        throw Exception('Could not load QR check-ins: $e');
      }
    }
  }

  Future<List<Map<String, dynamic>>> _safeLoadPatients(
    String hospitalId,
  ) async {
    try {
      final rows = await _supabase
          .from('patients')
          .select()
          .eq('hospital_id', hospitalId)
          .limit(500);

      return _mapRows(rows);
    } catch (_) {
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> _safeLoadDoctors(String hospitalId) async {
    try {
      final rows = await _supabase
          .from('doctors')
          .select()
          .eq('hospital_id', hospitalId)
          .order('created_at', ascending: false)
          .limit(500);

      return _mapRows(rows);
    } catch (_) {
      try {
        final rows = await _supabase
            .from('doctors')
            .select()
            .eq('hospital_id', hospitalId)
            .limit(500);

        return _mapRows(rows);
      } catch (_) {
        return [];
      }
    }
  }

  Future<List<Map<String, dynamic>>> _safeLoadDepartments(
    String hospitalId,
  ) async {
    try {
      final rows = await _supabase
          .from('departments')
          .select()
          .eq('hospital_id', hospitalId)
          .order('name', ascending: true);

      return _mapRows(rows);
    } catch (_) {
      return [];
    }
  }

  List<Map<String, dynamic>> _mapRows(dynamic rows) {
    if (rows is! List) return [];

    return rows
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
  }

  Future<void> _loadProfiles() async {
    _profilesByKey.clear();

    final profileKeys = <String>{};

    for (final patient in _patients) {
      final key = patient['profile_id'] ?? patient['user_id'];

      if (key != null && key.toString().isNotEmpty) {
        profileKeys.add(key.toString());
      }
    }

    for (final doctor in _doctors) {
      final key = doctor['profile_id'] ?? doctor['user_id'];

      if (key != null && key.toString().isNotEmpty) {
        profileKeys.add(key.toString());
      }
    }

    for (final checkin in _checkins) {
      final key = checkin['profile_id'] ?? checkin['user_id'];

      if (key != null && key.toString().isNotEmpty) {
        profileKeys.add(key.toString());
      }
    }

    if (profileKeys.isEmpty) return;

    final keys = profileKeys.toList();

    await _loadProfilesByColumn('id', keys);
    await _loadProfilesByColumn('user_id', keys);
  }

  Future<void> _loadProfilesByColumn(String column, List<String> keys) async {
    final selectOptions = [
      'id, user_id, first_name, surname, email, phone, phone_number, is_active',
      'id, user_id, first_name, surname, email, phone, is_active',
      'id, first_name, surname, email, phone',
    ];

    for (final selectText in selectOptions) {
      try {
        final rows = await _supabase
            .from('profiles')
            .select(selectText)
            .inFilter(column, keys);

        for (final row in rows.whereType<Map>()) {
          final profile = Map<String, dynamic>.from(row);

          final id = profile['id']?.toString();
          final userId = profile['user_id']?.toString();

          if (id != null && id.isNotEmpty) {
            _profilesByKey[id] = profile;
          }

          if (userId != null && userId.isNotEmpty) {
            _profilesByKey[userId] = profile;
          }
        }

        return;
      } catch (_) {
        continue;
      }
    }
  }

  Map<String, dynamic>? _profileFor(Map<String, dynamic> record) {
    final key = record['profile_id'] ?? record['user_id'];

    if (key == null) return null;

    return _profilesByKey[key.toString()];
  }

  Map<String, dynamic>? _patientById(dynamic patientId) {
    if (patientId == null) return null;

    for (final patient in _patients) {
      if (patient['id']?.toString() == patientId.toString()) {
        return patient;
      }
    }

    return null;
  }

  Map<String, dynamic>? _doctorById(dynamic doctorId) {
    if (doctorId == null) return null;

    for (final doctor in _doctors) {
      if (doctor['id']?.toString() == doctorId.toString()) {
        return doctor;
      }
    }

    return null;
  }

  String _patientNameForCheckin(Map<String, dynamic> checkin) {
    final directName =
        checkin['patient_name'] ??
        checkin['full_name'] ??
        checkin['name'] ??
        checkin['display_name'];

    if (directName != null && directName.toString().trim().isNotEmpty) {
      return directName.toString();
    }

    final patient = _patientById(checkin['patient_id']);

    if (patient != null) {
      final patientDirectName =
          patient['full_name'] ??
          patient['patient_name'] ??
          patient['name'] ??
          patient['display_name'];

      if (patientDirectName != null &&
          patientDirectName.toString().trim().isNotEmpty) {
        return patientDirectName.toString();
      }

      final patientProfile = _profileFor(patient);
      final firstName =
          patient['first_name'] ?? patientProfile?['first_name'] ?? '';
      final surname =
          patient['surname'] ??
          patient['last_name'] ??
          patientProfile?['surname'] ??
          '';

      final fullName = '$firstName $surname'.trim();

      if (fullName.isNotEmpty) {
        return fullName;
      }
    }

    final checkinProfile = _profileFor(checkin);

    if (checkinProfile != null) {
      final firstName = checkinProfile['first_name']?.toString() ?? '';
      final surname = checkinProfile['surname']?.toString() ?? '';
      final fullName = '$firstName $surname'.trim();

      if (fullName.isNotEmpty) {
        return fullName;
      }
    }

    final id = checkin['id']?.toString();

    if (id != null && id.length >= 8) {
      return 'QR Patient ${id.substring(0, 8)}';
    }

    return 'QR Patient';
  }

  String _patientPhoneForCheckin(Map<String, dynamic> checkin) {
    final directPhone =
        checkin['phone'] ??
        checkin['patient_phone'] ??
        checkin['phone_number'] ??
        checkin['contact_number'];

    if (directPhone != null && directPhone.toString().trim().isNotEmpty) {
      return directPhone.toString();
    }

    final patient = _patientById(checkin['patient_id']);

    if (patient != null) {
      final profile = _profileFor(patient);

      final phone =
          patient['phone'] ??
          patient['phone_number'] ??
          profile?['phone'] ??
          profile?['phone_number'];

      if (phone != null && phone.toString().trim().isNotEmpty) {
        return phone.toString();
      }
    }

    final checkinProfile = _profileFor(checkin);

    final profilePhone =
        checkinProfile?['phone'] ?? checkinProfile?['phone_number'];

    if (profilePhone != null && profilePhone.toString().trim().isNotEmpty) {
      return profilePhone.toString();
    }

    return 'No phone linked';
  }

  String _doctorNameById(dynamic doctorId) {
    final doctor = _doctorById(doctorId);

    if (doctor == null) {
      return 'No doctor assigned';
    }

    final profile = _profileFor(doctor);
    final firstName = profile?['first_name']?.toString() ?? '';
    final surname = profile?['surname']?.toString() ?? '';
    final fullName = '$firstName $surname'.trim();

    if (fullName.isNotEmpty) {
      return 'Dr $fullName';
    }

    final directName =
        doctor['doctor_name'] ??
        doctor['full_name'] ??
        doctor['name'] ??
        doctor['display_name'];

    if (directName != null && directName.toString().trim().isNotEmpty) {
      return directName.toString();
    }

    final doctorIdText = doctor['id']?.toString() ?? '';

    if (doctorIdText.length >= 8) {
      return 'Doctor ${doctorIdText.substring(0, 8)}';
    }

    return 'Doctor';
  }

  String _departmentNameById(dynamic departmentId) {
    if (departmentId == null) {
      return 'No department assigned';
    }

    for (final department in _departments) {
      if (department['id']?.toString() == departmentId.toString()) {
        return department['name']?.toString() ?? 'Department linked';
      }
    }

    return 'Department linked';
  }

  String _checkinDepartment(Map<String, dynamic> checkin) {
    final directDepartment =
        checkin['department'] ??
        checkin['department_name'] ??
        checkin['requested_department'];

    if (directDepartment != null &&
        directDepartment.toString().trim().isNotEmpty) {
      return directDepartment.toString();
    }

    return _departmentNameById(checkin['department_id']);
  }

  String _checkinDoctor(Map<String, dynamic> checkin) {
    final directDoctor =
        checkin['doctor_name'] ?? checkin['assigned_doctor_name'];

    if (directDoctor != null && directDoctor.toString().trim().isNotEmpty) {
      return directDoctor.toString();
    }

    return _doctorNameById(
      checkin['assigned_doctor_id'] ?? checkin['doctor_id'],
    );
  }

  String _checkinReason(Map<String, dynamic> checkin) {
    final value =
        checkin['reason'] ??
        checkin['checkin_reason'] ??
        checkin['symptoms'] ??
        checkin['main_complaint'] ??
        checkin['chief_complaint'] ??
        checkin['notes'];

    if (value != null && value.toString().trim().isNotEmpty) {
      return value.toString();
    }

    return 'No reason captured';
  }

  String _checkinUrgency(Map<String, dynamic> checkin) {
    final value =
        checkin['urgency'] ??
        checkin['urgency_level'] ??
        checkin['priority'] ??
        'normal';

    return value.toString();
  }

  String _normaliseStatus(dynamic value) {
    final raw = value?.toString() ?? 'waiting';

    final status = raw
        .trim()
        .toLowerCase()
        .replaceAll(' ', '_')
        .replaceAll('-', '_');

    const validStatuses = [
      'waiting',
      'assigned',
      'booked',
      'in_consultation',
      'completed',
      'cancelled',
      'emergency_escalation',
    ];

    return validStatuses.contains(status) ? status : 'waiting';
  }

  String _checkinStatus(Map<String, dynamic> checkin) {
    return _normaliseStatus(
      checkin['queue_status'] ?? checkin['checkin_status'] ?? checkin['status'],
    );
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'waiting':
        return 'Waiting';
      case 'assigned':
        return 'Assigned';
      case 'booked':
        return 'Booked';
      case 'in_consultation':
        return 'In Consultation';
      case 'completed':
        return 'Completed';
      case 'cancelled':
        return 'Cancelled';
      case 'emergency_escalation':
        return 'Emergency';
      default:
        return 'Waiting';
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'completed':
      case 'booked':
        return success;
      case 'assigned':
      case 'in_consultation':
        return accent;
      case 'cancelled':
      case 'emergency_escalation':
        return error;
      case 'waiting':
      default:
        return warning;
    }
  }

  IconData _statusIcon(String status) {
    switch (status) {
      case 'assigned':
        return Icons.assignment_ind_rounded;
      case 'booked':
        return Icons.event_available_rounded;
      case 'in_consultation':
        return Icons.medical_services_rounded;
      case 'completed':
        return Icons.check_circle_rounded;
      case 'cancelled':
        return Icons.cancel_rounded;
      case 'emergency_escalation':
        return Icons.emergency_rounded;
      case 'waiting':
      default:
        return Icons.qr_code_scanner_rounded;
    }
  }

  Color _urgencyColor(String urgency) {
    final value = urgency.toLowerCase();

    if (value.contains('emergency') ||
        value.contains('critical') ||
        value.contains('urgent')) {
      return error;
    }

    if (value.contains('high') || value.contains('medium')) {
      return warning;
    }

    return accent;
  }

  DateTime _createdDate(Map<String, dynamic> checkin) {
    final value =
        checkin['created_at'] ??
        checkin['checked_in_at'] ??
        checkin['updated_at'];

    final parsed = DateTime.tryParse(value?.toString() ?? '');

    return parsed?.toLocal() ?? DateTime.now();
  }

  String _formatDateTime(DateTime dateTime) {
    final day = dateTime.day.toString().padLeft(2, '0');
    final month = dateTime.month.toString().padLeft(2, '0');
    final year = dateTime.year;
    final hour = dateTime.hour.toString().padLeft(2, '0');
    final minute = dateTime.minute.toString().padLeft(2, '0');

    return '$day/$month/$year • $hour:$minute';
  }

  List<Map<String, dynamic>> get _visibleCheckins {
    final search = _searchController.text.trim().toLowerCase();

    return _checkins.where((checkin) {
      final patientName = _patientNameForCheckin(checkin).toLowerCase();
      final phone = _patientPhoneForCheckin(checkin).toLowerCase();
      final reason = _checkinReason(checkin).toLowerCase();
      final department = _checkinDepartment(checkin).toLowerCase();
      final doctor = _checkinDoctor(checkin).toLowerCase();
      final status = _checkinStatus(checkin);

      final matchesSearch =
          search.isEmpty ||
          patientName.contains(search) ||
          phone.contains(search) ||
          reason.contains(search) ||
          department.contains(search) ||
          doctor.contains(search) ||
          status.contains(search);

      final matchesStatus =
          _selectedStatus == 'All' || status == _selectedStatus;

      return matchesSearch && matchesStatus;
    }).toList();
  }

  int _countByStatus(String status) {
    return _checkins
        .where((checkin) => _checkinStatus(checkin) == status)
        .length;
  }

  int get _activeQueueCount {
    return _checkins.where((checkin) {
      final status = _checkinStatus(checkin);
      return status == 'waiting' ||
          status == 'assigned' ||
          status == 'booked' ||
          status == 'in_consultation' ||
          status == 'emergency_escalation';
    }).length;
  }

  void _showSnack(String message, {bool isError = false}) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? error : primary,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _updateCheckin({
    required String checkinId,
    required String status,
    required String doctorId,
    required String departmentId,
    required String notes,
  }) async {
    final hospitalId = _hospitalId;

    if (hospitalId == null) {
      throw Exception('Hospital ID is missing.');
    }

    final selectedDoctorId = doctorId == '__none__' ? null : doctorId;
    final selectedDepartmentId = departmentId == '__none__'
        ? null
        : departmentId;

    final nowIso = DateTime.now().toUtc().toIso8601String();

    final fullPayload = <String, dynamic>{
      'queue_status': status,
      'checkin_status': status,
      'status': status,
      'assigned_doctor_id': selectedDoctorId,
      'doctor_id': selectedDoctorId,
      'department_id': selectedDepartmentId,
      'department': selectedDepartmentId == null
          ? null
          : _departmentNameById(selectedDepartmentId),
      'reception_notes': notes.trim().isEmpty ? null : notes.trim(),
      'notes': notes.trim().isEmpty ? null : notes.trim(),
      'updated_at': nowIso,
    };

    final payloadOptions = [
      fullPayload,
      <String, dynamic>{
        'queue_status': status,
        'assigned_doctor_id': selectedDoctorId,
        'department_id': selectedDepartmentId,
        'reception_notes': notes.trim().isEmpty ? null : notes.trim(),
        'updated_at': nowIso,
      },
      <String, dynamic>{
        'checkin_status': status,
        'assigned_doctor_id': selectedDoctorId,
        'department_id': selectedDepartmentId,
        'reception_notes': notes.trim().isEmpty ? null : notes.trim(),
        'updated_at': nowIso,
      },
      <String, dynamic>{
        'queue_status': status,
        'department_id': selectedDepartmentId,
        'assigned_doctor_id': selectedDoctorId,
        'updated_at': nowIso,
      },
      <String, dynamic>{
        'status': status,
        'department_id': selectedDepartmentId,
        'doctor_id': selectedDoctorId,
        'notes': notes.trim().isEmpty ? null : notes.trim(),
        'updated_at': nowIso,
      },
    ];

    Object? lastError;

    for (final payload in payloadOptions) {
      try {
        await _supabase
            .from('reception_checkins')
            .update(payload)
            .eq('id', checkinId)
            .eq('hospital_id', hospitalId);

        return;
      } catch (e) {
        lastError = e;
      }
    }

    throw Exception(lastError ?? 'Could not update check-in.');
  }

  Future<void> _showCheckinEditor(Map<String, dynamic> checkin) async {
    final checkinId = checkin['id']?.toString();

    if (checkinId == null || checkinId.isEmpty) {
      _showSnack('This check-in does not have a valid ID.', isError: true);
      return;
    }

    String selectedStatus = _checkinStatus(checkin);
    String selectedDoctorId =
        (checkin['assigned_doctor_id'] ?? checkin['doctor_id'])?.toString() ??
        '__none__';
    String selectedDepartmentId =
        checkin['department_id']?.toString() ?? '__none__';

    final notesController = TextEditingController(
      text: (checkin['reception_notes'] ?? checkin['notes'] ?? '').toString(),
    );

    final doctorIds = _doctors
        .map((doctor) => doctor['id']?.toString())
        .whereType<String>()
        .toSet();

    final departmentIds = _departments
        .map((department) => department['id']?.toString())
        .whereType<String>()
        .toSet();

    if (selectedDoctorId != '__none__' &&
        !doctorIds.contains(selectedDoctorId)) {
      selectedDoctorId = '__current_doctor__';
    }

    if (selectedDepartmentId != '__none__' &&
        !departmentIds.contains(selectedDepartmentId)) {
      selectedDepartmentId = '__current_department__';
    }

    bool modalSaving = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
              ),
              child: Container(
                constraints: const BoxConstraints(maxHeight: 720),
                padding: const EdgeInsets.fromLTRB(22, 22, 22, 28),
                decoration: BoxDecoration(
                  color: context.cBgSecondary,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Manage QR Check-in',
                        style: TextStyle(
                          color: textDark,
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${_patientNameForCheckin(checkin)} • ${_patientPhoneForCheckin(checkin)}',
                        style: TextStyle(color: mutedText, fontSize: 13),
                      ),
                      const SizedBox(height: 22),
                      DropdownButtonFormField<String>(
                        initialValue: selectedStatus,
                        decoration: const InputDecoration(
                          labelText: 'Queue status',
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'waiting',
                            child: Text('Waiting'),
                          ),
                          DropdownMenuItem(
                            value: 'assigned',
                            child: Text('Assigned'),
                          ),
                          DropdownMenuItem(
                            value: 'booked',
                            child: Text('Booked'),
                          ),
                          DropdownMenuItem(
                            value: 'in_consultation',
                            child: Text('In Consultation'),
                          ),
                          DropdownMenuItem(
                            value: 'completed',
                            child: Text('Completed'),
                          ),
                          DropdownMenuItem(
                            value: 'cancelled',
                            child: Text('Cancelled'),
                          ),
                          DropdownMenuItem(
                            value: 'emergency_escalation',
                            child: Text('Emergency Escalation'),
                          ),
                        ],
                        onChanged: modalSaving
                            ? null
                            : (value) {
                                if (value == null) return;
                                setModalState(() {
                                  selectedStatus = value;
                                });
                              },
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        initialValue: selectedDepartmentId,
                        decoration: const InputDecoration(
                          labelText: 'Department',
                          border: OutlineInputBorder(),
                        ),
                        items: [
                          const DropdownMenuItem(
                            value: '__none__',
                            child: Text('No department assigned'),
                          ),
                          if (selectedDepartmentId == '__current_department__')
                            const DropdownMenuItem(
                              value: '__current_department__',
                              child: Text('Current department'),
                            ),
                          ..._departments.map(
                            (department) => DropdownMenuItem(
                              value: department['id']?.toString() ?? '',
                              child: Text(
                                department['name']?.toString() ?? 'Department',
                              ),
                            ),
                          ),
                        ],
                        onChanged: modalSaving
                            ? null
                            : (value) {
                                if (value == null) return;
                                setModalState(() {
                                  selectedDepartmentId = value;
                                });
                              },
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        initialValue: selectedDoctorId,
                        decoration: const InputDecoration(
                          labelText: 'Assigned doctor',
                          border: OutlineInputBorder(),
                        ),
                        items: [
                          const DropdownMenuItem(
                            value: '__none__',
                            child: Text('No doctor assigned'),
                          ),
                          if (selectedDoctorId == '__current_doctor__')
                            const DropdownMenuItem(
                              value: '__current_doctor__',
                              child: Text('Current doctor'),
                            ),
                          ..._doctors.map(
                            (doctor) => DropdownMenuItem(
                              value: doctor['id']?.toString() ?? '',
                              child: Text(
                                '${_doctorNameById(doctor['id'])} • ${doctor['specialization'] ?? 'General Practitioner'}',
                              ),
                            ),
                          ),
                        ],
                        onChanged: modalSaving
                            ? null
                            : (value) {
                                if (value == null) return;
                                setModalState(() {
                                  selectedDoctorId = value;
                                });
                              },
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: notesController,
                        enabled: !modalSaving,
                        maxLines: 4,
                        decoration: const InputDecoration(
                          labelText: 'Reception notes',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: modalSaving
                              ? null
                              : () async {
                                  final doctorValue =
                                      selectedDoctorId == '__current_doctor__'
                                      ? ((checkin['assigned_doctor_id'] ??
                                                checkin['doctor_id'])
                                            ?.toString())
                                      : selectedDoctorId;

                                  final departmentValue =
                                      selectedDepartmentId ==
                                          '__current_department__'
                                      ? checkin['department_id']?.toString()
                                      : selectedDepartmentId;

                                  setModalState(() {
                                    modalSaving = true;
                                  });

                                  try {
                                    await _updateCheckin(
                                      checkinId: checkinId,
                                      status: selectedStatus,
                                      doctorId: doctorValue ?? '__none__',
                                      departmentId:
                                          departmentValue ?? '__none__',
                                      notes: notesController.text,
                                    );

                                    if (sheetContext.mounted) {
                                      Navigator.of(sheetContext).pop();
                                    }

                                    await _loadQrCheckinsPage();

                                    _showSnack(
                                      'QR check-in updated successfully.',
                                    );
                                  } catch (e) {
                                    if (sheetContext.mounted) {
                                      setModalState(() {
                                        modalSaving = false;
                                      });
                                    }

                                    _showSnack(
                                      'Could not update QR check-in: $e',
                                      isError: true,
                                    );
                                  }
                                },
                          icon: modalSaving
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  ),
                                )
                              : Icon(Icons.save_rounded),
                          label: Text(
                            modalSaving
                                ? 'Saving...'
                                : 'Save QR check-in changes',
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: primary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 15),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    notesController.dispose();
  }

  void _openAiBookingQueue() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const HospitalAiBookingQueuePage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final checkins = _visibleCheckins;

    return Scaffold(
      backgroundColor: background,
      body: SafeArea(
        child: RefreshIndicator(
          color: accent,
          onRefresh: _loadQrCheckinsPage,
          child: _loading
              ? Center(child: CircularProgressIndicator(color: accent))
              : SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildHeader(),
                      const SizedBox(height: 22),
                      if (_error != null) _buildErrorBox(),
                      _buildStats(),
                      const SizedBox(height: 22),
                      _buildCheckinDirectory(checkins),
                    ],
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        IconButton(
          tooltip: 'Back to hospital dashboard',
          onPressed: () => Navigator.of(context).maybePop(),
          icon: Icon(Icons.arrow_back_rounded),
          color: primary,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'QR Check-ins • $_hospitalName',
                style: TextStyle(
                  color: textDark,
                  fontSize: 27,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                'Manage scanned patients, reception queue, departments and doctor assignment.',
                style: TextStyle(color: mutedText, fontSize: 14),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        OutlinedButton.icon(
          onPressed: _loadQrCheckinsPage,
          icon: Icon(Icons.refresh_rounded),
          label: Text('Refresh'),
          style: OutlinedButton.styleFrom(
            foregroundColor: primary,
            side: BorderSide(color: borderColor),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          ),
        ),
      ],
    );
  }

  Widget _buildErrorBox() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 18),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: error.withValues(alpha: 0.18)),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline_rounded, color: error),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Could not load all QR check-in details. $_error',
              style: TextStyle(color: textDark, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStats() {
    final stats = [
      _QrStat(
        title: 'Total Check-ins',
        value: _checkins.length.toString(),
        subtitle: 'All reception and QR records',
        icon: Icons.qr_code_scanner_rounded,
        color: accent,
      ),
      _QrStat(
        title: 'Waiting',
        value: _countByStatus('waiting').toString(),
        subtitle: 'Patients still waiting',
        icon: Icons.pending_actions_rounded,
        color: warning,
      ),
      _QrStat(
        title: 'Assigned / Booked',
        value: (_countByStatus('assigned') + _countByStatus('booked'))
            .toString(),
        subtitle: 'Department or doctor assigned',
        icon: Icons.assignment_ind_rounded,
        color: success,
      ),
      _QrStat(
        title: 'Emergency',
        value: _countByStatus('emergency_escalation').toString(),
        subtitle: 'Escalated check-ins',
        icon: Icons.emergency_rounded,
        color: error,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 1000;

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: stats.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: isWide ? 4 : 2,
            mainAxisExtent: 165,
            mainAxisSpacing: 14,
            crossAxisSpacing: 14,
          ),
          itemBuilder: (context, index) {
            final stat = stats[index];

            return Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: context.cBgSecondary,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: borderColor),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    height: 42,
                    width: 42,
                    decoration: BoxDecoration(
                      color: stat.color.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(stat.icon, color: stat.color),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        stat.value,
                        style: TextStyle(
                          color: textDark,
                          fontSize: 25,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        stat.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: textDark,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        stat.subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: mutedText, fontSize: 12),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildCheckinDirectory(List<Map<String, dynamic>> checkins) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: context.cBgSecondary,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.qr_code_scanner_rounded, color: accent),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Hospital QR Check-in Directory',
                  style: TextStyle(
                    color: primary,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: _openAiBookingQueue,
                icon: Icon(Icons.auto_awesome_rounded, size: 18),
                label: Text('AI Queue'),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            '${checkins.length} check-in(s) currently shown • $_activeQueueCount active queue item(s)',
            style: TextStyle(color: mutedText, fontSize: 13),
          ),
          const SizedBox(height: 18),
          TextField(
            controller: _searchController,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: 'Search patient, phone, reason, department or doctor',
              prefixIcon: Icon(Icons.search_rounded, color: accent),
              suffixIcon: _searchController.text.isEmpty
                  ? null
                  : IconButton(
                      onPressed: () {
                        _searchController.clear();
                        setState(() {});
                      },
                      icon: Icon(Icons.clear_rounded),
                    ),
              filled: true,
              fillColor: background,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(15),
                borderSide: BorderSide(color: borderColor),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(15),
                borderSide: BorderSide(color: borderColor),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(15),
                borderSide: BorderSide(color: accent, width: 1.5),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children:
                const [
                  _StatusFilter(label: 'All', value: 'All'),
                  _StatusFilter(label: 'Waiting', value: 'waiting'),
                  _StatusFilter(label: 'Assigned', value: 'assigned'),
                  _StatusFilter(label: 'Booked', value: 'booked'),
                  _StatusFilter(
                    label: 'In Consultation',
                    value: 'in_consultation',
                  ),
                  _StatusFilter(
                    label: 'Emergency',
                    value: 'emergency_escalation',
                  ),
                  _StatusFilter(label: 'Completed', value: 'completed'),
                  _StatusFilter(label: 'Cancelled', value: 'cancelled'),
                ].map((filter) {
                  return ChoiceChip(
                    label: Text(filter.label),
                    selected: _selectedStatus == filter.value,
                    selectedColor: accent.withValues(alpha: 0.13),
                    onSelected: (_) {
                      setState(() {
                        _selectedStatus = filter.value;
                      });
                    },
                  );
                }).toList(),
          ),
          const SizedBox(height: 20),
          if (checkins.isEmpty)
            _buildEmptyState()
          else
            ...checkins.map(_buildCheckinCard),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 42, horizontal: 20),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        children: [
          Icon(Icons.qr_code_scanner_rounded, color: accent, size: 42),
          SizedBox(height: 12),
          Text(
            'No QR check-ins found',
            style: TextStyle(
              color: primary,
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
          SizedBox(height: 6),
          Text(
            'QR and reception check-ins will appear here when patients scan in or reception creates a queue record.',
            textAlign: TextAlign.center,
            style: TextStyle(color: mutedText, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildCheckinCard(Map<String, dynamic> checkin) {
    final status = _checkinStatus(checkin);
    final statusColor = _statusColor(status);
    final patientName = _patientNameForCheckin(checkin);
    final phone = _patientPhoneForCheckin(checkin);
    final reason = _checkinReason(checkin);
    final urgency = _checkinUrgency(checkin);
    final department = _checkinDepartment(checkin);
    final doctor = _checkinDoctor(checkin);
    final created = _createdDate(checkin);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: status == 'emergency_escalation'
              ? error.withValues(alpha: 0.30)
              : borderColor,
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 780;

          final information = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                patientName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: textDark,
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                phone,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: mutedText,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _QrPill(
                    icon: Icons.access_time_rounded,
                    label: _formatDateTime(created),
                    color: accent,
                  ),
                  _QrPill(
                    icon: Icons.local_hospital_rounded,
                    label: department,
                    color: primary,
                  ),
                  _QrPill(
                    icon: Icons.medical_services_rounded,
                    label: doctor,
                    color: success,
                  ),
                  _QrPill(
                    icon: Icons.priority_high_rounded,
                    label: urgency,
                    color: _urgencyColor(urgency),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                reason,
                style: TextStyle(
                  color: textDark,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          );

          final manageButton = OutlinedButton.icon(
            onPressed: _saving ? null : () => _showCheckinEditor(checkin),
            icon: Icon(Icons.edit_rounded, size: 18),
            label: Text('Manage'),
            style: OutlinedButton.styleFrom(
              foregroundColor: primary,
              side: BorderSide(color: borderColor),
            ),
          );

          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      height: 50,
                      width: 50,
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Icon(_statusIcon(status), color: statusColor),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: information),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _QrPill(
                      icon: _statusIcon(status),
                      label: _statusLabel(status),
                      color: statusColor,
                    ),
                    const Spacer(),
                    manageButton,
                  ],
                ),
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: 50,
                width: 50,
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(_statusIcon(status), color: statusColor),
              ),
              const SizedBox(width: 14),
              Expanded(child: information),
              const SizedBox(width: 14),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _QrPill(
                    icon: _statusIcon(status),
                    label: _statusLabel(status),
                    color: statusColor,
                  ),
                  const SizedBox(height: 14),
                  manageButton,
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class _QrStat {
  final String title;
  final String value;
  final String subtitle;
  final IconData icon;
  final Color color;

  const _QrStat({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.icon,
    required this.color,
  });
}

class _StatusFilter {
  final String label;
  final String value;

  const _StatusFilter({required this.label, required this.value});
}

class _QrPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _QrPill({required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 260),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.20)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
