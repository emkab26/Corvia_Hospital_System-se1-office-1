
import 'package:flutter/material.dart';

/// Completion must be established by the authorised data source.
/// Never infer it from a free-text status such as "at_hospital".
enum DispatchCompletionState {
  completed,
  notCompleted,
  unknown,
}

/// One record from an existing, authorised dispatch history response.
/// Do not construct these from mock records in production.
class DispatchHistoryRecord {
  const DispatchHistoryRecord({
    required this.incidentId,
    required this.status,
    required this.completion,
    this.outcome,
    this.createdAt,
    this.completedAt,
  });

  final String incidentId;
  final String status;
  final DispatchCompletionState completion;
  final String? outcome;
  final DateTime? createdAt;
  final DateTime? completedAt;

  /// Case elapsed time, NOT ambulance dispatch/arrival/response time.
  Duration? get caseElapsed {
    if (completion != DispatchCompletionState.completed ||
        createdAt == null ||
        completedAt == null) {
      return null;
    }
    final elapsed = completedAt!.difference(createdAt!);
    return elapsed.isNegative ? null : elapsed;
  }
}

enum _ReportFilter { all, completed, notCompleted, unknown }

/// Read-only UI. Callers must load scoped records using the existing backend.
/// A paged/partial list cannot be presented as full historical statistics.
class DispatchHistoryReportPanel extends StatefulWidget {
  const DispatchHistoryReportPanel({
    super.key,
    required this.records,
    this.scopeDescription = 'Authorised records supplied to this screen',
    this.resultSetComplete = false,
    this.snapshotReceivedAt,
    this.isLoading = false,
    this.errorMessage,
    this.onRefresh,
  });

  final List<DispatchHistoryRecord> records;
  final String scopeDescription;
  final bool resultSetComplete;
  final DateTime? snapshotReceivedAt;
  final bool isLoading;
  final String? errorMessage;
  final VoidCallback? onRefresh;

  @override
  State<DispatchHistoryReportPanel> createState() =>
      _DispatchHistoryReportPanelState();
}

class _DispatchHistoryReportPanelState
    extends State<DispatchHistoryReportPanel> {
  _ReportFilter _filter = _ReportFilter.all;
  String _search = '';
  String? _statusFilter;

  static String _read(String? value, String fallback) {
    final clean = value?.trim() ?? '';
    return clean.isEmpty ? fallback : clean;
  }

  static String _time(DateTime? date) {
    if (date == null) return 'Not recorded';
    final local = date.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(local.day)}/${two(local.month)}/${local.year} '
        '${two(local.hour)}:${two(local.minute)}';
  }

  static String _elapsed(Duration? value) {
    if (value == null) return 'Unavailable';
    final minutes = (value.inSeconds / 60).round();
    if (minutes < 60) return '$minutes min';
    final hours = minutes ~/ 60;
    final remaining = minutes % 60;
    return '$hours h ${remaining.toString().padLeft(2, '0')} min';
  }

  bool _matches(DispatchHistoryRecord record) {
    final matchCompletion = switch (_filter) {
      _ReportFilter.all => true,
      _ReportFilter.completed =>
        record.completion == DispatchCompletionState.completed,
      _ReportFilter.notCompleted =>
        record.completion == DispatchCompletionState.notCompleted,
      _ReportFilter.unknown =>
        record.completion == DispatchCompletionState.unknown,
    };
    final query = _search.trim().toLowerCase();
    final matchSearch = query.isEmpty ||
        record.incidentId.toLowerCase().contains(query) ||
        record.status.toLowerCase().contains(query) ||
        (record.outcome?.toLowerCase().contains(query) ?? false);
    final matchStatus =
        _statusFilter == null || record.status == _statusFilter;
    return matchCompletion && matchSearch && matchStatus;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final records = widget.records;
    final filtered = records.where(_matches).toList();
    final completed = records.where((record) =>
        record.completion == DispatchCompletionState.completed).length;
    final open = records.where((record) =>
        record.completion == DispatchCompletionState.notCompleted).length;
    final unknown = records.length - completed - open;
    final statuses = records.map((record) => record.status)
        .where((status) => status.trim().isNotEmpty)
        .toSet().toList()..sort();
    final statusValue = statuses.contains(_statusFilter)
        ? _statusFilter : null;

    final completedFiltered = filtered.where((record) =>
        record.completion == DispatchCompletionState.completed).toList();
    final timings = completedFiltered.map((record) => record.caseElapsed)
        .whereType<Duration>().toList();
    final average = timings.isEmpty ? null : Duration(seconds:
        (timings.fold<int>(0, (total, d) => total + d.inSeconds) /
            timings.length).round());
    final outcomes = <String, int>{};
    for (final record in completedFiltered) {
      final outcome = _read(record.outcome, 'Not recorded');
      outcomes.update(outcome, (value) => value + 1, ifAbsent: () => 1);
    }
    final outcomeKeys = outcomes.keys.toList()..sort();

    return Card(
      key: const ValueKey('dispatch-history-report-panel'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.assessment_outlined, color: colors.primary),
              const SizedBox(width: 8),
              Expanded(child: Text('Dispatch history & outcomes',
                  style: theme.textTheme.titleMedium)),
              if (widget.onRefresh != null)
                IconButton(
                  tooltip: 'Refresh authorised history',
                  onPressed: widget.isLoading ? null : widget.onRefresh,
                  icon: const Icon(Icons.refresh),
                ),
            ]),
            Text('Scope: ${widget.scopeDescription}'),
            Text('Snapshot received: ${_time(widget.snapshotReceivedAt)}',
                style: theme.textTheme.bodySmall),
            const SizedBox(height: 8),
            Text(
              widget.resultSetComplete
                  ? 'Counts describe this server-confirmed complete result set.'
                  : 'PARTIAL / UNVERIFIED RESULT SET: Counts describe only '
                    'the loaded records, not all hospital incidents.',
              style: theme.textTheme.bodySmall,
            ),
            if (widget.isLoading) const LinearProgressIndicator(),
            if (widget.errorMessage != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'History refresh failed: ${widget.errorMessage}. '
                  'Displayed records may be stale.',
                  style: TextStyle(color: colors.error),
                ),
              ),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: [
              Chip(label: Text('${records.length} loaded')),
              Chip(label: Text('$completed completed')),
              Chip(label: Text('$open not completed')),
              Chip(label: Text('$unknown unverified')),
            ]),
            const SizedBox(height: 10),
            TextField(
              key: const ValueKey('dispatch-history-search'),
              decoration: const InputDecoration(
                labelText: 'Search loaded history',
                hintText: 'Incident reference, status or outcome',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              onChanged: (value) => setState(() => _search = value),
            ),
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 6, children: [
              ChoiceChip(
                label: const Text('All'),
                selected: _filter == _ReportFilter.all,
                onSelected: (_) => setState(() => _filter = _ReportFilter.all),
              ),
              ChoiceChip(
                label: const Text('Completed only'),
                selected: _filter == _ReportFilter.completed,
                onSelected: (_) =>
                    setState(() => _filter = _ReportFilter.completed),
              ),
              ChoiceChip(
                label: const Text('Not completed'),
                selected: _filter == _ReportFilter.notCompleted,
                onSelected: (_) =>
                    setState(() => _filter = _ReportFilter.notCompleted),
              ),
              ChoiceChip(
                label: const Text('Unverified'),
                selected: _filter == _ReportFilter.unknown,
                onSelected: (_) =>
                    setState(() => _filter = _ReportFilter.unknown),
              ),
            ]),
            if (statuses.isNotEmpty) ...[
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                key: ValueKey('dispatch-history-status-${statuses.join('|')}'),
                initialValue: statusValue,
                decoration: const InputDecoration(labelText: 'Filter status'),
                items: [
                  const DropdownMenuItem<String>(
                    value: '', child: Text('All recorded statuses')),
                  for (final status in statuses)
                    DropdownMenuItem(value: status, child: Text(status)),
                ],
                onChanged: (value) => setState(() {
                  _statusFilter = value == null || value.isEmpty ? null : value;
                }),
              ),
            ],
            const SizedBox(height: 12),
            Text('${filtered.length} matching loaded records',
                style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            Text('Recorded outcomes (completed, filtered):',
                style: theme.textTheme.labelLarge),
            if (completedFiltered.isEmpty)
              const Text('Unavailable: no completed records in this filter.'),
            for (final outcome in outcomeKeys)
              Text('$outcome: ${outcomes[outcome]}'),
            const SizedBox(height: 8),
            Text('Average case elapsed (created to completed): '
                '${_elapsed(average)}'),
            Text(
              'Valid timestamp pairs: ${timings.length} of '
              '${completedFiltered.length} filtered completed records. '
              'This is not ambulance response time.',
              style: theme.textTheme.bodySmall,
            ),
            const Divider(height: 28),
            if (filtered.isEmpty)
              const Text('No loaded records match these filters.'),
            for (final record in filtered)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: SelectableText('Incident ${record.incidentId}'),
                subtitle: Text(
                  'Status: ${_read(record.status, 'Not recorded')}\n'
                  'Completion: ${switch (record.completion) {
                    DispatchCompletionState.completed => 'Confirmed by source',
                    DispatchCompletionState.notCompleted => 'Not completed',
                    DispatchCompletionState.unknown => 'Not verified',
                  }}\n'
                  'Outcome: ${_read(record.outcome, 'Not recorded')}\n'
                  'Created: ${_time(record.createdAt)} '
                  '· Completed: ${_time(record.completedAt)}\n'
                  'Case elapsed: ${_elapsed(record.caseElapsed)}',
                ),
              ),
            const SizedBox(height: 8),
            Text(
              'Only existing authorised history should be supplied. '
              'No clinical or dispatch state is changed by this report. '
              'Do not infer missing dates, outcomes or completion.',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
