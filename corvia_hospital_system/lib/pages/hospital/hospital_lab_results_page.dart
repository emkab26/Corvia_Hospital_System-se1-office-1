import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../theme/app_theme.dart';
import '../../models/lab_release_state.dart';
import '../../widgets/status_view.dart';

class HospitalLabResultsPage extends StatefulWidget {
  const HospitalLabResultsPage({
    super.key,
    required this.hospitalId,
    required this.hospitalName,
  });

  final String hospitalId;
  final String hospitalName;

  @override
  State<HospitalLabResultsPage> createState() {
    return _HospitalLabResultsPageState();
  }
}

class _HospitalLabResultsPageState extends State<HospitalLabResultsPage> {
  static const Duration _requestTimeout = Duration(seconds: 20);

  final SupabaseClient _supabase = Supabase.instance.client;
  final TextEditingController _searchController = TextEditingController();

  bool _loading = true;
  bool _refreshing = false;

  String? _error;

  String _statusFilter = 'all';

  List<_HospitalLabResult> _results = const [];

  @override
  void initState() {
    super.initState();

    _loadResults(
      fullLoader: true,
    );
  }

  @override
  void dispose() {
    _searchController.dispose();

    super.dispose();
  }

  Future<void> _loadResults({
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
      final response = await _supabase
          .from('lab_results')
          .select()
          .eq(
            'hospital_id',
            widget.hospitalId,
          )
          .order(
            'created_at',
            ascending: false,
          )
          .timeout(
            _requestTimeout,
          );

      final rows = _rows(
        response,
      );

      var results = rows
          .map(
            _HospitalLabResult.fromMap,
          )
          .where(
            (result) => result.id.isNotEmpty,
          )
          .toList();

      results = await _attachNames(
        results,
      );

      results.sort(
        (
          first,
          second,
        ) {
          final firstDate = first.createdAt ?? DateTime(1970);
          final secondDate = second.createdAt ?? DateTime(1970);

          return secondDate.compareTo(firstDate);
        },
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _results = results;
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
            'Loading lab results took too long. Please check your connection and try again.';
      });
    } catch (error) {
      debugPrint(
        'HospitalLabResultsPage load failed: $error',
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _loading = false;
        _refreshing = false;
        _error = 'Hospital lab results could not be loaded. $error';
      });
    }
  }

  Future<List<_HospitalLabResult>> _attachNames(
    List<_HospitalLabResult> results,
  ) async {
    if (results.isEmpty) {
      return results;
    }

    final patientIds = results
        .map(
          (result) => result.patientId,
        )
        .where(
          (id) => id.isNotEmpty,
        )
        .toSet()
        .toList();

    final doctorIds = results
        .map(
          (result) => result.doctorId,
        )
        .where(
          (id) => id.isNotEmpty,
        )
        .toSet()
        .toList();

    final departmentIds = results
        .map(
          (result) => result.departmentId,
        )
        .where(
          (id) => id.isNotEmpty,
        )
        .toSet()
        .toList();

    final patientNames = await _loadPatientNames(
      patientIds,
    );

    final doctorNames = await _loadDoctorNames(
      doctorIds,
    );

    final departmentNames = await _loadDepartmentNames(
      departmentIds,
    );

    return results
        .map(
          (result) => result.copyWith(
            patientName: patientNames[result.patientId] ?? '',
            doctorName: doctorNames[result.doctorId] ?? '',
            departmentName: departmentNames[result.departmentId] ?? '',
          ),
        )
        .toList();
  }

  Future<Map<String, String>> _loadPatientNames(
    List<String> ids,
  ) async {
    if (ids.isEmpty) {
      return {};
    }

    try {
      final response = await _supabase
          .from('patients')
          .select()
          .inFilter(
            'id',
            ids,
          )
          .timeout(
            _requestTimeout,
          );

      final names = <String, String>{};

      for (final row in _rows(response)) {
        final id = _cleanText(row['id']);

        if (id.isEmpty) {
          continue;
        }

        names[id] = _displayName(
          row,
          fallback: 'Patient',
        );
      }

      return names;
    } catch (error) {
      debugPrint(
        'HospitalLabResultsPage patient-name load failed: $error',
      );

      return {};
    }
  }

  Future<Map<String, String>> _loadDoctorNames(
    List<String> ids,
  ) async {
    if (ids.isEmpty) {
      return {};
    }

    try {
      final response = await _supabase
          .from('doctors')
          .select()
          .inFilter(
            'id',
            ids,
          )
          .timeout(
            _requestTimeout,
          );

      final names = <String, String>{};

      for (final row in _rows(response)) {
        final id = _cleanText(row['id']);

        if (id.isEmpty) {
          continue;
        }

        final name = _displayName(
          row,
          fallback: 'Doctor',
        );

        names[id] = name.startsWith('Dr') ? name : 'Dr $name';
      }

      return names;
    } catch (error) {
      debugPrint(
        'HospitalLabResultsPage doctor-name load failed: $error',
      );

      return {};
    }
  }

  Future<Map<String, String>> _loadDepartmentNames(
    List<String> ids,
  ) async {
    if (ids.isEmpty) {
      return {};
    }

    try {
      final response = await _supabase
          .from('departments')
          .select()
          .inFilter(
            'id',
            ids,
          )
          .timeout(
            _requestTimeout,
          );

      final names = <String, String>{};

      for (final row in _rows(response)) {
        final id = _cleanText(row['id']);

        if (id.isEmpty) {
          continue;
        }

        final name = _firstText(
          [
            row['name'],
            row['department_name'],
            row['title'],
          ],
          fallback: '',
        );

        if (name.isNotEmpty) {
          names[id] = name;
        }
      }

      return names;
    } catch (error) {
      debugPrint(
        'HospitalLabResultsPage department-name load failed: $error',
      );

      return {};
    }
  }

  List<_HospitalLabResult> get _filteredResults {
    final query = _searchController.text.trim().toLowerCase();

    final filtered = _results.where(
      (result) {
        final statusMatch =
            _statusFilter == 'all' || result.status == _statusFilter;

        final searchText = [
          result.patientName,
          result.testName,
          result.status,
          result.result,
          result.fileUrl,
          result.doctorName,
          result.departmentName,
          result.patientId,
        ].join(' ').toLowerCase();

        final queryMatch = query.isEmpty || searchText.contains(query);

        return statusMatch && queryMatch;
      },
    ).toList();

    filtered.sort(
      (
        first,
        second,
      ) {
        final firstDate = first.createdAt ?? DateTime(1970);
        final secondDate = second.createdAt ?? DateTime(1970);

        return secondDate.compareTo(firstDate);
      },
    );

    return filtered;
  }

  String _formatDate(
    DateTime? date,
  ) {
    if (date == null) {
      return 'Date unavailable';
    }

    return DateFormat('EEE, d MMM yyyy • HH:mm').format(
      date.toLocal(),
    );
  }

  Color _statusColor(
    String status,
  ) {
    switch (status) {
      case 'completed':
        return CorviaColors.success;

      case 'in_progress':
        return CorviaColors.warning;

      case 'pending':
        return Colors.orange.shade700;

      case 'cancelled':
      case 'rejected':
        return CorviaColors.danger;

      default:
        return context.cAccentReadable;
    }
  }

  String _prettyStatus(
    String status,
  ) {
    final cleaned = status
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

  @override
  Widget build(
    BuildContext context,
  ) {
    return Scaffold(
      backgroundColor: context.cBgPrimary,
      appBar: AppBar(
        title: const Text(
          'Hospital Lab Results',
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading || _refreshing
                ? null
                : () {
                    _loadResults(
                      fullLoader: false,
                    );
                  },
            icon: const Icon(
              Icons.refresh_rounded,
            ),
          ),
        ],
      ),
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
    if (_loading && _results.isEmpty) {
      return StatusView.loading(
        message: 'Loading hospital lab results...',
      );
    }

    if (_error != null && _results.isEmpty) {
      return StatusView.error(
        friendlyMessage: _error!,
        onRetry: () {
          _loadResults(
            fullLoader: true,
          );
        },
      );
    }

    return RefreshIndicator(
      onRefresh: () {
        return _loadResults(
          fullLoader: false,
        );
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(
          18,
        ),
        children: [
          _HeaderCard(
            hospitalName: widget.hospitalName,
            totalCount: _results.length,
            pendingCount: _results
                .where(
                  (result) => result.status == 'pending',
                )
                .length,
            inProgressCount: _results
                .where(
                  (result) => result.status == 'in_progress',
                )
                .length,
            completedCount: _results
                .where(
                  (result) => result.status == 'completed',
                )
                .length,
          ),
          const SizedBox(height: 16),
          _buildFilters(),
          const SizedBox(height: 16),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(
                bottom: 12,
              ),
              child: _InlineError(
                message: _error!,
              ),
            ),
          _buildResultsList(),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildFilters() {
    return Container(
      padding: const EdgeInsets.all(
        14,
      ),
      decoration: BoxDecoration(
        color: context.cBgSecondary,
        borderRadius: BorderRadius.circular(
          16,
        ),
        border: Border.all(
          color: context.cDivider,
        ),
      ),
      child: Column(
        children: [
          TextField(
            controller: _searchController,
            onChanged: (_) {
              setState(() {});
            },
            style: TextStyle(
              color: context.cTextPrimary,
            ),
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search_rounded),
              labelText: 'Search lab results',
              hintText: 'Patient, test name, doctor, result or status',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _FilterChipButton(
                  label: 'All',
                  selected: _statusFilter == 'all',
                  onTap: () {
                    setState(() {
                      _statusFilter = 'all';
                    });
                  },
                ),
                _FilterChipButton(
                  label: 'Pending',
                  selected: _statusFilter == 'pending',
                  onTap: () {
                    setState(() {
                      _statusFilter = 'pending';
                    });
                  },
                ),
                _FilterChipButton(
                  label: 'In Progress',
                  selected: _statusFilter == 'in_progress',
                  onTap: () {
                    setState(() {
                      _statusFilter = 'in_progress';
                    });
                  },
                ),
                _FilterChipButton(
                  label: 'Completed',
                  selected: _statusFilter == 'completed',
                  onTap: () {
                    setState(() {
                      _statusFilter = 'completed';
                    });
                  },
                ),
                TextButton.icon(
                  onPressed: () {
                    setState(() {
                      _searchController.clear();
                      _statusFilter = 'all';
                    });
                  },
                  icon: const Icon(Icons.filter_alt_off_rounded),
                  label: const Text('Clear'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResultsList() {
    final results = _filteredResults;

    if (results.isEmpty) {
      return StatusView.empty(
        icon: Icons.science_outlined,
        title: 'No lab results found',
        subtitle: _results.isEmpty
            ? 'Lab results linked to this hospital will appear here.'
            : 'Try changing your search or filter.',
        onRetry: () {
          _loadResults(
            fullLoader: false,
          );
        },
      );
    }

    return Column(
      children: [
        for (var index = 0; index < results.length; index++) ...[
          _LabResultCard(
            lab: results[index],
            statusColor: _statusColor(
              results[index].status,
            ),
            statusLabel: _prettyStatus(
              results[index].status,
            ),
            dateLabel: _formatDate(
              results[index].createdAt,
            ),
          ),
          if (index != results.length - 1)
            const SizedBox(
              height: 12,
            ),
        ],
      ],
    );
  }
}

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({
    required this.hospitalName,
    required this.totalCount,
    required this.pendingCount,
    required this.inProgressCount,
    required this.completedCount,
  });

  final String hospitalName;
  final int totalCount;
  final int pendingCount;
  final int inProgressCount;
  final int completedCount;

  @override
  Widget build(
    BuildContext context,
  ) {
    return Container(
      padding: const EdgeInsets.all(
        18,
      ),
      decoration: BoxDecoration(
        gradient: context.cBgGradient,
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
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: Colors.blueAccent.withValues(
                alpha: 0.14,
              ),
              borderRadius: BorderRadius.circular(
                16,
              ),
            ),
            child: const Icon(
              Icons.science_rounded,
              color: Colors.blueAccent,
              size: 30,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Lab Results Management',
                  style: TextStyle(
                    color: context.cTextPrimary,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  hospitalName,
                  style: TextStyle(
                    color: context.cTextSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _CountPill(
                      label: 'Total',
                      value: totalCount,
                      color: context.cAccentReadable,
                    ),
                    _CountPill(
                      label: 'Pending',
                      value: pendingCount,
                      color: Colors.orange.shade700,
                    ),
                    _CountPill(
                      label: 'In Progress',
                      value: inProgressCount,
                      color: CorviaColors.warning,
                    ),
                    _CountPill(
                      label: 'Completed',
                      value: completedCount,
                      color: CorviaColors.success,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LabResultCard extends StatelessWidget {
  const _LabResultCard({
    required this.lab,
    required this.statusColor,
    required this.statusLabel,
    required this.dateLabel,
  });

  final _HospitalLabResult lab;
  final Color statusColor;
  final String statusLabel;
  final String dateLabel;

  bool get _hasResult {
    return lab.result.trim().isNotEmpty;
  }

  bool get _hasFile {
    return lab.fileUrl.trim().isNotEmpty;
  }

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

              final titleBlock = Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      lab.testName,
                      style: TextStyle(
                        color: context.cTextPrimary,
                        fontWeight: FontWeight.w900,
                        fontSize: 17,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      lab.patientName.isEmpty
                          ? 'Patient linked'
                          : lab.patientName,
                      style: TextStyle(
                        color: context.cTextSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      dateLabel,
                      style: TextStyle(
                        color: context.cTextMuted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              );

              final status = _StatusPill(
                label: statusLabel,
                color: statusColor,
              );

              if (compact) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _LeadingIcon(
                          color: statusColor,
                        ),
                        const SizedBox(width: 12),
                        titleBlock,
                      ],
                    ),
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerRight,
                      child: status,
                    ),
                  ],
                );
              }

              return Row(
                children: [
                  _LeadingIcon(
                    color: statusColor,
                  ),
                  const SizedBox(width: 12),
                  titleBlock,
                  const SizedBox(width: 12),
                  status,
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (lab.doctorName.isNotEmpty)
                _MetaChip(
                  icon: Icons.person_outline_rounded,
                  label: lab.doctorName,
                ),
              if (lab.departmentName.isNotEmpty)
                _MetaChip(
                  icon: Icons.domain_rounded,
                  label: lab.departmentName,
                ),
              _MetaChip(
                icon: _hasFile
                    ? Icons.picture_as_pdf_outlined
                    : Icons.description_outlined,
                label: _hasFile ? 'Document linked' : 'No document',
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_hasResult)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(
                12,
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
                lab.result,
                maxLines: 5,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: context.cTextSecondary,
                  height: 1.35,
                ),
              ),
            )
          else
            _NoticeBox(
              icon: Icons.pending_actions_rounded,
              color: statusColor,
              title: lab.status == 'completed'
                  ? 'Completed without result text'
                  : 'Awaiting result details',
              message: lab.status == 'completed'
                  ? 'This result is marked completed, but no structured result text is stored yet.'
                  : 'The assigned laboratory team will enter and release the result when processing is complete.',
            ),
          const SizedBox(height: 14),
          Text(
            lab.release.title,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 3),
          Text(lab.release.guidance),
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(
                Icons.admin_panel_settings_outlined,
                color: context.cTextSecondary,
                size: 17,
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  'Administrative oversight only. Collection, processing, and result release are performed by nursing and laboratory staff.',
                  style: TextStyle(
                    color: context.cTextSecondary,
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LeadingIcon extends StatelessWidget {
  const _LeadingIcon({
    required this.color,
  });

  final Color color;

  @override
  Widget build(
    BuildContext context,
  ) {
    return Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        color: color.withValues(
          alpha: 0.11,
        ),
        borderRadius: BorderRadius.circular(
          14,
        ),
      ),
      child: Icon(
        Icons.science_rounded,
        color: color,
      ),
    );
  }
}

class _FilterChipButton extends StatelessWidget {
  const _FilterChipButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(
    BuildContext context,
  ) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      selectedColor: context.cAccentReadable,
      backgroundColor: context.cBgPrimary,
      labelStyle: TextStyle(
        color: selected ? Colors.white : context.cTextPrimary,
        fontWeight: FontWeight.w700,
      ),
      side: BorderSide(
        color: selected ? context.cAccentReadable : context.cDivider,
      ),
      onSelected: (_) {
        onTap();
      },
    );
  }
}

class _CountPill extends StatelessWidget {
  const _CountPill({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final int value;
  final Color color;

  @override
  Widget build(
    BuildContext context,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: color.withValues(
          alpha: 0.11,
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
        '$label: $value',
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({
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
        horizontal: 10,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: color.withValues(
          alpha: 0.12,
        ),
        borderRadius: BorderRadius.circular(
          999,
        ),
        border: Border.all(
          color: color.withValues(
            alpha: 0.35,
          ),
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w900,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(
    BuildContext context,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 9,
        vertical: 7,
      ),
      decoration: BoxDecoration(
        color: context.cBgPrimary,
        borderRadius: BorderRadius.circular(
          999,
        ),
        border: Border.all(
          color: context.cDivider,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            color: context.cAccentReadable,
            size: 15,
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: context.cTextSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _NoticeBox extends StatelessWidget {
  const _NoticeBox({
    required this.icon,
    required this.color,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String message;

  @override
  Widget build(
    BuildContext context,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(
        12,
      ),
      decoration: BoxDecoration(
        color: color.withValues(
          alpha: 0.08,
        ),
        borderRadius: BorderRadius.circular(
          14,
        ),
        border: Border.all(
          color: color.withValues(
            alpha: 0.28,
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            color: color,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: context.cTextPrimary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  message,
                  style: TextStyle(
                    color: context.cTextSecondary,
                    fontSize: 12.5,
                    height: 1.35,
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

class _InlineError extends StatelessWidget {
  const _InlineError({
    required this.message,
  });

  final String message;

  @override
  Widget build(
    BuildContext context,
  ) {
    return Container(
      padding: const EdgeInsets.all(
        12,
      ),
      decoration: BoxDecoration(
        color: CorviaColors.danger.withValues(
          alpha: 0.08,
        ),
        borderRadius: BorderRadius.circular(
          14,
        ),
        border: Border.all(
          color: CorviaColors.danger.withValues(
            alpha: 0.28,
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
              message,
              style: TextStyle(
                color: context.cTextPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HospitalLabResult {
  const _HospitalLabResult({
    required this.id,
    required this.patientId,
    required this.doctorId,
    required this.hospitalId,
    required this.departmentId,
    required this.patientName,
    required this.doctorName,
    required this.departmentName,
    required this.testName,
    required this.result,
    required this.fileUrl,
    required this.status,
    required this.createdAt,
    required this.release,
  });

  final String id;
  final String patientId;
  final String doctorId;
  final String hospitalId;
  final String departmentId;

  final String patientName;
  final String doctorName;
  final String departmentName;

  final String testName;
  final String result;
  final String fileUrl;
  final String status;

  final DateTime? createdAt;
  final LabReleaseState release;

  _HospitalLabResult copyWith({
    String? patientName,
    String? doctorName,
    String? departmentName,
  }) {
    return _HospitalLabResult(
      id: id,
      patientId: patientId,
      doctorId: doctorId,
      hospitalId: hospitalId,
      departmentId: departmentId,
      patientName: patientName ?? this.patientName,
      doctorName: doctorName ?? this.doctorName,
      departmentName: departmentName ?? this.departmentName,
      testName: testName,
      result: result,
      fileUrl: fileUrl,
      status: status,
      createdAt: createdAt,
      release: release,
    );
  }

  factory _HospitalLabResult.fromMap(
    Map<String, dynamic> map,
  ) {
    return _HospitalLabResult(
      release: LabReleaseState.fromMap(map),
      id: _cleanText(
        map['id'],
      ),
      patientId: _cleanText(
        map['patient_id'],
      ),
      doctorId: _cleanText(
        map['doctor_id'],
      ),
      hospitalId: _cleanText(
        map['hospital_id'],
      ),
      departmentId: _cleanText(
        map['department_id'],
      ),
      patientName: '',
      doctorName: '',
      departmentName: '',
      testName: _firstText(
        [
          map['test_name'],
          map['name'],
          map['title'],
          map['test'],
        ],
        fallback: 'Laboratory Test',
      ),
      result: _valueText(
        map['result_text'] ?? map['result'] ?? map['results'],
      ),
      fileUrl: _firstText(
        [
          map['file_url'],
          map['result_url'],
          map['pdf_url'],
          map['document_url'],
        ],
        fallback: '',
      ),
      status: _normaliseStatus(
        _firstText(
          [
            map['status'],
          ],
          fallback: 'pending',
        ),
      ),
      createdAt: _firstDate(
        map,
        const [
          'result_date',
          'completed_at',
          'reviewed_at',
          'updated_at',
          'created_at',
        ],
      ),
    );
  }

  static String _normaliseStatus(
    String value,
  ) {
    final status =
        value.trim().toLowerCase().replaceAll('-', '_').replaceAll(' ', '_');

    const completed = {
      'completed',
      'complete',
      'done',
      'finalized',
      'finalised',
      'finished',
      'reviewed',
    };

    const inProgress = {
      'in_progress',
      'processing',
      'started',
      'collecting',
      'collected',
      'sent',
      'received',
    };

    const cancelled = {
      'cancelled',
      'canceled',
      'rejected',
      'void',
    };

    if (completed.contains(status)) {
      return 'completed';
    }

    if (inProgress.contains(status)) {
      return 'in_progress';
    }

    if (cancelled.contains(status)) {
      return 'cancelled';
    }

    if (status.isEmpty) {
      return 'pending';
    }

    return status;
  }

  static DateTime? _firstDate(
    Map<String, dynamic> map,
    List<String> columns,
  ) {
    for (final column in columns) {
      final parsed = DateTime.tryParse(
        map[column]?.toString() ?? '',
      );

      if (parsed != null) {
        return parsed;
      }
    }

    return null;
  }

  static String _valueText(
    dynamic value,
  ) {
    if (value == null) {
      return '';
    }

    if (value is String) {
      return value.trim();
    }

    if (value is num || value is bool) {
      return value.toString();
    }

    return value.toString().trim();
  }
}

String _displayName(
  Map<String, dynamic> row, {
  required String fallback,
}) {
  final direct = _firstText(
    [
      row['full_name'],
      row['name'],
      row['display_name'],
      row['patient_name'],
      row['doctor_name'],
    ],
    fallback: '',
  );

  if (direct.isNotEmpty) {
    return direct;
  }

  final firstName = _firstText(
    [
      row['first_name'],
      row['firstname'],
      row['given_name'],
    ],
    fallback: '',
  );

  final surname = _firstText(
    [
      row['surname'],
      row['last_name'],
      row['lastname'],
      row['family_name'],
    ],
    fallback: '',
  );

  final combined = '$firstName $surname'.trim();

  if (combined.isNotEmpty) {
    return combined;
  }

  final email = _cleanText(
    row['email'],
  );

  if (email.isNotEmpty) {
    return email;
  }

  return fallback;
}

String _firstText(
  List<dynamic> values, {
  required String fallback,
}) {
  for (final value in values) {
    final text = _cleanText(
      value,
    );

    if (text.isNotEmpty) {
      return text;
    }
  }

  return fallback;
}

String _cleanText(
  dynamic value,
) {
  if (value == null) {
    return '';
  }

  final text = value.toString().trim();

  if (text.isEmpty || text.toLowerCase() == 'null') {
    return '';
  }

  return text;
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
