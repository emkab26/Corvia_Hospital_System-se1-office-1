import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../services/doctor_clinical_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/error_messages.dart';

class AddPatientRecord extends StatefulWidget {
  const AddPatientRecord({
    super.key,
    required this.patientId,
    this.service,
  });

  final String patientId;
  final DoctorClinicalService? service;

  @override
  State<AddPatientRecord> createState() {
    return _AddPatientRecordState();
  }
}

class _AddPatientRecordState extends State<AddPatientRecord> {
  late final DoctorClinicalService _service;

  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  final TextEditingController _otherTreatmentController =
      TextEditingController();

  final TextEditingController _diagnosisController = TextEditingController();

  final TextEditingController _noteController = TextEditingController();

  final TextEditingController _otherTestController = TextEditingController();

  final TextEditingController _testResultController = TextEditingController();

  DoctorClinicalContext? _doctorContext;
  DoctorClinicalCatalog? _catalog;

  String? _selectedTreatment;
  String? _selectedTest;

  final List<String> _diagnoses = [];
  final List<String> _notes = [];

  final List<_PendingTestResult> _testResults = [];

  List<DoctorClinicalLabResult> _patientLabResults = [];

  String? _selectedPatientLabResultId;
  String? _labResultsLoadError;

  bool _loading = true;
  bool _submitting = false;

  String? _error;

  @override
  void initState() {
    super.initState();

    _service = widget.service ?? DoctorClinicalService();

    _load();
  }

  @override
  void dispose() {
    _otherTreatmentController.dispose();
    _diagnosisController.dispose();
    _noteController.dispose();
    _otherTestController.dispose();
    _testResultController.dispose();

    super.dispose();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
        _labResultsLoadError = null;
      });
    }

    try {
      final doctorContext = await _service.currentContext();

      final catalog = await _service.loadCatalog(
        doctorContext,
      );

      var patientLabResults = <DoctorClinicalLabResult>[];
      String? labResultsLoadError;

      try {
        patientLabResults = await _service.loadPatientCompletedLabResults(
          patientId: widget.patientId,
        );
      } catch (error) {
        debugPrint(
          'Patient lab results load failed: $error',
        );
        labResultsLoadError =
            'Existing lab results could not be loaded. Custom entry is still available.';
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _doctorContext = doctorContext;

        _catalog = catalog;

        _patientLabResults = patientLabResults;
        _labResultsLoadError = labResultsLoadError;

        _loading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _loading = false;

        _error = _cleanError(
          error,
        );
      });
    }
  }

  String get _resolvedTreatment {
    if (_selectedTreatment == 'Other') {
      return _otherTreatmentController.text.trim();
    }

    return _selectedTreatment?.trim() ?? '';
  }

  String get _resolvedTest {
    if (_selectedTest == 'Other') {
      return _otherTestController.text.trim();
    }

    return _selectedTest?.trim() ?? '';
  }

  void _addDiagnosis() {
    final value = _diagnosisController.text.trim();

    if (value.isEmpty) {
      return;
    }

    final alreadyExists = _diagnoses.any(
      (
        item,
      ) =>
          item.toLowerCase() == value.toLowerCase(),
    );

    if (alreadyExists) {
      _showMessage(
        'Diagnosis already added.',
      );

      return;
    }

    setState(() {
      _diagnoses.add(
        value,
      );

      _diagnosisController.clear();
    });
  }

  void _addNote() {
    final value = _noteController.text.trim();

    if (value.isEmpty) {
      return;
    }

    final alreadyExists = _notes.any(
      (
        item,
      ) =>
          item.toLowerCase() == value.toLowerCase(),
    );

    if (alreadyExists) {
      _showMessage(
        'Clinical note already added.',
      );

      return;
    }

    setState(() {
      _notes.add(
        value,
      );

      _noteController.clear();
    });
  }

  void _addTestResult() {
    final testName = _resolvedTest;

    final result = _testResultController.text.trim();

    if (testName.isEmpty) {
      _showMessage(
        'Select or enter a test first.',
      );

      return;
    }

    if (result.isEmpty) {
      _showMessage(
        'Enter the test result.',
      );

      return;
    }

    final duplicate = _testResults.any(
      (
        item,
      ) =>
          item.testName.toLowerCase() == testName.toLowerCase() &&
          item.result.toLowerCase() == result.toLowerCase(),
    );

    if (duplicate) {
      _showMessage(
        'This test result has already been added.',
      );

      return;
    }

    setState(() {
      _testResults.add(
        _PendingTestResult(
          testName: testName,
          result: result,
          sourceLabResultId: null,
        ),
      );

      _selectedTest = null;

      _otherTestController.clear();
      _testResultController.clear();
    });
  }

  DoctorClinicalLabResult? get _selectedPatientLabResult {
    final selectedId = _selectedPatientLabResultId;

    if (selectedId == null) {
      return null;
    }

    for (final result in _patientLabResults) {
      if (result.id == selectedId) {
        return result;
      }
    }

    return null;
  }

  String _patientLabResultLabel(DoctorClinicalLabResult result) {
    final date = result.createdAt == null
        ? 'Date unavailable'
        : DateFormat('d MMM yyyy').format(result.createdAt!.toLocal());
    final singleLineResult = result.result.replaceAll(RegExp(r'\s+'), ' ').trim();
    final preview = singleLineResult.length <= 45
        ? singleLineResult
        : '${singleLineResult.substring(0, 45)}...';

    return '${result.testName} • $date • $preview';
  }

  void _addExistingLabResult() {
    final selected = _selectedPatientLabResult;

    if (selected == null) {
      _showMessage('Select an existing patient lab result first.');
      return;
    }

    final alreadyAdded = _testResults.any(
      (item) => item.sourceLabResultId == selected.id,
    );

    if (alreadyAdded) {
      _showMessage('This patient lab result is already included.');
      return;
    }

    setState(() {
      _testResults.add(
        _PendingTestResult(
          testName: selected.testName,
          result: selected.result,
          sourceLabResultId: selected.id,
        ),
      );
      _selectedPatientLabResultId = null;
    });
  }

  Future<void> _submit() async {
    if (_submitting) {
      return;
    }

    if (!_formKey.currentState!.validate()) {
      return;
    }

    final doctorContext = _doctorContext;

    if (doctorContext == null) {
      _showMessage(
        'Doctor context is unavailable.',
      );

      return;
    }

    final treatment = _resolvedTreatment;

    if (treatment.isEmpty) {
      _showMessage(
        'Select or enter a treatment.',
      );

      return;
    }

    if (_diagnoses.isEmpty && _notes.isEmpty && _testResults.isEmpty) {
      _showMessage(
        'Add at least one diagnosis, '
        'clinical note or test result.',
      );

      return;
    }

    setState(() {
      _submitting = true;
    });

    try {
      final description = StringBuffer();

      description.writeln(
        'Doctor: ${doctorContext.doctorName}',
      );

      description.writeln(
        'Treatment: $treatment',
      );

      if (_diagnoses.isNotEmpty) {
        description.writeln(
          'Diagnosis: '
          '${_diagnoses.join(' | ')}',
        );
      }

      if (_testResults.isNotEmpty) {
        description.writeln(
          'Tests: '
          '${_testResults.map(
                (
                  item,
                ) =>
                    '${item.testName} '
                    '(${item.result})',
              ).join(' | ')}',
        );
      }

      if (_notes.isNotEmpty) {
        description.writeln(
          'Notes: '
          '${_notes.join(' | ')}',
        );
      }

      await _service.saveMedicalRecord(
        context: doctorContext,
        patientId: widget.patientId,
        recordType: 'treatment_plan',
        title: 'Treatment: $treatment',
        description: description.toString().trim(),
      );

      int failedLabUpdates = 0;

      for (final test in _testResults) {
        if (test.sourceLabResultId != null) {
          continue;
        }

        try {
          await _service.completeOrCreateLabResult(
            context: doctorContext,
            patientId: widget.patientId,
            testName: test.testName,
            result: test.result,
          );
        } catch (error) {
          debugPrint(
            'Lab result sync failed: '
            '$error',
          );

          failedLabUpdates++;
        }
      }

      if (!mounted) {
        return;
      }

      if (failedLabUpdates > 0) {
        _showMessage(
          'The medical record was saved, '
          'but $failedLabUpdates lab result(s) '
          'could not be synchronized.',
        );
      } else {
        _showMessage(
          'Patient record saved successfully.',
        );
      }

      Navigator.of(context).pop(
        true,
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      _showMessage(
        friendlyErrorMessage(
          error,
          whatFailed: "Couldn't save the patient record.",
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _submitting = false;
        });
      }
    }
  }

  String _cleanError(
    Object error,
  ) {
    return error
        .toString()
        .replaceFirst(
          'Exception: ',
          '',
        )
        .replaceFirst(
          'PostgrestException(message: ',
          '',
        );
  }

  void _showMessage(
    String message,
  ) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            message,
          ),
        ),
      );
  }

  @override
  Widget build(
    BuildContext context,
  ) {
    return Scaffold(
      backgroundColor: context.cBgPrimary,
      appBar: AppBar(
        title: const Text(
          'Add Patient Record',
        ),
      ),
      body: _loading
          ? Center(
              child: CircularProgressIndicator(
                color: CorviaColors.accent,
              ),
            )
          : _error != null
              ? _buildErrorState()
              : _buildForm(),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(
          24,
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: 520,
          ),
          child: Column(
            children: [
              Icon(
                Icons.error_outline,
                size: 56,
                color: CorviaColors.danger,
              ),
              const SizedBox(
                height: 14,
              ),
              Text(
                'Clinical record could not load',
                style: TextStyle(
                  color: context.cTextPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(
                height: 10,
              ),
              SelectableText(
                _error!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: context.cTextSecondary,
                ),
              ),
              const SizedBox(
                height: 18,
              ),
              FilledButton.icon(
                onPressed: _load,
                icon: const Icon(
                  Icons.refresh,
                ),
                label: const Text(
                  'Try Again',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildForm() {
    final doctor = _doctorContext!;

    final catalog = _catalog!;

    final treatmentItems = <String>[
      ...catalog.treatments,
      'Other',
    ];

    final testItems = <String>[
      ...catalog.labTests,
      'Other',
    ];

    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(
          18,
        ),
        children: [
          _buildDoctorBanner(
            doctor,
          ),
          const SizedBox(
            height: 22,
          ),

          // ======================================================
          // TREATMENT
          // ======================================================

          _sectionTitle(
            icon: Icons.health_and_safety_outlined,
            title: 'Treatment',
            subtitle: 'Select an existing option or choose Other.',
          ),
          const SizedBox(
            height: 10,
          ),
          DropdownButtonFormField<String>(
            initialValue: _selectedTreatment,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Treatment',
              prefixIcon: Icon(
                Icons.medical_services_outlined,
              ),
              border: OutlineInputBorder(),
            ),
            items: treatmentItems
                .map(
                  (
                    treatment,
                  ) =>
                      DropdownMenuItem<String>(
                    value: treatment,
                    child: Text(
                      treatment,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                )
                .toList(),
            onChanged: _submitting
                ? null
                : (
                    value,
                  ) {
                    setState(() {
                      _selectedTreatment = value;

                      if (value != 'Other') {
                        _otherTreatmentController.clear();
                      }
                    });
                  },
            validator: (
              value,
            ) {
              if (value == null || value.trim().isEmpty) {
                return 'Select a treatment.';
              }

              return null;
            },
          ),
          if (_selectedTreatment == 'Other') ...[
            const SizedBox(
              height: 12,
            ),
            TextFormField(
              controller: _otherTreatmentController,
              enabled: !_submitting,
              decoration: const InputDecoration(
                labelText: 'Custom Treatment',
                hintText: 'Enter the treatment provided',
                prefixIcon: Icon(
                  Icons.edit_outlined,
                ),
                border: OutlineInputBorder(),
              ),
              validator: (
                value,
              ) {
                if (_selectedTreatment == 'Other' &&
                    (value == null || value.trim().isEmpty)) {
                  return 'Enter the custom treatment.';
                }

                return null;
              },
            ),
          ],

          const SizedBox(
            height: 24,
          ),

          // ======================================================
          // DIAGNOSES
          // ======================================================

          _sectionTitle(
            icon: Icons.medical_information_outlined,
            title: 'Diagnoses',
            subtitle: 'Add one or more diagnoses for this record.',
          ),
          const SizedBox(
            height: 10,
          ),
          _textAdder(
            controller: _diagnosisController,
            label: 'Add Diagnosis',
            icon: Icons.medical_information_outlined,
            onAdd: _addDiagnosis,
          ),
          if (_diagnoses.isNotEmpty)
            _chipList(
              _diagnoses,
              onDelete: (
                value,
              ) {
                setState(() {
                  _diagnoses.remove(
                    value,
                  );
                });
              },
            ),

          const SizedBox(
            height: 24,
          ),

          // ======================================================
          // NOTES
          // ======================================================

          _sectionTitle(
            icon: Icons.note_alt_outlined,
            title: 'Clinical Notes',
            subtitle: 'Add observations and consultation notes.',
          ),
          const SizedBox(
            height: 10,
          ),
          _textAdder(
            controller: _noteController,
            label: 'Add Clinical Note',
            icon: Icons.note_add_outlined,
            onAdd: _addNote,
          ),
          if (_notes.isNotEmpty)
            _chipList(
              _notes,
              onDelete: (
                value,
              ) {
                setState(() {
                  _notes.remove(
                    value,
                  );
                });
              },
            ),

          const SizedBox(
            height: 24,
          ),

          // ======================================================
          // LAB RESULTS
          // ======================================================

          _sectionTitle(
            icon: Icons.biotech_outlined,
            title: 'Tests and Results',
            subtitle: 'Include an existing patient result or enter a custom '
                'test and result.',
          ),
          const SizedBox(
            height: 10,
          ),
          if (_labResultsLoadError != null) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: CorviaColors.warning.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: CorviaColors.warning.withValues(alpha: 0.30),
                ),
              ),
              child: Text(
                _labResultsLoadError!,
                style: TextStyle(color: context.cTextPrimary),
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (_patientLabResults.isNotEmpty) ...[
            DropdownButtonFormField<String>(
              key: ValueKey(_selectedPatientLabResultId),
              initialValue: _selectedPatientLabResultId,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Existing patient lab result',
                prefixIcon: Icon(Icons.history_rounded),
                border: OutlineInputBorder(),
              ),
              items: _patientLabResults
                  .map(
                    (result) => DropdownMenuItem<String>(
                      value: result.id,
                      child: Text(
                        _patientLabResultLabel(result),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(),
              onChanged: _submitting
                  ? null
                  : (value) {
                      setState(() {
                        _selectedPatientLabResultId = value;
                      });
                    },
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton.icon(
                onPressed: _submitting ? null : _addExistingLabResult,
                icon: const Icon(Icons.playlist_add_check_rounded),
                label: const Text('Include Existing Result'),
              ),
            ),
          ] else if (_labResultsLoadError == null) ...[
            Text(
              'This patient has no completed lab results to import yet.',
              style: TextStyle(color: context.cTextSecondary),
            ),
          ],
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 14),
            child: Row(
              children: [
                Expanded(child: Divider()),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 10),
                  child: Text('OR ADD A CUSTOM RESULT'),
                ),
                Expanded(child: Divider()),
              ],
            ),
          ),
          DropdownButtonFormField<String>(
            initialValue: _selectedTest,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Test or custom test',
              prefixIcon: Icon(
                Icons.biotech_outlined,
              ),
              border: OutlineInputBorder(),
            ),
            items: testItems
                .map(
                  (
                    test,
                  ) =>
                      DropdownMenuItem<String>(
                    value: test,
                    child: Text(
                      test,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                )
                .toList(),
            onChanged: _submitting
                ? null
                : (
                    value,
                  ) {
                    setState(() {
                      _selectedTest = value;

                      if (value != 'Other') {
                        _otherTestController.clear();
                      }
                    });
                  },
          ),
          if (_selectedTest == 'Other') ...[
            const SizedBox(
              height: 12,
            ),
            TextField(
              controller: _otherTestController,
              enabled: !_submitting,
              decoration: const InputDecoration(
                labelText: 'Custom Test',
                hintText: 'Enter the test name',
                prefixIcon: Icon(
                  Icons.edit_outlined,
                ),
                border: OutlineInputBorder(),
              ),
            ),
          ],
          const SizedBox(
            height: 12,
          ),
          TextField(
            controller: _testResultController,
            enabled: !_submitting,
            minLines: 1,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Result for Selected Test',
              hintText: 'Example: 6.2 mmol/L',
              prefixIcon: Icon(
                Icons.description_outlined,
              ),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(
            height: 10,
          ),
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton.icon(
              onPressed: _submitting ? null : _addTestResult,
              icon: const Icon(
                Icons.add,
              ),
              label: const Text(
                'Add Result',
              ),
            ),
          ),
          if (_testResults.isNotEmpty) ...[
            const SizedBox(
              height: 10,
            ),
            ..._testResults.map(
              (
                item,
              ) {
                return Card(
                  child: ListTile(
                    leading: Icon(
                      Icons.biotech,
                      color: context.cAccentReadable,
                    ),
                    title: Text(
                      item.testName,
                    ),
                    subtitle: Text(
                      item.sourceLabResultId == null
                          ? item.result
                          : 'Existing patient result • ${item.result}',
                    ),
                    trailing: IconButton(
                      tooltip: 'Remove',
                      onPressed: _submitting
                          ? null
                          : () {
                              setState(() {
                                _testResults.remove(
                                  item,
                                );
                              });
                            },
                      icon: Icon(
                        Icons.delete_outline,
                        color: CorviaColors.danger,
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
          const SizedBox(
            height: 28,
          ),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _submitting ? null : _submit,
              icon: _submitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                      ),
                    )
                  : const Icon(
                      Icons.save_outlined,
                    ),
              label: Text(
                _submitting ? 'Saving...' : 'Save Patient Record',
              ),
            ),
          ),
          const SizedBox(
            height: 30,
          ),
        ],
      ),
    );
  }

  Widget _buildDoctorBanner(
    DoctorClinicalContext doctor,
  ) {
    return Container(
      padding: const EdgeInsets.all(
        18,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            CorviaColors.accentDark,
            CorviaColors.accent,
          ],
        ),
        borderRadius: BorderRadius.circular(
          20,
        ),
      ),
      child: Row(
        children: [
          const CircleAvatar(
            radius: 27,
            backgroundColor: Colors.white,
            child: Icon(
              Icons.medical_services,
              color: Color(
                0xFF0F766E,
              ),
            ),
          ),
          const SizedBox(
            width: 13,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Recording Clinician',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 11,
                  ),
                ),
                const SizedBox(
                  height: 2,
                ),
                Text(
                  doctor.doctorName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 17,
                  ),
                ),
                const SizedBox(
                  height: 3,
                ),
                const Text(
                  'Doctor identity is linked automatically.',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          const Icon(
            Icons.verified,
            color: Colors.white,
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          icon,
          color: context.cAccentReadable,
        ),
        const SizedBox(
          width: 9,
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: context.cTextPrimary,
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(
                height: 2,
              ),
              Text(
                subtitle,
                style: TextStyle(
                  color: context.cTextSecondary,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _textAdder({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    required VoidCallback onAdd,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            enabled: !_submitting,
            minLines: 1,
            maxLines: 4,
            decoration: InputDecoration(
              labelText: label,
              prefixIcon: Icon(
                icon,
              ),
              border: const OutlineInputBorder(),
            ),
          ),
        ),
        const SizedBox(
          width: 8,
        ),
        SizedBox(
          height: 56,
          child: FilledButton(
            onPressed: _submitting ? null : onAdd,
            child: const Icon(
              Icons.add,
            ),
          ),
        ),
      ],
    );
  }

  Widget _chipList(
    List<String> values, {
    required void Function(
      String value,
    ) onDelete,
  }) {
    return Padding(
      padding: const EdgeInsets.only(
        top: 10,
      ),
      child: Wrap(
        spacing: 7,
        runSpacing: 7,
        children: values
            .map(
              (
                value,
              ) =>
                  InputChip(
                label: Text(
                  value,
                ),
                onDeleted: _submitting
                    ? null
                    : () {
                        onDelete(
                          value,
                        );
                      },
              ),
            )
            .toList(),
      ),
    );
  }
}

class _PendingTestResult {
  const _PendingTestResult({
    required this.testName,
    required this.result,
    required this.sourceLabResultId,
  });

  final String testName;
  final String result;
  final String? sourceLabResultId;
}
