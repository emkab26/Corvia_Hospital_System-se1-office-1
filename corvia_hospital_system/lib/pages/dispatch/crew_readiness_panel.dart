
import 'package:flutter/material.dart';

/// Read-only crew status panel using authorised WS4 assignments.
///
/// Shift details and clinical qualifications are not inferred
/// from an assignment. They require verified WS5/WS6 data.
class CrewReadinessPanel extends StatelessWidget {
  const CrewReadinessPanel({
    super.key,
    required this.assignments,
    this.snapshotVerifiedAt,
  });

  final List<Map<String, dynamic>> assignments;
  final DateTime? snapshotVerifiedAt;

  static String _read(Object? value, String fallback) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? fallback : text;
  }

  static String _date(DateTime? value) {
    if (value == null) return 'Not verified';

    final local = value.toLocal();

    String two(int number) =>
        number.toString().padLeft(2, '0');

    return '${two(local.day)}/${two(local.month)}/${local.year} '
        '${two(local.hour)}:${two(local.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    final active = assignments
        .where((assignment) => assignment['active'] == true)
        .length;

    final available = assignments.where(
      (assignment) =>
          assignment['active'] == true &&
          assignment['crew_available'] == true,
    ).length;

    return Card(
      key: const ValueKey('crew-readiness-panel'),
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.groups_outlined,
                  color: colors.primary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Crew readiness',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 8),

            Text(
              'Review recorded response crews, assignment states '
              'and server-reported crew availability.',
              style: theme.textTheme.bodyMedium,
            ),

            const SizedBox(height: 12),

            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(
                  label: Text(
                    '${assignments.length} assignments',
                  ),
                ),
                Chip(
                  label: Text('$active active'),
                ),
                Chip(
                  label: Text(
                    '$available active with crew availability reported',
                  ),
                ),
              ],
            ),

            const SizedBox(height: 8),

            Text(
              'Snapshot verified: ${_date(snapshotVerifiedAt)}',
              style: theme.textTheme.bodySmall,
            ),

            const SizedBox(height: 8),

            Text(
              'Crew availability does not independently confirm '
              'an active shift, registration, licence, qualifications '
              'or minimum clinical capability. These must be verified '
              'through the existing authorised fleet and paramedic systems.',
              style: theme.textTheme.bodySmall,
            ),

            if (assignments.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 16),
                child: Text(
                  'No response assignments returned. '
                  'No crew readiness can be confirmed from this snapshot.',
                ),
              ),

            for (final assignment in assignments) ...[
              const Divider(height: 24),
              _CrewAssignmentCard(
                assignment: assignment,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CrewAssignmentCard extends StatelessWidget {
  const _CrewAssignmentCard({
    required this.assignment,
  });

  final Map<String, dynamic> assignment;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    final active = assignment['active'] == true;

    final available = assignment['crew_available'];

    final overdue = assignment['overdue'] == true;

    final attention = assignment['attention'];

    final crewName = CrewReadinessPanel._read(
      assignment['crew'],
      'Crew not identified',
    );

    final unitName = CrewReadinessPanel._read(
      assignment['unit'],
      'Unit not identified',
    );

    final state = CrewReadinessPanel._read(
      assignment['state'],
      'Unknown',
    ).replaceAll('_', ' ');

    final purpose = CrewReadinessPanel._read(
      assignment['purpose'],
      'Not recorded',
    );

    final availabilityMessage = available == true
        ? 'Crew availability reported by WS4'
        : available == false
            ? 'Crew not available according to WS4'
            : 'Crew availability not verified';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              active
                  ? Icons.medical_services_outlined
                  : Icons.person_off_outlined,
              color: active
                  ? colors.primary
                  : colors.onSurfaceVariant,
            ),

            const SizedBox(width: 8),

            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    crewName,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text('Unit: $unitName'),
                ],
              ),
            ),
          ],
        ),

        const SizedBox(height: 10),

        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            Chip(
              label: Text(
                active ? 'Active assignment' : 'Inactive assignment',
              ),
            ),
            Chip(label: Text('State: $state')),
            Chip(label: Text('Purpose: $purpose')),
          ],
        ),

        const SizedBox(height: 10),

        Text(availabilityMessage),

        if (overdue)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.warning_amber_outlined,
                  color: colors.error,
                  size: 18,
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Assignment acknowledgement overdue. '
                    'Dispatch review is required.',
                  ),
                ),
              ],
            ),
          ),

        if (attention != null &&
            attention.toString().trim().isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Supervisor attention: $attention',
              style: TextStyle(color: colors.error),
            ),
          ),

        const SizedBox(height: 10),

        const Text(
          'Shift verification: Not provided by this assignment snapshot',
        ),

        const SizedBox(height: 4),

        const Text(
          'Clinical qualification verification: '
          'Not provided by this assignment snapshot',
        ),

        const SizedBox(height: 8),

        Text(
          'Use the existing authorised Fleet & Paramedic '
          'workspace to verify crew eligibility and perform '
          'any operational reassignment.',
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }
}
