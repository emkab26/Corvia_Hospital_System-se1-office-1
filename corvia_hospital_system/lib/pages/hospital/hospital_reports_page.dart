import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../theme/app_theme.dart';

class HospitalReportsPage extends StatefulWidget {
  const HospitalReportsPage({super.key, this.onBack});

  final VoidCallback? onBack;

  @override
  State<HospitalReportsPage> createState() => _HospitalReportsPageState();
}

class _HospitalReportsPageState extends State<HospitalReportsPage> {
  final SupabaseClient _supabase = Supabase.instance.client;
  Color get primary => context.cAccentReadable;
  Color get accent => CorviaColors.accent;
  Color get success => CorviaColors.success;
  Color get warning => CorviaColors.warning;
  Color get error => CorviaColors.danger;
  Color get background => context.cBgPrimary;
  Color get textDark => context.cTextPrimary;
  Color get mutedText => context.cTextMuted;

  bool _loading = true;
  String? _error;

  String? _hospitalId;
  String _hospitalName = 'Hospital Reports';
  String _dateRange = 'All time';

  List<Map<String, dynamic>> _patients = [];
  List<Map<String, dynamic>> _doctors = [];
  List<Map<String, dynamic>> _departments = [];
  List<Map<String, dynamic>> _appointments = [];
  List<Map<String, dynamic>> _checkins = [];
  List<Map<String, dynamic>> _aiBookings = [];

  @override
  void initState() {
    super.initState();
    _loadReports();
  }

  Future<void> _loadReports() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      await _loadHospitalContext();
      await _loadHospitalData();
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _loadHospitalContext() async {
    final user = _supabase.auth.currentUser;

    if (user == null) {
      throw Exception('You are not signed in.');
    }

    final adminLink = await _supabase
        .from('hospital_admins')
        .select('hospital_id, hospitals(name)')
        .eq('profile_id', user.id)
        .maybeSingle();

    if (adminLink == null) {
      throw Exception('This account is not linked to a hospital admin record.');
    }

    final hospitalId = adminLink['hospital_id']?.toString();

    if (hospitalId == null || hospitalId.trim().isEmpty) {
      throw Exception('No hospital is linked to this admin account.');
    }

    _hospitalId = hospitalId;

    final hospital = adminLink['hospitals'];

    if (hospital is Map && hospital['name'] != null) {
      _hospitalName = hospital['name'].toString();
    }
  }

  Future<void> _loadHospitalData() async {
    final hospitalId = _hospitalId;

    if (hospitalId == null) {
      throw Exception('Hospital ID could not be found.');
    }

    final results = await Future.wait([
      _loadTable('patients', hospitalId),
      _loadTable('doctors', hospitalId),
      _loadTable('departments', hospitalId),
      _loadTable('appointments', hospitalId),
      _loadTable('reception_checkins', hospitalId),
      _loadTable('hospital_ai_booking_requests', hospitalId),
    ]);

    _patients = results[0];
    _doctors = results[1];
    _departments = results[2];
    _appointments = results[3];
    _checkins = results[4];
    _aiBookings = results[5];
  }

  Future<List<Map<String, dynamic>>> _loadTable(
    String table,
    String hospitalId,
  ) async {
    try {
      final rows = await _supabase
          .from(table)
          .select()
          .eq('hospital_id', hospitalId)
          .limit(1000);

      return rows
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList();
    } catch (_) {
      return [];
    }
  }

  DateTime? _dateForRecord(Map<String, dynamic> record) {
    final rawDate = record['appointment_date'] ??
        record['scheduled_for'] ??
        record['created_at'] ??
        record['updated_at'];

    if (rawDate == null) return null;

    return DateTime.tryParse(rawDate.toString())?.toLocal();
  }

  bool _matchesSelectedDateRange(Map<String, dynamic> record) {
    if (_dateRange == 'All time') return true;

    final date = _dateForRecord(record);

    if (date == null) return false;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    if (_dateRange == 'Today') {
      final tomorrow = today.add(const Duration(days: 1));

      return !date.isBefore(today) && date.isBefore(tomorrow);
    }

    if (_dateRange == 'Last 7 days') {
      final sevenDaysAgo = today.subtract(const Duration(days: 7));

      return !date.isBefore(sevenDaysAgo);
    }

    if (_dateRange == 'This month') {
      return date.year == now.year && date.month == now.month;
    }

    return true;
  }

  List<Map<String, dynamic>> get _filteredAppointments {
    return _appointments.where(_matchesSelectedDateRange).toList();
  }

  List<Map<String, dynamic>> get _filteredCheckins {
    return _checkins.where(_matchesSelectedDateRange).toList();
  }

  List<Map<String, dynamic>> get _filteredAiBookings {
    return _aiBookings.where(_matchesSelectedDateRange).toList();
  }

  String _normaliseAppointmentStatus(Map<String, dynamic> appointment) {
    final raw = appointment['status'] ?? appointment['appointment_status'];

    final value = raw
        ?.toString()
        .trim()
        .toLowerCase()
        .replaceAll(' ', '_')
        .replaceAll('-', '_');

    const valid = [
      'pending',
      'scheduled',
      'confirmed',
      'checked_in',
      'completed',
      'cancelled',
      'no_show',
    ];

    return valid.contains(value) ? value! : 'pending';
  }

  String _normaliseDoctorStatus(Map<String, dynamic> doctor) {
    final value = doctor['status']
        ?.toString()
        .trim()
        .toLowerCase()
        .replaceAll(' ', '_')
        .replaceAll('-', '_');

    if (value == 'busy') return 'busy';
    if (value == 'off_duty') return 'off_duty';
    if (value == 'inactive') return 'inactive';

    return 'available';
  }

  String _normaliseCheckinStatus(Map<String, dynamic> checkin) {
    final raw = checkin['queue_status'] ??
        checkin['checkin_status'] ??
        checkin['status'];

    final value = raw
        ?.toString()
        .trim()
        .toLowerCase()
        .replaceAll(' ', '_')
        .replaceAll('-', '_');

    if (value == null || value.isEmpty) return 'waiting';

    if (value.contains('emergency') || value.contains('critical')) {
      return 'emergency';
    }

    if (value.contains('consultation')) {
      return 'in_consultation';
    }

    if (value.contains('assign')) {
      return 'assigned';
    }

    if (value.contains('book')) {
      return 'booked';
    }

    if (value.contains('complete')) {
      return 'completed';
    }

    if (value.contains('cancel')) {
      return 'cancelled';
    }

    return 'waiting';
  }

  String _normaliseAiStatus(Map<String, dynamic> booking) {
    final raw = booking['status'];

    final value = raw
        ?.toString()
        .trim()
        .toLowerCase()
        .replaceAll(' ', '_')
        .replaceAll('-', '_');

    if (value == null || value.isEmpty) return 'new';

    if (value.contains('emergency') || value.contains('critical')) {
      return 'emergency';
    }

    if (value.contains('confirm')) return 'confirmed';
    if (value.contains('review')) return 'reviewing';
    if (value.contains('cancel')) return 'cancelled';
    if (value.contains('complete')) return 'completed';

    return 'new';
  }

  int _countAppointmentStatus(String status) {
    return _filteredAppointments
        .where(
          (appointment) => _normaliseAppointmentStatus(appointment) == status,
        )
        .length;
  }

  int _countCheckinStatus(String status) {
    return _filteredCheckins
        .where((checkin) => _normaliseCheckinStatus(checkin) == status)
        .length;
  }

  int _countAiStatus(String status) {
    return _filteredAiBookings
        .where((booking) => _normaliseAiStatus(booking) == status)
        .length;
  }

  int get _availableDoctors {
    return _doctors.where((doctor) {
      return doctor['is_active'] != false &&
          _normaliseDoctorStatus(doctor) == 'available';
    }).length;
  }

  int get _busyDoctors {
    return _doctors.where((doctor) {
      return doctor['is_active'] != false &&
          _normaliseDoctorStatus(doctor) == 'busy';
    }).length;
  }

  int get _activeDepartments {
    return _departments.where((department) {
      return department['is_active'] != false;
    }).length;
  }

  int get _todayAppointments {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));

    return _appointments.where((appointment) {
      final date = _dateForRecord(appointment);

      if (date == null) return false;

      return !date.isBefore(today) && date.isBefore(tomorrow);
    }).length;
  }

  int get _emergencyCount {
    final emergencyCheckins = _filteredCheckins.where((checkin) {
      return _normaliseCheckinStatus(checkin) == 'emergency';
    }).length;

    final emergencyAi = _filteredAiBookings.where((booking) {
      return _normaliseAiStatus(booking) == 'emergency';
    }).length;

    return emergencyCheckins + emergencyAi;
  }

  List<_BreakdownItem> get _appointmentBreakdown {
    return [
      _BreakdownItem(
        label: 'Pending',
        value: _countAppointmentStatus('pending'),
        color: warning,
      ),
      _BreakdownItem(
        label: 'Scheduled',
        value: _countAppointmentStatus('scheduled'),
        color: accent,
      ),
      _BreakdownItem(
        label: 'Confirmed',
        value: _countAppointmentStatus('confirmed'),
        color: success,
      ),
      _BreakdownItem(
        label: 'Checked In',
        value: _countAppointmentStatus('checked_in'),
        color: const Color(0xFF8B5CF6),
      ),
      _BreakdownItem(
        label: 'Completed',
        value: _countAppointmentStatus('completed'),
        color: primary,
      ),
      _BreakdownItem(
        label: 'Cancelled',
        value: _countAppointmentStatus('cancelled'),
        color: error,
      ),
      _BreakdownItem(
        label: 'No Show',
        value: _countAppointmentStatus('no_show'),
        color: const Color(0xFF64748B),
      ),
    ];
  }

  List<_BreakdownItem> get _checkinBreakdown {
    return [
      _BreakdownItem(
        label: 'Waiting',
        value: _countCheckinStatus('waiting'),
        color: warning,
      ),
      _BreakdownItem(
        label: 'Assigned',
        value: _countCheckinStatus('assigned'),
        color: accent,
      ),
      _BreakdownItem(
        label: 'Booked',
        value: _countCheckinStatus('booked'),
        color: success,
      ),
      _BreakdownItem(
        label: 'In Consultation',
        value: _countCheckinStatus('in_consultation'),
        color: primary,
      ),
      _BreakdownItem(
        label: 'Emergency',
        value: _countCheckinStatus('emergency'),
        color: error,
      ),
      _BreakdownItem(
        label: 'Completed',
        value: _countCheckinStatus('completed'),
        color: const Color(0xFF8B5CF6),
      ),
    ];
  }

  List<_BreakdownItem> get _aiBreakdown {
    return [
      _BreakdownItem(
        label: 'New',
        value: _countAiStatus('new'),
        color: warning,
      ),
      _BreakdownItem(
        label: 'Reviewing',
        value: _countAiStatus('reviewing'),
        color: accent,
      ),
      _BreakdownItem(
        label: 'Confirmed',
        value: _countAiStatus('confirmed'),
        color: success,
      ),
      _BreakdownItem(
        label: 'Emergency',
        value: _countAiStatus('emergency'),
        color: error,
      ),
      _BreakdownItem(
        label: 'Cancelled',
        value: _countAiStatus('cancelled'),
        color: const Color(0xFF64748B),
      ),
    ];
  }

  int _maxBreakdownValue(List<_BreakdownItem> items) {
    if (items.isEmpty) return 1;

    final max = items.map((item) => item.value).fold<int>(0, (
      previous,
      current,
    ) {
      return current > previous ? current : previous;
    });

    return max == 0 ? 1 : max;
  }

  List<_ReportAlert> get _operationalAlerts {
    final alerts = <_ReportAlert>[];

    final waiting = _countCheckinStatus('waiting');

    if (waiting > 0) {
      alerts.add(
        _ReportAlert(
          title: '$waiting patient(s) waiting at reception',
          description: 'Review QR check-ins and assign a department or doctor.',
          icon: Icons.hourglass_top_rounded,
          color: warning,
        ),
      );
    }

    final pendingAppointments = _countAppointmentStatus('pending');

    if (pendingAppointments > 0) {
      alerts.add(
        _ReportAlert(
          title: '$pendingAppointments pending appointment(s)',
          description:
              'Confirm, reschedule or assign a doctor before the patient arrives.',
          icon: Icons.pending_actions_rounded,
          color: accent,
        ),
      );
    }

    final aiRequests = _countAiStatus('new') + _countAiStatus('reviewing');

    if (aiRequests > 0) {
      alerts.add(
        _ReportAlert(
          title: '$aiRequests AI booking request(s) require review',
          description:
              'Hospital staff must confirm the final department, doctor and booking.',
          icon: Icons.auto_awesome_rounded,
          color: warning,
        ),
      );
    }

    if (_emergencyCount > 0) {
      alerts.add(
        _ReportAlert(
          title: '$_emergencyCount emergency escalation record(s)',
          description:
              'Emergency cases must be handled by trained hospital staff immediately.',
          icon: Icons.emergency_rounded,
          color: error,
        ),
      );
    }

    if (_availableDoctors == 0 && _doctors.isNotEmpty) {
      alerts.add(
        _ReportAlert(
          title: 'No doctors currently marked available',
          description:
              'Review doctor availability and duty status before new bookings.',
          icon: Icons.medical_services_rounded,
          color: error,
        ),
      );
    }

    if (alerts.isEmpty) {
      alerts.add(
        _ReportAlert(
          title: 'No urgent operational alerts',
          description:
              'The selected report period has no outstanding queue or booking warnings.',
          icon: Icons.check_circle_rounded,
          color: success,
        ),
      );
    }

    return alerts;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: background,
      body: SafeArea(
        child: RefreshIndicator(
          color: accent,
          onRefresh: _loadReports,
          child: _loading
              ? Center(child: CircularProgressIndicator(color: accent))
              : SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildHeader(),
                      const SizedBox(height: 22),
                      if (_error != null) _buildErrorBox(),
                      _buildDateRangeFilter(),
                      const SizedBox(height: 18),
                      _buildStats(),
                      const SizedBox(height: 22),
                      _buildOperationalAlerts(),
                      const SizedBox(height: 22),
                      _buildAppointmentReport(),
                      const SizedBox(height: 22),
                      _buildCheckinReport(),
                      const SizedBox(height: 22),
                      _buildAiReport(),
                      const SizedBox(height: 22),
                      _buildHospitalCapacity(),
                    ],
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        IconButton(
          tooltip: 'Back to hospital dashboard',
          onPressed: widget.onBack ?? () => Navigator.of(context).maybePop(),
          icon: Icon(Icons.arrow_back_rounded),
          color: primary,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Reports • $_hospitalName',
                style: TextStyle(
                  color: textDark,
                  fontSize: 27,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                'Live operational reporting from hospital records, appointments, check-ins and AI booking requests.',
                style: TextStyle(color: mutedText, fontSize: 14),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        OutlinedButton.icon(
          onPressed: _loadReports,
          icon: Icon(Icons.refresh_rounded),
          label: Text('Refresh'),
          style: OutlinedButton.styleFrom(
            foregroundColor: primary,
            side: BorderSide(color: Color(0xFFE2E8F0)),
          ),
        ),
      ],
    );
  }

  Widget _buildErrorBox() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 18),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: error.withValues(alpha: 0.18)),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline_rounded, color: error),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Some report data could not load. $_error',
              style: TextStyle(color: textDark, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDateRangeFilter() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.cBgSecondary,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: context.cDivider),
      ),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            'Report period:',
            style: TextStyle(color: textDark, fontWeight: FontWeight.w900),
          ),
          ...['All time', 'Today', 'Last 7 days', 'This month'].map(
            (range) => ChoiceChip(
              label: Text(range),
              selected: _dateRange == range,
              selectedColor: accent.withValues(alpha: 0.15),
              onSelected: (_) {
                setState(() {
                  _dateRange = range;
                });
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStats() {
    final stats = [
      _ReportStat(
        title: 'Patients',
        value: _patients.length.toString(),
        subtitle: 'Linked to this hospital',
        icon: Icons.people_alt_rounded,
        color: accent,
      ),
      _ReportStat(
        title: 'Appointments',
        value: _filteredAppointments.length.toString(),
        subtitle: _dateRange,
        icon: Icons.calendar_month_rounded,
        color: success,
      ),
      _ReportStat(
        title: 'QR Check-ins',
        value: _filteredCheckins.length.toString(),
        subtitle: _dateRange,
        icon: Icons.qr_code_scanner_rounded,
        color: warning,
      ),
      _ReportStat(
        title: 'AI Requests',
        value: _filteredAiBookings.length.toString(),
        subtitle: _dateRange,
        icon: Icons.auto_awesome_rounded,
        color: primary,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 1000;

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: stats.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: wide ? 4 : 2,
            mainAxisExtent: 205,
            crossAxisSpacing: 14,
            mainAxisSpacing: 14,
          ),
          itemBuilder: (context, index) {
            final stat = stats[index];

            return Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: context.cBgSecondary,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: context.cDivider),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    height: 42,
                    width: 42,
                    decoration: BoxDecoration(
                      color: stat.color.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(stat.icon, color: stat.color),
                  ),
                  const Spacer(),
                  Text(
                    stat.value,
                    style: TextStyle(
                      color: textDark,
                      fontSize: 25,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    stat.title,
                    style: TextStyle(
                      color: textDark,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    stat.subtitle,
                    style: TextStyle(color: mutedText, fontSize: 12),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildOperationalAlerts() {
    final alerts = _operationalAlerts;

    return _buildPanel(
      title: 'Operational Alerts',
      icon: Icons.notifications_active_rounded,
      child: Column(
        children: alerts.map((alert) {
          return Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: alert.color.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: alert.color.withValues(alpha: 0.20)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(alert.icon, color: alert.color),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        alert.title,
                        style: TextStyle(
                          color: textDark,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        alert.description,
                        style: TextStyle(color: mutedText, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildAppointmentReport() {
    final items = _appointmentBreakdown;
    final total = _filteredAppointments.length;

    return _buildPanel(
      title: 'Appointment Report',
      icon: Icons.event_note_rounded,
      trailing: Text(
        '$total total',
        style: TextStyle(color: mutedText, fontWeight: FontWeight.w800),
      ),
      child: Column(
        children: [
          ...items.map(
            (item) => _buildBreakdownRow(item, _maxBreakdownValue(items)),
          ),
          const SizedBox(height: 8),
          _buildSummaryLine(
            Icons.today_rounded,
            'Appointments scheduled today',
            _todayAppointments.toString(),
            accent,
          ),
        ],
      ),
    );
  }

  Widget _buildCheckinReport() {
    final items = _checkinBreakdown;
    final total = _filteredCheckins.length;

    return _buildPanel(
      title: 'Reception & QR Check-in Report',
      icon: Icons.qr_code_scanner_rounded,
      trailing: Text(
        '$total total',
        style: TextStyle(color: mutedText, fontWeight: FontWeight.w800),
      ),
      child: Column(
        children: items
            .map((item) => _buildBreakdownRow(item, _maxBreakdownValue(items)))
            .toList(),
      ),
    );
  }

  Widget _buildAiReport() {
    final items = _aiBreakdown;
    final total = _filteredAiBookings.length;

    return _buildPanel(
      title: 'AI Booking Queue Report',
      icon: Icons.auto_awesome_rounded,
      trailing: Text(
        '$total total',
        style: TextStyle(color: mutedText, fontWeight: FontWeight.w800),
      ),
      child: Column(
        children: items
            .map((item) => _buildBreakdownRow(item, _maxBreakdownValue(items)))
            .toList(),
      ),
    );
  }

  Widget _buildHospitalCapacity() {
    return _buildPanel(
      title: 'Hospital Capacity Overview',
      icon: Icons.local_hospital_rounded,
      child: Column(
        children: [
          _buildSummaryLine(
            Icons.medical_services_rounded,
            'Total doctors',
            _doctors.length.toString(),
            accent,
          ),
          _buildSummaryLine(
            Icons.check_circle_rounded,
            'Doctors available',
            _availableDoctors.toString(),
            success,
          ),
          _buildSummaryLine(
            Icons.hourglass_top_rounded,
            'Doctors busy',
            _busyDoctors.toString(),
            warning,
          ),
          _buildSummaryLine(
            Icons.account_tree_rounded,
            'Active departments',
            _activeDepartments.toString(),
            primary,
          ),
          _buildSummaryLine(
            Icons.emergency_rounded,
            'Emergency records in selected period',
            _emergencyCount.toString(),
            error,
          ),
        ],
      ),
    );
  }

  Widget _buildPanel({
    required String title,
    required IconData icon,
    required Widget child,
    Widget? trailing,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: context.cBgSecondary,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: context.cDivider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: accent),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: primary,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              if (trailing != null) trailing,
            ],
          ),
          const SizedBox(height: 18),
          child,
        ],
      ),
    );
  }

  Widget _buildBreakdownRow(_BreakdownItem item, int maximum) {
    final fraction = item.value / maximum;

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                height: 10,
                width: 10,
                decoration: BoxDecoration(
                  color: item.color,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  item.label,
                  style: TextStyle(
                    color: textDark,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                item.value.toString(),
                style: TextStyle(color: textDark, fontWeight: FontWeight.w900),
              ),
            ],
          ),
          const SizedBox(height: 7),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: fraction,
              minHeight: 8,
              backgroundColor: context.cDivider,
              valueColor: AlwaysStoppedAnimation<Color>(item.color),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryLine(
    IconData icon,
    String label,
    String value,
    Color color,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: context.cBgPrimary,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: TextStyle(color: textDark, fontWeight: FontWeight.w700),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 17,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _ReportStat {
  final String title;
  final String value;
  final String subtitle;
  final IconData icon;
  final Color color;

  const _ReportStat({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.icon,
    required this.color,
  });
}

class _BreakdownItem {
  final String label;
  final int value;
  final Color color;

  const _BreakdownItem({
    required this.label,
    required this.value,
    required this.color,
  });
}

class _ReportAlert {
  final String title;
  final String description;
  final IconData icon;
  final Color color;

  const _ReportAlert({
    required this.title,
    required this.description,
    required this.icon,
    required this.color,
  });
}
