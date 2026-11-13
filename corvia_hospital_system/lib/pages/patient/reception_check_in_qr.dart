import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../theme/app_theme.dart';

import 'scan_code_page.dart';

class ReceptionCheckInQrPage extends StatefulWidget {
  const ReceptionCheckInQrPage({super.key});

  @override
  State<ReceptionCheckInQrPage> createState() => _ReceptionCheckInQrPageState();
}

class _ReceptionCheckInQrPageState extends State<ReceptionCheckInQrPage> {
  final SupabaseClient _client = Supabase.instance.client;

  _PatientAppointmentQr? _appointment;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadAppointmentQr();
  }

  Future<void> _loadAppointmentQr() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final response = await _client.rpc('patient_my_checkin_qr');

      if (response is! Map) {
        throw Exception('Appointment QR data could not load.');
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _appointment = _PatientAppointmentQr.fromJson(
          Map<String, dynamic>.from(response),
        );
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _error = _cleanError(error);
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
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

  Future<void> _openWalkInScanner() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const ScanCodePage(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.cBgPrimary,
      appBar: AppBar(
        title: const Text('My Appointment QR'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : _loadAppointmentQr,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadAppointmentQr,
        color: CorviaColors.accent,
        child: _buildBody(),
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: OutlinedButton.icon(
          onPressed: _openWalkInScanner,
          icon: const Icon(Icons.qr_code_scanner_rounded),
          label: const Text('Walk-in Check-in'),
        ),
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
          const SizedBox(height: 110),
          Icon(
            Icons.cloud_off_rounded,
            color: Colors.red.shade400,
            size: 58,
          ),
          const SizedBox(height: 16),
          Text(
            _error!,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: context.cTextPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _loadAppointmentQr,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Try Again'),
          ),
        ],
      );
    }

    final appointment = _appointment;

    if (appointment == null || !appointment.hasAppointment) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 110),
          Icon(
            Icons.event_busy_rounded,
            color: context.cTextSecondary,
            size: 58,
          ),
          const SizedBox(height: 16),
          Text(
            'No upcoming appointment',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: context.cTextPrimary,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            appointment?.message ??
                'Book an appointment first. Your check-in QR will appear here.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: context.cTextSecondary,
            ),
          ),
        ],
      );
    }

    final qrData =
        'CORVIA_CHECKIN|v=1|patient_id=${appointment.patientId}|appointment_id=${appointment.appointmentId}';

    final dateText = appointment.appointmentTime == null
        ? 'Appointment time unavailable'
        : DateFormat('EEEE, d MMMM yyyy • HH:mm')
            .format(appointment.appointmentTime!);

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(20),
      children: [
        Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: context.cBgSecondary,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: CorviaColors.divider,
            ),
          ),
          child: Column(
            children: [
              Icon(
                appointment.alreadyCheckedIn
                    ? Icons.check_circle_rounded
                    : Icons.qr_code_2_rounded,
                color: appointment.alreadyCheckedIn
                    ? Colors.green
                    : CorviaColors.accent,
                size: 42,
              ),
              const SizedBox(height: 14),
              Text(
                appointment.alreadyCheckedIn
                    ? 'Already Checked In'
                    : 'Scan at Reception',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: context.cTextPrimary,
                  fontSize: 23,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                appointment.patientName,
                style: TextStyle(
                  color: context.cTextPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                appointment.patientNumber,
                style: TextStyle(
                  color: context.cTextSecondary,
                ),
              ),
              const SizedBox(height: 20),
              Opacity(
                opacity: appointment.alreadyCheckedIn ? 0.45 : 1,
                child: QrImageView(
                  data: qrData,
                  size: 250,
                  backgroundColor: Colors.white,
                ),
              ),
              const SizedBox(height: 20),
              _detailRow(
                Icons.calendar_today_rounded,
                dateText,
              ),
              _detailRow(
                Icons.local_hospital_rounded,
                appointment.departmentName,
              ),
              _detailRow(
                Icons.person_outline_rounded,
                appointment.doctorName,
              ),
              _detailRow(
                Icons.notes_rounded,
                appointment.reason,
              ),
              const SizedBox(height: 18),
              _statusNotice(appointment),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Show this QR to Reception when you arrive. Reception will verify the appointment before checking you in.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: context.cTextSecondary,
            height: 1.4,
          ),
        ),
      ],
    );
  }

  Widget _detailRow(IconData icon, String value) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        children: [
          Icon(
            icon,
            size: 18,
            color: CorviaColors.accent,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: context.cTextPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusNotice(_PatientAppointmentQr appointment) {
    if (appointment.alreadyCheckedIn) {
      return _notice(
        icon: Icons.check_circle_outline_rounded,
        color: Colors.green,
        message:
            'Reception has already checked you in. Please wait for your queue update.',
      );
    }

    if (!appointment.isToday) {
      return _notice(
        icon: Icons.info_outline_rounded,
        color: Colors.orange.shade800,
        message:
            'This QR becomes valid on your appointment date. Reception cannot check you in early.',
      );
    }

    return _notice(
      icon: Icons.verified_user_outlined,
      color: Colors.green,
      message:
          'Your appointment is scheduled for today and ready for Reception check-in.',
    );
  }

  Widget _notice({
    required IconData icon,
    required Color color,
    required String message,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: color.withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: context.cTextPrimary,
                fontSize: 13,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PatientAppointmentQr {
  const _PatientAppointmentQr({
    required this.hasAppointment,
    required this.patientId,
    required this.patientName,
    required this.patientNumber,
    required this.appointmentId,
    required this.doctorName,
    required this.departmentName,
    required this.reason,
    required this.isToday,
    required this.alreadyCheckedIn,
    this.appointmentTime,
    this.message,
  });

  final bool hasAppointment;
  final String patientId;
  final String patientName;
  final String patientNumber;
  final String appointmentId;
  final String doctorName;
  final String departmentName;
  final String reason;
  final bool isToday;
  final bool alreadyCheckedIn;
  final DateTime? appointmentTime;
  final String? message;

  factory _PatientAppointmentQr.fromJson(Map<String, dynamic> json) {
    return _PatientAppointmentQr(
      hasAppointment: json['hasAppointment'] == true ||
          json['hasAppointment']?.toString().toLowerCase() == 'true',
      patientId: (json['patientId'] ?? '').toString(),
      patientName: (json['patientName'] ?? 'Corvia Patient').toString(),
      patientNumber: (json['patientNumber'] ?? 'Patient record').toString(),
      appointmentId: (json['appointmentId'] ?? '').toString(),
      doctorName: (json['doctorName'] ?? 'Unassigned doctor').toString(),
      departmentName:
          (json['departmentName'] ?? 'Unassigned department').toString(),
      reason: (json['reason'] ?? 'Appointment consultation').toString(),
      isToday: json['isToday'] == true ||
          json['isToday']?.toString().toLowerCase() == 'true',
      alreadyCheckedIn: json['alreadyCheckedIn'] == true ||
          json['alreadyCheckedIn']?.toString().toLowerCase() == 'true',
      appointmentTime: DateTime.tryParse(
        (json['appointmentTime'] ?? '').toString(),
      )?.toLocal(),
      message: json['message']?.toString(),
    );
  }
}
