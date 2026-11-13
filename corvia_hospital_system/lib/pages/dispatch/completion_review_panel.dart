
import 'package:flutter/material.dart';

/// Read-only review of a linked Team EMS incident.
///
/// Data must come from the existing authorised teamSnapshot().
/// This panel does not close, cancel or complete an incident.
///
/// A recorded hospital destination does not establish patient
/// acceptance. Receiver acknowledgement must be verified through
/// the existing receiving workflow.
class CompletionReviewPanel extends StatelessWidget {
  const CompletionReviewPanel({
    super.key,
    required this.snapshot,
    this.isStale = false,
  });

  final Map<String, dynamic> snapshot;
  final bool isStale;

  static String _read(
    Object? value,
    String fallback,
  ) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? fallback : text;
  }

  static int? _rowCount(Object? value) {
    if (value is! List) return null;

    if (value.any((item) => item is! Map)) {
      return null;
    }

    return value.length;
  }

  static String _destinationStatus(Object? value) {
    if (value is! Map) {
      return 'No receiving destination recorded';
    }

    final id = value['facility_id']?.toString().trim();

    if (id == null || id.isEmpty) {
      return 'No verified destination reference';
    }

    return 'Destination recorded - acceptance not verified';
  }

  static String _acknowledgementStatus(Object? value) {
    if (value == true) {
      return 'PRIMARY ACKNOWLEDGEMENT OVERDUE';
    }

    if (value == false) {
      return 'No overdue primary acknowledgement reported';
    }

    return 'Primary acknowledgement status not verified';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    final incidentNumber = _read(
      snapshot['incident_number'],
      'Not recorded',
    );

    final incidentStatus = _read(
      snapshot['status'],
      'Not verified',
    );

    final dispatchState = _read(
      snapshot['dispatch_state'],
      'Not verified',
    );

    final destination = snapshot['destination'];
    final exceptionCount = _rowCount(
      snapshot['exceptions'],
    );
    final unitCount = _rowCount(
      snapshot['units'],
    );
    final primaryOverdue = snapshot['primary_overdue'];

    final hasDestination = destination is Map &&
        destination['facility_id'] != null &&
        destination['facility_id']
            .toString()
            .trim()
            .isNotEmpty;

    final reviewItems = <String>[
      if (exceptionCount == null)
        'Unresolved exception information could not be verified.'
      else if (exceptionCount > 0)
        '$exceptionCount unresolved exception '
            '${exceptionCount == 1 ? 'entry' : 'entries'} '
            'require review.',
      if (!hasDestination)
        'Confirm a receiving destination through the '
            'authorised team workflow.',
      if (primaryOverdue == true)
        'Primary crew acknowledgement is overdue. '
            'Dispatch review is required.'
      else if (primaryOverdue is! bool)
        'Primary crew acknowledgement timing is not verified.',
      if (unitCount == null)
        'Team unit information could not be verified.'
      else if (unitCount == 0)
        'No team units were returned. Verify the '
            'actual resource state before closure.',
    ];

    return Card(
      key: const ValueKey('completion-review-panel'),
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
                  color: colors.primary,
                  size: 26,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Incident completion review',
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

            const SizedBox(height: 12),

            SelectableText(
              'Incident: $incidentNumber',
            ),

            const SizedBox(height: 8),

            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(
                  label: Text(
                    'Status: $incidentStatus',
                  ),
                ),
                Chip(
                  label: Text(
                    'Dispatch: $dispatchState',
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            if (isStale)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      color: colors.error,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'The latest incident state could not be '
                        'verified. Do not act on outdated information.',
                      ),
                    ),
                  ],
                ),
              ),

            Text(
              'Receiving destination',
              style: theme.textTheme.titleSmall,
            ),

            const SizedBox(height: 5),

            Text(
              _destinationStatus(destination),
            ),

            const SizedBox(height: 14),

            Text(
              'Safety exceptions',
              style: theme.textTheme.titleSmall,
            ),

            const SizedBox(height: 5),

            Text(
              exceptionCount == null
                  ? 'Unresolved exceptions: Not verified'
                  : 'Unresolved exception entries: $exceptionCount',
            ),

            const SizedBox(height: 14),

            Text(
              'Primary response',
              style: theme.textTheme.titleSmall,
            ),

            const SizedBox(height: 5),

            Text(
              _acknowledgementStatus(primaryOverdue),
            ),

            const SizedBox(height: 6),

            Text(
              unitCount == null
                  ? 'Team units: Not verified'
                  : 'Team unit entries: $unitCount',
            ),

            const SizedBox(height: 14),

            Text(
              'Hospital handover',
              style: theme.textTheme.titleSmall,
            ),

            const SizedBox(height: 5),

            const Text(
              'Receiving acknowledgement is not verified by '
              'this team snapshot. Check the authorised '
              'hospital receiving workflow.',
            ),

            const SizedBox(height: 14),

            Text(
              'Items requiring review',
              style: theme.textTheme.titleSmall,
            ),

            if (reviewItems.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'No review alerts were identified in the '
                  'supplied snapshot. This does not establish '
                  'that the incident is complete.',
                ),
              ),

            for (final item in reviewItems)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.warning_amber_outlined,
                      color: colors.error,
                      size: 19,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(item),
                    ),
                  ],
                ),
              ),

            const Divider(height: 28),

            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.info_outline,
                  color: colors.primary,
                  size: 20,
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Completion is not verified by this panel. '
                    'Hospital arrival, destination selection '
                    'and incident status alone do not prove '
                    'patient handover or incident closure. '
                    'Final completion requires the existing '
                    'authorised backend workflow.',
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
