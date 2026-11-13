import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../services/supabase_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/status_view.dart';

class PatientRecordsPage extends StatefulWidget {
  const PatientRecordsPage({super.key});

  @override
  State<PatientRecordsPage> createState() => _PatientRecordsPageState();
}

class _PatientRecordsPageState extends State<PatientRecordsPage> {
  // Number of records to fetch per page.
  static const int _pageSize = 10;
  Future<_PatientRecordsBundle>? _future;
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();

  // Pagination, sorting, and filtering state for medical records.
  final List<Map<String, dynamic>> _records = [];
  int _currentPage = 0;
  bool _hasMore = true;
  bool _loadingMore = false;
  bool _hasPreviousPage = false;
  bool _sortAscending = false;
  DateTime? _filterDate;
  Object? _recordsError;
  StackTrace? _recordsErrorStackTrace;

  // Status filter
  String? _selectedStatus;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  // Full reset
  Future<void> _refresh() async {
    setState(() {
      _records.clear();
      _currentPage = 0;
      _hasMore = true;
      _loadingMore = false;
      _hasPreviousPage = false;
      _recordsError = null;
      _recordsErrorStackTrace = null;
      _future = _PatientRecordsBundle.loadMeta();
      _selectedStatus = null;
    });
    await _loadNextPage();
  }

  Future<void> _reloadRecords() async {
    setState(() {
      _records.clear();
      _currentPage = 0;
      _hasMore = true;
      _loadingMore = false;
      _hasPreviousPage = false;
      _recordsError = null;
      _recordsErrorStackTrace = null;
    });
    await _loadNextPage();
  }

  Future<void> _clearFilters() async {
    _searchController.clear();
    setState(() {
      _filterDate = null;
      _selectedStatus = null;
    });
    await _reloadRecords();
  }

  Future<void> _nextPage() async {
    if (!_hasMore || _loadingMore) return;
    _currentPage++;
    await _loadNextPage();
  }

  Future<void> _previousPage() async {
    if (_currentPage == 0 || _loadingMore) return;
    _currentPage--;
    await _loadNextPage();
  }

  Future<void> _loadNextPage() async {
    if (_loadingMore) return;
    setState(() {
      _loadingMore = true;
      _recordsError = null;
      _recordsErrorStackTrace = null;
    });

    try {
      final patientId = await SupabaseService.currentPatientId();
      if (patientId == null) {
        if (!mounted) return;
        setState(() {
          _loadingMore = false;
          _hasMore = false;
        });
        return;
      }

      final from = _currentPage * _pageSize;
      final to = from + _pageSize - 1;
      final page = await _fetchPatientRecordsPage(patientId, from, to);
      if (!mounted) return;
      setState(() {
        _records
          ..clear()
          ..addAll(page);
        _hasMore = page.length == _pageSize;
        _hasPreviousPage = _currentPage > 0;
        _loadingMore = false;
      });
    } catch (error, stackTrace) {
      debugPrint(
        '[PatientRecords] records load failed: $error\n$stackTrace',
      );
      if (!mounted) return;
      setState(() {
        _loadingMore = false;
        _hasMore = false;
        _recordsError = error;
        _recordsErrorStackTrace = stackTrace;
      });
    }
  }

  Future<List<Map<String, dynamic>>> _fetchPatientRecordsPage(
    String patientId,
    int from,
    int to,
  ) async {
    Future<List<Map<String, dynamic>>> queryRecords({
      required bool includeStatus,
    }) async {
      var query = SupabaseService.client
          .from('medical_records')
          .select(
            includeStatus
                ? 'id, record_type, title, description, file_url, record_date, doctor_id, status'
                : 'id, record_type, title, description, file_url, record_date, doctor_id',
          )
          .eq('patient_id', patientId);

      final searchTerm = _searchController.text.trim();
      if (searchTerm.isNotEmpty) {
        query = query.or(
          'title.ilike.%$searchTerm%,record_type.ilike.%$searchTerm%,description.ilike.%$searchTerm%',
        );
      }

      if (_filterDate != null) {
        final startOfDay = DateTime(
          _filterDate!.year,
          _filterDate!.month,
          _filterDate!.day,
        ).toIso8601String();
        final endOfDay = DateTime(
          _filterDate!.year,
          _filterDate!.month,
          _filterDate!.day,
          23,
          59,
          59,
        ).toIso8601String();
        query =
            query.gte('record_date', startOfDay).lte('record_date', endOfDay);
      }

      // Status filter
      if (_selectedStatus != null && _selectedStatus != 'all') {
        final selectedStatus = _selectedStatus!;
        query = query.eq('status', selectedStatus);
      }

      final res = await query
          .order('record_date', ascending: _sortAscending)
          .range(from, to);
      return List<Map<String, dynamic>>.from(res as List);
    }

    try {
      return await queryRecords(includeStatus: true);
    } catch (e, st) {
      debugPrint(
        '[PatientRecords] status query failed, retrying without status: $e\n$st',
      );
      try {
        final page = await queryRecords(includeStatus: false);
        return page;
      } catch (nested, nestedSt) {
        debugPrint(
          '[PatientRecords] fallback query failed: $nested\n$nestedSt',
        );
        Error.throwWithStackTrace(nested, nestedSt);
      }
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _filterDate ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (picked != null && picked != _filterDate) {
      setState(() {
        _filterDate = picked;
      });
      _reloadRecords();
    }
  }

  // Status filter options
  final Map<String, String> _statusOptions = {
    'all': 'All Statuses',
    'active': 'Active',
    'draft': 'Draft',
    'incomplete': 'Incomplete',
    'archived': 'Archived',
    'needs_review': 'Needs Review',
  };

  // Wrapper for status views
  Widget _buildScrollableStatus(Widget child) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        Container(
          height: MediaQuery.of(context).size.height * 0.7,
          alignment: Alignment.center,
          child: child,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Patient Records'),
        actions: [
          IconButton(
            icon: const Icon(Icons.print_outlined),
            tooltip: 'Print Summary',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const PatientRecordSummaryPage(),
                ),
              );
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<_PatientRecordsBundle>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return _buildScrollableStatus(
                StatusView.loading(message: 'Loading your records...'),
              );
            }
            if (snap.hasError) {
              return _buildScrollableStatus(
                StatusView.error(
                  friendlyMessage: "We couldn't load your records.",
                  error: snap.error,
                  stackTrace: snap.stackTrace,
                  onRetry: _refresh,
                ),
              );
            }
            if (!snap.hasData || snap.data == null) {
              return _buildScrollableStatus(
                StatusView.loading(message: 'Processing data...'),
              );
            }
            final bundle = snap.data!;

            // Updated empty-state wording and retained icon and retry action
            if (bundle.patientId == null) {
              return _buildScrollableStatus(
                StatusView.empty(
                  icon: Icons.person_outline,
                  title: 'No patient profile found',
                  subtitle:
                      'You need to complete patient registration before records can be saved.',
                  onRetry: _refresh,
                ),
              );
            }

            final items = <_PatientRecordListItem>[
              const _SectionItem('Immunizations'),
              _ImmunizationsItem(bundle.immunizations),
              const _SectionItem('Risk Factors'),
              _RiskFactorsItem(bundle.riskFactors),
              _SectionItem(
                'Records',
                trailing: PopupMenuButton<bool>(
                  initialValue: _sortAscending,
                  icon: const Icon(Icons.sort_rounded),
                  tooltip: 'Sort records',
                  onSelected: (ascending) {
                    if (_sortAscending != ascending) {
                      setState(() {
                        _sortAscending = ascending;
                      });
                      _reloadRecords();
                    }
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(
                      value: false,
                      child: Text('Newest First'),
                    ),
                    PopupMenuItem(
                      value: true,
                      child: Text('Oldest First'),
                    ),
                  ],
                ),
              ),
              if (_recordsError != null)
                _RecordsErrorItem(
                  error: _recordsError!,
                  stackTrace: _recordsErrorStackTrace,
                  onRetry: _loadNextPage,
                )
              else ...[
                // Filter bar with status filter icon + dropdown menu
                _FilterBarItem(
                  searchController: _searchController,
                  onSearch: _reloadRecords,
                  selectedDate: _filterDate,
                  onPickDate: _pickDate,
                  onClearDate: () {
                    setState(() => _filterDate = null);
                    _reloadRecords();
                  },
                  selectedStatus: _selectedStatus,
                  onStatusChanged: (value) {
                    setState(() => _selectedStatus = value);
                    _reloadRecords();
                  },
                  statusOptions: _statusOptions,
                ),
                if (_records.isEmpty &&
                    !_loadingMore &&
                    (_searchController.text.isNotEmpty ||
                        _filterDate != null ||
                        (_selectedStatus != null && _selectedStatus != 'all')))
                  const _NoFilterResultsItem()
                else if (_records.isEmpty && !_loadingMore)
                  const _NoRecordsItem(),
                ..._records.map(_RecordItem.new),
                if (_loadingMore) const _LoadingItem(),
                if (!_hasMore && _records.isNotEmpty) const _EndItem(),
                const _PaginationControlsItem(),
              ],
              const _SpacerItem(),
            ];

            return ListView.builder(
              controller: _scrollController,
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(vertical: 16),
              itemCount: items.length,
              itemBuilder: (context, index) {
                return items[index].build(context);
              },
            );
          },
        ),
      ),
    );
  }
}

abstract class _PatientRecordListItem {
  const _PatientRecordListItem();
  Widget build(BuildContext context);
}

class _SectionItem extends _PatientRecordListItem {
  const _SectionItem(this.title, {this.trailing});
  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title, style: CorviaTextStyles.heading),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

class _FilterBarItem extends _PatientRecordListItem {
  const _FilterBarItem({
    required this.searchController,
    required this.onSearch,
    required this.selectedDate,
    required this.onPickDate,
    required this.onClearDate,
    required this.selectedStatus,
    required this.onStatusChanged,
    required this.statusOptions,
  });

  final TextEditingController searchController;
  final VoidCallback onSearch;
  final DateTime? selectedDate;
  final VoidCallback onPickDate;
  final VoidCallback onClearDate;
  final String? selectedStatus;
  final ValueChanged<String?> onStatusChanged;
  final Map<String, String> statusOptions;

  @override
  Widget build(BuildContext context) {
    final cardColor = Theme.of(context).cardColor;
    final hasStatusFilter = selectedStatus != null && selectedStatus != 'all';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: searchController,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => onSearch(),
              decoration: InputDecoration(
                hintText: 'Search records by name...',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: cardColor,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                // BUG FIX: ValueListenableBuilder only wraps the suffix icon, not the TextField
                suffixIcon: ValueListenableBuilder<TextEditingValue>(
                  valueListenable: searchController,
                  builder: (context, value, child) {
                    if (value.text.isEmpty) return const SizedBox.shrink();
                    return IconButton(
                      icon: const Icon(Icons.close, size: 20),
                      onPressed: () {
                        searchController.clear();
                        onSearch();
                      },
                    );
                  },
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Date filter
          InkWell(
            onTap: onPickDate,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: selectedDate != null
                    ? CorviaColors.accent.withValues(alpha: 0.15)
                    : cardColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: selectedDate != null
                      ? CorviaColors.accent
                      : Colors.transparent,
                  width: 1.5,
                ),
              ),
              child: Icon(
                Icons.calendar_month,
                color: selectedDate != null ? CorviaColors.accent : Colors.grey,
              ),
            ),
          ),
          if (selectedDate != null) ...[
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.clear, color: Colors.redAccent),
              onPressed: onClearDate,
              tooltip: 'Clear Date Filter',
            ),
          ],
          const SizedBox(width: 8),
          // Status Filter Icon Button with Dropdown Menu
          PopupMenuButton<String>(
            onSelected: onStatusChanged,
            initialValue: selectedStatus ?? 'all',
            icon: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: hasStatusFilter
                    ? CorviaColors.accent.withValues(alpha: 0.15)
                    : cardColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: hasStatusFilter
                      ? CorviaColors.accent
                      : Colors.transparent,
                  width: 1.5,
                ),
              ),
              child: Icon(
                Icons.filter_alt, //funnel icon
                color: hasStatusFilter ? CorviaColors.accent : Colors.grey,
              ),
            ),
            itemBuilder: (context) {
              return statusOptions.entries.map((entry) {
                return PopupMenuItem<String>(
                  value: entry.key,
                  child: Text(
                    entry.value,
                    style: const TextStyle(color: Colors.black),
                  ),
                );
              }).toList();
            },
          ),
          if (hasStatusFilter) ...[
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.clear, color: Colors.redAccent),
              onPressed: () {
                onStatusChanged('all');
              },
              tooltip: 'Clear Status Filter',
            ),
          ],
        ],
      ),
    );
  }
}

class _RecordsErrorItem extends _PatientRecordListItem {
  const _RecordsErrorItem({
    required this.error,
    required this.stackTrace,
    required this.onRetry,
  });

  final Object error;
  final StackTrace? stackTrace;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Card(
        child: StatusView.error(
          friendlyMessage: "We couldn't load your medical records.",
          error: error,
          stackTrace: stackTrace,
          onRetry: onRetry,
        ),
      ),
    );
  }
}

class _NoRecordsItem extends _PatientRecordListItem {
  const _NoRecordsItem();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      child: Column(
        children: [
          Icon(
            Icons.folder_open_outlined,
            size: 72,
            color: context.cTextMuted,
          ),
          const SizedBox(height: 20),
          Text(
            'No medical records yet',
            style: CorviaTextStyles.heading,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 10),
          Text(
            'Records added by your authorised care team will appear here.',
            textAlign: TextAlign.center,
            style: TextStyle(color: context.cTextSecondary),
          ),
        ],
      ),
    );
  }
}

class _NoFilterResultsItem extends _PatientRecordListItem {
  const _NoFilterResultsItem();

  @override
  Widget build(BuildContext context) {
    final state = context.findAncestorStateOfType<_PatientRecordsPageState>();

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: 24,
        vertical: 40,
      ),
      child: Center(
        child: Column(
          children: [
            Icon(
              Icons.search_off_rounded,
              size: 72,
              color: CorviaColors.textSecondary,
            ),
            const SizedBox(height: 20),
            Text(
              'No patient records found',
              style: CorviaTextStyles.heading,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            Text(
              'We couldn’t find any patient records matching your search. Try a different name or clear your filters.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: CorviaColors.textSecondary,
              ),
            ),
            const SizedBox(height: 20),
            OutlinedButton(
              onPressed: state?._clearFilters,
              child: const Text('Clear Search'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ImmunizationsItem extends _PatientRecordListItem {
  const _ImmunizationsItem(this.items);
  final List<String> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16),
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: InlineStatus(
              icon: Icons.vaccines,
              message: 'No immunizations recorded yet.',
            ),
          ),
        ),
      );
    }
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          for (final item in items)
            ListTile(
              leading: Icon(Icons.vaccines, color: CorviaColors.success),
              title: Text(item, style: const TextStyle(color: Colors.white)),
              dense: true,
            ),
        ],
      ),
    );
  }
}

class _RiskFactorsItem extends _PatientRecordListItem {
  const _RiskFactorsItem(this.items);
  final List<String> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16),
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: InlineStatus(
              icon: Icons.warning_amber,
              message: 'No risk factors recorded yet.',
            ),
          ),
        ),
      );
    }
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          for (final item in items)
            ListTile(
              leading: const Icon(Icons.warning, color: CorviaColors.warning),
              title: Text(item, style: const TextStyle(color: Colors.white)),
              dense: true,
            ),
        ],
      ),
    );
  }
}

class _RecordItem extends _PatientRecordListItem {
  const _RecordItem(this.record);
  final Map<String, dynamic> record;

  @override
  Widget build(BuildContext context) {
    return PatientRecordCard(record: record);
  }
}
// Added responsive layout handling for patient record cards across mobile, tablet and web

class PatientRecordCard extends StatelessWidget {
  const PatientRecordCard({
    super.key,
    required this.record,
  });

  final Map<String, dynamic> record;

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;

    final bool isMobile = screenWidth < 600;
    final bool isTablet = screenWidth >= 600 && screenWidth < 1024;
    final df = DateFormat('d MMM yyyy');
    final updateDf = DateFormat('d MMM yyyy, HH:mm');
    final recordDateRaw = record['record_date'];
    final String recordType =
        (record['record_type'] ?? 'general').toString().trim();
    final String dateString = recordDateRaw != null
        ? df.format(DateTime.parse(recordDateRaw.toString()).toLocal())
        : '';

    // --- TASK WORK: Added Safe Summary Ref Code ---
    final String refCode =
        'Ref: ${record['id'].toString().substring(0, 4).toUpperCase()}';
    final String subtitleText = '$refCode • $recordType • $dateString';
    final String rawStatus =
        (record['status'] ?? 'active').toString().trim().toLowerCase();

    // SMART FALLBACK: Use existing record_date to represent the "Last updated" metric
    final fallbackDate = recordDateRaw;

    final String updatedString = fallbackDate != null
        ? updateDf.format(DateTime.parse(fallbackDate.toString()).toLocal())
        : 'Unknown';

    return Card(
      margin: EdgeInsets.symmetric(
        horizontal: isMobile ? 16 : 32,
        vertical: isTablet ? 6 : 8,
      ),
      child: ExpansionTile(
        leading: Icon(
          Icons.description,
          size: isMobile ? 24 : 30,
          color: CorviaColors.accentLight,
        ),
        title: Text(
          (record['title'] ?? 'Record').toString(),
          style: TextStyle(
            color: CorviaColors.textPrimary,
            fontWeight: FontWeight.bold,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              subtitleText,
              style: TextStyle(
                color: CorviaColors.textSecondary,
                fontSize: isMobile ? 11 : 13,
              ),
            ),
            if (updatedString.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                'Last updated: $updatedString',
                style: TextStyle(
                  color: CorviaColors.textSecondary.withValues(alpha: 0.7),
                  fontSize: 10,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ]
          ],
        ),
        trailing: RecordStatusBadge(status: rawStatus),
        children: [
          if ((record['description'] ?? '').toString().isNotEmpty)
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  isMobile ? 24 : 72,
                  0,
                  16,
                  12,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Divider(),
                    const Text("Clinical Observations:",
                        style: TextStyle(
                            color: Colors.blueAccent,
                            fontWeight: FontWeight.bold,
                            fontSize: 12)),
                    const SizedBox(height: 4),
                    Text(
                      record['description'].toString(),
                      style: TextStyle(color: CorviaColors.textSecondary),
                    ),
                    const SizedBox(height: 12),

                    // --- TASK WORK: Detailed Report Button ---
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.open_in_new, size: 16),
                        label: const Text("View Full Detailed Report"),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: CorviaColors.accent,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 8),
                        ),
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) =>
                                  PatientRecordDetailPage(record: record),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class RecordStatusBadge extends StatelessWidget {
  const RecordStatusBadge({super.key, required this.status});
  final String status;

  static const _statusLabels = {
    'active': 'Active',
    'draft': 'Draft',
    'incomplete': 'Incomplete',
    'archived': 'Archived',
    'needs_review': 'Needs Review',
    'needs review': 'Needs Review',
  };

  Color get _color {
    switch (_normalizedStatus) {
      case 'active':
        return CorviaColors.success;
      case 'draft':
        return Colors.orangeAccent;
      case 'incomplete':
        return Colors.amber;
      case 'archived':
        return Colors.grey;
      case 'needs_review':
        return CorviaColors.accent;
      default:
        return CorviaColors.textSecondary;
    }
  }

  String get _normalizedStatus =>
      status.trim().toLowerCase().replaceAll(RegExp(r'[\s_-]+'), '_');

  String get _label =>
      _statusLabels[_normalizedStatus] ??
      (status.trim().isEmpty
          ? 'Unknown'
          : status.trim()[0].toUpperCase() + status.trim().substring(1));

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: _color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _color.withValues(alpha: 0.45)),
      ),
      child: Text(
        _label,
        style: TextStyle(
          color: _color,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class _LoadingItem extends _PatientRecordListItem {
  const _LoadingItem();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(16),
      child: Center(child: CircularProgressIndicator()),
    );
  }
}

class _EndItem extends _PatientRecordListItem {
  const _EndItem();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: Text(
          'All records loaded',
          style: TextStyle(color: CorviaColors.textSecondary),
        ),
      ),
    );
  }
}

class _PaginationControlsItem extends _PatientRecordListItem {
  const _PaginationControlsItem();

  @override
  Widget build(BuildContext context) {
    final state = context.findAncestorStateOfType<_PatientRecordsPageState>();
    if (state == null) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          ElevatedButton.icon(
            onPressed: state._hasPreviousPage ? state._previousPage : null,
            icon: const Icon(Icons.arrow_back),
            label: const Text('Previous'),
          ),
          Text(
            'Page ${state._currentPage + 1}',
            style: const TextStyle(
              fontWeight: FontWeight.bold,
            ),
          ),
          ElevatedButton.icon(
            onPressed: state._hasMore ? state._nextPage : null,
            icon: const Icon(Icons.arrow_forward),
            label: const Text('Next'),
          ),
        ],
      ),
    );
  }
}

class _SpacerItem extends _PatientRecordListItem {
  const _SpacerItem();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(height: 80);
  }
}

class _PatientRecordsBundle {
  _PatientRecordsBundle({
    required this.patientId,
    required this.immunizations,
    required this.riskFactors,
  });

  final String? patientId;
  final List<String> immunizations;
  final List<String> riskFactors;

  bool get isEmpty => immunizations.isEmpty && riskFactors.isEmpty;

  static Future<_PatientRecordsBundle> loadMeta() async {
    final patientId = await SupabaseService.currentPatientId();
    if (patientId == null) {
      return _PatientRecordsBundle(
        patientId: null,
        immunizations: const [],
        riskFactors: const [],
      );
    }
    final client = SupabaseService.client;
    final userId = SupabaseService.currentUserId;

    Future<List<Map<String, dynamic>>> immunizationRecords() async {
      try {
        final res = await client
            .from('medical_records')
            .select('title, record_type')
            .eq('patient_id', patientId)
            .inFilter('record_type', ['immunization', 'vaccine']);
        return List<Map<String, dynamic>>.from(res as List);
      } catch (_) {
        return <Map<String, dynamic>>[];
      }
    }

    Future<Map<String, dynamic>?> details() async {
      if (userId == null) return null;
      try {
        return await client
            .from('medical_details')
            .select('medical_conditions')
            .eq('user_id', userId)
            .maybeSingle();
      } catch (_) {
        return null;
      }
    }

    final results = await Future.wait([immunizationRecords(), details()]);
    final immRecs = results[0] as List<Map<String, dynamic>>;
    final det = results[1] as Map<String, dynamic>?;

    final immunizations = immRecs
        .map((record) => (record['title'] ?? 'Immunization').toString())
        .toList();

    final riskFactors = <String>[];
    if (det != null) {
      final conditions = (det['medical_conditions'] as List?) ?? const [];
      for (final condition in conditions) {
        final value = condition?.toString();
        if (value != null && value.isNotEmpty) {
          riskFactors.add(value);
        }
      }
    }

    return _PatientRecordsBundle(
      patientId: patientId,
      immunizations: immunizations,
      riskFactors: riskFactors,
    );
  }
}

// --- TASK WORK: New Detail Page Widget added at the very end ---
class PatientRecordSummaryPage extends StatelessWidget {
  const PatientRecordSummaryPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Patient Record Summary')),
      body: const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'This summary page is not available yet.\nPlease return to the records list.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16),
          ),
        ),
      ),
    );
  }
}

class PatientRecordDetailPage extends StatelessWidget {
  final Map<String, dynamic> record;
  const PatientRecordDetailPage({super.key, required this.record});

  @override
  Widget build(BuildContext context) {
    final dateStr = DateFormat('d MMMM yyyy')
        .format(DateTime.parse(record['record_date']).toLocal());
    final ref = record['id'].toString().substring(0, 4).toUpperCase();

    return Scaffold(
      appBar: AppBar(title: Text("Record Details #$ref")),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildDetailCard("Personal Details", [
            _buildDetailRow(Icons.person, "Patient Name", "Popo Mompe"),
            _buildDetailRow(Icons.cake, "Age", "24 Years"),
            _buildDetailRow(Icons.male, "Gender", "Male"),
          ]),
          _buildDetailCard("Contact Details", [
            _buildDetailRow(Icons.phone, "Phone", "+27 81 234 5678"),
            _buildDetailRow(Icons.email, "Email", "p.mompe@example.com"),
          ]),
          _buildDetailCard("Medical Summary", [
            _buildDetailRow(Icons.title, "Title", record['title'] ?? "Record"),
            _buildDetailRow(
                Icons.category, "Category", record['record_type'] ?? "General"),
            _buildDetailRow(Icons.calendar_month, "Date", dateStr),
            const Divider(),
            const Text("Observations:",
                style: TextStyle(
                    fontWeight: FontWeight.bold, color: Colors.blueAccent)),
            const SizedBox(height: 8),
            Text(record['description'] ?? "No clinical notes available."),
          ]),
          _buildDetailCard("Record Status", [
            ListTile(
              leading: const Icon(Icons.check_circle, color: Colors.green),
              title: const Text("Verified & Completed",
                  style: TextStyle(
                      color: Colors.green, fontWeight: FontWeight.bold)),
              subtitle: Text("Finalized on $dateStr"),
            )
          ]),
        ],
      ),
    );
  }

  Widget _buildDetailCard(String title, List<Widget> children) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.blueAccent)),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.grey),
          const SizedBox(width: 8),
          Text("$label:", style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(width: 8),
          Text(value),
        ],
      ),
    );
  }
}
