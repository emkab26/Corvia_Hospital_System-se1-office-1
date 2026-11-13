import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/supabase_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/read_aloud_button.dart';
import '../../widgets/status_view.dart';

import 'book_appointment.dart';
import 'report_a_doctor_page.dart';
import 'reception_check_in_qr.dart';

class AppointmentsPage extends StatefulWidget {
  const AppointmentsPage({
    super.key,
  });

  @override
  State<AppointmentsPage> createState() {
    return _AppointmentsPageState();
  }
}

class _AppointmentsPageState extends State<AppointmentsPage>
    with SingleTickerProviderStateMixin {
  static const Duration _requestTimeout = Duration(seconds: 20);

  late final TabController _tabController;

  List<_Appointment> _appointments = [];

  bool _loading = true;
  bool _refreshing = false;

  bool _openingBookingPage = false;
  bool _openingQrPage = false;

  String? _error;

  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();

    _tabController = TabController(
      length: 2,
      vsync: this,
    );

    _loadAppointments(
      showFullLoader: true,
    );
  }

  @override
  void dispose() {
    _tabController.dispose();

    super.dispose();
  }

  Future<void> _loadAppointments({
    required bool showFullLoader,
  }) async {
    final generation = ++_loadGeneration;

    final showLoader = showFullLoader || _appointments.isEmpty;

    if (mounted) {
      setState(() {
        _error = null;

        _loading = showLoader;
        _refreshing = !showLoader;
      });
    }

    try {
      final appointments = await _fetchAppointments().timeout(
        _requestTimeout,
      );

      if (!mounted || generation != _loadGeneration) {
        return;
      }

      setState(() {
        _appointments = appointments;

        _error = null;
      });
    } on TimeoutException {
      if (!mounted || generation != _loadGeneration) {
        return;
      }

      const message = 'The server took too long to respond. '
          'Check your connection and try again.';

      if (_appointments.isEmpty) {
        setState(() {
          _error = message;
        });
      } else {
        _showMessage(
          message,
          isError: true,
        );
      }
    } catch (error) {
      debugPrint(
        'Patient appointments load failed: $error',
      );

      if (!mounted || generation != _loadGeneration) {
        return;
      }

      final message = _friendlyError(
        error,
      );

      if (_appointments.isEmpty) {
        setState(() {
          _error = message;
        });
      } else {
        _showMessage(
          'Could not refresh appointments. $message',
          isError: true,
        );
      }
    } finally {
      if (mounted && generation == _loadGeneration) {
        setState(() {
          _loading = false;
          _refreshing = false;
        });
      }
    }
  }

  Future<void> _refresh() {
    return _loadAppointments(
      showFullLoader: false,
    );
  }

  Future<List<_Appointment>> _fetchAppointments() async {
    final response = await SupabaseService.client
        .rpc(
          'corvia_patient_my_appointments',
        )
        .timeout(
          _requestTimeout,
        );

    final rows = _rows(
      response,
    );

    final appointments = <_Appointment>[];

    for (final row in rows) {
      final appointmentId = row['id']?.toString().trim();

      final patientId = row['patient_id']?.toString().trim();

      final rawDate = row['appointment_date']?.toString().trim();

      if (appointmentId == null ||
          appointmentId.isEmpty ||
          patientId == null ||
          patientId.isEmpty ||
          rawDate == null ||
          rawDate.isEmpty) {
        debugPrint(
          'Skipping invalid appointment RPC row: $row',
        );

        continue;
      }

      final parsedDate = DateTime.tryParse(
        rawDate,
      );

      if (parsedDate == null) {
        continue;
      }

      final duration = _parsePositiveInt(
        row['duration_minutes'],
        fallback: 30,
      );

      appointments.add(
        _Appointment(
          id: appointmentId,
          patientId: patientId,
          doctorId: _cleanText(
            row['doctor_id'],
            fallback: '',
          ),
          doctorName: _cleanText(
            row['doctor_name'],
            fallback: 'Doctor',
          ),
          hospitalName: _cleanText(
            row['hospital_name'],
            fallback: '',
          ),
          departmentName: _cleanText(
            row['department_name'],
            fallback: '',
          ),
          date: parsedDate.toLocal(),
          durationMinutes: duration,
          reason: _cleanText(
            row['reason'],
            fallback: '',
          ),
          type: _cleanText(
            row['appointment_type'],
            fallback: 'in-person',
          ),
          status: _canonicalStatus(
            row['status']?.toString(),
          ),
        ),
      );
    }

    return appointments;
  }

  List<Map<String, dynamic>> _rows(
    dynamic data,
  ) {
    if (data is! List) {
      return [];
    }

    return data
        .whereType<Map>()
        .map(
          (row) => Map<String, dynamic>.from(
            row,
          ),
        )
        .toList();
  }

  int _parsePositiveInt(
    dynamic value, {
    required int fallback,
  }) {
    if (value is int && value > 0) {
      return value;
    }

    if (value is num && value > 0) {
      return value.toInt();
    }

    final parsed = int.tryParse(
      value?.toString() ?? '',
    );

    if (parsed == null || parsed <= 0) {
      return fallback;
    }

    return parsed;
  }

  String _cleanText(
    dynamic value, {
    required String fallback,
  }) {
    final text = value?.toString().trim();

    if (text == null || text.isEmpty || text.toLowerCase() == 'null') {
      return fallback;
    }

    return text;
  }

  static String _canonicalStatus(
    String? rawStatus,
  ) {
    final status = (rawStatus ?? '')
        .trim()
        .toLowerCase()
        .replaceAll(
          RegExp(
            r'[\s-]+',
          ),
          '_',
        )
        .replaceAll(
          RegExp(
            r'_+',
          ),
          '_',
        );

    switch (status) {
      case '':
        return 'scheduled';

      case 'checkedin':
      case 'check_in':
      case 'checkin':
        return 'checked_in';

      case 'noshow':
        return 'no_show';

      case 'canceled':
        return 'cancelled';

      default:
        return status;
    }
  }

  String _friendlyError(
    Object error,
  ) {
    if (error is TimeoutException) {
      return 'The server took too long to respond.';
    }

    final message = error.toString();

    final lower = message.toLowerCase();

    if (lower.contains(
          'row-level security',
        ) ||
        lower.contains(
          'permission denied',
        ) ||
        lower.contains(
          '42501',
        )) {
      return 'Your account does not have permission to view these appointments.';
    }

    if (lower.contains(
          'not signed in',
        ) ||
        lower.contains(
          'must be signed in',
        )) {
      return 'You are not signed in.';
    }

    return message
        .replaceFirst(
          'Exception: ',
          '',
        )
        .replaceFirst(
          'Bad state: ',
          '',
        );
  }

  Future<void> _openBookingPage() async {
    if (_openingBookingPage || !mounted) {
      return;
    }

    setState(() {
      _openingBookingPage = true;
    });

    try {
      final booked = await Navigator.of(context).push<bool>(
        MaterialPageRoute<bool>(
          builder: (_) {
            return const BookingApp();
          },
        ),
      );

      if (!mounted) {
        return;
      }

      if (booked == true) {
        _tabController.animateTo(
          0,
        );

        _showMessage(
          'Appointment booked successfully.',
        );
      }

      await _refresh();
    } finally {
      if (mounted) {
        setState(() {
          _openingBookingPage = false;
        });
      }
    }
  }

  Future<void> _openCheckInQr() async {
    if (_openingQrPage || !mounted) {
      return;
    }

    setState(() {
      _openingQrPage = true;
    });

    try {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) {
            return const ReceptionCheckInQrPage();
          },
        ),
      );

      if (mounted) {
        await _refresh();
      }
    } finally {
      if (mounted) {
        setState(() {
          _openingQrPage = false;
        });
      }
    }
  }

  List<_Appointment> get _upcomingAppointments {
    final appointments = _appointments.where(
      (appointment) {
        final status = appointment.effectiveStatus;

        return status == 'pending' ||
            status == 'scheduled' ||
            status == 'confirmed' ||
            status == 'checked_in';
      },
    ).toList();

    appointments.sort(
      (
        first,
        second,
      ) {
        return first.date.compareTo(
          second.date,
        );
      },
    );

    return appointments;
  }

  List<_Appointment> get _pastAppointments {
    final appointments = _appointments.where(
      (appointment) {
        final status = appointment.effectiveStatus;

        return status != 'pending' &&
            status != 'scheduled' &&
            status != 'confirmed' &&
            status != 'checked_in';
      },
    ).toList();

    appointments.sort(
      (
        first,
        second,
      ) {
        return second.date.compareTo(
          first.date,
        );
      },
    );

    return appointments;
  }

  bool get _hasQrEligibleAppointment {
    final now = DateTime.now();

    final today = DateTime(
      now.year,
      now.month,
      now.day,
    );

    return _appointments.any(
      (appointment) {
        final status = appointment.effectiveStatus;

        final appointmentDay = DateTime(
          appointment.date.year,
          appointment.date.month,
          appointment.date.day,
        );

        return (status == 'scheduled' || status == 'confirmed') &&
            !appointmentDay.isBefore(today);
      },
    );
  }

  void _showMessage(
    String message, {
    bool isError = false,
  }) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          backgroundColor: isError ? CorviaColors.danger : null,
          content: Text(
            message,
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.cBgPrimary,
      appBar: AppBar(
        title: const Text(
          'Appointments',
        ),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(
              icon: Icon(
                Icons.upcoming_outlined,
              ),
              text: 'Upcoming',
            ),
            Tab(
              icon: Icon(
                Icons.history_rounded,
              ),
              text: 'Past',
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Check-In QR',
            onPressed: _openingQrPage ? null : _openCheckInQr,
            icon: _openingQrPage
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                    ),
                  )
                : const Icon(
                    Icons.qr_code_2_rounded,
                  ),
          ),
          IconButton(
            tooltip: 'Refresh appointments',
            onPressed: _loading || _refreshing ? null : _refresh,
            icon: const Icon(
              Icons.refresh_rounded,
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openingBookingPage ? null : _openBookingPage,
        backgroundColor: CorviaColors.accent,
        icon: _openingBookingPage
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Icon(
                Icons.add_rounded,
                color: Colors.white,
              ),
        label: Text(
          _openingBookingPage ? 'Opening...' : 'Book Appointment',
          style: const TextStyle(
            color: Colors.white,
          ),
        ),
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: _buildBody(),
          ),
          if (_refreshing)
            const Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: LinearProgressIndicator(),
            ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading && _appointments.isEmpty) {
      return StatusView.loading(
        message: 'Loading appointments...',
      );
    }

    if (_error != null && _appointments.isEmpty) {
      return StatusView.error(
        friendlyMessage: "We couldn't load your appointments.",
        error: _error,
        onRetry: () {
          _loadAppointments(
            showFullLoader: true,
          );
        },
      );
    }

    return TabBarView(
      controller: _tabController,
      children: [
        Column(
          children: [
            if (_hasQrEligibleAppointment)
              _CheckInQrBanner(
                opening: _openingQrPage,
                onPressed: _openCheckInQr,
              ),
            Expanded(
              child: _AppointmentList(
                appointments: _upcomingAppointments,
                emptyIcon: Icons.calendar_today_outlined,
                emptyTitle: 'No upcoming appointments',
                emptySubtitle: 'Use Book Appointment to schedule a visit.',
                onRefresh: _refresh,
                onCancelled: _refresh,
              ),
            ),
          ],
        ),
        _AppointmentList(
          appointments: _pastAppointments,
          emptyIcon: Icons.history_rounded,
          emptyTitle: 'No past appointments',
          emptySubtitle:
              'Completed, cancelled and missed appointments will appear here.',
          onRefresh: _refresh,
        ),
      ],
    );
  }
}

class _Appointment {
  const _Appointment({
    required this.id,
    required this.patientId,
    required this.doctorId,
    required this.doctorName,
    required this.hospitalName,
    required this.departmentName,
    required this.date,
    required this.durationMinutes,
    required this.reason,
    required this.type,
    required this.status,
  });

  final String id;
  final String patientId;
  final String doctorId;
  final String doctorName;
  final String hospitalName;
  final String departmentName;

  final DateTime date;

  final int durationMinutes;

  final String reason;
  final String type;
  final String status;

  String get effectiveStatus {
    final canonical = _AppointmentsPageState._canonicalStatus(
      status,
    );

    if (canonical == 'pending' ||
        canonical == 'scheduled' ||
        canonical == 'confirmed') {
      final end = date.add(
        Duration(
          minutes: durationMinutes,
        ),
      );

      if (end.isBefore(
        DateTime.now(),
      )) {
        return 'missed';
      }
    }

    return canonical;
  }
}

class _CheckInQrBanner extends StatelessWidget {
  const _CheckInQrBanner({
    required this.opening,
    required this.onPressed,
  });

  final bool opening;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        16,
        14,
        16,
        2,
      ),
      child: Material(
        color: CorviaColors.accent.withValues(
          alpha: 0.10,
        ),
        borderRadius: BorderRadius.circular(
          14,
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(
            14,
          ),
          onTap: opening ? null : onPressed,
          child: Container(
            padding: const EdgeInsets.all(
              14,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(
                14,
              ),
              border: Border.all(
                color: CorviaColors.accent.withValues(
                  alpha: 0.35,
                ),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: CorviaColors.accent.withValues(
                      alpha: 0.15,
                    ),
                    borderRadius: BorderRadius.circular(
                      12,
                    ),
                  ),
                  child: Icon(
                    Icons.qr_code_2_rounded,
                    color: context.cAccentReadable,
                  ),
                ),
                const SizedBox(
                  width: 12,
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Appointment Check-In QR',
                        style: TextStyle(
                          color: context.cTextPrimary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(
                        height: 3,
                      ),
                      Text(
                        'Open your next eligible appointment QR for reception.',
                        style: TextStyle(
                          color: context.cTextSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                if (opening)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                    ),
                  )
                else
                  Icon(
                    Icons.chevron_right_rounded,
                    color: context.cAccentReadable,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AppointmentList extends StatefulWidget {
  const _AppointmentList({
    required this.appointments,
    required this.emptyIcon,
    required this.emptyTitle,
    required this.emptySubtitle,
    required this.onRefresh,
    this.onCancelled,
  });

  final List<_Appointment> appointments;

  final IconData emptyIcon;

  final String emptyTitle;
  final String emptySubtitle;

  final Future<void> Function() onRefresh;

  final Future<void> Function()? onCancelled;

  @override
  State<_AppointmentList> createState() {
    return _AppointmentListState();
  }
}

class _AppointmentListState extends State<_AppointmentList> {
  static const int _pageSize = 10;

  int _visibleCount = _pageSize;

  @override
  void didUpdateWidget(
    covariant _AppointmentList oldWidget,
  ) {
    super.didUpdateWidget(
      oldWidget,
    );

    if (oldWidget.appointments.length != widget.appointments.length) {
      _visibleCount = _pageSize;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.appointments.isEmpty) {
      return RefreshIndicator(
        onRefresh: widget.onRefresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(
            24,
          ),
          children: [
            const SizedBox(
              height: 80,
            ),
            Icon(
              widget.emptyIcon,
              size: 56,
              color: context.cTextSecondary,
            ),
            const SizedBox(
              height: 16,
            ),
            Text(
              widget.emptyTitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: context.cTextPrimary,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(
              height: 7,
            ),
            Text(
              widget.emptySubtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: context.cTextSecondary,
              ),
            ),
          ],
        ),
      );
    }

    final visible = widget.appointments
        .take(
          _visibleCount,
        )
        .toList();

    final hasMore = widget.appointments.length > _visibleCount;

    final remaining = widget.appointments.length - _visibleCount;

    return RefreshIndicator(
      onRefresh: widget.onRefresh,
      child: LayoutBuilder(
        builder: (
          context,
          constraints,
        ) {
          final horizontalPadding = constraints.maxWidth >= 900 ? 30.0 : 16.0;

          return ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(
              horizontalPadding,
              16,
              horizontalPadding,
              110,
            ),
            itemCount: visible.length + (hasMore ? 1 : 0),
            separatorBuilder: (
              context,
              index,
            ) {
              return const SizedBox(
                height: 12,
              );
            },
            itemBuilder: (
              context,
              index,
            ) {
              if (index == visible.length) {
                return OutlinedButton.icon(
                  onPressed: () {
                    setState(
                      () {
                        _visibleCount += _pageSize;
                      },
                    );
                  },
                  icon: const Icon(
                    Icons.expand_more_rounded,
                  ),
                  label: Text(
                    'Load more '
                    '($remaining remaining)',
                  ),
                );
              }

              return Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: 1000,
                  ),
                  child: _AppointmentCard(
                    appointment: visible[index],
                    onCancelled: widget.onCancelled,
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _AppointmentCard extends StatefulWidget {
  const _AppointmentCard({
    required this.appointment,
    this.onCancelled,
  });

  final _Appointment appointment;

  final Future<void> Function()? onCancelled;

  @override
  State<_AppointmentCard> createState() {
    return _AppointmentCardState();
  }
}

class _AppointmentCardState extends State<_AppointmentCard> {
  static const Duration _requestTimeout = Duration(seconds: 20);

  bool _cancelling = false;
  bool _openingReport = false;

  bool get _canCancel {
    final status = widget.appointment.effectiveStatus;

    return status == 'pending' ||
        status == 'scheduled' ||
        status == 'confirmed';
  }

  bool get _canReport {
    return widget.appointment.effectiveStatus == 'completed' &&
        widget.appointment.doctorId.trim().isNotEmpty;
  }

  Future<void> _openReport() async {
    if (_openingReport || !_canReport) {
      return;
    }

    setState(() {
      _openingReport = true;
    });

    final appointment = widget.appointment;

    try {
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => ReportADoctorPage(
            initialDoctorId: appointment.doctorId,
            initialDoctorName: appointment.doctorName,
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _openingReport = false;
        });
      }
    }
  }

  Future<void> _confirmCancellation() async {
    if (_cancelling) {
      return;
    }

    final appointment = widget.appointment;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (
        dialogContext,
      ) {
        return AlertDialog(
          title: const Text(
            'Cancel appointment?',
          ),
          content: Text(
            'Are you sure you want to cancel '
            'your appointment with '
            '${appointment.doctorName} on '
            '${DateFormat('EEE, d MMM yyyy').format(appointment.date)} '
            'at '
            '${DateFormat('HH:mm').format(appointment.date)}?\n\n'
            'This action cannot be undone.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(
                  dialogContext,
                  false,
                );
              },
              child: const Text(
                'Keep Appointment',
              ),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: CorviaColors.danger,
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                Navigator.pop(
                  dialogContext,
                  true,
                );
              },
              child: const Text(
                'Cancel Appointment',
              ),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) {
      return;
    }

    setState(() {
      _cancelling = true;
    });

    try {
      await SupabaseService.client.rpc(
        'corvia_patient_cancel_appointment',
        params: {
          'p_appointment_id': appointment.id,
        },
      ).timeout(
        _requestTimeout,
      );

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text(
              'Appointment cancelled.',
            ),
          ),
        );

      final callback = widget.onCancelled;

      if (callback != null) {
        await callback();
      }
    } on TimeoutException {
      _showCancellationError(
        'The server took too long to respond.',
      );
    } on PostgrestException catch (error) {
      debugPrint(
        'Appointment cancellation RPC failed: '
        '${error.message}',
      );

      _showCancellationError(
        error.message.toLowerCase().contains(
                  'cannot',
                )
            ? error.message
            : "Couldn't cancel the appointment. Please refresh and try again.",
      );
    } catch (error) {
      debugPrint(
        'Appointment cancellation failed: $error',
      );

      _showCancellationError(
        "Couldn't cancel the appointment. Please try again.",
      );
    } finally {
      if (mounted) {
        setState(() {
          _cancelling = false;
        });
      }
    }
  }

  void _showCancellationError(
    String message,
  ) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: CorviaColors.danger,
        ),
      );
  }

  Color _statusColor(
    String status,
  ) {
    switch (status) {
      case 'pending':
        return CorviaColors.warning;

      case 'scheduled':
        return CorviaColors.accentLight;

      case 'confirmed':
        return CorviaColors.accent;

      case 'checked_in':
        return Colors.deepPurple;

      case 'completed':
        return CorviaColors.success;

      case 'cancelled':
        return CorviaColors.danger;

      case 'no_show':
      case 'missed':
        return CorviaColors.warning;

      default:
        return context.cTextSecondary;
    }
  }

  String _statusLabel(
    String status,
  ) {
    if (status == 'missed') {
      return 'Missed';
    }

    return status
        .split('_')
        .where(
          (word) => word.isNotEmpty,
        )
        .map(
      (word) {
        return '${word[0].toUpperCase()}'
            '${word.substring(1)}';
      },
    ).join(' ');
  }

  @override
  Widget build(BuildContext context) {
    final appointment = widget.appointment;

    final status = appointment.effectiveStatus;

    final statusColor = _statusColor(
      status,
    );

    final dateText = DateFormat(
      'EEE, d MMM yyyy',
    ).format(
      appointment.date,
    );

    final startTime = DateFormat(
      'HH:mm',
    ).format(
      appointment.date,
    );

    final endTime = DateFormat(
      'HH:mm',
    ).format(
      appointment.date.add(
        Duration(
          minutes: appointment.durationMinutes,
        ),
      ),
    );

    final telehealth = appointment.type.toLowerCase().replaceAll(
              '-',
              '_',
            ) ==
        'telehealth';

    final readAloudText = [
      '${_statusLabel(status)} appointment with ${appointment.doctorName}',
      'on ${DateFormat('EEEE d MMMM yyyy').format(appointment.date)}',
      'at $startTime',
      telehealth ? 'as a telehealth call' : 'in person',
      if (!telehealth && appointment.hospitalName.isNotEmpty)
        'at ${appointment.hospitalName}',
      if (appointment.reason.isNotEmpty) 'for ${appointment.reason}',
    ].join(', ');

    return Card(
      color: context.cBgSecondary,
      elevation: 1,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(
          16,
        ),
        side: BorderSide(
          color: context.cDivider,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(
          16,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LayoutBuilder(
              builder: (
                context,
                constraints,
              ) {
                final compact = constraints.maxWidth < 520;

                final doctorSection = Row(
                  children: [
                    CircleAvatar(
                      radius: 23,
                      backgroundColor: statusColor.withValues(
                        alpha: 0.14,
                      ),
                      child: Icon(
                        telehealth
                            ? Icons.video_call_rounded
                            : Icons.medical_services_rounded,
                        color: statusColor,
                      ),
                    ),
                    const SizedBox(
                      width: 12,
                    ),
                    Expanded(
                      child: Text(
                        appointment.doctorName,
                        style: TextStyle(
                          color: context.cTextPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                );

                if (compact) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      doctorSection,
                      const SizedBox(
                        height: 12,
                      ),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          ReadAloudButton(
                            text: readAloudText,
                          ),
                          _StatusChip(
                            label: _statusLabel(
                              status,
                            ),
                            color: statusColor,
                          ),
                        ],
                      ),
                    ],
                  );
                }

                return Row(
                  children: [
                    Expanded(
                      child: doctorSection,
                    ),
                    ReadAloudButton(
                      text: readAloudText,
                    ),
                    const SizedBox(
                      width: 8,
                    ),
                    _StatusChip(
                      label: _statusLabel(
                        status,
                      ),
                      color: statusColor,
                    ),
                  ],
                );
              },
            ),
            const SizedBox(
              height: 14,
            ),
            _InfoRow(
              icon: Icons.calendar_today_rounded,
              text: dateText,
            ),
            const SizedBox(
              height: 7,
            ),
            _InfoRow(
              icon: Icons.access_time_rounded,
              text: '$startTime – $endTime '
                  '(${appointment.durationMinutes} min)',
            ),
            const SizedBox(
              height: 7,
            ),
            _InfoRow(
              icon: telehealth
                  ? Icons.video_call_rounded
                  : Icons.local_hospital_outlined,
              text: telehealth ? 'Telehealth' : 'In-person',
            ),
            if (appointment.hospitalName.isNotEmpty) ...[
              const SizedBox(
                height: 7,
              ),
              _InfoRow(
                icon: Icons.apartment_rounded,
                text: appointment.hospitalName,
              ),
            ],
            if (appointment.departmentName.isNotEmpty) ...[
              const SizedBox(
                height: 7,
              ),
              _InfoRow(
                icon: Icons.domain_rounded,
                text: appointment.departmentName,
              ),
            ],
            if (appointment.reason.isNotEmpty) ...[
              const SizedBox(
                height: 7,
              ),
              _InfoRow(
                icon: Icons.notes_outlined,
                text: appointment.reason,
              ),
            ],
            if (_canCancel) ...[
              const SizedBox(
                height: 16,
              ),
              Divider(
                color: context.cDivider,
              ),
              const SizedBox(
                height: 10,
              ),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: CorviaColors.danger,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: _cancelling ? null : _confirmCancellation,
                  icon: _cancelling
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(
                          Icons.cancel_outlined,
                        ),
                  label: Text(
                    _cancelling ? 'Cancelling...' : 'Cancel Appointment',
                  ),
                ),
              ),
            ],
            if (_canReport) ...[
              const SizedBox(height: 16),
              Divider(
                color: context.cDivider,
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: CorviaColors.warning,
                    side: const BorderSide(
                      color: CorviaColors.warning,
                    ),
                  ),
                  onPressed: _openingReport ? null : _openReport,
                  icon: _openingReport
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                          ),
                        )
                      : const Icon(
                          Icons.report_problem_outlined,
                        ),
                  label: Text(
                    _openingReport ? 'Opening Report...' : 'Report Doctor',
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

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.text,
  });

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          icon,
          size: 17,
          color: context.cAccentReadable,
        ),
        const SizedBox(
          width: 9,
        ),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              color: context.cTextSecondary,
              fontSize: 14,
            ),
          ),
        ),
      ],
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.label,
    required this.color,
  });

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Appointment status: $label',
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: 10,
          vertical: 5,
        ),
        decoration: BoxDecoration(
          color: color.withValues(
            alpha: 0.14,
          ),
          borderRadius: BorderRadius.circular(
            20,
          ),
          border: Border.all(
            color: color.withValues(
              alpha: 0.40,
            ),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}
