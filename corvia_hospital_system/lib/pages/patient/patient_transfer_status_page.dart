import 'package:flutter/material.dart';

import '../../services/patient_transfer_status_service.dart';
import '../../theme/app_theme.dart';

class PatientTransferStatusPage extends StatefulWidget {
  const PatientTransferStatusPage({
    super.key,
    required this.transferId,
  });

  final String transferId;

  @override
  State<PatientTransferStatusPage> createState() =>
      _PatientTransferStatusPageState();
}

class _PatientTransferStatusPageState extends State<PatientTransferStatusPage> {
  final PatientTransferStatusService _service = PatientTransferStatusService();

  bool _loading = true;
  String? _error;

  PatientTransferStatusRecord? _transfer;

  @override
  void initState() {
    super.initState();
    _loadTransfer();
  }

  Future<void> _loadTransfer() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final transfer = await _service.loadTransferStatus(
        widget.transferId,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _transfer = transfer;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  String _formatDate(DateTime? value) {
    if (value == null) {
      return 'Not available';
    }

    final year = value.year.toString();
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');

    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');

    return '$year-$month-$day $hour:$minute';
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'accepted':
      case 'received':
      case 'completed':
        return CorviaColors.success;

      case 'requested':
      case 'ready_for_transfer':
        return CorviaColors.warning;

      case 'rejected':
      case 'cancelled':
        return CorviaColors.danger;

      default:
        return context.cAccentReadable;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.cBgPrimary,
      appBar: AppBar(
        backgroundColor: context.cBgSecondary,
        foregroundColor: context.cTextPrimary,
        title: const Text(
          'Hospital Transfer',
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : _loadTransfer,
            icon: const Icon(
              Icons.refresh_rounded,
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? Center(
                child: CircularProgressIndicator(
                  color: context.cAccentReadable,
                ),
              )
            : _error != null
                ? _buildErrorState()
                : _transfer == null
                    ? _buildEmptyState()
                    : _buildTransferBody(
                        _transfer!,
                      ),
      ),
    );
  }

  Widget _buildTransferBody(
    PatientTransferStatusRecord transfer,
  ) {
    final statusColor = _statusColor(transfer.status);

    return RefreshIndicator(
      onRefresh: _loadTransfer,
      child: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: context.cBgSecondary,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: context.cDivider,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: statusColor.withValues(
                          alpha: 0.10,
                        ),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Icon(
                        Icons.compare_arrows_rounded,
                        color: statusColor,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            transfer.transferNumber,
                            style: TextStyle(
                              color: context.cTextPrimary,
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            transfer.displayStatus,
                            style: TextStyle(
                              color: statusColor,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),
                    ),
                    _statusBadge(
                      transfer.displayPriority,
                      transfer.priority == 'critical' ||
                              transfer.priority == 'emergency'
                          ? CorviaColors.danger
                          : transfer.priority == 'urgent'
                              ? CorviaColors.warning
                              : context.cAccentReadable,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  transfer.statusMessage,
                  style: TextStyle(
                    color: context.cTextSecondary,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _section(
            title: 'Hospital Route',
            icon: Icons.route_rounded,
            child: Column(
              children: [
                _hospitalRow(
                  icon: Icons.local_hospital_rounded,
                  label: 'Source hospital',
                  value: transfer.sourceHospitalName,
                ),
                Container(
                  margin: const EdgeInsets.symmetric(
                    vertical: 8,
                  ),
                  height: 28,
                  width: 2,
                  color: context.cDivider,
                ),
                _hospitalRow(
                  icon: Icons.flag_rounded,
                  label: 'Destination hospital',
                  value: transfer.destinationHospitalName,
                ),
                const SizedBox(height: 12),
                _detailLine(
                  'Destination location',
                  transfer.destinationLocation,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _section(
            title: 'Estimated Times',
            icon: Icons.schedule_rounded,
            child: Column(
              children: [
                _detailLine(
                  'Estimated departure',
                  _formatDate(
                    transfer.estimatedDepartureAt,
                  ),
                ),
                _detailLine(
                  'Estimated arrival',
                  _formatDate(
                    transfer.estimatedArrivalAt,
                  ),
                ),
                if (transfer.actualDepartureAt != null)
                  _detailLine(
                    'Actual departure',
                    _formatDate(
                      transfer.actualDepartureAt,
                    ),
                  ),
                if (transfer.actualArrivalAt != null)
                  _detailLine(
                    'Actual arrival',
                    _formatDate(
                      transfer.actualArrivalAt,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _section(
            title: 'Transfer Progress',
            icon: Icons.timeline_rounded,
            child: Column(
              children: transfer.milestones.map(
                (milestone) {
                  return _milestoneTile(milestone);
                },
              ).toList(),
            ),
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: context.cAccentReadable.withValues(
                alpha: 0.07,
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: context.cAccentReadable.withValues(
                  alpha: 0.18,
                ),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.privacy_tip_rounded,
                  color: context.cAccentReadable,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Clinical transfer documents and medical handover information are only available to authorised hospital staff.',
                    style: TextStyle(
                      color: context.cTextSecondary,
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _section({
    required String title,
    required IconData icon,
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: context.cBgSecondary,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: context.cDivider,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                icon,
                color: context.cAccentReadable,
              ),
              const SizedBox(width: 10),
              Text(
                title,
                style: TextStyle(
                  color: context.cTextPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }

  Widget _hospitalRow({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: context.cAccentReadable.withValues(
              alpha: 0.09,
            ),
            borderRadius: BorderRadius.circular(13),
          ),
          child: Icon(
            icon,
            color: context.cAccentReadable,
            size: 21,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: context.cTextSecondary,
                  fontSize: 11,
                ),
              ),
              Text(
                value,
                style: TextStyle(
                  color: context.cTextPrimary,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _milestoneTile(
    PatientTransferMilestone milestone,
  ) {
    final color = milestone.negative
        ? CorviaColors.danger
        : milestone.completed
            ? CorviaColors.success
            : milestone.current
                ? CorviaColors.warning
                : context.cTextSecondary;

    return Padding(
      padding: const EdgeInsets.only(
        bottom: 14,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.10),
              shape: BoxShape.circle,
              border: Border.all(
                color: color.withValues(alpha: 0.35),
              ),
            ),
            child: Icon(
              milestone.completed
                  ? Icons.check_rounded
                  : milestone.current
                      ? Icons.more_horiz_rounded
                      : Icons.circle_outlined,
              color: color,
              size: 16,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  milestone.label,
                  style: TextStyle(
                    color: milestone.completed || milestone.current
                        ? context.cTextPrimary
                        : context.cTextSecondary,
                    fontWeight:
                        milestone.current ? FontWeight.w900 : FontWeight.w700,
                  ),
                ),
                if (milestone.date != null)
                  Text(
                    _formatDate(milestone.date),
                    style: TextStyle(
                      color: context.cTextSecondary,
                      fontSize: 11,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _detailLine(
    String label,
    String value,
  ) {
    return Padding(
      padding: const EdgeInsets.only(
        bottom: 8,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 150,
            child: Text(
              label,
              style: TextStyle(
                color: context.cTextPrimary,
                fontWeight: FontWeight.w800,
                fontSize: 12,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: context.cTextSecondary,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusBadge(
    String label,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: color.withValues(alpha: 0.24),
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Container(
        constraints: const BoxConstraints(
          maxWidth: 520,
        ),
        margin: const EdgeInsets.all(20),
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: CorviaColors.danger.withValues(
            alpha: 0.07,
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: CorviaColors.danger.withValues(
              alpha: 0.24,
            ),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline_rounded,
              color: CorviaColors.danger,
              size: 42,
            ),
            const SizedBox(height: 12),
            Text(
              'Transfer could not load',
              style: TextStyle(
                color: context.cTextPrimary,
                fontWeight: FontWeight.w900,
                fontSize: 17,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _error ?? 'Unknown error',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: context.cTextSecondary,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: _loadTransfer,
              icon: const Icon(
                Icons.refresh_rounded,
              ),
              label: const Text('Try Again'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Text(
        'Transfer information is not available.',
        style: TextStyle(
          color: context.cTextSecondary,
        ),
      ),
    );
  }
}
