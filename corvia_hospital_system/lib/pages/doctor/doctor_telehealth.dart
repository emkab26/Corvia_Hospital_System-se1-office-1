import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../services/supabase_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/status_view.dart';

class DoctorTelehealthPage extends StatefulWidget {
  const DoctorTelehealthPage({super.key});

  @override
  State<DoctorTelehealthPage> createState() => _DoctorTelehealthPageState();
}

class _DoctorTelehealthPageState extends State<DoctorTelehealthPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  Future<_TelehealthBundle>? _future;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _refresh();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  void _refresh() {
    setState(() {
      _future = _TelehealthBundle.load();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CorviaColors.primaryDark,
      appBar: AppBar(
        title: const Text('Telehealth'),
        backgroundColor: CorviaColors.secondaryDark,
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: CorviaColors.accent,
          labelColor: CorviaColors.accentLight,
          unselectedLabelColor: CorviaColors.textSecondary,
          tabs: const [
            Tab(text: 'Today'),
            Tab(text: 'Upcoming'),
            Tab(text: 'Past'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _refresh,
          ),
        ],
      ),
      body: FutureBuilder<_TelehealthBundle>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return StatusView.loading(
              message: 'Loading telehealth appointments...',
            );
          }

          if (snapshot.hasError) {
            return StatusView.error(
              friendlyMessage: "We couldn't load your telehealth appointments.",
              error: snapshot.error,
              stackTrace: snapshot.stackTrace,
              onRetry: _refresh,
            );
          }

          final bundle = snapshot.data!;

          if (bundle.notADoctor) {
            return StatusView.empty(
              icon: Icons.medical_services_outlined,
              title: 'No doctor profile found',
              subtitle:
                  'You need a doctor profile to host telehealth consultations.',
            );
          }

          return TabBarView(
            controller: _tabs,
            children: [
              _TelehealthList(
                items: bundle.today,
                emptyTitle: 'No telehealth calls today',
                emptySubtitle:
                    'When a patient books a telehealth appointment for today, '
                    'it will appear here.',
                isUpcoming: true,
                onJoin: _joinCall,
                onRefresh: _refresh,
              ),
              _TelehealthList(
                items: bundle.upcoming,
                emptyTitle: 'No upcoming telehealth calls',
                emptySubtitle:
                    'Future telehealth appointments show here once a patient '
                    'books one.',
                isUpcoming: true,
                onJoin: _joinCall,
                onRefresh: _refresh,
              ),
              _TelehealthList(
                items: bundle.past,
                emptyTitle: 'No past telehealth calls',
                emptySubtitle:
                    'Completed or cancelled telehealth appointments will '
                    'appear here.',
                isUpcoming: false,
                onJoin: _joinCall,
                onRefresh: _refresh,
              ),
            ],
          );
        },
      ),
    );
  }

  void _joinCall(_TelehealthAppt appointment) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: CorviaColors.warning,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 5),
        content: const Text(
          'Telehealth video calls are not wired yet. Patient and appointment '
          'details are ready, but the call service is still being built.',
        ),
      ),
    );
  }
}

class _TelehealthBundle {
  const _TelehealthBundle({
    required this.notADoctor,
    required this.today,
    required this.upcoming,
    required this.past,
  });

  final bool notADoctor;
  final List<_TelehealthAppt> today;
  final List<_TelehealthAppt> upcoming;
  final List<_TelehealthAppt> past;

  static Future<_TelehealthBundle> load() async {
    final client = SupabaseService.client;
    final user = client.auth.currentUser;

    if (user == null) {
      return const _TelehealthBundle(
        notADoctor: true,
        today: [],
        upcoming: [],
        past: [],
      );
    }

    final doctorRow = await client
        .from('doctors')
        .select('id')
        .eq('profile_id', user.id)
        .maybeSingle();

    final doctorId = doctorRow?['id']?.toString();

    if (doctorId == null || doctorId.isEmpty) {
      return const _TelehealthBundle(
        notADoctor: true,
        today: [],
        upcoming: [],
        past: [],
      );
    }

    final appointmentRows = await client
        .from('appointments')
        .select(
          'id, patient_id, appointment_date, duration_minutes, reason, status',
        )
        .eq('doctor_id', doctorId)
        .eq('type', 'telehealth')
        .order('appointment_date', ascending: true);

    final patientIds = <String>{};

    for (final row in appointmentRows as List) {
      final patientId = row['patient_id']?.toString();

      if (patientId != null && patientId.isNotEmpty) {
        patientIds.add(patientId);
      }
    }

    final profileIdByPatientId = <String, String>{};

    if (patientIds.isNotEmpty) {
      final patientRows = await client
          .from('patients')
          .select('id, profile_id')
          .inFilter('id', patientIds.toList());

      for (final row in patientRows as List) {
        final patientId = row['id']?.toString() ?? '';
        final profileId = row['profile_id']?.toString() ?? '';

        if (patientId.isNotEmpty && profileId.isNotEmpty) {
          profileIdByPatientId[patientId] = profileId;
        }
      }
    }

    final profileIds = profileIdByPatientId.values.toSet();
    final namesByProfileUserId = <String, String>{};

    if (profileIds.isNotEmpty) {
      final profileRows = await client
          .from('profiles')
          .select('user_id, first_name, surname')
          .inFilter('user_id', profileIds.toList());

      for (final row in profileRows as List) {
        final userId = row['user_id']?.toString() ?? '';
        final firstName = row['first_name']?.toString().trim() ?? '';
        final surname = row['surname']?.toString().trim() ?? '';
        final fullName = '$firstName $surname'.trim();

        if (userId.isNotEmpty && fullName.isNotEmpty) {
          namesByProfileUserId[userId] = fullName;
        }
      }
    }

    final appointments = <_TelehealthAppt>[];

    for (final row in appointmentRows as List) {
      final appointmentDate = DateTime.tryParse(
        row['appointment_date']?.toString() ?? '',
      );

      if (appointmentDate == null) {
        continue;
      }

      final patientId = row['patient_id']?.toString() ?? '';
      final profileId = profileIdByPatientId[patientId] ?? '';

      final patientName = namesByProfileUserId[profileId] ?? 'Unknown Patient';

      appointments.add(
        _TelehealthAppt(
          id: row['id']?.toString() ?? '',
          patientName: patientName,
          date: appointmentDate.toLocal(),
          durationMinutes: (row['duration_minutes'] as int?) ?? 30,
          reason: row['reason']?.toString() ?? '',
          status: row['status']?.toString() ?? 'scheduled',
        ),
      );
    }

    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final tomorrowStart = todayStart.add(const Duration(days: 1));

    final today = <_TelehealthAppt>[];
    final upcoming = <_TelehealthAppt>[];
    final past = <_TelehealthAppt>[];

    for (final appointment in appointments) {
      final status = appointment.effectiveStatus;

      if (status != 'scheduled' && status != 'confirmed') {
        past.add(appointment);
      } else if (appointment.date.isBefore(todayStart)) {
        past.add(appointment);
      } else if (appointment.date.isBefore(tomorrowStart)) {
        today.add(appointment);
      } else {
        upcoming.add(appointment);
      }
    }

    past.sort((first, second) => second.date.compareTo(first.date));

    return _TelehealthBundle(
      notADoctor: false,
      today: today,
      upcoming: upcoming,
      past: past,
    );
  }
}

class _TelehealthAppt {
  const _TelehealthAppt({
    required this.id,
    required this.patientName,
    required this.date,
    required this.durationMinutes,
    required this.reason,
    required this.status,
  });

  final String id;
  final String patientName;
  final DateTime date;
  final int durationMinutes;
  final String reason;
  final String status;

  String get effectiveStatus {
    if (status == 'scheduled' || status == 'confirmed') {
      final endTime = date.add(
        Duration(minutes: durationMinutes),
      );

      if (endTime.isBefore(DateTime.now())) {
        return 'missed';
      }
    }

    return status;
  }

  String get initials {
    if (patientName == 'Unknown Patient') {
      return 'UP';
    }

    final parts = patientName.trim().split(RegExp(r'\s+'));

    if (parts.isEmpty || parts.first.isEmpty) {
      return '?';
    }

    if (parts.length == 1) {
      return parts.first[0].toUpperCase();
    }

    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }

  bool get isJoinable {
    final now = DateTime.now();
    final start = date.subtract(const Duration(minutes: 5));
    final end = date.add(
      Duration(minutes: durationMinutes + 5),
    );

    return now.isAfter(start) && now.isBefore(end);
  }
}

class _TelehealthList extends StatefulWidget {
  const _TelehealthList({
    required this.items,
    required this.emptyTitle,
    required this.emptySubtitle,
    required this.isUpcoming,
    required this.onJoin,
    required this.onRefresh,
  });

  final List<_TelehealthAppt> items;
  final String emptyTitle;
  final String emptySubtitle;
  final bool isUpcoming;
  final void Function(_TelehealthAppt) onJoin;
  final VoidCallback onRefresh;

  @override
  State<_TelehealthList> createState() => _TelehealthListState();
}

class _TelehealthListState extends State<_TelehealthList> {
  static const _pageSize = 10;
  int _visibleCount = _pageSize;

  @override
  void didUpdateWidget(_TelehealthList oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.items.length != widget.items.length) {
      _visibleCount = _pageSize;
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.items;

    if (items.isEmpty) {
      return RefreshIndicator(
        onRefresh: () async {
          widget.onRefresh();
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(
              height: MediaQuery.of(context).size.height * 0.7,
              child: StatusView.empty(
                icon: Icons.video_call_outlined,
                title: widget.emptyTitle,
                subtitle: widget.emptySubtitle,
              ),
            ),
          ],
        ),
      );
    }

    final visibleAppointments = items.take(_visibleCount).toList();
    final hasMore = items.length > _visibleCount;
    final remaining = items.length - _visibleCount;

    return RefreshIndicator(
      onRefresh: () async {
        widget.onRefresh();
      },
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
        itemCount: visibleAppointments.length + (hasMore ? 1 : 0),
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, index) {
          if (index == visibleAppointments.length) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: OutlinedButton.icon(
                onPressed: () {
                  setState(() {
                    _visibleCount += _pageSize;
                  });
                },
                icon: const Icon(Icons.expand_more),
                label: Text('Load more ($remaining remaining)'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: CorviaColors.accentLight,
                  side: BorderSide(
                    color: CorviaColors.accentLight.withValues(alpha: 0.5),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            );
          }

          return _TelehealthCard(
            appointment: visibleAppointments[index],
            showJoinButton: widget.isUpcoming,
            onJoin: () {
              widget.onJoin(visibleAppointments[index]);
            },
          );
        },
      ),
    );
  }
}

class _TelehealthCard extends StatelessWidget {
  const _TelehealthCard({
    required this.appointment,
    required this.showJoinButton,
    required this.onJoin,
  });

  final _TelehealthAppt appointment;
  final bool showJoinButton;
  final VoidCallback onJoin;

  @override
  Widget build(BuildContext context) {
    final start = DateFormat('HH:mm').format(appointment.date);
    final end = DateFormat('HH:mm').format(
      appointment.date.add(
        Duration(minutes: appointment.durationMinutes),
      ),
    );

    final dayLabel = DateFormat('EEE d MMM yyyy').format(appointment.date);
    final status = appointment.effectiveStatus;
    final canJoin = appointment.isJoinable;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: CorviaColors.accent.withValues(alpha: 0.18),
                  child: Text(
                    appointment.initials,
                    style: TextStyle(
                      color: CorviaColors.accentLight,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        appointment.patientName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        dayLabel,
                        style: TextStyle(
                          color: CorviaColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                _StatusPill(status: status),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(
                  Icons.access_time,
                  size: 14,
                  color: CorviaColors.accentLight,
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    '$start – $end (${appointment.durationMinutes} min)',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: CorviaColors.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
            if (appointment.reason.isNotEmpty) ...[
              const SizedBox(height: 6),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.notes_outlined,
                    size: 14,
                    color: CorviaColors.accentLight,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      appointment.reason,
                      style: TextStyle(
                        color: CorviaColors.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            if (showJoinButton && status != 'missed') ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: canJoin
                        ? CorviaColors.accent
                        : CorviaColors.secondaryDark,
                    foregroundColor:
                        canJoin ? Colors.white : CorviaColors.textSecondary,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: onJoin,
                  icon: const Icon(Icons.video_call),
                  label: Text(
                    canJoin
                        ? 'Join call now'
                        : 'Scheduled for ${DateFormat('d MMM, HH:mm').format(appointment.date)}',
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.status,
  });

  final String status;

  Color get _color {
    switch (status) {
      case 'scheduled':
        return Colors.blueAccent;
      case 'confirmed':
        return CorviaColors.accent;
      case 'completed':
        return Colors.green;
      case 'cancelled':
        return Colors.redAccent;
      case 'no_show':
        return Colors.orange;
      case 'missed':
        return Colors.deepOrange;
      default:
        return Colors.grey;
    }
  }

  String get _label {
    if (status.isEmpty) {
      return '';
    }

    return status
        .replaceAll('_', ' ')
        .split(' ')
        .map(
          (part) => part.isEmpty
              ? part
              : '${part[0].toUpperCase()}${part.substring(1)}',
        )
        .join(' ');
  }

  @override
  Widget build(BuildContext context) {
    final color = _color;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 8,
        vertical: 3,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: color.withValues(alpha: 0.5),
        ),
      ),
      child: Text(
        _label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
