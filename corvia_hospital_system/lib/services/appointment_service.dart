import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/supabase_service.dart';

/// Service class handling all appointment business logic
class AppointmentService {
  final SupabaseClient _supabase = SupabaseService.client;

  /// Returns a human-readable label for the given ISO weekday list.
  /// Examples: "Mon–Fri", "Mon, Wed, Fri", "Every day", "Not available".
  static String workingDaysLabel(List<int> days) {
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

  /// Advances [from] forward until it lands on a working day.
  /// Returns [from] if it is already a working day or [workingDays] is empty.
  static DateTime nextWorkingDay(DateTime from, List<int> workingDays) {
    if (workingDays.isEmpty) return from;
    var d = from;
    for (int i = 0; i < 7; i++) {
      if (workingDays.contains(d.weekday)) return d;
      d = d.add(const Duration(days: 1));
    }
    return from;
  }

  /// Format TimeOfDay to string (HH:MM)
  static String formatTimeOfDay(TimeOfDay t) {
    return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  }

  /// Get today's midnight DateTime
  static DateTime todayMidnight() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  /// Check if a given date is a working day
  static bool isWorkingDay(DateTime date, List<int> workingDays) {
    return workingDays.isEmpty || workingDays.contains(date.weekday);
  }

  /// Generate all possible slots for a given day based on doctor's schedule
  static List<DateTime> allSlotsForDay({
    required DateTime selectedDate,
    required int slotMins,
    required TimeOfDay workStart,
    required TimeOfDay workEnd,
    required List<int> workingDays,
  }) {
    if (!isWorkingDay(selectedDate, workingDays)) return [];

    final slots = <DateTime>[];
    final start = DateTime(selectedDate.year, selectedDate.month,
        selectedDate.day, workStart.hour, workStart.minute);
    final end = DateTime(selectedDate.year, selectedDate.month,
        selectedDate.day, workEnd.hour, workEnd.minute);
    var t = start;
    while (t.isBefore(end)) {
      slots.add(t);
      t = t.add(Duration(minutes: slotMins));
    }
    return slots;
  }

  /// Check if a specific slot can be booked
  bool isSlotBookable({
    required DateTime slot,
    required int selectedDuration,
    required DateTime selectedDate,
    required TimeOfDay workEnd,
    required int slotMins,
    required List appointmentRows,
    required List blockedRows,
  }) {
    if (slot.isBefore(DateTime.now())) return false;

    final slotEnd = slot.add(Duration(minutes: selectedDuration));

    // Must finish before (or exactly at) the end of the working day.
    final workEndDt = DateTime(selectedDate.year, selectedDate.month,
        selectedDate.day, workEnd.hour, workEnd.minute);
    if (slotEnd.isAfter(workEndDt)) return false;

    // Interval overlap with existing appointments.
    for (final row in appointmentRows) {
      if ((row['status']?.toString() ?? '') == 'cancelled') continue;
      final ts = DateTime.tryParse(row['appointment_date'].toString());
      if (ts == null) continue;
      final apptStart = ts.toLocal();
      final apptMins = (row['duration_minutes'] as int?) ?? slotMins;
      final apptEnd = apptStart.add(Duration(minutes: apptMins));
      if (slot.isBefore(apptEnd) && slotEnd.isAfter(apptStart)) {
        return false;
      }
    }

    // Interval overlap with blocked ranges.
    for (final row in blockedRows) {
      final blockStart =
          DateTime.tryParse(row['start_time'].toString())?.toLocal();
      final blockEnd = DateTime.tryParse(row['end_time'].toString())?.toLocal();
      if (blockStart == null || blockEnd == null) continue;
      if (slot.isBefore(blockEnd) && slotEnd.isAfter(blockStart)) {
        return false;
      }
    }

    return true;
  }

  /// Load busy slots (appointments and blocked times) for a doctor on a specific date
  Future<Map<String, List>> loadBusySlots({
    required String doctorId,
    required DateTime selectedDate,
  }) async {
    final start = selectedDate;
    final end = start.add(const Duration(days: 1));

    final appts = await _supabase
        .from('appointments')
        .select('appointment_date, duration_minutes, status')
        .eq('doctor_id', doctorId)
        .gte('appointment_date', start.toUtc().toIso8601String())
        .lt('appointment_date', end.toUtc().toIso8601String());

    List blocked = [];
    try {
      blocked = await _supabase
          .from('doctor_unavailable_slots')
          .select('start_time, end_time')
          .eq('doctor_id', doctorId)
          .gte('start_time', start.toUtc().toIso8601String())
          .lt('start_time', end.toUtc().toIso8601String());
    } catch (e) {
      debugPrint('AppointmentService: failed to load blocked slots: $e');
    }

    return {
      'appointments': appts as List,
      'blocked': blocked,
    };
  }

  /// Book an appointment
  Future<void> bookAppointment({
    required String patientId,
    required String doctorId,
    required DateTime slot,
    required int durationMinutes,
    required String reason,
    required String appointmentType,
  }) async {
    await _supabase.from('appointments').insert({
      'patient_id': patientId,
      'doctor_id': doctorId,
      'appointment_date': slot.toUtc().toIso8601String(),
      'duration_minutes': durationMinutes,
      'reason': reason,
      'type': appointmentType,
      'status': 'scheduled',
    });
  }

  /// Get duration options based on slot minutes
  static List<int> getDurationOptions(int slotMins) {
    final cap = (slotMins * 4) < 120 ? slotMins * 4 : 120;
    final opts = <int>[];
    for (var d = slotMins; d <= cap; d += slotMins) {
      opts.add(d);
    }
    return opts;
  }

  /// Get the current patient ID from Supabase auth
  static Future<String?> getCurrentPatientId() async {
    return await SupabaseService.currentPatientId();
  }
}
