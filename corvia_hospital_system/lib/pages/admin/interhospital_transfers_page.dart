import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../theme/app_theme.dart';
import '../../widgets/status_view.dart';

class InterhospitalTransfersPage extends StatefulWidget {
  const InterhospitalTransfersPage({
    super.key,
  });

  @override
  State<InterhospitalTransfersPage> createState() {
    return _InterhospitalTransfersPageState();
  }
}

class _InterhospitalTransfersPageState
    extends State<InterhospitalTransfersPage>
    with SingleTickerProviderStateMixin {
  static const Duration _requestTimeout = Duration(seconds: 25);

  final SupabaseClient _supabase = Supabase.instance.client;

  final TextEditingController _searchController = TextEditingController();

  late final TabController _tabController;

  bool _loading = true;
  bool _refreshing = false;
  bool _saving = false;

  String? _error;

  String? _hospitalId;
  String _hospitalName = 'Hospital';

  List<_TransferHospital> _destinationHospitals = const [];
  List<_TransferPatient> _patients = const [];
  List<_HospitalTransfer> _transfers = const [];

  @override
  void initState() {
    super.initState();

    _tabController = TabController(
      length: 4,
      vsync: this,
    );

    _loadAll(
      fullLoader: true,
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    _tabController.dispose();

    super.dispose();
  }

  Future<void> _loadAll({
    required bool fullLoader,
  }) async {
    if (mounted) {
      setState(() {
        _error = null;
        _loading = fullLoader;
        _refreshing = !fullLoader;
      });
    }

    try {
      final contextResponse = await _supabase
          .rpc(
            'corvia_hospital_transfer_context',
          )
          .timeout(
            _requestTimeout,
          );

      final contextRows = _rows(
        contextResponse,
      );

      if (contextRows.isEmpty) {
        throw StateError(
          'Hospital context could not be loaded.',
        );
      }

      final contextRow = contextRows.first;

      final hospitalId = _cleanText(
        contextRow['hospital_id'],
      );

      final hospitalName = _cleanText(
        contextRow['hospital_name'],
        fallback: 'Hospital',
      );

      if (hospitalId.isEmpty) {
        throw StateError(
          'Hospital context has no hospital ID.',
        );
      }

      final results = await Future.wait([
        _supabase
            .rpc(
              'corvia_hospital_transfer_hospitals',
            )
            .timeout(
              _requestTimeout,
            ),
        _supabase
            .rpc(
              'corvia_hospital_transfer_patients',
            )
            .timeout(
              _requestTimeout,
            ),
        _supabase
            .rpc(
              'corvia_hospital_my_transfers',
            )
            .timeout(
              _requestTimeout,
            ),
      ]);

      final hospitals = _rows(
        results[0],
      )
          .map(
            _TransferHospital.fromMap,
          )
          .where(
            (hospital) => hospital.id.isNotEmpty,
          )
          .toList();

      final patients = _rows(
        results[1],
      )
          .map(
            _TransferPatient.fromMap,
          )
          .where(
            (patient) => patient.id.isNotEmpty,
          )
          .toList();

      final transfers = _rows(
        results[2],
      )
          .map(
            _HospitalTransfer.fromMap,
          )
          .where(
            (transfer) => transfer.id.isNotEmpty,
          )
          .toList();

      transfers.sort(
        (
          first,
          second,
        ) {
          return second.sortDate.compareTo(
            first.sortDate,
          );
        },
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _hospitalId = hospitalId;
        _hospitalName = hospitalName;
        _destinationHospitals = hospitals;
        _patients = patients;
        _transfers = transfers;
        _loading = false;
        _refreshing = false;
        _error = null;
      });
    } on TimeoutException {
      if (!mounted) {
        return;
      }

      setState(() {
        _loading = false;
        _refreshing = false;
        _error =
            'Loading transfers took too long. Please check your connection and try again.';
      });
    } catch (error) {
      debugPrint(
        'InterhospitalTransfersPage load failed: $error',
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _loading = false;
        _refreshing = false;
        _error = 'Inter-hospital transfers could not be loaded. $error';
      });
    }
  }

  Future<void> _refresh() {
    return _loadAll(
      fullLoader: false,
    );
  }

  /// Adds a receiving hospital that is not yet on Corvia, so a transfer can
  /// be recorded to it. Returns the new hospital id.
  Future<String?> _addDestinationHospital(
    BuildContext context, {
    String initialName = '',
  }) async {
    final name = TextEditingController(text: initialName);
    final city = TextEditingController();
    final phone = TextEditingController();
    final email = TextEditingController();
    final formKey = GlobalKey<FormState>();
    var saving = false;
    String? error;

    final id = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Add receiving hospital'),
          content: SizedBox(
            width: 440,
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: name,
                    autofocus: true,
                    decoration: const InputDecoration(
                      labelText: 'Hospital name',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) => (value ?? '').trim().length < 3
                        ? 'Enter the hospital name.'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: city,
                    decoration: const InputDecoration(
                      labelText: 'City / town',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: phone,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'Phone (optional)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: email,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Email (optional)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  if (error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      error!,
                      style: TextStyle(color: CorviaColors.danger),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed:
                  saving ? null : () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      if (!(formKey.currentState?.validate() ?? false)) {
                        return;
                      }
                      setDialogState(() {
                        saving = true;
                        error = null;
                      });
                      try {
                        String? text(TextEditingController c) =>
                            c.text.trim().isEmpty ? null : c.text.trim();
                        final row = await _supabase
                            .from('hospitals')
                            .insert({
                              'name': name.text.trim(),
                              'city': text(city),
                              'phone': text(phone),
                              'email': text(email),
                              'type': 'external',
                              'is_active': true,
                            })
                            .select('id, name')
                            .single()
                            .timeout(_requestTimeout);
                        final hospital = _TransferHospital.fromMap(
                          Map<String, dynamic>.from(row),
                        );
                        if (mounted) {
                          setState(() {
                            _destinationHospitals = [
                              ..._destinationHospitals,
                              hospital,
                            ];
                          });
                        }
                        if (dialogContext.mounted) {
                          Navigator.of(dialogContext).pop(hospital.id);
                        }
                      } catch (e) {
                        setDialogState(() {
                          saving = false;
                          error = 'Could not add the hospital. Your account '
                              'may not be allowed to add hospitals. $e';
                        });
                      }
                    },
              child: Text(saving ? 'Adding...' : 'Add hospital'),
            ),
          ],
        ),
      ),
    );

    for (final controller in [name, city, phone, email]) {
      controller.dispose();
    }
    return id;
  }

  /// Searchable pop-up for choosing the receiving hospital.
  Future<String?> _pickDestinationHospital(
    BuildContext context,
    String? currentId,
  ) {
    var query = '';

    return showDialog<String>(
      context: context,
      builder: (pickerContext) {
        return StatefulBuilder(
          builder: (pickerContext, setPickerState) {
            final needle = query.trim().toLowerCase();
            final matches = _destinationHospitals
                .where(
                  (hospital) =>
                      needle.isEmpty ||
                      hospital.name.toLowerCase().contains(needle),
                )
                .toList();

            return AlertDialog(
              title: const Text('Choose destination hospital'),
              contentPadding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              content: SizedBox(
                width: 460,
                height: 420,
                child: Column(
                  children: [
                    TextField(
                      autofocus: true,
                      decoration: const InputDecoration(
                        hintText: 'Search hospitals',
                        prefixIcon: Icon(Icons.search),
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (value) =>
                          setPickerState(() => query = value),
                    ),
                    const SizedBox(height: 10),
                    Expanded(
                      child: matches.isEmpty
                          ? Center(
                              child: Text(
                                _destinationHospitals.isEmpty
                                    ? 'No other hospitals are on Corvia yet. '
                                        'Use "Add hospital" to add the '
                                        'receiving hospital.'
                                    : 'No hospitals match your search.',
                                textAlign: TextAlign.center,
                              ),
                            )
                          : ListView.separated(
                              itemCount: matches.length,
                              separatorBuilder: (_, __) =>
                                  const Divider(height: 1),
                              itemBuilder: (_, index) {
                                final hospital = matches[index];
                                final isCurrent = hospital.id == currentId;

                                return ListTile(
                                  leading: const Icon(
                                    Icons.local_hospital_outlined,
                                  ),
                                  title: Text(hospital.name),
                                  trailing: isCurrent
                                      ? const Icon(Icons.check_rounded)
                                      : null,
                                  selected: isCurrent,
                                  onTap: () => Navigator.of(
                                    pickerContext,
                                  ).pop(hospital.id),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton.icon(
                  onPressed: () async {
                    final created = await _addDestinationHospital(
                      pickerContext,
                      initialName: query.trim(),
                    );
                    if (created != null && pickerContext.mounted) {
                      Navigator.of(pickerContext).pop(created);
                    }
                  },
                  icon: const Icon(Icons.add_business_outlined),
                  label: const Text('Add hospital'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(pickerContext).pop(),
                  child: const Text('Cancel'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  List<_HospitalTransfer> _filteredTransfers(
    _TransferFilter filter,
  ) {
    final query = _searchController.text.trim().toLowerCase();

    final filtered = _transfers.where(
      (transfer) {
        final matchesTab = switch (filter) {
          _TransferFilter.overview => true,
          _TransferFilter.incoming => transfer.direction == 'incoming',
          _TransferFilter.outgoing => transfer.direction == 'outgoing',
          _TransferFilter.all => true,
        };

        if (!matchesTab) {
          return false;
        }

        final searchText = [
          transfer.patientName,
          transfer.patientIdentifier,
          transfer.sourceHospitalName,
          transfer.destinationHospitalName,
          transfer.status,
          transfer.urgency,
          transfer.reason,
          transfer.clinicalSummary,
        ].join(' ').toLowerCase();

        return query.isEmpty || searchText.contains(query);
      },
    ).toList();

    filtered.sort(
      (
        first,
        second,
      ) {
        return second.sortDate.compareTo(
          first.sortDate,
        );
      },
    );

    return filtered;
  }

  int get _incomingCount {
    return _transfers
        .where(
          (transfer) =>
              transfer.direction == 'incoming' &&
              transfer.isActive,
        )
        .length;
  }

  int get _outgoingCount {
    return _transfers
        .where(
          (transfer) =>
              transfer.direction == 'outgoing' &&
              transfer.isActive,
        )
        .length;
  }

  int get _acceptedCount {
    return _transfers
        .where(
          (transfer) => transfer.status == 'accepted',
        )
        .length;
  }

  int get _readyCount {
    return _transfers
        .where(
          (transfer) => transfer.status == 'ready',
        )
        .length;
  }

  int get _inTransitCount {
    return _transfers
        .where(
          (transfer) => transfer.status == 'in_transit',
        )
        .length;
  }

  int get _receivedCount {
    return _transfers
        .where(
          (transfer) => transfer.status == 'received',
        )
        .length;
  }

  int get _urgentActiveCount {
    return _transfers
        .where(
          (transfer) =>
              transfer.isActive &&
              {
                'urgent',
                'critical',
              }.contains(
                transfer.urgency,
              ),
        )
        .length;
  }

  int get _completedCount {
    return _transfers
        .where(
          (transfer) => transfer.status == 'completed',
        )
        .length;
  }

  Future<void> _openCreateDialog() async {
    if (_saving) {
      return;
    }

    if (_patients.isEmpty) {
      _showSnack(
        'No patients are available for transfer from this hospital.',
        isError: true,
      );

      return;
    }

    final formKey = GlobalKey<FormState>();

    final reasonController = TextEditingController();
    final summaryController = TextEditingController();

    String? selectedPatientId = _patients.first.id;
    // No default: the receiving hospital must be a deliberate choice.
    String? selectedDestinationId;
    String urgency = 'routine';

    final created = await showDialog<bool>(
      context: context,
      barrierDismissible: !_saving,
      builder: (
        dialogContext,
      ) {
        return StatefulBuilder(
          builder: (
            dialogContext,
            setDialogState,
          ) {
            Future<void> submit() async {
              if (_saving) {
                return;
              }

              final form = formKey.currentState;

              if (form == null || !form.validate()) {
                return;
              }

              setDialogState(() {
                _saving = true;
              });

              if (mounted) {
                setState(() {
                  _saving = true;
                });
              }

              try {
                await _supabase
                    .rpc(
                      'corvia_hospital_create_transfer',
                      params: {
                        'p_patient_id': selectedPatientId,
                        'p_destination_hospital_id': selectedDestinationId,
                        'p_reason': reasonController.text.trim(),
                        'p_urgency': urgency,
                        'p_clinical_summary': summaryController.text.trim(),
                      },
                    )
                    .timeout(
                      _requestTimeout,
                    );

                if (dialogContext.mounted) {
                  Navigator.of(dialogContext).pop(true);
                }
              } on TimeoutException {
                _dialogSnack(
                  dialogContext,
                  'Creating the transfer took too long. Please try again.',
                );
              } on PostgrestException catch (error) {
                _dialogSnack(
                  dialogContext,
                  error.message,
                );
              } catch (error) {
                _dialogSnack(
                  dialogContext,
                  'Transfer could not be created. $error',
                );
              } finally {
                if (mounted) {
                  setState(() {
                    _saving = false;
                  });
                }

                setDialogState(() {
                  _saving = false;
                });
              }
            }

            return AlertDialog(
              backgroundColor: context.cBgSecondary,
              title: Text(
                'New Inter-Hospital Transfer',
                style: TextStyle(
                  color: context.cTextPrimary,
                  fontWeight: FontWeight.w900,
                ),
              ),
              content: SizedBox(
                width: 620,
                child: Form(
                  key: formKey,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        DropdownButtonFormField<String>(
                          initialValue: selectedPatientId,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Patient',
                            prefixIcon: Icon(Icons.person_outline_rounded),
                            border: OutlineInputBorder(),
                          ),
                          items: _patients.map(
                            (patient) {
                              return DropdownMenuItem<String>(
                                value: patient.id,
                                child: Text(
                                  '${patient.name} • ${patient.identifier}',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              );
                            },
                          ).toList(),
                          onChanged: _saving
                              ? null
                              : (value) {
                                  setDialogState(() {
                                    selectedPatientId = value;
                                  });
                                },
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Please select a patient.';
                            }

                            return null;
                          },
                        ),
                        const SizedBox(height: 14),
                        FormField<String>(
                          initialValue: selectedDestinationId,
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Please select a destination hospital.';
                            }

                            return null;
                          },
                          builder: (field) {
                            final selected = _destinationHospitals
                                .where(
                                  (hospital) => hospital.id == field.value,
                                )
                                .firstOrNull;

                            return InkWell(
                              borderRadius: BorderRadius.circular(4),
                              onTap: _saving
                                  ? null
                                  : () async {
                                      final picked =
                                          await _pickDestinationHospital(
                                        dialogContext,
                                        field.value,
                                      );
                                      if (picked == null) return;
                                      setDialogState(() {
                                        selectedDestinationId = picked;
                                      });
                                      field.didChange(picked);
                                    },
                              child: InputDecorator(
                                isEmpty: selected == null,
                                decoration: InputDecoration(
                                  labelText: 'Destination Hospital',
                                  hintText: 'Tap to choose a hospital',
                                  prefixIcon: const Icon(
                                    Icons.local_hospital_outlined,
                                  ),
                                  suffixIcon: const Icon(
                                    Icons.arrow_drop_down_rounded,
                                  ),
                                  border: const OutlineInputBorder(),
                                  errorText: field.errorText,
                                ),
                                child: selected == null
                                    ? null
                                    : Text(
                                        selected.name,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 14),
                        DropdownButtonFormField<String>(
                          initialValue: urgency,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Urgency',
                            prefixIcon: Icon(Icons.priority_high_rounded),
                            border: OutlineInputBorder(),
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: 'routine',
                              child: Text('Routine'),
                            ),
                            DropdownMenuItem(
                              value: 'soon',
                              child: Text('Soon'),
                            ),
                            DropdownMenuItem(
                              value: 'urgent',
                              child: Text('Urgent'),
                            ),
                            DropdownMenuItem(
                              value: 'critical',
                              child: Text('Critical'),
                            ),
                          ],
                          onChanged: _saving
                              ? null
                              : (value) {
                                  if (value == null) {
                                    return;
                                  }

                                  setDialogState(() {
                                    urgency = value;
                                  });
                                },
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: reasonController,
                          enabled: !_saving,
                          minLines: 3,
                          maxLines: 5,
                          maxLength: 3000,
                          decoration: const InputDecoration(
                            labelText: 'Transfer Reason',
                            hintText:
                                'Example: Specialist care required, bed availability, emergency escalation...',
                            prefixIcon: Icon(Icons.notes_outlined),
                            border: OutlineInputBorder(),
                          ),
                          validator: (value) {
                            final text = value?.trim() ?? '';

                            if (text.length < 3) {
                              return 'Please provide a transfer reason.';
                            }

                            return null;
                          },
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: summaryController,
                          enabled: !_saving,
                          minLines: 4,
                          maxLines: 8,
                          maxLength: 10000,
                          decoration: const InputDecoration(
                            labelText: 'Clinical / Transfer Summary',
                            hintText:
                                'Add safe transfer notes for the receiving hospital.',
                            prefixIcon: Icon(Icons.summarize_outlined),
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'This creates an outgoing request for your hospital and an incoming request for the destination hospital.',
                          style: TextStyle(
                            color: context.cTextSecondary,
                            fontSize: 12,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: _saving
                      ? null
                      : () {
                          Navigator.of(dialogContext).pop(false);
                        },
                  child: const Text('Cancel'),
                ),
                FilledButton.icon(
                  onPressed: _saving ? null : submit,
                  icon: _saving
                      ? const SizedBox(
                          width: 17,
                          height: 17,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                          ),
                        )
                      : const Icon(Icons.add_rounded),
                  label: Text(
                    _saving ? 'Creating...' : 'Create Transfer',
                  ),
                ),
              ],
            );
          },
        );
      },
    );

    reasonController.dispose();
    summaryController.dispose();

    if (created == true && mounted) {
      _showSnack(
        'Transfer request created.',
      );

      await _refresh();
    }
  }

  Future<void> _performAction(
    _HospitalTransfer transfer,
    String action, {
    bool requireNote = false,
  }) async {
    if (_saving) {
      return;
    }

    final noteController = TextEditingController();

    final title = _actionTitle(
      action,
    );

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: !_saving,
      builder: (
        dialogContext,
      ) {
        return StatefulBuilder(
          builder: (
            dialogContext,
            setDialogState,
          ) {
            Future<void> submit() async {
              final note = noteController.text.trim();

              if (requireNote && note.length < 3) {
                _dialogSnack(
                  dialogContext,
                  'Please provide a note/reason.',
                );

                return;
              }

              setDialogState(() {
                _saving = true;
              });

              if (mounted) {
                setState(() {
                  _saving = true;
                });
              }

              try {
                await _supabase
                    .rpc(
                      'corvia_hospital_update_transfer_status',
                      params: {
                        'p_transfer_id': transfer.id,
                        'p_action': action,
                        'p_note': note.isEmpty ? null : note,
                      },
                    )
                    .timeout(
                      _requestTimeout,
                    );

                if (dialogContext.mounted) {
                  Navigator.of(dialogContext).pop(true);
                }
              } on TimeoutException {
                _dialogSnack(
                  dialogContext,
                  'Updating the transfer took too long. Please try again.',
                );
              } on PostgrestException catch (error) {
                _dialogSnack(
                  dialogContext,
                  error.message,
                );
              } catch (error) {
                _dialogSnack(
                  dialogContext,
                  'Transfer could not be updated. $error',
                );
              } finally {
                if (mounted) {
                  setState(() {
                    _saving = false;
                  });
                }

                setDialogState(() {
                  _saving = false;
                });
              }
            }

            return AlertDialog(
              backgroundColor: context.cBgSecondary,
              title: Text(
                title,
                style: TextStyle(
                  color: context.cTextPrimary,
                  fontWeight: FontWeight.w900,
                ),
              ),
              content: SizedBox(
                width: 540,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _DialogLine(
                      label: 'Patient',
                      value: transfer.patientName,
                    ),
                    _DialogLine(
                      label: 'From',
                      value: transfer.sourceHospitalName,
                    ),
                    _DialogLine(
                      label: 'To',
                      value: transfer.destinationHospitalName,
                    ),
                    _DialogLine(
                      label: 'Current status',
                      value: _prettyStatus(transfer.status),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: noteController,
                      enabled: !_saving,
                      minLines: 3,
                      maxLines: 6,
                      decoration: InputDecoration(
                        labelText: requireNote
                            ? 'Required note / reason'
                            : 'Optional note',
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'This action updates the shared transfer status for both hospitals.',
                      style: TextStyle(
                        color: context.cTextSecondary,
                        fontSize: 12,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: _saving
                      ? null
                      : () {
                          Navigator.of(dialogContext).pop(false);
                        },
                  child: const Text('Cancel'),
                ),
                FilledButton.icon(
                  onPressed: _saving ? null : submit,
                  icon: _saving
                      ? const SizedBox(
                          width: 17,
                          height: 17,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                          ),
                        )
                      : const Icon(Icons.check_circle_outline_rounded),
                  label: Text(
                    _saving ? 'Saving...' : title,
                  ),
                ),
              ],
            );
          },
        );
      },
    );

    noteController.dispose();

    if (confirmed == true && mounted) {
      _showSnack(
        'Transfer updated.',
      );

      await _refresh();
    }
  }

  String _actionTitle(
    String action,
  ) {
    switch (action) {
      case 'accept':
        return 'Accept Transfer';

      case 'reject':
        return 'Reject Transfer';

      case 'mark_ready':
        return 'Mark Transfer Ready';

      case 'dispatch':
        return 'Dispatch Transfer';

      case 'receive':
        return 'Receive Patient';

      case 'complete':
        return 'Complete Transfer';

      case 'cancel':
        return 'Cancel Transfer';

      default:
        return 'Update Transfer';
    }
  }

  void _dialogSnack(
    BuildContext dialogContext,
    String message,
  ) {
    if (!dialogContext.mounted) {
      return;
    }

    ScaffoldMessenger.of(dialogContext)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            message,
          ),
        ),
      );
  }

  void _showSnack(
    String message, {
    bool isError = false,
  }) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          backgroundColor: isError ? CorviaColors.danger : null,
          content: Text(
            message,
          ),
        ),
      );
  }

  Color _statusColor(
    String value,
  ) {
    switch (value) {
      case 'requested':
        return CorviaColors.warning;

      case 'accepted':
        return CorviaColors.success;

      case 'ready':
        return Colors.orange.shade700;

      case 'in_transit':
        return Colors.indigo;

      case 'received':
        return Colors.teal;

      case 'completed':
        return CorviaColors.success;

      case 'rejected':
      case 'cancelled':
        return CorviaColors.danger;

      default:
        return context.cAccentReadable;
    }
  }

  Color _urgencyColor(
    String value,
  ) {
    switch (value) {
      case 'critical':
        return CorviaColors.danger;

      case 'urgent':
        return Colors.deepOrange;

      case 'soon':
        return CorviaColors.warning;

      default:
        return context.cAccentReadable;
    }
  }

  String _prettyStatus(
    String value,
  ) {
    final cleaned = value
        .trim()
        .replaceAll(
          '_',
          ' ',
        )
        .replaceAll(
          '-',
          ' ',
        );

    if (cleaned.isEmpty) {
      return 'Unknown';
    }

    return cleaned
        .split(RegExp(r'\s+'))
        .where(
          (word) => word.isNotEmpty,
        )
        .map(
          (word) => '${word[0].toUpperCase()}'
              '${word.substring(1).toLowerCase()}',
        )
        .join(' ');
  }

  String _formatDate(
    DateTime? value,
  ) {
    if (value == null) {
      return 'No date';
    }

    return DateFormat('EEE, d MMM yyyy • HH:mm').format(
      value.toLocal(),
    );
  }

  @override
  Widget build(
    BuildContext context,
  ) {
    return Scaffold(
      backgroundColor: context.cBgPrimary,
      body: Stack(
        children: [
          Positioned.fill(
            child: _buildBody(),
          ),
          if (_refreshing)
            const Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: LinearProgressIndicator(),
            ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading && _transfers.isEmpty) {
      return StatusView.loading(
        message: 'Loading inter-hospital transfers...',
      );
    }

    if (_error != null && _transfers.isEmpty) {
      return StatusView.error(
        friendlyMessage: _error!,
        onRetry: () {
          _loadAll(
            fullLoader: true,
          );
        },
      );
    }

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(
          18,
        ),
        children: [
          _buildHeader(),
          const SizedBox(height: 14),
          _buildTabs(),
          const SizedBox(height: 14),
          _buildStats(),
          const SizedBox(height: 14),
          _buildQuickActions(),
          const SizedBox(height: 14),
          _buildSearch(),
          const SizedBox(height: 14),
          _buildTabContent(),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return LayoutBuilder(
      builder: (
        context,
        constraints,
      ) {
        final compact = constraints.maxWidth < 700;

        final title = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Inter-Hospital Transfers',
              style: TextStyle(
                color: context.cTextPrimary,
                fontSize: 24,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              'Request, accept, dispatch, receive and complete patient transfers.',
              style: TextStyle(
                color: context.cTextSecondary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _hospitalName,
              style: TextStyle(
                color: context.cAccentReadable,
                fontWeight: FontWeight.w800,
                fontSize: 12,
              ),
            ),
          ],
        );

        final actions = Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            OutlinedButton.icon(
              onPressed: _refreshing || _loading ? null : _refresh,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Refresh'),
            ),
            FilledButton.icon(
              onPressed: _saving ? null : _openCreateDialog,
              icon: const Icon(Icons.add_rounded),
              label: const Text('New Transfer'),
            ),
          ],
        );

        if (compact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              title,
              const SizedBox(height: 12),
              actions,
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: title,
            ),
            const SizedBox(width: 16),
            actions,
          ],
        );
      },
    );
  }

  Widget _buildTabs() {
    return TabBar(
      controller: _tabController,
      isScrollable: false,
      tabs: const [
        Tab(
          icon: Icon(Icons.dashboard_rounded),
          text: 'Overview',
        ),
        Tab(
          icon: Icon(Icons.south_west_rounded),
          text: 'Incoming',
        ),
        Tab(
          icon: Icon(Icons.north_east_rounded),
          text: 'Outgoing',
        ),
        Tab(
          icon: Icon(Icons.list_alt_rounded),
          text: 'All Transfers',
        ),
      ],
      onTap: (_) {
        setState(() {});
      },
    );
  }

  Widget _buildStats() {
    final items = [
      _StatItem(
        icon: Icons.south_west_rounded,
        label: 'Incoming Requests',
        value: _incomingCount,
        color: CorviaColors.warning,
      ),
      _StatItem(
        icon: Icons.north_east_rounded,
        label: 'Outgoing Requests',
        value: _outgoingCount,
        color: Colors.orange.shade700,
      ),
      _StatItem(
        icon: Icons.verified_rounded,
        label: 'Accepted',
        value: _acceptedCount,
        color: CorviaColors.success,
      ),
      _StatItem(
        icon: Icons.assignment_turned_in_rounded,
        label: 'Ready',
        value: _readyCount,
        color: Colors.orange.shade700,
      ),
      _StatItem(
        icon: Icons.local_shipping_rounded,
        label: 'In Transit',
        value: _inTransitCount,
        color: Colors.indigo,
      ),
      _StatItem(
        icon: Icons.input_rounded,
        label: 'Received',
        value: _receivedCount,
        color: Colors.teal,
      ),
      _StatItem(
        icon: Icons.emergency_rounded,
        label: 'Urgent Active',
        value: _urgentActiveCount,
        color: CorviaColors.danger,
      ),
      _StatItem(
        icon: Icons.check_circle_outline_rounded,
        label: 'Completed',
        value: _completedCount,
        color: CorviaColors.success,
      ),
    ];

    return GridView.builder(
      itemCount: items.length,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 290,
        mainAxisExtent: 82,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemBuilder: (
        context,
        index,
      ) {
        return _StatCard(
          item: items[index],
        );
      },
    );
  }

  Widget _buildQuickActions() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(
        16,
      ),
      decoration: BoxDecoration(
        color: context.cBgSecondary,
        borderRadius: BorderRadius.circular(
          18,
        ),
        border: Border.all(
          color: context.cDivider,
        ),
      ),
      child: LayoutBuilder(
        builder: (
          context,
          constraints,
        ) {
          final compact = constraints.maxWidth < 600;

          final title = Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: context.cAccentReadable.withValues(
                    alpha: 0.10,
                  ),
                  borderRadius: BorderRadius.circular(
                    13,
                  ),
                ),
                child: Icon(
                  Icons.bolt_rounded,
                  color: context.cAccentReadable,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Quick Actions',
                      style: TextStyle(
                        color: context.cTextPrimary,
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                      ),
                    ),
                    Text(
                      'Manage the transfer lifecycle',
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

          final buttons = Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              FilledButton.icon(
                onPressed: _saving ? null : _openCreateDialog,
                icon: const Icon(Icons.add_rounded),
                label: const Text('Request Transfer'),
              ),
              OutlinedButton.icon(
                onPressed: _refreshing ? null : _refresh,
                icon: const Icon(Icons.sync_rounded),
                label: const Text('Refresh Statuses'),
              ),
            ],
          );

          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                title,
                const SizedBox(height: 14),
                buttons,
              ],
            );
          }

          return Row(
            children: [
              Expanded(
                child: title,
              ),
              buttons,
            ],
          );
        },
      ),
    );
  }

  Widget _buildSearch() {
    return TextField(
      controller: _searchController,
      onChanged: (_) {
        setState(() {});
      },
      style: TextStyle(
        color: context.cTextPrimary,
      ),
      decoration: InputDecoration(
        prefixIcon: const Icon(Icons.search_rounded),
        labelText: 'Search transfers',
        hintText: 'Patient, hospital, reason, urgency or status',
        suffixIcon: _searchController.text.trim().isEmpty
            ? null
            : IconButton(
                onPressed: () {
                  setState(() {
                    _searchController.clear();
                  });
                },
                icon: const Icon(Icons.clear_rounded),
              ),
        border: const OutlineInputBorder(),
      ),
    );
  }

  Widget _buildTabContent() {
    final index = _tabController.index;

    final filter = switch (index) {
      1 => _TransferFilter.incoming,
      2 => _TransferFilter.outgoing,
      3 => _TransferFilter.all,
      _ => _TransferFilter.overview,
    };

    final transfers = _filteredTransfers(
      filter,
    );

    if (filter == _TransferFilter.overview) {
      final urgent = transfers
          .where(
            (transfer) =>
                transfer.isActive &&
                {
                  'urgent',
                  'critical',
                }.contains(
                  transfer.urgency,
                ),
          )
          .toList();

      final inTransit = transfers
          .where(
            (transfer) => transfer.status == 'in_transit',
          )
          .toList();

      final incomingRequested = transfers
          .where(
            (transfer) =>
                transfer.direction == 'incoming' &&
                transfer.status == 'requested',
          )
          .toList();

      return Column(
        children: [
          _TransferSection(
            title: 'Urgent Active Transfers',
            subtitle: 'Urgent, emergency and critical transfers',
            icon: Icons.emergency_rounded,
            transfers: urgent,
            emptyText: 'No urgent active transfers.',
            cardBuilder: _buildTransferCard,
          ),
          const SizedBox(height: 14),
          _TransferSection(
            title: 'Patients In Transit',
            subtitle: 'Patients currently travelling between hospitals',
            icon: Icons.local_shipping_rounded,
            transfers: inTransit,
            emptyText: 'No patients are currently in transit.',
            cardBuilder: _buildTransferCard,
          ),
          const SizedBox(height: 14),
          _TransferSection(
            title: 'Incoming Requests',
            subtitle: 'Transfers awaiting a destination decision',
            icon: Icons.assignment_late_outlined,
            transfers: incomingRequested,
            emptyText: 'No incoming transfer requests.',
            cardBuilder: _buildTransferCard,
          ),
        ],
      );
    }

    if (transfers.isEmpty) {
      return StatusView.empty(
        icon: Icons.compare_arrows_rounded,
        title: 'No transfers found',
        subtitle: 'Transfers for this hospital will appear here.',
        onRetry: _refresh,
      );
    }

    return Column(
      children: [
        for (var index = 0; index < transfers.length; index++) ...[
          _buildTransferCard(
            transfers[index],
          ),
          if (index != transfers.length - 1)
            const SizedBox(height: 12),
        ],
      ],
    );
  }

  Widget _buildTransferCard(
    _HospitalTransfer transfer,
  ) {
    return _TransferCard(
      transfer: transfer,
      statusColor: _statusColor(
        transfer.status,
      ),
      urgencyColor: _urgencyColor(
        transfer.urgency,
      ),
      statusLabel: _prettyStatus(
        transfer.status,
      ),
      urgencyLabel: _prettyStatus(
        transfer.urgency,
      ),
      requestedAtLabel: _formatDate(
        transfer.requestedAt,
      ),
      saving: _saving,
      onAccept: transfer.canAccept
          ? () {
              _performAction(
                transfer,
                'accept',
              );
            }
          : null,
      onReject: transfer.canReject
          ? () {
              _performAction(
                transfer,
                'reject',
                requireNote: true,
              );
            }
          : null,
      onMarkReady: transfer.canMarkReady
          ? () {
              _performAction(
                transfer,
                'mark_ready',
              );
            }
          : null,
      onDispatch: transfer.canDispatch
          ? () {
              _performAction(
                transfer,
                'dispatch',
              );
            }
          : null,
      onReceive: transfer.canReceive
          ? () {
              _performAction(
                transfer,
                'receive',
              );
            }
          : null,
      onComplete: transfer.canComplete
          ? () {
              _performAction(
                transfer,
                'complete',
              );
            }
          : null,
      onCancel: transfer.canCancel
          ? () {
              _performAction(
                transfer,
                'cancel',
                requireNote: true,
              );
            }
          : null,
    );
  }
}

enum _TransferFilter {
  overview,
  incoming,
  outgoing,
  all,
}

class _TransferHospital {
  const _TransferHospital({
    required this.id,
    required this.name,
  });

  final String id;
  final String name;

  factory _TransferHospital.fromMap(
    Map<String, dynamic> map,
  ) {
    return _TransferHospital(
      id: _cleanText(
        map['id'],
      ),
      name: _cleanText(
        map['name'],
        fallback: 'Hospital',
      ),
    );
  }
}

class _TransferPatient {
  const _TransferPatient({
    required this.id,
    required this.name,
    required this.identifier,
  });

  final String id;
  final String name;
  final String identifier;

  factory _TransferPatient.fromMap(
    Map<String, dynamic> map,
  ) {
    return _TransferPatient(
      id: _cleanText(
        map['id'],
      ),
      name: _cleanText(
        map['name'],
        fallback: 'Patient',
      ),
      identifier: _cleanText(
        map['identifier'],
        fallback: 'Patient record',
      ),
    );
  }
}

class _HospitalTransfer {
  const _HospitalTransfer({
    required this.id,
    required this.patientId,
    required this.patientName,
    required this.patientIdentifier,
    required this.sourceHospitalId,
    required this.sourceHospitalName,
    required this.destinationHospitalId,
    required this.destinationHospitalName,
    required this.urgency,
    required this.status,
    required this.reason,
    required this.clinicalSummary,
    required this.transferNotes,
    required this.rejectionReason,
    required this.requestedAt,
    required this.acceptedAt,
    required this.readyAt,
    required this.dispatchedAt,
    required this.receivedAt,
    required this.completedAt,
    required this.rejectedAt,
    required this.cancelledAt,
    required this.createdAt,
    required this.updatedAt,
    required this.direction,
    required this.canAccept,
    required this.canReject,
    required this.canMarkReady,
    required this.canDispatch,
    required this.canReceive,
    required this.canComplete,
    required this.canCancel,
  });

  final String id;
  final String patientId;
  final String patientName;
  final String patientIdentifier;

  final String sourceHospitalId;
  final String sourceHospitalName;

  final String destinationHospitalId;
  final String destinationHospitalName;

  final String urgency;
  final String status;

  final String reason;
  final String clinicalSummary;
  final String transferNotes;
  final String rejectionReason;

  final DateTime? requestedAt;
  final DateTime? acceptedAt;
  final DateTime? readyAt;
  final DateTime? dispatchedAt;
  final DateTime? receivedAt;
  final DateTime? completedAt;
  final DateTime? rejectedAt;
  final DateTime? cancelledAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  final String direction;

  final bool canAccept;
  final bool canReject;
  final bool canMarkReady;
  final bool canDispatch;
  final bool canReceive;
  final bool canComplete;
  final bool canCancel;

  bool get isActive {
    return {
      'requested',
      'accepted',
      'ready',
      'in_transit',
      'received',
    }.contains(
      status,
    );
  }

  DateTime get sortDate {
    return updatedAt ??
        createdAt ??
        requestedAt ??
        DateTime.fromMillisecondsSinceEpoch(0);
  }

  factory _HospitalTransfer.fromMap(
    Map<String, dynamic> map,
  ) {
    return _HospitalTransfer(
      id: _cleanText(
        map['id'],
      ),
      patientId: _cleanText(
        map['patient_id'],
      ),
      patientName: _cleanText(
        map['patient_name'],
        fallback: 'Patient',
      ),
      patientIdentifier: _cleanText(
        map['patient_identifier'],
        fallback: 'Patient record',
      ),
      sourceHospitalId: _cleanText(
        map['source_hospital_id'],
      ),
      sourceHospitalName: _cleanText(
        map['source_hospital_name'],
        fallback: 'Source hospital',
      ),
      destinationHospitalId: _cleanText(
        map['destination_hospital_id'],
      ),
      destinationHospitalName: _cleanText(
        map['destination_hospital_name'],
        fallback: 'Destination hospital',
      ),
      urgency: _canonical(
        map['urgency'],
        fallback: 'routine',
      ),
      status: _canonical(
        map['status'],
        fallback: 'requested',
      ),
      reason: _cleanText(
        map['reason'],
      ),
      clinicalSummary: _cleanText(
        map['clinical_summary'],
      ),
      transferNotes: _cleanText(
        map['transfer_notes'],
      ),
      rejectionReason: _cleanText(
        map['rejection_reason'],
      ),
      requestedAt: _parseDate(
        map['requested_at'],
      ),
      acceptedAt: _parseDate(
        map['accepted_at'],
      ),
      readyAt: _parseDate(
        map['ready_at'],
      ),
      dispatchedAt: _parseDate(
        map['dispatched_at'],
      ),
      receivedAt: _parseDate(
        map['received_at'],
      ),
      completedAt: _parseDate(
        map['completed_at'],
      ),
      rejectedAt: _parseDate(
        map['rejected_at'],
      ),
      cancelledAt: _parseDate(
        map['cancelled_at'],
      ),
      createdAt: _parseDate(
        map['created_at'],
      ),
      updatedAt: _parseDate(
        map['updated_at'],
      ),
      direction: _canonical(
        map['direction'],
        fallback: 'related',
      ),
      canAccept: _asBool(
        map['can_accept'],
      ),
      canReject: _asBool(
        map['can_reject'],
      ),
      canMarkReady: _asBool(
        map['can_mark_ready'],
      ),
      canDispatch: _asBool(
        map['can_dispatch'],
      ),
      canReceive: _asBool(
        map['can_receive'],
      ),
      canComplete: _asBool(
        map['can_complete'],
      ),
      canCancel: _asBool(
        map['can_cancel'],
      ),
    );
  }
}

class _StatItem {
  const _StatItem({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final int value;
  final Color color;
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.item,
  });

  final _StatItem item;

  @override
  Widget build(
    BuildContext context,
  ) {
    return Container(
      padding: const EdgeInsets.all(
        14,
      ),
      decoration: BoxDecoration(
        color: context.cBgSecondary,
        borderRadius: BorderRadius.circular(
          18,
        ),
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
              color: item.color.withValues(
                alpha: 0.11,
              ),
              borderRadius: BorderRadius.circular(
                14,
              ),
            ),
            child: Icon(
              item.icon,
              color: item.color,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.value.toString(),
                  style: TextStyle(
                    color: context.cTextPrimary,
                    fontWeight: FontWeight.w900,
                    fontSize: 20,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  item.label,
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

class _TransferSection extends StatelessWidget {
  const _TransferSection({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.transfers,
    required this.emptyText,
    required this.cardBuilder,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final List<_HospitalTransfer> transfers;
  final String emptyText;
  final Widget Function(_HospitalTransfer transfer) cardBuilder;

  @override
  Widget build(
    BuildContext context,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(
        16,
      ),
      decoration: BoxDecoration(
        color: context.cBgSecondary,
        borderRadius: BorderRadius.circular(
          18,
        ),
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
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: context.cAccentReadable.withValues(
                    alpha: 0.10,
                  ),
                  borderRadius: BorderRadius.circular(
                    13,
                  ),
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
          const SizedBox(height: 14),
          if (transfers.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(
                18,
              ),
              decoration: BoxDecoration(
                color: context.cBgPrimary,
                borderRadius: BorderRadius.circular(
                  14,
                ),
                border: Border.all(
                  color: context.cDivider,
                ),
              ),
              child: Text(
                emptyText,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: context.cTextSecondary,
                ),
              ),
            )
          else
            Column(
              children: [
                for (var index = 0; index < transfers.length; index++) ...[
                  cardBuilder(
                    transfers[index],
                  ),
                  if (index != transfers.length - 1)
                    const SizedBox(height: 12),
                ],
              ],
            ),
        ],
      ),
    );
  }
}

class _TransferCard extends StatelessWidget {
  const _TransferCard({
    required this.transfer,
    required this.statusColor,
    required this.urgencyColor,
    required this.statusLabel,
    required this.urgencyLabel,
    required this.requestedAtLabel,
    required this.saving,
    required this.onAccept,
    required this.onReject,
    required this.onMarkReady,
    required this.onDispatch,
    required this.onReceive,
    required this.onComplete,
    required this.onCancel,
  });

  final _HospitalTransfer transfer;

  final Color statusColor;
  final Color urgencyColor;

  final String statusLabel;
  final String urgencyLabel;
  final String requestedAtLabel;

  final bool saving;

  final VoidCallback? onAccept;
  final VoidCallback? onReject;
  final VoidCallback? onMarkReady;
  final VoidCallback? onDispatch;
  final VoidCallback? onReceive;
  final VoidCallback? onComplete;
  final VoidCallback? onCancel;

  @override
  Widget build(
    BuildContext context,
  ) {
    final chips = <Widget>[
      _Pill(
        label: transfer.direction == 'incoming' ? 'Incoming' : 'Outgoing',
        color: context.cAccentReadable,
      ),
      _Pill(
        label: statusLabel,
        color: statusColor,
      ),
      _Pill(
        label: urgencyLabel,
        color: urgencyColor,
      ),
    ];

    final actions = <Widget>[
      if (onAccept != null)
        FilledButton.icon(
          onPressed: saving ? null : onAccept,
          icon: const Icon(Icons.check_circle_outline_rounded),
          label: const Text('Accept'),
        ),
      if (onReject != null)
        OutlinedButton.icon(
          onPressed: saving ? null : onReject,
          icon: const Icon(Icons.cancel_outlined),
          label: const Text('Reject'),
          style: OutlinedButton.styleFrom(
            foregroundColor: CorviaColors.danger,
          ),
        ),
      if (onMarkReady != null)
        FilledButton.icon(
          onPressed: saving ? null : onMarkReady,
          icon: const Icon(Icons.assignment_turned_in_outlined),
          label: const Text('Mark Ready'),
        ),
      if (onDispatch != null)
        FilledButton.icon(
          onPressed: saving ? null : onDispatch,
          icon: const Icon(Icons.local_shipping_outlined),
          label: const Text('Dispatch'),
        ),
      if (onReceive != null)
        FilledButton.icon(
          onPressed: saving ? null : onReceive,
          icon: const Icon(Icons.input_rounded),
          label: const Text('Receive'),
        ),
      if (onComplete != null)
        FilledButton.icon(
          onPressed: saving ? null : onComplete,
          icon: const Icon(Icons.verified_rounded),
          label: const Text('Complete'),
        ),
      if (onCancel != null)
        OutlinedButton.icon(
          onPressed: saving ? null : onCancel,
          icon: const Icon(Icons.block_rounded),
          label: const Text('Cancel'),
        ),
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(
        16,
      ),
      decoration: BoxDecoration(
        color: context.cBgSecondary,
        borderRadius: BorderRadius.circular(
          18,
        ),
        border: Border.all(
          color: statusColor.withValues(
            alpha: 0.32,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (
              context,
              constraints,
            ) {
              final compact = constraints.maxWidth < 620;

              final title = Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      transfer.patientName,
                      style: TextStyle(
                        color: context.cTextPrimary,
                        fontWeight: FontWeight.w900,
                        fontSize: 17,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      transfer.patientIdentifier,
                      style: TextStyle(
                        color: context.cTextSecondary,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Requested: $requestedAtLabel',
                      style: TextStyle(
                        color: context.cTextMuted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              );

              final leading = Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: statusColor.withValues(
                    alpha: 0.11,
                  ),
                  borderRadius: BorderRadius.circular(
                    14,
                  ),
                ),
                child: Icon(
                  transfer.direction == 'incoming'
                      ? Icons.south_west_rounded
                      : Icons.north_east_rounded,
                  color: statusColor,
                ),
              );

              if (compact) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        leading,
                        const SizedBox(width: 12),
                        title,
                      ],
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: chips,
                    ),
                  ],
                );
              }

              return Row(
                children: [
                  leading,
                  const SizedBox(width: 12),
                  title,
                  const SizedBox(width: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: chips,
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 14),
          _InfoLine(
            icon: Icons.local_hospital_outlined,
            label: 'From',
            value: transfer.sourceHospitalName,
          ),
          _InfoLine(
            icon: Icons.local_hospital_rounded,
            label: 'To',
            value: transfer.destinationHospitalName,
          ),
          if (transfer.reason.isNotEmpty)
            _InfoLine(
              icon: Icons.notes_outlined,
              label: 'Reason',
              value: transfer.reason,
            ),
          if (transfer.clinicalSummary.isNotEmpty)
            _InfoLine(
              icon: Icons.summarize_outlined,
              label: 'Summary',
              value: transfer.clinicalSummary,
            ),
          if (transfer.transferNotes.isNotEmpty)
            _InfoLine(
              icon: Icons.sticky_note_2_outlined,
              label: 'Notes',
              value: transfer.transferNotes,
            ),
          if (transfer.rejectionReason.isNotEmpty)
            _InfoLine(
              icon: Icons.report_problem_outlined,
              label: 'Rejection',
              value: transfer.rejectionReason,
            ),
          const SizedBox(height: 14),
          _TimelineStrip(
            transfer: transfer,
          ),
          if (actions.isNotEmpty) ...[
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: actions,
            ),
          ],
        ],
      ),
    );
  }
}

class _TimelineStrip extends StatelessWidget {
  const _TimelineStrip({
    required this.transfer,
  });

  final _HospitalTransfer transfer;

  @override
  Widget build(
    BuildContext context,
  ) {
    final steps = [
      _TimelineStep(
        label: 'Requested',
        done: transfer.requestedAt != null,
      ),
      _TimelineStep(
        label: 'Accepted',
        done: transfer.acceptedAt != null,
      ),
      _TimelineStep(
        label: 'Ready',
        done: transfer.readyAt != null,
      ),
      _TimelineStep(
        label: 'Transit',
        done: transfer.dispatchedAt != null,
      ),
      _TimelineStep(
        label: 'Received',
        done: transfer.receivedAt != null,
      ),
      _TimelineStep(
        label: 'Completed',
        done: transfer.completedAt != null,
      ),
    ];

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: steps.map(
        (step) {
          return Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 9,
              vertical: 6,
            ),
            decoration: BoxDecoration(
              color: step.done
                  ? CorviaColors.success.withValues(alpha: 0.10)
                  : context.cBgPrimary,
              borderRadius: BorderRadius.circular(
                999,
              ),
              border: Border.all(
                color: step.done
                    ? CorviaColors.success.withValues(alpha: 0.35)
                    : context.cDivider,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  step.done
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked_rounded,
                  size: 14,
                  color: step.done
                      ? CorviaColors.success
                      : context.cTextMuted,
                ),
                const SizedBox(width: 5),
                Text(
                  step.label,
                  style: TextStyle(
                    color: step.done
                        ? CorviaColors.success
                        : context.cTextSecondary,
                    fontWeight: FontWeight.w700,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          );
        },
      ).toList(),
    );
  }
}

class _TimelineStep {
  const _TimelineStep({
    required this.label,
    required this.done,
  });

  final String label;
  final bool done;
}

class _DialogLine extends StatelessWidget {
  const _DialogLine({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(
    BuildContext context,
  ) {
    return Padding(
      padding: const EdgeInsets.only(
        bottom: 6,
      ),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '$label: ',
              style: TextStyle(
                color: context.cTextPrimary,
                fontWeight: FontWeight.w900,
              ),
            ),
            TextSpan(
              text: value,
              style: TextStyle(
                color: context.cTextSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(
    BuildContext context,
  ) {
    return Padding(
      padding: const EdgeInsets.only(
        bottom: 7,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            size: 17,
            color: context.cAccentReadable,
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 82,
            child: Text(
              label,
              style: TextStyle(
                color: context.cTextMuted,
                fontWeight: FontWeight.w800,
                fontSize: 12,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: context.cTextSecondary,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.label,
    required this.color,
  });

  final String label;
  final Color color;

  @override
  Widget build(
    BuildContext context,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 9,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: color.withValues(
          alpha: 0.10,
        ),
        borderRadius: BorderRadius.circular(
          999,
        ),
        border: Border.all(
          color: color.withValues(
            alpha: 0.25,
          ),
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w900,
          fontSize: 11,
        ),
      ),
    );
  }
}

String _cleanText(
  dynamic value, {
  String fallback = '',
}) {
  if (value == null) {
    return fallback;
  }

  final text = value.toString().trim();

  if (text.isEmpty || text.toLowerCase() == 'null') {
    return fallback;
  }

  return text;
}

String _canonical(
  dynamic value, {
  required String fallback,
}) {
  final text = _cleanText(
    value,
    fallback: fallback,
  )
      .toLowerCase()
      .replaceAll(
        '-',
        '_',
      )
      .replaceAll(
        ' ',
        '_',
      );

  return text.isEmpty ? fallback : text;
}

DateTime? _parseDate(
  dynamic value,
) {
  final text = _cleanText(
    value,
  );

  if (text.isEmpty) {
    return null;
  }

  return DateTime.tryParse(
    text,
  )?.toLocal();
}

bool _asBool(
  dynamic value,
) {
  if (value is bool) {
    return value;
  }

  final text = value?.toString().toLowerCase().trim();

  return text == 'true' || text == '1' || text == 'yes';
}

List<Map<String, dynamic>> _rows(
  dynamic response,
) {
  if (response is! List) {
    return [];
  }

  return response
      .whereType<Map>()
      .map(
        (row) => Map<String, dynamic>.from(
          row,
        ),
      )
      .toList();
}