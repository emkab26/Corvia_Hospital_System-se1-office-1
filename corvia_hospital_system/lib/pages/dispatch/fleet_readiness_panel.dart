
import 'package:flutter/material.dart';

/// Read-only presentation of the authenticated WS4 fleet snapshot.
///
/// The backend remains responsible for eligibility, readiness validation,
/// organisation scoping and whether a unit can be assigned.
class FleetReadinessPanel extends StatelessWidget {
  const FleetReadinessPanel({
    super.key,
    required this.units,
    this.snapshotVerifiedAt,
  });

  final List<Map<String, dynamic>> units;
  final DateTime? snapshotVerifiedAt;

  static String _read(Object? value, String fallback) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? fallback : text;
  }

  static bool _hasIdentity(Map<String, dynamic> unit) {
    final id = unit['id'];
    final version = unit['version'];

    return id is String &&
        id.trim().isNotEmpty &&
        version is String &&
        version.trim().isNotEmpty;
  }

  static bool _serverEligible(Map<String, dynamic> unit) {
    return unit['reason'] == 'Eligible' && _hasIdentity(unit);
  }

  static String _date(Object? value) {
    if (value == null) return 'Not recorded';

    final parsed = value is DateTime
        ? value
        : DateTime.tryParse(value.toString());

    if (parsed == null) return 'Not recorded';

    final date = parsed.toLocal();

    String two(int number) =>
        number.toString().padLeft(2, '0');

    return '${two(date.day)}/${two(date.month)}/${date.year} '
        '${two(date.hour)}:${two(date.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    final eligible = units.where(_serverEligible).length;
    final unavailable = units.length - eligible;

    return Card(
      key: const ValueKey('fleet-readiness-panel'),
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.health_and_safety_outlined,
                  color: colors.primary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Fleet readiness',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 8),

            Text(
              'Readiness information for units returned by the '
              'authorised response service.',
              style: theme.textTheme.bodyMedium,
            ),

            const SizedBox(height: 12),

            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(
                  avatar: const Icon(
                    Icons.airport_shuttle_outlined,
                    size: 18,
                  ),
                  label: Text('${units.length} listed'),
                ),
                Chip(
                  avatar: const Icon(
                    Icons.check_circle_outline,
                    size: 18,
                  ),
                  label: Text('$eligible eligible'),
                ),
                Chip(
                  avatar: const Icon(
                    Icons.warning_amber_outlined,
                    size: 18,
                  ),
                  label: Text('$unavailable not verified eligible'),
                ),
              ],
            ),

            const SizedBox(height: 8),

            Text(
              'Snapshot verified: ${_date(snapshotVerifiedAt)}',
              style: theme.textTheme.bodySmall,
            ),

            const SizedBox(height: 4),

            Text(
              'This is not a hospital-wide fleet count. '
              'An eligible result is server-reported and may change. '
              'Assignment must be revalidated by the backend.',
              style: theme.textTheme.bodySmall,
            ),

            if (units.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 16),
                child: Text(
                  'No fleet units returned. Availability cannot be confirmed.',
                ),
              ),

            for (final unit in units) ...[
              const Divider(height: 24),
              _ReadinessUnitCard(unit: unit),
            ],
          ],
        ),
      ),
    );
  }
}

class _ReadinessUnitCard extends StatelessWidget {
  const _ReadinessUnitCard({
    required this.unit,
  });

  final Map<String, dynamic> unit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    final eligibilityReason = FleetReadinessPanel._read(
      unit['reason'],
      'Not verified',
    );

    final hasIdentity =
        FleetReadinessPanel._hasIdentity(unit);

    final eligible =
        FleetReadinessPanel._serverEligible(unit);

    final rawReview = unit['review'];
    final review =
        rawReview is Map ? rawReview : null;

    final reviewReason = review == null
        ? 'No readiness review returned'
        : FleetReadinessPanel._read(
            review['reason'],
            'Reason not recorded',
          );

    final recordedAt = review == null
        ? 'Not recorded'
        : FleetReadinessPanel._date(
            review['recorded_at'],
          );

    final validUntil = review == null
        ? 'Not recorded'
        : FleetReadinessPanel._date(
            review['valid_until'],
          );

    final reviewer = review == null
        ? 'Not recorded'
        : FleetReadinessPanel._read(
            review['actor'],
            'Not recorded',
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              eligible
                  ? Icons.verified_outlined
                  : Icons.report_problem_outlined,
              color: eligible
                  ? colors.primary
                  : colors.error,
            ),

            const SizedBox(width: 8),

            Expanded(
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  Text(
                    FleetReadinessPanel._read(
                      unit['label'],
                      'Unnamed ambulance',
                    ),
                    style:
                        theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  const SizedBox(height: 4),

                  Text(
                    eligible
                        ? 'Server eligibility: Eligible'
                        : 'Not verified eligible: $eligibilityReason',
                  ),
                ],
              ),
            ),
          ],
        ),

        if (!hasIdentity)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Unit identity or version is missing. '
              'The unit cannot be safely selected for an assignment.',
              style: TextStyle(color: colors.error),
            ),
          ),

        const SizedBox(height: 10),

        Text(
          'Readiness review',
          style: theme.textTheme.labelLarge,
        ),

        const SizedBox(height: 5),

        Text('Reason: $reviewReason'),
        Text('Recorded: $recordedAt'),
        Text('Expires: $validUntil'),
        Text('Reviewer: $reviewer'),

        if (unit['can_review'] == true) ...[
          const SizedBox(height: 6),
          const Text(
            'A readiness review may be available to an authorised '
            'operator in the incident fleet workspace.',
          ),
        ],

        const SizedBox(height: 8),

        Text(
          'No readiness status is changed by this panel.',
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }
}
