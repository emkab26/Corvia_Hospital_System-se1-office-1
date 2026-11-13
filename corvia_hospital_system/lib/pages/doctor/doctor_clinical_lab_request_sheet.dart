import 'package:flutter/material.dart';

import '../../services/doctor_clinical_service.dart';
import '../../theme/app_theme.dart';

class DoctorClinicalLabRequestSheet extends StatefulWidget {
  const DoctorClinicalLabRequestSheet({
    super.key,
    required this.doctorId,
  });

  final String doctorId;

  @override
  State<DoctorClinicalLabRequestSheet> createState() {
    return _DoctorClinicalLabRequestSheetState();
  }
}

class _DoctorClinicalLabRequestSheetState
    extends State<DoctorClinicalLabRequestSheet> {
  final DoctorClinicalService _service = DoctorClinicalService();

  final TextEditingController _otherTestController = TextEditingController();

  DoctorClinicalContext? _doctorContext;

  List<DoctorClinicalPatient> _patients = [];
  List<String> _tests = [];
  List<DoctorClinicalLabOrganization> _laboratories = [];

  String? _selectedPatientId;
  String? _selectedTest;
  String? _selectedLaboratoryId;
  bool _requiresDoctorReview = true;

  bool _loading = true;
  bool _submitting = false;

  String? _error;

  @override
  void initState() {
    super.initState();

    _load();
  }

  @override
  void dispose() {
    _otherTestController.dispose();

    super.dispose();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final doctorContext = await _service.currentContext();

      if (doctorContext.doctorId != widget.doctorId) {
        throw Exception(
          'The signed-in doctor does not match '
          'this lab workspace.',
        );
      }

      final patients = await _service.loadDoctorPatients(
        doctorContext,
      );

      final catalog = await _service.loadCatalog(
        doctorContext,
      );

      final laboratories = await _service.loadAvailableLabOrganizations();

      if (!mounted) {
        return;
      }

      setState(() {
        _doctorContext = doctorContext;

        _patients = patients;

        _tests = catalog.labTests;

        _laboratories = laboratories;

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

  String get _resolvedTest {
    if (_selectedTest == 'Other') {
      return _otherTestController.text.trim();
    }

    return _selectedTest?.trim() ?? '';
  }

  Future<void> _submit() async {
    if (_submitting) {
      return;
    }

    final doctorContext = _doctorContext;

    final patientId = _selectedPatientId;

    final testName = _resolvedTest;
    final laboratoryId = _selectedLaboratoryId;

    if (doctorContext == null) {
      _setError(
        'Doctor context is unavailable.',
      );

      return;
    }

    if (patientId == null || patientId.trim().isEmpty) {
      _setError(
        'Select a patient.',
      );

      return;
    }

    if (testName.isEmpty) {
      _setError(
        'Select or enter a lab test.',
      );

      return;
    }

    if (laboratoryId == null || laboratoryId.trim().isEmpty) {
      _setError('Select the laboratory that will receive this specimen.');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      await _service.createLabOrder(
        context: doctorContext,
        patientId: patientId,
        testName: testName,
        labOrganizationId: laboratoryId,
        requiresDoctorReview: _requiresDoctorReview,
      );

      if (!mounted) {
        return;
      }

      Navigator.of(context).pop(
        true,
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _error = 'Could not create lab request. '
            '${_cleanError(error)}';
      });
    } finally {
      if (mounted) {
        setState(() {
          _submitting = false;
        });
      }
    }
  }

  void _setError(
    String message,
  ) {
    if (!mounted) {
      return;
    }

    setState(() {
      _error = message;
    });
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

  @override
  Widget build(
    BuildContext context,
  ) {
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          12,
          20,
          20 + keyboardHeight,
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: context.cTextMuted,
                    borderRadius: BorderRadius.circular(
                      99,
                    ),
                  ),
                ),
              ),
              const SizedBox(
                height: 18,
              ),
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: CorviaColors.accent.withValues(
                        alpha: 0.12,
                      ),
                      borderRadius: BorderRadius.circular(
                        14,
                      ),
                    ),
                    child: Icon(
                      Icons.biotech_outlined,
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
                          'New Lab Request',
                          style: TextStyle(
                            color: context.cTextPrimary,
                            fontSize: 21,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(
                          height: 3,
                        ),
                        Text(
                          'Request a test, then send the specimen to '
                          'the selected laboratory.',
                          style: TextStyle(
                            color: context.cTextSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: _submitting
                        ? null
                        : () {
                            Navigator.of(
                              context,
                            ).pop();
                          },
                    icon: const Icon(
                      Icons.close,
                    ),
                  ),
                ],
              ),
              const SizedBox(
                height: 20,
              ),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.symmetric(
                    vertical: 45,
                  ),
                  child: Center(
                    child: CircularProgressIndicator(),
                  ),
                )
              else ...[
                if (_doctorContext != null)
                  _doctorCard(
                    _doctorContext!,
                  ),
                const SizedBox(
                  height: 15,
                ),
                DropdownButtonFormField<String>(
                  initialValue: _selectedPatientId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Patient',
                    prefixIcon: Icon(
                      Icons.person_outline,
                    ),
                    border: OutlineInputBorder(),
                  ),
                  items: _patients
                      .map(
                        (
                          patient,
                        ) =>
                            DropdownMenuItem<String>(
                          value: patient.id,
                          child: Text(
                            patient.name,
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
                            _selectedPatientId = value;
                          });
                        },
                ),
                const SizedBox(
                  height: 15,
                ),
                DropdownButtonFormField<String>(
                  initialValue: _selectedLaboratoryId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Receiving laboratory',
                    prefixIcon: Icon(Icons.local_hospital_outlined),
                    border: OutlineInputBorder(),
                  ),
                  items: _laboratories
                      .map(
                        (laboratory) => DropdownMenuItem<String>(
                          value: laboratory.id,
                          child: Text(
                            '${laboratory.name} · ${laboratory.typeLabel}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: _submitting || _laboratories.isEmpty
                      ? null
                      : (value) {
                          setState(() => _selectedLaboratoryId = value);
                        },
                ),
                if (_laboratories.isEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    'No receiving laboratory is available. Contact your hospital administrator to configure laboratory access.',
                    style: TextStyle(
                      color: CorviaColors.warning,
                      fontSize: 12,
                      height: 1.35,
                    ),
                  ),
                ],
                const SizedBox(
                  height: 15,
                ),
                DropdownButtonFormField<String>(
                  initialValue: _selectedTest,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Lab Test',
                    prefixIcon: Icon(
                      Icons.biotech_outlined,
                    ),
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    ..._tests,
                    'Other',
                  ]
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
                      hintText: 'Enter the requested investigation',
                      prefixIcon: Icon(
                        Icons.edit_outlined,
                      ),
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ],
              if (!_loading && _doctorContext != null) ...[
                const SizedBox(height: 16),
                DropdownButtonFormField<bool>(
                  initialValue: _requiresDoctorReview,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Patient result release',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(
                        value: true,
                        child: Text('Send to me for review first')),
                    DropdownMenuItem(
                        value: false,
                        child: Text('Release after lab verification')),
                  ],
                  onChanged: _submitting
                      ? null
                      : (value) {
                          if (value != null) {
                            setState(() => _requiresDoctorReview = value);
                          }
                        },
                ),
                const SizedBox(height: 8),
                Text(
                  _requiresDoctorReview
                      ? 'A verifier must approve the result. It then comes to you, as the ordering doctor, for review before you release it to the patient.'
                      : 'A verifier must approve the result before it becomes available to the patient automatically.',
                  style: TextStyle(color: context.cTextSecondary, fontSize: 12),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(
                  height: 15,
                ),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(
                    13,
                  ),
                  decoration: BoxDecoration(
                    color: CorviaColors.danger.withValues(
                      alpha: 0.10,
                    ),
                    borderRadius: BorderRadius.circular(
                      12,
                    ),
                    border: Border.all(
                      color: CorviaColors.danger.withValues(
                        alpha: 0.30,
                      ),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.error_outline,
                        color: CorviaColors.danger,
                      ),
                      const SizedBox(
                        width: 9,
                      ),
                      Expanded(
                        child: Text(
                          _error!,
                          style: TextStyle(
                            color: context.cTextPrimary,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(
                height: 22,
              ),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _loading || _submitting ? null : _submit,
                  icon: _submitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                          ),
                        )
                      : const Icon(
                          Icons.send,
                        ),
                  label: Text(
                    _submitting ? 'Submitting...' : 'Submit Lab Request',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _doctorCard(
    DoctorClinicalContext doctor,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(
        14,
      ),
      decoration: BoxDecoration(
        color: CorviaColors.accent.withValues(
          alpha: 0.10,
        ),
        borderRadius: BorderRadius.circular(
          14,
        ),
        border: Border.all(
          color: CorviaColors.accent.withValues(
            alpha: 0.25,
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.verified_user_outlined,
            color: context.cAccentReadable,
          ),
          const SizedBox(
            width: 10,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  doctor.doctorName,
                  style: TextStyle(
                    color: context.cTextPrimary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(
                  height: 3,
                ),
                Text(
                  doctor.hospitalId == null
                      ? 'Doctor identity linked automatically'
                      : 'Doctor, hospital and department '
                          'context linked automatically',
                  style: TextStyle(
                    color: context.cTextSecondary,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          Icon(
            Icons.verified,
            color: CorviaColors.success,
          ),
        ],
      ),
    );
  }
}
