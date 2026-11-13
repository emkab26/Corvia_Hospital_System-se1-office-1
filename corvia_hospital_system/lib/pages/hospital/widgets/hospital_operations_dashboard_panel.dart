import 'package:flutter/material.dart';

import '../../../../../services/hospital_operations_service.dart';
import '../../../../../theme/app_theme.dart';

class HospitalOperationsDashboardPanel extends StatefulWidget {
  const HospitalOperationsDashboardPanel({
    super.key,
    required this.hospitalId,
    required this.onOpenAdmissions,
    required this.onOpenBedBoard,
    required this.onOpenStructure,
  });

  final String hospitalId;

  final VoidCallback onOpenAdmissions;
  final VoidCallback onOpenBedBoard;
  final VoidCallback onOpenStructure;

  @override
  State<HospitalOperationsDashboardPanel> createState() =>
      _HospitalOperationsDashboardPanelState();
}

class _HospitalOperationsDashboardPanelState
    extends State<HospitalOperationsDashboardPanel> {
  final HospitalOperationsService _service = HospitalOperationsService();

  bool _loading = true;
  String? _error;

  HospitalOperationsStats? _stats;

  @override
  void initState() {
    super.initState();

    _loadStats();
  }

  @override
  void didUpdateWidget(
    covariant HospitalOperationsDashboardPanel oldWidget,
  ) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.hospitalId != widget.hospitalId) {
      _loadStats();
    }
  }

  Future<void> _loadStats() async {
    if (widget.hospitalId.trim().isEmpty) {
      return;
    }

    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final stats = await _service.loadStats(
        widget.hospitalId,
      );

      if (!mounted) return;

      setState(() {
        _stats = stats;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  Color _occupancyColor(
    HospitalOperationsStats stats,
  ) {
    if (stats.hasCriticalCapacityWarning) {
      return CorviaColors.danger;
    }

    if (stats.hasCapacityWarning) {
      return CorviaColors.warning;
    }

    return CorviaColors.success;
  }

  String _formatGeneratedAt(DateTime? value) {
    if (value == null) {
      return 'Not refreshed yet';
    }

    return '${value.year}-'
        '${value.month.toString().padLeft(2, '0')}-'
        '${value.day.toString().padLeft(2, '0')} '
        '${value.hour.toString().padLeft(2, '0')}:'
        '${value.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: context.cBgSecondary,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: context.cDivider,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(),
          const SizedBox(height: 16),
          if (_loading)
            _buildLoadingState()
          else if (_error != null)
            _buildErrorState()
          else if (_stats != null)
            _buildStats(_stats!),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 560;

        final heading = Row(
          children: [
            Container(
              height: 44,
              width: 44,
              decoration: BoxDecoration(
                color: context.cAccentReadable.withValues(
                  alpha: 0.10,
                ),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                Icons.hotel_rounded,
                color: context.cAccentReadable,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Admissions & Bed Capacity',
                    style: TextStyle(
                      color: context.cTextPrimary,
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'Live admission, assignment and bed-status overview',
                    style: TextStyle(
                      color: context.cTextSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        );

        final actions = Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            TextButton(
              onPressed: widget.onOpenAdmissions,
              child: Text(
                'Admissions',
                style: TextStyle(
                  color: context.cAccentReadable,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            IconButton(
              tooltip: 'Refresh operations',
              onPressed: _loading ? null : _loadStats,
              icon: Icon(
                Icons.refresh_rounded,
                color: context.cAccentReadable,
              ),
            ),
          ],
        );

        if (compact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              heading,
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: actions,
              ),
            ],
          );
        }

        return Row(
          children: [
            Expanded(child: heading),
            const SizedBox(width: 10),
            actions,
          ],
        );
      },
    );
  }

  Widget _buildLoadingState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        vertical: 40,
      ),
      decoration: BoxDecoration(
        color: context.cBgPrimary,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: context.cDivider,
        ),
      ),
      child: Center(
        child: CircularProgressIndicator(
          color: context.cAccentReadable,
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: CorviaColors.danger.withValues(
          alpha: 0.07,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: CorviaColors.danger.withValues(
            alpha: 0.20,
          ),
        ),
      ),
      child: Column(
        children: [
          const Icon(
            Icons.error_outline_rounded,
            color: CorviaColors.danger,
            size: 34,
          ),
          const SizedBox(height: 9),
          Text(
            'Operations statistics could not load',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: context.cTextPrimary,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            _error ?? 'Unknown error',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: context.cTextSecondary,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.tonalIcon(
            onPressed: _loadStats,
            icon: const Icon(
              Icons.refresh_rounded,
            ),
            label: const Text('Try Again'),
          ),
        ],
      ),
    );
  }

  Widget _buildStats(
    HospitalOperationsStats stats,
  ) {
    final occupancyColor = _occupancyColor(stats);

    final cards = [
      _OperationsMetric(
        label: 'Active Admissions',
        value: stats.activeAdmissions,
        icon: Icons.hotel_rounded,
        color: CorviaColors.success,
      ),
      _OperationsMetric(
        label: 'Planned Admissions',
        value: stats.plannedAdmissions,
        icon: Icons.event_available_rounded,
        color: CorviaColors.warning,
      ),
      _OperationsMetric(
        label: 'Awaiting Bed',
        value: stats.admittedWithoutBed,
        icon: Icons.bed_outlined,
        color: stats.admittedWithoutBed > 0
            ? CorviaColors.danger
            : CorviaColors.success,
      ),
      _OperationsMetric(
        label: 'Available Beds',
        value: stats.availableBeds,
        icon: Icons.check_circle_rounded,
        color: CorviaColors.success,
      ),
      _OperationsMetric(
        label: 'Occupied Beds',
        value: stats.occupiedBeds,
        icon: Icons.person_rounded,
        color: CorviaColors.danger,
      ),
      _OperationsMetric(
        label: 'Cleaning Beds',
        value: stats.cleaningBeds,
        icon: Icons.cleaning_services_rounded,
        color: CorviaColors.warning,
      ),
      _OperationsMetric(
        label: 'Reserved Beds',
        value: stats.reservedBeds,
        icon: Icons.bookmark_rounded,
        color: context.cAccentReadable,
      ),
      _OperationsMetric(
        label: 'Unavailable Beds',
        value: stats.unavailableBeds,
        icon: Icons.build_circle_rounded,
        color: Colors.grey,
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 760
                ? 4
                : constraints.maxWidth >= 440
                    ? 2
                    : 1;

            const spacing = 10.0;

            final cardWidth =
                (constraints.maxWidth - ((columns - 1) * spacing)) / columns;

            return Wrap(
              spacing: spacing,
              runSpacing: spacing,
              children: cards.map((card) {
                return SizedBox(
                  width: cardWidth,
                  child: _MetricCard(
                    metric: card,
                  ),
                );
              }).toList(),
            );
          },
        ),
        const SizedBox(height: 16),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            color: context.cBgPrimary,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: context.cDivider,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Hospital Bed Occupancy',
                      style: TextStyle(
                        color: context.cTextPrimary,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  Text(
                    '${stats.occupancyPercentage.toStringAsFixed(1)}%',
                    style: TextStyle(
                      color: occupancyColor,
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 9),
              ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: LinearProgressIndicator(
                  value: stats.occupancyProgress,
                  minHeight: 10,
                  backgroundColor: context.cDivider.withValues(
                    alpha: 0.65,
                  ),
                  valueColor: AlwaysStoppedAnimation<Color>(
                    occupancyColor,
                  ),
                ),
              ),
              const SizedBox(height: 9),
              Text(
                '${stats.occupiedBeds} of '
                '${stats.activeBeds} active beds are occupied.',
                style: TextStyle(
                  color: context.cTextSecondary,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
        if (stats.hasAdmissionWarning || stats.hasCapacityWarning) ...[
          const SizedBox(height: 12),
          _OperationsWarning(
            stats: stats,
          ),
        ],
        const SizedBox(height: 14),
        LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 520;

            final admissionButton = FilledButton.tonalIcon(
              onPressed: widget.onOpenAdmissions,
              icon: const Icon(
                Icons.hotel_rounded,
              ),
              label: const Text(
                'Manage Admissions',
              ),
            );

            final bedBoardButton = OutlinedButton.icon(
              onPressed: widget.onOpenBedBoard,
              icon: const Icon(
                Icons.bed_rounded,
              ),
              label: const Text(
                'Live Bed Board',
              ),
            );

            final structureButton = OutlinedButton.icon(
              onPressed: widget.onOpenStructure,
              icon: const Icon(
                Icons.account_tree_rounded,
              ),
              label: const Text(
                'Hospital Structure',
              ),
            );

            if (compact) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  admissionButton,
                  const SizedBox(height: 9),
                  bedBoardButton,
                  const SizedBox(height: 9),
                  structureButton,
                ],
              );
            }

            return Wrap(
              spacing: 9,
              runSpacing: 9,
              children: [
                admissionButton,
                bedBoardButton,
                structureButton,
              ],
            );
          },
        ),
        const SizedBox(height: 10),
        Text(
          'Last calculated: '
          '${_formatGeneratedAt(stats.generatedAt)}',
          style: TextStyle(
            color: context.cTextSecondary,
            fontSize: 10,
          ),
        ),
      ],
    );
  }
}

class _OperationsMetric {
  const _OperationsMetric({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final int value;
  final IconData icon;
  final Color color;
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.metric,
  });

  final _OperationsMetric metric;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.cBgPrimary,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: context.cDivider,
        ),
      ),
      child: Row(
        children: [
          Container(
            height: 39,
            width: 39,
            decoration: BoxDecoration(
              color: metric.color.withValues(
                alpha: 0.10,
              ),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(
              metric.icon,
              color: metric.color,
              size: 20,
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  metric.value.toString(),
                  style: TextStyle(
                    color: context.cTextPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  metric.label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: context.cTextSecondary,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _OperationsWarning extends StatelessWidget {
  const _OperationsWarning({
    required this.stats,
  });

  final HospitalOperationsStats stats;

  @override
  Widget build(BuildContext context) {
    final critical = stats.hasCriticalCapacityWarning;

    final color = critical ? CorviaColors.danger : CorviaColors.warning;

    final messages = <String>[];

    if (stats.admittedWithoutBed > 0) {
      messages.add(
        '${stats.admittedWithoutBed} admitted patient'
        '${stats.admittedWithoutBed == 1 ? '' : 's'} '
        '${stats.admittedWithoutBed == 1 ? 'is' : 'are'} '
        'waiting for a bed assignment.',
      );
    }

    if (stats.hasCriticalCapacityWarning) {
      messages.add(
        'Bed occupancy is critically high at '
        '${stats.occupancyPercentage.toStringAsFixed(1)}%.',
      );
    } else if (stats.hasCapacityWarning) {
      messages.add(
        'Bed occupancy is high at '
        '${stats.occupancyPercentage.toStringAsFixed(1)}%.',
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: color.withValues(alpha: 0.24),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            critical ? Icons.error_rounded : Icons.warning_amber_rounded,
            color: color,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              messages.join(' '),
              style: TextStyle(
                color: context.cTextPrimary,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
