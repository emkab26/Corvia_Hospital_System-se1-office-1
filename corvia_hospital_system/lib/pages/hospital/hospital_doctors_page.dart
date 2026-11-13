import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../theme/app_theme.dart';
import 'hospital_page_shared.dart';

class HospitalDoctorsPage extends StatefulWidget {
  const HospitalDoctorsPage({super.key});

  @override
  State<HospitalDoctorsPage> createState() => _HospitalDoctorsPageState();
}

class _HospitalDoctorsPageState extends State<HospitalDoctorsPage> {
  final SupabaseClient _supabase = Supabase.instance.client;
  final TextEditingController _searchController = TextEditingController();

  bool _loading = true;
  String? _error;
  String? _hospitalId;
  String _hospitalName = 'Hospital Doctors';
  String _filter = 'All';

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
        fallbackName: 'Hospital Doctors',
      );

      final results = await Future.wait([
        _loadDoctors(scope.hospitalId),
        _loadDepartments(scope.hospitalId),
      ]);

      _hospitalId = scope.hospitalId;
      _hospitalName = scope.hospitalName;
      _doctors = results[0];
      _departments = results[1];

      _profiles = await HospitalDataTools.loadProfiles(
        _supabase,
        _doctors,
      );
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

  Future<List<Map<String, dynamic>>> _loadDoctors(
    String hospitalId,
  ) async {
    try {
      final rows = await _supabase
          .from('doctors')
          .select()
          .eq('hospital_id', hospitalId)
          .order('created_at', ascending: false)
          .limit(500);

      return HospitalDataTools.rows(rows);
    } catch (_) {
      final rows = await _supabase
          .from('doctors')
          .select()
          .eq('hospital_id', hospitalId)
          .limit(500);

      return HospitalDataTools.rows(rows);
    }
  }

  Future<List<Map<String, dynamic>>> _loadDepartments(
    String hospitalId,
  ) async {
    try {
      final rows = await _supabase
          .from('departments')
          .select()
          .eq('hospital_id', hospitalId)
          .order('name', ascending: true);

      return HospitalDataTools.rows(rows);
    } catch (_) {
      return [];
    }
  }

  String _name(Map<String, dynamic> doctor) {
    return HospitalDataTools.personName(
      doctor,
      _profiles,
      prefix: 'Dr',
      fallback: 'Doctor profile not linked',
    );
  }

  String _email(Map<String, dynamic> doctor) {
    return HospitalDataTools.email(doctor, _profiles);
  }

  String _phone(Map<String, dynamic> doctor) {
    return HospitalDataTools.phone(doctor, _profiles);
  }

  String _status(Map<String, dynamic> doctor) {
    final raw = doctor['status']?.toString().toLowerCase().trim() ?? '';

    if (raw == 'busy') return 'busy';

    if (raw == 'off_duty' || raw == 'off duty') {
      return 'off_duty';
    }

    if (raw == 'inactive' || doctor['is_active'] == false) {
      return 'inactive';
    }

    return 'available';
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'busy':
        return 'Busy';
      case 'off_duty':
        return 'Off Duty';
      case 'inactive':
        return 'Inactive';
      default:
        return 'Available';
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'busy':
        return CorviaColors.warning;
      case 'off_duty':
        return context.cTextMuted;
      case 'inactive':
        return CorviaColors.danger;
      default:
        return CorviaColors.success;
    }
  }

  String _departmentName(dynamic departmentId) {
    for (final department in _departments) {
      if (department['id']?.toString() == departmentId?.toString()) {
        return department['name']?.toString() ?? 'Department linked';
      }
    }

    return 'No department assigned';
  }

  List<Map<String, dynamic>> get _visibleDoctors {
    final search = _searchController.text.trim().toLowerCase();

    return _doctors.where((doctor) {
      final status = _status(doctor);

      final specialty =
          doctor['specialization']?.toString().toLowerCase() ?? '';

      final department = _departmentName(
        doctor['department_id'],
      ).toLowerCase();

      final matchesSearch = search.isEmpty ||
          _name(doctor).toLowerCase().contains(search) ||
          _email(doctor).toLowerCase().contains(search) ||
          specialty.contains(search) ||
          department.contains(search);

      final matchesFilter = _filter == 'All' ||
          (_filter == 'Available' && status == 'available') ||
          (_filter == 'Busy' && status == 'busy') ||
          (_filter == 'Off Duty' && status == 'off_duty') ||
          (_filter == 'Inactive' && status == 'inactive');

      return matchesSearch && matchesFilter;
    }).toList();
  }

  int _count(String targetStatus) {
    return _doctors.where((doctor) {
      return _status(doctor) == targetStatus;
    }).length;
  }

  void _showSnack(
    String message, {
    bool error = false,
  }) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? CorviaColors.danger : context.cAccentReadable,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _manageDoctor(Map<String, dynamic> doctor) async {
    final doctorId = doctor['id']?.toString();

    if (doctorId == null || doctorId.isEmpty) {
      _showSnack(
        'This doctor record has no ID.',
        error: true,
      );
      return;
    }

    String status = _status(doctor);

    String departmentId = doctor['department_id']?.toString() ?? '__none__';

    final validDepartmentIds = _departments
        .map((department) => department['id']?.toString())
        .whereType<String>()
        .toSet();

    if (departmentId != '__none__' &&
        !validDepartmentIds.contains(departmentId)) {
      departmentId = '__none__';
    }

    final roomController = TextEditingController(
      text: doctor['room_name']?.toString() ??
          doctor['location']?.toString() ??
          '',
    );

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
                        'Manage ${_name(doctor)}',
                        style: TextStyle(
                          color: context.cTextPrimary,
                          fontSize: 21,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${_email(doctor)} • ${doctor['specialization'] ?? 'General Practitioner'}',
                        style: TextStyle(
                          color: context.cTextSecondary,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 20),
                      DropdownButtonFormField<String>(
                        initialValue: status,
                        decoration: const InputDecoration(
                          labelText: 'Availability status',
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'available',
                            child: Text('Available'),
                          ),
                          DropdownMenuItem(
                            value: 'busy',
                            child: Text('Busy'),
                          ),
                          DropdownMenuItem(
                            value: 'off_duty',
                            child: Text('Off Duty'),
                          ),
                          DropdownMenuItem(
                            value: 'inactive',
                            child: Text('Inactive'),
                          ),
                        ],
                        onChanged: saving
                            ? null
                            : (value) {
                                if (value == null) return;

                                setModalState(() {
                                  status = value;
                                });
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

                                setModalState(() {
                                  departmentId = value;
                                });
                              },
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: roomController,
                        enabled: !saving,
                        decoration: const InputDecoration(
                          labelText: 'Room or location',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 22),
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
                                        .from('doctors')
                                        .update({
                                          'status': status,
                                          'is_active': status != 'inactive',
                                          'department_id':
                                              departmentId == '__none__'
                                                  ? null
                                                  : departmentId,
                                          'room_name':
                                              roomController.text.trim().isEmpty
                                                  ? null
                                                  : roomController.text.trim(),
                                          'updated_at': DateTime.now()
                                              .toUtc()
                                              .toIso8601String(),
                                        })
                                        .eq('id', doctorId)
                                        .eq('hospital_id', _hospitalId!);

                                    if (sheetContext.mounted) {
                                      Navigator.of(sheetContext).pop();
                                    }

                                    await _loadPage();
                                    _showSnack('Doctor details updated.');
                                  } catch (e) {
                                    if (sheetContext.mounted) {
                                      setModalState(() {
                                        saving = false;
                                      });
                                    }

                                    _showSnack(
                                      'Could not update doctor: $e',
                                      error: true,
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
                              : const Icon(Icons.save_rounded),
                          label: Text(
                            saving ? 'Saving...' : 'Save doctor changes',
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

    roomController.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final doctors = _visibleDoctors;

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
                        title: 'Doctors • $_hospitalName',
                        subtitle:
                            'Manage availability, departments, rooms and doctor assignments.',
                        onRefresh: _loadPage,
                      ),
                      const SizedBox(height: 22),
                      if (_error != null) _errorBox(),
                      HospitalStatGrid(
                        items: [
                          HospitalStatItem(
                            title: 'Total Doctors',
                            value: _doctors.length.toString(),
                            subtitle: 'Linked to this hospital',
                            icon: Icons.medical_services_rounded,
                            color: context.cAccentReadable,
                          ),
                          HospitalStatItem(
                            title: 'Available',
                            value: _count('available').toString(),
                            subtitle: 'Ready for appointments',
                            icon: Icons.check_circle_rounded,
                            color: CorviaColors.success,
                          ),
                          HospitalStatItem(
                            title: 'Busy',
                            value: _count('busy').toString(),
                            subtitle: 'Currently occupied',
                            icon: Icons.hourglass_top_rounded,
                            color: CorviaColors.warning,
                          ),
                          HospitalStatItem(
                            title: 'Off Duty',
                            value: _count('off_duty').toString(),
                            subtitle: 'Not currently available',
                            icon: Icons.event_busy_rounded,
                            color: context.cTextMuted,
                          ),
                        ],
                      ),
                      const SizedBox(height: 22),
                      HospitalPanel(
                        title: 'Hospital Doctor Directory',
                        subtitle:
                            '${doctors.length} doctor record(s) currently shown',
                        icon: Icons.medical_services_rounded,
                        child: Column(
                          children: [
                            HospitalSearchBox(
                              controller: _searchController,
                              hint:
                                  'Search doctor name, email, specialty or department',
                              onChanged: (_) {
                                setState(() {});
                              },
                            ),
                            const SizedBox(height: 14),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                'All',
                                'Available',
                                'Busy',
                                'Off Duty',
                                'Inactive',
                              ].map((item) {
                                return ChoiceChip(
                                  label: Text(item),
                                  selected: _filter == item,
                                  selectedColor: context.cAccentReadable
                                      .withValues(alpha: 0.12),
                                  onSelected: (_) {
                                    setState(() {
                                      _filter = item;
                                    });
                                  },
                                );
                              }).toList(),
                            ),
                            const SizedBox(height: 18),
                            if (doctors.isEmpty)
                              const HospitalEmptyState(
                                icon: Icons.medical_services_outlined,
                                title: 'No doctors found',
                                message:
                                    'Doctors linked to this hospital will appear here.',
                              )
                            else
                              ...doctors.map(
                                (doctor) => _DoctorCard(
                                  name: _name(doctor),
                                  email: _email(doctor),
                                  phone: _phone(doctor),
                                  specialty:
                                      doctor['specialization']?.toString() ??
                                          'General Practitioner',
                                  department: _departmentName(
                                    doctor['department_id'],
                                  ),
                                  room: doctor['room_name']?.toString() ??
                                      doctor['location']?.toString() ??
                                      'No room assigned',
                                  status: _statusLabel(_status(doctor)),
                                  statusColor: _statusColor(_status(doctor)),
                                  onManage: () {
                                    _manageDoctor(doctor);
                                  },
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
        'Could not load all doctor information. $_error',
        style: TextStyle(
          color: context.cTextPrimary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _DoctorCard extends StatelessWidget {
  const _DoctorCard({
    required this.name,
    required this.email,
    required this.phone,
    required this.specialty,
    required this.department,
    required this.room,
    required this.status,
    required this.statusColor,
    required this.onManage,
  });

  final String name;
  final String email;
  final String phone;
  final String specialty;
  final String department;
  final String room;
  final String status;
  final Color statusColor;
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
          final compact = constraints.maxWidth < 700;

          final details = Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
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
                  '$specialty • $department',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: context.cTextSecondary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '$email • $phone',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: context.cTextSecondary,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  room,
                  style: TextStyle(
                    color: context.cTextSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          );

          final avatar = Container(
            height: 50,
            width: 50,
            decoration: BoxDecoration(
              color: CorviaColors.success.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              Icons.medical_services_rounded,
              color: CorviaColors.success,
            ),
          );

          final action = Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              HospitalStatusPill(
                label: status,
                color: statusColor,
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: onManage,
                icon: const Icon(
                  Icons.edit_rounded,
                  size: 18,
                ),
                label: const Text('Manage'),
              ),
            ],
          );

          if (compact) {
            return Column(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    avatar,
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
              avatar,
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
