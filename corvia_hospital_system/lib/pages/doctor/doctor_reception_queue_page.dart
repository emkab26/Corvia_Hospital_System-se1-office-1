import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../theme/app_theme.dart';

class DoctorReceptionQueuePage extends StatefulWidget {
  const DoctorReceptionQueuePage({super.key});

  @override
  State<DoctorReceptionQueuePage> createState() =>
      _DoctorReceptionQueuePageState();
}

class _DoctorReceptionQueuePageState extends State<DoctorReceptionQueuePage> {
  final SupabaseClient _client = Supabase.instance.client;

  List<_DoctorQueueItem> _queue = <_DoctorQueueItem>[];

  Timer? _timer;

  bool _loading = true;
  String? _error;
  String? _actioningId;

  @override
  void initState() {
    super.initState();
    _loadQueue();

    _timer = Timer.periodic(
      const Duration(seconds: 20),
      (_) => _loadQueue(showLoading: false),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
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
      final response = await _client.rpc('doctor_reception_queue_today');

      final rows = response is List
          ? response
              .whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .toList()
          : <Map<String, dynamic>>[];

      final checkInIds = rows
          .map(
            (row) => (row['checkinId'] ?? row['checkin_id'] ?? row['id'])
                ?.toString()
                .trim(),
          )
          .whereType<String>()
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList();

      final storedReasons = await _loadStoredReasons(checkInIds);

      for (final row in rows) {
        final checkInId = (row['checkinId'] ?? row['checkin_id'] ?? row['id'])
            ?.toString()
            .trim();
        final reason = checkInId == null ? null : storedReasons[checkInId];
        if (reason != null && reason.trim().isNotEmpty) {
          row['reason'] = reason;
        }
      }

      final items = rows.map(_DoctorQueueItem.fromJson).toList();

      if (!mounted) {
        return;
      }

      setState(() {
        _queue = items;
        _error = null;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _error = _cleanError(error);
      });
    } finally {
      if (mounted && showLoading) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<Map<String, String>> _loadStoredReasons(
    List<String> checkInIds,
  ) async {
    if (checkInIds.isEmpty) return <String, String>{};

    List<dynamic> rows = const [];

    try {
      rows = await _client
          .from('reception_checkins')
          .select('id, reason')
          .inFilter('id', checkInIds);
    } catch (_) {
      // Some installations only expose assigned queue rows through an RPC.
    }

    if (rows.isEmpty) {
      try {
        final response = await _client.rpc(
          'doctor_reception_checkin_reasons',
          params: {'p_checkin_ids': checkInIds},
        );
        if (response is List) rows = response;
      } catch (_) {
        // Keep the queue usable if an older database migration is still live.
      }
    }

    final reasons = <String, String>{};
    for (final value in rows.whereType<Map>()) {
      final row = Map<String, dynamic>.from(value);
      final id = (row['checkin_id'] ?? row['id'])?.toString().trim();
      final reason = row['reason']?.toString().trim();
      if (id != null && id.isNotEmpty && reason != null && reason.isNotEmpty) {
        reasons[id] = reason;
      }
    }
    return reasons;
  }

  Future<void> _startConsultation(_DoctorQueueItem item) async {
    await _confirmAndUpdate(
      item: item,
      nextStatus: 'with_doctor',
      title: 'Start consultation?',
      message: 'Move ${item.patientName} to With Doctor?',
      note: 'Doctor started consultation',
    );
  }

  Future<void> _callPatient(_DoctorQueueItem item) async {
    await _confirmAndUpdate(
      item: item,
      nextStatus: 'called',
      title: 'Call patient?',
      message: 'Call ${item.patientName} for their consultation?',
      note: 'Patient called by Doctor',
      useDoctorCallRpc: true,
    );
  }

  Future<void> _completeConsultation(_DoctorQueueItem item) async {
    await _confirmAndUpdate(
      item: item,
      nextStatus: 'completed',
      title: 'Complete consultation?',
      message:
          'Mark ${item.patientName} as completed? This will update Reception queue.',
      note: 'Doctor completed consultation',
    );
  }

  Future<void> _confirmAndUpdate({
    required _DoctorQueueItem item,
    required String nextStatus,
    required String title,
    required String message,
    required String note,
    bool useDoctorCallRpc = false,
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
      _actioningId = item.checkinId;
    });

    try {
      if (useDoctorCallRpc) {
        await _client.rpc(
          'doctor_call_reception_patient',
          params: {
            'p_checkin_id': item.checkinId,
            'p_note': note,
          },
        );
      } else {
        await _client.rpc(
          'doctor_update_reception_queue_status',
          params: {
            'p_checkin_id': item.checkinId,
            'p_new_status': nextStatus,
            'p_note': note,
          },
        );
      }

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

  String _cleanError(Object error) {
    return error
        .toString()
        .replaceFirst('Exception: ', '')
        .replaceAll('PostgrestException(message: ', '')
        .replaceAll(')', '');
  }

  String _prettyStatus(String value) {
    final status = value.trim().toLowerCase().replaceAll(' ', '_');

    if (status.isEmpty) {
      return 'Waiting';
    }

    return status
        .split('_')
        .where((word) => word.isNotEmpty)
        .map(
          (word) => '${word[0].toUpperCase()}${word.substring(1)}',
        )
        .join(' ');
  }

  Color _statusColor(_DoctorQueueItem item) {
    final status = item.queueStatus;

    if (status == 'completed') {
      return CorviaColors.success;
    }

    if (item.isUrgent) {
      return CorviaColors.danger;
    }

    if (status == 'with_doctor') {
      return Colors.teal;
    }

    if (status == 'called') {
      return Colors.deepPurpleAccent;
    }

    return CorviaColors.warning;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.cBgPrimary,
      appBar: AppBar(
        title: const Text('Reception Queue'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : _loadQueue,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadQueue,
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return Center(
        child: CircularProgressIndicator(color: CorviaColors.accent),
      );
    }

    if (_error != null) {
      return ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 100),
          const Icon(
            Icons.cloud_off_rounded,
            size: 60,
            color: Colors.redAccent,
          ),
          const SizedBox(height: 14),
          Text(
            _error!,
            textAlign: TextAlign.center,
            style: TextStyle(color: context.cTextPrimary),
          ),
          const SizedBox(height: 18),
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
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 120),
          Icon(
            Icons.event_seat_outlined,
            size: 60,
            color: CorviaColors.accent,
          ),
          SizedBox(height: 16),
          Text(
            'No Reception queue patients assigned to you today.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: context.cTextPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'When Reception checks in and assigns a patient, they will appear here.',
            textAlign: TextAlign.center,
            style: TextStyle(color: context.cTextSecondary),
          ),
        ],
      );
    }

    final activeQueue = _queue
        .where(
          (item) => item.queueStatus != 'completed',
        )
        .toList();
    final completedQueue = _queue
        .where(
          (item) => item.queueStatus == 'completed',
        )
        .toList();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Patients checked in by Reception. Call patients, then start and complete consultations here.',
          style: TextStyle(color: context.cTextSecondary),
        ),
        const SizedBox(height: 14),
        if (activeQueue.isEmpty)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: CorviaColors.secondaryDark,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: CorviaColors.success.withValues(alpha: 0.35),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.task_alt_rounded,
                  color: CorviaColors.success,
                ),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'No active patients remain in your queue.',
                    style: TextStyle(
                      color: context.cTextSecondary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          )
        else
          ...activeQueue.map(_queueCard),
        if (completedQueue.isNotEmpty)
          Container(
            decoration: BoxDecoration(
              color: CorviaColors.secondaryDark,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: CorviaColors.success.withValues(alpha: 0.45),
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: ExpansionTile(
              initiallyExpanded: false,
              leading: Icon(
                Icons.check_circle_rounded,
                color: CorviaColors.success,
              ),
              title: Text(
                'Completed (${completedQueue.length})',
                style: TextStyle(
                  color: context.cTextPrimary,
                  fontWeight: FontWeight.w800,
                ),
              ),
              subtitle: Text(
                'Tap to review completed patients',
                style: TextStyle(color: context.cTextSecondary),
              ),
              iconColor: CorviaColors.success,
              collapsedIconColor: CorviaColors.success,
              childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
              children: completedQueue.map(_queueCard).toList(),
            ),
          ),
      ],
    );
  }

  Widget _queueCard(_DoctorQueueItem item) {
    final color = _statusColor(item);
    final isCompleted = item.queueStatus == 'completed';

    final checkedIn = item.checkedInAt == null
        ? 'Unknown'
        : DateFormat('HH:mm').format(item.checkedInAt!);

    final appointment = item.appointmentTime == null
        ? 'Walk-in'
        : DateFormat('HH:mm').format(item.appointmentTime!);

    final isActioning = _actioningId == item.checkinId;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: CorviaColors.secondaryDark,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: color.withValues(alpha: 0.55),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundColor: color.withValues(alpha: 0.18),
                child: Icon(
                  isCompleted
                      ? Icons.check_circle_rounded
                      : item.isUrgent
                          ? Icons.priority_high_rounded
                          : Icons.person_rounded,
                  color: color,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  item.patientName,
                  style: TextStyle(
                    color: context.cTextPrimary,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              _badge(
                isCompleted
                    ? 'COMPLETED'
                    : item.isUrgent
                        ? 'URGENT'
                        : _prettyStatus(item.queueStatus),
                color,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            item.patientNumber,
            style: TextStyle(color: context.cTextSecondary),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 14,
            runSpacing: 8,
            children: [
              _detail(Icons.local_hospital_rounded, item.departmentName),
              _detail(Icons.login_rounded, 'Checked in $checkedIn'),
              _detail(Icons.event_rounded, 'Appointment $appointment'),
              if (item.isWalkIn)
                _detail(Icons.directions_walk_rounded, 'Walk-in'),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            item.visitReason,
            style: TextStyle(
              color: context.cTextPrimary,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 14),
          if (isActioning)
            Center(
              child: CircularProgressIndicator(color: CorviaColors.accent),
            )
          else
            _actionsForStatus(item),
        ],
      ),
    );
  }

  Widget _actionsForStatus(_DoctorQueueItem item) {
    if (item.queueStatus == 'completed') {
      return Row(
        children: [
          Icon(Icons.check_circle_rounded, color: CorviaColors.success),
          SizedBox(width: 8),
          Text(
            'Completed',
            style: TextStyle(
              color: CorviaColors.success,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      );
    }

    if (item.queueStatus == 'with_doctor') {
      return SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: () => _completeConsultation(item),
          icon: const Icon(Icons.check_circle_rounded),
          label: const Text('Complete Consultation'),
        ),
      );
    }

    if (item.queueStatus == 'waiting' ||
        item.queueStatus == 'checked_in' ||
        item.queueStatus == 'confirmed') {
      return SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: Colors.deepPurple,
          ),
          onPressed: () => _callPatient(item),
          icon: const Icon(Icons.campaign_rounded),
          label: const Text('Call Patient'),
        ),
      );
    }

    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: () => _startConsultation(item),
        icon: const Icon(Icons.play_arrow_rounded),
        label: const Text('Start Consultation'),
      ),
    );
  }

  Widget _detail(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: context.cTextSecondary, size: 15),
        const SizedBox(width: 5),
        Text(
          text,
          style: TextStyle(
            color: context.cTextSecondary,
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  Widget _badge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 9,
        vertical: 5,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _DoctorQueueItem {
  const _DoctorQueueItem({
    required this.checkinId,
    required this.patientId,
    required this.appointmentId,
    required this.patientName,
    required this.patientNumber,
    required this.departmentName,
    required this.visitReason,
    required this.queueStatus,
    required this.urgency,
    required this.isUrgent,
    required this.isWalkIn,
    this.checkedInAt,
    this.appointmentTime,
  });

  final String checkinId;
  final String patientId;
  final String appointmentId;
  final String patientName;
  final String patientNumber;
  final String departmentName;
  final String visitReason;
  final String queueStatus;
  final String urgency;
  final bool isUrgent;
  final bool isWalkIn;
  final DateTime? checkedInAt;
  final DateTime? appointmentTime;

  factory _DoctorQueueItem.fromJson(Map<String, dynamic> json) {
    return _DoctorQueueItem(
      checkinId: (json['checkinId'] ?? '').toString(),
      patientId: (json['patientId'] ?? '').toString(),
      appointmentId: (json['appointmentId'] ?? '').toString(),
      patientName: (json['patientName'] ?? 'Unknown patient').toString(),
      patientNumber: (json['patientNumber'] ?? 'Patient record').toString(),
      departmentName: (json['departmentName'] ?? 'Unassigned').toString(),
      visitReason: _firstReason(json),
      queueStatus: (json['queueStatus'] ?? 'waiting')
          .toString()
          .toLowerCase()
          .replaceAll(' ', '_'),
      urgency: (json['urgency'] ?? 'normal').toString().toLowerCase(),
      isUrgent: json['isUrgent'] == true ||
          json['isUrgent']?.toString().toLowerCase() == 'true',
      isWalkIn: json['isWalkIn'] == true ||
          json['isWalkIn']?.toString().toLowerCase() == 'true',
      checkedInAt: _date(json['checkedInAt']),
      appointmentTime: _date(json['appointmentTime']),
    );
  }

  static DateTime? _date(dynamic value) {
    if (value == null) {
      return null;
    }

    return DateTime.tryParse(value.toString())?.toLocal();
  }

  static String _firstReason(Map<String, dynamic> json) {
    final values = [
      json['reason'],
      json['visit_reason'],
      json['visitReason'],
      json['reason_for_visit'],
      json['appointment_reason'],
    ];

    for (final value in values) {
      final text = value?.toString().trim();
      if (text != null &&
          text.isNotEmpty &&
          text.toLowerCase() != 'no reason supplied') {
        return text;
      }
    }

    return 'No reason supplied';
  }
}
