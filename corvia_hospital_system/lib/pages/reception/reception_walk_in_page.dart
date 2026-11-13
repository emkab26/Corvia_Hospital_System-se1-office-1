import 'package:flutter/material.dart';

import '../../services/reception_service.dart';
import '../../theme/app_theme.dart';

class ReceptionWalkInPage extends StatefulWidget {
  const ReceptionWalkInPage({
    super.key,
    required this.patient,
  });

  final ReceptionPatient patient;

  @override
  State<ReceptionWalkInPage> createState() => _ReceptionWalkInPageState();
}

class _ReceptionWalkInPageState extends State<ReceptionWalkInPage> {
  final ReceptionService _service = ReceptionService();
  final TextEditingController _reasonController = TextEditingController();

  List<ReceptionDepartment> _departments = <ReceptionDepartment>[];
  List<ReceptionDoctor> _doctors = <ReceptionDoctor>[];

  ReceptionDepartment? _selectedDepartment;
  ReceptionDoctor? _selectedDoctor;

  String _urgency = 'normal';

  bool _loading = true;
  bool _loadingDoctors = false;
  bool _saving = false;

  String? _error;

  @override
  void initState() {
    super.initState();
    _loadDepartments();
  }

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _loadDepartments() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final departments = await _service.loadDepartments();

      if (!mounted) {
        return;
      }

      setState(() {
        _departments = departments;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _error = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _changeDepartment(
    ReceptionDepartment? department,
  ) async {
    setState(() {
      _selectedDepartment = department;
      _selectedDoctor = null;
      _doctors = <ReceptionDoctor>[];
    });

    if (department == null) {
      return;
    }

    setState(() {
      _loadingDoctors = true;
    });

    try {
      final doctors = await _service.loadDoctors(department.id);

      if (!mounted || _selectedDepartment?.id != department.id) {
        return;
      }

      setState(() {
        _doctors = doctors;
      });
    } catch (error) {
      _snack('Doctors could not load: ${_cleanError(error)}');
    } finally {
      if (mounted) {
        setState(() {
          _loadingDoctors = false;
        });
      }
    }
  }

  Future<void> _changeUrgency(String? nextUrgency) async {
    if (nextUrgency == null || nextUrgency == _urgency) {
      return;
    }

    if (nextUrgency == 'normal') {
      setState(() {
        _urgency = nextUrgency;
      });
      return;
    }

    final label = nextUrgency == 'emergency' ? 'Emergency' : 'Urgent';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text('Mark as $label?'),
          content: Text(
            nextUrgency == 'emergency'
                ? 'This places the patient at the top of Reception queue. Follow hospital emergency escalation protocol. Reception does not diagnose.'
                : 'This places the patient above normal queue entries.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text('Mark $label'),
            ),
          ],
        );
      },
    );

    if (confirmed == true && mounted) {
      setState(() {
        _urgency = nextUrgency;
      });
    }
  }

  Future<void> _saveWalkIn() async {
    final department = _selectedDepartment;
    final reason = _reasonController.text.trim();

    if (department == null) {
      _snack('Select a department first.');
      return;
    }

    if (reason.length < 3) {
      _snack('Enter a short reason for the visit.');
      return;
    }

    setState(() {
      _saving = true;
    });

    try {
      await _service.createWalkIn(
        patientId: widget.patient.id,
        departmentId: department.id,
        doctorId: _selectedDoctor?.id,
        reason: reason,
        urgency: _urgency,
      );

      if (!mounted) {
        return;
      }

      _snack('Walk-in check-in created successfully.');
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) {
        return;
      }

      _snack(_friendlyWalkInError(error));
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  String _friendlyWalkInError(Object error) {
    final raw = error.toString().toLowerCase();

    if (raw.contains('already has an active check-in today') ||
        raw.contains('active check-in')) {
      return 'This patient is already checked in today. Open Reception Queue to manage the active visit.';
    }

    if (raw.contains('permission denied')) {
      return 'You do not have permission to create this walk-in check-in.';
    }

    if (raw.contains('network') ||
        raw.contains('socketexception') ||
        raw.contains('failed host lookup')) {
      return 'Could not connect to the hospital system. Check your internet connection and try again.';
    }

    return 'Could not create the walk-in check-in. Please try again.';
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  String _cleanError(Object error) {
    return error
        .toString()
        .replaceFirst('Exception: ', '')
        .replaceAll('PostgrestException(message: ', '')
        .replaceAll(')', '');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.cBgPrimary,
      appBar: AppBar(
        title: const Text('New Walk-In'),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(),
            )
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      _cleanError(_error!),
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : SafeArea(
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      _patientCard(),
                      const SizedBox(height: 20),
                      Text(
                        'Walk-In Details',
                        style: TextStyle(
                          color: context.cTextPrimary,
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<ReceptionDepartment>(
                        initialValue: _selectedDepartment,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Department',
                          prefixIcon: Icon(Icons.local_hospital_rounded),
                        ),
                        items: _departments
                            .map(
                              (department) => DropdownMenuItem(
                                value: department,
                                child: Text(
                                  department.locationName.isEmpty
                                      ? department.name
                                      : '${department.name} • ${department.locationName}',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: _saving ? null : _changeDepartment,
                      ),
                      const SizedBox(height: 14),
                      if (_loadingDoctors)
                        const Center(
                          child: Padding(
                            padding: EdgeInsets.all(14),
                            child: CircularProgressIndicator(),
                          ),
                        )
                      else
                        DropdownButtonFormField<ReceptionDoctor>(
                          initialValue: _selectedDoctor,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Doctor (optional)',
                            prefixIcon: Icon(Icons.person_outline_rounded),
                          ),
                          items: [
                            const DropdownMenuItem<ReceptionDoctor>(
                              value: null,
                              child: Text('No doctor selected yet'),
                            ),
                            ..._doctors.map(
                              (doctor) => DropdownMenuItem(
                                value: doctor,
                                child: Text(
                                  '${doctor.name} • ${doctor.statusLabel}',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                          ],
                          onChanged: _selectedDepartment == null || _saving
                              ? null
                              : (doctor) {
                                  setState(() {
                                    _selectedDoctor = doctor;
                                  });
                                },
                        ),
                      const SizedBox(height: 14),
                      DropdownButtonFormField<String>(
                        initialValue: _urgency,
                        decoration: const InputDecoration(
                          labelText: 'Urgency',
                          prefixIcon: Icon(Icons.priority_high_rounded),
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'normal',
                            child: Text('Normal'),
                          ),
                          DropdownMenuItem(
                            value: 'urgent',
                            child: Text('Urgent'),
                          ),
                          DropdownMenuItem(
                            value: 'emergency',
                            child: Text('Emergency escalation'),
                          ),
                        ],
                        onChanged: _saving ? null : _changeUrgency,
                      ),
                      if (_urgency == 'emergency') ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.red.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: Colors.red.withValues(alpha: 0.45),
                            ),
                          ),
                          child: const Row(
                            children: [
                              Icon(
                                Icons.warning_amber_rounded,
                                color: Colors.red,
                              ),
                              SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Emergency escalation selected. Follow hospital emergency procedure immediately.',
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 14),
                      TextField(
                        controller: _reasonController,
                        enabled: !_saving,
                        maxLines: 3,
                        decoration: const InputDecoration(
                          labelText: 'Reason for visit',
                          hintText: 'Example: Follow-up consultation',
                          alignLabelWithHint: true,
                          prefixIcon: Icon(Icons.notes_rounded),
                        ),
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: _saving ? null : _saveWalkIn,
                          icon: _saving
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.check_circle_rounded),
                          label: Text(
                            _saving
                                ? 'Creating Check-In...'
                                : 'Create Walk-In Check-In',
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
    );
  }

  Widget _patientCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.cBgSecondary,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: CorviaColors.accent.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: CorviaColors.accent.withValues(alpha: 0.14),
            child: Icon(
              Icons.person_rounded,
              color: CorviaColors.accent,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.patient.fullName,
                  style: TextStyle(
                    color: context.cTextPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  widget.patient.patientNumber,
                  style: TextStyle(
                    color: context.cTextSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
