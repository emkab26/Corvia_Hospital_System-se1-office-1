import 'package:intl/intl.dart';
import 'package:flutter/material.dart';

import '../../services/hospital_admission_service.dart';
import '../../theme/app_theme.dart';
import 'hospital_structure_page.dart';

class HospitalAdmissionsPage extends StatefulWidget {
  const HospitalAdmissionsPage({
    super.key,
    this.initialHospitalId,
  });

  final String? initialHospitalId;

  @override
  State<HospitalAdmissionsPage> createState() => _HospitalAdmissionsPageState();
}

class _HospitalAdmissionsPageState extends State<HospitalAdmissionsPage> {
  final HospitalAdmissionService _service = HospitalAdmissionService();

  final TextEditingController _searchController = TextEditingController();

  bool _loading = true;
  bool _actionBusy = false;

  String? _error;
  String? _selectedHospitalId;

  String _selectedStatusFilter = 'active';

  List<Map<String, dynamic>> _hospitals = [];
  HospitalAdmissionWorkspace? _workspace;

  static const String _noBedValue = '__no_bed__';

  static const List<String> _admissionTypes = [
    'elective',
    'emergency',
    'day_case',
    'transfer',
    'maternity',
    'paediatric',
    'mental_health',
    'observation',
  ];

  static const List<String> _visitorStatuses = [
    'visitors_allowed',
    'family_only',
    'approved_visitors_only',
    'primary_contact_only',
    'ward_approval_required',
    'icu_approval_required',
    'temporarily_restricted',
    'infection_isolation',
    'no_visitors',
    'security_restricted',
    'end_of_life_exception',
  ];

  static const List<String> _sourceTypes = [
    'direct',
    'emergency',
    'referral',
    'interhospital_transfer',
  ];

  static const List<String> _statusFilters = [
    'active',
    'all',
    'planned',
    'admitted',
    'discharged',
    'transferred',
    'cancelled',
  ];

  @override
  void initState() {
    super.initState();

    _searchController.addListener(_handleSearchChanged);

    _loadInitialData();
  }

  @override
  void dispose() {
    _searchController.removeListener(_handleSearchChanged);
    _searchController.dispose();

    super.dispose();
  }

  void _handleSearchChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _loadInitialData() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final hospitals = await _service.getAdminHospitals();

      if (hospitals.isEmpty) {
        throw Exception(
          'This admin account is not linked to a hospital.',
        );
      }

      final initialHospitalExists = hospitals.any(
        (hospital) => hospital['id']?.toString() == widget.initialHospitalId,
      );

      final hospitalId = initialHospitalExists
          ? widget.initialHospitalId
          : hospitals.first['id']?.toString();

      if (hospitalId == null || hospitalId.trim().isEmpty) {
        throw Exception(
          'No valid hospital ID was found for this account.',
        );
      }

      _hospitals = hospitals;
      _selectedHospitalId = hospitalId;

      await _loadWorkspace();
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  Future<void> _loadWorkspace() async {
    final hospitalId = _selectedHospitalId;

    if (hospitalId == null || hospitalId.isEmpty) {
      return;
    }

    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final workspace = await _service.loadWorkspace(
        hospitalId,
      );

      if (!mounted) return;

      setState(() {
        _workspace = workspace;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  String get _hospitalName {
    final hospitalId = _selectedHospitalId;

    for (final hospital in _hospitals) {
      if (hospital['id']?.toString() == hospitalId) {
        return hospital['name']?.toString() ?? 'Hospital';
      }
    }

    return 'Hospital';
  }

  List<HospitalAdmissionRecord> get _filteredAdmissions {
    final admissions = _workspace?.admissions ?? <HospitalAdmissionRecord>[];

    final search = _searchController.text.trim().toLowerCase();

    return admissions.where((admission) {
      final matchesSearch =
          search.isEmpty || admission.searchText.contains(search);

      bool matchesStatus;

      switch (_selectedStatusFilter) {
        case 'active':
          matchesStatus =
              admission.status == 'planned' || admission.status == 'admitted';
          break;

        case 'all':
          matchesStatus = true;
          break;

        default:
          matchesStatus = admission.status == _selectedStatusFilter;
      }

      return matchesSearch && matchesStatus;
    }).toList();
  }

  InputDecoration _inputDecoration(
    String label, {
    String? hint,
    IconData? prefixIcon,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: prefixIcon == null
          ? null
          : Icon(
              prefixIcon,
              color: context.cAccentReadable,
            ),
      filled: true,
      fillColor: context.cBgPrimary,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(
          color: context.cDivider,
        ),
      ),
    );
  }

  String _humanize(dynamic value) {
    final raw = value?.toString().trim() ?? '';

    if (raw.isEmpty) {
      return 'Not set';
    }

    return raw.split('_').where((part) => part.isNotEmpty).map((part) {
      if (part.length == 1) {
        return part.toUpperCase();
      }

      return '${part[0].toUpperCase()}${part.substring(1)}';
    }).join(' ');
  }

  String _formatDateTime(DateTime? value) {
    if (value == null) {
      return 'Not set';
    }

    final local = value.toLocal();

    return '${local.year}-'
        '${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')} '
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }

  String _formatDate(DateTime? value) {
    if (value == null) {
      return 'Not set';
    }

    final local = value.toLocal();

    return '${local.year}-'
        '${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')}';
  }

  Color _statusColor(
    BuildContext context,
    String status,
  ) {
    switch (status) {
      case 'admitted':
        return CorviaColors.success;

      case 'planned':
        return CorviaColors.warning;

      case 'discharged':
        return context.cAccentReadable;

      case 'transferred':
        return Colors.indigo;

      case 'cancelled':
        return Colors.grey;

      case 'deceased':
        return CorviaColors.danger;

      default:
        return context.cAccentReadable;
    }
  }

  void _showSnack(
    String message, {
    bool error = false,
  }) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? CorviaColors.danger : CorviaColors.accentDark,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _showCreateAdmissionDialog() async {
    final workspace = _workspace;

    if (workspace == null) {
      return;
    }

    if (workspace.patients.isEmpty) {
      _showSnack(
        'No patients are linked to this hospital yet.',
        error: true,
      );
      return;
    }

    final reasonController = TextEditingController();
    final diagnosisController = TextEditingController();

    String selectedPatientId = workspace.patients.first.patientId;

    String selectedAdmissionType = 'elective';
    String selectedAdmissionStatus = 'admitted';
    String selectedVisitorStatus = 'approved_visitors_only';
    String selectedSourceType = 'direct';
    String selectedBedId = _noBedValue;

    DateTime? expectedDischargeDate;
    bool saving = false;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final availableBeds = workspace.availableBeds;

            return AlertDialog(
              backgroundColor: context.cBgSecondary,
              title: const Text(
                'Create Hospital Admission',
              ),
              content: SizedBox(
                width: 650,
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      DropdownButtonFormField<String>(
                        initialValue: selectedPatientId,
                        isExpanded: true,
                        decoration: _inputDecoration(
                          'Patient',
                          prefixIcon: Icons.person_rounded,
                        ),
                        items: workspace.patients.map((patient) {
                          return DropdownMenuItem<String>(
                            value: patient.patientId,
                            child: Text(
                              '${patient.patientName} • '
                              '${patient.displayPatientNumber}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          );
                        }).toList(),
                        onChanged: saving
                            ? null
                            : (value) {
                                if (value != null) {
                                  setDialogState(() {
                                    selectedPatientId = value;
                                  });
                                }
                              },
                      ),
                      const SizedBox(height: 12),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final compact = constraints.maxWidth < 520;

                          final admissionType = DropdownButtonFormField<String>(
                            initialValue: selectedAdmissionType,
                            isExpanded: true,
                            decoration: _inputDecoration(
                              'Admission type',
                            ),
                            items: _admissionTypes.map((type) {
                              return DropdownMenuItem<String>(
                                value: type,
                                child: Text(_humanize(type)),
                              );
                            }).toList(),
                            onChanged: saving
                                ? null
                                : (value) {
                                    if (value != null) {
                                      setDialogState(() {
                                        selectedAdmissionType = value;

                                        if (value == 'emergency') {
                                          selectedSourceType = 'emergency';
                                        }

                                        if (value == 'transfer') {
                                          selectedSourceType =
                                              'interhospital_transfer';
                                        }

                                        if (value == 'maternity') {
                                          selectedVisitorStatus =
                                              'approved_visitors_only';
                                        }

                                        if (value == 'mental_health') {
                                          selectedVisitorStatus =
                                              'ward_approval_required';
                                        }
                                      });
                                    }
                                  },
                          );

                          final status = DropdownButtonFormField<String>(
                            initialValue: selectedAdmissionStatus,
                            isExpanded: true,
                            decoration: _inputDecoration(
                              'Initial status',
                            ),
                            items: const [
                              DropdownMenuItem<String>(
                                value: 'admitted',
                                child: Text('Admitted now'),
                              ),
                              DropdownMenuItem<String>(
                                value: 'planned',
                                child: Text(
                                  'Planned admission',
                                ),
                              ),
                            ],
                            onChanged: saving
                                ? null
                                : (value) {
                                    if (value != null) {
                                      setDialogState(() {
                                        selectedAdmissionStatus = value;

                                        if (value == 'planned') {
                                          selectedBedId = _noBedValue;
                                        }
                                      });
                                    }
                                  },
                          );

                          if (compact) {
                            return Column(
                              children: [
                                admissionType,
                                const SizedBox(height: 12),
                                status,
                              ],
                            );
                          }

                          return Row(
                            children: [
                              Expanded(child: admissionType),
                              const SizedBox(width: 12),
                              Expanded(child: status),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: selectedSourceType,
                        isExpanded: true,
                        decoration: _inputDecoration(
                          'Admission source',
                        ),
                        items: _sourceTypes.map((source) {
                          return DropdownMenuItem<String>(
                            value: source,
                            child: Text(_humanize(source)),
                          );
                        }).toList(),
                        onChanged: saving
                            ? null
                            : (value) {
                                if (value != null) {
                                  setDialogState(() {
                                    selectedSourceType = value;
                                  });
                                }
                              },
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: selectedVisitorStatus,
                        isExpanded: true,
                        decoration: _inputDecoration(
                          'Visitor access status',
                        ),
                        items: _visitorStatuses.map((status) {
                          return DropdownMenuItem<String>(
                            value: status,
                            child: Text(_humanize(status)),
                          );
                        }).toList(),
                        onChanged: saving
                            ? null
                            : (value) {
                                if (value != null) {
                                  setDialogState(() {
                                    selectedVisitorStatus = value;
                                  });
                                }
                              },
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: reasonController,
                        maxLines: 3,
                        decoration: _inputDecoration(
                          'Admission reason',
                          hint: 'Reason for hospital admission',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: diagnosisController,
                        maxLines: 3,
                        decoration: _inputDecoration(
                          'Admitting diagnosis or clinical note',
                          hint: 'Initial diagnosis or clinical information',
                        ),
                      ),
                      const SizedBox(height: 12),
                      InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: saving
                            ? null
                            : () async {
                                final selectedDate = await showDatePicker(
                                  context: dialogContext,
                                  initialDate: expectedDischargeDate ??
                                      DateTime.now().add(
                                        const Duration(
                                          days: 1,
                                        ),
                                      ),
                                  firstDate: DateTime.now(),
                                  lastDate: DateTime.now().add(
                                    const Duration(
                                      days: 3650,
                                    ),
                                  ),
                                );

                                if (selectedDate != null) {
                                  setDialogState(() {
                                    expectedDischargeDate = selectedDate;
                                  });
                                }
                              },
                        child: InputDecorator(
                          decoration: _inputDecoration(
                            'Expected discharge date',
                            prefixIcon: Icons.event_rounded,
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  expectedDischargeDate == null
                                      ? 'No expected date selected'
                                      : _formatDate(
                                          expectedDischargeDate,
                                        ),
                                  style: TextStyle(
                                    color: expectedDischargeDate == null
                                        ? context.cTextSecondary
                                        : context.cTextPrimary,
                                  ),
                                ),
                              ),
                              if (expectedDischargeDate != null)
                                IconButton(
                                  tooltip: 'Clear expected date',
                                  onPressed: saving
                                      ? null
                                      : () {
                                          setDialogState(() {
                                            expectedDischargeDate = null;
                                          });
                                        },
                                  icon: const Icon(
                                    Icons.close_rounded,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                      if (selectedAdmissionStatus == 'admitted') ...[
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          key: ValueKey(
                            'create-$selectedAdmissionStatus-'
                            '$selectedBedId',
                          ),
                          initialValue: selectedBedId,
                          isExpanded: true,
                          decoration: _inputDecoration(
                            'Initial bed assignment',
                            hint: 'Bed assignment is optional',
                            prefixIcon: Icons.bed_rounded,
                          ),
                          items: [
                            const DropdownMenuItem<String>(
                              value: _noBedValue,
                              child: Text(
                                'Admit without assigning a bed',
                              ),
                            ),
                            ...availableBeds.map((bed) {
                              return DropdownMenuItem<String>(
                                value: bed.bedId,
                                child: Text(
                                  bed.displayLocation,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              );
                            }),
                          ],
                          onChanged: saving
                              ? null
                              : (value) {
                                  if (value != null) {
                                    setDialogState(() {
                                      selectedBedId = value;
                                    });
                                  }
                                },
                        ),
                      ],
                      if (selectedAdmissionStatus == 'admitted' &&
                          availableBeds.isEmpty) ...[
                        const SizedBox(height: 10),
                        _DialogNotice(
                          icon: Icons.warning_amber_rounded,
                          message:
                              'No available beds are currently configured. '
                              'The patient can still be admitted without a bed.',
                          color: CorviaColors.warning,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: saving
                      ? null
                      : () {
                          Navigator.of(dialogContext).pop();
                        },
                  child: const Text('Cancel'),
                ),
                FilledButton.icon(
                  onPressed: saving
                      ? null
                      : () async {
                          setDialogState(() {
                            saving = true;
                          });

                          try {
                            final admissionId = await _service.createAdmission(
                              hospitalId: _selectedHospitalId!,
                              patientId: selectedPatientId,
                              admissionType: selectedAdmissionType,
                              status: selectedAdmissionStatus,
                              admissionReason: reasonController.text,
                              admittingDiagnosis: diagnosisController.text,
                              expectedDischargeAt: expectedDischargeDate,
                              visitorStatus: selectedVisitorStatus,
                              sourceType: selectedSourceType,
                            );

                            if (selectedAdmissionStatus == 'admitted' &&
                                selectedBedId != _noBedValue) {
                              await _service.assignBed(
                                admissionId: admissionId,
                                bedId: selectedBedId,
                              );
                            }

                            if (!dialogContext.mounted) {
                              return;
                            }

                            Navigator.of(dialogContext).pop();

                            _showSnack(
                              selectedAdmissionStatus == 'planned'
                                  ? 'Planned admission created successfully.'
                                  : selectedBedId == _noBedValue
                                      ? 'Patient admitted successfully without a bed assignment.'
                                      : 'Patient admitted and assigned to a bed successfully.',
                            );

                            await _loadWorkspace();
                          } catch (error) {
                            _showSnack(
                              'Could not create admission: $error',
                              error: true,
                            );

                            setDialogState(() {
                              saving = false;
                            });
                          }
                        },
                  icon: const Icon(
                    Icons.add_circle_rounded,
                  ),
                  label: Text(
                    selectedAdmissionStatus == 'planned'
                        ? 'Create Planned Admission'
                        : 'Admit Patient',
                  ),
                ),
              ],
            );
          },
        );
      },
    );

    reasonController.dispose();
    diagnosisController.dispose();
  }

  Future<void> _showAdmitPlannedDialog(
    HospitalAdmissionRecord admission,
  ) async {
    if (_actionBusy) {
      return;
    }

    setState(() {
      _actionBusy = true;
    });

    List<HospitalAdmissionBedOption> beds;

    try {
      beds = await _service.getAvailableBeds(
        admission.hospitalId,
      );
    } catch (error) {
      if (mounted) {
        setState(() {
          _actionBusy = false;
        });
      }

      _showSnack(
        'Could not load available beds: $error',
        error: true,
      );

      return;
    }

    if (!mounted) return;

    setState(() {
      _actionBusy = false;
    });

    String selectedBedId = _noBedValue;
    bool saving = false;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: context.cBgSecondary,
              title: const Text(
                'Admit Planned Patient',
              ),
              content: SizedBox(
                width: 580,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _DialogPatientSummary(
                        admission: admission,
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        initialValue: selectedBedId,
                        isExpanded: true,
                        decoration: _inputDecoration(
                          'Bed assignment',
                          prefixIcon: Icons.bed_rounded,
                        ),
                        items: [
                          const DropdownMenuItem<String>(
                            value: _noBedValue,
                            child: Text(
                              'Admit without assigning a bed',
                            ),
                          ),
                          ...beds.map((bed) {
                            return DropdownMenuItem<String>(
                              value: bed.bedId,
                              child: Text(
                                bed.displayLocation,
                                overflow: TextOverflow.ellipsis,
                              ),
                            );
                          }),
                        ],
                        onChanged: saving
                            ? null
                            : (value) {
                                if (value != null) {
                                  setDialogState(() {
                                    selectedBedId = value;
                                  });
                                }
                              },
                      ),
                      if (beds.isEmpty) ...[
                        const SizedBox(height: 12),
                        _DialogNotice(
                          icon: Icons.warning_amber_rounded,
                          message: 'No beds are currently available. '
                              'The patient can still be admitted without a bed.',
                          color: CorviaColors.warning,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: saving
                      ? null
                      : () {
                          Navigator.of(dialogContext).pop();
                        },
                  child: const Text('Cancel'),
                ),
                FilledButton.icon(
                  onPressed: saving
                      ? null
                      : () async {
                          setDialogState(() {
                            saving = true;
                          });

                          try {
                            await _service.admitPlannedAdmission(
                              admission.admissionId,
                            );

                            if (selectedBedId != _noBedValue) {
                              await _service.assignBed(
                                admissionId: admission.admissionId,
                                bedId: selectedBedId,
                              );
                            }

                            if (!dialogContext.mounted) {
                              return;
                            }

                            Navigator.of(dialogContext).pop();

                            _showSnack(
                              selectedBedId == _noBedValue
                                  ? 'Patient admitted successfully without a bed assignment.'
                                  : 'Patient admitted and assigned to a bed successfully.',
                            );

                            await _loadWorkspace();
                          } catch (error) {
                            _showSnack(
                              'Could not admit patient: $error',
                              error: true,
                            );

                            setDialogState(() {
                              saving = false;
                            });
                          }
                        },
                  icon: const Icon(
                    Icons.login_rounded,
                  ),
                  label: const Text('Admit Patient'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _showAssignBedDialog(
    HospitalAdmissionRecord admission,
  ) async {
    if (_actionBusy) {
      return;
    }

    setState(() {
      _actionBusy = true;
    });

    try {
      final beds = await _service.getAvailableBeds(
        admission.hospitalId,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _actionBusy = false;
      });

      if (beds.isEmpty) {
        _showSnack(
          'No available beds were found for this hospital.',
          error: true,
        );
        return;
      }

      String selectedBedId = beds.first.bedId;
      DateTime? expectedDischarge = admission.expectedDischargeAt?.toLocal();
      bool saving = false;

      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          return StatefulBuilder(
            builder: (context, setDialogState) {
              return AlertDialog(
                backgroundColor: context.cBgSecondary,
                title: const Text(
                  'Assign Patient to Bed',
                ),
                content: SizedBox(
                  width: 620,
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _DialogPatientSummary(
                          admission: admission,
                        ),
                        const SizedBox(height: 16),
                        DropdownButtonFormField<String>(
                          initialValue: selectedBedId,
                          isExpanded: true,
                          decoration: _inputDecoration(
                            'Available bed',
                            prefixIcon: Icons.bed_rounded,
                          ),
                          items: beds.map((bed) {
                            return DropdownMenuItem<String>(
                              value: bed.bedId,
                              child: Text(
                                '${bed.displayLocation} • '
                                '${_humanize(bed.bedType)}',
                                overflow: TextOverflow.ellipsis,
                              ),
                            );
                          }).toList(),
                          onChanged: saving
                              ? null
                              : (value) {
                                  if (value != null) {
                                    setDialogState(() {
                                      selectedBedId = value;
                                    });
                                  }
                                },
                        ),
                        const SizedBox(height: 12),
                        InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: saving
                              ? null
                              : () async {
                                  final today = DateTime.now();
                                  final picked = await showDatePicker(
                                    context: context,
                                    initialDate: expectedDischarge ??
                                        today.add(const Duration(days: 3)),
                                    firstDate: DateTime(
                                        today.year, today.month, today.day),
                                    lastDate:
                                        today.add(const Duration(days: 365)),
                                    helpText: 'Expected discharge date',
                                  );
                                  if (picked != null) {
                                    setDialogState(() {
                                      expectedDischarge = DateTime(picked.year,
                                          picked.month, picked.day, 10);
                                    });
                                  }
                                },
                          child: InputDecorator(
                            decoration: _inputDecoration(
                              'Expected discharge',
                              prefixIcon: Icons.event_available_rounded,
                            ),
                            child: Text(
                              expectedDischarge == null
                                  ? 'Tap to set a date (optional)'
                                  : DateFormat('EEE d MMM yyyy')
                                      .format(expectedDischarge!),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: saving
                        ? null
                        : () {
                            Navigator.of(dialogContext).pop();
                          },
                    child: const Text('Cancel'),
                  ),
                  FilledButton.icon(
                    onPressed: saving
                        ? null
                        : () async {
                            setDialogState(() {
                              saving = true;
                            });

                            try {
                              await _service.assignBed(
                                admissionId: admission.admissionId,
                                bedId: selectedBedId,
                              );

                              String? dischargeError;
                              final discharge = expectedDischarge;
                              if (discharge != null) {
                                try {
                                  await _service.setExpectedDischarge(
                                    admissionId: admission.admissionId,
                                    expectedDischargeAt: discharge,
                                  );
                                } catch (error) {
                                  dischargeError = '$error';
                                }
                              }

                              if (!dialogContext.mounted) {
                                return;
                              }

                              Navigator.of(dialogContext).pop();

                              _showSnack(
                                dischargeError == null
                                    ? 'Patient assigned to bed successfully.'
                                    : 'Bed assigned, but the expected discharge '
                                        'date was not saved: $dischargeError',
                                error: dischargeError != null,
                              );

                              await _loadWorkspace();
                            } catch (error) {
                              _showSnack(
                                'Could not assign bed: $error',
                                error: true,
                              );

                              setDialogState(() {
                                saving = false;
                              });
                            }
                          },
                    icon: const Icon(
                      Icons.bed_rounded,
                    ),
                    label: const Text('Assign Bed'),
                  ),
                ],
              );
            },
          );
        },
      );
    } catch (error) {
      if (mounted) {
        setState(() {
          _actionBusy = false;
        });
      }

      _showSnack(
        'Could not load available beds: $error',
        error: true,
      );
    }
  }

  Future<void> _showTransferBedDialog(
    HospitalAdmissionRecord admission,
  ) async {
    if (_actionBusy) {
      return;
    }

    setState(() {
      _actionBusy = true;
    });

    try {
      final allBeds = await _service.getAvailableBeds(
        admission.hospitalId,
        includeCurrentBedId: admission.bedId,
      );

      final availableBeds = allBeds.where((bed) {
        return bed.bedId != admission.bedId;
      }).toList();

      if (!mounted) {
        return;
      }

      setState(() {
        _actionBusy = false;
      });

      if (availableBeds.isEmpty) {
        _showSnack(
          'No alternative beds are currently available.',
          error: true,
        );
        return;
      }

      final reasonController = TextEditingController();

      String selectedBedId = availableBeds.first.bedId;
      bool saving = false;

      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          return StatefulBuilder(
            builder: (context, setDialogState) {
              return AlertDialog(
                backgroundColor: context.cBgSecondary,
                title: const Text(
                  'Transfer Patient to Another Bed',
                ),
                content: SizedBox(
                  width: 650,
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _DialogPatientSummary(
                          admission: admission,
                        ),
                        const SizedBox(height: 12),
                        _DialogNotice(
                          icon: Icons.location_on_rounded,
                          message:
                              'Current location: ${admission.displayLocation}',
                          color: context.cAccentReadable,
                        ),
                        const SizedBox(height: 16),
                        DropdownButtonFormField<String>(
                          initialValue: selectedBedId,
                          isExpanded: true,
                          decoration: _inputDecoration(
                            'New bed',
                            prefixIcon: Icons.swap_horiz_rounded,
                          ),
                          items: availableBeds.map((bed) {
                            return DropdownMenuItem<String>(
                              value: bed.bedId,
                              child: Text(
                                '${bed.displayLocation} • '
                                '${_humanize(bed.bedType)}',
                                overflow: TextOverflow.ellipsis,
                              ),
                            );
                          }).toList(),
                          onChanged: saving
                              ? null
                              : (value) {
                                  if (value != null) {
                                    setDialogState(() {
                                      selectedBedId = value;
                                    });
                                  }
                                },
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: reasonController,
                          maxLines: 3,
                          decoration: _inputDecoration(
                            'Transfer reason',
                            hint: 'Clinical, operational or isolation reason',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: saving
                        ? null
                        : () {
                            Navigator.of(dialogContext).pop();
                          },
                    child: const Text('Cancel'),
                  ),
                  FilledButton.icon(
                    onPressed: saving
                        ? null
                        : () async {
                            if (reasonController.text.trim().isEmpty) {
                              _showSnack(
                                'A transfer reason is required.',
                                error: true,
                              );
                              return;
                            }

                            setDialogState(() {
                              saving = true;
                            });

                            try {
                              await _service.transferBed(
                                admissionId: admission.admissionId,
                                newBedId: selectedBedId,
                                transferReason: reasonController.text,
                              );

                              if (!dialogContext.mounted) {
                                return;
                              }

                              Navigator.of(dialogContext).pop();

                              _showSnack(
                                'Patient transferred to the new bed successfully.',
                              );

                              await _loadWorkspace();
                            } catch (error) {
                              _showSnack(
                                'Could not transfer patient: $error',
                                error: true,
                              );

                              setDialogState(() {
                                saving = false;
                              });
                            }
                          },
                    icon: const Icon(
                      Icons.swap_horiz_rounded,
                    ),
                    label: const Text('Transfer Patient'),
                  ),
                ],
              );
            },
          );
        },
      );

      reasonController.dispose();
    } catch (error) {
      if (mounted) {
        setState(() {
          _actionBusy = false;
        });
      }

      _showSnack(
        'Could not load alternative beds: $error',
        error: true,
      );
    }
  }

  Future<void> _showDischargeDialog(
    HospitalAdmissionRecord admission,
  ) async {
    final reasonController = TextEditingController();

    bool saving = false;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: context.cBgSecondary,
              title: const Text('Discharge Patient'),
              content: SizedBox(
                width: 600,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _DialogPatientSummary(
                        admission: admission,
                      ),
                      const SizedBox(height: 14),
                      if (admission.hasBedAssignment)
                        _DialogNotice(
                          icon: Icons.cleaning_services_rounded,
                          message:
                              'The current bed will automatically change to Cleaning after discharge.',
                          color: CorviaColors.warning,
                        ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: reasonController,
                        maxLines: 4,
                        decoration: _inputDecoration(
                          'Discharge reason',
                          hint: 'Clinical discharge reason or outcome',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: saving
                      ? null
                      : () {
                          Navigator.of(dialogContext).pop();
                        },
                  child: const Text('Cancel'),
                ),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: CorviaColors.success,
                  ),
                  onPressed: saving
                      ? null
                      : () async {
                          if (reasonController.text.trim().isEmpty) {
                            _showSnack(
                              'A discharge reason is required.',
                              error: true,
                            );
                            return;
                          }

                          setDialogState(() {
                            saving = true;
                          });

                          try {
                            await _service.dischargeAdmission(
                              admissionId: admission.admissionId,
                              dischargeReason: reasonController.text,
                            );

                            if (!dialogContext.mounted) {
                              return;
                            }

                            Navigator.of(dialogContext).pop();

                            _showSnack(
                              'Patient discharged successfully.',
                            );

                            await _loadWorkspace();
                          } catch (error) {
                            _showSnack(
                              'Could not discharge patient: $error',
                              error: true,
                            );

                            setDialogState(() {
                              saving = false;
                            });
                          }
                        },
                  icon: const Icon(
                    Icons.exit_to_app_rounded,
                  ),
                  label: const Text('Discharge Patient'),
                ),
              ],
            );
          },
        );
      },
    );

    reasonController.dispose();
  }

  Future<void> _showCancelAdmissionDialog(
    HospitalAdmissionRecord admission,
  ) async {
    final reasonController = TextEditingController();

    bool saving = false;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: context.cBgSecondary,
              title: const Text(
                'Cancel Planned Admission',
              ),
              content: SizedBox(
                width: 580,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _DialogPatientSummary(
                        admission: admission,
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: reasonController,
                        maxLines: 4,
                        decoration: _inputDecoration(
                          'Cancellation reason',
                          hint: 'Reason the planned admission was cancelled',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: saving
                      ? null
                      : () {
                          Navigator.of(dialogContext).pop();
                        },
                  child: const Text('Keep Admission'),
                ),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: CorviaColors.danger,
                  ),
                  onPressed: saving
                      ? null
                      : () async {
                          if (reasonController.text.trim().isEmpty) {
                            _showSnack(
                              'A cancellation reason is required.',
                              error: true,
                            );
                            return;
                          }

                          setDialogState(() {
                            saving = true;
                          });

                          try {
                            await _service.cancelAdmission(
                              admissionId: admission.admissionId,
                              cancellationReason: reasonController.text,
                            );

                            if (!dialogContext.mounted) {
                              return;
                            }

                            Navigator.of(dialogContext).pop();

                            _showSnack(
                              'Planned admission cancelled successfully.',
                            );

                            await _loadWorkspace();
                          } catch (error) {
                            _showSnack(
                              'Could not cancel admission: $error',
                              error: true,
                            );

                            setDialogState(() {
                              saving = false;
                            });
                          }
                        },
                  icon: const Icon(
                    Icons.cancel_rounded,
                  ),
                  label: const Text('Cancel Admission'),
                ),
              ],
            );
          },
        );
      },
    );

    reasonController.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _workspace == null && _hospitals.isEmpty) {
      return Center(
        child: CircularProgressIndicator(
          color: context.cAccentReadable,
        ),
      );
    }

    if (_error != null && _workspace == null && _hospitals.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: _AdmissionsErrorState(
            message: _error!,
            onRetry: _loadInitialData,
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: context.cBgPrimary,
      body: Column(
        children: [
          _buildHeader(),
          _buildSummary(),
          _buildFilters(),
          if (_error != null) _buildErrorBanner(),
          Expanded(
            child: Stack(
              children: [
                _buildAdmissionsContent(),
                if (_loading)
                  Positioned.fill(
                    child: ColoredBox(
                      color: context.cBgPrimary.withValues(
                        alpha: 0.65,
                      ),
                      child: Center(
                        child: CircularProgressIndicator(
                          color: context.cAccentReadable,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(
        20,
        20,
        20,
        14,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 780;

          final heading = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Admissions & Bed Management',
                style: TextStyle(
                  color: context.cTextPrimary,
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                'Plan admissions, admit patients, assign beds, '
                'transfer patients and complete discharges.',
                style: TextStyle(
                  color: context.cTextSecondary,
                  fontSize: 13,
                ),
              ),
            ],
          );

          final controls = Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: compact ? constraints.maxWidth : 290,
                child: DropdownButtonFormField<String>(
                  initialValue: _selectedHospitalId,
                  isExpanded: true,
                  decoration: _inputDecoration(
                    'Current hospital',
                    prefixIcon: Icons.local_hospital_rounded,
                  ),
                  items: _hospitals.map((hospital) {
                    return DropdownMenuItem<String>(
                      value: hospital['id'].toString(),
                      child: Text(
                        hospital['name']?.toString() ?? 'Hospital',
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                  }).toList(),
                  onChanged: _loading || _actionBusy
                      ? null
                      : (value) async {
                          if (value == null || value == _selectedHospitalId) {
                            return;
                          }

                          setState(() {
                            _selectedHospitalId = value;
                            _workspace = null;
                          });

                          await _loadWorkspace();
                        },
                ),
              ),
              FilledButton.icon(
                onPressed:
                    _loading || _actionBusy ? null : _showCreateAdmissionDialog,
                icon: const Icon(
                  Icons.add_circle_rounded,
                ),
                label: const Text('New Admission'),
              ),
              OutlinedButton.icon(
                onPressed: _loading || _actionBusy
                    ? null
                    : () {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const HospitalStructurePage(
                              initialTab: 4,
                            ),
                          ),
                        );
                      },
                icon: const Icon(Icons.add_box_rounded),
                label: const Text('Add Bed'),
              ),
              IconButton.filledTonal(
                tooltip: 'Refresh admissions',
                onPressed: _loading || _actionBusy ? null : _loadWorkspace,
                icon: const Icon(
                  Icons.refresh_rounded,
                ),
              ),
            ],
          );

          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                heading,
                const SizedBox(height: 16),
                controls,
              ],
            );
          }

          return Row(
            children: [
              Expanded(child: heading),
              const SizedBox(width: 18),
              controls,
            ],
          );
        },
      ),
    );
  }

  Widget _buildSummary() {
    final workspace = _workspace;

    final summary = [
      _AdmissionSummaryData(
        label: 'Active Admissions',
        value: workspace?.activeAdmissions ?? 0,
        icon: Icons.hotel_rounded,
        color: CorviaColors.success,
      ),
      _AdmissionSummaryData(
        label: 'Planned',
        value: workspace?.plannedAdmissions ?? 0,
        icon: Icons.event_available_rounded,
        color: CorviaColors.warning,
      ),
      _AdmissionSummaryData(
        label: 'Awaiting Bed',
        value: workspace?.admittedWithoutBed ?? 0,
        icon: Icons.bed_outlined,
        color: CorviaColors.danger,
      ),
      _AdmissionSummaryData(
        label: 'Available Beds',
        value: workspace?.availableBeds.length ?? 0,
        icon: Icons.bed_rounded,
        color: context.cAccentReadable,
      ),
      _AdmissionSummaryData(
        label: 'Discharged',
        value: workspace?.dischargedAdmissions ?? 0,
        icon: Icons.exit_to_app_rounded,
        color: context.cAccentReadable,
      ),
      _AdmissionSummaryData(
        label: 'Hospital Patients',
        value: workspace?.patients.length ?? 0,
        icon: Icons.people_alt_rounded,
        color: context.cAccentReadable,
      ),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        20,
        0,
        20,
        14,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          Widget card(_AdmissionSummaryData item, double width) {
            return SizedBox(
              width: width,
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: context.cBgSecondary,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: context.cDivider),
                ),
                child: Row(
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
                    const SizedBox(width: 11),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.value.toString(),
                            style: TextStyle(
                              color: context.cTextPrimary,
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          Text(
                            item.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: context.cTextSecondary,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          if (constraints.maxWidth < 700) {
            return SizedBox(
              height: 82,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: summary.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (_, index) => card(summary[index], 190),
              ),
            );
          }

          final columns = constraints.maxWidth >= 1100 ? 6 : 3;

          const spacing = 10.0;

          final width =
              (constraints.maxWidth - ((columns - 1) * spacing)) / columns;

          return Wrap(
            spacing: spacing,
            runSpacing: spacing,
            children: summary.map((item) => card(item, width)).toList(),
          );
        },
      ),
    );
  }

  Widget _buildFilters() {
    return Container(
      margin: const EdgeInsets.fromLTRB(
        20,
        0,
        20,
        12,
      ),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.cBgSecondary,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: context.cDivider,
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 650;

          final searchField = TextField(
            controller: _searchController,
            decoration: _inputDecoration(
              'Search admissions',
              hint: 'Patient, admission number, ward, room or bed',
              prefixIcon: Icons.search_rounded,
            ).copyWith(
              suffixIcon: _searchController.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear search',
                      onPressed: () {
                        _searchController.clear();
                      },
                      icon: const Icon(
                        Icons.close_rounded,
                      ),
                    ),
            ),
          );

          final statusDropdown = DropdownButtonFormField<String>(
            initialValue: _selectedStatusFilter,
            decoration: _inputDecoration(
              'Admission status',
              prefixIcon: Icons.filter_alt_rounded,
            ),
            items: _statusFilters.map((status) {
              return DropdownMenuItem<String>(
                value: status,
                child: Text(
                  status == 'active' ? 'Active and Planned' : _humanize(status),
                ),
              );
            }).toList(),
            onChanged: (value) {
              if (value != null) {
                setState(() {
                  _selectedStatusFilter = value;
                });
              }
            },
          );

          if (compact) {
            return Column(
              children: [
                searchField,
                const SizedBox(height: 10),
                statusDropdown,
              ],
            );
          }

          return Row(
            children: [
              Expanded(
                flex: 2,
                child: searchField,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: statusDropdown,
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildErrorBanner() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(
        20,
        0,
        20,
        12,
      ),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: CorviaColors.danger.withValues(
          alpha: 0.08,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: CorviaColors.danger.withValues(
            alpha: 0.25,
          ),
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.error_outline_rounded,
            color: CorviaColors.danger,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _error!,
              style: TextStyle(
                color: context.cTextPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          TextButton(
            onPressed: _loadWorkspace,
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _buildAdmissionsContent() {
    final workspace = _workspace;

    if (workspace == null) {
      return Center(
        child: CircularProgressIndicator(
          color: context.cAccentReadable,
        ),
      );
    }

    final admissions = _filteredAdmissions;

    if (admissions.isEmpty) {
      return RefreshIndicator(
        onRefresh: _loadWorkspace,
        color: context.cAccentReadable,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            20,
            10,
            20,
            40,
          ),
          children: [
            _AdmissionsEmptyState(
              title: _searchController.text.trim().isNotEmpty
                  ? 'No matching admissions'
                  : 'No admissions found',
              message: _searchController.text.trim().isNotEmpty
                  ? 'No admissions match the current search and status filter.'
                  : 'Create a planned admission or admit a patient to begin.',
              onCreate: _showCreateAdmissionDialog,
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadWorkspace,
      color: context.cAccentReadable,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(
          20,
          6,
          20,
          40,
        ),
        itemCount: admissions.length + 1,
        itemBuilder: (context, index) {
          if (index == 0) {
            return Padding(
              padding: const EdgeInsets.only(
                bottom: 10,
              ),
              child: Text(
                '$_hospitalName • '
                '${admissions.length} admission'
                '${admissions.length == 1 ? '' : 's'} shown',
                style: TextStyle(
                  color: context.cTextSecondary,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            );
          }

          final admission = admissions[index - 1];

          return _AdmissionCard(
            admission: admission,
            statusColor: _statusColor(
              context,
              admission.status,
            ),
            humanize: _humanize,
            formatDateTime: _formatDateTime,
            busy: _actionBusy,
            onAdmit: admission.isPlanned
                ? () => _showAdmitPlannedDialog(
                      admission,
                    )
                : null,
            onAssignBed: admission.isAdmitted && !admission.hasBedAssignment
                ? () => _showAssignBedDialog(
                      admission,
                    )
                : null,
            onTransferBed: admission.isAdmitted && admission.hasBedAssignment
                ? () => _showTransferBedDialog(
                      admission,
                    )
                : null,
            onDischarge: admission.isAdmitted
                ? () => _showDischargeDialog(
                      admission,
                    )
                : null,
            onCancel: admission.isPlanned
                ? () => _showCancelAdmissionDialog(
                      admission,
                    )
                : null,
          );
        },
      ),
    );
  }
}

class _AdmissionSummaryData {
  const _AdmissionSummaryData({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final int value;
  final IconData icon;
  final Color color;
}

class _AdmissionCard extends StatelessWidget {
  const _AdmissionCard({
    required this.admission,
    required this.statusColor,
    required this.humanize,
    required this.formatDateTime,
    required this.busy,
    required this.onAdmit,
    required this.onAssignBed,
    required this.onTransferBed,
    required this.onDischarge,
    required this.onCancel,
  });

  final HospitalAdmissionRecord admission;
  final Color statusColor;

  final String Function(dynamic value) humanize;
  final String Function(DateTime? value) formatDateTime;

  final bool busy;

  final VoidCallback? onAdmit;
  final VoidCallback? onAssignBed;
  final VoidCallback? onTransferBed;
  final VoidCallback? onDischarge;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.cBgSecondary,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: statusColor.withValues(alpha: 0.22),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 600;

              final patientHeader = Row(
                children: [
                  Container(
                    height: 50,
                    width: 50,
                    decoration: BoxDecoration(
                      color: statusColor.withValues(
                        alpha: 0.10,
                      ),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(
                      admission.isAdmitted
                          ? Icons.hotel_rounded
                          : admission.isPlanned
                              ? Icons.event_note_rounded
                              : Icons.medical_information_rounded,
                      color: statusColor,
                    ),
                  ),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          admission.patientName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: context.cTextPrimary,
                            fontSize: 17,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${admission.displayAdmissionNumber} • '
                          '${admission.patientNumber ?? 'No patient number'}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
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

              final statusPill = Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 11,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: statusColor.withValues(
                    alpha: 0.10,
                  ),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: statusColor.withValues(
                      alpha: 0.25,
                    ),
                  ),
                ),
                child: Text(
                  humanize(admission.status),
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              );

              if (compact) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    patientHeader,
                    const SizedBox(height: 11),
                    statusPill,
                  ],
                );
              }

              return Row(
                children: [
                  Expanded(child: patientHeader),
                  const SizedBox(width: 12),
                  statusPill,
                ],
              );
            },
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 900
                  ? 4
                  : constraints.maxWidth >= 560
                      ? 2
                      : 1;

              const spacing = 10.0;

              final itemWidth =
                  (constraints.maxWidth - ((columns - 1) * spacing)) / columns;

              final details = [
                _AdmissionDetail(
                  label: 'Admission Type',
                  value: humanize(admission.admissionType),
                  icon: Icons.category_rounded,
                ),
                _AdmissionDetail(
                  label: 'Source',
                  value: humanize(admission.sourceType),
                  icon: Icons.input_rounded,
                ),
                _AdmissionDetail(
                  label: 'Admitted',
                  value: formatDateTime(admission.admittedAt),
                  icon: Icons.login_rounded,
                ),
                _AdmissionDetail(
                  label: 'Expected Discharge',
                  value: formatDateTime(
                    admission.expectedDischargeAt,
                  ),
                  icon: Icons.event_available_rounded,
                ),
              ];

              return Wrap(
                spacing: spacing,
                runSpacing: spacing,
                children: details.map((detail) {
                  return SizedBox(
                    width: itemWidth,
                    child: detail,
                  );
                }).toList(),
              );
            },
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              color: context.cBgPrimary,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: context.cDivider,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  admission.hasBedAssignment
                      ? Icons.location_on_rounded
                      : Icons.bed_outlined,
                  color: admission.hasBedAssignment
                      ? context.cAccentReadable
                      : CorviaColors.warning,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        admission.hasBedAssignment
                            ? 'Current Location'
                            : 'Bed Assignment',
                        style: TextStyle(
                          color: context.cTextPrimary,
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        admission.hasBedAssignment
                            ? admission.displayLocation
                            : admission.isAdmitted
                                ? 'Patient is admitted but does not have a bed yet.'
                                : 'A bed can be assigned after the patient is admitted.',
                        style: TextStyle(
                          color: context.cTextSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (admission.admissionReason != null ||
              admission.admittingDiagnosis != null) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(
                color: context.cBgPrimary,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: context.cDivider,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (admission.admissionReason != null)
                    _AdmissionTextLine(
                      label: 'Reason',
                      value: admission.admissionReason!,
                    ),
                  if (admission.admittingDiagnosis != null)
                    _AdmissionTextLine(
                      label: 'Diagnosis / Note',
                      value: admission.admittingDiagnosis!,
                    ),
                  _AdmissionTextLine(
                    label: 'Visitor Status',
                    value: humanize(
                      admission.visitorStatus,
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (admission.dischargeReason != null) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(
                color: context.cBgPrimary,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: context.cDivider,
                ),
              ),
              child: _AdmissionTextLine(
                label: admission.status == 'cancelled'
                    ? 'Cancellation Reason'
                    : 'Discharge Reason',
                value: admission.dischargeReason!,
              ),
            ),
          ],
          if (onAdmit != null ||
              onAssignBed != null ||
              onTransferBed != null ||
              onDischarge != null ||
              onCancel != null) ...[
            const SizedBox(height: 14),
            Divider(color: context.cDivider),
            const SizedBox(height: 10),
            Wrap(
              spacing: 9,
              runSpacing: 9,
              children: [
                if (onAdmit != null)
                  FilledButton.icon(
                    onPressed: busy ? null : onAdmit,
                    icon: const Icon(
                      Icons.login_rounded,
                    ),
                    label: const Text('Admit Patient'),
                  ),
                if (onAssignBed != null)
                  FilledButton.tonalIcon(
                    onPressed: busy ? null : onAssignBed,
                    icon: const Icon(
                      Icons.bed_rounded,
                    ),
                    label: const Text('Assign Bed'),
                  ),
                if (onTransferBed != null)
                  OutlinedButton.icon(
                    onPressed: busy ? null : onTransferBed,
                    icon: const Icon(
                      Icons.swap_horiz_rounded,
                    ),
                    label: const Text('Transfer Bed'),
                  ),
                if (onDischarge != null)
                  OutlinedButton.icon(
                    onPressed: busy ? null : onDischarge,
                    icon: const Icon(
                      Icons.exit_to_app_rounded,
                    ),
                    label: const Text('Discharge'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: CorviaColors.success,
                    ),
                  ),
                if (onCancel != null)
                  OutlinedButton.icon(
                    onPressed: busy ? null : onCancel,
                    icon: const Icon(
                      Icons.cancel_rounded,
                    ),
                    label: const Text('Cancel Admission'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: CorviaColors.danger,
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _AdmissionDetail extends StatelessWidget {
  const _AdmissionDetail({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: context.cBgPrimary,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: context.cDivider,
        ),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            size: 20,
            color: context.cAccentReadable,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: context.cTextSecondary,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: context.cTextPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
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

class _AdmissionTextLine extends StatelessWidget {
  const _AdmissionTextLine({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '$label: ',
              style: TextStyle(
                color: context.cTextPrimary,
                fontWeight: FontWeight.w900,
                fontSize: 12,
              ),
            ),
            TextSpan(
              text: value,
              style: TextStyle(
                color: context.cTextSecondary,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DialogPatientSummary extends StatelessWidget {
  const _DialogPatientSummary({
    required this.admission,
  });

  final HospitalAdmissionRecord admission;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.cBgPrimary,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: context.cDivider,
        ),
      ),
      child: Row(
        children: [
          Container(
            height: 44,
            width: 44,
            decoration: BoxDecoration(
              color: context.cAccentReadable.withValues(
                alpha: 0.10,
              ),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              Icons.person_rounded,
              color: context.cAccentReadable,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  admission.patientName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: context.cTextPrimary,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${admission.displayAdmissionNumber} • '
                  '${admission.patientNumber ?? 'No patient number'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: context.cTextSecondary,
                    fontSize: 12,
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

class _DialogNotice extends StatelessWidget {
  const _DialogNotice({
    required this.icon,
    required this.message,
    required this.color,
  });

  final IconData icon;
  final String message;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: color.withValues(alpha: 0.22),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            color: color,
            size: 20,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: context.cTextPrimary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AdmissionsEmptyState extends StatelessWidget {
  const _AdmissionsEmptyState({
    required this.title,
    required this.message,
    required this.onCreate,
  });

  final String title;
  final String message;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 24,
        vertical: 48,
      ),
      decoration: BoxDecoration(
        color: context.cBgSecondary,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: context.cDivider,
        ),
      ),
      child: Column(
        children: [
          Icon(
            Icons.hotel_outlined,
            size: 50,
            color: context.cAccentReadable,
          ),
          const SizedBox(height: 14),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: context.cTextPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: context.cTextSecondary,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: onCreate,
            icon: const Icon(
              Icons.add_circle_rounded,
            ),
            label: const Text('New Admission'),
          ),
        ],
      ),
    );
  }
}

class _AdmissionsErrorState extends StatelessWidget {
  const _AdmissionsErrorState({
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(
        maxWidth: 540,
      ),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: context.cBgSecondary,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: CorviaColors.danger.withValues(
            alpha: 0.30,
          ),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.error_outline_rounded,
            color: CorviaColors.danger,
            size: 44,
          ),
          const SizedBox(height: 12),
          Text(
            'Admissions could not load',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: context.cTextPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: context.cTextSecondary,
            ),
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(
              Icons.refresh_rounded,
            ),
            label: const Text('Try Again'),
          ),
        ],
      ),
    );
  }
}
