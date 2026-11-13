import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../services/reception_service.dart';
import '../../theme/app_theme.dart';

class ReceptionQueuePage extends StatefulWidget {
  const ReceptionQueuePage({super.key});

  @override
  State<ReceptionQueuePage> createState() => _ReceptionQueuePageState();
}

class _ReceptionQueuePageState extends State<ReceptionQueuePage> {
  final ReceptionService _service = ReceptionService();

  List<ReceptionQueueItem> _queue = <ReceptionQueueItem>[];

  Timer? _autoRefresh;

  bool _loading = true;
  String? _error;
  String? _actioningId;

  String _statusFilter = 'all';
  String _departmentFilter = 'all';
  String _doctorFilter = 'all';
  bool _onlyUrgent = false;

  @override
  void initState() {
    super.initState();
    _loadQueue();

    _autoRefresh = Timer.periodic(
      const Duration(seconds: 20),
      (_) => _loadQueue(showLoading: false),
    );
  }

  @override
  void dispose() {
    _autoRefresh?.cancel();
    super.dispose();
  }

  Future<void> _loadQueue({
    bool showLoading = true,
  }) async {
    if (showLoading && mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final queue = await _service.loadTodayQueue();

      if (!mounted) {
        return;
      }

      setState(() {
        _queue = queue;
        _error = null;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _error = error.toString();
      });
    } finally {
      if (mounted && showLoading) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  List<ReceptionQueueItem> get _filteredQueue {
    final list = _queue.where((item) {
      final status = _statusKey(item.queueStatus);

      if (_onlyUrgent && !item.isUrgent) {
        return false;
      }

      if (_statusFilter != 'all' && status != _statusFilter) {
        return false;
      }

      if (_departmentFilter != 'all' &&
          item.departmentName != _departmentFilter) {
        return false;
      }

      if (_doctorFilter != 'all' && item.doctorName != _doctorFilter) {
        return false;
      }

      return true;
    }).toList();

    list.sort((left, right) {
      if (left.isUrgent != right.isUrgent) {
        return left.isUrgent ? -1 : 1;
      }

      final leftTime = left.checkedInAt ?? left.appointmentTime;
      final rightTime = right.checkedInAt ?? right.appointmentTime;

      if (leftTime == null && rightTime == null) {
        return 0;
      }

      if (leftTime == null) {
        return 1;
      }

      if (rightTime == null) {
        return -1;
      }

      return leftTime.compareTo(rightTime);
    });

    return list;
  }

  List<String> get _departments {
    final values = _queue
        .map((item) => item.departmentName)
        .where((value) => value.trim().isNotEmpty)
        .toSet()
        .toList()
      ..sort();

    return values;
  }

  List<String> get _doctors {
    final values = _queue
        .map((item) => item.doctorName)
        .where(
          (value) =>
              value.trim().isNotEmpty && value.toLowerCase() != 'unassigned',
        )
        .toSet()
        .toList()
      ..sort();

    return values;
  }

  Future<void> _showActions(ReceptionQueueItem item) async {
    final status = _statusKey(item.queueStatus);
    final isClosed =
        status == 'completed' || status == 'cancelled' || status == 'no_show';

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(item.patientName),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${item.departmentName} • ${item.doctorName}',
                ),
                const SizedBox(height: 8),
                Text(
                  'Current status: ${_prettyStatus(item.queueStatus)}',
                ),
                const SizedBox(height: 18),
                if (!isClosed && status == 'waiting')
                  _dialogActionButton(
                    icon: Icons.campaign_rounded,
                    label: 'Call Patient',
                    color: Colors.deepPurple,
                    onPressed: () async {
                      Navigator.of(dialogContext).pop();

                      await _runAction(
                        item: item,
                        nextStatus: 'called',
                        note: 'Patient called by Reception',
                        title: 'Call patient?',
                        message:
                            'Mark ${item.patientName} as called in the queue?',
                      );
                    },
                  ),
                if (!isClosed && status == 'called')
                  _dialogActionButton(
                    icon: Icons.schedule_rounded,
                    label: 'Return to Waiting',
                    color: Colors.orange.shade800,
                    onPressed: () async {
                      Navigator.of(dialogContext).pop();

                      await _runAction(
                        item: item,
                        nextStatus: 'waiting',
                        note: 'Returned to waiting by Reception',
                        title: 'Return to waiting?',
                        message:
                            'Move ${item.patientName} back into the waiting queue?',
                      );
                    },
                  ),
                if (!isClosed)
                  _dialogActionButton(
                    icon: item.isUrgent
                        ? Icons.arrow_downward_rounded
                        : Icons.priority_high_rounded,
                    label: item.isUrgent
                        ? 'Clear Urgent Status'
                        : 'Mark as Urgent',
                    color: item.isUrgent ? Colors.blueGrey : Colors.red,
                    onPressed: () async {
                      Navigator.of(dialogContext).pop();

                      await _runAction(
                        item: item,
                        nextStatus: status,
                        makeUrgent: !item.isUrgent,
                        note: item.isUrgent
                            ? 'Urgent status cleared by Reception'
                            : 'Marked urgent by Reception',
                        title: item.isUrgent
                            ? 'Clear urgent status?'
                            : 'Mark as urgent?',
                        message: item.isUrgent
                            ? 'Return ${item.patientName} to normal queue priority?'
                            : 'Move ${item.patientName} above normal queue entries?',
                      );
                    },
                  ),
                if (!isClosed)
                  _dialogActionButton(
                    icon: Icons.person_off_rounded,
                    label: 'Mark No Show',
                    color: Colors.grey.shade700,
                    onPressed: () async {
                      Navigator.of(dialogContext).pop();

                      await _runAction(
                        item: item,
                        nextStatus: 'no_show',
                        note: 'Marked no-show by Reception',
                        title: 'Mark no-show?',
                        message:
                            'Mark ${item.patientName} as not arriving today?',
                      );
                    },
                  ),
                if (!isClosed)
                  _dialogActionButton(
                    icon: Icons.cancel_outlined,
                    label: 'Cancel Check-In',
                    color: Colors.red,
                    onPressed: () async {
                      Navigator.of(dialogContext).pop();

                      await _runAction(
                        item: item,
                        nextStatus: 'cancelled',
                        note: 'Check-in cancelled by Reception',
                        title: 'Cancel check-in?',
                        message:
                            'Remove ${item.patientName} from the active Reception queue?',
                      );
                    },
                  ),
                if (isClosed)
                  Text(
                    'This queue entry is closed and can no longer be changed by Reception.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: context.cTextSecondary,
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  Widget _dialogActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: onPressed,
          icon: Icon(icon, color: color),
          label: Text(label),
        ),
      ),
    );
  }

  Future<void> _runAction({
    required ReceptionQueueItem item,
    required String nextStatus,
    required String note,
    required String title,
    required String message,
    bool? makeUrgent,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Confirm'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) {
      return;
    }

    setState(() {
      _actioningId = item.id;
    });

    try {
      await _service.updateQueueStatus(
        checkInId: item.id,
        newStatus: nextStatus,
        makeUrgent: makeUrgent,
        note: note,
      );

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${item.patientName} updated successfully.'),
        ),
      );

      await _loadQueue(showLoading: false);
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_cleanError(error)),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _actioningId = null;
        });
      }
    }
  }

  void _clearFilters() {
    setState(() {
      _statusFilter = 'all';
      _departmentFilter = 'all';
      _doctorFilter = 'all';
      _onlyUrgent = false;
    });
  }

  String _statusKey(String status) {
    return status.trim().toLowerCase().replaceAll(' ', '_');
  }

  String _prettyStatus(String value) {
    if (value.trim().isEmpty) {
      return 'Waiting';
    }

    return value
        .replaceAll('_', ' ')
        .split(' ')
        .where((word) => word.isNotEmpty)
        .map(
          (word) => '${word[0].toUpperCase()}${word.substring(1)}',
        )
        .join(' ');
  }

  String _cleanError(Object error) {
    return error
        .toString()
        .replaceFirst('Exception: ', '')
        .replaceAll('PostgrestException(message: ', '')
        .replaceAll(')', '');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.cBgPrimary,
      appBar: AppBar(
        title: const Text('Live Waiting Queue'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : _loadQueue,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        color: CorviaColors.accent,
        onRefresh: _loadQueue,
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (_error != null) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 100),
          Icon(
            Icons.cloud_off_rounded,
            size: 58,
            color: Colors.red.shade400,
          ),
          const SizedBox(height: 14),
          Text(
            _cleanError(_error!),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _loadQueue,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Try Again'),
          ),
        ],
      );
    }

    if (_queue.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 120),
          Icon(
            Icons.event_seat_outlined,
            size: 58,
            color: context.cTextSecondary,
          ),
          const SizedBox(height: 14),
          Text(
            'No patients are checked in today.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: context.cTextPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Use Search Patient or New Walk-In to start the queue.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: context.cTextSecondary,
            ),
          ),
        ],
      );
    }

    final visibleQueue = _filteredQueue;

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Auto-refreshes every 20 seconds. Urgent patients appear first.',
          style: TextStyle(
            color: context.cTextSecondary,
            fontSize: 13,
          ),
        ),
        const SizedBox(height: 12),
        _filters(),
        const SizedBox(height: 14),
        if (visibleQueue.isEmpty)
          _emptyFilteredQueue()
        else
          ...visibleQueue.map(_queueCard),
      ],
    );
  }

  Widget _filters() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        FilterChip(
          label: const Text('Urgent only'),
          selected: _onlyUrgent,
          onSelected: (selected) {
            setState(() {
              _onlyUrgent = selected;
            });
          },
        ),
        _filterMenu(
          current: _statusFilter,
          label: 'Status',
          values: const [
            'all',
            'waiting',
            'called',
            'with_doctor',
            'completed',
            'no_show',
            'cancelled',
          ],
          onChanged: (value) {
            setState(() {
              _statusFilter = value;
            });
          },
        ),
        _filterMenu(
          current: _departmentFilter,
          label: 'Department',
          values: ['all', ..._departments],
          onChanged: (value) {
            setState(() {
              _departmentFilter = value;
            });
          },
        ),
        _filterMenu(
          current: _doctorFilter,
          label: 'Doctor',
          values: ['all', ..._doctors],
          onChanged: (value) {
            setState(() {
              _doctorFilter = value;
            });
          },
        ),
        TextButton.icon(
          onPressed: _clearFilters,
          icon: const Icon(Icons.clear_all_rounded),
          label: const Text('Clear'),
        ),
      ],
    );
  }

  Widget _filterMenu({
    required String current,
    required String label,
    required List<String> values,
    required ValueChanged<String> onChanged,
  }) {
    return PopupMenuButton<String>(
      onSelected: onChanged,
      itemBuilder: (context) {
        return values
            .map(
              (value) => PopupMenuItem<String>(
                value: value,
                child: Text(
                  value == 'all'
                      ? 'All $label'
                      : label == 'Status'
                          ? _prettyStatus(value)
                          : value,
                ),
              ),
            )
            .toList();
      },
      child: Chip(
        label: Text(
          current == 'all'
              ? label
              : label == 'Status'
                  ? _prettyStatus(current)
                  : current,
        ),
        avatar: const Icon(
          Icons.filter_list_rounded,
          size: 18,
        ),
      ),
    );
  }

  Widget _emptyFilteredQueue() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: context.cBgSecondary,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: CorviaColors.divider),
      ),
      child: Column(
        children: [
          Icon(
            Icons.filter_alt_off_rounded,
            size: 42,
            color: context.cTextSecondary,
          ),
          const SizedBox(height: 10),
          Text(
            'No patients match these filters.',
            style: TextStyle(
              color: context.cTextPrimary,
              fontWeight: FontWeight.w800,
            ),
          ),
          TextButton(
            onPressed: _clearFilters,
            child: const Text('Clear filters'),
          ),
        ],
      ),
    );
  }

  Widget _queueCard(ReceptionQueueItem item) {
    final statusColor = _statusColor(item);

    final checkedIn = item.checkedInAt == null
        ? 'Unknown'
        : DateFormat('HH:mm').format(item.checkedInAt!);

    final appointment = item.appointmentTime == null
        ? 'Walk-in'
        : DateFormat('HH:mm').format(item.appointmentTime!);

    final isActioning = _actioningId == item.id;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: context.cBgSecondary,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: item.isUrgent
              ? Colors.red.withValues(alpha: 0.8)
              : CorviaColors.divider,
          width: item.isUrgent ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  item.patientName,
                  style: TextStyle(
                    color: context.cTextPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              _statusBadge(
                item.isUrgent ? 'URGENT' : _prettyStatus(item.queueStatus),
                item.isUrgent ? Colors.red : statusColor,
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            item.patientNumber,
            style: TextStyle(
              color: context.cTextSecondary,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 11),
          Wrap(
            spacing: 14,
            runSpacing: 8,
            children: [
              _detail(Icons.local_hospital_rounded, item.departmentName),
              _detail(Icons.person_outline_rounded, item.doctorName),
              _detail(Icons.login_rounded, 'Checked in $checkedIn'),
              _detail(Icons.event_rounded, 'Appointment $appointment'),
              if (item.isWalkIn)
                _detail(Icons.directions_walk_rounded, 'Walk-in'),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            item.visitReason,
            style: TextStyle(
              color: context.cTextPrimary,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton.icon(
              onPressed: isActioning ? null : () => _showActions(item),
              icon: isActioning
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.more_horiz_rounded),
              label: Text(isActioning ? 'Updating...' : 'Manage'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _detail(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 15,
          color: context.cTextSecondary,
        ),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            text,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: context.cTextSecondary,
              fontSize: 12,
            ),
          ),
        ),
      ],
    );
  }

  Widget _statusBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 9,
        vertical: 5,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Color _statusColor(ReceptionQueueItem item) {
    final status = _statusKey(item.queueStatus);

    if (item.isUrgent || status.contains('emergency')) {
      return Colors.red;
    }

    if (status == 'completed') {
      return Colors.green;
    }

    if (status == 'called') {
      return Colors.deepPurple;
    }

    if (status == 'with_doctor') {
      return Colors.teal;
    }

    if (status == 'cancelled' || status == 'no_show') {
      return Colors.grey;
    }

    return Colors.orange.shade800;
  }
}
