import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/nurse_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/text_controller_scope.dart';

class NurseMedicationRoundsPage extends StatefulWidget {
  const NurseMedicationRoundsPage({
    super.key,
    this.service,
    this.showAppBar = true,
  });

  final NurseService? service;

  /// The nurse workspace supplies the shared header when this page is embedded.
  final bool showAppBar;

  @override
  State<NurseMedicationRoundsPage> createState() =>
      _NurseMedicationRoundsPageState();
}

class _NurseMedicationRoundsPageState extends State<NurseMedicationRoundsPage> {
  final SupabaseClient _supabase = Supabase.instance.client;
  late final NurseService _service = widget.service ?? NurseService();
  NurseWorkspace? _workspace;

  final TextEditingController _searchController = TextEditingController();

  bool _isLoading = true;
  bool _isSaving = false;

  String? _errorMessage;
  String _selectedPatientFilter = 'all';

  String? get _nurseProfileId => _workspace?.context.profileId;

  List<Map<String, dynamic>> _assignments = [];
  List<Map<String, dynamic>> _prescriptions = [];
  List<Map<String, dynamic>> _todayLogs = [];

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
        _isLoading = true;
        _errorMessage = null;
      });
    }

    try {
      final workspace = await _service.loadWorkspace();
      if (!mounted) return;
      _workspace = workspace;
      _assignments = workspace.assignments;
      final patientIds = workspace.assignedPatientIds;
      if (_selectedPatientFilter != 'all' && !patientIds.contains(_selectedPatientFilter)) {
        _selectedPatientFilter = 'all';
      }
      await _loadPrescriptions(patientIds);
      await _loadTodayLogs(workspace.context.nurseUserId);

      if (!mounted) {
        return;
      }

      setState(() {
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isLoading = false;
        _errorMessage = error.toString();
      });
    }
  }

  Future<void> _loadPrescriptions(
    List<String> patientIds,
  ) async {
    _prescriptions = [];

    if (patientIds.isEmpty) {
      return;
    }

    try {
      final response = await _supabase
          .from('prescriptions')
          .select()
          .inFilter(
            'patient_id',
            patientIds,
          )
          .eq('status', 'active')
          .order(
            'created_at',
            ascending: false,
          );

      _prescriptions = List<Map<String, dynamic>>.from(
        response as List,
      );
    } catch (_) {
      final response = await _supabase.from('prescriptions').select().inFilter(
            'patient_id',
            patientIds,
          );

      _prescriptions = List<Map<String, dynamic>>.from(
        response as List,
      );
    }
  }

  Future<void> _loadTodayLogs(
    String userId,
  ) async {
    final now = DateTime.now();

    final todayStart = DateTime(
      now.year,
      now.month,
      now.day,
    ).toUtc();

    final response = await _supabase
        .from(
          'medication_administration_logs',
        )
        .select()
        .eq('nurse_user_id', userId)
        .eq('hospital_id', _workspace!.context.hospitalId)
        .gte(
          'recorded_at',
          todayStart.toIso8601String(),
        )
        .order(
          'recorded_at',
          ascending: false,
        );

    _todayLogs = List<Map<String, dynamic>>.from(
      response as List,
    );
  }

  String _firstText(
    List<dynamic> values, {
    required String fallback,
  }) {
    for (final value in values) {
      if (value != null && value.toString().trim().isNotEmpty) {
        return value.toString().trim();
      }
    }

    return fallback;
  }

  String _patientName(String patientId) =>
      _workspace!.patient(patientId).displayName;

  String _medicationName(
    Map<String, dynamic> prescription,
  ) {
    return _firstText(
      [
        prescription['medication_name'],
        prescription['medication'],
        prescription['medicine_name'],
        prescription['drug_name'],
        prescription['name'],
      ],
      fallback: 'Medication',
    );
  }

  String _dosage(
    Map<String, dynamic> prescription,
  ) {
    return _firstText(
      [
        prescription['dosage'],
        prescription['dose'],
        prescription['strength'],
      ],
      fallback: 'Dosage not recorded',
    );
  }

  String _frequency(
    Map<String, dynamic> prescription,
  ) {
    return _firstText(
      [
        prescription['frequency'],
        prescription['schedule'],
      ],
      fallback: 'Frequency not recorded',
    );
  }

  String _instructions(
    Map<String, dynamic> prescription,
  ) {
    return _firstText(
      [
        prescription['instructions'],
        prescription['notes'],
        prescription['special_instructions'],
      ],
      fallback: 'No additional instructions',
    );
  }

  Map<String, dynamic>? _assignmentForPatient(
    String patientId,
  ) {
    for (final assignment in _assignments) {
      if (assignment['patient_id']?.toString() == patientId) {
        return assignment;
      }
    }

    return null;
  }

  Map<String, dynamic>? _lastLogForPrescription(
    String prescriptionId,
  ) {
    for (final log in _todayLogs) {
      if (log['prescription_id']?.toString() == prescriptionId) {
        return log;
      }
    }

    return null;
  }

  List<Map<String, dynamic>> get _visiblePrescriptions {
    final search = _searchController.text.trim().toLowerCase();

    return _prescriptions.where((prescription) {
      final patientId = prescription['patient_id']?.toString() ?? '';

      final patient = _patientName(patientId).toLowerCase();

      final medication = _medicationName(prescription).toLowerCase();

      final matchesSearch = search.isEmpty ||
          patient.contains(search) ||
          medication.contains(search);

      final matchesPatient = _selectedPatientFilter == 'all' ||
          patientId == _selectedPatientFilter;

      return matchesSearch && matchesPatient;
    }).toList();
  }

  Future<void> _showRecordDialog(
    Map<String, dynamic> prescription,
  ) async {
    String selectedStatus = 'administered';

    // Null means cancelled; otherwise the notes typed into the dialog.
    final notes = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return TextControllerScope(
          builder: (notesController) {
            return StatefulBuilder(
              builder: (
                dialogContext,
                setDialogState,
              ) {
                return AlertDialog(
                  title: Text(
                    _medicationName(
                      prescription,
                    ),
                  ),
                  content: SizedBox(
                    width: 480,
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Patient: ${_patientName(prescription['patient_id'].toString())}',
                          ),
                          const SizedBox(
                            height: 8,
                          ),
                          Text(
                            'Dose: ${_dosage(prescription)}',
                          ),
                          const SizedBox(
                            height: 8,
                          ),
                          Text(
                            'Frequency: ${_frequency(prescription)}',
                          ),
                          const SizedBox(
                            height: 16,
                          ),
                          DropdownButtonFormField<String>(
                            initialValue: selectedStatus,
                            decoration: const InputDecoration(
                              labelText: 'Round Status',
                              border: OutlineInputBorder(),
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: 'administered',
                                child: Text(
                                  'Administered',
                                ),
                              ),
                              DropdownMenuItem(
                                value: 'skipped',
                                child: Text(
                                  'Skipped',
                                ),
                              ),
                              DropdownMenuItem(
                                value: 'refused',
                                child: Text(
                                  'Patient Refused',
                                ),
                              ),
                            ],
                            onChanged: (value) {
                              if (value != null) {
                                setDialogState(() {
                                  selectedStatus = value;
                                });
                              }
                            },
                          ),
                          const SizedBox(
                            height: 12,
                          ),
                          TextField(
                            controller: notesController,
                            minLines: 3,
                            maxLines: 6,
                            decoration: const InputDecoration(
                              labelText: 'Round Notes',
                              hintText:
                                  'Reason for skipped/refused or other notes',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () {
                        Navigator.of(
                          dialogContext,
                        ).pop();
                      },
                      child: const Text('Cancel'),
                    ),
                    ElevatedButton.icon(
                      onPressed: () {
                        Navigator.of(
                          dialogContext,
                        ).pop(notesController.text);
                      },
                      icon: const Icon(Icons.save),
                      label: const Text('Save'),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );

    if (notes != null) {
      await _recordMedicationRound(
        prescription: prescription,
        status: selectedStatus,
        notes: notes,
      );
    }
  }

  Future<void> _recordMedicationRound({
    required Map<String, dynamic> prescription,
    required String status,
    required String notes,
  }) async {
    if (_isSaving) {
      return;
    }

    final user = _supabase.auth.currentUser;

    if (user == null || user.id != _workspace?.context.nurseUserId) {
      _showMessage('Your nurse session changed. Please reload this page.');
      return;
    }

    final patientId = prescription['patient_id']?.toString();

    final prescriptionId = prescription['id']?.toString();

    if (patientId == null || prescriptionId == null) {
      _showMessage(
        'Prescription information is incomplete.',
      );
      return;
    }

    final assignment = _assignmentForPatient(patientId);

    if (assignment == null) {
      _showMessage(
        'No active patient assignment was found.',
      );
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      final now = DateTime.now().toUtc().toIso8601String();

      await _supabase
          .from(
        'medication_administration_logs',
      )
          .insert({
        'hospital_id': assignment['hospital_id'],
        'patient_id': patientId,
        'assignment_id': assignment['id'],
        'prescription_id': prescriptionId,
        'nurse_user_id': user.id,
        'nurse_profile_id': _nurseProfileId,
        'medication_name': _medicationName(
          prescription,
        ),
        'dosage': _dosage(prescription),
        'frequency': _frequency(prescription),
        'instructions': _instructions(prescription),
        'status': status,
        'scheduled_for': now,
        'administered_at': status == 'administered' ? now : null,
        'recorded_at': now,
        'notes': notes.trim(),
        'created_at': now,
        'updated_at': now,
      });

      await _loadTodayLogs(user.id);

      if (mounted) {
        setState(() {});
      }

      _showMessage(
        'Medication round recorded.',
      );
    } catch (error) {
      _showMessage(
        'Could not record medication round. $error',
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  Color _logColor(String status) {
    switch (status) {
      case 'administered':
        return CorviaColors.success;
      case 'refused':
        return CorviaColors.danger;
      default:
        return CorviaColors.warning;
    }
  }

  String _formatTime(dynamic value) {
    final date = DateTime.tryParse(
      value?.toString() ?? '',
    )?.toLocal();

    if (date == null) {
      return '';
    }

    return '${date.hour.toString().padLeft(2, '0')}:'
        '${date.minute.toString().padLeft(2, '0')}';
  }

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visiblePrescriptions;

    return Scaffold(
      backgroundColor: context.cBgPrimary,
      appBar: widget.showAppBar ? AppBar(
        title: const Text('Medication Rounds'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _isLoading ? null : _loadPage,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ) : null,
      body: _isLoading
          ? Center(
              child: CircularProgressIndicator(
                color: CorviaColors.accent,
              ),
            )
          : _errorMessage != null
              ? _buildErrorState()
              : RefreshIndicator(
                  onRefresh: _loadPage,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(18),
                    children: [
                      _buildHeader(),
                      const SizedBox(
                        height: 16,
                      ),
                      TextField(
                        controller: _searchController,
                        onChanged: (_) {
                          setState(() {});
                        },
                        decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.search),
                          hintText: 'Search medication or patient',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(
                        height: 12,
                      ),
                      DropdownButtonFormField<String>(
                        key: ValueKey(
                          _selectedPatientFilter,
                        ),
                        initialValue: _selectedPatientFilter,
                        decoration: const InputDecoration(
                          labelText: 'Filter by Patient',
                          border: OutlineInputBorder(),
                        ),
                        items: [
                          const DropdownMenuItem(
                            value: 'all',
                            child: Text('All Patients'),
                          ),
                          ..._workspace!.assignedPatientIds.map(
                            (patientId) {
                              return DropdownMenuItem(
                                value: patientId,
                                child: Text(
                                  _patientName(
                                    patientId,
                                  ),
                                ),
                              );
                            },
                          ),
                        ],
                        onChanged: (value) {
                          if (value != null) {
                            setState(() {
                              _selectedPatientFilter = value;
                            });
                          }
                        },
                      ),
                      const SizedBox(
                        height: 18,
                      ),
                      if (visible.isEmpty)
                        _buildEmptyState()
                      else
                        ...visible.map(
                          _buildPrescriptionCard,
                        ),
                    ],
                  ),
                ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            CorviaColors.accentDark,
            CorviaColors.accent,
          ],
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.medication_outlined,
            color: Colors.white,
            size: 42,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              '${_prescriptions.length} active prescription(s)\n'
              '${_todayLogs.length} round record(s) today',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                height: 1.5,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPrescriptionCard(
    Map<String, dynamic> prescription,
  ) {
    final patientId = prescription['patient_id']?.toString() ?? '';

    final prescriptionId = prescription['id']?.toString() ?? '';

    final lastLog = _lastLogForPrescription(
      prescriptionId,
    );

    final lastStatus = lastLog?['status']?.toString();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.cBgSecondary,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: context.cDivider,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.medication,
                color: CorviaColors.accent,
                size: 30,
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _medicationName(
                        prescription,
                      ),
                      style: TextStyle(
                        color: context.cTextPrimary,
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _patientName(patientId),
                      style: TextStyle(
                        color: context.cTextSecondary,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              if (lastStatus != null)
                _MedicationStatusPill(
                  label: '$lastStatus ${_formatTime(lastLog?['recorded_at'])}',
                  color: _logColor(lastStatus),
                ),
            ],
          ),
          const SizedBox(height: 13),
          Text(
            'Dose: ${_dosage(prescription)}',
            style: TextStyle(
              color: context.cTextPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            'Frequency: ${_frequency(prescription)}',
            style: TextStyle(
              color: context.cTextSecondary,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            _instructions(prescription),
            style: TextStyle(
              color: context.cTextSecondary,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isSaving
                  ? null
                  : () {
                      _showRecordDialog(
                        prescription,
                      );
                    },
              icon: const Icon(Icons.fact_check),
              label: const Text('Record Round'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: context.cBgSecondary,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: context.cDivider,
        ),
      ),
      child: Column(
        children: [
          Icon(
            Icons.medication_outlined,
            color: context.cTextMuted,
            size: 54,
          ),
          const SizedBox(height: 12),
          Text(
            'No active medication rounds',
            style: TextStyle(
              color: context.cTextPrimary,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            'Active prescriptions for your assigned patients will appear here.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: context.cTextSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline,
              color: CorviaColors.danger,
              size: 56,
            ),
            const SizedBox(height: 14),
            SelectableText(
              _errorMessage ?? 'Unknown error',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 18),
            ElevatedButton.icon(
              onPressed: _loadPage,
              icon: const Icon(Icons.refresh),
              label: const Text('Try Again'),
            ),
          ],
        ),
      ),
    );
  }
}

class _MedicationStatusPill extends StatelessWidget {
  const _MedicationStatusPill({
    required this.label,
    required this.color,
  });

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 8,
        vertical: 5,
      ),
      decoration: BoxDecoration(
        color: color.withValues(
          alpha: 0.12,
        ),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
