import 'package:flutter/material.dart';
import 'package:flutter_speed_dial/flutter_speed_dial.dart';
import 'package:intl/intl.dart';

import '../../services/doctor_clinical_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/status_view.dart';

import 'doctor_add_patient_record.dart';

class PatientRecordsPage extends StatefulWidget {
  const PatientRecordsPage({
    super.key,
    this.patientId,
    this.patientName,
  });

  final String? patientId;
  final String? patientName;

  @override
  State<PatientRecordsPage> createState() {
    return _PatientRecordsPageState();
  }
}

class _PatientRecordsPageState extends State<PatientRecordsPage> {
  final DoctorClinicalService _service = DoctorClinicalService();

  final TextEditingController _patientController = TextEditingController();

  DoctorClinicalContext? _doctorContext;

  List<DoctorClinicalPatient> _patients = [];

  String? _selectedPatientId;

  Future<_PatientRecordsBundle>? _future;

  bool _loadingPatients = true;

  bool _showNewestFirst = true;

  String? _patientLoadError;

  @override
  void initState() {
    super.initState();

    _loadPage();
  }

  @override
  void dispose() {
    _patientController.dispose();

    super.dispose();
  }

  Future<void> _loadPage() async {
    if (mounted) {
      setState(() {
        _loadingPatients = true;
        _patientLoadError = null;
      });
    }

    try {
      final doctorContext = await _service.currentContext();

      final patients = await _service.loadDoctorPatients(
        doctorContext,
      );

      String? selectedId = widget.patientId ?? _selectedPatientId;

      if (selectedId != null &&
          !patients.any(
            (
              patient,
            ) =>
                patient.id == selectedId,
          )) {
        /*
         * Keep a patient supplied by another authorised
         * clinical route even if they have no previous
         * appointment/prescription yet.
         */
        if (widget.patientId == selectedId) {
          patients.add(
            DoctorClinicalPatient(
              id: selectedId,
              name: widget.patientName ?? 'Patient',
              profileId: '',
            ),
          );
        } else {
          selectedId = null;
        }
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _doctorContext = doctorContext;

        _patients = patients;

        _selectedPatientId = selectedId;

        _loadingPatients = false;

        if (selectedId != null) {
          final match = _patients
              .where(
                (
                  patient,
                ) =>
                    patient.id == selectedId,
              )
              .firstOrNull;

          _patientController.text =
              match?.name ?? widget.patientName ?? 'Patient';

          _future = _loadBundle(
            selectedId,
          );
        }
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _loadingPatients = false;

        _patientLoadError = _clean(
          error,
        );
      });
    }
  }

  Future<_PatientRecordsBundle> _loadBundle(
    String patientId,
  ) async {
    final records = await _service.loadMedicalRecords(
      patientId: patientId,
      newestFirst: _showNewestFirst,
    );

    final legacyConditions = await _service.loadLegacyMedicalConditions(
      patientId,
    );

    final immunizations = <_ClinicalTag>[];

    final riskFactors = <_ClinicalTag>[];

    final generalRecords = <Map<String, dynamic>>[];

    for (final record in records) {
      final type = _normalise(
        record['record_type'],
      );

      if (type == 'immunization' ||
          type == 'immunisation' ||
          type == 'vaccine') {
        immunizations.add(
          _ClinicalTag.fromRecord(
            record,
          ),
        );

        continue;
      }

      if (type == 'risk_factor' || type == 'riskfactor') {
        riskFactors.add(
          _ClinicalTag.fromRecord(
            record,
          ),
        );

        continue;
      }

      generalRecords.add(
        record,
      );
    }

    final existingRiskLabels = riskFactors
        .map(
          (
            item,
          ) =>
              item.label.toLowerCase(),
        )
        .toSet();

    for (final condition in legacyConditions) {
      if (existingRiskLabels.contains(
        condition.toLowerCase(),
      )) {
        continue;
      }

      riskFactors.add(
        _ClinicalTag(
          id: null,
          label: condition,
          description: 'Existing medical condition',
          doctorId: null,
          recordDate: null,
          legacy: true,
        ),
      );
    }

    return _PatientRecordsBundle(
      patientId: patientId,
      records: generalRecords,
      immunizations: immunizations,
      riskFactors: riskFactors,
    );
  }

  void _refresh() {
    final patientId = _selectedPatientId;

    if (patientId == null) {
      return;
    }

    setState(() {
      _future = _loadBundle(
        patientId,
      );
    });
  }

  void _showPatientDialog() {
    if (_patients.isEmpty) {
      _snack(
        'No patients found for your doctor account.',
      );

      return;
    }

    showDialog<void>(
      context: context,
      builder: (
        dialogContext,
      ) {
        return AlertDialog(
          title: const Text(
            'Select Patient',
          ),
          content: SizedBox(
            width: 480,
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: _patients.length,
              separatorBuilder: (
                _,
                __,
              ) =>
                  const Divider(),
              itemBuilder: (
                context,
                index,
              ) {
                final patient = _patients[index];

                return ListTile(
                  leading: const Icon(
                    Icons.person_outline,
                  ),
                  title: Text(
                    patient.name,
                  ),
                  onTap: () {
                    Navigator.of(
                      dialogContext,
                    ).pop();

                    setState(() {
                      _selectedPatientId = patient.id;

                      _patientController.text = patient.name;

                      _future = _loadBundle(
                        patient.id,
                      );
                    });
                  },
                );
              },
            ),
          ),
        );
      },
    );
  }

  Future<void> _openAddRecord() async {
    final patientId = _selectedPatientId;

    if (patientId == null) {
      _snack(
        'Select a patient first.',
      );

      return;
    }

    await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => AddPatientRecord(
          patientId: patientId,
        ),
      ),
    );

    if (mounted) {
      _refresh();
    }
  }

  Future<void> _addRiskFactor() async {
    await _addClinicalTag(
      recordType: 'risk_factor',
      title: 'Add Risk Factor',
      fieldLabel: 'Risk Factor',
      hint: 'Example: Smoking, hypertension, family history',
    );
  }

  Future<void> _addImmunization() async {
    await _addClinicalTag(
      recordType: 'immunization',
      title: 'Add Immunisation',
      fieldLabel: 'Immunisation',
      hint: 'Example: Influenza vaccine 2026',
    );
  }

  Future<void> _addClinicalTag({
    required String recordType,
    required String title,
    required String fieldLabel,
    required String hint,
  }) async {
    final patientId = _selectedPatientId;

    final doctorContext = _doctorContext;

    if (patientId == null || doctorContext == null) {
      _snack(
        'Select a patient first.',
      );

      return;
    }

    final nameController = TextEditingController();

    final notesController = TextEditingController();

    final result = await showDialog<_ClinicalTagDialogResult>(
      context: context,
      builder: (
        dialogContext,
      ) {
        return AlertDialog(
          title: Text(
            title,
          ),
          content: SizedBox(
            width: 500,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: fieldLabel,
                    hintText: hint,
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(
                  height: 12,
                ),
                TextField(
                  controller: notesController,
                  minLines: 2,
                  maxLines: 5,
                  decoration: const InputDecoration(
                    labelText: 'Clinical Notes',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(
                  dialogContext,
                ).pop();
              },
              child: const Text(
                'Cancel',
              ),
            ),
            FilledButton(
              onPressed: () {
                final label = nameController.text.trim();

                if (label.isEmpty) {
                  return;
                }

                Navigator.of(
                  dialogContext,
                ).pop(
                  _ClinicalTagDialogResult(
                    label: label,
                    notes: notesController.text.trim(),
                  ),
                );
              },
              child: const Text(
                'Save',
              ),
            ),
          ],
        );
      },
    );

    nameController.dispose();
    notesController.dispose();

    if (result == null) {
      return;
    }

    try {
      await _service.saveMedicalRecord(
        context: doctorContext,
        patientId: patientId,
        recordType: recordType,
        title: result.label,
        description: result.notes,
      );

      _snack(
        '$fieldLabel saved.',
      );

      _refresh();
    } catch (error) {
      _snack(
        'Could not save $fieldLabel. '
        '${_clean(error)}',
      );
    }
  }

  Future<void> _editClinicalTag(
    _ClinicalTag item,
  ) async {
    final doctorContext = _doctorContext;

    if (item.legacy || item.id == null || doctorContext == null) {
      return;
    }

    if (item.doctorId != doctorContext.doctorId) {
      _snack(
        'You can only edit clinical entries you created.',
      );

      return;
    }

    final labelController = TextEditingController(
      text: item.label,
    );

    final notesController = TextEditingController(
      text: item.description,
    );

    final result = await showDialog<_ClinicalTagDialogResult>(
      context: context,
      builder: (
        dialogContext,
      ) {
        return AlertDialog(
          title: const Text(
            'Edit Clinical Entry',
          ),
          content: SizedBox(
            width: 500,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: labelController,
                  decoration: const InputDecoration(
                    labelText: 'Clinical Entry',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(
                  height: 12,
                ),
                TextField(
                  controller: notesController,
                  minLines: 2,
                  maxLines: 5,
                  decoration: const InputDecoration(
                    labelText: 'Notes',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(
                  dialogContext,
                ).pop();
              },
              child: const Text(
                'Cancel',
              ),
            ),
            FilledButton(
              onPressed: () {
                final label = labelController.text.trim();

                if (label.isEmpty) {
                  return;
                }

                Navigator.of(
                  dialogContext,
                ).pop(
                  _ClinicalTagDialogResult(
                    label: label,
                    notes: notesController.text.trim(),
                  ),
                );
              },
              child: const Text(
                'Save Changes',
              ),
            ),
          ],
        );
      },
    );

    labelController.dispose();
    notesController.dispose();

    if (result == null) {
      return;
    }

    try {
      await _service.updateMedicalRecord(
        context: doctorContext,
        recordId: item.id!,
        title: result.label,
        description: result.notes,
      );

      _snack(
        'Clinical entry updated.',
      );

      _refresh();
    } catch (error) {
      _snack(
        'Could not update clinical entry. '
        '${_clean(error)}',
      );
    }
  }

  String _normalise(
    dynamic value,
  ) {
    return value
            ?.toString()
            .trim()
            .toLowerCase()
            .replaceAll(
              '-',
              '_',
            )
            .replaceAll(
              ' ',
              '_',
            ) ??
        '';
  }

  String _clean(
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

  void _snack(
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
          'Patient Records',
        ),
        actions: [
          IconButton(
            icon: Icon(
              _showNewestFirst ? Icons.arrow_downward : Icons.arrow_upward,
            ),
            tooltip: _showNewestFirst ? 'Newest first' : 'Oldest first',
            onPressed: () {
              setState(() {
                _showNewestFirst = !_showNewestFirst;

                _refresh();
              });
            },
          ),
        ],
      ),
      floatingActionButton: _selectedPatientId == null
          ? null
          : SpeedDial(
              backgroundColor: CorviaColors.accent,
              foregroundColor: Colors.white,
              icon: Icons.add,
              activeIcon: Icons.close,
              children: [
                SpeedDialChild(
                  child: const Icon(
                    Icons.note_add,
                  ),
                  label: 'Add Record',
                  onTap: _openAddRecord,
                ),
                SpeedDialChild(
                  child: const Icon(
                    Icons.warning_amber,
                  ),
                  label: 'Add Risk Factor',
                  onTap: _addRiskFactor,
                ),
                SpeedDialChild(
                  child: const Icon(
                    Icons.vaccines,
                  ),
                  label: 'Add Immunisation',
                  onTap: _addImmunization,
                ),
              ],
            ),
      body: _loadingPatients
          ? StatusView.loading(
              message: 'Loading doctor patients...',
            )
          : _patientLoadError != null
              ? StatusView.error(
                  friendlyMessage:
                      "We couldn't load the doctor's patient records.",
                  error: _patientLoadError,
                  onRetry: _loadPage,
                )
              : Column(
                  children: [
                    const SizedBox(
                      height: 16,
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                      ),
                      child: TextFormField(
                        controller: _patientController,
                        readOnly: true,
                        decoration: const InputDecoration(
                          labelText: 'Patient',
                          prefixIcon: Icon(
                            Icons.person_search,
                          ),
                          suffixIcon: Icon(
                            Icons.arrow_drop_down,
                          ),
                          border: OutlineInputBorder(),
                        ),
                        onTap: _showPatientDialog,
                      ),
                    ),
                    const SizedBox(
                      height: 8,
                    ),
                    Expanded(
                      child: RefreshIndicator(
                        onRefresh: () async {
                          _refresh();
                        },
                        child: _future == null
                            ? StatusView.empty(
                                icon: Icons.person_search,
                                title: 'Select a patient',
                                subtitle:
                                    'Choose one of your patients to view clinical records.',
                              )
                            : FutureBuilder<_PatientRecordsBundle>(
                                future: _future,
                                builder: (
                                  context,
                                  snapshot,
                                ) {
                                  if (snapshot.connectionState !=
                                      ConnectionState.done) {
                                    return StatusView.loading(
                                      message: 'Loading patient records...',
                                    );
                                  }

                                  if (snapshot.hasError) {
                                    return StatusView.error(
                                      friendlyMessage:
                                          "We couldn't load the patient records.",
                                      error: snapshot.error,
                                      stackTrace: snapshot.stackTrace,
                                      onRetry: _refresh,
                                    );
                                  }

                                  final bundle = snapshot.data!;

                                  return ListView(
                                    physics:
                                        const AlwaysScrollableScrollPhysics(),
                                    padding: const EdgeInsets.only(
                                      bottom: 90,
                                    ),
                                    children: [
                                      _SectionHeader(
                                        title: 'Immunisations',
                                        actionLabel: 'Add',
                                        onAction: _addImmunization,
                                      ),
                                      _ClinicalTagCard(
                                        items: bundle.immunizations,
                                        emptyIcon: Icons.vaccines,
                                        emptyMessage:
                                            'No immunisations recorded yet.',
                                        accent: CorviaColors.success,
                                        currentDoctorId:
                                            _doctorContext?.doctorId,
                                        onEdit: _editClinicalTag,
                                      ),
                                      _SectionHeader(
                                        title: 'Risk Factors',
                                        actionLabel: 'Add',
                                        onAction: _addRiskFactor,
                                      ),
                                      _ClinicalTagCard(
                                        items: bundle.riskFactors,
                                        emptyIcon: Icons.warning_amber,
                                        emptyMessage:
                                            'No risk factors recorded yet.',
                                        accent: CorviaColors.warning,
                                        currentDoctorId:
                                            _doctorContext?.doctorId,
                                        onEdit: _editClinicalTag,
                                      ),
                                      const _SectionHeader(
                                        title: 'Medical Records',
                                      ),
                                      _RecordsCard(
                                        items: bundle.records,
                                      ),
                                    ],
                                  );
                                },
                              ),
                      ),
                    ),
                  ],
                ),
    );
  }
}

class _PatientRecordsBundle {
  const _PatientRecordsBundle({
    required this.patientId,
    required this.records,
    required this.immunizations,
    required this.riskFactors,
  });

  final String patientId;

  final List<Map<String, dynamic>> records;

  final List<_ClinicalTag> immunizations;

  final List<_ClinicalTag> riskFactors;
}

class _ClinicalTag {
  const _ClinicalTag({
    required this.id,
    required this.label,
    required this.description,
    required this.doctorId,
    required this.recordDate,
    required this.legacy,
  });

  final String? id;

  final String label;
  final String description;

  final String? doctorId;

  final DateTime? recordDate;

  final bool legacy;

  factory _ClinicalTag.fromRecord(
    Map<String, dynamic> record,
  ) {
    return _ClinicalTag(
      id: record['id']?.toString(),
      label: record['title']?.toString().trim().isNotEmpty == true
          ? record['title'].toString().trim()
          : 'Clinical entry',
      description: record['description']?.toString() ?? '',
      doctorId: record['doctor_id']?.toString(),
      recordDate: DateTime.tryParse(
        record['record_date']?.toString() ?? '',
      ),
      legacy: false,
    );
  }
}

class _ClinicalTagDialogResult {
  const _ClinicalTagDialogResult({
    required this.label,
    required this.notes,
  });

  final String label;
  final String notes;
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(
    BuildContext context,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        16,
        18,
        16,
        8,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: CorviaTextStyles.heading,
            ),
          ),
          if (actionLabel != null && onAction != null)
            TextButton.icon(
              onPressed: onAction,
              icon: const Icon(
                Icons.add,
                size: 17,
              ),
              label: Text(
                actionLabel!,
              ),
            ),
        ],
      ),
    );
  }
}

class _ClinicalTagCard extends StatelessWidget {
  const _ClinicalTagCard({
    required this.items,
    required this.emptyIcon,
    required this.emptyMessage,
    required this.accent,
    required this.currentDoctorId,
    required this.onEdit,
  });

  final List<_ClinicalTag> items;

  final IconData emptyIcon;
  final String emptyMessage;
  final Color accent;

  final String? currentDoctorId;

  final void Function(
    _ClinicalTag item,
  ) onEdit;

  @override
  Widget build(
    BuildContext context,
  ) {
    if (items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: 16,
        ),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(
              16,
            ),
            child: InlineStatus(
              icon: emptyIcon,
              message: emptyMessage,
            ),
          ),
        ),
      );
    }

    return Card(
      margin: const EdgeInsets.symmetric(
        horizontal: 16,
      ),
      child: Column(
        children: items.map(
          (
            item,
          ) {
            final canEdit = !item.legacy &&
                item.id != null &&
                currentDoctorId != null &&
                item.doctorId == currentDoctorId;

            return ListTile(
              leading: Icon(
                emptyIcon,
                color: accent,
              ),
              title: Text(
                item.label,
                style: TextStyle(
                  color: context.cTextPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (item.description.trim().isNotEmpty)
                    Text(
                      item.description,
                      style: TextStyle(
                        color: context.cTextSecondary,
                        fontSize: 12,
                      ),
                    ),
                  if (item.legacy)
                    Text(
                      'Existing patient medical condition',
                      style: TextStyle(
                        color: context.cTextMuted,
                        fontSize: 10,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                ],
              ),
              trailing: canEdit
                  ? IconButton(
                      tooltip: 'Edit',
                      onPressed: () {
                        onEdit(
                          item,
                        );
                      },
                      icon: const Icon(
                        Icons.edit_outlined,
                      ),
                    )
                  : null,
            );
          },
        ).toList(),
      ),
    );
  }
}

class _RecordsCard extends StatelessWidget {
  const _RecordsCard({
    required this.items,
  });

  final List<Map<String, dynamic>> items;

  @override
  Widget build(
    BuildContext context,
  ) {
    final formatter = DateFormat(
      'd MMM yyyy',
    );

    if (items.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(
          horizontal: 16,
        ),
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(
              16,
            ),
            child: InlineStatus(
              icon: Icons.folder_open,
              message: 'No general medical records yet.',
            ),
          ),
        ),
      );
    }

    return Card(
      margin: const EdgeInsets.symmetric(
        horizontal: 16,
      ),
      child: Column(
        children: items.map(
          (
            record,
          ) {
            final date = DateTime.tryParse(
              record['record_date']?.toString() ?? '',
            )?.toLocal();

            return ExpansionTile(
              leading: Icon(
                Icons.description,
                color: CorviaColors.accentLight,
              ),
              title: Text(
                record['title']?.toString() ?? 'Record',
                style: TextStyle(
                  color: context.cTextPrimary,
                  fontWeight: FontWeight.bold,
                ),
              ),
              subtitle: Text(
                [
                  if ((record['record_type']?.toString() ?? '').isNotEmpty)
                    record['record_type'].toString().replaceAll(
                          '_',
                          ' ',
                        ),
                  if (date != null)
                    formatter.format(
                      date,
                    ),
                ].join(
                  ' • ',
                ),
                style: TextStyle(
                  color: context.cTextSecondary,
                ),
              ),
              children: [
                if ((record['description']?.toString() ?? '').trim().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      16,
                      0,
                      16,
                      14,
                    ),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        record['description'].toString(),
                        style: TextStyle(
                          color: context.cTextSecondary,
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ).toList(),
      ),
    );
  }
}

extension _FirstOrNullExtension<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;

    if (!iterator.moveNext()) {
      return null;
    }

    return iterator.current;
  }
}
