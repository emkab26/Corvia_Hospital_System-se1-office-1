import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/nurse_service.dart';
import '../../theme/app_theme.dart';

class NurseObservationsPage extends StatefulWidget {
  const NurseObservationsPage({
    super.key,
    this.service,
    this.showAppBar = true,
    this.initialPatientId,
  });

  final String? initialPatientId;

  final NurseService? service;

  /// The nurse workspace supplies the shared header when this page is embedded.
  final bool showAppBar;

  @override
  State<NurseObservationsPage> createState() => _NurseObservationsPageState();
}

class _NurseObservationsPageState extends State<NurseObservationsPage> {
  final SupabaseClient _supabase = Supabase.instance.client;
  late final NurseService _service = widget.service ?? NurseService();
  NurseWorkspace? _workspace;

  final TextEditingController _temperatureController = TextEditingController();

  final TextEditingController _systolicController = TextEditingController();

  final TextEditingController _diastolicController = TextEditingController();

  final TextEditingController _pulseController = TextEditingController();

  final TextEditingController _oxygenController = TextEditingController();

  final TextEditingController _respiratoryController = TextEditingController();

  final TextEditingController _glucoseController = TextEditingController();

  final TextEditingController _painController = TextEditingController();

  final TextEditingController _notesController = TextEditingController();

  bool _isLoading = true;
  bool _isSaving = false;

  String? _errorMessage;
  String? _selectedPatientId;
  String? get _nurseProfileId => _workspace?.context.profileId;

  List<Map<String, dynamic>> _assignments = [];
  List<Map<String, dynamic>> _history = [];

  @override
  void initState() {
    super.initState();
    _loadPage();
  }

  @override
  void dispose() {
    _temperatureController.dispose();
    _systolicController.dispose();
    _diastolicController.dispose();
    _pulseController.dispose();
    _oxygenController.dispose();
    _respiratoryController.dispose();
    _glucoseController.dispose();
    _painController.dispose();
    _notesController.dispose();
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
      final previousContext = _workspace?.context;
      _workspace = workspace;
      _assignments = workspace.assignments;
      final patientIds = workspace.assignedPatientIds;
      final previousPatientId = _selectedPatientId;
      if (!patientIds.contains(_selectedPatientId)) {
        _selectedPatientId = patientIds.contains(widget.initialPatientId)
            ? widget.initialPatientId
            : patientIds.firstOrNull;
      }
      if (previousPatientId != null &&
          (previousPatientId != _selectedPatientId ||
           previousContext?.hospitalId != workspace.context.hospitalId ||
           previousContext?.nurseUserId != workspace.context.nurseUserId)) {
        _clearForm();
      }

      await _loadHistory();

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

  String _patientName(String patientId) =>
      _workspace!.patient(patientId).dropdownLabel;

  Future<void> _loadHistory() async {
    _history = [];

    final patientId = _selectedPatientId;
    final hospitalId = _workspace!.context.hospitalId;

    if (patientId == null) {
      _history = [];
      return;
    }

    final response = await _supabase
        .from('patient_observations')
        .select()
        .eq('patient_id', patientId)
        .eq('hospital_id', hospitalId)
        .order(
          'observed_at',
          ascending: false,
        )
        .limit(30);

    if (!mounted || _selectedPatientId != patientId ||
        _workspace?.context.hospitalId != hospitalId) {
      return;
    }
    _history = List<Map<String, dynamic>>.from(response as List);
  }

  double? _doubleValue(
    TextEditingController controller,
  ) {
    final text = controller.text.trim().replaceAll(',', '.');

    if (text.isEmpty) {
      return null;
    }

    return double.tryParse(text);
  }

  int? _intValue(
    TextEditingController controller,
  ) {
    final text = controller.text.trim();

    if (text.isEmpty) {
      return null;
    }

    return int.tryParse(text);
  }

  bool get _hasObservationValues {
    return [
      _temperatureController,
      _systolicController,
      _diastolicController,
      _pulseController,
      _oxygenController,
      _respiratoryController,
      _glucoseController,
      _painController,
      _notesController,
    ].any(
      (controller) => controller.text.trim().isNotEmpty,
    );
  }

  Future<void> _saveObservation() async {
    if (_isSaving) {
      return;
    }

    final user = _supabase.auth.currentUser;
    final patientId = _selectedPatientId;

    if (user == null || patientId == null ||
        user.id != _workspace?.context.nurseUserId) {
      _showMessage(
        'Select an assigned patient first.',
      );
      return;
    }

    if (!_hasObservationValues) {
      _showMessage(
        'Enter at least one observation or note.',
      );
      return;
    }

    final painScore = _intValue(_painController);

    if (painScore != null && (painScore < 0 || painScore > 10)) {
      _showMessage(
        'Pain score must be between 0 and 10.',
      );
      return;
    }

    final assignment = _assignmentForPatient(patientId);

    if (assignment == null) {
      _showMessage(
        'No active assignment was found.',
      );
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      final now = DateTime.now().toUtc().toIso8601String();

      await _supabase.from('patient_observations').insert({
        'hospital_id': assignment['hospital_id'],
        'assignment_id': assignment['id'],
        'patient_id': patientId,
        'nurse_user_id': user.id,
        'nurse_profile_id': _nurseProfileId,
        'temperature_c': _doubleValue(
          _temperatureController,
        ),
        'systolic_bp': _intValue(
          _systolicController,
        ),
        'diastolic_bp': _intValue(
          _diastolicController,
        ),
        'pulse_bpm': _intValue(
          _pulseController,
        ),
        'oxygen_saturation': _doubleValue(
          _oxygenController,
        ),
        'respiratory_rate': _intValue(
          _respiratoryController,
        ),
        'blood_glucose': _doubleValue(
          _glucoseController,
        ),
        'pain_score': painScore,
        'notes': _notesController.text.trim(),
        'observed_at': now,
        'created_at': now,
        'updated_at': now,
      });

      _clearForm();
      await _loadHistory();

      if (mounted) {
        setState(() {});
      }

      _showMessage(
        'Patient observations saved.',
      );
    } catch (error) {
      _showMessage(
        'Could not save observations. $error',
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  void _clearForm() {
    _temperatureController.clear();
    _systolicController.clear();
    _diastolicController.clear();
    _pulseController.clear();
    _oxygenController.clear();
    _respiratoryController.clear();
    _glucoseController.clear();
    _painController.clear();
    _notesController.clear();
  }

  String _formatDateTime(dynamic value) {
    final date = DateTime.tryParse(
      value?.toString() ?? '',
    )?.toLocal();

    if (date == null) {
      return 'Unknown time';
    }

    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/'
        '${date.year} '
        '${date.hour.toString().padLeft(2, '0')}:'
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
    return Scaffold(
      backgroundColor: context.cBgPrimary,
      appBar: widget.showAppBar ? AppBar(
        title: const Text(
          'Observations and Vitals',
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _isLoading ? null : _loadPage,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ) : null,
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return Center(
        child: CircularProgressIndicator(
          color: CorviaColors.accent,
        ),
      );
    }

    if (_errorMessage != null) {
      return _buildErrorState();
    }

    if (_assignments.isEmpty) {
      return _buildNoAssignmentsState();
    }

    return RefreshIndicator(
      onRefresh: _loadPage,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(18),
        children: [
          _buildPatientSelector(),
          const SizedBox(height: 16),
          _buildObservationForm(),
          const SizedBox(height: 20),
          Text(
            'Recent Observations',
            style: TextStyle(
              color: context.cTextPrimary,
              fontSize: 19,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          if (_history.isEmpty)
            _buildEmptyHistory()
          else
            ..._history.map(
              _buildHistoryCard,
            ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildPatientSelector() {
    final selectedAssignment = _selectedPatientId == null
        ? null
        : _assignmentForPatient(
            _selectedPatientId!,
          );

    return Container(
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
          Text(
            'Assigned Patient',
            style: TextStyle(
              color: context.cTextPrimary,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            key: ValueKey(
              _selectedPatientId,
            ),
            initialValue: _selectedPatientId,
            decoration: const InputDecoration(
              labelText: 'Patient',
              border: OutlineInputBorder(),
            ),
            isExpanded: true,
            items: _workspace!.assignedPatientIds.map(
              (patientId) {

                return DropdownMenuItem<String>(
                  value: patientId,
                  child: Text(
                    _patientName(patientId),
                    overflow: TextOverflow.ellipsis,
                  ),
                );
              },
            ).toList(),
            onChanged: _isSaving ? null : (value) async {
              setState(() {
                _clearForm();
                _history = [];
                _selectedPatientId = value;
              });

              await _loadHistory();

              if (mounted) {
                setState(() {});
              }
            },
          ),
          if (selectedAssignment != null) ...[
            const SizedBox(height: 10),
            Text(
              '${selectedAssignment['ward'] ?? 'No ward'} • '
              '${selectedAssignment['shift_type'] ?? 'No shift'}',
              style: TextStyle(
                color: context.cTextSecondary,
                fontSize: 13,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildObservationForm() {
    return Container(
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: context.cBgSecondary,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: context.cDivider,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Record New Observation',
            style: TextStyle(
              color: context.cTextPrimary,
              fontSize: 17,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (
              context,
              constraints,
            ) {
              final fieldWidth = constraints.maxWidth >= 700
                  ? (constraints.maxWidth - 12) / 2
                  : constraints.maxWidth;

              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _numberField(
                    width: fieldWidth,
                    controller: _temperatureController,
                    label: 'Temperature',
                    suffix: '°C',
                  ),
                  _numberField(
                    width: fieldWidth,
                    controller: _pulseController,
                    label: 'Pulse',
                    suffix: 'bpm',
                  ),
                  _numberField(
                    width: fieldWidth,
                    controller: _systolicController,
                    label: 'Systolic BP',
                    suffix: 'mmHg',
                    decimal: false,
                  ),
                  _numberField(
                    width: fieldWidth,
                    controller: _diastolicController,
                    label: 'Diastolic BP',
                    suffix: 'mmHg',
                    decimal: false,
                  ),
                  _numberField(
                    width: fieldWidth,
                    controller: _oxygenController,
                    label: 'Oxygen Saturation',
                    suffix: '%',
                  ),
                  _numberField(
                    width: fieldWidth,
                    controller: _respiratoryController,
                    label: 'Respiratory Rate',
                    suffix: '/min',
                    decimal: false,
                  ),
                  _numberField(
                    width: fieldWidth,
                    controller: _glucoseController,
                    label: 'Blood Glucose',
                    suffix: 'mmol/L',
                  ),
                  _numberField(
                    width: fieldWidth,
                    controller: _painController,
                    label: 'Pain Score (0–10)',
                    suffix: '/10',
                    decimal: false,
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _notesController,
            minLines: 3,
            maxLines: 6,
            decoration: const InputDecoration(
              labelText: 'Observation Notes',
              hintText: 'Patient condition, symptoms or concerns',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isSaving ? null : _saveObservation,
              icon: _isSaving
                  ? const SizedBox(
                      width: 17,
                      height: 17,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                      ),
                    )
                  : const Icon(Icons.save),
              label: Text(
                _isSaving ? 'Saving...' : 'Save Observation',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _numberField({
    required double width,
    required TextEditingController controller,
    required String label,
    required String suffix,
    bool decimal = true,
  }) {
    return SizedBox(
      width: width,
      child: TextField(
        controller: controller,
        keyboardType: TextInputType.numberWithOptions(
          decimal: decimal,
          signed: false,
        ),
        decoration: InputDecoration(
          labelText: label,
          suffixText: suffix,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }

  Widget _buildHistoryCard(
    Map<String, dynamic> observation,
  ) {
    final readings = <String>[];

    void addReading(
      String label,
      dynamic value,
      String suffix,
    ) {
      if (value != null) {
        readings.add(
          '$label: $value$suffix',
        );
      }
    }

    addReading(
      'Temp',
      observation['temperature_c'],
      '°C',
    );

    if (observation['systolic_bp'] != null ||
        observation['diastolic_bp'] != null) {
      readings.add(
        'BP: ${observation['systolic_bp'] ?? '--'}/'
        '${observation['diastolic_bp'] ?? '--'}',
      );
    }

    addReading(
      'Pulse',
      observation['pulse_bpm'],
      ' bpm',
    );

    addReading(
      'O₂',
      observation['oxygen_saturation'],
      '%',
    );

    addReading(
      'Resp',
      observation['respiratory_rate'],
      '/min',
    );

    addReading(
      'Glucose',
      observation['blood_glucose'],
      ' mmol/L',
    );

    addReading(
      'Pain',
      observation['pain_score'],
      '/10',
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: context.cBgSecondary,
        borderRadius: BorderRadius.circular(17),
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
                Icons.monitor_heart_outlined,
                color: CorviaColors.accent,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  _formatDateTime(
                    observation['observed_at'],
                  ),
                  style: TextStyle(
                    color: context.cTextPrimary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          if (readings.isNotEmpty) ...[
            const SizedBox(height: 11),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: readings
                  .map(
                    (reading) => Chip(
                      label: Text(reading),
                    ),
                  )
                  .toList(),
            ),
          ],
          if ((observation['notes']?.toString().trim() ?? '').isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              observation['notes'].toString(),
              style: TextStyle(
                color: context.cTextSecondary,
                fontSize: 13,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEmptyHistory() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: context.cBgSecondary,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: context.cDivider,
        ),
      ),
      child: Center(
        child: Text(
          'No observations have been recorded for this patient.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: context.cTextSecondary,
          ),
        ),
      ),
    );
  }

  Widget _buildNoAssignmentsState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          'No patients are assigned to this nurse account.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: context.cTextSecondary,
            fontSize: 16,
          ),
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: SingleChildScrollView(
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
            Text(
              'Could not load observations',
              style: TextStyle(
                color: context.cTextPrimary,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            SelectableText(
              _errorMessage ?? 'Unknown error',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: context.cTextSecondary,
              ),
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
