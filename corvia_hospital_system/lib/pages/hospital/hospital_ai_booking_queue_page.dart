import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../theme/app_theme.dart';

class HospitalAiBookingQueuePage extends StatefulWidget {
  const HospitalAiBookingQueuePage({super.key, this.onBack});

  final VoidCallback? onBack;

  @override
  State<HospitalAiBookingQueuePage> createState() =>
      _HospitalAiBookingQueuePageState();
}

class _HospitalAiBookingQueuePageState
    extends State<HospitalAiBookingQueuePage> {
  final SupabaseClient _supabase = Supabase.instance.client;
  final TextEditingController _searchController = TextEditingController();
  Color get primary => context.cAccentReadable;
  Color get accent => CorviaColors.accent;
  Color get success => CorviaColors.success;
  Color get warning => CorviaColors.warning;
  Color get error => CorviaColors.danger;
  Color get background => context.cBgPrimary;
  Color get textDark => context.cTextPrimary;
  Color get mutedText => context.cTextMuted;

  bool _loading = true;
  bool _actionBusy = false;
  String? _error;

  String? _hospitalId;
  String _hospitalName = 'AI Booking Queue';
  String _selectedFilter = 'All';

  List<Map<String, dynamic>> _bookings = [];
  List<Map<String, dynamic>> _patients = [];
  List<Map<String, dynamic>> _doctors = [];
  List<Map<String, dynamic>> _departments = [];

  final Map<String, Map<String, dynamic>> _profilesByKey = {};

  @override
  void initState() {
    super.initState();
    _loadPage();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadPage() async {
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

    String hospitalName = 'AI Booking Queue';
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
      _loadBookings(hospitalId),
      _loadPatients(hospitalId),
      _loadDoctors(hospitalId),
      _loadDepartments(hospitalId),
    ]);

    _bookings = results[0];
    _patients = results[1];
    _doctors = results[2];
    _departments = results[3];
  }

  Future<List<Map<String, dynamic>>> _loadBookings(String hospitalId) async {
    try {
      final rows = await _supabase
          .from('hospital_ai_booking_requests')
          .select()
          .eq('hospital_id', hospitalId)
          .order('created_at', ascending: false)
          .limit(500);

      return _mapRows(rows);
    } catch (_) {
      final rows = await _supabase
          .from('hospital_ai_booking_requests')
          .select()
          .eq('hospital_id', hospitalId)
          .limit(500);

      return _mapRows(rows);
    }
  }

  Future<List<Map<String, dynamic>>> _loadPatients(String hospitalId) async {
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

  Future<List<Map<String, dynamic>>> _loadDoctors(String hospitalId) async {
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

  Future<List<Map<String, dynamic>>> _loadDepartments(String hospitalId) async {
    try {
      final rows = await _supabase
          .from('departments')
          .select()
          .eq('hospital_id', hospitalId)
          .eq('is_active', true)
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

    if (profileKeys.isEmpty) return;

    final keys = profileKeys.toList();

    await _loadProfilesByColumn('id', keys);
    await _loadProfilesByColumn('user_id', keys);
  }

  Future<void> _loadProfilesByColumn(String column, List<String> keys) async {
    try {
      final rows = await _supabase
          .from('profiles')
          .select(
            'id, user_id, first_name, surname, email, phone, phone_number, id_number',
          )
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
    } catch (_) {
      // Booking queue can still show without profile names.
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

  String _patientName(Map<String, dynamic> booking) {
    final directName =
        booking['patient_name'] ?? booking['full_name'] ?? booking['name'];

    if (directName != null && directName.toString().trim().isNotEmpty) {
      return directName.toString();
    }

    final patient = _patientById(booking['patient_id']);

    if (patient == null) {
      return 'QR scanned patient';
    }

    final patientName =
        patient['full_name'] ?? patient['patient_name'] ?? patient['name'];

    if (patientName != null && patientName.toString().trim().isNotEmpty) {
      return patientName.toString();
    }

    final profile = _profileFor(patient);

    final firstName = patient['first_name'] ?? profile?['first_name'] ?? '';
    final surname =
        patient['surname'] ?? patient['last_name'] ?? profile?['surname'] ?? '';

    final fullName = '$firstName $surname'.trim();

    if (fullName.isNotEmpty) {
      return fullName;
    }

    return 'Corvia Patient';
  }

  String _patientPhone(Map<String, dynamic> booking) {
    final phone =
        booking['patient_phone'] ?? booking['phone'] ?? booking['phone_number'];

    if (phone != null && phone.toString().trim().isNotEmpty) {
      return phone.toString();
    }

    final patient = _patientById(booking['patient_id']);
    final profile = patient == null ? null : _profileFor(patient);

    final patientPhone = patient?['phone'] ??
        patient?['phone_number'] ??
        profile?['phone'] ??
        profile?['phone_number'];

    if (patientPhone != null && patientPhone.toString().trim().isNotEmpty) {
      return patientPhone.toString();
    }

    return 'No phone number';
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

    return 'Assigned doctor';
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

  String _normaliseStatus(dynamic value) {
    final raw = value?.toString() ?? 'new';

    final status =
        raw.trim().toLowerCase().replaceAll(' ', '_').replaceAll('-', '_');

    if (status.contains('emergency') || status.contains('critical')) {
      return 'emergency_escalation';
    }

    if (status.contains('confirm')) {
      return 'confirmed';
    }

    if (status.contains('cancel')) {
      return 'cancelled';
    }

    if (status.contains('complete')) {
      return 'completed';
    }

    if (status.contains('review')) {
      return 'reviewing';
    }

    return status == 'new' ? 'new' : 'new';
  }

  String _bookingStatus(Map<String, dynamic> booking) {
    return _normaliseStatus(booking['status']);
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'new':
        return 'New';
      case 'reviewing':
        return 'Reviewing';
      case 'confirmed':
        return 'Confirmed';
      case 'completed':
        return 'Completed';
      case 'cancelled':
        return 'Cancelled';
      case 'emergency_escalation':
        return 'Emergency';
      default:
        return 'New';
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'new':
      case 'reviewing':
        return warning;
      case 'confirmed':
      case 'completed':
        return success;
      case 'cancelled':
      case 'emergency_escalation':
        return error;
      default:
        return accent;
    }
  }

  String _urgency(Map<String, dynamic> booking) {
    return booking['ai_urgency']?.toString() ??
        booking['urgency']?.toString() ??
        booking['urgency_level']?.toString() ??
        'normal';
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

  String _reason(Map<String, dynamic> booking) {
    return booking['reason']?.toString() ??
        booking['symptoms']?.toString() ??
        booking['chief_complaint']?.toString() ??
        'No reason captured';
  }

  String _summary(Map<String, dynamic> booking) {
    return booking['ai_summary']?.toString() ??
        booking['summary']?.toString() ??
        booking['ai_notes']?.toString() ??
        'No AI summary available.';
  }

  String _recommendedDepartment(Map<String, dynamic> booking) {
    final recommendation = booking['ai_recommended_department']?.toString();

    if (recommendation != null && recommendation.trim().isNotEmpty) {
      return recommendation;
    }

    return _departmentNameById(booking['requested_department_id']);
  }

  String _formatDateTime(dynamic value) {
    if (value == null) return 'Unknown time';

    final date = DateTime.tryParse(value.toString());

    if (date == null) {
      return value.toString();
    }

    final local = date.toLocal();

    final day = local.day.toString().padLeft(2, '0');
    final month = local.month.toString().padLeft(2, '0');
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');

    return '$day/$month/${local.year} • $hour:$minute';
  }

  Map<String, dynamic>? _findBestDoctor(dynamic departmentId) {
    final activeDoctors = _doctors.where((doctor) {
      return doctor['is_active'] != false;
    }).toList();

    final availableDoctors = activeDoctors.where((doctor) {
      final status = doctor['status']?.toString().toLowerCase() ?? '';
      return status.isEmpty || status == 'available';
    }).toList();

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

  List<Map<String, dynamic>> get _visibleBookings {
    final search = _searchController.text.trim().toLowerCase();

    return _bookings.where((booking) {
      final patient = _patientName(booking).toLowerCase();
      final phone = _patientPhone(booking).toLowerCase();
      final reason = _reason(booking).toLowerCase();
      final summary = _summary(booking).toLowerCase();
      final department = _recommendedDepartment(booking).toLowerCase();
      final doctor = _doctorNameById(
        booking['assigned_doctor_id'],
      ).toLowerCase();
      final status = _bookingStatus(booking);

      final matchesSearch = search.isEmpty ||
          patient.contains(search) ||
          phone.contains(search) ||
          reason.contains(search) ||
          summary.contains(search) ||
          department.contains(search) ||
          doctor.contains(search);

      final matchesFilter =
          _selectedFilter == 'All' || status == _selectedFilter;

      return matchesSearch && matchesFilter;
    }).toList();
  }

  int _countStatus(String status) {
    return _bookings
        .where((booking) => _bookingStatus(booking) == status)
        .length;
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

  Map<String, dynamic> _bookingPayload(
    Map<String, dynamic> booking, {
    required String status,
    required String departmentId,
    required String doctorId,
    String? appointmentId,
    String? note,
  }) {
    final payload = <String, dynamic>{
      'status': status,
      'requested_department_id':
          departmentId == '__none__' ? null : departmentId,
      'assigned_doctor_id': doctorId == '__none__' ? null : doctorId,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };

    if (appointmentId != null) {
      payload['appointment_id'] = appointmentId;
    }

    if (note != null) {
      final existing = booking['ai_notes']?.toString() ?? '';
      final cleanNote = note.trim();

      payload['ai_notes'] =
          cleanNote.isEmpty ? existing : '$existing\n$cleanNote'.trim();
    }

    return payload;
  }

  Future<void> _updateLinkedCheckin(
    Map<String, dynamic> booking, {
    required String status,
    required String departmentId,
    required String doctorId,
    String? appointmentId,
  }) async {
    final checkinId = booking['checkin_id'];

    if (checkinId == null) return;

    try {
      final checkin = await _supabase
          .from('reception_checkins')
          .select()
          .eq('id', checkinId)
          .maybeSingle();

      if (checkin == null) return;

      final update = <String, dynamic>{};

      if (checkin.containsKey('queue_status')) {
        update['queue_status'] = status;
      }

      if (checkin.containsKey('checkin_status')) {
        update['checkin_status'] = status;
      }

      if (checkin.containsKey('status')) {
        update['status'] = status;
      }

      if (checkin.containsKey('department_id')) {
        update['department_id'] =
            departmentId == '__none__' ? null : departmentId;
      }

      if (checkin.containsKey('assigned_doctor_id')) {
        update['assigned_doctor_id'] = doctorId == '__none__' ? null : doctorId;
      }

      if (appointmentId != null && checkin.containsKey('appointment_id')) {
        update['appointment_id'] = appointmentId;
      }

      if (checkin.containsKey('updated_at')) {
        update['updated_at'] = DateTime.now().toUtc().toIso8601String();
      }

      if (update.isEmpty) return;

      await _supabase
          .from('reception_checkins')
          .update(update)
          .eq('id', checkinId)
          .eq('hospital_id', _hospitalId!);
    } catch (_) {
      // Booking confirmation still succeeds even if linked check-in lacks fields.
    }
  }

  Future<void> _quickConfirmBooking(Map<String, dynamic> booking) async {
    if (_actionBusy) return;

    final bookingId = booking['id']?.toString();

    if (bookingId == null || bookingId.isEmpty) {
      _showSnack('This AI booking request has no ID.', isError: true);
      return;
    }

    final hospitalId = _hospitalId;

    if (hospitalId == null) {
      _showSnack('No hospital linked to this admin account.', isError: true);
      return;
    }

    final status = _bookingStatus(booking);

    if (status == 'confirmed' || status == 'completed') {
      _showSnack('This booking has already been confirmed.');
      return;
    }

    final departmentId =
        booking['requested_department_id']?.toString() ?? '__none__';

    String doctorId = booking['assigned_doctor_id']?.toString() ?? '__none__';

    if (doctorId == '__none__') {
      final suggestedDoctor = _findBestDoctor(
        departmentId == '__none__' ? null : departmentId,
      );

      doctorId = suggestedDoctor?['id']?.toString() ?? '__none__';
    }

    if (doctorId == '__none__') {
      _showSnack(
        'No doctor is assigned. Open Manage and assign a doctor first.',
        isError: true,
      );
      return;
    }

    final patientId = booking['patient_id']?.toString();

    if (patientId == null || patientId.isEmpty) {
      _showSnack(
        'This AI request has no linked patient record.',
        isError: true,
      );
      return;
    }

    setState(() {
      _actionBusy = true;
    });

    try {
      String? appointmentId = booking['appointment_id']?.toString();

      if (appointmentId == null || appointmentId.isEmpty) {
        final urgency = _urgency(booking).toLowerCase();

        final isEmergency = urgency.contains('emergency') ||
            urgency.contains('critical') ||
            urgency.contains('urgent');

        final appointmentTime = isEmergency
            ? DateTime.now()
            : DateTime.now().add(const Duration(minutes: 15));

        final appointmentStatus = isEmergency ? 'checked_in' : 'confirmed';

        final inserted = await _supabase
            .from('appointments')
            .insert({
              'hospital_id': hospitalId,
              'patient_id': patientId,
              'doctor_id': doctorId,
              'department_id': departmentId == '__none__' ? null : departmentId,
              'department': _departmentNameById(
                departmentId == '__none__' ? null : departmentId,
              ),
              'appointment_date': appointmentTime.toUtc().toIso8601String(),
              'scheduled_for': appointmentTime.toUtc().toIso8601String(),
              'duration_minutes': 30,
              'reason': _reason(booking),
              'status': appointmentStatus,
              'appointment_status': appointmentStatus,
              'type': isEmergency ? 'emergency' : 'consultation',
              'appointment_type': isEmergency ? 'emergency' : 'consultation',
              'urgency': isEmergency ? 'emergency' : _urgency(booking),
              'urgency_level': isEmergency ? 'emergency' : _urgency(booking),
              'ai_recommended': true,
              'ai_summary': _summary(booking),
              'source': 'hospital_ai',
              'created_by': _supabase.auth.currentUser?.id,
              'checked_in_at':
                  isEmergency ? DateTime.now().toUtc().toIso8601String() : null,
            })
            .select('id')
            .single();

        appointmentId = inserted['id']?.toString();
      }

      await _supabase
          .from('hospital_ai_booking_requests')
          .update(
            _bookingPayload(
              booking,
              status: 'confirmed',
              departmentId: departmentId,
              doctorId: doctorId,
              appointmentId: appointmentId,
              note:
                  'Confirmed by hospital admin. Staff must verify all clinical decisions.',
            ),
          )
          .eq('id', bookingId)
          .eq('hospital_id', hospitalId);

      await _updateLinkedCheckin(
        booking,
        status: 'booked',
        departmentId: departmentId,
        doctorId: doctorId,
        appointmentId: appointmentId,
      );

      _showSnack('AI booking confirmed and appointment created.');

      await _loadPage();
    } catch (e) {
      _showSnack('Could not confirm AI booking: $e', isError: true);
    } finally {
      if (mounted) {
        setState(() {
          _actionBusy = false;
        });
      }
    }
  }

  Future<void> _emergencyEscalation(Map<String, dynamic> booking) async {
    if (_actionBusy) return;

    final bookingId = booking['id']?.toString();
    final hospitalId = _hospitalId;

    if (bookingId == null || hospitalId == null) {
      _showSnack('Booking request is incomplete.', isError: true);
      return;
    }

    setState(() {
      _actionBusy = true;
    });

    try {
      String departmentId = '__none__';

      for (final department in _departments) {
        final name = department['name']?.toString().toLowerCase() ?? '';

        if (name.contains('emergency')) {
          departmentId = department['id']?.toString() ?? '__none__';
          break;
        }
      }

      final doctor = _findBestDoctor(
        departmentId == '__none__' ? null : departmentId,
      );

      final doctorId = doctor?['id']?.toString() ?? '__none__';

      await _supabase
          .from('hospital_ai_booking_requests')
          .update(
            _bookingPayload(
              booking,
              status: 'emergency_escalation',
              departmentId: departmentId,
              doctorId: doctorId,
              note:
                  'Emergency escalation selected by hospital admin. Patient must be reviewed by emergency staff immediately.',
            ),
          )
          .eq('id', bookingId)
          .eq('hospital_id', hospitalId);

      await _updateLinkedCheckin(
        booking,
        status: 'emergency_escalation',
        departmentId: departmentId,
        doctorId: doctorId,
      );

      _showSnack('Patient escalated to the emergency queue.');

      await _loadPage();
    } catch (e) {
      _showSnack('Could not escalate AI booking: $e', isError: true);
    } finally {
      if (mounted) {
        setState(() {
          _actionBusy = false;
        });
      }
    }
  }

  Future<void> _showBookingEditor(Map<String, dynamic> booking) async {
    final bookingId = booking['id']?.toString();

    if (bookingId == null || bookingId.isEmpty) {
      _showSnack('This booking request has no valid ID.', isError: true);
      return;
    }

    String selectedStatus = _bookingStatus(booking);
    String selectedDepartmentId =
        booking['requested_department_id']?.toString() ?? '__none__';
    String selectedDoctorId =
        booking['assigned_doctor_id']?.toString() ?? '__none__';

    final noteController = TextEditingController(
      text: booking['ai_notes']?.toString() ?? '',
    );

    bool saving = false;

    final validDepartmentIds = _departments
        .map((department) => department['id']?.toString())
        .whereType<String>()
        .toSet();

    final validDoctorIds = _doctors
        .map((doctor) => doctor['id']?.toString())
        .whereType<String>()
        .toSet();

    if (selectedDepartmentId != '__none__' &&
        !validDepartmentIds.contains(selectedDepartmentId)) {
      selectedDepartmentId = '__none__';
    }

    if (selectedDoctorId != '__none__' &&
        !validDoctorIds.contains(selectedDoctorId)) {
      selectedDoctorId = '__none__';
    }

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
                constraints: const BoxConstraints(maxHeight: 780),
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
                        'Manage AI Booking Request',
                        style: TextStyle(
                          color: textDark,
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${_patientName(booking)} • ${_patientPhone(booking)}',
                        style: TextStyle(color: mutedText, fontSize: 13),
                      ),
                      const SizedBox(height: 20),
                      DropdownButtonFormField<String>(
                        initialValue: selectedStatus,
                        decoration: const InputDecoration(
                          labelText: 'Booking status',
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(value: 'new', child: Text('New')),
                          DropdownMenuItem(
                            value: 'reviewing',
                            child: Text('Reviewing'),
                          ),
                          DropdownMenuItem(
                            value: 'confirmed',
                            child: Text('Confirmed'),
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
                        onChanged: saving
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
                          ..._departments.map(
                            (department) => DropdownMenuItem(
                              value: department['id']?.toString() ?? '',
                              child: Text(
                                department['name']?.toString() ?? 'Department',
                              ),
                            ),
                          ),
                        ],
                        onChanged: saving
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
                          ..._doctors.map(
                            (doctor) => DropdownMenuItem(
                              value: doctor['id']?.toString() ?? '',
                              child: Text(_doctorNameById(doctor['id'])),
                            ),
                          ),
                        ],
                        onChanged: saving
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
                        controller: noteController,
                        enabled: !saving,
                        maxLines: 4,
                        decoration: const InputDecoration(
                          labelText: 'Staff / AI notes',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: saving
                              ? null
                              : () async {
                                  setModalState(() {
                                    saving = true;
                                  });

                                  try {
                                    await _supabase
                                        .from('hospital_ai_booking_requests')
                                        .update(
                                          _bookingPayload(
                                            booking,
                                            status: selectedStatus,
                                            departmentId: selectedDepartmentId,
                                            doctorId: selectedDoctorId,
                                            note: noteController.text,
                                          ),
                                        )
                                        .eq('id', bookingId)
                                        .eq('hospital_id', _hospitalId!);

                                    await _updateLinkedCheckin(
                                      booking,
                                      status: selectedStatus ==
                                              'emergency_escalation'
                                          ? 'emergency_escalation'
                                          : selectedStatus == 'confirmed'
                                              ? 'booked'
                                              : 'waiting',
                                      departmentId: selectedDepartmentId,
                                      doctorId: selectedDoctorId,
                                    );

                                    if (sheetContext.mounted) {
                                      Navigator.of(sheetContext).pop();
                                    }

                                    await _loadPage();

                                    _showSnack('AI booking request updated.');
                                  } catch (e) {
                                    if (sheetContext.mounted) {
                                      setModalState(() {
                                        saving = false;
                                      });
                                    }

                                    _showSnack(
                                      'Could not update booking: $e',
                                      isError: true,
                                    );
                                  }
                                },
                          icon: saving
                              ? const SizedBox(
                                  height: 18,
                                  width: 18,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  ),
                                )
                              : Icon(Icons.save_rounded),
                          label: Text(
                            saving ? 'Saving...' : 'Save booking changes',
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

    noteController.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bookings = _visibleBookings;

    return Scaffold(
      backgroundColor: background,
      body: SafeArea(
        child: RefreshIndicator(
          color: accent,
          onRefresh: _loadPage,
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
                      _buildBookingDirectory(bookings),
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
          onPressed: widget.onBack ?? () => Navigator.of(context).maybePop(),
          icon: Icon(Icons.arrow_back_rounded),
          color: primary,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'AI Booking Queue • $_hospitalName',
                style: TextStyle(
                  color: textDark,
                  fontSize: 27,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                'Review AI recommendations before staff confirm the final booking.',
                style: TextStyle(color: mutedText, fontSize: 14),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        OutlinedButton.icon(
          onPressed: _loadPage,
          icon: Icon(Icons.refresh_rounded),
          label: Text('Refresh'),
          style: OutlinedButton.styleFrom(
            foregroundColor: primary,
            side: BorderSide(color: Color(0xFFE2E8F0)),
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
              'Could not load all AI booking information. $_error',
              style: TextStyle(color: textDark, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStats() {
    final stats = [
      _QueueStat(
        title: 'Total Requests',
        value: _bookings.length.toString(),
        subtitle: 'AI booking requests',
        icon: Icons.auto_awesome_rounded,
        color: accent,
      ),
      _QueueStat(
        title: 'New',
        value: _countStatus('new').toString(),
        subtitle: 'Needs staff review',
        icon: Icons.mark_email_unread_rounded,
        color: warning,
      ),
      _QueueStat(
        title: 'Confirmed',
        value: _countStatus('confirmed').toString(),
        subtitle: 'Appointment created',
        icon: Icons.verified_rounded,
        color: success,
      ),
      _QueueStat(
        title: 'Emergency',
        value: _countStatus('emergency_escalation').toString(),
        subtitle: 'Urgent escalation records',
        icon: Icons.emergency_rounded,
        color: error,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 1000;

        return GridView.builder(
          itemCount: stats.length,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: isWide ? 4 : 2,
            mainAxisExtent: 205,
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
                border: Border.all(color: context.cDivider),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
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
                  const Spacer(),
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
                    style: TextStyle(
                      color: textDark,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    stat.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: mutedText, fontSize: 12),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildBookingDirectory(List<Map<String, dynamic>> bookings) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: context.cBgSecondary,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: context.cDivider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome_rounded, color: accent),
              SizedBox(width: 10),
              Text(
                'AI Booking Requests',
                style: TextStyle(
                  color: primary,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            '${bookings.length} booking request(s) currently shown',
            style: TextStyle(color: mutedText, fontSize: 13),
          ),
          const SizedBox(height: 18),
          TextField(
            controller: _searchController,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText:
                  'Search patient, symptoms, department, doctor or AI summary',
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
              fillColor: context.cBgPrimary,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(15),
                borderSide: BorderSide(color: Color(0xFFE2E8F0)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(15),
                borderSide: BorderSide(color: Color(0xFFE2E8F0)),
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
            children: [
              _FilterItem(label: 'All', value: 'All'),
              _FilterItem(label: 'New', value: 'new'),
              _FilterItem(label: 'Reviewing', value: 'reviewing'),
              _FilterItem(label: 'Confirmed', value: 'confirmed'),
              _FilterItem(
                label: 'Emergency',
                value: 'emergency_escalation',
              ),
              _FilterItem(label: 'Cancelled', value: 'cancelled'),
            ].map((filter) {
              return ChoiceChip(
                label: Text(filter.label),
                selected: _selectedFilter == filter.value,
                selectedColor: accent.withValues(alpha: 0.13),
                onSelected: (_) {
                  setState(() {
                    _selectedFilter = filter.value;
                  });
                },
              );
            }).toList(),
          ),
          const SizedBox(height: 20),
          if (bookings.isEmpty)
            _buildEmptyState()
          else
            ...bookings.map(_buildBookingCard),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 42, horizontal: 20),
      decoration: BoxDecoration(
        color: context.cBgPrimary,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: context.cDivider),
      ),
      child: Column(
        children: [
          Icon(Icons.auto_awesome_outlined, color: accent, size: 42),
          SizedBox(height: 12),
          Text(
            'No AI booking requests found',
            style: TextStyle(
              color: primary,
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
          SizedBox(height: 6),
          Text(
            'New requests appear after a QR-scanned patient completes symptom intake.',
            textAlign: TextAlign.center,
            style: TextStyle(color: mutedText, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildBookingCard(Map<String, dynamic> booking) {
    final status = _bookingStatus(booking);
    final statusColor = _statusColor(status);
    final urgency = _urgency(booking);

    final departmentId =
        booking['requested_department_id']?.toString() ?? '__none__';

    final assignedDoctorId =
        booking['assigned_doctor_id']?.toString() ?? '__none__';

    final suggestedDoctor = assignedDoctorId == '__none__'
        ? _findBestDoctor(departmentId == '__none__' ? null : departmentId)
        : _doctorById(assignedDoctorId);

    final doctorName = suggestedDoctor == null
        ? 'No doctor assigned'
        : _doctorNameById(suggestedDoctor['id']);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.cBgPrimary,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: statusColor.withValues(alpha: 0.30)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 760;

          final details = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _patientName(booking),
                style: TextStyle(
                  color: textDark,
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${_patientPhone(booking)} • ${_formatDateTime(booking['created_at'])}',
                style: TextStyle(color: mutedText, fontSize: 12),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _QueuePill(
                    icon: Icons.priority_high_rounded,
                    label: urgency,
                    color: _urgencyColor(urgency),
                  ),
                  _QueuePill(
                    icon: Icons.local_hospital_rounded,
                    label: _recommendedDepartment(booking),
                    color: accent,
                  ),
                  _QueuePill(
                    icon: Icons.medical_services_rounded,
                    label: doctorName,
                    color: success,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _InfoLine(label: 'Symptoms', value: _reason(booking)),
              _InfoLine(label: 'AI Summary', value: _summary(booking)),
            ],
          );

          final actionButtons = Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _QueuePill(
                icon: Icons.circle,
                label: _statusLabel(status),
                color: statusColor,
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed:
                    _actionBusy ? null : () => _showBookingEditor(booking),
                icon: Icon(Icons.edit_rounded, size: 18),
                label: Text('Manage'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: primary,
                  side: BorderSide(color: Color(0xFFE2E8F0)),
                ),
              ),
              const SizedBox(height: 8),
              ElevatedButton.icon(
                onPressed: _actionBusy ||
                        status == 'confirmed' ||
                        status == 'completed'
                    ? null
                    : () => _quickConfirmBooking(booking),
                icon: Icon(Icons.check_circle_rounded, size: 18),
                label: Text('Confirm'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: primary,
                  foregroundColor: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _actionBusy || status == 'emergency_escalation'
                    ? null
                    : () => _emergencyEscalation(booking),
                icon: Icon(Icons.emergency_rounded, size: 18),
                label: Text('Emergency'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: error,
                  side: BorderSide(color: error),
                ),
              ),
            ],
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
                      child: Icon(
                        Icons.auto_awesome_rounded,
                        color: statusColor,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: details),
                  ],
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _QueuePill(
                      icon: Icons.circle,
                      label: _statusLabel(status),
                      color: statusColor,
                    ),
                    OutlinedButton.icon(
                      onPressed: _actionBusy
                          ? null
                          : () => _showBookingEditor(booking),
                      icon: Icon(Icons.edit_rounded, size: 18),
                      label: Text('Manage'),
                    ),
                    ElevatedButton.icon(
                      onPressed: _actionBusy ||
                              status == 'confirmed' ||
                              status == 'completed'
                          ? null
                          : () => _quickConfirmBooking(booking),
                      icon: Icon(Icons.check_circle_rounded, size: 18),
                      label: Text('Confirm'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _actionBusy || status == 'emergency_escalation'
                          ? null
                          : () => _emergencyEscalation(booking),
                      icon: Icon(Icons.emergency_rounded, size: 18),
                      label: Text('Emergency'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: error,
                        side: BorderSide(color: error),
                      ),
                    ),
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
                child: Icon(Icons.auto_awesome_rounded, color: statusColor),
              ),
              const SizedBox(width: 14),
              Expanded(child: details),
              const SizedBox(width: 14),
              actionButtons,
            ],
          );
        },
      ),
    );
  }
}

class _QueueStat {
  final String title;
  final String value;
  final String subtitle;
  final IconData icon;
  final Color color;

  const _QueueStat({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.icon,
    required this.color,
  });
}

class _FilterItem {
  final String label;
  final String value;

  const _FilterItem({required this.label, required this.value});
}

class _QueuePill extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _QueuePill({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 250),
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
              maxLines: 1,
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

class _InfoLine extends StatelessWidget {
  final String label;
  final String value;

  const _InfoLine({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: RichText(
        text: TextSpan(
          children: [
            TextSpan(
              text: '$label: ',
              style: TextStyle(
                color: CorviaColors.textPrimary,
                fontSize: 12,
                fontWeight: FontWeight.w900,
              ),
            ),
            TextSpan(
              text: value,
              style: TextStyle(
                color: CorviaColors.textMuted,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
