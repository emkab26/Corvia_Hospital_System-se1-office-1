import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher_string.dart';

import '../../services/supabase_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/status_view.dart';

class DoctorReportViewingPage extends StatefulWidget {
  const DoctorReportViewingPage({
    super.key,
    this.patientId,
    this.patientName,
  });

  final String? patientId;
  final String? patientName;

  @override
  State<DoctorReportViewingPage> createState() =>
      _DoctorReportViewingPageState();
}

class _DoctorReportViewingPageState extends State<DoctorReportViewingPage> {
  final _searchCtrl = TextEditingController();
  Future<_DoctorReportsBundle>? _future;
  String _query = '';
  String _dateSort = 'newest';
  String _patientFilterId = 'all';

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
      _future = _DoctorReportsBundle.load(
        initialPatientId: widget.patientId,
        initialPatientName: widget.patientName,
      );
    });
  }

  List<_DoctorReport> _filterReports(List<_DoctorReport> reports) {
    final q = _query.trim().toLowerCase();
    final filtered = reports.where((report) {
      final matchesPatient =
          _patientFilterId == 'all' || report.patientId == _patientFilterId;
      final matchesSearch = q.isEmpty ||
          report.title.toLowerCase().contains(q) ||
          report.patientName.toLowerCase().contains(q) ||
          report.description.toLowerCase().contains(q) ||
          report.type.toLowerCase().contains(q) ||
          report.patientId.toLowerCase().contains(q) ||
          report.id.toLowerCase().contains(q);
      return matchesPatient && matchesSearch;
    }).toList();

    filtered.sort((a, b) {
      final newestFirst = _compareReportDates(a, b);
      return _dateSort == 'oldest' ? -newestFirst : newestFirst;
    });

    return filtered;
  }

  int _compareReportDates(_DoctorReport a, _DoctorReport b) {
    final aDate = a.reportDate;
    final bDate = b.reportDate;
    if (aDate == null && bDate == null) return 0;
    if (aDate == null) return 1;
    if (bDate == null) return -1;
    return bDate.compareTo(aDate);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.cBgPrimary,
      appBar: AppBar(
        title: const Text('Doctor Reports'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh reports',
            onPressed: _refresh,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => _refresh(),
        child: FutureBuilder<_DoctorReportsBundle>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return StatusView.loading(message: 'Loading doctor reports...');
            }
            if (snap.hasError) {
              return StatusView.error(
                friendlyMessage: "We couldn't load doctor reports.",
                error: snap.error,
                stackTrace: snap.stackTrace,
                onRetry: _refresh,
              );
            }

            final bundle = snap.data!;
            if (bundle.notADoctor) {
              return StatusView.empty(
                icon: Icons.medical_services_outlined,
                title: 'No doctor profile found',
                subtitle: 'You need a doctor profile to view patient reports.',
              );
            }

            return CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(
                  child: _ReportsHeader(
                    totalReports: bundle.reports.length,
                    patientCount: bundle.patientCount,
                  ),
                ),
                SliverToBoxAdapter(
                  child: _SearchAndFilters(
                    controller: _searchCtrl,
                    query: _query,
                    dateSort: _dateSort,
                    patientFilterId: _patientFilterId,
                    patients: bundle.patients,
                    recordCount: _filterReports(bundle.reports).length,
                    onQueryChanged: (value) => setState(() => _query = value),
                    onClear: () {
                      _searchCtrl.clear();
                      setState(() => _query = '');
                    },
                    onDateSortChanged: (value) =>
                        setState(() => _dateSort = value),
                    onPatientChanged: (value) => setState(
                      () => _patientFilterId = value ?? 'all',
                    ),
                  ),
                ),
                _buildReportList(bundle),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildReportList(_DoctorReportsBundle bundle) {
    if (bundle.reports.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: StatusView.empty(
          icon: Icons.assignment_outlined,
          title: 'No reports yet',
          subtitle: widget.patientName == null
              ? 'Reports will appear here once medical records are added for your patients.'
              : 'No reports are available for ${widget.patientName}.',
        ),
      );
    }

    final reports = _filterReports(bundle.reports);
    if (reports.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: StatusView.empty(
          icon: Icons.search_off,
          title: 'No matching reports',
          subtitle: 'Try another patient, date order, or keyword.',
        ),
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      sliver: SliverList.separated(
        itemCount: reports.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          return _ReportCard(report: reports[index]);
        },
      ),
    );
  }
}

class _DoctorReportsBundle {
  const _DoctorReportsBundle({
    required this.notADoctor,
    required this.reports,
    required this.patientCount,
    required this.patients,
  });

  final bool notADoctor;
  final List<_DoctorReport> reports;
  final int patientCount;
  final List<_PatientReportOption> patients;

  static Future<_DoctorReportsBundle> load({
    String? initialPatientId,
    String? initialPatientName,
  }) async {
    final client = SupabaseService.client;
    final doctorId = await SupabaseService.currentDoctorId();
    if (doctorId == null) {
      return const _DoctorReportsBundle(
        notADoctor: true,
        reports: [],
        patientCount: 0,
        patients: [],
      );
    }

    final patientNames = <String, String>{};
    final patientIds = <String>{};

    if (initialPatientId != null && initialPatientId.isNotEmpty) {
      patientIds.add(initialPatientId);
      if (initialPatientName != null && initialPatientName.isNotEmpty) {
        patientNames[initialPatientId] = initialPatientName;
      }
    } else {
      final appointmentRows = await client
          .from('appointments')
          .select('patient_id')
          .eq('doctor_id', doctorId);
      final prescriptionRows = await client
          .from('prescriptions')
          .select('patient_id')
          .eq('doctor_id', doctorId);

      for (final row in (appointmentRows as List)) {
        final id = row['patient_id']?.toString();
        if (id != null && id.isNotEmpty) patientIds.add(id);
      }
      for (final row in (prescriptionRows as List)) {
        final id = row['patient_id']?.toString();
        if (id != null && id.isNotEmpty) patientIds.add(id);
      }
    }

    if (patientIds.isEmpty) {
      return const _DoctorReportsBundle(
        notADoctor: false,
        reports: [],
        patientCount: 0,
        patients: [],
      );
    }

    final patientRows = await client
        .from('patients')
        .select(
          'id, profile:profiles!patients_profile_id_fkey(first_name, surname)',
        )
        .inFilter('id', patientIds.toList());

    for (final row in (patientRows as List)) {
      final id = row['id']?.toString();
      if (id == null) continue;
      final profile = row['profile'] as Map<String, dynamic>?;
      final firstName = profile?['first_name']?.toString() ?? '';
      final surname = profile?['surname']?.toString() ?? '';
      final name = '$firstName $surname'.trim();
      if (name.isNotEmpty) {
        patientNames[id] = name;
      }
    }

    final recordRows = await client
        .from('medical_records')
        .select(
          'id, patient_id, doctor_id, record_type, title, description, file_url, record_date, created_at',
        )
        .inFilter('patient_id', patientIds.toList())
        .order('record_date', ascending: false);

    final reports = <_DoctorReport>[];
    for (final row in (recordRows as List)) {
      final patientId = row['patient_id']?.toString() ?? '';
      reports.add(
        _DoctorReport.fromMap(
          row as Map<String, dynamic>,
          patientName: patientNames[patientId] ?? '',
        ),
      );
    }

    reports.sort((a, b) {
      final aDate = a.reportDate;
      final bDate = b.reportDate;
      if (aDate == null && bDate == null) return 0;
      if (aDate == null) return 1;
      if (bDate == null) return -1;
      return bDate.compareTo(aDate);
    });

    final recordCounts = <String, int>{};
    for (final report in reports) {
      recordCounts[report.patientId] =
          (recordCounts[report.patientId] ?? 0) + 1;
    }

    final patients = patientIds
        .map(
          (id) => _PatientReportOption(
            id: id,
            name: patientNames[id] ?? id,
            recordCount: recordCounts[id] ?? 0,
          ),
        )
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));

    return _DoctorReportsBundle(
      notADoctor: false,
      reports: reports,
      patientCount: patientIds.length,
      patients: patients,
    );
  }
}

class _PatientReportOption {
  const _PatientReportOption({
    required this.id,
    required this.name,
    required this.recordCount,
  });

  final String id;
  final String name;
  final int recordCount;
}

class _DoctorReport {
  const _DoctorReport({
    required this.id,
    required this.patientId,
    required this.patientName,
    required this.title,
    required this.type,
    required this.description,
    required this.reportDate,
    required this.fileUrl,
  });

  final String id;
  final String patientId;
  final String patientName;
  final String title;
  final String type;
  final String description;
  final DateTime? reportDate;
  final String? fileUrl;

  static _DoctorReport fromMap(
    Map<String, dynamic> row, {
    required String patientName,
  }) {
    final type = (row['record_type'] ?? '').toString().trim();
    final title = (row['title'] ?? '').toString().trim();
    final description = (row['description'] ?? '').toString().trim();
    final dateText = (row['record_date'] ?? row['created_at'] ?? '').toString();
    final parsedDate = DateTime.tryParse(dateText);
    final fileUrl = row['file_url']?.toString().trim();

    return _DoctorReport(
      id: row['id']?.toString() ?? '',
      patientId: row['patient_id']?.toString() ?? '',
      patientName: patientName,
      title: title,
      type: type,
      description: description,
      reportDate: parsedDate,
      fileUrl: fileUrl == null || fileUrl.isEmpty ? null : fileUrl,
    );
  }
}

extension _DoctorReportDisplay on _DoctorReport {
  String get displayTitle {
    if (title.isNotEmpty) return title;
    if (type.isNotEmpty) return type;
    if (id.isNotEmpty) return id;
    return patientId;
  }
}

class _ReportsHeader extends StatelessWidget {
  const _ReportsHeader({
    required this.totalReports,
    required this.patientCount,
  });

  final int totalReports;
  final int patientCount;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Doctor Report Viewing',
            style: TextStyle(
              color: context.cAccentReadable,
              fontSize: 26,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'View patient reports, notes, scans, and attached files from one doctor workspace.',
            style: TextStyle(color: context.cTextSecondary, height: 1.4),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _MetricTile(
                  label: 'Reports',
                  value: totalReports.toString(),
                  icon: Icons.assignment,
                  color: CorviaColors.accent,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _MetricTile(
                  label: 'Patients',
                  value: patientCount.toString(),
                  icon: Icons.people,
                  color: CorviaColors.success,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SearchAndFilters extends StatelessWidget {
  const _SearchAndFilters({
    required this.controller,
    required this.query,
    required this.dateSort,
    required this.patientFilterId,
    required this.patients,
    required this.recordCount,
    required this.onQueryChanged,
    required this.onClear,
    required this.onDateSortChanged,
    required this.onPatientChanged,
  });

  final TextEditingController controller;
  final String query;
  final String dateSort;
  final String patientFilterId;
  final List<_PatientReportOption> patients;
  final int recordCount;
  final ValueChanged<String> onQueryChanged;
  final VoidCallback onClear;
  final ValueChanged<String> onDateSortChanged;
  final ValueChanged<String?> onPatientChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: controller,
            style: TextStyle(color: context.cTextPrimary),
            decoration: InputDecoration(
              hintText: 'Search by patient, title, or note',
              prefixIcon: Icon(Icons.search, color: context.cAccentReadable),
              suffixIcon: query.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: onClear,
                    ),
            ),
            onChanged: onQueryChanged,
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: patientFilterId,
            isExpanded: true,
            dropdownColor: context.cBgSecondary,
            decoration: InputDecoration(
              labelText: 'Filter by patient',
              prefixIcon:
                  Icon(Icons.person_search, color: context.cAccentReadable),
            ),
            items: [
              const DropdownMenuItem(
                value: 'all',
                child: Text('All patients'),
              ),
              for (final patient in patients)
                DropdownMenuItem(
                  value: patient.id,
                  child: Text('${patient.name} (${patient.recordCount})'),
                ),
            ],
            onChanged: onPatientChanged,
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _RecordCountBadge(count: recordCount),
                const SizedBox(width: 8),
                _DateSortChip(
                  label: 'Newest date',
                  value: 'newest',
                  selected: dateSort == 'newest',
                  onSelected: onDateSortChanged,
                ),
                _DateSortChip(
                  label: 'Oldest date',
                  value: 'oldest',
                  selected: dateSort == 'oldest',
                  onSelected: onDateSortChanged,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ReportCard extends StatelessWidget {
  const _ReportCard({required this.report});

  final _DoctorReport report;

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('d MMM yyyy');
    final hasFile = report.fileUrl != null;
    final details = [
      if (report.patientName.isNotEmpty) report.patientName,
      if (report.reportDate != null) df.format(report.reportDate!.toLocal()),
    ];

    var expanded = false;
    return StatefulBuilder(
      builder: (context, setLocalState) {
        return Card(
          color: context.cBgSecondary,
          child: InkWell(
            onTap: () => setLocalState(() => expanded = !expanded),
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.all(16),
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
                          color: CorviaColors.accent.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          hasFile ? Icons.picture_as_pdf : Icons.description,
                          color: context.cAccentReadable,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              report.displayTitle,
                              style: TextStyle(
                                color: context.cTextPrimary,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            if (details.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                details.join(' | '),
                                style: TextStyle(color: context.cTextSecondary),
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (report.reportDate != null)
                        _ReportDateBadge(date: report.reportDate!),
                    ],
                  ),
                  if (expanded) ...[
                    if (report.description.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(
                        report.description,
                        style: TextStyle(
                            color: context.cTextSecondary, height: 1.35),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Icon(Icons.badge, color: context.cTextMuted, size: 18),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Patient ID: ${report.patientId}',
                            style: TextStyle(
                                color: context.cTextMuted, fontSize: 12),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (hasFile)
                          TextButton.icon(
                            icon: const Icon(Icons.open_in_new),
                            label: const Text('Open'),
                            onPressed: () => launchUrlString(report.fileUrl!),
                          ),
                      ],
                    ),
                  ] else ...[
                    const SizedBox(height: 12),
                    Text(
                      'Tap to expand',
                      style: TextStyle(color: context.cTextMuted, fontSize: 12),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.cBgSecondary,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.cDivider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color),
          const SizedBox(height: 10),
          Text(
            value,
            style: TextStyle(
              color: context.cTextPrimary,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(label, style: TextStyle(color: context.cTextSecondary)),
        ],
      ),
    );
  }
}

class _RecordCountBadge extends StatelessWidget {
  const _RecordCountBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: context.cBgSecondary,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: context.cDivider),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.list_alt, color: context.cAccentReadable, size: 18),
          const SizedBox(width: 6),
          Text(
            '$count records',
            style: TextStyle(
              color: context.cTextSecondary,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

class _DateSortChip extends StatelessWidget {
  const _DateSortChip({
    required this.label,
    required this.value,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final String value;
  final bool selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onSelected(value),
        selectedColor: CorviaColors.accent.withValues(alpha: 0.22),
        labelStyle: TextStyle(
          color: selected ? context.cAccentReadable : context.cTextSecondary,
          fontWeight: selected ? FontWeight.bold : FontWeight.normal,
        ),
        side: BorderSide(
          color: selected ? CorviaColors.accent : context.cDivider,
        ),
      ),
    );
  }
}

class _ReportDateBadge extends StatelessWidget {
  const _ReportDateBadge({required this.date});

  final DateTime date;

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('d MMM');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: CorviaColors.success.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: CorviaColors.success.withValues(alpha: 0.5)),
      ),
      child: Text(
        df.format(date.toLocal()),
        style: TextStyle(
          color: CorviaColors.success,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
