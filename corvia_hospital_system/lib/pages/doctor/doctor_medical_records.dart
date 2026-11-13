import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../services/doctor_clinical_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/status_view.dart';

import 'doctor_add_patient_record.dart';

class DoctorMedicalRecordsPage extends StatefulWidget {
  const DoctorMedicalRecordsPage({
    super.key,
  });

  @override
  State<DoctorMedicalRecordsPage> createState() {
    return _DoctorMedicalRecordsPageState();
  }
}

class _DoctorMedicalRecordsPageState extends State<DoctorMedicalRecordsPage> {
  final DoctorClinicalService _service = DoctorClinicalService();

  bool _loading = true;
  bool _loadingRecords = false;

  String? _error;
  String? _recordsError;

  List<DoctorClinicalPatient> _patients = [];

  List<Map<String, dynamic>> _records = [];

  String? _selectedPatientId;

  @override
  void initState() {
    super.initState();

    _loadPage();
  }

  Future<void> _loadPage() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
        _recordsError = null;
      });
    }

    try {
      final doctorContext = await _service.currentContext();

      final patients = await _service.loadDoctorPatients(
        doctorContext,
      );

      String? selectedPatientId = _selectedPatientId;

      if (selectedPatientId == null ||
          !patients.any(
            (
              patient,
            ) =>
                patient.id == selectedPatientId,
          )) {
        selectedPatientId = patients.isEmpty ? null : patients.first.id;
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _patients = patients;

        _selectedPatientId = selectedPatientId;

        _loading = false;
      });

      if (selectedPatientId != null) {
        await _loadPatientRecords(
          selectedPatientId,
        );
      }
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _loading = false;

        _error = _clean(
          error,
        );
      });
    }
  }

  Future<void> _loadPatientRecords(
    String patientId,
  ) async {
    if (mounted) {
      setState(() {
        _loadingRecords = true;
        _recordsError = null;
      });
    }

    try {
      final records = await _service.loadMedicalRecords(
        patientId: patientId,
        newestFirst: true,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _records = records;

        _loadingRecords = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _loadingRecords = false;

        _recordsError = _clean(
          error,
        );
      });
    }
  }

  DoctorClinicalPatient? get _selectedPatient {
    final id = _selectedPatientId;

    if (id == null) {
      return null;
    }

    for (final patient in _patients) {
      if (patient.id == id) {
        return patient;
      }
    }

    return null;
  }

  Future<void> _openAddRecord() async {
    final patient = _selectedPatient;

    if (patient == null) {
      _snack(
        'Select a patient first.',
      );

      return;
    }

    await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => AddPatientRecord(
          patientId: patient.id,
        ),
      ),
    );

    if (!mounted) {
      return;
    }

    await _loadPatientRecords(
      patient.id,
    );
  }

  String _prettyType(
    dynamic value,
  ) {
    final text = value
            ?.toString()
            .replaceAll(
              '_',
              ' ',
            )
            .trim() ??
        '';

    if (text.isEmpty) {
      return 'Medical Record';
    }

    return text
        .split(
          RegExp(
            r'\s+',
          ),
        )
        .map(
          (
            word,
          ) =>
              word.isEmpty
                  ? ''
                  : '${word[0].toUpperCase()}'
                      '${word.substring(1)}',
        )
        .join(
          ' ',
        );
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
    final selectedPatient = _selectedPatient;

    return Scaffold(
      backgroundColor: context.cBgPrimary,
      appBar: AppBar(
        title: const Text(
          'Medical Records',
        ),
        actions: [
          IconButton(
            onPressed: _loading ? null : _loadPage,
            icon: const Icon(
              Icons.refresh,
            ),
            tooltip: 'Refresh',
          ),
        ],
      ),
      floatingActionButton: selectedPatient == null
          ? null
          : FloatingActionButton.extended(
              onPressed: _openAddRecord,
              backgroundColor: CorviaColors.accent,
              icon: const Icon(
                Icons.add,
              ),
              label: const Text(
                'Add Record',
              ),
            ),
      body: _loading
          ? StatusView.loading(
              message: 'Loading doctor medical records...',
            )
          : _error != null
              ? StatusView.error(
                  friendlyMessage: "We couldn't load doctor records.",
                  error: _error,
                  onRetry: _loadPage,
                )
              : _patients.isEmpty
                  ? StatusView.empty(
                      icon: Icons.people_outline,
                      title: 'No patients available',
                      subtitle:
                          'Patients linked to this doctor through appointments, prescriptions or labs will appear here.',
                      onRetry: _loadPage,
                    )
                  : RefreshIndicator(
                      onRefresh: _loadPage,
                      child: ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.all(
                          16,
                        ),
                        children: [
                          Text(
                            'Patient Medical Records',
                            style: TextStyle(
                              color: context.cTextPrimary,
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(
                            height: 6,
                          ),
                          Text(
                            'Select a doctor-linked patient and manage their clinical record.',
                            style: TextStyle(
                              color: context.cTextSecondary,
                            ),
                          ),
                          const SizedBox(
                            height: 20,
                          ),
                          DropdownButtonFormField<String>(
                            initialValue: _selectedPatientId,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'Select Patient',
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
                            onChanged: (
                              patientId,
                            ) async {
                              if (patientId == null) {
                                return;
                              }

                              setState(() {
                                _selectedPatientId = patientId;

                                _records = [];

                                _recordsError = null;
                              });

                              await _loadPatientRecords(
                                patientId,
                              );
                            },
                          ),
                          if (selectedPatient != null) ...[
                            const SizedBox(
                              height: 18,
                            ),
                            _patientSummary(
                              selectedPatient,
                            ),
                            const SizedBox(
                              height: 22,
                            ),
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    'Medical History',
                                    style: TextStyle(
                                      color: context.cTextPrimary,
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                OutlinedButton.icon(
                                  onPressed: _openAddRecord,
                                  icon: const Icon(
                                    Icons.add,
                                  ),
                                  label: const Text(
                                    'Add',
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(
                              height: 10,
                            ),
                            if (_loadingRecords)
                              const Padding(
                                padding: EdgeInsets.all(
                                  30,
                                ),
                                child: Center(
                                  child: CircularProgressIndicator(),
                                ),
                              )
                            else if (_recordsError != null)
                              _inlineError()
                            else if (_records.isEmpty)
                              _emptyRecords()
                            else
                              ..._records.map(
                                _recordCard,
                              ),
                            const SizedBox(
                              height: 90,
                            ),
                          ],
                        ],
                      ),
                    ),
    );
  }

  Widget _patientSummary(
    DoctorClinicalPatient patient,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(
          16,
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 24,
              backgroundColor: CorviaColors.accent.withValues(
                alpha: 0.16,
              ),
              child: Icon(
                Icons.person,
                color: CorviaColors.accentLight,
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
                    patient.name,
                    style: TextStyle(
                      color: context.cTextPrimary,
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(
                    height: 4,
                  ),
                  Text(
                    'Doctor-linked patient',
                    style: TextStyle(
                      color: context.cTextSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.verified_outlined,
              color: CorviaColors.success,
            ),
          ],
        ),
      ),
    );
  }

  Widget _recordCard(
    Map<String, dynamic> record,
  ) {
    final date = DateTime.tryParse(
      record['record_date']?.toString() ?? '',
    )?.toLocal();

    final dateLabel = date == null
        ? 'No date recorded'
        : DateFormat(
            'd MMMM yyyy',
          ).format(
            date,
          );

    final type = _prettyType(
      record['record_type'],
    );

    return Padding(
      padding: const EdgeInsets.only(
        bottom: 12,
      ),
      child: Card(
        child: ExpansionTile(
          leading: Icon(
            _iconForType(
              type,
            ),
            color: CorviaColors.accentLight,
          ),
          title: Text(
            record['title']?.toString() ?? 'Untitled Record',
            style: TextStyle(
              color: context.cTextPrimary,
              fontWeight: FontWeight.bold,
            ),
          ),
          subtitle: Text(
            '$type • $dateLabel',
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
                  16,
                ),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    record['description'].toString(),
                    style: TextStyle(
                      color: context.cTextSecondary,
                      height: 1.4,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  IconData _iconForType(
    String value,
  ) {
    final type = value.toLowerCase();

    if (type.contains(
          'immun',
        ) ||
        type.contains(
          'vaccine',
        )) {
      return Icons.vaccines;
    }

    if (type.contains(
      'risk',
    )) {
      return Icons.warning_amber;
    }

    if (type.contains(
      'lab',
    )) {
      return Icons.biotech_outlined;
    }

    if (type.contains(
      'treatment',
    )) {
      return Icons.health_and_safety_outlined;
    }

    if (type.contains(
      'prescription',
    )) {
      return Icons.medication_outlined;
    }

    return Icons.description_outlined;
  }

  Widget _emptyRecords() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(
          24,
        ),
        child: Column(
          children: [
            Icon(
              Icons.folder_open_outlined,
              size: 42,
              color: CorviaColors.accentLight,
            ),
            const SizedBox(
              height: 10,
            ),
            Text(
              'No medical records yet',
              style: TextStyle(
                color: context.cTextPrimary,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(
              height: 5,
            ),
            Text(
              'Use Add Record to create the first clinical record.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: context.cTextSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _inlineError() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(
          18,
        ),
        child: Column(
          children: [
            Icon(
              Icons.error_outline,
              color: CorviaColors.danger,
              size: 36,
            ),
            const SizedBox(
              height: 10,
            ),
            Text(
              _recordsError!,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: context.cTextSecondary,
              ),
            ),
            const SizedBox(
              height: 12,
            ),
            OutlinedButton(
              onPressed: () {
                final patientId = _selectedPatientId;

                if (patientId != null) {
                  _loadPatientRecords(
                    patientId,
                  );
                }
              },
              child: const Text(
                'Retry',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
