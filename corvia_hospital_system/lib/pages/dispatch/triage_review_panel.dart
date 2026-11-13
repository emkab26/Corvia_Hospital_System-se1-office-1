
import 'package:flutter/material.dart';

/// Read-only view of the authorised WS4 response snapshot.
///
/// No clinical decisions, assignment authority or new Supabase calls are
/// made here. Data comes from the existing scoped response service.
class Ws4TriageReviewPanel extends StatelessWidget {
  const Ws4TriageReviewPanel({
    super.key,
    required this.incidentId,
    required this.status,
    required this.priority,
    required this.sceneDetails,
    required this.location,
    required this.assignments,
    required this.events,
    required this.lastVerifiedAt,
  });

  final String incidentId;
  final String status;
  final Object? priority;
  final Object? sceneDetails;
  final Map<dynamic, dynamic> location;
  final List<dynamic> assignments;
  final List<dynamic> events;
  final DateTime lastVerifiedAt;

  String _value(Object? value, String fallback) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? fallback : text;
  }

  String _readable(String value) {
    return value.replaceAll('_', ' ').trim();
  }

  String _time(Object? value) {
    DateTime? date;

    if (value is DateTime) {
      date = value;
    } else if (value != null) {
      date = DateTime.tryParse(value.toString());
    }

    if (date == null) return 'Not recorded';

    final local = date.toLocal();

    String two(int number) => number.toString().padLeft(2, '0');

    return '${two(local.day)}/${two(local.month)}/${local.year} '
        '${two(local.hour)}:${two(local.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final details = _value(
      sceneDetails,
      'No scene details supplied.',
    );

    final latitude = location['latitude'];
    final longitude = location['longitude'];

    final hasCoordinates = latitude is num &&
        longitude is num &&
        latitude.isFinite &&
        longitude.isFinite &&
        latitude >= -90 &&
        latitude <= 90 &&
        longitude >= -180 &&
        longitude <= 180;

    // No unnecessary casts.
    final recordedPosition = hasCoordinates
        ? '${latitude.toStringAsFixed(5)}, '
            '${longitude.toStringAsFixed(5)}'
        : 'No valid coordinates recorded';

    final activeAssignments = assignments.where((item) {
      return item is Map && item['active'] == true;
    }).length;

    final source = _value(
      location['location_source'] ?? location['source'],
      'Source not recorded',
    );

    final positionAt = _time(
      location['location_at'] ?? location['captured_at'],
    );

    final problems = <String>[
      if (details == 'No scene details supplied.')
        'Confirm the scene description with the patient or clinical team.',
      if (!hasCoordinates)
        'Confirm an actionable location before coordinating a response.',
      if (activeAssignments == 0)
        'No active WS4 assignment is shown. Check the linked team EMS '
            'case separately before concluding that no team is assigned.',
    ];

    return Card(
      key: const ValueKey('ws4-triage-review'),
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.fact_check_outlined,
                  color: scheme.primary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Incident triage review',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const Chip(
                  label: Text('Read only'),
                ),
              ],
            ),

            const SizedBox(height: 8),

            SelectableText(
              'WS4 incident: $incidentId',
            ),

            const SizedBox(height: 8),

            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(
                  label: Text(
                    'Status: ${_readable(status)}',
                  ),
                ),
                Chip(
                  label: Text(
                    'Priority: ${_value(priority, 'Not recorded')}',
                  ),
                ),
                Chip(
                  label: Text(
                    '$activeAssignments active WS4 assignment'
                    '${activeAssignments == 1 ? '' : 's'}',
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            Text(
              'Patient-reported scene details',
              style: theme.textTheme.titleSmall,
            ),

            const SizedBox(height: 4),

            Text(details),

            const SizedBox(height: 12),

            Text(
              'Recorded incident location',
              style: theme.textTheme.titleSmall,
            ),

            const SizedBox(height: 4),

            SelectableText(recordedPosition),

            Text(
              'Source: $source · Captured: $positionAt',
              style: theme.textTheme.bodySmall,
            ),

            const SizedBox(height: 8),

            Text(
              'Snapshot verified: ${_time(lastVerifiedAt)}',
              style: theme.textTheme.bodySmall,
            ),

            if (problems.isNotEmpty) ...[
              const SizedBox(height: 12),

              Text(
                'Items requiring review',
                style: theme.textTheme.titleSmall,
              ),

              for (final problem in problems)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.warning_amber_outlined,
                        size: 18,
                        color: scheme.error,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(problem),
                      ),
                    ],
                  ),
                ),
            ],

            const SizedBox(height: 12),

            Text(
              'This summary is not a clinical assessment, live GPS feed, '
              'dispatch assignment confirmation or receiving-hospital '
              'approval. Use the existing authorised response controls '
              'for those actions.',
              style: theme.textTheme.bodySmall,
            ),

            if (events.isNotEmpty)
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: Text(
                  'Loaded audit entries (${events.length})',
                ),
                subtitle: const Text(
                  'Recorded events; ordering not assumed',
                ),
                children: [
                  for (final entry in events.take(5))
                    if (entry is Map)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        title: Text(
                          _value(entry['command'], 'Event'),
                        ),
                        subtitle: Text(
                          '${_value(entry['detail'], 'No detail recorded')}\n'
                          'Saved: ${_time(entry['recorded_at'])}',
                        ),
                      ),

                  if (events.length > 5)
                    const ListTile(
                      dense: true,
                      title: Text(
                        'More events are available below '
                        'in the response timeline.',
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
