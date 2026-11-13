import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/doctor_clinical_service.dart';
import '../../theme/app_theme.dart';
import 'patient_pharmacy_status_page.dart';

class DoctorPatientTimelinePage extends StatefulWidget {
  const DoctorPatientTimelinePage({
    super.key,
    this.patientId,
  });

  /// When supplied, the timeline is opened by a doctor for this patient.
  /// When omitted, the signed-in patient's own timeline is loaded.
  final String? patientId;

  @override
  State<DoctorPatientTimelinePage> createState() =>
      _DoctorPatientTimelinePageState();
}

class _DoctorPatientTimelinePageState extends State<DoctorPatientTimelinePage> {
  final SupabaseClient _supabase = Supabase.instance.client;

  final TextEditingController _searchController = TextEditingController();

  bool _loading = true;

  String? _error;

  String _selectedFilter = 'All';

  List<_TimelineItem> _items = [];

  Map<String, _DispenseDetails> _dispenseDetails = {};

  static const List<String> _filters = [
    'All',
    'Pharmacy',
    'Prescriptions',
    'Appointments',
    'Lab',
    'Clinical',
  ];

  @override
  void initState() {
    super.initState();

    _loadTimeline();
  }

  @override
  void dispose() {
    _searchController.dispose();

    super.dispose();
  }

  Future<void> _loadTimeline() async {
    if (!mounted) {
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final user = _supabase.auth.currentUser;

      if (user == null) {
        throw Exception(
          'No active Corvia session was found.',
        );
      }

      final requestedPatientId = _cleanId(
        widget.patientId,
      );

      late final String patientId;

      if (requestedPatientId != null) {
        final clinicalService = DoctorClinicalService(
          client: _supabase,
        );
        final doctorContext = await clinicalService.currentContext();
        final linkedPatients = await clinicalService.loadDoctorPatients(
          doctorContext,
        );

        if (!linkedPatients.any(
          (patient) => patient.id == requestedPatientId,
        )) {
          throw Exception(
            'This patient is not linked to the signed-in doctor.',
          );
        }

        patientId = requestedPatientId;
      } else {
        final patientResponse = await _supabase
            .from('patients')
            .select('id, profile_id, is_active')
            .eq('profile_id', user.id)
            .maybeSingle();

        if (patientResponse == null) {
          throw Exception(
            'No patient record is linked to this account.',
          );
        }

        if (patientResponse['is_active'] == false) {
          throw Exception(
            'This patient record is inactive.',
          );
        }

        final ownPatientId = _cleanId(
          patientResponse['id'],
        );

        if (ownPatientId == null) {
          throw Exception(
            'The linked patient record has no valid ID.',
          );
        }

        patientId = ownPatientId;
      }

      var timelineRows = <Map<String, dynamic>>[];

      try {
        final timelineResponse = await _supabase
            .from('patient_timeline_items')
            .select(
              'id, patient_id, created_by, item_type, title, '
              'description, source, source_id, severity, '
              'doctor_visible, patient_visible, created_at, updated_at',
            )
            .eq('patient_id', patientId)
            .order(
              'created_at',
              ascending: false,
            )
            .limit(300);

        timelineRows = _rows(
          timelineResponse,
        ).where(
          (row) {
            if (requestedPatientId != null) {
              return row['doctor_visible'] != false;
            }

            return row['patient_visible'] != false;
          },
        ).toList();
      } catch (error) {
        debugPrint(
          'Stored patient timeline lookup failed: $error',
        );
      }

      final loadedItems = timelineRows
          .map(
            _TimelineItem.fromMap,
          )
          .toList();

      final sourceItems = await _loadSourceTimeline(
        patientId,
        isOwnPatient: requestedPatientId == null,
      );
      final existingSourceKeys = loadedItems
          .map(
            _timelineSourceKey,
          )
          .whereType<String>()
          .toSet();

      for (final sourceItem in sourceItems) {
        final sourceKey = _timelineSourceKey(
          sourceItem,
        );

        if (sourceKey == null || existingSourceKeys.add(sourceKey)) {
          loadedItems.add(
            sourceItem,
          );
        }
      }

      loadedItems.sort(
        (first, second) {
          final firstDate = first.createdAt ?? DateTime(1970);

          final secondDate = second.createdAt ?? DateTime(1970);

          return secondDate.compareTo(firstDate);
        },
      );

      final dispenseDetails = await _loadDispenseDetails(
        loadedItems,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _items = loadedItems;
        _dispenseDetails = dispenseDetails;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _loading = false;
        _error = _cleanError(error);
      });
    }
  }

  Future<List<_TimelineItem>> _loadSourceTimeline(
    String patientId, {
    required bool isOwnPatient,
  }) async {
    final items = <_TimelineItem>[];

    try {
      final response = await _supabase
          .from('appointments')
          .select(
            'id, patient_id, reason, status, type, appointment_type, '
            'appointment_date, scheduled_for, completed_at, created_at',
          )
          .eq('patient_id', patientId);

      for (final row in _rows(response)) {
        final id = _cleanId(row['id']);

        if (id == null) {
          continue;
        }

        final status = _cleanText(
          row['status'],
          fallback: 'scheduled',
        );
        final type = _cleanText(
          row['appointment_type'] ?? row['type'],
          fallback: 'in-person',
        );
        final reason = _cleanText(
          row['reason'],
          fallback: 'Consultation',
        );

        items.add(
          _TimelineItem.fromMap({
            'id': 'appointment:$id',
            'patient_id': patientId,
            'item_type': 'appointment',
            'title': 'Appointment: $reason',
            'description': '${_TimelineItem._pretty(status)} · '
                '${_TimelineItem._pretty(type)}',
            'source': 'appointment',
            'source_id': id,
            'severity': 'normal',
            'doctor_visible': true,
            'patient_visible': true,
            'created_at': row['completed_at'] ??
                row['appointment_date'] ??
                row['scheduled_for'] ??
                row['created_at'],
          }),
        );
      }
    } catch (error) {
      debugPrint('Timeline appointment lookup failed: $error');
    }

    try {
      final response = await _supabase
          .from('prescriptions')
          .select(
            'id, patient_id, medication_name, dosage, frequency, status, '
            'issued_at, created_at',
          )
          .eq('patient_id', patientId);

      for (final row in _rows(response)) {
        final id = _cleanId(row['id']);

        if (id == null) {
          continue;
        }

        final medication = _cleanText(
          row['medication_name'],
          fallback: 'Medication',
        );
        final dosage = _cleanText(row['dosage']);
        final frequency = _cleanText(row['frequency']);
        final status = _cleanText(
          row['status'],
          fallback: 'active',
        );
        final details = [
          if (dosage.isNotEmpty) dosage,
          if (frequency.isNotEmpty) frequency,
          _TimelineItem._pretty(status),
        ];

        items.add(
          _TimelineItem.fromMap({
            'id': 'prescription:$id',
            'patient_id': patientId,
            'item_type': 'prescription',
            'title': 'Prescription: $medication',
            'description': details.join(' · '),
            'source': 'prescription',
            'source_id': id,
            'severity': 'normal',
            'doctor_visible': true,
            'patient_visible': true,
            'created_at': row['issued_at'] ?? row['created_at'],
          }),
        );
      }
    } catch (error) {
      debugPrint('Timeline prescription lookup failed: $error');
    }

    try {
      final response = isOwnPatient
          ? await _supabase.rpc('corvia_patient_lab_order_timeline')
          : await _supabase
              .from('lab_results')
              .select(
                'id, patient_id, test_name, result, status, created_at',
              )
              .eq('patient_id', patientId);

      for (final row in _rows(response)) {
        final id = _cleanId(row['id']);

        if (id == null) {
          continue;
        }

        final testName = _cleanText(
          row['test_name'],
          fallback: 'Laboratory test',
        );
        final result = _cleanText(row['result']);
        final status = _cleanText(
          row['status'],
          fallback: 'pending',
        );

        items.add(
          _TimelineItem.fromMap({
            'id': 'lab_result:$id',
            'patient_id': patientId,
            'item_type': 'lab_result',
            'title': testName,
            'description': result.isEmpty
                ? _TimelineItem._pretty(status)
                : '$result · ${_TimelineItem._pretty(status)}',
            'source': 'lab_result',
            'source_id': id,
            'severity': 'normal',
            'doctor_visible': true,
            'patient_visible': true,
            'created_at': row['created_at'],
          }),
        );
      }
    } catch (error) {
      debugPrint('Timeline lab-result lookup failed: $error');
    }

    try {
      final response = await _supabase
          .from('reception_checkins')
          .select(
            'id, patient_id, reason, urgency, is_walk_in, status, '
            'checkin_status, queue_status, checkin_time, checked_in_at, '
            'with_doctor_at, completed_at, created_at',
          )
          .eq('patient_id', patientId);

      for (final row in _rows(response)) {
        final id = _cleanId(row['id']);

        if (id == null) {
          continue;
        }

        final status = _cleanText(
          row['queue_status'] ?? row['checkin_status'] ?? row['status'],
          fallback: 'waiting',
        );
        final reason = _cleanText(
          row['reason'],
          fallback: 'Reception consultation',
        );
        final isWalkIn = row['is_walk_in'] == true;

        items.add(
          _TimelineItem.fromMap({
            'id': 'reception_checkin:$id',
            'patient_id': patientId,
            'item_type': isWalkIn ? 'walk_in' : 'reception_check_in',
            'title': isWalkIn ? 'Walk-in: $reason' : 'Check-in: $reason',
            'description': _TimelineItem._pretty(status),
            'source': 'reception_checkin',
            'source_id': id,
            'severity': _cleanText(
              row['urgency'],
              fallback: 'normal',
            ),
            'doctor_visible': true,
            'patient_visible': true,
            'created_at': row['completed_at'] ??
                row['with_doctor_at'] ??
                row['checked_in_at'] ??
                row['checkin_time'] ??
                row['created_at'],
          }),
        );
      }
    } catch (error) {
      debugPrint('Timeline reception check-in lookup failed: $error');
    }

    try {
      final response = await _supabase
          .from('prescription_dispenses')
          .select(
            'id, patient_id, status, received_at, verified_at, preparing_at, '
            'ready_at, collected_at, cancelled_at, updated_at, created_at',
          )
          .eq('patient_id', patientId);

      for (final row in _rows(response)) {
        final id = _cleanId(row['id']);

        if (id == null) {
          continue;
        }

        final status = _cleanText(
          row['status'],
          fallback: 'received',
        );

        items.add(
          _TimelineItem.fromMap({
            'id': 'prescription_dispense:$id',
            'patient_id': patientId,
            'item_type': 'medication_collection',
            'title': 'Pharmacy: ${_TimelineItem._pretty(status)}',
            'description': 'Prescription dispensing status updated.',
            'source': 'prescription_dispense',
            'source_id': id,
            'severity': 'normal',
            'doctor_visible': true,
            'patient_visible': true,
            'created_at': row['collected_at'] ??
                row['ready_at'] ??
                row['preparing_at'] ??
                row['verified_at'] ??
                row['cancelled_at'] ??
                row['updated_at'] ??
                row['received_at'] ??
                row['created_at'],
          }),
        );
      }
    } catch (error) {
      debugPrint('Timeline pharmacy lookup failed: $error');
    }

    return items;
  }

  String? _timelineSourceKey(
    _TimelineItem item,
  ) {
    final sourceId = item.sourceId?.trim();

    if (sourceId == null || sourceId.isEmpty) {
      return null;
    }

    final normalizedSource = item.source
        .trim()
        .toLowerCase()
        .replaceAll('-', '_')
        .replaceAll(' ', '_');

    if (normalizedSource.contains('dispense') ||
        normalizedSource.contains('pharmacy')) {
      return 'prescription_dispense:$sourceId';
    }

    if (normalizedSource.contains('prescription') ||
        normalizedSource.contains('medication')) {
      return 'prescription:$sourceId';
    }

    if (normalizedSource.contains('appointment') ||
        normalizedSource.contains('consultation')) {
      return 'appointment:$sourceId';
    }

    if (normalizedSource.contains('lab') ||
        normalizedSource.contains('pathology')) {
      return 'lab_result:$sourceId';
    }

    if (normalizedSource.contains('reception') ||
        normalizedSource.contains('checkin') ||
        normalizedSource.contains('check_in') ||
        normalizedSource.contains('walk_in')) {
      return 'reception_checkin:$sourceId';
    }

    return '$normalizedSource:$sourceId';
  }

  String _cleanText(
    dynamic value, {
    String fallback = '',
  }) {
    final text = value?.toString().trim();

    if (text == null || text.isEmpty || text.toLowerCase() == 'null') {
      return fallback;
    }

    return text;
  }

  Future<Map<String, _DispenseDetails>> _loadDispenseDetails(
    List<_TimelineItem> items,
  ) async {
    final dispenseIds = items
        .where(
          (item) {
            return item.isPharmacy && item.sourceId != null;
          },
        )
        .map(
          (item) => item.sourceId!,
        )
        .toSet()
        .toList();

    if (dispenseIds.isEmpty) {
      return {};
    }

    try {
      final dispenseResponse =
          await _supabase.from('prescription_dispenses').select().inFilter(
                'id',
                dispenseIds,
              );

      final dispenseRows = _rows(
        dispenseResponse,
      );

      final prescriptionIds = dispenseRows
          .map(
            (row) => _cleanId(
              row['prescription_id'],
            ),
          )
          .whereType<String>()
          .toSet()
          .toList();

      final hospitalIds = dispenseRows
          .map(
            (row) => _cleanId(
              row['hospital_id'],
            ),
          )
          .whereType<String>()
          .toSet()
          .toList();

      final prescriptions = <String, Map<String, dynamic>>{};

      final hospitals = <String, Map<String, dynamic>>{};

      if (prescriptionIds.isNotEmpty) {
        try {
          final prescriptionResponse =
              await _supabase.from('prescriptions').select().inFilter(
                    'id',
                    prescriptionIds,
                  );

          for (final row in _rows(
            prescriptionResponse,
          )) {
            final id = _cleanId(
              row['id'],
            );

            if (id != null) {
              prescriptions[id] = row;
            }
          }
        } catch (error) {
          debugPrint(
            'Timeline prescription lookup failed: $error',
          );
        }
      }

      if (hospitalIds.isNotEmpty) {
        try {
          final hospitalResponse = await _supabase
              .from('hospitals')
              .select('id, name, address, phone')
              .inFilter(
                'id',
                hospitalIds,
              );

          for (final row in _rows(
            hospitalResponse,
          )) {
            final id = _cleanId(
              row['id'],
            );

            if (id != null) {
              hospitals[id] = row;
            }
          }
        } catch (error) {
          debugPrint(
            'Timeline hospital lookup failed: $error',
          );
        }
      }

      final results = <String, _DispenseDetails>{};

      for (final dispense in dispenseRows) {
        final dispenseId = _cleanId(
          dispense['id'],
        );

        if (dispenseId == null) {
          continue;
        }

        final prescriptionId = _cleanId(
          dispense['prescription_id'],
        );

        final hospitalId = _cleanId(
          dispense['hospital_id'],
        );

        results[dispenseId] = _DispenseDetails.fromMaps(
          dispense: dispense,
          prescription:
              prescriptionId == null ? null : prescriptions[prescriptionId],
          hospital: hospitalId == null ? null : hospitals[hospitalId],
        );
      }

      return results;
    } catch (error) {
      debugPrint(
        'Timeline pharmacy detail lookup failed: $error',
      );

      return {};
    }
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
          (row) => Map<String, dynamic>.from(row),
        )
        .toList();
  }

  String? _cleanId(dynamic value) {
    final text = value?.toString().trim();

    if (text == null || text.isEmpty || text.toLowerCase() == 'null') {
      return null;
    }

    return text;
  }

  String _cleanError(Object error) {
    if (error is PostgrestException) {
      final details = error.details?.toString().trim() ?? '';

      if (details.isNotEmpty &&
          details.toLowerCase() != 'null' &&
          details != error.message) {
        return '${error.message} $details';
      }

      return error.message;
    }

    return error.toString().replaceFirst(
          'Exception: ',
          '',
        );
  }

  List<_TimelineItem> get _visibleItems {
    final search = _searchController.text.trim().toLowerCase();

    return _items.where(
      (item) {
        bool matchesFilter;

        switch (_selectedFilter) {
          case 'Pharmacy':
            matchesFilter = item.isPharmacy;
            break;

          case 'Prescriptions':
            matchesFilter = item.isPrescription && !item.isPharmacy;
            break;

          case 'Appointments':
            matchesFilter = item.isAppointment;
            break;

          case 'Lab':
            matchesFilter = item.isLab;
            break;

          case 'Clinical':
            matchesFilter = !item.isPharmacy &&
                !item.isPrescription &&
                !item.isAppointment &&
                !item.isLab;
            break;

          case 'All':
          default:
            matchesFilter = true;
        }

        if (!matchesFilter) {
          return false;
        }

        if (search.isEmpty) {
          return true;
        }

        final dispense =
            item.sourceId == null ? null : _dispenseDetails[item.sourceId];

        final searchable = [
          item.title,
          item.description,
          item.itemType,
          item.source,
          item.severity,
          dispense?.medicineName ?? '',
          dispense?.hospitalName ?? '',
          dispense?.collectionReference ?? '',
          dispense?.statusLabel ?? '',
        ].join(' ').toLowerCase();

        return searchable.contains(search);
      },
    ).toList();
  }

  int get _pharmacyCount {
    return _items
        .where(
          (item) => item.isPharmacy,
        )
        .length;
  }

  int get _recentCount {
    final cutoff = DateTime.now().subtract(
      const Duration(days: 30),
    );

    return _items.where(
      (item) {
        final createdAt = item.createdAt;

        return createdAt != null && createdAt.isAfter(cutoff);
      },
    ).length;
  }

  Color _itemColor(
    _TimelineItem item,
    _DispenseDetails? dispense,
  ) {
    final severity = item.severity.toLowerCase();

    if (severity == 'critical' ||
        severity == 'emergency' ||
        severity == 'urgent' ||
        severity == 'high') {
      return CorviaColors.danger;
    }

    if (severity == 'warning' || severity == 'medium') {
      return CorviaColors.warning;
    }

    if (item.isPharmacy) {
      return _pharmacyStatusColor(
        dispense?.status ?? '',
      );
    }

    if (item.isLab) {
      return Colors.cyan.shade700;
    }

    if (item.isAppointment) {
      return Colors.blue.shade700;
    }

    if (item.isPrescription) {
      return Colors.deepPurple;
    }

    return context.cAccentReadable;
  }

  Color _pharmacyStatusColor(
    String status,
  ) {
    switch (status.toLowerCase()) {
      case 'received':
        return Colors.orange.shade800;

      case 'verified':
        return Colors.blue.shade700;

      case 'preparing':
        return Colors.deepPurple;

      case 'ready_for_collection':
        return Colors.green.shade700;

      case 'collected':
        return Colors.teal.shade700;

      case 'unable_to_dispense':
      case 'cancelled':
        return CorviaColors.danger;

      default:
        return Colors.teal.shade700;
    }
  }

  IconData _itemIcon(
    _TimelineItem item,
  ) {
    if (item.isPharmacy) {
      return Icons.local_pharmacy_outlined;
    }

    if (item.isPrescription) {
      return Icons.medication_outlined;
    }

    if (item.isLab) {
      return Icons.science_outlined;
    }

    if (item.isAppointment) {
      return Icons.calendar_month_outlined;
    }

    final normalized = [
      item.itemType,
      item.title,
      item.source,
    ].join(' ').toLowerCase();

    if (normalized.contains('symptom') || normalized.contains('intake')) {
      return Icons.psychology_outlined;
    }

    if (normalized.contains('vital') || normalized.contains('observation')) {
      return Icons.monitor_heart_outlined;
    }

    if (normalized.contains('doctor') || normalized.contains('note')) {
      return Icons.note_alt_outlined;
    }

    if (normalized.contains('emergency')) {
      return Icons.emergency_outlined;
    }

    return Icons.timeline_rounded;
  }

  String _formatDateTime(
    DateTime? value,
  ) {
    if (value == null) {
      return 'Date not recorded';
    }

    final local = value.toLocal();

    return '${local.day.toString().padLeft(2, '0')}/'
        '${local.month.toString().padLeft(2, '0')}/'
        '${local.year} • '
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }

  String _sourceLabel(String source) {
    final cleaned = source.trim().replaceAll('-', '_').replaceAll(' ', '_');

    if (cleaned.isEmpty) {
      return 'Corvia';
    }

    switch (cleaned.toLowerCase()) {
      case 'prescription_dispense':
        return 'Hospital Pharmacy';

      case 'prescription':
      case 'prescriptions':
        return 'Prescription';

      case 'appointment':
      case 'appointments':
        return 'Appointment';

      case 'lab_result':
      case 'lab_results':
        return 'Laboratory';

      case 'ai_symptom_intake':
      case 'ai_symptom_intakes':
        return 'AI Symptom Intake';

      case 'nurse_observation':
      case 'nurse_observations':
        return 'Nurse Observation';

      default:
        return cleaned
            .split('_')
            .where(
              (word) => word.isNotEmpty,
            )
            .map(
          (word) {
            return '${word[0].toUpperCase()}'
                '${word.substring(1).toLowerCase()}';
          },
        ).join(' ');
    }
  }

  Future<void> _showDetails(
    _TimelineItem item,
  ) async {
    final dispense =
        item.sourceId == null ? null : _dispenseDetails[item.sourceId];

    final color = _itemColor(
      item,
      dispense,
    );

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.cBgSecondary,
      builder: (
        sheetContext,
      ) {
        return FractionallySizedBox(
          heightFactor: 0.90,
          child: SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                20,
                12,
                20,
                28,
              ),
              children: [
                Center(
                  child: Container(
                    width: 44,
                    height: 4,
                    decoration: BoxDecoration(
                      color: context.cDivider,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 54,
                      height: 54,
                      decoration: BoxDecoration(
                        color: color.withValues(
                          alpha: 0.12,
                        ),
                        borderRadius: BorderRadius.circular(17),
                      ),
                      child: Icon(
                        _itemIcon(item),
                        color: color,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.title,
                            style: TextStyle(
                              color: context.cTextPrimary,
                              fontSize: 21,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _formatDateTime(
                              item.createdAt,
                            ),
                            style: TextStyle(
                              color: context.cTextSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    _TimelineBadge(
                      label: _sourceLabel(item.source),
                      color: color,
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: context.cBgPrimary,
                    borderRadius: BorderRadius.circular(17),
                    border: Border.all(
                      color: context.cDivider,
                    ),
                  ),
                  child: Text(
                    item.description.isEmpty
                        ? 'No additional timeline description was recorded.'
                        : item.description,
                    style: TextStyle(
                      color: context.cTextPrimary,
                      height: 1.5,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                _TimelineDetailSection(
                  title: 'Timeline Information',
                  icon: Icons.timeline_rounded,
                  children: [
                    _TimelineDetailRow(
                      label: 'Type',
                      value: item.displayItemType,
                    ),
                    _TimelineDetailRow(
                      label: 'Source',
                      value: _sourceLabel(item.source),
                    ),
                    _TimelineDetailRow(
                      label: 'Severity',
                      value: item.displaySeverity,
                    ),
                    _TimelineDetailRow(
                      label: 'Recorded',
                      value: _formatDateTime(
                        item.createdAt,
                      ),
                    ),
                    _TimelineDetailRow(
                      label: 'Doctor visibility',
                      value: item.doctorVisible ? 'Visible' : 'Hidden',
                    ),
                  ],
                ),
                if (dispense != null) ...[
                  const SizedBox(height: 14),
                  _TimelineDetailSection(
                    title: 'Pharmacy Collection',
                    icon: Icons.local_pharmacy_outlined,
                    children: [
                      _TimelineDetailRow(
                        label: 'Medication',
                        value: dispense.medicineName,
                      ),
                      _TimelineDetailRow(
                        label: 'Status',
                        value: dispense.statusLabel,
                      ),
                      _TimelineDetailRow(
                        label: 'Hospital',
                        value: dispense.hospitalName,
                      ),
                      _TimelineDetailRow(
                        label: 'Collection reference',
                        value: dispense.collectionReference,
                      ),
                      _TimelineDetailRow(
                        label: 'Received',
                        value: _formatDateTime(
                          dispense.receivedAt,
                        ),
                      ),
                      _TimelineDetailRow(
                        label: 'Ready',
                        value: _formatDateTime(
                          dispense.readyAt,
                        ),
                      ),
                      _TimelineDetailRow(
                        label: 'Collected',
                        value: _formatDateTime(
                          dispense.collectedAt,
                        ),
                      ),
                      _TimelineDetailRow(
                        label: 'Collected by',
                        value: dispense.collectedByName,
                      ),
                      _TimelineDetailRow(
                        label: 'Relationship',
                        value: dispense.collectorRelationship,
                      ),
                      _TimelineDetailRow(
                        label: 'Collection notes',
                        value: dispense.collectionNotes,
                      ),
                    ],
                  ),
                  if (widget.patientId == null) ...[
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          Navigator.of(
                            sheetContext,
                          ).pop();

                          await Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) {
                                return const PatientPharmacyStatusPage();
                              },
                            ),
                          );
                        },
                        icon: const Icon(
                          Icons.local_pharmacy_outlined,
                        ),
                        label: const Text(
                          'Open Pharmacy Status',
                        ),
                      ),
                    ),
                  ],
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.cBgPrimary,
      appBar: AppBar(
        title: const Text(
          'Patient Timeline',
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh timeline',
            onPressed: _loading ? null : _loadTimeline,
            icon: const Icon(
              Icons.refresh_rounded,
            ),
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return Center(
        child: CircularProgressIndicator(
          color: context.cAccentReadable,
        ),
      );
    }

    if (_error != null) {
      return _buildErrorState();
    }

    if (_items.isEmpty) {
      return _buildEmptyState();
    }

    final visibleItems = _visibleItems;

    return RefreshIndicator(
      onRefresh: _loadTimeline,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          16,
          16,
          16,
          28,
        ),
        children: [
          Text(
            'Medical Activity',
            style: TextStyle(
              color: context.cTextPrimary,
              fontSize: 24,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'View appointments, prescriptions, laboratory '
            'activity and completed pharmacy collections.',
            style: TextStyle(
              color: context.cTextSecondary,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 20),
          _buildSummary(),
          const SizedBox(height: 18),
          TextField(
            controller: _searchController,
            onChanged: (_) {
              setState(() {});
            },
            decoration: InputDecoration(
              hintText: 'Search timeline, medicine or collection reference',
              prefixIcon: const Icon(
                Icons.search,
              ),
              suffixIcon: _searchController.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear search',
                      onPressed: () {
                        _searchController.clear();

                        setState(() {});
                      },
                      icon: const Icon(
                        Icons.clear,
                      ),
                    ),
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _filters.map(
              (filter) {
                return ChoiceChip(
                  label: Text(filter),
                  selected: _selectedFilter == filter,
                  onSelected: (_) {
                    setState(() {
                      _selectedFilter = filter;
                    });
                  },
                );
              },
            ).toList(),
          ),
          const SizedBox(height: 20),
          Text(
            '$_selectedFilter Activity '
            '(${visibleItems.length})',
            style: TextStyle(
              color: context.cTextPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 12),
          if (visibleItems.isEmpty)
            _buildFilteredEmptyState()
          else
            ...visibleItems.map(
              _buildTimelineCard,
            ),
        ],
      ),
    );
  }

  Widget _buildSummary() {
    final summary = [
      _TimelineSummaryItem(
        label: 'Total Activity',
        value: _items.length,
        icon: Icons.timeline_rounded,
        color: context.cAccentReadable,
      ),
      _TimelineSummaryItem(
        label: 'Pharmacy',
        value: _pharmacyCount,
        icon: Icons.local_pharmacy_outlined,
        color: Colors.teal.shade700,
      ),
      _TimelineSummaryItem(
        label: 'Last 30 Days',
        value: _recentCount,
        icon: Icons.history_rounded,
        color: Colors.blue.shade700,
      ),
    ];

    return LayoutBuilder(
      builder: (
        context,
        constraints,
      ) {
        final columns = constraints.maxWidth >= 720
            ? 3
            : constraints.maxWidth >= 440
                ? 2
                : 1;

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: summary.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            mainAxisExtent: 108,
          ),
          itemBuilder: (
            context,
            index,
          ) {
            final item = summary[index];

            return Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: context.cBgSecondary,
                borderRadius: BorderRadius.circular(17),
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
                        alpha: 0.12,
                      ),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      item.icon,
                      color: item.color,
                    ),
                  ),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${item.value}',
                          style: TextStyle(
                            color: context.cTextPrimary,
                            fontSize: 23,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          item.label,
                          style: TextStyle(
                            color: context.cTextSecondary,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildTimelineCard(
    _TimelineItem item,
  ) {
    final dispense =
        item.sourceId == null ? null : _dispenseDetails[item.sourceId];

    final color = _itemColor(
      item,
      dispense,
    );

    final subtitle = item.description.isEmpty
        ? 'No additional details recorded.'
        : item.description;

    return Container(
      margin: const EdgeInsets.only(
        bottom: 13,
      ),
      decoration: BoxDecoration(
        color: context.cBgSecondary,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: context.cDivider,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () {
            _showDetails(item);
          },
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Column(
                  children: [
                    Container(
                      width: 47,
                      height: 47,
                      decoration: BoxDecoration(
                        color: color.withValues(
                          alpha: 0.12,
                        ),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        _itemIcon(item),
                        color: color,
                      ),
                    ),
                    Container(
                      width: 2,
                      height: 55,
                      margin: const EdgeInsets.only(top: 7),
                      color: color.withValues(
                        alpha: 0.22,
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              item.title,
                              style: TextStyle(
                                color: context.cTextPrimary,
                                fontSize: 17,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          _TimelineBadge(
                            label: dispense != null
                                ? dispense.statusLabel
                                : _sourceLabel(
                                    item.source,
                                  ),
                            color: color,
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        subtitle,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: context.cTextSecondary,
                          height: 1.4,
                        ),
                      ),
                      if (dispense != null) ...[
                        const SizedBox(height: 11),
                        Wrap(
                          spacing: 12,
                          runSpacing: 8,
                          children: [
                            _TimelineInfo(
                              icon: Icons.medication_outlined,
                              text: dispense.medicineName,
                            ),
                            _TimelineInfo(
                              icon: Icons.qr_code_2,
                              text: dispense.collectionReference,
                            ),
                            _TimelineInfo(
                              icon: Icons.local_hospital_outlined,
                              text: dispense.hospitalName,
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 11),
                      Row(
                        children: [
                          Icon(
                            Icons.schedule,
                            size: 15,
                            color: context.cTextMuted,
                          ),
                          const SizedBox(width: 5),
                          Expanded(
                            child: Text(
                              _formatDateTime(
                                item.createdAt,
                              ),
                              style: TextStyle(
                                color: context.cTextMuted,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          Icon(
                            Icons.chevron_right_rounded,
                            color: context.cTextMuted,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    return RefreshIndicator(
      onRefresh: _loadTimeline,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 100),
          Icon(
            Icons.cloud_off_outlined,
            color: CorviaColors.danger,
            size: 58,
          ),
          const SizedBox(height: 16),
          Text(
            'Timeline could not load',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: context.cTextPrimary,
              fontSize: 21,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          SelectableText(
            _error ?? 'Unknown timeline error.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: context.cTextSecondary,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: _loadTimeline,
            icon: const Icon(
              Icons.refresh_rounded,
            ),
            label: const Text(
              'Try Again',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return RefreshIndicator(
      onRefresh: _loadTimeline,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 100),
          Icon(
            Icons.timeline_rounded,
            color: context.cTextSecondary,
            size: 62,
          ),
          const SizedBox(height: 16),
          Text(
            'No timeline activity yet',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: context.cTextPrimary,
              fontSize: 21,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Appointments, clinical updates, prescriptions, '
            'laboratory records and completed pharmacy '
            'collections will appear here.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: context.cTextSecondary,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilteredEmptyState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(32),
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
            Icons.filter_alt_off_outlined,
            size: 44,
            color: context.cTextSecondary,
          ),
          const SizedBox(height: 12),
          Text(
            'No $_selectedFilter activity',
            style: TextStyle(
              color: context.cTextPrimary,
              fontSize: 17,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'No timeline records match the selected '
            'filter or search.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: context.cTextSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _TimelineItem {
  const _TimelineItem({
    required this.id,
    required this.patientId,
    required this.createdBy,
    required this.itemType,
    required this.title,
    required this.description,
    required this.source,
    required this.sourceId,
    required this.severity,
    required this.doctorVisible,
    required this.patientVisible,
    required this.createdAt,
  });

  factory _TimelineItem.fromMap(
    Map<String, dynamic> map,
  ) {
    return _TimelineItem(
      id: _text(
        map['id'],
      ),
      patientId: _text(
        map['patient_id'],
      ),
      createdBy: _nullableText(
        map['created_by'],
      ),
      itemType: _text(
        map['item_type'],
        fallback: 'note',
      ),
      title: _text(
        map['title'],
        fallback: 'Timeline Activity',
      ),
      description: _text(
        map['description'],
      ),
      source: _text(
        map['source'],
        fallback: 'corvia',
      ),
      sourceId: _nullableText(
        map['source_id'],
      ),
      severity: _text(
        map['severity'],
        fallback: 'normal',
      ),
      doctorVisible: map['doctor_visible'] != false,
      patientVisible: map['patient_visible'] != false,
      createdAt: _date(
        map['created_at'],
      ),
    );
  }

  final String id;
  final String patientId;
  final String? createdBy;
  final String itemType;
  final String title;
  final String description;
  final String source;
  final String? sourceId;
  final String severity;
  final bool doctorVisible;
  final bool patientVisible;
  final DateTime? createdAt;

  String get _combined {
    return [
      itemType,
      title,
      source,
    ].join(' ').toLowerCase();
  }

  bool get isPharmacy {
    return source.toLowerCase() == 'prescription_dispense' ||
        _combined.contains(
          'medication_collection',
        ) ||
        _combined.contains('pharmacy') ||
        _combined.contains('dispense') ||
        _combined.contains(
          'medication collected',
        );
  }

  bool get isPrescription {
    return _combined.contains('prescription') ||
        _combined.contains('medication');
  }

  bool get isAppointment {
    return _combined.contains('appointment') ||
        _combined.contains('consultation');
  }

  bool get isLab {
    return _combined.contains('lab') ||
        _combined.contains('pathology') ||
        _combined.contains('test result');
  }

  String get displayItemType {
    return _pretty(
      itemType,
    );
  }

  String get displaySeverity {
    return _pretty(
      severity,
    );
  }

  static String _text(
    dynamic value, {
    String fallback = '',
  }) {
    final text = value?.toString().trim();

    if (text == null || text.isEmpty || text.toLowerCase() == 'null') {
      return fallback;
    }

    return text;
  }

  static String? _nullableText(
    dynamic value,
  ) {
    final text = value?.toString().trim();

    if (text == null || text.isEmpty || text.toLowerCase() == 'null') {
      return null;
    }

    return text;
  }

  static DateTime? _date(dynamic value) {
    final text = value?.toString().trim();

    if (text == null || text.isEmpty) {
      return null;
    }

    return DateTime.tryParse(text);
  }

  static String _pretty(String value) {
    final cleaned = value.trim().replaceAll('-', '_').replaceAll(' ', '_');

    return cleaned
        .split('_')
        .where(
          (word) => word.isNotEmpty,
        )
        .map(
      (word) {
        return '${word[0].toUpperCase()}'
            '${word.substring(1).toLowerCase()}';
      },
    ).join(' ');
  }
}

class _DispenseDetails {
  const _DispenseDetails({
    required this.id,
    required this.status,
    required this.collectionReference,
    required this.medicineName,
    required this.hospitalName,
    required this.receivedAt,
    required this.readyAt,
    required this.collectedAt,
    required this.collectedByName,
    required this.collectorRelationship,
    required this.collectionNotes,
  });

  factory _DispenseDetails.fromMaps({
    required Map<String, dynamic> dispense,
    required Map<String, dynamic>? prescription,
    required Map<String, dynamic>? hospital,
  }) {
    return _DispenseDetails(
      id: _text(
        dispense['id'],
      ),
      status: _text(
        dispense['status'],
        fallback: 'received',
      ).toLowerCase(),
      collectionReference: _text(
        dispense['collection_reference'],
        fallback: 'Not available',
      ),
      medicineName: _medicineName(
        prescription,
      ),
      hospitalName: _firstText(
        [
          hospital?['name'],
        ],
        fallback: 'Hospital Pharmacy',
      ),
      receivedAt: _date(
        dispense['received_at'],
      ),
      readyAt: _date(
        dispense['ready_at'],
      ),
      collectedAt: _date(
        dispense['collected_at'],
      ),
      collectedByName: _firstText(
        [
          dispense['collected_by_name'],
        ],
        fallback: 'Not recorded',
      ),
      collectorRelationship: _firstText(
        [
          dispense['collector_relationship'],
        ],
        fallback: 'Not recorded',
      ),
      collectionNotes: _firstText(
        [
          dispense['collection_notes'],
        ],
        fallback: 'No collection notes',
      ),
    );
  }

  final String id;
  final String status;
  final String collectionReference;
  final String medicineName;
  final String hospitalName;
  final DateTime? receivedAt;
  final DateTime? readyAt;
  final DateTime? collectedAt;
  final String collectedByName;
  final String collectorRelationship;
  final String collectionNotes;

  String get statusLabel {
    switch (status) {
      case 'received':
        return 'Received';

      case 'verified':
        return 'Verified';

      case 'preparing':
        return 'Preparing';

      case 'ready_for_collection':
        return 'Ready for Collection';

      case 'collected':
        return 'Collected';

      case 'unable_to_dispense':
        return 'Unable to Dispense';

      case 'cancelled':
        return 'Cancelled';

      default:
        return _TimelineItem._pretty(
          status,
        );
    }
  }

  static String _medicineName(
    Map<String, dynamic>? prescription,
  ) {
    final directName = _firstText(
      [
        prescription?['medication_name'],
        prescription?['medicine_name'],
        prescription?['medication'],
        prescription?['drug_name'],
        prescription?['name'],
      ],
      fallback: '',
    );

    if (directName.isNotEmpty) {
      return directName;
    }

    final medicines = prescription?['medicines'];

    if (medicines is List) {
      final names = medicines
          .whereType<Map>()
          .map(
            (medicine) {
              return _firstText(
                [
                  medicine['name'],
                  medicine['medication_name'],
                  medicine['medication'],
                ],
                fallback: '',
              );
            },
          )
          .where(
            (name) => name.isNotEmpty,
          )
          .toList();

      if (names.isNotEmpty) {
        return names.join(', ');
      }
    }

    return 'Prescription medication';
  }

  static String _text(
    dynamic value, {
    String fallback = '',
  }) {
    final text = value?.toString().trim();

    if (text == null || text.isEmpty || text.toLowerCase() == 'null') {
      return fallback;
    }

    return text;
  }

  static String _firstText(
    List<dynamic> values, {
    required String fallback,
  }) {
    for (final value in values) {
      final text = value?.toString().trim();

      if (text != null && text.isNotEmpty && text.toLowerCase() != 'null') {
        return text;
      }
    }

    return fallback;
  }

  static DateTime? _date(dynamic value) {
    final text = value?.toString().trim();

    if (text == null || text.isEmpty) {
      return null;
    }

    return DateTime.tryParse(text);
  }
}

class _TimelineSummaryItem {
  const _TimelineSummaryItem({
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

class _TimelineBadge extends StatelessWidget {
  const _TimelineBadge({
    required this.label,
    required this.color,
  });

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(
        maxWidth: 155,
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: 9,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: color.withValues(
          alpha: 0.10,
        ),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: color.withValues(
            alpha: 0.23,
          ),
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
}

class _TimelineInfo extends StatelessWidget {
  const _TimelineInfo({
    required this.icon,
    required this.text,
  });

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 15,
          color: context.cTextMuted,
        ),
        const SizedBox(width: 5),
        ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: 220,
          ),
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: context.cTextSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class _TimelineDetailSection extends StatelessWidget {
  const _TimelineDetailSection({
    required this.title,
    required this.icon,
    required this.children,
  });

  final String title;
  final IconData icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: context.cBgPrimary,
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
                icon,
                color: context.cAccentReadable,
              ),
              const SizedBox(width: 9),
              Text(
                title,
                style: TextStyle(
                  color: context.cTextPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }
}

class _TimelineDetailRow extends StatelessWidget {
  const _TimelineDetailRow({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(
        bottom: 12,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 145,
            child: Text(
              label,
              style: TextStyle(
                color: context.cTextMuted,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: context.cTextPrimary,
                fontWeight: FontWeight.w600,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
