import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/hospital_visitor_service.dart';
import '../../theme/app_theme.dart';
import 'hospital_visitor_scanner_page.dart';

class HospitalVisitorsPage extends StatefulWidget {
  const HospitalVisitorsPage({
    super.key,
    this.initialHospitalId,
  });

  final String? initialHospitalId;

  @override
  State<HospitalVisitorsPage> createState() => _HospitalVisitorsPageState();
}

class _HospitalVisitorsPageState extends State<HospitalVisitorsPage>
    with SingleTickerProviderStateMixin {
  final HospitalVisitorService _service = HospitalVisitorService();

  late final TabController _tabController;

  bool _refreshing = false;

  final TextEditingController _visitorSearchController =
      TextEditingController();

  final TextEditingController _passSearchController = TextEditingController();

  final TextEditingController _checkinSearchController =
      TextEditingController();

  final TextEditingController _restrictionSearchController =
      TextEditingController();

  bool _loading = true;
  bool _actionBusy = false;

  String? _error;
  String? _selectedHospitalId;

  String _passStatusFilter = 'all';
  bool _showOpenCheckinsOnly = true;
  bool _showActiveRestrictionsOnly = true;

  List<Map<String, dynamic>> _hospitals = [];

  HospitalVisitorWorkspace? _workspace;

  static const List<String> _identityTypes = [
    'south_african_id',
    'passport',
    'drivers_licence',
    'birth_certificate',
    'temporary_document',
    'other',
  ];

  static const List<String> _passTypes = [
    'single_visit',
    'temporary',
    'daily',
    'recurring',
    'family',
    'primary_contact',
    'end_of_life',
    'staff_authorised',
  ];

  static const List<String> _restrictionTypes = [
    'no_visitors',
    'approved_only',
    'family_only',
    'primary_contact_only',
    'security_restricted',
    'infection_control',
    'court_order',
    'patient_request',
    'staff_discretion',
  ];

  @override
  void initState() {
    super.initState();

    _tabController = TabController(
      length: 5,
      vsync: this,
    );

    _loadInitialData();
  }

  @override
  void dispose() {
    _tabController.dispose();

    _visitorSearchController.dispose();
    _passSearchController.dispose();
    _checkinSearchController.dispose();
    _restrictionSearchController.dispose();

    super.dispose();
  }

  String? _hospitalIdFromMap(
    Map<String, dynamic> hospital,
  ) {
    return hospital['hospital_id']?.toString() ?? hospital['id']?.toString();
  }

  String _hospitalNameFromMap(
    Map<String, dynamic> hospital,
  ) {
    final nested = hospital['hospitals'];

    if (nested is Map && nested['name'] != null) {
      return nested['name'].toString();
    }

    return hospital['hospital_name']?.toString() ??
        hospital['name']?.toString() ??
        'Hospital';
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
          'No hospitals are linked to this admin account.',
        );
      }

      String? selectedId = widget.initialHospitalId;

      final availableIds =
          hospitals.map(_hospitalIdFromMap).whereType<String>().toSet();

      if (selectedId == null || !availableIds.contains(selectedId)) {
        selectedId = _hospitalIdFromMap(hospitals.first);
      }

      if (selectedId == null) {
        throw Exception(
          'A valid hospital could not be selected.',
        );
      }

      final workspace = await _service.loadWorkspace(
        selectedId,
      );

      if (!mounted) return;

      setState(() {
        _hospitals = hospitals;
        _selectedHospitalId = selectedId;
        _workspace = workspace;
        _loading = false;
        _refreshing = false;
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _error = error.toString();
        _loading = false;
        _refreshing = false;
      });
    }
  }

  Future<void> _loadWorkspace() async {
    final hospitalId = _selectedHospitalId;

    if (hospitalId == null || _refreshing) {
      return;
    }

    final hasExistingWorkspace = _workspace != null;

    if (mounted) {
      setState(() {
        _error = null;
        _refreshing = true;

        if (!hasExistingWorkspace) {
          _loading = true;
        }
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
        _refreshing = false;
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _error = error.toString();
        _loading = false;
        _refreshing = false;
      });
    }
  }

  Future<void> _refreshAfterDialog() async {
    if (!mounted) {
      return;
    }

    await Future<void>.delayed(
      const Duration(milliseconds: 250),
    );

    if (!mounted) {
      return;
    }

    await _loadWorkspace();
  }

  void _disposeControllersAfterDialog(
    Iterable<TextEditingController> controllers,
  ) {
    Future<void>.delayed(
      const Duration(milliseconds: 350),
      () {
        for (final controller in controllers) {
          controller.dispose();
        }
      },
    );
  }

  Future<void> _selectHospital(
    String hospitalId,
  ) async {
    if (hospitalId == _selectedHospitalId) {
      return;
    }

    setState(() {
      _selectedHospitalId = hospitalId;
      _workspace = null;
    });

    await _loadWorkspace();
  }

  void _showMessage(
    String message, {
    bool error = false,
  }) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor:
              error ? CorviaColors.danger : CorviaColors.accentDark,
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  String _formatDate(DateTime? value) {
    if (value == null) {
      return 'Not available';
    }

    return '${value.year}-'
        '${value.month.toString().padLeft(2, '0')}-'
        '${value.day.toString().padLeft(2, '0')} '
        '${value.hour.toString().padLeft(2, '0')}:'
        '${value.minute.toString().padLeft(2, '0')}';
  }

  String _humanize(String value) {
    final words = value.replaceAll('_', ' ').trim().split(RegExp(r'\s+'));

    return words.map((word) {
      if (word.isEmpty) return word;

      return '${word[0].toUpperCase()}'
          '${word.substring(1).toLowerCase()}';
    }).join(' ');
  }

  Color _statusColor(String status) {
    final lower = status.toLowerCase();

    if (lower == 'approved' ||
        lower == 'active' ||
        lower == 'successful' ||
        lower == 'allowed') {
      return CorviaColors.success;
    }

    if (lower == 'pending' || lower == 'draft') {
      return CorviaColors.warning;
    }

    if (lower == 'revoked' || lower == 'denied' || lower == 'blocked') {
      return CorviaColors.danger;
    }

    return context.cAccentReadable;
  }

  List<HospitalVisitorRecord> get _filteredVisitors {
    final workspace = _workspace;

    if (workspace == null) {
      return [];
    }

    final search = _visitorSearchController.text.trim().toLowerCase();

    if (search.isEmpty) {
      return workspace.visitors;
    }

    return workspace.visitors.where((visitor) {
      return visitor.searchText.contains(search);
    }).toList();
  }

  List<HospitalVisitorPassRecord> get _filteredPasses {
    final workspace = _workspace;

    if (workspace == null) {
      return [];
    }

    final search = _passSearchController.text.trim().toLowerCase();

    return workspace.passes.where((pass) {
      if (_passStatusFilter != 'all' && pass.status != _passStatusFilter) {
        return false;
      }

      if (search.isNotEmpty && !pass.searchText.contains(search)) {
        return false;
      }

      return true;
    }).toList();
  }

  List<HospitalVisitorCheckinRecord> get _filteredCheckins {
    final workspace = _workspace;

    if (workspace == null) {
      return [];
    }

    final search = _checkinSearchController.text.trim().toLowerCase();

    return workspace.checkins.where((checkin) {
      if (_showOpenCheckinsOnly && !checkin.isOpen) {
        return false;
      }

      if (search.isNotEmpty && !checkin.searchText.contains(search)) {
        return false;
      }

      return true;
    }).toList();
  }

  List<PatientVisitorRestrictionRecord> get _filteredRestrictions {
    final workspace = _workspace;

    if (workspace == null) {
      return [];
    }

    final search = _restrictionSearchController.text.trim().toLowerCase();

    return workspace.restrictions.where((restriction) {
      if (_showActiveRestrictionsOnly && !restriction.isCurrentlyActive) {
        return false;
      }

      if (search.isNotEmpty && !restriction.searchText.contains(search)) {
        return false;
      }

      return true;
    }).toList();
  }

  Future<void> _openScanner({
    String? qrToken,
  }) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => HospitalVisitorScannerPage(
          initialQrToken: qrToken,
        ),
      ),
    );

    await _refreshAfterDialog();
  }

  Future<void> _showVisitorDialog({
    HospitalVisitorRecord? visitor,
  }) async {
    final hospitalId = _selectedHospitalId;

    if (hospitalId == null) return;

    final formKey = GlobalKey<FormState>();

    final firstNameController = TextEditingController(
      text: visitor?.firstName,
    );

    final surnameController = TextEditingController(
      text: visitor?.surname,
    );

    final idNumberController = TextEditingController(
      text: visitor?.idNumber,
    );

    final phoneController = TextEditingController(
      text: visitor?.phone,
    );

    final emailController = TextEditingController(
      text: visitor?.email,
    );

    final vehicleController = TextEditingController(
      text: visitor?.vehicleRegistration,
    );

    final notesController = TextEditingController(
      text: visitor?.notes,
    );

    var idType = visitor?.idType ?? 'south_african_id';

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (
            context,
            setDialogState,
          ) {
            return AlertDialog(
              title: Text(
                visitor == null ? 'Add Visitor' : 'Edit Visitor',
              ),
              content: SizedBox(
                width: 520,
                child: Form(
                  key: formKey,
                  child: SingleChildScrollView(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TextFormField(
                            controller: firstNameController,
                            decoration: const InputDecoration(
                              labelText: 'First name',
                              border: OutlineInputBorder(),
                            ),
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return 'First name is required.';
                              }

                              return null;
                            },
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: surnameController,
                            decoration: const InputDecoration(
                              labelText: 'Surname',
                              border: OutlineInputBorder(),
                            ),
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return 'Surname is required.';
                              }

                              return null;
                            },
                          ),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<String>(
                            initialValue: idType,
                            decoration: const InputDecoration(
                              labelText: 'Identity type',
                              border: OutlineInputBorder(),
                            ),
                            items: _identityTypes
                                .map(
                                  (type) => DropdownMenuItem(
                                    value: type,
                                    child: Text(
                                      _humanize(
                                        type,
                                      ),
                                    ),
                                  ),
                                )
                                .toList(),
                            onChanged: (value) {
                              if (value == null) return;

                              setDialogState(() {
                                idType = value;
                              });
                            },
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: idNumberController,
                            decoration: const InputDecoration(
                              labelText: 'Identity number (optional)',
                              hintText: 'Can be verified at reception',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: phoneController,
                            keyboardType: TextInputType.phone,
                            decoration: const InputDecoration(
                              labelText: 'Phone',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: emailController,
                            keyboardType: TextInputType.emailAddress,
                            decoration: const InputDecoration(
                              labelText: 'Email',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: vehicleController,
                            textCapitalization: TextCapitalization.characters,
                            decoration: const InputDecoration(
                              labelText: 'Vehicle registration',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: notesController,
                            maxLines: 3,
                            decoration: const InputDecoration(
                              labelText: 'Notes',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.of(dialogContext).pop();
                  },
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () {
                    if (!(formKey.currentState?.validate() ?? false)) {
                      return;
                    }

                    Navigator.of(dialogContext).pop({
                      'first_name': firstNameController.text,
                      'surname': surnameController.text,
                      'id_type': idType,
                      'id_number': idNumberController.text,
                      'phone': phoneController.text,
                      'email': emailController.text,
                      'vehicle': vehicleController.text,
                      'notes': notesController.text,
                    });
                  },
                  child: const Text('Save Visitor'),
                ),
              ],
            );
          },
        );
      },
    );

    _disposeControllersAfterDialog([
      firstNameController,
      surnameController,
      idNumberController,
      phoneController,
      emailController,
      vehicleController,
      notesController,
    ]);

    if (result == null || !mounted) return;

    setState(() {
      _actionBusy = true;
    });

    try {
      await _service.upsertVisitor(
        hospitalId: hospitalId,
        firstName: result['first_name'].toString(),
        surname: result['surname'].toString(),
        idType: result['id_type'].toString(),
        idNumber: result['id_number']?.toString(),
        phone: result['phone']?.toString(),
        email: result['email']?.toString(),
        vehicleRegistration: result['vehicle']?.toString(),
        notes: result['notes']?.toString(),
      );

      _showMessage(
        visitor == null
            ? 'Visitor added successfully.'
            : 'Visitor updated successfully.',
      );

      await _loadWorkspace();
    } catch (error) {
      _showMessage(
        'Visitor could not be saved: $error',
        error: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          _actionBusy = false;
        });
      }
    }
  }

  Future<void> _setVisitorBlocked(
    HospitalVisitorRecord visitor,
  ) async {
    final shouldBlock = !visitor.isBlocked;

    String? reason;

    if (shouldBlock) {
      final controller = TextEditingController();

      reason = await showDialog<String>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: const Text('Block Visitor'),
            content: TextField(
              controller: controller,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Block reason',
                border: OutlineInputBorder(),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                },
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  final value = controller.text.trim();

                  if (value.isEmpty) return;

                  Navigator.of(dialogContext).pop(value);
                },
                child: const Text('Block Visitor'),
              ),
            ],
          );
        },
      );

      _disposeControllersAfterDialog([
        controller,
      ]);

      if (reason == null || !mounted) return;
    }

    if (!mounted) return;

    setState(() {
      _actionBusy = true;
    });

    try {
      await _service.setVisitorBlocked(
        visitorId: visitor.visitorId,
        blocked: shouldBlock,
        reason: reason,
      );

      _showMessage(
        shouldBlock
            ? 'Visitor blocked successfully.'
            : 'Visitor unblocked successfully.',
      );

      await _loadWorkspace();
    } catch (error) {
      _showMessage(
        'Visitor status could not be changed: $error',
        error: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          _actionBusy = false;
        });
      }
    }
  }

  Future<void> _showCreatePassDialog({
    HospitalVisitorRecord? selectedVisitor,
  }) async {
    final workspace = _workspace;
    final hospitalId = _selectedHospitalId;

    if (workspace == null || hospitalId == null) {
      return;
    }

    if (workspace.visitors.isEmpty) {
      _showMessage(
        'Add a visitor before creating a pass.',
        error: true,
      );
      return;
    }

    if (workspace.admissions.isEmpty) {
      _showMessage(
        'No planned or admitted patients are available.',
        error: true,
      );
      return;
    }

    final availableVisitors =
        workspace.visitors.where((visitor) => !visitor.isBlocked).toList();

    if (availableVisitors.isEmpty) {
      _showMessage(
        'All registered visitors are currently blocked.',
        error: true,
      );
      return;
    }

    String visitorId = selectedVisitor != null && !selectedVisitor.isBlocked
        ? selectedVisitor.visitorId
        : availableVisitors.first.visitorId;

    String admissionId = workspace.admissions.first.admissionId;

    String relationship = 'family';
    String passType = 'single_visit';

    int durationHours = 8;

    bool approveNow = true;
    bool requiresId = true;
    bool restrictionOverride = false;

    final purposeController = TextEditingController();

    final maxEntriesController = TextEditingController(text: '1');

    final overrideController = TextEditingController();

    final notesController = TextEditingController();

    final formKey = GlobalKey<FormState>();

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (
            context,
            setDialogState,
          ) {
            return AlertDialog(
              title: const Text(
                'Create Visitor Pass',
              ),
              content: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: 600,
                  maxHeight: 620,
                ),
                child: Form(
                  key: formKey,
                  child: SingleChildScrollView(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          DropdownButtonFormField<String>(
                            initialValue: visitorId,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'Visitor',
                              border: OutlineInputBorder(),
                            ),
                            items: availableVisitors
                                .map(
                                  (visitor) => DropdownMenuItem(
                                    value: visitor.visitorId,
                                    child: Text(
                                      visitor.fullName,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                )
                                .toList(),
                            onChanged: (value) {
                              if (value == null) return;

                              setDialogState(() {
                                visitorId = value;
                              });
                            },
                          ),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<String>(
                            initialValue: admissionId,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'Patient admission',
                              border: OutlineInputBorder(),
                            ),
                            items: workspace.admissions
                                .map(
                                  (admission) => DropdownMenuItem(
                                    value: admission.admissionId,
                                    child: Text(
                                      '${admission.patientName} • '
                                      '${admission.displayLocation}',
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                )
                                .toList(),
                            onChanged: (value) {
                              if (value == null) return;

                              setDialogState(() {
                                admissionId = value;
                              });
                            },
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            initialValue: relationship,
                            decoration: const InputDecoration(
                              labelText: 'Relationship to patient',
                              hintText:
                                  'Family, spouse, parent, primary contact',
                              border: OutlineInputBorder(),
                            ),
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return 'Relationship is required.';
                              }

                              return null;
                            },
                            onChanged: (value) {
                              relationship = value;
                            },
                          ),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<String>(
                            initialValue: passType,
                            decoration: const InputDecoration(
                              labelText: 'Pass type',
                              border: OutlineInputBorder(),
                            ),
                            items: _passTypes
                                .map(
                                  (type) => DropdownMenuItem(
                                    value: type,
                                    child: Text(
                                      _humanize(type),
                                    ),
                                  ),
                                )
                                .toList(),
                            onChanged: (value) {
                              if (value == null) return;

                              setDialogState(() {
                                passType = value;
                              });
                            },
                          ),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<int>(
                            initialValue: durationHours,
                            decoration: const InputDecoration(
                              labelText: 'Pass validity',
                              border: OutlineInputBorder(),
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: 2,
                                child: Text('2 hours'),
                              ),
                              DropdownMenuItem(
                                value: 4,
                                child: Text('4 hours'),
                              ),
                              DropdownMenuItem(
                                value: 8,
                                child: Text('8 hours'),
                              ),
                              DropdownMenuItem(
                                value: 24,
                                child: Text('24 hours'),
                              ),
                              DropdownMenuItem(
                                value: 72,
                                child: Text('3 days'),
                              ),
                              DropdownMenuItem(
                                value: 168,
                                child: Text('7 days'),
                              ),
                            ],
                            onChanged: (value) {
                              if (value == null) return;

                              setDialogState(() {
                                durationHours = value;
                              });
                            },
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: maxEntriesController,
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                            decoration: const InputDecoration(
                              labelText: 'Maximum entries',
                              border: OutlineInputBorder(),
                            ),
                            validator: (value) {
                              final number = int.tryParse(
                                value?.trim() ?? '',
                              );

                              if (number == null || number < 1) {
                                return 'Enter at least 1.';
                              }

                              return null;
                            },
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: purposeController,
                            maxLines: 2,
                            decoration: const InputDecoration(
                              labelText: 'Visit purpose',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 8),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            value: approveNow,
                            onChanged: (value) {
                              setDialogState(() {
                                approveNow = value;
                              });
                            },
                            title: const Text(
                              'Approve pass immediately',
                            ),
                          ),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            value: requiresId,
                            onChanged: (value) {
                              setDialogState(() {
                                requiresId = value;
                              });
                            },
                            title: const Text(
                              'Require identity verification at check-in',
                            ),
                          ),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            value: restrictionOverride,
                            onChanged: (value) {
                              setDialogState(() {
                                restrictionOverride = value;
                              });
                            },
                            title: const Text(
                              'Override visitor restriction',
                            ),
                            subtitle: const Text(
                              'Only use with authorised staff approval.',
                            ),
                          ),
                          if (restrictionOverride) ...[
                            const SizedBox(height: 8),
                            TextFormField(
                              controller: overrideController,
                              maxLines: 3,
                              decoration: const InputDecoration(
                                labelText: 'Override reason',
                                border: OutlineInputBorder(),
                              ),
                              validator: (value) {
                                if (restrictionOverride &&
                                    (value == null || value.trim().isEmpty)) {
                                  return 'Override reason is required.';
                                }

                                return null;
                              },
                            ),
                          ],
                          const SizedBox(height: 12),
                          TextField(
                            controller: notesController,
                            maxLines: 3,
                            decoration: const InputDecoration(
                              labelText: 'Notes',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.of(dialogContext).pop();
                  },
                  child: const Text('Cancel'),
                ),
                FilledButton.icon(
                  onPressed: () {
                    if (!(formKey.currentState?.validate() ?? false)) {
                      ScaffoldMessenger.of(dialogContext).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Check the highlighted fields before creating the pass.',
                          ),
                        ),
                      );
                      return;
                    }

                    Navigator.of(dialogContext).pop({
                      'visitor_id': visitorId,
                      'admission_id': admissionId,
                      'relationship': relationship,
                      'pass_type': passType,
                      'duration': durationHours,
                      'max_entries': int.parse(
                        maxEntriesController.text,
                      ),
                      'purpose': purposeController.text,
                      'approve_now': approveNow,
                      'requires_id': requiresId,
                      'override': restrictionOverride,
                      'override_reason': overrideController.text,
                      'notes': notesController.text,
                    });
                  },
                  icon: const Icon(
                    Icons.badge_rounded,
                  ),
                  label: const Text(
                    'Create Pass',
                  ),
                ),
              ],
            );
          },
        );
      },
    );

    _disposeControllersAfterDialog([
      purposeController,
      maxEntriesController,
      overrideController,
      notesController,
    ]);

    if (result == null || !mounted) return;

    final admission = workspace.admissions.firstWhere(
      (item) => item.admissionId == result['admission_id'],
    );

    final now = DateTime.now();

    setState(() {
      _actionBusy = true;
    });

    _showMessage('Creating visitor pass...');

    try {
      final pass = await _service
          .createVisitorPass(
        hospitalId: hospitalId,
        visitorId: result['visitor_id'].toString(),
        patientId: admission.patientId,
        admissionId: admission.admissionId,
        relationshipToPatient: result['relationship'].toString(),
        visitPurpose: result['purpose']?.toString(),
        passType: result['pass_type'].toString(),
        validFrom: now,
        validUntil: now.add(
          Duration(
            hours: result['duration'] as int,
          ),
        ),
        maxEntries: result['max_entries'] as int,
        requestedWardId: admission.wardId,
        requiresIdentityVerification: result['requires_id'] as bool,
        approveNow: result['approve_now'] as bool,
        restrictionOverride: result['override'] as bool,
        overrideReason: result['override_reason']?.toString(),
        notes: result['notes']?.toString(),
      )
          .timeout(
        const Duration(seconds: 25),
        onTimeout: () => throw Exception(
          'The server did not respond. Check the connection and try again.',
        ),
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).hideCurrentSnackBar();

      await _showPassCreatedDialog(
        pass,
      );

      if (!mounted) return;

      await _refreshAfterDialog();
    } catch (error) {
      _showMessage(
        'Visitor pass could not be created: $error',
        error: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          _actionBusy = false;
        });
      }
    }
  }

  Future<void> _showPassCreatedDialog(
    VisitorPassCreationResult pass,
  ) async {
    var copied = false;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (
            dialogContext,
            setDialogState,
          ) {
            return AlertDialog(
              title: const Text(
                'Visitor Pass Created',
              ),
              content: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: 520,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _dialogDetail(
                        'Pass number',
                        pass.passNumber,
                      ),
                      _dialogDetail(
                        'Status',
                        _humanize(pass.status),
                      ),
                      _dialogDetail(
                        'Valid from',
                        _formatDate(pass.validFrom),
                      ),
                      _dialogDetail(
                        'Valid until',
                        _formatDate(pass.validUntil),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'QR Token',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: context.cBgPrimary,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: context.cDivider,
                          ),
                        ),
                        child: SelectableText(
                          pass.qrToken,
                        ),
                      ),
                      if (copied) ...[
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Icon(
                              Icons.check_circle_rounded,
                              color: CorviaColors.success,
                              size: 18,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Token copied to clipboard',
                              style: TextStyle(
                                color: CorviaColors.success,
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton.icon(
                  onPressed: () async {
                    await Clipboard.setData(
                      ClipboardData(
                        text: pass.qrToken,
                      ),
                    );

                    if (!dialogContext.mounted) {
                      return;
                    }

                    setDialogState(() {
                      copied = true;
                    });
                  },
                  icon: Icon(
                    copied ? Icons.check_rounded : Icons.copy_rounded,
                  ),
                  label: Text(
                    copied ? 'Copied' : 'Copy Token',
                  ),
                ),
                FilledButton(
                  onPressed: () {
                    Navigator.of(dialogContext).pop();
                  },
                  child: const Text('Done'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _approvePass(
    HospitalVisitorPassRecord pass,
  ) async {
    if (_actionBusy) {
      return;
    }

    setState(() {
      _actionBusy = true;
    });

    try {
      await _service.approveVisitorPass(
        pass.visitorPassId,
      );

      _showMessage(
        'Visitor pass approved.',
      );

      await _loadWorkspace();
    } catch (error) {
      _showMessage(
        'Visitor pass could not be approved: $error',
        error: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          _actionBusy = false;
        });
      }
    }
  }

  Future<void> _revokePass(
    HospitalVisitorPassRecord pass,
  ) async {
    final controller = TextEditingController();

    final reason = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text(
            'Revoke Visitor Pass',
          ),
          content: TextField(
            controller: controller,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Revocation reason',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
              },
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final value = controller.text.trim();

                if (value.isEmpty) return;

                Navigator.of(dialogContext).pop(value);
              },
              child: const Text('Revoke Pass'),
            ),
          ],
        );
      },
    );

    _disposeControllersAfterDialog([
      controller,
    ]);

    if (reason == null || !mounted) return;

    setState(() {
      _actionBusy = true;
    });

    try {
      await _service.revokeVisitorPass(
        visitorPassId: pass.visitorPassId,
        reason: reason,
      );

      _showMessage(
        'Visitor pass revoked.',
      );

      await _loadWorkspace();
    } catch (error) {
      _showMessage(
        'Visitor pass could not be revoked: $error',
        error: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          _actionBusy = false;
        });
      }
    }
  }

  Future<void> _checkoutVisitor(
    HospitalVisitorCheckinRecord checkin,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text(
            'Check Visitor Out',
          ),
          content: Text(
            'Check ${checkin.visitorName} out of the hospital?',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(false);
              },
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              onPressed: () {
                Navigator.of(dialogContext).pop(true);
              },
              icon: const Icon(
                Icons.logout_rounded,
              ),
              label: const Text(
                'Check Out',
              ),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) return;

    setState(() {
      _actionBusy = true;
    });

    try {
      final result = await _service.checkoutVisitor(
        checkinId: checkin.checkinId,
      );

      if (!result.success) {
        throw Exception(
          result.reason ?? 'Visitor could not be checked out.',
        );
      }

      _showMessage(
        'Visitor checked out successfully.',
      );

      await _loadWorkspace();
    } catch (error) {
      _showMessage(
        'Visitor checkout failed: $error',
        error: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          _actionBusy = false;
        });
      }
    }
  }

  Future<void> _showRestrictionDialog() async {
    final workspace = _workspace;
    final hospitalId = _selectedHospitalId;

    if (workspace == null || hospitalId == null) {
      return;
    }

    if (workspace.admissions.isEmpty) {
      _showMessage(
        'No patient admission is available.',
        error: true,
      );
      return;
    }

    String admissionId = workspace.admissions.first.admissionId;

    String type = 'approved_only';
    int durationHours = 24;

    final reasonController = TextEditingController();

    final formKey = GlobalKey<FormState>();

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (
            context,
            setDialogState,
          ) {
            return AlertDialog(
              title: const Text(
                'Add Visitor Restriction',
              ),
              content: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: 560,
                  maxHeight: 560,
                ),
                child: Form(
                  key: formKey,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        DropdownButtonFormField<String>(
                          initialValue: admissionId,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Patient admission',
                            border: OutlineInputBorder(),
                          ),
                          items: workspace.admissions
                              .map(
                                (admission) => DropdownMenuItem(
                                  value: admission.admissionId,
                                  child: Text(
                                    '${admission.patientName} • '
                                    '${admission.displayLocation}',
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: (value) {
                            if (value == null) return;

                            setDialogState(() {
                              admissionId = value;
                            });
                          },
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          initialValue: type,
                          decoration: const InputDecoration(
                            labelText: 'Restriction type',
                            border: OutlineInputBorder(),
                          ),
                          items: _restrictionTypes
                              .map(
                                (item) => DropdownMenuItem(
                                  value: item,
                                  child: Text(
                                    _humanize(item),
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: (value) {
                            if (value == null) return;

                            setDialogState(() {
                              type = value;
                            });
                          },
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<int>(
                          initialValue: durationHours,
                          decoration: const InputDecoration(
                            labelText: 'Restriction duration',
                            border: OutlineInputBorder(),
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: 4,
                              child: Text('4 hours'),
                            ),
                            DropdownMenuItem(
                              value: 8,
                              child: Text('8 hours'),
                            ),
                            DropdownMenuItem(
                              value: 24,
                              child: Text('24 hours'),
                            ),
                            DropdownMenuItem(
                              value: 72,
                              child: Text('3 days'),
                            ),
                            DropdownMenuItem(
                              value: 168,
                              child: Text('7 days'),
                            ),
                            DropdownMenuItem(
                              value: 720,
                              child: Text('30 days'),
                            ),
                          ],
                          onChanged: (value) {
                            if (value == null) return;

                            setDialogState(() {
                              durationHours = value;
                            });
                          },
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: reasonController,
                          maxLines: 4,
                          decoration: const InputDecoration(
                            labelText: 'Restriction reason',
                            border: OutlineInputBorder(),
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Restriction reason is required.';
                            }

                            return null;
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.of(dialogContext).pop();
                  },
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () {
                    if (!(formKey.currentState?.validate() ?? false)) {
                      return;
                    }

                    Navigator.of(dialogContext).pop({
                      'admission_id': admissionId,
                      'type': type,
                      'duration': durationHours,
                      'reason': reasonController.text,
                    });
                  },
                  child: const Text(
                    'Create Restriction',
                  ),
                ),
              ],
            );
          },
        );
      },
    );

    _disposeControllersAfterDialog([
      reasonController,
    ]);

    if (result == null || !mounted) return;

    final admission = workspace.admissions.firstWhere(
      (item) => item.admissionId == result['admission_id'],
    );

    final now = DateTime.now();

    setState(() {
      _actionBusy = true;
    });

    try {
      await _service.createRestriction(
        hospitalId: hospitalId,
        patientId: admission.patientId,
        admissionId: admission.admissionId,
        restrictionType: result['type'].toString(),
        reason: result['reason'].toString(),
        startsAt: now,
        endsAt: now.add(
          Duration(
            hours: result['duration'] as int,
          ),
        ),
      );

      _showMessage(
        'Visitor restriction created.',
      );

      await _loadWorkspace();
    } catch (error) {
      _showMessage(
        'Restriction could not be created: $error',
        error: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          _actionBusy = false;
        });
      }
    }
  }

  Future<void> _revokeRestriction(
    PatientVisitorRestrictionRecord restriction,
  ) async {
    final controller = TextEditingController();

    final reason = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text(
            'Revoke Visitor Restriction',
          ),
          content: TextField(
            controller: controller,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Revocation reason',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
              },
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final value = controller.text.trim();

                if (value.isEmpty) return;

                Navigator.of(dialogContext).pop(value);
              },
              child: const Text(
                'Revoke Restriction',
              ),
            ),
          ],
        );
      },
    );

    _disposeControllersAfterDialog([
      controller,
    ]);

    if (reason == null || !mounted) return;

    setState(() {
      _actionBusy = true;
    });

    try {
      await _service.revokeRestriction(
        restrictionId: restriction.restrictionId,
        reason: reason,
      );

      _showMessage(
        'Visitor restriction revoked.',
      );

      await _loadWorkspace();
    } catch (error) {
      _showMessage(
        'Restriction could not be revoked: $error',
        error: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          _actionBusy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.cBgPrimary,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            _buildTabs(),
            if (_refreshing && _workspace != null)
              LinearProgressIndicator(
                minHeight: 2,
                color: context.cAccentReadable,
                backgroundColor: Colors.transparent,
              ),
            Expanded(
              child: _loading
                  ? Center(
                      child: CircularProgressIndicator(
                        color: context.cAccentReadable,
                      ),
                    )
                  : _error != null && _workspace == null
                      ? _buildErrorState()
                      : _workspace == null
                          ? _buildEmptyWorkspace()
                          : TabBarView(
                              controller: _tabController,
                              children: [
                                _buildOverviewTab(),
                                _buildVisitorsTab(),
                                _buildPassesTab(),
                                _buildCheckinsTab(),
                                _buildRestrictionsTab(),
                              ],
                            ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(
        20,
        18,
        20,
        14,
      ),
      decoration: BoxDecoration(
        color: context.cBgSecondary,
        border: Border(
          bottom: BorderSide(
            color: context.cDivider,
          ),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 700;

          final heading = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Visitor Access Management',
                style: TextStyle(
                  color: context.cTextPrimary,
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Manage visitor records, passes, restrictions, check-ins and check-outs.',
                style: TextStyle(
                  color: context.cTextSecondary,
                  fontSize: 13,
                ),
              ),
            ],
          );

          final hospitalDropdown = SizedBox(
            width: compact ? double.infinity : 260,
            child: DropdownButtonFormField<String>(
              key: ValueKey(
                'hospital-${_selectedHospitalId ?? 'none'}',
              ),
              initialValue: _selectedHospitalId,
              decoration: const InputDecoration(
                labelText: 'Hospital',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: _hospitals.map((hospital) {
                final id = _hospitalIdFromMap(hospital);

                return DropdownMenuItem(
                  value: id,
                  child: Text(
                    _hospitalNameFromMap(
                      hospital,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                );
              }).toList(),
              onChanged: _loading || _refreshing
                  ? null
                  : (value) {
                      if (value == null) return;

                      _selectHospital(value);
                    },
            ),
          );

          final actions = Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: _actionBusy || _refreshing ? null : _loadWorkspace,
                icon: _refreshing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                        ),
                      )
                    : const Icon(
                        Icons.refresh_rounded,
                      ),
                label: Text(
                  _refreshing ? 'Refreshing...' : 'Refresh',
                ),
              ),
              FilledButton.icon(
                onPressed: _actionBusy || _refreshing
                    ? null
                    : () {
                        _openScanner();
                      },
                icon: const Icon(
                  Icons.qr_code_scanner_rounded,
                ),
                label: const Text(
                  'Scan Visitor',
                ),
              ),
            ],
          );

          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                heading,
                const SizedBox(height: 14),
                hospitalDropdown,
                const SizedBox(height: 12),
                actions,
              ],
            );
          }

          return Row(
            children: [
              Expanded(child: heading),
              const SizedBox(width: 14),
              hospitalDropdown,
              const SizedBox(width: 12),
              actions,
            ],
          );
        },
      ),
    );
  }

  Widget _buildTabs() {
    return Container(
      color: context.cBgSecondary,
      child: TabBar(
        controller: _tabController,
        isScrollable: true,
        tabAlignment: TabAlignment.start,
        labelColor: context.cAccentReadable,
        unselectedLabelColor: context.cTextSecondary,
        indicatorColor: context.cAccentReadable,
        tabs: const [
          Tab(
            icon: Icon(
              Icons.dashboard_rounded,
            ),
            text: 'Overview',
          ),
          Tab(
            icon: Icon(
              Icons.people_alt_rounded,
            ),
            text: 'Visitors',
          ),
          Tab(
            icon: Icon(
              Icons.badge_rounded,
            ),
            text: 'Passes',
          ),
          Tab(
            icon: Icon(
              Icons.login_rounded,
            ),
            text: 'Check-ins',
          ),
          Tab(
            icon: Icon(
              Icons.block_rounded,
            ),
            text: 'Restrictions',
          ),
        ],
      ),
    );
  }

  Widget _buildOverviewTab() {
    final workspace = _workspace!;
    final stats = workspace.stats;

    final metrics = [
      _VisitorMetric(
        label: 'Visitors',
        value: stats.totalVisitors,
        icon: Icons.people_alt_rounded,
        color: context.cAccentReadable,
      ),
      _VisitorMetric(
        label: 'Checked In',
        value: stats.currentlyCheckedIn,
        icon: Icons.login_rounded,
        color: CorviaColors.success,
      ),
      _VisitorMetric(
        label: 'Check-ins Today',
        value: stats.checkinsToday,
        icon: Icons.how_to_reg_rounded,
        color: CorviaColors.success,
      ),
      _VisitorMetric(
        label: 'Pending Passes',
        value: stats.pendingPasses,
        icon: Icons.pending_actions_rounded,
        color: CorviaColors.warning,
      ),
      _VisitorMetric(
        label: 'Approved Passes',
        value: stats.approvedPasses,
        icon: Icons.verified_rounded,
        color: CorviaColors.success,
      ),
      _VisitorMetric(
        label: 'Denied Today',
        value: stats.deniedToday,
        icon: Icons.gpp_bad_rounded,
        color: CorviaColors.danger,
      ),
      _VisitorMetric(
        label: 'Restrictions',
        value: stats.activeRestrictions,
        icon: Icons.block_rounded,
        color: CorviaColors.danger,
      ),
      _VisitorMetric(
        label: 'Blocked Visitors',
        value: stats.blockedVisitors,
        icon: Icons.person_off_rounded,
        color: CorviaColors.danger,
      ),
    ];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 1000
                  ? 4
                  : constraints.maxWidth >= 560
                      ? 2
                      : 1;

              const spacing = 12.0;

              final width =
                  (constraints.maxWidth - ((columns - 1) * spacing)) / columns;

              return Wrap(
                spacing: spacing,
                runSpacing: spacing,
                children: metrics.map((metric) {
                  return SizedBox(
                    width: width,
                    child: _VisitorMetricCard(
                      metric: metric,
                    ),
                  );
                }).toList(),
              );
            },
          ),
          const SizedBox(height: 18),
          _panel(
            title: 'Visitor Quick Actions',
            subtitle: 'Common hospital visitor operations',
            icon: Icons.bolt_rounded,
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                FilledButton.icon(
                  onPressed: _actionBusy || _refreshing
                      ? null
                      : () {
                          _showVisitorDialog();
                        },
                  icon: const Icon(
                    Icons.person_add_rounded,
                  ),
                  label: const Text(
                    'Add Visitor',
                  ),
                ),
                FilledButton.tonalIcon(
                  onPressed: _actionBusy || _refreshing
                      ? null
                      : () {
                          _showCreatePassDialog();
                        },
                  icon: const Icon(
                    Icons.badge_rounded,
                  ),
                  label: const Text(
                    'Create Visitor Pass',
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: _actionBusy || _refreshing
                      ? null
                      : () {
                          _openScanner();
                        },
                  icon: const Icon(
                    Icons.qr_code_scanner_rounded,
                  ),
                  label: const Text(
                    'Scan Visitor Pass',
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: _actionBusy || _refreshing
                      ? null
                      : _showRestrictionDialog,
                  icon: const Icon(
                    Icons.block_rounded,
                  ),
                  label: const Text(
                    'Add Restriction',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          _panel(
            title: 'Currently Checked In',
            subtitle: 'Visitors currently inside the hospital',
            icon: Icons.location_on_rounded,
            child: workspace.openCheckins.isEmpty
                ? _emptyState(
                    icon: Icons.person_search_rounded,
                    title: 'No visitors currently checked in',
                    message: 'Checked-in visitors will appear here.',
                  )
                : Column(
                    children: workspace.openCheckins
                        .take(6)
                        .map(
                          _overviewCheckinCard,
                        )
                        .toList(),
                  ),
          ),
          const SizedBox(height: 18),
          _panel(
            title: 'Pending Pass Approvals',
            subtitle: 'Visitor passes waiting for staff approval',
            icon: Icons.pending_actions_rounded,
            child: workspace.pendingPasses.isEmpty
                ? _emptyState(
                    icon: Icons.verified_rounded,
                    title: 'No pending passes',
                    message: 'All visitor passes are currently processed.',
                  )
                : Column(
                    children: workspace.pendingPasses
                        .take(6)
                        .map(
                          _overviewPendingPassCard,
                        )
                        .toList(),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildVisitorsTab() {
    final visitors = _filteredVisitors;

    return Column(
      children: [
        _filterBar(
          controller: _visitorSearchController,
          hint: 'Search visitor records',
          action: FilledButton.icon(
            onPressed: _actionBusy || _refreshing
                ? null
                : () {
                    _showVisitorDialog();
                  },
            icon: const Icon(
              Icons.person_add_rounded,
            ),
            label: const Text('Add Visitor'),
          ),
        ),
        Expanded(
          child: visitors.isEmpty
              ? _emptyState(
                  icon: Icons.people_outline_rounded,
                  title: 'No visitors found',
                  message: 'Add a visitor or adjust the search filter.',
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(18),
                  itemCount: visitors.length,
                  itemBuilder: (
                    context,
                    index,
                  ) {
                    return _visitorCard(
                      visitors[index],
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildPassesTab() {
    final passes = _filteredPasses;

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          color: context.cBgSecondary,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 650;

              final search = TextField(
                controller: _passSearchController,
                onChanged: (_) {
                  setState(() {});
                },
                decoration: const InputDecoration(
                  hintText: 'Search visitor passes',
                  prefixIcon: Icon(
                    Icons.search_rounded,
                  ),
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              );

              final filter = DropdownButtonFormField<String>(
                key: ValueKey(
                  'pass-status-$_passStatusFilter',
                ),
                initialValue: _passStatusFilter,
                decoration: const InputDecoration(
                  labelText: 'Status',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: const [
                  DropdownMenuItem(
                    value: 'all',
                    child: Text('All statuses'),
                  ),
                  DropdownMenuItem(
                    value: 'pending',
                    child: Text('Pending'),
                  ),
                  DropdownMenuItem(
                    value: 'approved',
                    child: Text('Approved'),
                  ),
                  DropdownMenuItem(
                    value: 'active',
                    child: Text('Active'),
                  ),
                  DropdownMenuItem(
                    value: 'used',
                    child: Text('Used'),
                  ),
                  DropdownMenuItem(
                    value: 'expired',
                    child: Text('Expired'),
                  ),
                  DropdownMenuItem(
                    value: 'revoked',
                    child: Text('Revoked'),
                  ),
                ],
                onChanged: _refreshing
                    ? null
                    : (value) {
                        if (value == null) return;

                        setState(() {
                          _passStatusFilter = value;
                        });
                      },
              );

              final action = FilledButton.icon(
                onPressed: _actionBusy || _refreshing
                    ? null
                    : () {
                        _showCreatePassDialog();
                      },
                icon: const Icon(
                  Icons.add_card_rounded,
                ),
                label: const Text(
                  'Create Pass',
                ),
              );

              if (compact) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    search,
                    const SizedBox(height: 10),
                    filter,
                    const SizedBox(height: 10),
                    action,
                  ],
                );
              }

              return Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: search,
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 180,
                    child: filter,
                  ),
                  const SizedBox(width: 10),
                  action,
                ],
              );
            },
          ),
        ),
        Expanded(
          child: passes.isEmpty
              ? _emptyState(
                  icon: Icons.badge_outlined,
                  title: 'No visitor passes found',
                  message:
                      'Create a visitor pass or change the current filters.',
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(18),
                  itemCount: passes.length,
                  itemBuilder: (
                    context,
                    index,
                  ) {
                    return _passCard(
                      passes[index],
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildCheckinsTab() {
    final checkins = _filteredCheckins;

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          color: context.cBgSecondary,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 650;

              final search = TextField(
                controller: _checkinSearchController,
                onChanged: (_) {
                  setState(() {});
                },
                decoration: const InputDecoration(
                  hintText: 'Search visitor check-ins',
                  prefixIcon: Icon(
                    Icons.search_rounded,
                  ),
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              );

              final toggle = FilterChip(
                selected: _showOpenCheckinsOnly,
                label: const Text(
                  'Currently inside only',
                ),
                onSelected: _refreshing
                    ? null
                    : (value) {
                        setState(() {
                          _showOpenCheckinsOnly = value;
                        });
                      },
              );

              final scanner = FilledButton.icon(
                onPressed: _actionBusy || _refreshing
                    ? null
                    : () {
                        _openScanner();
                      },
                icon: const Icon(
                  Icons.qr_code_scanner_rounded,
                ),
                label: const Text(
                  'Scan Visitor',
                ),
              );

              if (compact) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    search,
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        toggle,
                        scanner,
                      ],
                    ),
                  ],
                );
              }

              return Row(
                children: [
                  Expanded(child: search),
                  const SizedBox(width: 12),
                  toggle,
                  const SizedBox(width: 12),
                  scanner,
                ],
              );
            },
          ),
        ),
        Expanded(
          child: checkins.isEmpty
              ? _emptyState(
                  icon: Icons.login_rounded,
                  title: 'No visitor check-ins found',
                  message:
                      'Visitor check-ins will appear after a pass is scanned.',
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(18),
                  itemCount: checkins.length,
                  itemBuilder: (
                    context,
                    index,
                  ) {
                    return _checkinCard(
                      checkins[index],
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildRestrictionsTab() {
    final restrictions = _filteredRestrictions;

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          color: context.cBgSecondary,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 650;

              final search = TextField(
                controller: _restrictionSearchController,
                onChanged: (_) {
                  setState(() {});
                },
                decoration: const InputDecoration(
                  hintText: 'Search visitor restrictions',
                  prefixIcon: Icon(
                    Icons.search_rounded,
                  ),
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              );

              final toggle = FilterChip(
                selected: _showActiveRestrictionsOnly,
                label: const Text(
                  'Active only',
                ),
                onSelected: _refreshing
                    ? null
                    : (value) {
                        setState(() {
                          _showActiveRestrictionsOnly = value;
                        });
                      },
              );

              final action = FilledButton.icon(
                onPressed:
                    _actionBusy || _refreshing ? null : _showRestrictionDialog,
                icon: const Icon(
                  Icons.add_moderator_rounded,
                ),
                label: const Text(
                  'Add Restriction',
                ),
              );

              if (compact) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    search,
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        toggle,
                        action,
                      ],
                    ),
                  ],
                );
              }

              return Row(
                children: [
                  Expanded(child: search),
                  const SizedBox(width: 12),
                  toggle,
                  const SizedBox(width: 12),
                  action,
                ],
              );
            },
          ),
        ),
        Expanded(
          child: restrictions.isEmpty
              ? _emptyState(
                  icon: Icons.health_and_safety_outlined,
                  title: 'No visitor restrictions found',
                  message: 'Patient visitor restrictions will appear here.',
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(18),
                  itemCount: restrictions.length,
                  itemBuilder: (
                    context,
                    index,
                  ) {
                    return _restrictionCard(
                      restrictions[index],
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _visitorCard(
    HospitalVisitorRecord visitor,
  ) {
    final color =
        visitor.isBlocked ? CorviaColors.danger : context.cAccentReadable;

    final identitySummary = visitor.idNumber?.trim();

    return _recordCard(
      leading: Icons.person_rounded,
      color: color,
      title: visitor.fullName,
      subtitle: identitySummary != null && identitySummary.isNotEmpty
          ? identitySummary
          : 'Identity to verify at reception',
      details: [
        'Identity type: ${_humanize(visitor.idType)}',
        if (visitor.phone != null) 'Phone: ${visitor.phone}',
        if (visitor.email != null) 'Email: ${visitor.email}',
        if (visitor.vehicleRegistration != null)
          'Vehicle: ${visitor.vehicleRegistration}',
        if (visitor.isBlocked)
          'Blocked: ${visitor.blockedReason ?? 'No reason'}',
      ],
      status: visitor.isBlocked ? 'Blocked' : 'Active',
      actions: [
        OutlinedButton.icon(
          onPressed: _actionBusy || _refreshing
              ? null
              : () {
                  _showVisitorDialog(
                    visitor: visitor,
                  );
                },
          icon: const Icon(
            Icons.edit_rounded,
          ),
          label: const Text('Edit'),
        ),
        OutlinedButton.icon(
          onPressed: _actionBusy || _refreshing || visitor.isBlocked
              ? null
              : () {
                  _showCreatePassDialog(
                    selectedVisitor: visitor,
                  );
                },
          icon: const Icon(
            Icons.badge_rounded,
          ),
          label: const Text(
            'Create Pass',
          ),
        ),
        OutlinedButton.icon(
          onPressed: _actionBusy || _refreshing
              ? null
              : () {
                  _setVisitorBlocked(
                    visitor,
                  );
                },
          icon: Icon(
            visitor.isBlocked ? Icons.lock_open_rounded : Icons.block_rounded,
          ),
          label: Text(
            visitor.isBlocked ? 'Unblock' : 'Block',
          ),
          style: OutlinedButton.styleFrom(
            foregroundColor:
                visitor.isBlocked ? CorviaColors.success : CorviaColors.danger,
          ),
        ),
      ],
    );
  }

  Widget _passCard(
    HospitalVisitorPassRecord pass,
  ) {
    final color = _statusColor(pass.status);

    return _recordCard(
      leading: Icons.badge_rounded,
      color: color,
      title: pass.passNumber,
      subtitle: '${pass.visitorName} visiting ${pass.patientName}',
      details: [
        'Type: ${_humanize(pass.passType)}',
        'Relationship: ${_humanize(pass.relationshipToPatient)}',
        'Valid: ${_formatDate(pass.validFrom)} '
            'to ${_formatDate(pass.validUntil)}',
        'Entries: ${pass.entriesUsed}'
            '${pass.maxEntries == null ? '' : ' / ${pass.maxEntries}'}',
        if (pass.requestedWardName != null) 'Ward: ${pass.requestedWardName}',
        if (pass.requiresIdentityVerification)
          'Identity verification required at check-in',
        if (pass.isCurrentlyCheckedIn)
          'Currently checked in since ${_formatDate(pass.checkedInAt)}',
      ],
      status: _humanize(pass.status),
      actions: [
        OutlinedButton.icon(
          onPressed: _actionBusy || _refreshing
              ? null
              : () async {
                  await Clipboard.setData(
                    ClipboardData(
                      text: pass.qrToken,
                    ),
                  );

                  if (!mounted) {
                    return;
                  }

                  _showMessage(
                    'QR token copied.',
                  );
                },
          icon: const Icon(
            Icons.copy_rounded,
          ),
          label: const Text(
            'Copy Token',
          ),
        ),
        OutlinedButton.icon(
          onPressed: _actionBusy || _refreshing || pass.isCurrentlyCheckedIn
              ? null
              : () {
                  _openScanner(
                    qrToken: pass.qrToken,
                  );
                },
          icon: const Icon(
            Icons.qr_code_scanner_rounded,
          ),
          label: const Text('Scan'),
        ),
        if (pass.canApprove)
          FilledButton.tonalIcon(
            onPressed: _actionBusy || _refreshing
                ? null
                : () {
                    _approvePass(pass);
                  },
            icon: const Icon(
              Icons.verified_rounded,
            ),
            label: const Text('Approve'),
          ),
        if (pass.canRevoke)
          OutlinedButton.icon(
            onPressed: _actionBusy || _refreshing
                ? null
                : () {
                    _revokePass(pass);
                  },
            icon: const Icon(
              Icons.cancel_rounded,
            ),
            label: const Text('Revoke'),
            style: OutlinedButton.styleFrom(
              foregroundColor: CorviaColors.danger,
            ),
          ),
      ],
    );
  }

  Widget _checkinCard(
    HospitalVisitorCheckinRecord checkin,
  ) {
    final color =
        checkin.isOpen ? CorviaColors.success : context.cTextSecondary;

    return _recordCard(
      leading: checkin.isOpen ? Icons.login_rounded : Icons.logout_rounded,
      color: color,
      title: checkin.visitorName,
      subtitle: 'Visiting ${checkin.patientName}',
      details: [
        'Pass: ${checkin.passNumber ?? 'Not available'}',
        'Location: ${checkin.displayLocation}',
        'Checked in: ${_formatDate(checkin.checkinAt)}',
        if (checkin.checkoutAt != null)
          'Checked out: ${_formatDate(checkin.checkoutAt)}',
        'Identity verified: ${checkin.identityVerified ? 'Yes' : 'No'}',
        'Method: ${_humanize(checkin.checkinMethod)}',
      ],
      status: checkin.isOpen ? 'Inside Hospital' : 'Checked Out',
      actions: [
        if (checkin.isOpen)
          FilledButton.tonalIcon(
            onPressed: _actionBusy || _refreshing
                ? null
                : () {
                    _checkoutVisitor(
                      checkin,
                    );
                  },
            icon: const Icon(
              Icons.logout_rounded,
            ),
            label: const Text(
              'Check Out',
            ),
          ),
      ],
    );
  }

  Widget _restrictionCard(
    PatientVisitorRestrictionRecord restriction,
  ) {
    final active = restriction.isCurrentlyActive;

    final color = active ? CorviaColors.danger : context.cTextSecondary;

    return _recordCard(
      leading: Icons.block_rounded,
      color: color,
      title: restriction.patientName,
      subtitle: _humanize(
        restriction.restrictionType,
      ),
      details: [
        restriction.reason,
        'Starts: ${_formatDate(restriction.startsAt)}',
        'Ends: ${_formatDate(restriction.endsAt)}',
        if (restriction.admissionNumber != null)
          'Admission: ${restriction.admissionNumber}',
        if (restriction.revocationReason != null)
          'Revoked: ${restriction.revocationReason}',
      ],
      status: active ? 'Active' : 'Inactive',
      actions: [
        if (active)
          OutlinedButton.icon(
            onPressed: _actionBusy || _refreshing
                ? null
                : () {
                    _revokeRestriction(
                      restriction,
                    );
                  },
            icon: const Icon(
              Icons.remove_moderator_rounded,
            ),
            label: const Text(
              'Revoke',
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: CorviaColors.danger,
            ),
          ),
      ],
    );
  }

  Widget _overviewCheckinCard(
    HospitalVisitorCheckinRecord checkin,
  ) {
    return Container(
      margin: const EdgeInsets.only(
        bottom: 10,
      ),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: context.cBgPrimary,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: context.cDivider,
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.person_pin_circle_rounded,
            color: CorviaColors.success,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  checkin.visitorName,
                  style: TextStyle(
                    color: context.cTextPrimary,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  '${checkin.patientName} • ${checkin.displayLocation}',
                  style: TextStyle(
                    color: context.cTextSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: _actionBusy || _refreshing
                ? null
                : () {
                    _checkoutVisitor(
                      checkin,
                    );
                  },
            child: const Text('Check Out'),
          ),
        ],
      ),
    );
  }

  Widget _overviewPendingPassCard(
    HospitalVisitorPassRecord pass,
  ) {
    return Container(
      margin: const EdgeInsets.only(
        bottom: 10,
      ),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: context.cBgPrimary,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: context.cDivider,
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.pending_actions_rounded,
            color: CorviaColors.warning,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  pass.visitorName,
                  style: TextStyle(
                    color: context.cTextPrimary,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  'Visiting ${pass.patientName} • ${pass.passNumber}',
                  style: TextStyle(
                    color: context.cTextSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: _actionBusy || _refreshing
                ? null
                : () {
                    _approvePass(pass);
                  },
            child: const Text('Approve'),
          ),
        ],
      ),
    );
  }

  Widget _filterBar({
    required TextEditingController controller,
    required String hint,
    required Widget action,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      color: context.cBgSecondary,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 560;

          final search = TextField(
            controller: controller,
            onChanged: (_) {
              setState(() {});
            },
            decoration: InputDecoration(
              hintText: hint,
              prefixIcon: const Icon(
                Icons.search_rounded,
              ),
              border: const OutlineInputBorder(),
              isDense: true,
            ),
          );

          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                search,
                const SizedBox(height: 10),
                action,
              ],
            );
          }

          return Row(
            children: [
              Expanded(child: search),
              const SizedBox(width: 12),
              action,
            ],
          );
        },
      ),
    );
  }

  Widget _recordCard({
    required IconData leading,
    required Color color,
    required String title,
    required String subtitle,
    required List<String> details,
    required String status,
    required List<Widget> actions,
  }) {
    return Container(
      margin: const EdgeInsets.only(
        bottom: 12,
      ),
      padding: const EdgeInsets.all(15),
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
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  leading,
                  color: color,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: context.cTextPrimary,
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 3),
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
              const SizedBox(width: 8),
              Flexible(
                child: Align(
                  alignment: Alignment.topRight,
                  child: _statusPill(
                    status,
                    color,
                  ),
                ),
              ),
            ],
          ),
          if (details.isNotEmpty) ...[
            const SizedBox(height: 12),
            ...details.map(
              (detail) => Padding(
                padding: const EdgeInsets.only(
                  bottom: 4,
                ),
                child: Text(
                  detail,
                  style: TextStyle(
                    color: context.cTextSecondary,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
          ],
          if (actions.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: actions,
            ),
          ],
        ],
      ),
    );
  }

  Widget _panel({
    required String title,
    required String subtitle,
    required IconData icon,
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: context.cBgSecondary,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: context.cDivider,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 43,
                height: 43,
                decoration: BoxDecoration(
                  color: context.cAccentReadable.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  icon,
                  color: context.cAccentReadable,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: context.cTextPrimary,
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                      ),
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
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }

  Widget _statusPill(
    String label,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: color.withValues(alpha: 0.24),
        ),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  Widget _emptyState({
    required IconData icon,
    required String title,
    required String message,
  }) {
    return Center(
      child: Container(
        constraints: const BoxConstraints(
          maxWidth: 500,
        ),
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: context.cAccentReadable,
              size: 42,
            ),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: context.cTextPrimary,
                fontSize: 17,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
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

  Widget _buildErrorState() {
    return Center(
      child: Container(
        constraints: const BoxConstraints(
          maxWidth: 550,
        ),
        margin: const EdgeInsets.all(20),
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: CorviaColors.danger.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: CorviaColors.danger.withValues(alpha: 0.24),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline_rounded,
              color: CorviaColors.danger,
              size: 40,
            ),
            const SizedBox(height: 12),
            Text(
              'Visitor workspace could not load',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: context.cTextPrimary,
                fontSize: 17,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _error ?? 'Unknown error',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: context.cTextSecondary,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: _loading ? null : _loadInitialData,
              icon: const Icon(
                Icons.refresh_rounded,
              ),
              label: const Text('Try Again'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyWorkspace() {
    return _emptyState(
      icon: Icons.local_hospital_outlined,
      title: 'No visitor workspace available',
      message: 'Select a hospital and refresh the visitor workspace.',
    );
  }

  Widget _dialogDetail(
    String label,
    String value,
  ) {
    return Padding(
      padding: const EdgeInsets.only(
        bottom: 8,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
            ),
          ),
        ],
      ),
    );
  }
}

class _VisitorMetric {
  const _VisitorMetric({
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

class _VisitorMetricCard extends StatelessWidget {
  const _VisitorMetricCard({
    required this.metric,
  });

  final _VisitorMetric metric;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(15),
      constraints: const BoxConstraints(
        minHeight: 82,
      ),
      decoration: BoxDecoration(
        color: context.cBgSecondary,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: context.cDivider,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: metric.color.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              metric.icon,
              color: metric.color,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  metric.value.toString(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: context.cTextPrimary,
                    fontSize: 21,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  metric.label,
                  maxLines: 2,
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
    );
  }
}
