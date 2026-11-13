import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/doctor_directory.dart';
import '../../services/supabase_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/doctor_availability_avatar.dart';
import '../../widgets/status_view.dart';

/// Statuses that still hold an appointment slot.
///
/// Cancelled, completed, no_show and missed must not block rebooking.
const List<String> kActiveAppointmentStatuses = [
  'pending',
  'scheduled',
  'confirmed',
  'checked_in',
];

/// Returns true when [slot] overlaps an existing active appointment row.
///
/// This helper is kept top-level because unit tests use it directly.
/// The live app now uses secure Supabase RPCs for final booking safety,
/// but this pure helper is still useful for testing slot-overlap logic.
@visibleForTesting
bool bookingClashesWith({
  required DateTime slot,
  required int durationMinutes,
  required int defaultDurationMinutes,
  required List<dynamic> rows,
}) {
  final slotEnd = slot.add(
    Duration(minutes: durationMinutes),
  );

  for (final row in rows) {
    if (row is! Map) {
      continue;
    }

    final status = (row['status'] ?? '')
        .toString()
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[\s-]+'), '_');

    if (!kActiveAppointmentStatuses.contains(status)) {
      continue;
    }

    final rawDate = row['appointment_date']?.toString();

    if (rawDate == null || rawDate.trim().isEmpty) {
      continue;
    }

    final parsed = DateTime.tryParse(rawDate);

    if (parsed == null) {
      continue;
    }

    final appointmentStart = parsed.toLocal();

    final durationValue = row['duration_minutes'];

    final appointmentMinutes = durationValue is int
        ? durationValue
        : durationValue is num
            ? durationValue.toInt()
            : int.tryParse(durationValue?.toString() ?? '') ??
                defaultDurationMinutes;

    final safeAppointmentMinutes =
        appointmentMinutes <= 0 ? defaultDurationMinutes : appointmentMinutes;

    final appointmentEnd = appointmentStart.add(
      Duration(minutes: safeAppointmentMinutes),
    );

    // Half-open range overlap:
    // 10:00-11:00 and 11:00-11:30 do NOT clash.
    if (slot.isBefore(appointmentEnd) && slotEnd.isAfter(appointmentStart)) {
      return true;
    }
  }

  return false;
}

String workingDaysLabel(List<int> days) {
  if (days.isEmpty) return 'Not available';

  final sorted = [...days]..sort();

  if (sorted.length == 7) return 'Every day';

  if (sorted.length == 5 && sorted.every((d) => d >= 1 && d <= 5)) {
    return 'Mon–Fri';
  }

  if (sorted.length == 6 && sorted.every((d) => d >= 1 && d <= 6)) {
    return 'Mon–Sat';
  }

  const names = ['', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  return sorted.map((d) => names[d]).join(', ');
}

DateTime nextWorkingDay(
  DateTime from,
  List<int> workingDays,
) {
  if (workingDays.isEmpty) return from;

  var date = from;

  for (var index = 0; index < 14; index++) {
    if (workingDays.contains(date.weekday)) {
      return date;
    }

    date = date.add(
      const Duration(days: 1),
    );
  }

  return from;
}

class BookingApp extends StatelessWidget {
  const BookingApp({
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return const _DoctorListPage();
  }
}

class _DoctorListPage extends StatefulWidget {
  const _DoctorListPage();

  @override
  State<_DoctorListPage> createState() {
    return _DoctorListPageState();
  }
}

class _DoctorListPageState extends State<_DoctorListPage> {
  Future<List<DoctorEntry>>? _future;

  bool _hasUserLocation = false;

  @override
  void initState() {
    super.initState();

    _refresh();
  }

  void _refresh() {
    setState(() {
      _future = _load();
    });
  }

  Future<List<DoctorEntry>> _load() async {
    _hasUserLocation = await DoctorDirectory.userLocationAvailable();

    String? ownDoctorId;

    try {
      ownDoctorId = await SupabaseService.currentDoctorId();
    } catch (error) {
      debugPrint(
        'BookAppointment: own doctor lookup failed: $error',
      );
    }

    final doctors = await DoctorDirectory.load(
      requireAvailable: true,
    );

    if (ownDoctorId == null || ownDoctorId.isEmpty) {
      return doctors;
    }

    return doctors
        .where(
          (doctor) => doctor.doctorId != ownDoctorId,
        )
        .toList();
  }

  Future<void> _openDoctor(
    DoctorEntry doctor,
  ) async {
    final booked = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) {
          return _BookSlotPage(
            doctor: doctor,
          );
        },
      ),
    );

    if (booked == true && mounted) {
      Navigator.of(context).pop(
        true,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.cBgPrimary,
      appBar: AppBar(
        title: const Text(
          'Book an Appointment',
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          _refresh();

          await _future;
        },
        child: FutureBuilder<List<DoctorEntry>>(
          future: _future,
          builder: (
            context,
            snapshot,
          ) {
            if (snapshot.connectionState != ConnectionState.done) {
              return StatusView.loading(
                message: 'Loading doctors...',
              );
            }

            if (snapshot.hasError) {
              return StatusView.error(
                friendlyMessage: "We couldn't load the doctor directory.",
                error: snapshot.error,
                stackTrace: snapshot.stackTrace,
                onRetry: _refresh,
              );
            }

            final doctors = snapshot.data ?? const [];

            if (doctors.isEmpty) {
              return StatusView.empty(
                icon: Icons.medical_services_outlined,
                title: 'No doctors are available right now',
                subtitle:
                    'Verified active doctors will appear here when booking is available.',
                onRetry: _refresh,
              );
            }

            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              children: [
                if (_hasUserLocation)
                  Padding(
                    padding: const EdgeInsets.only(
                      bottom: 8,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.my_location,
                          size: 14,
                          color: CorviaColors.accentLight,
                        ),
                        const SizedBox(
                          width: 6,
                        ),
                        Text(
                          'Sorted by distance from you',
                          style: TextStyle(
                            color: context.cTextSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                for (var index = 0; index < doctors.length; index++) ...[
                  _DoctorTile(
                    doctor: doctors[index],
                    onTap: () {
                      _openDoctor(
                        doctors[index],
                      );
                    },
                  ),
                  if (index != doctors.length - 1)
                    const SizedBox(
                      height: 12,
                    ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _DoctorTile extends StatelessWidget {
  const _DoctorTile({
    required this.doctor,
    required this.onTap,
  });

  final DoctorEntry doctor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final summary = [
      if (doctor.specialization.isNotEmpty) doctor.specialization,
      if (doctor.location.isNotEmpty) doctor.location,
    ].join(' • ');

    return Card(
      color: context.cBgSecondary,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 8,
        ),
        leading: DoctorAvailabilityAvatar(
          doctor: doctor,
        ),
        title: Text(
          doctor.displayName,
          style: TextStyle(
            color: context.cTextPrimary,
            fontWeight: FontWeight.bold,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (summary.isNotEmpty)
              Text(
                summary,
                style: TextStyle(
                  color: context.cTextSecondary,
                ),
              ),
            if (doctor.distanceLabel.isNotEmpty)
              Text(
                doctor.distanceLabel,
                style: TextStyle(
                  color: CorviaColors.accentLight,
                  fontSize: 12,
                ),
              ),
            Text(
              '${doctor.slotDurationMinutes}-min appts • '
              '${workingDaysLabel(doctor.workingDays)}',
              style: TextStyle(
                color: context.cTextMuted,
                fontSize: 11,
              ),
            ),
          ],
        ),
        trailing: Icon(
          Icons.chevron_right,
          color: CorviaColors.accentLight,
        ),
        onTap: onTap,
      ),
    );
  }
}

class _BookSlotPage extends StatefulWidget {
  const _BookSlotPage({
    required this.doctor,
  });

  final DoctorEntry doctor;

  @override
  State<_BookSlotPage> createState() {
    return _BookSlotPageState();
  }
}

class _BookSlotPageState extends State<_BookSlotPage> {
  static const Duration _requestTimeout = Duration(seconds: 20);

  int get _slotMins => widget.doctor.slotDurationMinutes;

  TimeOfDay get _workStart => widget.doctor.workStart;

  TimeOfDay get _workEnd => widget.doctor.workEnd;

  List<int> get _workingDays => widget.doctor.workingDays;

  late int _selectedDuration;
  late DateTime _selectedDate;

  String _appointmentType = 'in-person';

  final TextEditingController _reasonCtrl = TextEditingController();

  List<_BusyInterval> _busyIntervals = [];

  bool _loadingSlots = true;
  bool _booking = false;
  bool _hasUnsavedChanges = false;

  String? _slotError;

  @override
  void initState() {
    super.initState();

    _selectedDuration = _slotMins;
    _selectedDate = _firstUsefulDate();

    _loadBusy();
  }

  @override
  void dispose() {
    _reasonCtrl.dispose();

    super.dispose();
  }

  static DateTime _todayMidnight() {
    final now = DateTime.now();

    return DateTime(
      now.year,
      now.month,
      now.day,
    );
  }

  DateTime _firstUsefulDate() {
    final now = DateTime.now();

    final today = _todayMidnight();

    final todayWorkEnd = DateTime(
      today.year,
      today.month,
      today.day,
      _workEnd.hour,
      _workEnd.minute,
    );

    if ((_workingDays.isEmpty || _workingDays.contains(today.weekday)) &&
        now.isBefore(todayWorkEnd)) {
      return today;
    }

    return nextWorkingDay(
      today.add(
        const Duration(days: 1),
      ),
      _workingDays,
    );
  }

  List<int> get _durationOptions {
    final cap = (_slotMins * 4) < 120 ? _slotMins * 4 : 120;

    final values = <int>[];

    for (var duration = _slotMins;
        duration <= cap;
        duration += _slotMins) {
      values.add(duration);
    }

    return values.isEmpty ? [_slotMins] : values;
  }

  bool get _isWorkingDay {
    return _workingDays.isEmpty ||
        _workingDays.contains(
          _selectedDate.weekday,
        );
  }

  List<DateTime> _allSlotsForDay() {
    if (!_isWorkingDay) {
      return [];
    }

    final slots = <DateTime>[];

    final start = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
      _workStart.hour,
      _workStart.minute,
    );

    final end = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
      _workEnd.hour,
      _workEnd.minute,
    );

    var time = start;

    while (time.isBefore(end)) {
      slots.add(time);

      time = time.add(
        Duration(
          minutes: _slotMins,
        ),
      );
    }

    return slots;
  }

  bool _isSlotInPast(
    DateTime slot,
  ) {
    return slot.isBefore(
      DateTime.now(),
    );
  }

  bool _isSlotBookable(
    DateTime slot,
  ) {
    if (_booking || _isSlotInPast(slot)) {
      return false;
    }

    final slotEnd = slot.add(
      Duration(
        minutes: _selectedDuration,
      ),
    );

    final workEnd = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
      _workEnd.hour,
      _workEnd.minute,
    );

    if (slotEnd.isAfter(workEnd)) {
      return false;
    }

    for (final busy in _busyIntervals) {
      if (slot.isBefore(busy.end) && slotEnd.isAfter(busy.start)) {
        return false;
      }
    }

    return true;
  }

  Future<void> _loadBusy() async {
    if (!_isWorkingDay) {
      if (!mounted) return;

      setState(() {
        _busyIntervals = [];
        _loadingSlots = false;
        _slotError = null;
      });

      return;
    }

    setState(() {
      _loadingSlots = true;
      _slotError = null;
    });

    try {
      final response = await SupabaseService.client
          .rpc(
            'corvia_patient_doctor_busy_slots',
            params: {
              'p_doctor_id': widget.doctor.doctorId,
              'p_day': DateFormat(
                'yyyy-MM-dd',
              ).format(
                _selectedDate,
              ),
            },
          )
          .timeout(
            _requestTimeout,
          );

      final busy = <_BusyInterval>[];

      if (response is List) {
        for (final raw in response) {
          if (raw is! Map) {
            continue;
          }

          final row = Map<String, dynamic>.from(
            raw,
          );

          final start = DateTime.tryParse(
            row['start_time']?.toString() ?? '',
          )?.toLocal();

          final end = DateTime.tryParse(
            row['end_time']?.toString() ?? '',
          )?.toLocal();

          if (start == null || end == null || !end.isAfter(start)) {
            continue;
          }

          busy.add(
            _BusyInterval(
              start: start,
              end: end,
              kind: row['slot_kind']?.toString() ?? 'busy',
            ),
          );
        }
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _busyIntervals = busy;
        _loadingSlots = false;
        _slotError = null;
      });
    } on TimeoutException {
      if (!mounted) return;

      setState(() {
        _loadingSlots = false;
        _slotError = 'Checking availability took too long. Please try again.';
      });
    } catch (error) {
      debugPrint(
        'BookAppointment busy-slot load failed: $error',
      );

      if (!mounted) return;

      setState(() {
        _loadingSlots = false;
        _slotError = "We couldn't check the doctor's schedule.";
      });
    }
  }

  Future<void> _moveToNextWorkingDay() async {
    final nextDate = nextWorkingDay(
      _selectedDate.add(
        const Duration(days: 1),
      ),
      _workingDays,
    );

    setState(() {
      _selectedDate = nextDate;
      _hasUnsavedChanges = true;
    });

    await _loadBusy();
  }

  Future<void> _pickDate() async {
    final safeInitial =
        _workingDays.isEmpty || _workingDays.contains(_selectedDate.weekday)
            ? _selectedDate
            : nextWorkingDay(
                _selectedDate,
                _workingDays,
              );

    final picked = await showDatePicker(
      context: context,
      initialDate: safeInitial,
      firstDate: _todayMidnight(),
      lastDate: _todayMidnight().add(
        const Duration(days: 60),
      ),
      selectableDayPredicate: _workingDays.isEmpty
          ? null
          : (day) {
              return _workingDays.contains(
                day.weekday,
              );
            },
      builder: (
        pickerContext,
        child,
      ) {
        return Theme(
          data: Theme.of(
            pickerContext,
          ).copyWith(
            colorScheme: Theme.of(
              pickerContext,
            ).colorScheme.copyWith(
                  primary: CorviaColors.accent,
                  onPrimary: Colors.white,
                  surface: context.cBgSecondary,
                  onSurface: context.cTextPrimary,
                ),
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(
                foregroundColor: CorviaColors.accentLight,
              ),
            ),
            dialogTheme: DialogThemeData(
              backgroundColor: context.cBgPrimary,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked == null) {
      return;
    }

    setState(() {
      _selectedDate = DateTime(
        picked.year,
        picked.month,
        picked.day,
      );

      _hasUnsavedChanges = true;
    });

    await _loadBusy();
  }

  Future<void> _book(
    DateTime slot,
  ) async {
    if (_booking) {
      return;
    }

    if (!_isSlotBookable(slot)) {
      _snack(
        'That time is no longer available.',
      );

      return;
    }

    final reason = _reasonCtrl.text.trim();

    if (reason.length < 2) {
      _snack(
        'Please describe the reason for your visit first.',
      );

      return;
    }

    final durationLabel = _selectedDuration == _slotMins
        ? '$_selectedDuration min'
        : '$_selectedDuration min '
            '(${_selectedDuration ~/ _slotMins} slots)';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (
        dialogContext,
      ) {
        return AlertDialog(
          backgroundColor: context.cBgSecondary,
          title: Text(
            'Confirm appointment',
            style: TextStyle(
              color: context.cTextPrimary,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _ConfirmRow(
                Icons.person,
                widget.doctor.displayName,
              ),
              _ConfirmRow(
                Icons.calendar_today,
                DateFormat(
                  'EEE d MMM yyyy',
                ).format(slot),
              ),
              _ConfirmRow(
                Icons.access_time,
                DateFormat.Hm().format(slot),
              ),
              _ConfirmRow(
                Icons.timelapse_outlined,
                durationLabel,
              ),
              _ConfirmRow(
                Icons.local_hospital_outlined,
                'In-person',
              ),
              _ConfirmRow(
                Icons.notes_outlined,
                reason,
              ),
            ],
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
                'Cancel',
              ),
            ),
            ElevatedButton(
              key: const Key(
                'confirmBookingButton',
              ),
              onPressed: () {
                Navigator.pop(
                  dialogContext,
                  true,
                );
              },
              child: const Text(
                'Confirm booking',
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
      _booking = true;
    });

    try {
      final appointmentId = await SupabaseService.client
          .rpc(
            'corvia_patient_book_appointment',
            params: {
              'p_doctor_id': widget.doctor.doctorId,
              'p_appointment_date': slot.toUtc().toIso8601String(),
              'p_duration_minutes': _selectedDuration,
              'p_reason': reason,
              'p_appointment_type': _appointmentType,
            },
          )
          .timeout(
            _requestTimeout,
          );

      if (appointmentId == null) {
        throw StateError(
          'The appointment was not created.',
        );
      }

      if (!mounted) {
        return;
      }

      _hasUnsavedChanges = false;

      _reasonCtrl.clear();

      _snack(
        'Appointment booked successfully.',
      );

      Navigator.of(context).pop(
        true,
      );
    } on TimeoutException {
      if (!mounted) return;

      _snack(
        'Booking took too long. '
        'Please refresh your appointments before trying again.',
        isError: true,
      );

      await _loadBusy();
    } on PostgrestException catch (error) {
      debugPrint(
        'BookAppointment RPC error: '
        '${error.message} | ${error.code}',
      );

      if (!mounted) return;

      _snack(
        _bookingErrorMessage(
          error,
        ),
        isError: true,
      );

      await _loadBusy();
    } catch (error) {
      debugPrint(
        'BookAppointment failed: $error',
      );

      if (!mounted) return;

      _snack(
        "We couldn't book that appointment. Please try again.",
        isError: true,
      );

      await _loadBusy();
    } finally {
      if (mounted) {
        setState(() {
          _booking = false;
        });
      }
    }
  }

  String _bookingErrorMessage(
    PostgrestException error,
  ) {
    final message = error.message.toLowerCase();

    if (message.contains(
      'already have another appointment',
    )) {
      return 'You already have another appointment during that time.';
    }

    if (message.contains(
          'no longer available',
        ) ||
        message.contains(
          'unavailable during',
        )) {
      return 'That appointment time is no longer available. Please choose another time.';
    }

    if (message.contains(
      'own doctor profile',
    )) {
      return 'You cannot book yourself as your own treating doctor.';
    }

    if (message.contains(
      'doctor is not currently available',
    )) {
      return 'This doctor is no longer available for booking.';
    }

    if (error.code == '23P01') {
      return 'That time overlaps an existing appointment.';
    }

    return "We couldn't book that appointment. Please try again.";
  }

  void _snack(
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

  String _fmtTOD(
    TimeOfDay time,
  ) {
    return '${time.hour.toString().padLeft(2, '0')}:'
        '${time.minute.toString().padLeft(2, '0')}';
  }

  Widget _choiceChip({
    Key? key,
    required String label,
    required bool selected,
    required VoidCallback onSelected,
  }) {
    return ChoiceChip(
      key: key,
      label: Text(label),
      selected: selected,
      selectedColor: CorviaColors.accent,
      backgroundColor: context.cBgSecondary,
      labelStyle: TextStyle(
        color: selected ? Colors.white : context.cTextPrimary,
        fontWeight: selected ? FontWeight.bold : FontWeight.w500,
      ),
      side: BorderSide(
        color: selected ? CorviaColors.accent : context.cDivider,
      ),
      onSelected: _booking
          ? null
          : (_) {
              onSelected();
            },
    );
  }

  @override
  Widget build(BuildContext context) {
    final dateLabel = DateFormat(
      'EEE, d MMM yyyy',
    ).format(
      _selectedDate,
    );

    final slots = _allSlotsForDay();

    final durations = _durationOptions;

    return PopScope(
      canPop: !_hasUnsavedChanges && !_booking,
      onPopInvokedWithResult: (
        didPop,
        result,
      ) async {
        if (didPop || !_hasUnsavedChanges || _booking) {
          return;
        }

        final shouldLeave = await showDialog<bool>(
          context: context,
          builder: (
            dialogContext,
          ) {
            return AlertDialog(
              title: const Text(
                'Unsaved Changes',
              ),
              content: const Text(
                'You have unsaved appointment details. '
                'If you leave now, your changes will be lost.',
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
                    'Stay',
                  ),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.pop(
                      dialogContext,
                      true,
                    );
                  },
                  child: const Text(
                    'Leave',
                  ),
                ),
              ],
            );
          },
        );

        if (shouldLeave != true || !context.mounted) {
          return;
        }

        setState(() {
          _hasUnsavedChanges = false;
        });

        Navigator.of(context).pop();
      },
      child: Scaffold(
        backgroundColor: context.cBgPrimary,
        resizeToAvoidBottomInset: true,
        appBar: AppBar(
          title: Text(
            widget.doctor.displayName,
          ),
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              16,
              16,
              16,
              32,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (widget.doctor.specialization.isNotEmpty)
                  Text(
                    widget.doctor.specialization,
                    style: TextStyle(
                      color: CorviaColors.accentLight,
                      fontSize: 16,
                    ),
                  ),
                if (widget.doctor.distanceLabel.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(
                      top: 4,
                    ),
                    child: Text(
                      widget.doctor.distanceLabel,
                      style: TextStyle(
                        color: context.cTextSecondary,
                        fontSize: 13,
                      ),
                    ),
                  ),
                const SizedBox(
                  height: 16,
                ),
                Card(
                  color: context.cBgSecondary,
                  child: Padding(
                    padding: const EdgeInsets.all(
                      12,
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.calendar_today,
                              color: CorviaColors.accentLight,
                            ),
                            const SizedBox(
                              width: 12,
                            ),
                            Expanded(
                              child: Text(
                                dateLabel,
                                style: TextStyle(
                                  color: context.cTextPrimary,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            TextButton(
                              onPressed: _booking ? null : _pickDate,
                              child: const Text(
                                'Change',
                              ),
                            ),
                          ],
                        ),
                        Divider(
                          height: 1,
                          color: context.cDivider,
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: 8,
                          ),
                          child: Wrap(
                            alignment: WrapAlignment.center,
                            spacing: 10,
                            runSpacing: 4,
                            children: [
                              _SmallInfo(
                                icon: Icons.event_available,
                                text: workingDaysLabel(
                                  _workingDays,
                                ),
                              ),
                              _SmallInfo(
                                icon: Icons.schedule,
                                text:
                                    '${_fmtTOD(_workStart)}–${_fmtTOD(_workEnd)}',
                              ),
                            ],
                          ),
                        ),
                        Divider(
                          height: 1,
                          color: context.cDivider,
                        ),
                        Padding(
                          padding: const EdgeInsets.only(
                            top: 8,
                          ),
                          child: Row(
                            children: [
                              Text(
                                'Type:',
                                style: TextStyle(
                                  color: context.cTextPrimary,
                                ),
                              ),
                              const SizedBox(
                                width: 12,
                              ),
                              _choiceChip(
                                key: const Key(
                                  'inPersonChip',
                                ),
                                label: 'In-person',
                                selected: true,
                                onSelected: () {
                                  setState(
                                    () {
                                      _appointmentType = 'in-person';

                                      _hasUnsavedChanges = true;
                                    },
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                        if (durations.length > 1) ...[
                          Divider(
                            height: 14,
                            color: context.cDivider,
                          ),
                          Row(
                            children: [
                              Text(
                                'Duration:',
                                style: TextStyle(
                                  color: context.cTextPrimary,
                                ),
                              ),
                              const SizedBox(
                                width: 12,
                              ),
                              Expanded(
                                child: SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: Row(
                                    children: [
                                      for (final duration in durations)
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            right: 8,
                                          ),
                                          child: _choiceChip(
                                            key: Key(
                                              'duration_$duration',
                                            ),
                                            label: '$duration min',
                                            selected:
                                                _selectedDuration == duration,
                                            onSelected: () {
                                              setState(
                                                () {
                                                  _selectedDuration = duration;

                                                  _hasUnsavedChanges = true;
                                                },
                                              );
                                            },
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(
                  height: 12,
                ),
                TextField(
                  key: const Key(
                    'reasonField',
                  ),
                  controller: _reasonCtrl,
                  enabled: !_booking,
                  onChanged: (_) {
                    _hasUnsavedChanges = true;
                  },
                  style: TextStyle(
                    color: context.cTextPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                  cursorColor: CorviaColors.accent,
                  maxLines: 2,
                  maxLength: 2000,
                  decoration: InputDecoration(
                    labelText: 'Reason for visit',
                    hintText: 'e.g. Follow-up on blood test results',
                    labelStyle: TextStyle(
                      color: context.cTextSecondary,
                    ),
                    hintStyle: TextStyle(
                      color: context.cTextMuted,
                    ),
                    filled: true,
                    fillColor: context.cBgSecondary,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(
                        14,
                      ),
                    ),
                  ),
                ),
                const SizedBox(
                  height: 16,
                ),
                Row(
                  children: [
                    Text(
                      'Available times',
                      style: TextStyle(
                        color: CorviaColors.accentLight,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(
                      width: 8,
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: CorviaColors.accent.withValues(
                          alpha: 0.15,
                        ),
                        borderRadius: BorderRadius.circular(
                          6,
                        ),
                      ),
                      child: Text(
                        '$_selectedDuration min',
                        style: TextStyle(
                          color: CorviaColors.accentLight,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(
                  height: 8,
                ),
                _buildSlotArea(
                  slots,
                ),
                if (_booking)
                  Padding(
                    padding: const EdgeInsets.only(
                      top: 12,
                    ),
                    child: LinearProgressIndicator(
                      color: CorviaColors.accent,
                      backgroundColor: context.cBgSecondary,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSlotArea(
    List<DateTime> slots,
  ) {
    const statusHeight = 220.0;

    if (!_isWorkingDay) {
      final dayName = DateFormat(
        'EEEE',
      ).format(
        _selectedDate,
      );

      return SizedBox(
        height: statusHeight,
        child: StatusView.empty(
          icon: Icons.event_busy_outlined,
          title: '$dayName is not a working day',
          subtitle: '${widget.doctor.displayName} works on '
              '${workingDaysLabel(_workingDays)}.',
        ),
      );
    }

    if (_loadingSlots) {
      return SizedBox(
        height: statusHeight,
        child: StatusView.loading(
          message: 'Checking availability...',
        ),
      );
    }

    if (_slotError != null) {
      return SizedBox(
        height: statusHeight,
        child: StatusView.error(
          friendlyMessage: _slotError!,
          onRetry: _loadBusy,
        ),
      );
    }

    if (slots.isEmpty) {
      return SizedBox(
        height: statusHeight,
        child: StatusView.empty(
          icon: Icons.event_busy_outlined,
          title: 'No slots available',
          subtitle: 'This doctor has no bookable slots on this day.',
        ),
      );
    }

    final anyBookable = slots.any(
      _isSlotBookable,
    );

    final allSlotsPast = slots.every(
      _isSlotInPast,
    );

    if (!anyBookable && allSlotsPast) {
      return SizedBox(
        height: statusHeight,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(
              18,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.access_time,
                  color: context.cTextMuted,
                  size: 46,
                ),
                const SizedBox(
                  height: 10,
                ),
                Text(
                  'Today’s available times have passed',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: context.cTextPrimary,
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(
                  height: 6,
                ),
                Text(
                  'Choose the next available working day.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: context.cTextSecondary,
                  ),
                ),
                const SizedBox(
                  height: 14,
                ),
                ElevatedButton.icon(
                  onPressed: _moveToNextWorkingDay,
                  icon: const Icon(
                    Icons.arrow_forward,
                  ),
                  label: const Text(
                    'Next available day',
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (!anyBookable) {
      return SizedBox(
        height: statusHeight,
        child: StatusView.empty(
          icon: Icons.event_busy_outlined,
          title: 'No available times',
          subtitle:
              'All appointment times for this day are currently occupied or blocked.',
        ),
      );
    }

    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 3,
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: 2.4,
      children: [
        for (final slot in slots)
          _SlotChip(
            time: slot,
            bookable: _isSlotBookable(
              slot,
            ),
            onTap: () {
              _book(slot);
            },
          ),
      ],
    );
  }
}

class _BusyInterval {
  const _BusyInterval({
    required this.start,
    required this.end,
    required this.kind,
  });

  final DateTime start;
  final DateTime end;
  final String kind;
}

class _SmallInfo extends StatelessWidget {
  const _SmallInfo({
    required this.icon,
    required this.text,
  });

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 14,
          color: context.cTextMuted,
        ),
        const SizedBox(
          width: 4,
        ),
        Text(
          text,
          style: TextStyle(
            color: context.cTextMuted,
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}

class _ConfirmRow extends StatelessWidget {
  const _ConfirmRow(
    this.icon,
    this.text,
  );

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        vertical: 5,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            size: 16,
            color: CorviaColors.accentLight,
          ),
          const SizedBox(
            width: 10,
          ),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: context.cTextPrimary,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SlotChip extends StatelessWidget {
  const _SlotChip({
    required this.time,
    required this.bookable,
    required this.onTap,
  });

  final DateTime time;
  final bool bookable;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final label = DateFormat.Hm().format(
      time,
    );

    return Material(
      color: bookable ? CorviaColors.accent : context.cBgSecondary,
      borderRadius: BorderRadius.circular(
        10,
      ),
      child: InkWell(
        key: Key(
          'appointmentSlot_$label',
        ),
        borderRadius: BorderRadius.circular(
          10,
        ),
        onTap: bookable ? onTap : null,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(
              10,
            ),
            border: Border.all(
              color: bookable ? CorviaColors.accent : context.cDivider,
            ),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: bookable ? Colors.white : context.cTextMuted,
                fontWeight: FontWeight.bold,
                decoration: bookable ? null : TextDecoration.lineThrough,
              ),
            ),
          ),
        ),
      ),
    );
  }
}