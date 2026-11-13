import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../theme/app_theme.dart';

class HospitalDepartmentsPage extends StatefulWidget {
  const HospitalDepartmentsPage({super.key});

  @override
  State<HospitalDepartmentsPage> createState() =>
      _HospitalDepartmentsPageState();
}

class _HospitalDepartmentsPageState extends State<HospitalDepartmentsPage> {
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

  bool _loading = true;
  String? _error;
  String? _hospitalId;
  String _hospitalName = 'Hospital Departments';
  String _selectedFilter = 'All';

  List<Map<String, dynamic>> _departments = [];
  List<Map<String, dynamic>> _doctors = [];

  @override
  void initState() {
    super.initState();
    _loadDepartmentsPage();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadDepartmentsPage() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      await _loadHospitalContext();
      await _loadHospitalData();
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

    String hospitalName = 'Hospital Departments';
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
      _supabase
          .from('departments')
          .select()
          .eq('hospital_id', hospitalId)
          .order('name', ascending: true),
      _supabase
          .from('doctors')
          .select('id, department_id, status, is_active')
          .eq('hospital_id', hospitalId),
    ]);

    final departmentRows = results[0];
    final doctorRows = results[1];

    _departments = departmentRows
              .whereType<Map>()
              .map((row) => Map<String, dynamic>.from(row))
              .toList();

    _doctors = doctorRows
              .whereType<Map>()
              .map((row) => Map<String, dynamic>.from(row))
              .toList();
  }

  int _doctorCount(dynamic departmentId) {
    return _doctors.where((doctor) {
      return doctor['department_id']?.toString() == departmentId.toString();
    }).length;
  }

  int _availableDoctorCount(dynamic departmentId) {
    return _doctors.where((doctor) {
      final doctorDepartmentId = doctor['department_id']?.toString();
      final isActive = doctor['is_active'] != false;
      final status = doctor['status']?.toString().toLowerCase() ?? '';

      return doctorDepartmentId == departmentId.toString() &&
          isActive &&
          (status.isEmpty || status == 'available');
    }).length;
  }

  List<Map<String, dynamic>> get _visibleDepartments {
    final search = _searchController.text.trim().toLowerCase();

    return _departments.where((department) {
      final name = department['name']?.toString().toLowerCase() ?? '';
      final description =
          department['description']?.toString().toLowerCase() ?? '';
      final location =
          department['location_name']?.toString().toLowerCase() ?? '';

      final isActive = department['is_active'] != false;

      final matchesSearch =
          search.isEmpty ||
          name.contains(search) ||
          description.contains(search) ||
          location.contains(search);

      final matchesFilter = switch (_selectedFilter) {
        'Active' => isActive,
        'Inactive' => !isActive,
        'With Doctors' => _doctorCount(department['id']) > 0,
        _ => true,
      };

      return matchesSearch && matchesFilter;
    }).toList();
  }

  int get _activeDepartments {
    return _departments.where((department) {
      return department['is_active'] != false;
    }).length;
  }

  int get _inactiveDepartments {
    return _departments.where((department) {
      return department['is_active'] == false;
    }).length;
  }

  int get _departmentsWithDoctors {
    return _departments.where((department) {
      return _doctorCount(department['id']) > 0;
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

  Future<void> _showDepartmentEditor(Map<String, dynamic>? department) async {
    final isEditing = department != null;

    final nameController = TextEditingController(
      text: department?['name']?.toString() ?? '',
    );

    final descriptionController = TextEditingController(
      text: department?['description']?.toString() ?? '',
    );

    final locationController = TextEditingController(
      text: department?['location_name']?.toString() ?? '',
    );

    bool isActive = department?['is_active'] != false;
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
                  borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isEditing ? 'Manage Department' : 'Add Department',
                        style: TextStyle(
                          color: textDark,
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        isEditing
                            ? 'Update department details and availability.'
                            : 'Create a department for this hospital.',
                        style: TextStyle(color: mutedText, fontSize: 13),
                      ),
                      const SizedBox(height: 22),
                      TextField(
                        controller: nameController,
                        enabled: !saving,
                        decoration: const InputDecoration(
                          labelText: 'Department name',
                          hintText: 'Example: Emergency Department',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: locationController,
                        enabled: !saving,
                        decoration: const InputDecoration(
                          labelText: 'Location / Floor / Wing',
                          hintText: 'Example: Ground floor, East Wing',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: descriptionController,
                        enabled: !saving,
                        maxLines: 3,
                        decoration: const InputDecoration(
                          labelText: 'Department description',
                          hintText:
                              'What services does this department provide?',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 16),
                      // Transparent Material so the tile has a Material
                      // ancestor to paint its fill and ink onto. The sheet is
                      // transparent, so the white Container above would
                      // otherwise hide those effects.
                      Material(
                        type: MaterialType.transparency,
                        child: SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            'Department active',
                            style: TextStyle(
                              color: textDark,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          subtitle: Text(
                            isActive
                                ? 'Doctors and appointments can use this department.'
                                : 'This department is hidden from new assignments.',
                            style: TextStyle(color: mutedText, fontSize: 12),
                          ),
                          value: isActive,
                          activeThumbColor: success,
                          onChanged: saving
                              ? null
                              : (value) {
                                  setModalState(() {
                                    isActive = value;
                                  });
                                },
                        ),
                      ),
                      const SizedBox(height: 22),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: saving
                              ? null
                              : () async {
                                  final name = nameController.text.trim();

                                  if (name.isEmpty) {
                                    _showSnack(
                                      'Department name is required.',
                                      isError: true,
                                    );
                                    return;
                                  }

                                  setModalState(() {
                                    saving = true;
                                  });

                                  try {
                                    final data = <String, dynamic>{
                                      'name': name,
                                      'description':
                                          descriptionController.text
                                              .trim()
                                              .isEmpty
                                          ? null
                                          : descriptionController.text.trim(),
                                      'location_name':
                                          locationController.text.trim().isEmpty
                                          ? null
                                          : locationController.text.trim(),
                                      'is_active': isActive,
                                      'updated_at': DateTime.now()
                                          .toUtc()
                                          .toIso8601String(),
                                    };

                                    if (isEditing) {
                                      await _supabase
                                          .from('departments')
                                          .update(data)
                                          .eq('id', department['id'])
                                          .eq('hospital_id', _hospitalId!);
                                    } else {
                                      await _supabase
                                          .from('departments')
                                          .insert({
                                            ...data,
                                            'hospital_id': _hospitalId!,
                                            'created_at': DateTime.now()
                                                .toUtc()
                                                .toIso8601String(),
                                          });
                                    }

                                    if (sheetContext.mounted) {
                                      Navigator.of(sheetContext).pop();
                                    }

                                    await _loadDepartmentsPage();

                                    _showSnack(
                                      isEditing
                                          ? 'Department updated successfully.'
                                          : 'Department created successfully.',
                                    );
                                  } catch (e) {
                                    if (sheetContext.mounted) {
                                      setModalState(() {
                                        saving = false;
                                      });
                                    }

                                    _showSnack(
                                      'Could not save department: $e',
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
                              : Icon(
                                  isEditing
                                      ? Icons.save_rounded
                                      : Icons.add_rounded,
                                ),
                          label: Text(
                            saving
                                ? 'Saving...'
                                : isEditing
                                ? 'Save department changes'
                                : 'Create department',
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

    nameController.dispose();
    descriptionController.dispose();
    locationController.dispose();
  }

  Future<void> _toggleDepartmentStatus(Map<String, dynamic> department) async {
    final departmentId = department['id']?.toString();

    if (departmentId == null || departmentId.isEmpty) {
      _showSnack('Department has no valid ID.', isError: true);
      return;
    }

    final currentStatus = department['is_active'] != false;
    final newStatus = !currentStatus;

    try {
      await _supabase
          .from('departments')
          .update({
            'is_active': newStatus,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', departmentId)
          .eq('hospital_id', _hospitalId!);

      await _loadDepartmentsPage();

      _showSnack(
        newStatus ? 'Department activated.' : 'Department deactivated.',
      );
    } catch (e) {
      _showSnack('Could not update department: $e', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final departments = _visibleDepartments;

    return Scaffold(
      backgroundColor: background,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showDepartmentEditor(null),
        backgroundColor: primary,
        foregroundColor: Colors.white,
        icon: Icon(Icons.add_rounded),
        label: Text('Add Department'),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          color: accent,
          onRefresh: _loadDepartmentsPage,
          child: _loading
              ? Center(child: CircularProgressIndicator(color: accent))
              : SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 100),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildHeader(),
                      const SizedBox(height: 22),
                      if (_error != null) _buildErrorBox(),
                      _buildStats(),
                      const SizedBox(height: 22),
                      _buildDepartmentDirectory(departments),
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
                'Departments • $_hospitalName',
                style: TextStyle(
                  color: textDark,
                  fontSize: 27,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                'Manage departments, locations, active status and doctor assignment.',
                style: TextStyle(color: mutedText, fontSize: 14),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        OutlinedButton.icon(
          onPressed: _loadDepartmentsPage,
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
              'Could not load all department data. $_error',
              style: TextStyle(color: textDark, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStats() {
    final items = [
      _DepartmentStat(
        title: 'Total Departments',
        value: _departments.length.toString(),
        subtitle: 'All hospital departments',
        icon: Icons.local_hospital_rounded,
        color: accent,
      ),
      _DepartmentStat(
        title: 'Active',
        value: _activeDepartments.toString(),
        subtitle: 'Available for assignments',
        icon: Icons.check_circle_rounded,
        color: success,
      ),
      _DepartmentStat(
        title: 'With Doctors',
        value: _departmentsWithDoctors.toString(),
        subtitle: 'Department staff linked',
        icon: Icons.medical_services_rounded,
        color: warning,
      ),
      _DepartmentStat(
        title: 'Inactive',
        value: _inactiveDepartments.toString(),
        subtitle: 'Not accepting assignments',
        icon: Icons.pause_circle_rounded,
        color: error,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 1000;

        return GridView.builder(
          itemCount: items.length,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: isWide ? 4 : 2,
            mainAxisExtent: 205,
            mainAxisSpacing: 14,
            crossAxisSpacing: 14,
          ),
          itemBuilder: (context, index) {
            final item = items[index];

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
                      color: item.color.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(item.icon, color: item.color),
                  ),
                  const Spacer(),
                  Text(
                    item.value,
                    style: TextStyle(
                      color: textDark,
                      fontSize: 25,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    item.title,
                    style: TextStyle(
                      color: textDark,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    item.subtitle,
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

  Widget _buildDepartmentDirectory(List<Map<String, dynamic>> departments) {
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
              Icon(Icons.account_tree_rounded, color: accent),
              SizedBox(width: 10),
              Text(
                'Hospital Department Directory',
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
            '${departments.length} department(s) currently shown',
            style: TextStyle(color: mutedText, fontSize: 13),
          ),
          const SizedBox(height: 18),
          TextField(
            controller: _searchController,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: 'Search department, service or location',
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
            children: ['All', 'Active', 'Inactive', 'With Doctors'].map((
              filter,
            ) {
              return ChoiceChip(
                label: Text(filter),
                selected: _selectedFilter == filter,
                selectedColor: accent.withValues(alpha: 0.13),
                onSelected: (_) {
                  setState(() {
                    _selectedFilter = filter;
                  });
                },
              );
            }).toList(),
          ),
          const SizedBox(height: 20),
          if (departments.isEmpty)
            _buildEmptyState()
          else
            ...departments.map(_buildDepartmentCard),
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
          Icon(Icons.local_hospital_outlined, color: accent, size: 42),
          SizedBox(height: 12),
          Text(
            'No departments found',
            style: TextStyle(
              color: primary,
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
          SizedBox(height: 6),
          Text(
            'Create a department such as Emergency, General Practice or Cardiology.',
            textAlign: TextAlign.center,
            style: TextStyle(color: mutedText, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildDepartmentCard(Map<String, dynamic> department) {
    final name = department['name']?.toString() ?? 'Department';
    final description =
        department['description']?.toString() ??
        'No service description captured.';
    final location =
        department['location_name']?.toString() ?? 'No location assigned.';
    final isActive = department['is_active'] != false;
    final departmentColor = isActive ? success : error;
    final doctorCount = _doctorCount(department['id']);
    final availableDoctors = _availableDoctorCount(department['id']);

    return Container(
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

          final details = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                style: TextStyle(
                  color: textDark,
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                description,
                style: TextStyle(
                  color: mutedText,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _DepartmentPill(
                    icon: Icons.location_on_rounded,
                    label: location,
                    color: accent,
                  ),
                  _DepartmentPill(
                    icon: Icons.medical_services_rounded,
                    label: '$doctorCount doctor(s)',
                    color: warning,
                  ),
                  _DepartmentPill(
                    icon: Icons.check_circle_rounded,
                    label: '$availableDoctors available',
                    color: success,
                  ),
                ],
              ),
            ],
          );

          final actions = Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _DepartmentPill(
                icon: isActive
                    ? Icons.check_circle_rounded
                    : Icons.pause_circle_rounded,
                label: isActive ? 'Active' : 'Inactive',
                color: departmentColor,
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => _showDepartmentEditor(department),
                icon: Icon(Icons.edit_rounded, size: 18),
                label: Text('Manage'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: primary,
                  side: BorderSide(color: Color(0xFFE2E8F0)),
                ),
              ),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: () => _toggleDepartmentStatus(department),
                icon: Icon(
                  isActive
                      ? Icons.pause_circle_outline_rounded
                      : Icons.play_circle_outline_rounded,
                  size: 18,
                ),
                label: Text(isActive ? 'Deactivate' : 'Activate'),
                style: TextButton.styleFrom(
                  foregroundColor: isActive ? error : success,
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
                        color: departmentColor.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Icon(
                        Icons.local_hospital_rounded,
                        color: departmentColor,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: details),
                  ],
                ),
                const SizedBox(height: 14),
                actions,
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
                  color: departmentColor.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  Icons.local_hospital_rounded,
                  color: departmentColor,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(child: details),
              const SizedBox(width: 14),
              actions,
            ],
          );
        },
      ),
    );
  }
}

class _DepartmentStat {
  final String title;
  final String value;
  final String subtitle;
  final IconData icon;
  final Color color;

  const _DepartmentStat({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.icon,
    required this.color,
  });
}

class _DepartmentPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _DepartmentPill({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 240),
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
