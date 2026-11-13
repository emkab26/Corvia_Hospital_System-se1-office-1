
import 'package:flutter/material.dart';

/// Read-only operational progress based on the authorised response snapshot.
///
/// This widget never performs a dispatch mutation and never infers a
/// confirmed hospital handover from arrival at a receiving facility.
class ResponseProgressPanel extends StatelessWidget {
  const ResponseProgressPanel({
    super.key,
    required this.assignments,
    required this.snapshotVerifiedAt,
    this.incidentStatus,
  });

  final List<Map<String, dynamic>> assignments;
  final DateTime? snapshotVerifiedAt;
  final String? incidentStatus;

  static String read(Object? value, String fallback) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? fallback : text;
  }

  static String readable(Object? value) {
    return read(value, 'Unknown').replaceAll('_', ' ');
  }

  static String formatTime(Object? value) {
    if (value == null) return 'Not recorded';

    final date = value is DateTime
        ? value
        : DateTime.tryParse(value.toString());

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

    final active = assignments
        .where((assignment) => assignment['active'] == true)
        .length;

    final overdue = assignments
        .where(
          (assignment) =>
              assignment['active'] == true &&
              assignment['overdue'] == true,
        )
        .length;

    final handoverRequests = assignments
        .where(
          (assignment) =>
              assignment['state'] == 'handover_requested',
        )
        .length;

    return Card(
      key: const ValueKey('response-progress-panel'),
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.emergency_outlined,
                  color: colors.primary,
                  size: 26,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Paramedic response progress',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 8),

            Text(
              'Recorded status of the response assignments '
              'available to your authorised account.',
              style: theme.textTheme.bodyMedium,
            ),

            const SizedBox(height: 12),

            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(
                  label: Text(
                    '${assignments.length} recorded assignments',
                  ),
                ),
                Chip(
                  label: Text('$active active'),
                ),
                if (overdue > 0)
                  Chip(
                    avatar: Icon(
                      Icons.warning_amber_outlined,
                      color: colors.error,
                      size: 18,
                    ),
                    label: Text('$overdue overdue'),
                  ),
                if (handoverRequests > 0)
                  Chip(
                    label: Text(
                      '$handoverRequests handover requests',
                    ),
                  ),
              ],
            ),

            const SizedBox(height: 10),

            Text(
              'Incident status: ${readable(incidentStatus)}',
              style: theme.textTheme.bodyMedium,
            ),

            Text(
              'Snapshot verified: ${formatTime(snapshotVerifiedAt)}',
              style: theme.textTheme.bodySmall,
            ),

            const SizedBox(height: 8),

            Text(
              'This is a recorded response snapshot, not live '
              'ambulance tracking. Handover completion requires '
              'an explicit authorised receiving confirmation.',
              style: theme.textTheme.bodySmall,
            ),

            if (assignments.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 16),
                child: Text(
                  'No response assignments were returned. '
                  'Check the linked Team EMS workspace for '
                  'separately managed crews.',
                ),
              ),

            for (final assignment in assignments) ...[
              const Divider(height: 26),
              _ResponseAssignmentCard(
                assignment: assignment,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ResponseAssignmentCard extends StatelessWidget {
  const _ResponseAssignmentCard({
    required this.assignment,
  });

  final Map<String, dynamic> assignment;

  String get _state =>
      ResponseProgressPanel.read(
        assignment['state'],
        'unknown',
      ).toLowerCase();

  String get _nextAction {
    switch (_state) {
      case 'offered':
        return 'Awaiting crew acknowledgement. '
            'Review the offer deadline.';

      case 'acknowledged':
        return 'Crew has acknowledged the assignment. '
            'Await an en-route update.';

      case 'en_route':
        return 'Crew is recorded as en route. '
            'Await arrival confirmation from the scene.';

      case 'on_scene':
        return 'Crew is recorded as on scene. '
            'Patient identification and transport requirements '
            'must be confirmed through the authorised workflow.';

      case 'transporting':
        return 'Patient transport is recorded as underway. '
            'Hospital arrival and handover are not yet confirmed.';

      case 'at_hospital':
        return 'Hospital arrival is recorded. '
            'This does not confirm that the patient was handed over.';

      case 'handover_requested':
        return 'The crew has requested handover. '
            'Explicit confirmation by an authorised receiving '
            'team member is still required.';

      default:
        return 'Review the latest recorded status '
            'and authorised response timeline.';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    final active = assignment['active'] == true;
    final overdue = assignment['overdue'] == true;
    final available = assignment['crew_available'];
    final patientConfirmed =
        assignment['patient_confirmed'] == true;

    final unit = ResponseProgressPanel.read(
      assignment['unit'],
      'Unit not identified',
    );

    final crew = ResponseProgressPanel.read(
      assignment['crew'],
      'Crew not identified',
    );

    final purpose = ResponseProgressPanel.readable(
      assignment['purpose'],
    );

    final attention = ResponseProgressPanel.read(
      assignment['attention'],
      '',
    );

    final destination = assignment['destination_id'];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              active
                  ? Icons.medical_services_outlined
                  : Icons.history_outlined,
              color: active
                  ? colors.primary
                  : colors.onSurfaceVariant,
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    unit,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text('Crew: $crew'),
                  Text('Purpose: $purpose'),
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
                active
                    ? 'Active assignment'
                    : 'Inactive assignment',
              ),
            ),
            Chip(
              label: Text(
                'Status: ${ResponseProgressPanel.readable(_state)}',
              ),
            ),
          ],
        ),

        const SizedBox(height: 10),

        Text(
          'Recorded response stage',
          style: theme.textTheme.titleSmall,
        ),

        const SizedBox(height: 5),

        Text(_nextAction),

        const SizedBox(height: 10),

        Text(
          patientConfirmed
              ? 'Patient match recorded by the crew.'
              : 'Patient match has not been recorded.',
        ),

        const SizedBox(height: 5),

        Text(
          available == true
              ? 'Crew availability reported by the server.'
              : available == false
                  ? 'Crew eligibility or availability is not satisfied.'
                  : 'Crew availability has not been verified.',
        ),

        if (destination != null) ...[
          const SizedBox(height: 5),
          Text(
            'Recorded destination ID: $destination',
          ),
          Text(
            'The destination ID does not confirm '
            'hospital capacity or acceptance.',
            style: theme.textTheme.bodySmall,
          ),
        ],

        if (_state == 'offered' &&
            assignment['deadline'] != null) ...[
          const SizedBox(height: 7),
          Text(
            'Acknowledgement deadline: '
            '${ResponseProgressPanel.formatTime(assignment['deadline'])}',
          ),
        ],

        if (overdue) ...[
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.warning_amber_rounded,
                color: colors.error,
                size: 19,
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Acknowledgement is overdue. '
                  'Dispatch or supervisor review is required.',
                ),
              ),
            ],
          ),
        ],

        if (attention.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(
            'Supervisor attention: $attention',
            style: TextStyle(
              color: colors.error,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],

        const SizedBox(height: 10),

        Text(
          'Use the existing response controls below to '
          'acknowledge, update or hand over an assignment. '
          'This panel never writes operational changes.',
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }
}
