
import 'package:flutter/material.dart';

/// Displays recorded incident and response-unit positions.
///
/// Positions and freshness flags must come from the existing
/// authenticated response snapshot. This widget makes no
/// network requests and never represents recorded GPS as
/// continuous live tracking.
class GpsLocationPanel extends StatelessWidget {
  const GpsLocationPanel({
    super.key,
    required this.incidentLocation,
    required this.assignments,
    required this.snapshotVerifiedAt,
  });

  final Map<String, dynamic> incidentLocation;
  final List<Map<String, dynamic>> assignments;
  final DateTime snapshotVerifiedAt;

  static String _read(Object? value, String fallback) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? fallback : text;
  }

  static DateTime? _parseTime(Object? value) {
    if (value is DateTime) return value;
    if (value == null) return null;
    return DateTime.tryParse(value.toString());
  }

  static String _formatTime(Object? value) {
    final date = _parseTime(value);

    if (date == null) return 'Not recorded';

    final local = date.toLocal();

    String two(int number) {
      return number.toString().padLeft(2, '0');
    }

    return '${two(local.day)}/${two(local.month)}/${local.year} '
        '${two(local.hour)}:${two(local.minute)}';
  }

  static bool _validCoordinates(
    Map<String, dynamic> position,
  ) {
    final latitude = position['latitude'];
    final longitude = position['longitude'];

    if (latitude is! num || longitude is! num) {
      return false;
    }

    final lat = latitude.toDouble();
    final lon = longitude.toDouble();

    return lat.isFinite &&
        lon.isFinite &&
        lat >= -90 &&
        lat <= 90 &&
        lon >= -180 &&
        lon <= 180;
  }

  static bool _stale(
    Map<String, dynamic> position,
  ) {
    return position['location_stale'] == true ||
        position['location_fresh'] == false;
  }

  static String _freshness(
    Map<String, dynamic> position,
  ) {
    if (!_validCoordinates(position)) {
      return 'Location unavailable or invalid';
    }

    final stale = position['location_stale'];
    final fresh = position['location_fresh'];

    if (stale == true && fresh == true) {
      return 'Conflicting backend freshness flags';
    }

    if (stale == true || fresh == false) {
      return 'STALE - backend flag';
    }

    if (fresh == true) {
      return 'Backend reports fresh - not live GPS';
    }

    if (stale == false) {
      return 'Backend reports not stale - not live GPS';
    }

    return 'Freshness not verified';
  }

  static bool _needsAttention(
    Map<String, dynamic> position,
  ) {
    if (!_validCoordinates(position)) return true;

    if (position['location_stale'] == true &&
        position['location_fresh'] == true) {
      return true;
    }

    return _stale(position);
  }

  static String _coordinates(
    Map<String, dynamic> position,
  ) {
    if (!_validCoordinates(position)) {
      return 'No valid coordinates recorded';
    }

    final latitude = position['latitude'] as num;
    final longitude = position['longitude'] as num;

    return '${latitude.toStringAsFixed(5)}, '
        '${longitude.toStringAsFixed(5)}';
  }

  static String _accuracy(
    Map<String, dynamic> position,
  ) {
    final accuracy = position['accuracy_metres'];

    if (accuracy is! num ||
        !accuracy.toDouble().isFinite ||
        accuracy < 0) {
      return 'Not recorded';
    }

    return '${accuracy.toStringAsFixed(1)} m';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    final activeAssignments = assignments.where(
      (assignment) => assignment['active'] == true,
    ).toList();

    final locationAlerts = activeAssignments.where(
      _needsAttention,
    ).length;

    return Card(
      key: const ValueKey('gps-location-panel'),
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.location_on_outlined,
                  color: colors.primary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'GPS & location monitoring',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 8),

            Text(
              'Recorded incident and response-unit positions '
              'from the authorised dispatch snapshot.',
              style: theme.textTheme.bodyMedium,
            ),

            const SizedBox(height: 10),

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
                  label: Text(
                    '${activeAssignments.length} active',
                  ),
                ),
                if (locationAlerts > 0)
                  Chip(
                    avatar: Icon(
                      Icons.warning_amber_outlined,
                      color: colors.error,
                      size: 18,
                    ),
                    label: Text(
                      '$locationAlerts location alerts',
                    ),
                  ),
              ],
            ),

            const SizedBox(height: 8),

            Text(
              'Snapshot verified: '
              '${_formatTime(snapshotVerifiedAt)}',
              style: theme.textTheme.bodySmall,
            ),

            const SizedBox(height: 8),

            Text(
              'These are recorded positions, not continuous '
              'live tracking. Only server-provided freshness '
              'flags are used to classify a position as stale '
              'or fresh. Missing flags remain unverified.',
              style: theme.textTheme.bodySmall,
            ),

            const Divider(height: 28),

            Text(
              'Incident location',
              style: theme.textTheme.titleSmall,
            ),

            const SizedBox(height: 8),

            _RecordedPosition(
              label: 'Reported scene position',
              position: incidentLocation,
            ),

            const Divider(height: 28),

            Text(
              'Response-unit locations',
              style: theme.textTheme.titleSmall,
            ),

            if (assignments.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'No response assignments returned. '
                  'Unit positions cannot be verified.',
                ),
              ),

            for (final assignment in assignments) ...[
              const SizedBox(height: 12),

              _RecordedPosition(
                label:
                    'Unit: ${_read(assignment['unit'], 'Unknown')} '
                    '- Crew: ${_read(assignment['crew'], 'Unknown')}',
                position: assignment,
                active: assignment['active'] == true,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _RecordedPosition extends StatelessWidget {
  const _RecordedPosition({
    required this.label,
    required this.position,
    this.active,
  });

  final String label;
  final Map<String, dynamic> position;
  final bool? active;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    final attention = GpsLocationPanel._needsAttention(
      position,
    );

    final coordinates = GpsLocationPanel._coordinates(
      position,
    );

    final freshness = GpsLocationPanel._freshness(
      position,
    );

    final source = GpsLocationPanel._read(
      position['location_source'] ??
          position['position_source'],
      'Not recorded',
    );

    final captured = GpsLocationPanel._formatTime(
      position['location_at'] ??
          position['captured_at'],
    );

    final accuracy = GpsLocationPanel._accuracy(
      position,
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: attention
              ? colors.error.withValues(alpha: 0.5)
              : colors.outlineVariant,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                attention
                    ? Icons.warning_amber_outlined
                    : Icons.location_on_outlined,
                color: attention
                    ? colors.error
                    : colors.primary,
              ),

              const SizedBox(width: 8),

              Expanded(
                child: Text(
                  label,
                  style: theme.textTheme.titleSmall,
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          if (active != null)
            Text(
              active!
                  ? 'Assignment: Active'
                  : 'Assignment: Inactive',
            ),

          const SizedBox(height: 5),

          SelectableText(
            'Coordinates: $coordinates',
          ),

          const SizedBox(height: 5),

          Text(
            'Freshness: $freshness',
            style: TextStyle(
              color: attention
                  ? colors.error
                  : colors.onSurface,
              fontWeight: attention
                  ? FontWeight.w600
                  : FontWeight.normal,
            ),
          ),

          const SizedBox(height: 5),

          Text('Source: $source'),

          Text('Recorded: $captured'),

          Text('Accuracy: $accuracy'),

          if (attention)
            Padding(
              padding: const EdgeInsets.only(top: 9),
              child: Text(
                'Location requires dispatch review. '
                'Do not assume this is the current '
                'physical position of the unit.',
                style: TextStyle(
                  color: colors.error,
                ),
              ),
            ),

          if (!attention)
            Padding(
              padding: const EdgeInsets.only(top: 9),
              child: Text(
                'Freshness must be interpreted using '
                'the recorded timestamp and backend '
                'status. A position is not a live feed.',
                style: theme.textTheme.bodySmall,
              ),
            ),
        ],
      ),
    );
  }
}
