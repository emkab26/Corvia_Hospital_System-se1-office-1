
import 'package:flutter/material.dart';

/// Displays eligibility returned by the existing, authorised WS4 response API.
/// This widget does not query Supabase or assign a vehicle on its own.
class FleetAvailabilityPanel extends StatelessWidget {
  const FleetAvailabilityPanel({
    super.key,
    required this.units,
    required this.assignments,
    required this.canAct,
    required this.hasReviewReason,
    required this.onReviewReadiness,
    required this.onAssignPrimary,
    required this.onAssignBackup,
  });

  final List<Map<String, dynamic>> units;
  final List<Map<String, dynamic>> assignments;
  final bool canAct;
  final bool hasReviewReason;
  final ValueChanged<Map<String, dynamic>> onReviewReadiness;
  final ValueChanged<Map<String, dynamic>> onAssignPrimary;
  final ValueChanged<Map<String, dynamic>> onAssignBackup;

  static bool _active(Map<String, dynamic> row) =>
      row['active'] == true;

  static String _read(Object? value, String fallback) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? fallback : text;
  }

  static bool _validRef(Map<String, dynamic> unit) =>
      unit['id'] is String &&
      (unit['id'] as String).trim().isNotEmpty &&
      unit['version'] is String &&
      (unit['version'] as String).trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    final eligible = units.where(
      (unit) => unit['reason'] == 'Eligible' && _validRef(unit),
    ).length;

    final activePrimary = assignments.any(
      (entry) =>
          _active(entry) && entry['purpose'] == 'primary',
    );

    final activeBackup = assignments.any(
      (entry) =>
          _active(entry) && entry['purpose'] == 'backup',
    );

    final backupRequested = assignments.any(
      (entry) =>
          _active(entry) && entry['attention'] == 'backup',
    );

    return Card(
      key: const ValueKey('fleet-availability-panel'),
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.airport_shuttle_outlined,
                  color: colors.primary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Incident fleet availability',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 8),

            Text(
              '${units.length} unit${units.length == 1 ? '' : 's'} '
              'in this authorised incident snapshot '
              '· $eligible currently eligible',
            ),

            const SizedBox(height: 4),

            Text(
              'Eligibility and readiness are determined by the server. '
              'This list is not a whole-hospital live fleet count.',
              style: Theme.of(context).textTheme.bodySmall,
            ),

            if (!canAct)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Actions are locked while loading, after an error, '
                  'or when the incident is not editable.',
                  style: TextStyle(color: colors.error),
                ),
              ),

            if (units.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text(
                  'No units were returned for this incident. '
                  'Do not assume a resource is available.',
                ),
              ),

            for (final unit in units) ...[
              const Divider(height: 24),

              _UnitRow(
                unit: unit,

                canReview: canAct &&
                    hasReviewReason &&
                    unit['can_review'] == true &&
                    _validRef(unit),

                canAssignPrimary: canAct &&
                    !activePrimary &&
                    unit['reason'] == 'Eligible' &&
                    _validRef(unit),

                canAssignBackup: canAct &&
                    backupRequested &&
                    !activeBackup &&
                    unit['reason'] == 'Eligible' &&
                    _validRef(unit),

                onReview: () => onReviewReadiness(unit),

                onPrimary: () => onAssignPrimary(unit),

                onBackup: () => onAssignBackup(unit),
              ),
            ],

            if (eligible == 0 && units.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  'No unit in this snapshot is currently eligible. '
                  'Review the server reasons; do not force assignment.',
                  style: TextStyle(color: colors.error),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _UnitRow extends StatelessWidget {
  const _UnitRow({
    required this.unit,
    required this.canReview,
    required this.canAssignPrimary,
    required this.canAssignBackup,
    required this.onReview,
    required this.onPrimary,
    required this.onBackup,
  });

  final Map<String, dynamic> unit;
  final bool canReview;
  final bool canAssignPrimary;
  final bool canAssignBackup;

  final VoidCallback onReview;
  final VoidCallback onPrimary;
  final VoidCallback onBackup;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    final reason = FleetAvailabilityPanel._read(
      unit['reason'],
      'Eligibility not verified',
    );

    final eligible = reason == 'Eligible';

    final rawReview = unit['review'];
    final review = rawReview is Map ? rawReview : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          FleetAvailabilityPanel._read(
            unit['label'],
            'Unnamed unit',
          ),
          style: Theme.of(context).textTheme.titleSmall,
        ),

        const SizedBox(height: 5),

        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              eligible
                  ? Icons.check_circle_outline
                  : Icons.block_outlined,
              size: 18,
              color: eligible ? colors.primary : colors.error,
            ),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                eligible
                    ? 'Server eligibility: Eligible'
                    : 'Not eligible: $reason',
              ),
            ),
          ],
        ),

        if (review != null) ...[
          const SizedBox(height: 6),

          Text(
            'Readiness review: '
            '${FleetAvailabilityPanel._read(review['reason'], 'No reason')} '
            '· recorded ${FleetAvailabilityPanel._read(review['recorded_at'], 'unknown')} '
            '· expires ${FleetAvailabilityPanel._read(review['valid_until'], 'unknown')}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],

        const SizedBox(height: 9),

        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (unit['can_review'] == true)
              OutlinedButton.icon(
                onPressed: canReview ? onReview : null,
                icon: const Icon(Icons.fact_check_outlined),
                label: const Text('Review readiness'),
              ),

            FilledButton.tonalIcon(
              onPressed:
                  canAssignPrimary ? onPrimary : null,
              icon: const Icon(
                Icons.assignment_turned_in_outlined,
              ),
              label: const Text('Assign primary'),
            ),

            if (canAssignBackup)
              OutlinedButton.icon(
                onPressed: onBackup,
                icon: const Icon(Icons.group_add_outlined),
                label: const Text('Assign backup'),
              ),
          ],
        ),
      ],
    );
  }
}
