import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../services/doctor_clinical_service.dart';
import '../../services/supabase_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/status_view.dart';

import '../patient/doctor_patient_timeline.dart';

/// Lists every patient that has ever had an appointment or prescription with
/// the currently signed-in doctor. Tapping a row opens a sheet with the
/// patient's appointment + prescription history.
class DoctorPatientManagementPage extends StatefulWidget {
  const DoctorPatientManagementPage({super.key});

  @override
  State<DoctorPatientManagementPage> createState() =>
      _DoctorPatientManagementPageState();
}

class _DoctorPatientManagementPageState
    extends State<DoctorPatientManagementPage> {
  final _searchCtrl = TextEditingController();
  Future<_PatientListBundle>? _future;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _refresh() {
    setState(() {
      _future = _PatientListBundle.load();
    });
  }

  List<_PatientRow> _filter(List<_PatientRow> all) {
    final query = _query.trim().toLowerCase();

    if (query.isEmpty) {
      return all;
    }

    return all.where((patient) {
      return patient.name.toLowerCase().contains(query) ||
          (patient.primaryCondition?.toLowerCase().contains(query) ?? false);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.cBgPrimary,
      appBar: AppBar(
        title: const Text('Patient Management'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _refresh,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _searchCtrl,
              style: TextStyle(color: CorviaColors.textPrimary),
              decoration: InputDecoration(
                hintText: 'Search by name or condition',
                prefixIcon: Icon(
                  Icons.search,
                  color: CorviaColors.accentLight,
                ),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() {
                            _query = '';
                          });
                        },
                      ),
              ),
              onChanged: (value) {
                setState(() {
                  _query = value;
                });
              },
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async {
                _refresh();
              },
              child: FutureBuilder<_PatientListBundle>(
                future: _future,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return StatusView.loading(
                      message: 'Loading your patients...',
                    );
                  }

                  if (snapshot.hasError) {
                    return StatusView.error(
                      friendlyMessage: "We couldn't load your patient list.",
                      error: snapshot.error,
                      stackTrace: snapshot.stackTrace,
                      onRetry: _refresh,
                    );
                  }

                  final bundle = snapshot.data!;

                  if (bundle.notADoctor) {
                    return StatusView.empty(
                      icon: Icons.medical_services_outlined,
                      title: 'No doctor profile found',
                      subtitle: 'You need a doctor profile to manage patients.',
                    );
                  }

                  final allPatients = bundle.patients;

                  if (allPatients.isEmpty) {
                    return StatusView.empty(
                      icon: Icons.people_outline,
                      title: 'No patients yet',
                      subtitle: 'Patients appear here once you have had an '
                          'appointment with them or written them a '
                          'prescription.',
                      onRetry: _refresh,
                    );
                  }

                  final filteredPatients = _filter(allPatients);

                  if (filteredPatients.isEmpty) {
                    final searchText = _searchCtrl.text.trim();

                    return StatusView.empty(
                      icon: Icons.search_off,
                      title: 'No patients found',
                      subtitle: searchText.isEmpty
                          ? 'Try searching by patient name or condition.'
                          : 'No results found for "$searchText".\n\n'
                              'Check the spelling or try searching by another name or condition.',
                    );
                  }

                  return _PatientList(
                    patients: filteredPatients,
                    onTap: _openDetail,
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _openDetail(_PatientRow patient) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: CorviaColors.secondaryDark,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(20),
        ),
      ),
      builder: (_) {
        return _PatientDetailSheet(patient: patient);
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Data model
// ─────────────────────────────────────────────────────────────────────────────

class _PatientListBundle {
  _PatientListBundle({
    required this.notADoctor,
    required this.patients,
  });

  final bool notADoctor;
  final List<_PatientRow> patients;

  static Future<_PatientListBundle> load() async {
    final client = SupabaseService.client;
    final user = client.auth.currentUser;

    if (user == null) {
      return _PatientListBundle(
        notADoctor: true,
        patients: const [],
      );
    }

    final clinicalService = DoctorClinicalService(
      client: client,
    );

    DoctorClinicalContext doctorContext;
    List<DoctorClinicalPatient> linkedPatients;

    try {
      doctorContext = await clinicalService.currentContext();
      linkedPatients = await clinicalService.loadDoctorPatients(
        doctorContext,
      );
    } catch (_) {
      return _PatientListBundle(
        notADoctor: true,
        patients: const [],
      );
    }

    final doctorId = doctorContext.doctorId;

    final appointmentRows = await client
        .from('appointments')
        .select('patient_id, appointment_date, status')
        .eq('doctor_id', doctorId);

    final prescriptionRows = await client
        .from('prescriptions')
        .select('patient_id, issued_at, status')
        .eq('doctor_id', doctorId);

    final appointmentCounts = <String, int>{};
    final prescriptionCounts = <String, int>{};
    final lastVisitByPatientId = <String, DateTime>{};

    void increaseCount(Map<String, int> bucket, String? patientId) {
      if (patientId == null || patientId.isEmpty) {
        return;
      }

      bucket[patientId] = (bucket[patientId] ?? 0) + 1;
    }

    for (final row in appointmentRows as List) {
      final patientId = row['patient_id']?.toString();

      increaseCount(appointmentCounts, patientId);

      final appointmentDate = DateTime.tryParse(
        row['appointment_date']?.toString() ?? '',
      );

      if (patientId != null &&
          patientId.isNotEmpty &&
          appointmentDate != null) {
        final currentLatest = lastVisitByPatientId[patientId];

        if (currentLatest == null || appointmentDate.isAfter(currentLatest)) {
          lastVisitByPatientId[patientId] = appointmentDate;
        }
      }
    }

    for (final row in prescriptionRows as List) {
      increaseCount(
        prescriptionCounts,
        row['patient_id']?.toString(),
      );
    }

    final patientIds = linkedPatients
        .map(
          (patient) => patient.id,
        )
        .toSet();

    if (patientIds.isEmpty) {
      return _PatientListBundle(
        notADoctor: false,
        patients: const [],
      );
    }

    // Get patient medical records first.
    // Names are loaded separately from profiles using patients.profile_id.
    final patientRows = await client
        .from('patients')
        .select(
          'id, profile_id, date_of_birth, gender, primary_condition',
        )
        .inFilter('id', patientIds.toList());

    final profileIds = <String>{};

    for (final row in patientRows as List) {
      final profileId = row['profile_id']?.toString();

      if (profileId != null && profileId.isNotEmpty) {
        profileIds.add(profileId);
      }
    }

    final namesByProfileId = <String, String>{};

    if (profileIds.isNotEmpty) {
      try {
        final profileRows = await client
            .from('profiles')
            .select('user_id, first_name, surname')
            .inFilter('user_id', profileIds.toList());

        for (final row in profileRows as List) {
          final profileId = row['user_id']?.toString() ?? '';

          final firstName = row['first_name']?.toString().trim() ?? '';
          final surname = row['surname']?.toString().trim() ?? '';
          final fullName = '$firstName $surname'.trim();

          if (profileId.isNotEmpty && fullName.isNotEmpty) {
            namesByProfileId[profileId] = fullName;
          }
        }
      } catch (error) {
        debugPrint('Could not load patient profile names: $error');
      }
    }

    final linkedNamesByPatientId = <String, String>{
      for (final patient in linkedPatients) patient.id: patient.name,
    };

    final patients = <_PatientRow>[];

    for (final row in patientRows as List) {
      final patientId = row['id']?.toString() ?? '';

      if (patientId.isEmpty) {
        continue;
      }

      final profileId = row['profile_id']?.toString() ?? '';
      final patientName = namesByProfileId[profileId] ??
          linkedNamesByPatientId[patientId] ??
          'Unknown Patient';

      DateTime? dateOfBirth;

      final rawDateOfBirth = row['date_of_birth']?.toString();

      if (rawDateOfBirth != null && rawDateOfBirth.isNotEmpty) {
        dateOfBirth = DateTime.tryParse(rawDateOfBirth);
      }

      patients.add(
        _PatientRow(
          id: patientId,
          name: patientName,
          dateOfBirth: dateOfBirth,
          gender: row['gender']?.toString(),
          primaryCondition: row['primary_condition']?.toString(),
          appointmentCount: appointmentCounts[patientId] ?? 0,
          prescriptionCount: prescriptionCounts[patientId] ?? 0,
          lastVisit: lastVisitByPatientId[patientId],
        ),
      );
    }

    patients.sort((first, second) {
      final firstVisit = first.lastVisit;
      final secondVisit = second.lastVisit;

      if (firstVisit != null && secondVisit != null) {
        return secondVisit.compareTo(firstVisit);
      }

      if (firstVisit != null) {
        return -1;
      }

      if (secondVisit != null) {
        return 1;
      }

      return first.name.toLowerCase().compareTo(
            second.name.toLowerCase(),
          );
    });

    return _PatientListBundle(
      notADoctor: false,
      patients: patients,
    );
  }
}

class _PatientRow {
  _PatientRow({
    required this.id,
    required this.name,
    required this.dateOfBirth,
    required this.gender,
    required this.primaryCondition,
    required this.appointmentCount,
    required this.prescriptionCount,
    required this.lastVisit,
  });

  final String id;
  final String name;
  final DateTime? dateOfBirth;
  final String? gender;
  final String? primaryCondition;
  final int appointmentCount;
  final int prescriptionCount;
  final DateTime? lastVisit;

  int? get age {
    final dateOfBirthValue = dateOfBirth;

    if (dateOfBirthValue == null) {
      return null;
    }

    final now = DateTime.now();
    var age = now.year - dateOfBirthValue.year;

    if (now.month < dateOfBirthValue.month ||
        (now.month == dateOfBirthValue.month &&
            now.day < dateOfBirthValue.day)) {
      age--;
    }

    return age;
  }

  String get initials {
    if (name == 'Unknown Patient') {
      return 'UP';
    }

    final parts = name.trim().split(RegExp(r'\s+'));

    if (parts.isEmpty || parts.first.isEmpty) {
      return '?';
    }

    if (parts.length == 1) {
      return parts.first[0].toUpperCase();
    }

    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Paginated patient list
// ─────────────────────────────────────────────────────────────────────────────

class _PatientList extends StatefulWidget {
  const _PatientList({
    required this.patients,
    required this.onTap,
  });

  final List<_PatientRow> patients;
  final void Function(_PatientRow) onTap;

  @override
  State<_PatientList> createState() => _PatientListState();
}

class _PatientListState extends State<_PatientList> {
  static const _pageSize = 10;

  int _visibleCount = _pageSize;

  @override
  void didUpdateWidget(_PatientList oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.patients.length != widget.patients.length) {
      _visibleCount = _pageSize;
    }
  }

  @override
  Widget build(BuildContext context) {
    final allPatients = widget.patients;
    final visiblePatients = allPatients.take(_visibleCount).toList();
    final hasMore = allPatients.length > _visibleCount;
    final remaining = allPatients.length - _visibleCount;

    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
      itemCount: visiblePatients.length + (hasMore ? 1 : 0),
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, index) {
        if (index == visiblePatients.length) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: OutlinedButton.icon(
              onPressed: () {
                setState(() {
                  _visibleCount += _pageSize;
                });
              },
              icon: const Icon(Icons.expand_more),
              label: Text('Load more ($remaining remaining)'),
              style: OutlinedButton.styleFrom(
                foregroundColor: CorviaColors.accentLight,
                side: BorderSide(
                  color: CorviaColors.accentLight.withValues(alpha: 0.5),
                ),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          );
        }

        return _PatientCard(
          patient: visiblePatients[index],
          onTap: () {
            widget.onTap(visiblePatients[index]);
          },
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Patient list card
// ─────────────────────────────────────────────────────────────────────────────

class _PatientCard extends StatelessWidget {
  const _PatientCard({
    required this.patient,
    required this.onTap,
  });

  final _PatientRow patient;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ageGenderParts = <String>[
      if (patient.age != null) '${patient.age} yrs',
      if (patient.gender != null && patient.gender!.isNotEmpty) patient.gender!,
    ];

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 6,
          ),
          leading: CircleAvatar(
            radius: 22,
            backgroundColor: CorviaColors.accent.withValues(alpha: 0.18),
            child: Text(
              patient.initials,
              style: TextStyle(
                color: CorviaColors.accentLight,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          title: Text(
            patient.name,
            style: TextStyle(
              color: CorviaColors.textPrimary,
              fontWeight: FontWeight.bold,
            ),
          ),
          subtitle: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (ageGenderParts.isNotEmpty)
                Text(
                  ageGenderParts.join(' · '),
                  style: TextStyle(
                    color: CorviaColors.textSecondary,
                  ),
                ),
              if (patient.primaryCondition != null &&
                  patient.primaryCondition!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    patient.primaryCondition!,
                    overflow: TextOverflow.ellipsis,
                    maxLines: 2,
                    style: TextStyle(
                      color: CorviaColors.accentLight,
                      fontSize: 12,
                    ),
                  ),
                ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  _CountBadge(
                    icon: Icons.calendar_today,
                    label: '${patient.appointmentCount} appt'
                        '${patient.appointmentCount == 1 ? '' : 's'}',
                    color: Colors.blueAccent,
                  ),
                  _CountBadge(
                    icon: Icons.medication,
                    label: '${patient.prescriptionCount} Rx',
                    color: Colors.greenAccent,
                  ),
                  if (patient.lastVisit != null)
                    _CountBadge(
                      icon: Icons.history,
                      label:
                          'Last: ${DateFormat('d MMM').format(patient.lastVisit!.toLocal())}',
                      color: CorviaColors.textMuted,
                    ),
                ],
              ),
            ],
          ),
          trailing: Icon(
            Icons.chevron_right,
            color: CorviaColors.accentLight,
          ),
          onTap: onTap,
        ),
      ),
    );
  }
}

class _CountBadge extends StatelessWidget {
  const _CountBadge({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 8,
        vertical: 3,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: color.withValues(alpha: 0.4),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 12,
            color: color,
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: CorviaColors.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Patient detail bottom sheet
// ─────────────────────────────────────────────────────────────────────────────

class _PatientDetailSheet extends StatefulWidget {
  const _PatientDetailSheet({
    required this.patient,
  });

  final _PatientRow patient;

  @override
  State<_PatientDetailSheet> createState() => _PatientDetailSheetState();
}

class _PatientDetailSheetState extends State<_PatientDetailSheet> {
  Future<_PatientDetail>? _future;

  @override
  void initState() {
    super.initState();
    _future = _PatientDetail.load(widget.patient.id);
  }

  @override
  Widget build(BuildContext context) {
    final patient = widget.patient;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (_, scrollController) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: CorviaColors.textMuted,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor:
                        CorviaColors.accent.withValues(alpha: 0.18),
                    child: Text(
                      patient.initials,
                      style: TextStyle(
                        color: CorviaColors.accentLight,
                        fontWeight: FontWeight.bold,
                        fontSize: 22,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          patient.name,
                          style: CorviaTextStyles.heading,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          [
                            if (patient.age != null) '${patient.age} yrs',
                            if (patient.gender != null &&
                                patient.gender!.isNotEmpty)
                              patient.gender!,
                          ].join(' · '),
                          style: CorviaTextStyles.subtle,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (patient.primaryCondition != null &&
                  patient.primaryCondition!.isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: CorviaColors.warning.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: CorviaColors.warning.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.medical_information,
                        size: 16,
                        color: CorviaColors.warning,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Primary condition: ${patient.primaryCondition!}',
                          style: TextStyle(
                            color: CorviaColors.textPrimary,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Divider(
                color: CorviaColors.divider,
                height: 1,
              ),
              const SizedBox(height: 12),
              Expanded(
                child: FutureBuilder<_PatientDetail>(
                  future: _future,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState != ConnectionState.done) {
                      return StatusView.loading(
                        message: 'Loading history...',
                      );
                    }

                    if (snapshot.hasError) {
                      return StatusView.error(
                        friendlyMessage:
                            "We couldn't load this patient's history.",
                        error: snapshot.error,
                        onRetry: () {
                          setState(() {
                            _future = _PatientDetail.load(patient.id);
                          });
                        },
                      );
                    }

                    return _DetailBody(
                      detail: snapshot.data!,
                      scrollController: scrollController,
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _DetailBody extends StatelessWidget {
  const _DetailBody({
    required this.detail,
    required this.scrollController,
  });

  final _PatientDetail detail;
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Column(
        children: [
          TabBar(
            indicatorColor: CorviaColors.accent,
            labelColor: CorviaColors.accentLight,
            unselectedLabelColor: CorviaColors.textSecondary,
            tabs: [
              Tab(
                text: 'Appointments (${detail.appointments.length})',
              ),
              Tab(
                text: 'Prescriptions (${detail.prescriptions.length})',
              ),
              const Tab(
                text: 'Timeline',
              ),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _AppointmentsList(
                  items: detail.appointments,
                  scrollController: scrollController,
                ),
                _PrescriptionsList(
                  items: detail.prescriptions,
                  scrollController: scrollController,
                ),
                DoctorPatientTimelinePage(
                  patientId: detail.patientId,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AppointmentsList extends StatelessWidget {
  const _AppointmentsList({
    required this.items,
    required this.scrollController,
  });

  final List<_ApptDetail> items;
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: InlineStatus(
          icon: Icons.calendar_today_outlined,
          message: 'No appointments with this patient yet.',
        ),
      );
    }

    final dateFormat = DateFormat('EEE d MMM yyyy, HH:mm');

    return ListView.separated(
      controller: scrollController,
      padding: const EdgeInsets.only(top: 8),
      itemCount: items.length,
      separatorBuilder: (_, __) {
        return Divider(
          color: CorviaColors.divider,
          height: 8,
        );
      },
      itemBuilder: (_, index) {
        final appointment = items[index];

        return ListTile(
          dense: true,
          leading: Icon(
            appointment.type == 'telehealth'
                ? Icons.video_call
                : Icons.local_hospital_outlined,
            color: CorviaColors.accentLight,
          ),
          title: Text(
            dateFormat.format(appointment.date.toLocal()),
            style: TextStyle(
              color: CorviaColors.textPrimary,
              fontSize: 14,
            ),
          ),
          subtitle: Text(
            [
              if (appointment.reason.isNotEmpty) appointment.reason,
              appointment.type,
            ].join(' · '),
            style: TextStyle(
              color: CorviaColors.textSecondary,
            ),
          ),
          trailing: _StatusPill(
            status: appointment.effectiveStatus,
          ),
        );
      },
    );
  }
}

class _PrescriptionsList extends StatelessWidget {
  const _PrescriptionsList({
    required this.items,
    required this.scrollController,
  });

  final List<_RxDetail> items;
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: InlineStatus(
          icon: Icons.medication_outlined,
          message: 'No prescriptions written for this patient yet.',
        ),
      );
    }

    final dateFormat = DateFormat('d MMM yyyy');

    return ListView.separated(
      controller: scrollController,
      padding: const EdgeInsets.only(top: 8),
      itemCount: items.length,
      separatorBuilder: (_, __) {
        return Divider(
          color: CorviaColors.divider,
          height: 8,
        );
      },
      itemBuilder: (_, index) {
        final prescription = items[index];

        return ListTile(
          dense: true,
          leading: const Icon(
            Icons.medication,
            color: Colors.greenAccent,
          ),
          title: Text(
            prescription.medicationName,
            style: TextStyle(
              color: CorviaColors.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
          subtitle: Text(
            '${prescription.dosage} · ${prescription.frequency} · '
            '${dateFormat.format(prescription.issuedAt.toLocal())}',
            style: TextStyle(
              color: CorviaColors.textSecondary,
            ),
          ),
          trailing: _StatusPill(
            status: prescription.status,
          ),
        );
      },
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.status,
  });

  final String status;

  Color get _color {
    switch (status) {
      case 'scheduled':
        return Colors.blueAccent;
      case 'confirmed':
        return CorviaColors.accent;
      case 'completed':
        return Colors.green;
      case 'cancelled':
        return Colors.redAccent;
      case 'no_show':
        return Colors.orange;
      case 'missed':
        return Colors.deepOrange;
      case 'active':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _color;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 8,
        vertical: 3,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: color.withValues(alpha: 0.5),
        ),
      ),
      child: Text(
        status.isEmpty ? '' : status[0].toUpperCase() + status.substring(1),
        style: TextStyle(
          color: CorviaColors.textPrimary,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Patient detail data
// ─────────────────────────────────────────────────────────────────────────────

class _PatientDetail {
  _PatientDetail({
    required this.patientId,
    required this.appointments,
    required this.prescriptions,
  });

  final String patientId;
  final List<_ApptDetail> appointments;
  final List<_RxDetail> prescriptions;

  static Future<_PatientDetail> load(String patientId) async {
    final client = SupabaseService.client;
    final user = client.auth.currentUser;

    if (user == null) {
      return _PatientDetail(
        patientId: patientId,
        appointments: const [],
        prescriptions: const [],
      );
    }

    late final String doctorId;

    try {
      final doctorContext = await DoctorClinicalService(
        client: client,
      ).currentContext();
      doctorId = doctorContext.doctorId;
    } catch (_) {
      return _PatientDetail(
        patientId: patientId,
        appointments: const [],
        prescriptions: const [],
      );
    }

    final appointmentRows = await client
        .from('appointments')
        .select(
          'appointment_date, duration_minutes, reason, type, status',
        )
        .eq('doctor_id', doctorId)
        .eq('patient_id', patientId)
        .order('appointment_date', ascending: false);

    final prescriptionRows = await client
        .from('prescriptions')
        .select(
          'medication_name, dosage, frequency, duration, status, issued_at',
        )
        .eq('doctor_id', doctorId)
        .eq('patient_id', patientId)
        .order('issued_at', ascending: false);

    final appointments = <_ApptDetail>[];

    for (final row in appointmentRows as List) {
      final appointmentDate = DateTime.tryParse(
        row['appointment_date']?.toString() ?? '',
      );

      if (appointmentDate == null) {
        continue;
      }

      appointments.add(
        _ApptDetail(
          date: appointmentDate,
          durationMinutes: (row['duration_minutes'] as int?) ?? 30,
          reason: row['reason']?.toString() ?? '',
          type: row['type']?.toString() ?? 'in-person',
          status: row['status']?.toString() ?? 'scheduled',
        ),
      );
    }

    final prescriptions = <_RxDetail>[];

    for (final row in prescriptionRows as List) {
      final issuedDate = DateTime.tryParse(
        row['issued_at']?.toString() ?? '',
      );

      prescriptions.add(
        _RxDetail(
          medicationName: row['medication_name']?.toString() ?? '',
          dosage: row['dosage']?.toString() ?? '',
          frequency: row['frequency']?.toString() ?? '',
          duration: row['duration']?.toString() ?? '',
          status: row['status']?.toString() ?? 'active',
          issuedAt: issuedDate ?? DateTime.now(),
        ),
      );
    }

    return _PatientDetail(
      patientId: patientId,
      appointments: appointments,
      prescriptions: prescriptions,
    );
  }
}

class _ApptDetail {
  _ApptDetail({
    required this.date,
    required this.durationMinutes,
    required this.reason,
    required this.type,
    required this.status,
  });

  final DateTime date;
  final int durationMinutes;
  final String reason;
  final String type;
  final String status;

  String get effectiveStatus {
    if (status == 'scheduled' || status == 'confirmed') {
      final appointmentEndTime = date.add(
        Duration(minutes: durationMinutes),
      );

      if (appointmentEndTime.isBefore(DateTime.now())) {
        return 'missed';
      }
    }

    return status;
  }
}

class _RxDetail {
  _RxDetail({
    required this.medicationName,
    required this.dosage,
    required this.frequency,
    required this.duration,
    required this.status,
    required this.issuedAt,
  });

  final String medicationName;
  final String dosage;
  final String frequency;
  final String duration;
  final String status;
  final DateTime issuedAt;
}
