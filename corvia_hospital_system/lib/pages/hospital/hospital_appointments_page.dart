import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../theme/app_theme.dart';
import 'hospital_page_shared.dart';

class HospitalAppointmentsPage extends StatefulWidget {
  const HospitalAppointmentsPage({super.key});

  @override
  State<HospitalAppointmentsPage> createState() =>
      _HospitalAppointmentsPageState();
}

class _HospitalAppointmentsPageState extends State<HospitalAppointmentsPage> {
  final SupabaseClient _supabase = Supabase.instance.client;
  final TextEditingController _searchController = TextEditingController();

  bool _loading = true;
  String? _error;
  String? _hospitalId;
  String _hospitalName = 'Hospital Appointments';
  String _statusFilter = 'All';
  String _dateFilter = 'All dates';

  List<Map<String, dynamic>> _appointments = [];
  List<Map<String, dynamic>> _patients = [];
  List<Map<String, dynamic>> _doctors = [];
  List<Map<String, dynamic>> _departments = [];
  Map<String, Map<String, dynamic>> _profiles = {};

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
      final scope = await HospitalAdminScope.load(
        _supabase,
        fallbackName: 'Hospital Appointments',
      );

      final results = await Future.wait([
        _loadTable('appointments', scope.hospitalId),
        _loadTable('patients', scope.hospitalId),
        _loadTable('doctors', scope.hospitalId),
        _loadTable('departments', scope.hospitalId),
      ]);

      _hospitalId = scope.hospitalId;
      _hospitalName = scope.hospitalName;
      _appointments = results[0];
      _patients = results[1];
      _doctors = results[2];
      _departments = results[3];
      _profiles = await HospitalDataTools.loadProfiles(
        _supabase,
        [..._patients, ..._doctors],
      );
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<List<Map<String, dynamic>>> _loadTable(
    String table,
    String hospitalId,
  ) async {
    try {
      final rows = await _supabase
          .from(table)
          .select()
          .eq('hospital_id', hospitalId)
          .order('created_at', ascending: false)
          .limit(500);

      return HospitalDataTools.rows(rows);
    } catch (_) {
      final rows = await _supabase
          .from(table)
          .select()
          .eq('hospital_id', hospitalId)
          .limit(500);

      return HospitalDataTools.rows(rows);
    }
  }

  Map<String, dynamic>? _patient(dynamic id) {
    for (final patient in _patients) {
      if (patient['id']?.toString() == id?.toString()) {
        return patient;
      }
    }

    return null;
  }

  Map<String, dynamic>? _doctor(dynamic id) {
    for (final doctor in _doctors) {
      if (doctor['id']?.toString() == id?.toString()) {
        return doctor;
      }
    }

    return null;
  }

  String _patientName(dynamic id) {
    final patient = _patient(id);

    if (patient == null) {
      return 'Patient record not linked';
    }

    return HospitalDataTools.personName(
      patient,
      _profiles,
      fallback: 'Patient profile not linked',
    );
  }

  String _doctorName(dynamic id) {
    final doctor = _doctor(id);

    if (doctor == null) {
      return 'Doctor not assigned';
    }

    return HospitalDataTools.personName(
      doctor,
      _profiles,
      prefix: 'Dr',
      fallback: 'Doctor profile not linked',
    );
  }

  String _departmentName(dynamic id) {
    for (final department in _departments) {
      if (department['id']?.toString() == id?.toString()) {
        return department['name']?.toString() ?? 'Department linked';
      }
    }

    return 'No department assigned';
  }

  String _status(Map<String, dynamic> appointment) {
    final raw =
        appointment['status'] ?? appointment['appointment_status'] ?? 'pending';

    final value = raw
        .toString()
        .toLowerCase()
        .trim()
        .replaceAll(' ', '_')
        .replaceAll('-', '_');

    const valid = [
      'pending',
      'scheduled',
      'confirmed',
      'checked_in',
      'completed',
      'cancelled',
      'no_show',
    ];

    return valid.contains(value) ? value : 'pending';
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'scheduled':
        return 'Scheduled';
      case 'confirmed':
        return 'Confirmed';
      case 'checked_in':
        return 'Checked In';
      case 'completed':
        return 'Completed';
      case 'cancelled':
        return 'Cancelled';
      case 'no_show':
        return 'No Show';
      default:
        return 'Pending';
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'confirmed':
      case 'completed':
        return CorviaColors.success;
      case 'checked_in':
        return context.cAccentReadable;
      case 'cancelled':
      case 'no_show':
        return CorviaColors.danger;
      default:
        return CorviaColors.warning;
    }
  }

  DateTime _date(Map<String, dynamic> appointment) {
    final value = appointment['scheduled_for'] ??
        appointment['appointment_date'] ??
        appointment['created_at'];

    return DateTime.tryParse(value?.toString() ?? '')?.toLocal() ??
        DateTime.now();
  }

  String _dateText(Map<String, dynamic> appointment) {
    final date = _date(appointment);

    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year} • '
        '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  List<Map<String, dynamic>> get _visibleAppointments {
    final search = _searchController.text.trim().toLowerCase();
    final now = DateTime.now();
    final startToday = DateTime(now.year, now.month, now.day);
    final tomorrow = startToday.add(const Duration(days: 1));

    return _appointments.where((appointment) {
      final appointmentDate = _date(appointment);
      final status = _status(appointment);

      final matchesSearch = search.isEmpty ||
          _patientName(appointment['patient_id'])
              .toLowerCase()
              .contains(search) ||
          _doctorName(appointment['doctor_id'])
              .toLowerCase()
              .contains(search) ||
          _departmentName(appointment['department_id'])
              .toLowerCase()
              .contains(search) ||
          (appointment['reason']?.toString().toLowerCase().contains(search) ??
              false);

      final matchesStatus = _statusFilter == 'All' || status == _statusFilter;

      final matchesDate = _dateFilter == 'All dates' ||
          (_dateFilter == 'Today' &&
              !appointmentDate.isBefore(startToday) &&
              appointmentDate.isBefore(tomorrow)) ||
          (_dateFilter == 'Upcoming' && !appointmentDate.isBefore(tomorrow)) ||
          (_dateFilter == 'Past' && appointmentDate.isBefore(startToday));

      return matchesSearch && matchesStatus && matchesDate;
    }).toList();
  }

  int _countStatus(String target) {
    return _appointments.where((item) => _status(item) == target).length;
  }

  int get _todayCount {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    final end = start.add(const Duration(days: 1));

    return _appointments.where((item) {
      final date = _date(item);
      return !date.isBefore(start) && date.isBefore(end);
    }).length;
  }

  Future<void> _manage(Map<String, dynamic> appointment) async {
    final id = appointment['id']?.toString();

    if (id == null || id.isEmpty) {
      return;
    }

    String status = _status(appointment);
    String doctorId = appointment['doctor_id']?.toString() ?? '';
    String departmentId =
        appointment['department_id']?.toString() ?? '__none__';

    bool saving = false;

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
                padding: const EdgeInsets.fromLTRB(22, 22, 22, 28),
                decoration: BoxDecoration(
                  color: context.cBgSecondary,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(28),
                  ),
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Manage Appointment',
                        style: TextStyle(
                          color: context.cTextPrimary,
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${_patientName(appointment['patient_id'])} • ${_dateText(appointment)}',
                        style: TextStyle(
                          color: context.cTextSecondary,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 20),
                      DropdownButtonFormField<String>(
                        initialValue: status,
                        decoration: const InputDecoration(
                          labelText: 'Appointment status',
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'pending',
                            child: Text('Pending'),
                          ),
                          DropdownMenuItem(
                            value: 'scheduled',
                            child: Text('Scheduled'),
                          ),
                          DropdownMenuItem(
                            value: 'confirmed',
                            child: Text('Confirmed'),
                          ),
                          DropdownMenuItem(
                            value: 'checked_in',
                            child: Text('Checked In'),
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
                            value: 'no_show',
                            child: Text('No Show'),
                          ),
                        ],
                        onChanged: saving
                            ? null
                            : (value) {
                                if (value == null) return;
                                setModalState(() => status = value);
                              },
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        initialValue: doctorId.isEmpty ? null : doctorId,
                        decoration: const InputDecoration(
                          labelText: 'Assigned doctor',
                          border: OutlineInputBorder(),
                        ),
                        items: _doctors
                            .map(
                              (doctor) => DropdownMenuItem(
                                value: doctor['id']?.toString() ?? '',
                                child: Text(_doctorName(doctor['id'])),
                              ),
                            )
                            .toList(),
                        onChanged: saving
                            ? null
                            : (value) {
                                if (value == null) return;
                                setModalState(() => doctorId = value);
                              },
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        initialValue: departmentId,
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
                                setModalState(() => departmentId = value);
                              },
                      ),
                      const SizedBox(height: 22),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: saving
                              ? null
                              : () async {
                                  if (doctorId.isEmpty) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Select a doctor first.'),
                                      ),
                                    );
                                    return;
                                  }

                                  setModalState(() => saving = true);

                                  try {
                                    await _supabase
                                        .from('appointments')
                                        .update({
                                          'status': status,
                                          'appointment_status': status,
                                          'doctor_id': doctorId,
                                          'department_id':
                                              departmentId == '__none__'
                                                  ? null
                                                  : departmentId,
                                          'updated_at': DateTime.now()
                                              .toUtc()
                                              .toIso8601String(),
                                        })
                                        .eq('id', id)
                                        .eq('hospital_id', _hospitalId!);

                                    if (sheetContext.mounted) {
                                      Navigator.of(sheetContext).pop();
                                    }

                                    await _loadPage();
                                  } catch (e) {
                                    if (sheetContext.mounted) {
                                      setModalState(() => saving = false);
                                    }
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
                              : const Icon(Icons.save_rounded),
                          label: Text(
                            saving ? 'Saving...' : 'Save appointment changes',
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
  }

  @override
  Widget build(BuildContext context) {
    final appointments = _visibleAppointments;

    return Scaffold(
      backgroundColor: context.cBgPrimary,
      body: SafeArea(
        child: RefreshIndicator(
          color: context.cAccentReadable,
          onRefresh: _loadPage,
          child: _loading
              ? Center(
                  child: CircularProgressIndicator(
                    color: context.cAccentReadable,
                  ),
                )
              : SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      HospitalPageHeader(
                        title: 'Appointments • $_hospitalName',
                        subtitle:
                            'Manage hospital appointments, schedules, doctors and patient status.',
                        onRefresh: _loadPage,
                      ),
                      const SizedBox(height: 22),
                      if (_error != null) _errorBox(),
                      HospitalStatGrid(
                        items: [
                          HospitalStatItem(
                            title: 'Total Appointments',
                            value: _appointments.length.toString(),
                            subtitle: 'All hospital appointments',
                            icon: Icons.calendar_month_rounded,
                            color: context.cAccentReadable,
                          ),
                          HospitalStatItem(
                            title: 'Today',
                            value: _todayCount.toString(),
                            subtitle: 'Scheduled for today',
                            icon: Icons.today_rounded,
                            color: CorviaColors.success,
                          ),
                          HospitalStatItem(
                            title: 'Waiting',
                            value: (_countStatus('pending') +
                                    _countStatus('scheduled'))
                                .toString(),
                            subtitle: 'Pending or scheduled',
                            icon: Icons.pending_actions_rounded,
                            color: CorviaColors.warning,
                          ),
                          HospitalStatItem(
                            title: 'Checked In',
                            value: _countStatus('checked_in').toString(),
                            subtitle: 'Patients currently checked in',
                            icon: Icons.login_rounded,
                            color: context.cAccentReadable,
                          ),
                        ],
                      ),
                      const SizedBox(height: 22),
                      HospitalPanel(
                        title: 'Hospital Appointment Directory',
                        subtitle:
                            '${appointments.length} appointment(s) currently shown',
                        icon: Icons.event_note_rounded,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            HospitalSearchBox(
                              controller: _searchController,
                              hint:
                                  'Search patient, doctor, reason or department',
                              onChanged: (_) => setState(() {}),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Appointment status',
                              style: TextStyle(
                                color: context.cTextPrimary,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                ('All', 'All'),
                                ('Pending', 'pending'),
                                ('Confirmed', 'confirmed'),
                                ('Checked In', 'checked_in'),
                                ('Completed', 'completed'),
                                ('Cancelled', 'cancelled'),
                                ('No Show', 'no_show'),
                              ].map((item) {
                                return ChoiceChip(
                                  label: Text(item.$1),
                                  selected: _statusFilter == item.$2,
                                  selectedColor: context.cAccentReadable
                                      .withValues(alpha: 0.12),
                                  onSelected: (_) {
                                    setState(() => _statusFilter = item.$2);
                                  },
                                );
                              }).toList(),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Date filter',
                              style: TextStyle(
                                color: context.cTextPrimary,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                'All dates',
                                'Today',
                                'Upcoming',
                                'Past',
                              ].map((item) {
                                return ChoiceChip(
                                  label: Text(item),
                                  selected: _dateFilter == item,
                                  selectedColor: context.cAccentReadable
                                      .withValues(alpha: 0.12),
                                  onSelected: (_) {
                                    setState(() => _dateFilter = item);
                                  },
                                );
                              }).toList(),
                            ),
                            const SizedBox(height: 18),
                            if (appointments.isEmpty)
                              const HospitalEmptyState(
                                icon: Icons.event_busy_rounded,
                                title: 'No appointments found',
                                message:
                                    'Appointments linked to this hospital will appear here.',
                              )
                            else
                              ...appointments.map(
                                (appointment) => _AppointmentCard(
                                  patient:
                                      _patientName(appointment['patient_id']),
                                  doctor: _doctorName(appointment['doctor_id']),
                                  department: _departmentName(
                                      appointment['department_id']),
                                  reason: appointment['reason']?.toString() ??
                                      'No reason captured',
                                  date: _dateText(appointment),
                                  status: _statusLabel(_status(appointment)),
                                  color: _statusColor(_status(appointment)),
                                  onManage: () => _manage(appointment),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }

  Widget _errorBox() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 18),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: CorviaColors.danger.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: CorviaColors.danger.withValues(alpha: 0.20),
        ),
      ),
      child: Text(
        'Some appointment information could not load. $_error',
        style: TextStyle(
          color: context.cTextPrimary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _AppointmentCard extends StatelessWidget {
  const _AppointmentCard({
    required this.patient,
    required this.doctor,
    required this.department,
    required this.reason,
    required this.date,
    required this.status,
    required this.color,
    required this.onManage,
  });

  final String patient;
  final String doctor;
  final String department;
  final String reason;
  final String date;
  final String status;
  final Color color;
  final VoidCallback onManage;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.cBgPrimary,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: context.cDivider),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 720;

          final details = Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  patient,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: context.cTextPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  doctor,
                  style: TextStyle(
                    color: context.cTextSecondary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$department • $date',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: context.cTextSecondary,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  reason,
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

          final action = Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              HospitalStatusPill(label: status, color: color),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: onManage,
                icon: const Icon(Icons.edit_calendar_rounded, size: 18),
                label: const Text('Manage'),
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
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Icon(Icons.event_rounded, color: color),
                    ),
                    const SizedBox(width: 14),
                    details,
                  ],
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: action,
                ),
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(Icons.event_rounded, color: color),
              ),
              const SizedBox(width: 14),
              details,
              const SizedBox(width: 12),
              action,
            ],
          );
        },
      ),
    );
  }
}
