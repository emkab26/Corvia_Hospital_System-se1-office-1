
import 'package:flutter/material.dart';

/// Read-only operational audit data from an authorised response snapshot.
///
/// The parent must provide only records the current role may inspect.
/// This panel never changes incident state or makes Supabase requests.
class IncidentAccountabilityPanel extends StatelessWidget {
  const IncidentAccountabilityPanel({
    super.key,
    required this.incidentId,
    required this.events,
    required this.assignments,
    required this.snapshotVerifiedAt,
    this.olderEvents = false,
    this.onRefresh,
  });

  final String incidentId;
  final List<Map<String, dynamic>> events;
  final List<Map<String, dynamic>> assignments;
  final DateTime snapshotVerifiedAt;
  final bool olderEvents;
  final VoidCallback? onRefresh;

  static const _exceptionCommands = <String>{
    'exception',
    'resolve_exception',
    'terminal_exception',
  };

  static String _text(Object? value, String fallback) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? fallback : text;
  }

  static String _date(Object? input) {
    final DateTime? date = input is DateTime
        ? input
        : DateTime.tryParse(input?.toString() ?? '');

    if (date == null) return 'Not recorded';

    final local = date.toLocal();

    String two(int number) =>
        number.toString().padLeft(2, '0');

    return '${two(local.day)}/${two(local.month)}/${local.year} '
        '${two(local.hour)}:${two(local.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    final activeAttention = assignments.where((assignment) {
      final attention = assignment['attention'];

      return assignment['active'] == true &&
          attention != null &&
          attention.toString().trim().isNotEmpty;
    }).toList();

    final overdue = assignments.where((assignment) {
      return assignment['active'] == true &&
          assignment['overdue'] == true;
    }).length;

    final exceptionEvents = events.where((event) {
      final command =
          event['command']?.toString().toLowerCase();

      return _exceptionCommands.contains(command);
    }).length;

    return Card(
      key: const ValueKey('incident-accountability-panel'),
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.history,
                  color: colors.primary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Incident accountability',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                if (onRefresh != null)
                  IconButton(
                    tooltip: 'Refresh authorised incident data',
                    onPressed: onRefresh,
                    icon: const Icon(Icons.refresh),
                  ),
              ],
            ),

            SelectableText('Incident: $incidentId'),

            const SizedBox(height: 6),

            Text(
              'Snapshot verified: ${_date(snapshotVerifiedAt)}',
              style: theme.textTheme.bodySmall,
            ),

            const SizedBox(height: 10),

            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(
                  label: Text(
                    '${events.length} loaded audit events',
                  ),
                ),
                Chip(
                  label: Text(
                    '$exceptionEvents exception-related events',
                  ),
                ),
                Chip(
                  label: Text(
                    '${activeAttention.length} active assignment alerts',
                  ),
                ),
                if (overdue > 0)
                  Chip(
                    label: Text(
                      '$overdue overdue acknowledgements',
                    ),
                  ),
              ],
            ),

            const SizedBox(height: 8),

            Text(
              'Audit events are recorded actions, not a count of '
              'unresolved exceptions. Current blockers and closure '
              'authority must be verified by the server.',
              style: theme.textTheme.bodySmall,
            ),

            if (activeAttention.isNotEmpty) ...[
              const SizedBox(height: 12),

              Text(
                'Assignments needing attention',
                style: theme.textTheme.titleSmall,
              ),

              for (final assignment in activeAttention)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.warning_amber_outlined,
                        size: 18,
                        color: colors.error,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${_text(assignment['unit'], 'Unidentified unit')} '
                          '· ${_text(assignment['attention'], 'Review required')} '
                          '· ${_text(assignment['state'], 'State unknown')}',
                        ),
                      ),
                    ],
                  ),
                ),
            ],

            const SizedBox(height: 12),

            Text(
              'Persisted operational events',
              style: theme.textTheme.titleSmall,
            ),

            if (events.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'No audit events were returned in this snapshot.',
                ),
              ),

            if (olderEvents)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'The service reports older events outside this '
                  'loaded window. Do not treat this as the '
                  'complete audit history.',
                ),
              ),

            for (final event in events.take(10))
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(
                  _text(
                    event['command'],
                    'Unknown action',
                  ),
                ),
                subtitle: Text(
                  '${_text(event['detail'], 'No detail recorded')}\n'
                  'Role: ${_text(event['actor_role'], 'Unknown')} '
                  '· Actor: ${_text(event['actor_id'], 'Not recorded')}\n'
                  'Occurred: ${_date(event['occurred_at'])} '
                  '· Saved: ${_date(event['recorded_at'])}',
                ),
              ),

            if (events.length > 10)
              const Text(
                'Only the first 10 supplied entries are shown '
                'here. Use the full response timeline for '
                'the other loaded entries.',
              ),

            const SizedBox(height: 6),

            Text(
              'Displayed order follows the API response; it is '
              'not independently verified. This panel does not '
              'resolve exceptions, acknowledge messages '
              'or close incidents.',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
