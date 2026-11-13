import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../theme/app_theme.dart';

class DoctorAppointmentsPage extends StatefulWidget {
  /// Set to [true] when this page is pushed as a standalone route (e.g. from
  /// the dashboard "Schedule" card) so a back button is shown in the AppBar.
  /// Leave [false] (default) when embedded as a nav tab.
  const DoctorAppointmentsPage({super.key, this.showBackButton = false});

  final bool showBackButton;

  @override
  State<DoctorAppointmentsPage> createState() => _DoctorAppointmentsPageState();
}

class _DoctorAppointmentsPageState extends State<DoctorAppointmentsPage> {
  final SupabaseClient _supabase = Supabase.instance.client;

  bool _loading = true;
  bool _updating = false;
  String? _error;

  List<Map<String, dynamic>> _appointments = [];
  Map<String, Map<String, dynamic>> _patientsById = {};

  String _filter = 'All';

  @override
  void initState() {
    super.initState();
    _loadAppointments();
  }

  Future<void> _refresh() async {
    await _loadAppointments();
  }

  Future<void> _loadAppointments() async {
    if (!mounted) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final user = _supabase.auth.currentUser;

      if (user == null) {
        throw StateError('You are not logged in.');
      }

      final doctorRow = await _supabase
          .from('doctors')
          .select('id')
          .eq('profile_id', user.id)
          .maybeSingle();

      if (doctorRow == null) {
        throw StateError(
          'Doctor profile not found. Please make sure this account is linked to a doctor record.',
        );
      }

      final doctorId = doctorRow['id']?.toString();

      if (doctorId == null || doctorId.isEmpty) {
        throw StateError('Doctor profile has no valid doctor ID.');
      }

      final appointmentResponse = await _supabase
          .from('appointments')
          .select(
            'id, doctor_id, patient_id, appointment_date, duration_minutes, reason, status, type, notes, created_at, updated_at',
          )
          .eq('doctor_id', doctorId)
          .order('appointment_date', ascending: false);

      final appointments = List<Map<String, dynamic>>.from(
        appointmentResponse as List,
      );

      final patientIds = appointments
          .map((appointment) => appointment['patient_id']?.toString())
          .whereType<String>()
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList();

      final patientsById = <String, Map<String, dynamic>>{};

      if (patientIds.isNotEmpty) {
        try {
          final patientResponse = await _supabase
              .from('patients')
              .select(
                'id, first_name, surname, email, phone, date_of_birth',
              )
              .inFilter('id', patientIds);

          for (final patient in List<Map<String, dynamic>>.from(
            patientResponse as List,
          )) {
            final patientId = patient['id']?.toString();

            if (patientId != null && patientId.isNotEmpty) {
              patientsById[patientId] = patient;
            }
          }
        } catch (e) {
          debugPrint('Could not load patient details: $e');
        }
      }

      if (!mounted) return;

      setState(() {
        _appointments = appointments;
        _patientsById = patientsById;
        _loading = false;
      });
    } catch (e) {
      debugPrint('Doctor appointments load failed: $e');

      if (!mounted) return;

      setState(() {
        _loading = false;
        _error = _friendlyError(e);
      });
    }
  }

  String _friendlyError(Object error) {
    final message = error.toString();

    if (message.contains('infinite recursion')) {
      return 'Appointments database permissions still have a recursion problem. Run the appointments RLS SQL fix in Supabase.';
    }

    if (message.contains('Doctor profile not found')) {
      return 'Doctor profile not found for this login account.';
    }

    if (message.contains('not logged in')) {
      return 'You are not logged in.';
    }

    return message.replaceFirst('Exception: ', '');
  }

  List<Map<String, dynamic>> get _filteredAppointments {
    if (_filter == 'All') {
      return _appointments;
    }

    return _appointments.where((appointment) {
      final status = _normaliseStatus(
        appointment['status']?.toString() ?? '',
      );

      return status == _normaliseStatus(_filter);
    }).toList();
  }

  String _normaliseStatus(String value) {
    return value.trim().toLowerCase().replaceAll('_', ' ');
  }

  String _statusLabel(String? rawStatus) {
    final status = _normaliseStatus(rawStatus ?? '');

    if (status.isEmpty) {
      return 'Pending';
    }

    return status
        .split(' ')
        .map(
          (word) => word.isEmpty
              ? ''
              : '${word[0].toUpperCase()}${word.substring(1)}',
        )
        .join(' ');
  }

  Color _statusColor(String? rawStatus) {
    final status = _normaliseStatus(rawStatus ?? '');

    switch (status) {
      case 'confirmed':
        return Colors.blue;
      case 'checked in':
      case 'checked_in':
        return Colors.deepPurple;
      case 'completed':
        return Colors.green;
      case 'cancelled':
        return Colors.red;
      case 'no show':
      case 'no_show':
        return Colors.orange;
      default:
        return Colors.amber.shade800;
    }
  }

  IconData _statusIcon(String? rawStatus) {
    final status = _normaliseStatus(rawStatus ?? '');

    switch (status) {
      case 'confirmed':
        return Icons.event_available_outlined;
      case 'checked in':
      case 'checked_in':
        return Icons.login_outlined;
      case 'completed':
        return Icons.task_alt_outlined;
      case 'cancelled':
        return Icons.cancel_outlined;
      case 'no show':
      case 'no_show':
        return Icons.person_off_outlined;
      default:
        return Icons.schedule_outlined;
    }
  }

  String _patientName(Map<String, dynamic> appointment) {
    final patientId = appointment['patient_id']?.toString();
    final patient = patientId == null ? null : _patientsById[patientId];

    if (patient == null) {
      return 'Patient details unavailable';
    }

    final firstName = patient['first_name']?.toString().trim() ?? '';
    final surname = patient['surname']?.toString().trim() ?? '';

    final name = '$firstName $surname'.trim();

    return name.isEmpty ? 'Unnamed patient' : name;
  }

  String _patientContact(Map<String, dynamic> appointment) {
    final patientId = appointment['patient_id']?.toString();
    final patient = patientId == null ? null : _patientsById[patientId];

    if (patient == null) {
      return 'Patient ID: ${patientId ?? 'Unknown'}';
    }

    final email = patient['email']?.toString().trim() ?? '';
    final phone = patient['phone']?.toString().trim() ?? '';

    if (email.isNotEmpty) {
      return email;
    }

    if (phone.isNotEmpty) {
      return phone;
    }

    return 'No contact information';
  }

  DateTime? _appointmentDate(Map<String, dynamic> appointment) {
    final rawDate = appointment['appointment_date']?.toString();

    if (rawDate == null || rawDate.isEmpty) {
      return null;
    }

    return DateTime.tryParse(rawDate)?.toLocal();
  }

  Future<void> _showAppointmentActions(
    Map<String, dynamic> appointment,
  ) async {
    final status = _statusLabel(
      appointment['status']?.toString(),
    );

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.cBgSecondary,
      isScrollControlled: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _patientName(appointment),
                  style: TextStyle(
                    color: context.cTextPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Current status: $status',
                  style: TextStyle(
                    color: context.cTextSecondary,
                  ),
                ),
                const SizedBox(height: 20),
                ListTile(
                  leading: const Icon(Icons.edit_note_outlined),
                  title: const Text('Add or edit doctor notes'),
                  onTap: () async {
                    Navigator.pop(sheetContext);
                    await _showDoctorNotesDialog(appointment);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.sync_alt_outlined),
                  title: const Text('Change appointment status'),
                  onTap: () async {
                    Navigator.pop(sheetContext);
                    await _showStatusDialog(appointment);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showDoctorNotesDialog(
    Map<String, dynamic> appointment,
  ) async {
    final notesController = TextEditingController(
      text: appointment['notes']?.toString() ?? '',
    );

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: context.cBgSecondary,
          title: Text(
            'Doctor Notes',
            style: TextStyle(
              color: context.cTextPrimary,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: SizedBox(
            width: 520,
            child: TextField(
              controller: notesController,
              maxLines: 7,
              minLines: 4,
              style: TextStyle(
                color: context.cTextPrimary,
              ),
              decoration: InputDecoration(
                labelText: 'Clinical notes',
                hintText: 'Add appointment notes for this patient.',
                labelStyle: TextStyle(
                  color: context.cTextSecondary,
                ),
                floatingLabelStyle: TextStyle(
                  color: CorviaColors.accent,
                ),
                alignLabelWithHint: true,
                border: const OutlineInputBorder(),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed:
                  _updating ? null : () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton.icon(
              onPressed: _updating
                  ? null
                  : () async {
                      final success = await _saveDoctorNotes(
                        appointmentId: appointment['id'].toString(),
                        notes: notesController.text.trim(),
                      );

                      if (!dialogContext.mounted || !success) {
                        return;
                      }

                      Navigator.pop(dialogContext, true);
                    },
              icon: _updating
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.save_outlined),
              label: Text(_updating ? 'Saving...' : 'Save Notes'),
            ),
          ],
        );
      },
    );

    notesController.dispose();

    if (saved == true) {
      _showMessage('Doctor notes saved.');
    }
  }

  Future<bool> _saveDoctorNotes({
    required String appointmentId,
    required String notes,
  }) async {
    if (appointmentId.isEmpty) {
      _showMessage('Appointment ID is missing.', isError: true);
      return false;
    }

    setState(() {
      _updating = true;
    });

    try {
      final updated = await _supabase
          .from('appointments')
          .update({
            'notes': notes.isEmpty ? null : notes,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', appointmentId)
          .select(
            'id, doctor_id, patient_id, appointment_date, duration_minutes, reason, status, type, notes, created_at, updated_at',
          )
          .single();

      if (!mounted) return false;

      final updatedAppointment = Map<String, dynamic>.from(updated);

      setState(() {
        final index = _appointments.indexWhere(
          (appointment) => appointment['id']?.toString() == appointmentId,
        );

        if (index != -1) {
          _appointments[index] = updatedAppointment;
        }
      });

      return true;
    } on PostgrestException catch (e) {
      _showMessage(
        'Could not save doctor notes: ${e.message}',
        isError: true,
      );
      return false;
    } catch (e) {
      _showMessage(
        'Could not save doctor notes: $e',
        isError: true,
      );
      return false;
    } finally {
      if (mounted) {
        setState(() {
          _updating = false;
        });
      }
    }
  }

  Future<void> _showStatusDialog(
    Map<String, dynamic> appointment,
  ) async {
    String selectedStatus = _normaliseStatus(
      appointment['status']?.toString() ?? 'pending',
    );

    const statuses = <String>[
      'pending',
      'confirmed',
      'checked in',
      'completed',
      'cancelled',
      'no show',
    ];

    if (!statuses.contains(selectedStatus)) {
      selectedStatus = 'pending';
    }

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: context.cBgSecondary,
              title: Text(
                'Change Appointment Status',
                style: TextStyle(
                  color: context.cTextPrimary,
                  fontWeight: FontWeight.bold,
                ),
              ),
              content: SizedBox(
                width: 440,
                child: DropdownButtonFormField<String>(
                  initialValue: selectedStatus,
                  isExpanded: true,
                  dropdownColor: context.cBgSecondary,
                  style: TextStyle(
                    color: context.cTextPrimary,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Status',
                    labelStyle: TextStyle(
                      color: context.cTextSecondary,
                    ),
                    border: const OutlineInputBorder(),
                  ),
                  items: statuses
                      .map(
                        (status) => DropdownMenuItem<String>(
                          value: status,
                          child: Text(_statusLabel(status)),
                        ),
                      )
                      .toList(),
                  onChanged: _updating
                      ? null
                      : (value) {
                          if (value == null) return;

                          setDialogState(() {
                            selectedStatus = value;
                          });
                        },
                ),
              ),
              actions: [
                TextButton(
                  onPressed: _updating
                      ? null
                      : () => Navigator.pop(dialogContext, false),
                  child: const Text('Cancel'),
                ),
                ElevatedButton.icon(
                  onPressed: _updating
                      ? null
                      : () async {
                          final success = await _updateAppointmentStatus(
                            appointmentId: appointment['id'].toString(),
                            newStatus: selectedStatus,
                          );

                          if (!dialogContext.mounted || !success) {
                            return;
                          }

                          Navigator.pop(dialogContext, true);
                        },
                  icon: _updating
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.check_circle_outline),
                  label: Text(_updating ? 'Updating...' : 'Update Status'),
                ),
              ],
            );
          },
        );
      },
    );

    if (saved == true) {
      _showMessage('Appointment status updated.');
    }
  }

  Future<bool> _updateAppointmentStatus({
    required String appointmentId,
    required String newStatus,
  }) async {
    if (appointmentId.isEmpty) {
      _showMessage('Appointment ID is missing.', isError: true);
      return false;
    }

    setState(() {
      _updating = true;
    });

    try {
      final updated = await _supabase
          .from('appointments')
          .update({
            'status': newStatus,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', appointmentId)
          .select(
            'id, doctor_id, patient_id, appointment_date, duration_minutes, reason, status, type, notes, created_at, updated_at',
          )
          .single();

      if (!mounted) return false;

      final updatedAppointment = Map<String, dynamic>.from(updated);

      setState(() {
        final index = _appointments.indexWhere(
          (appointment) => appointment['id']?.toString() == appointmentId,
        );

        if (index != -1) {
          _appointments[index] = updatedAppointment;
        }
      });

      return true;
    } on PostgrestException catch (e) {
      _showMessage(
        'Could not update appointment status: ${e.message}',
        isError: true,
      );
      return false;
    } catch (e) {
      _showMessage(
        'Could not update appointment status: $e',
        isError: true,
      );
      return false;
    } finally {
      if (mounted) {
        setState(() {
          _updating = false;
        });
      }
    }
  }

  void _showMessage(
    String message, {
    bool isError = false,
  }) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: isError ? Colors.red.shade700 : null,
        content: Text(message),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final appointments = _filteredAppointments;

    return Scaffold(
      backgroundColor: context.cBgPrimary,
      appBar: AppBar(
        title: const Text('Appointments'),
        leading: widget.showBackButton
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                tooltip: 'Back',
                onPressed: () => Navigator.pop(context),
              )
            : null,
        actions: [
          IconButton(
            onPressed: _loading ? null : _refresh,
            tooltip: 'Refresh appointments',
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? Center(
              child: CircularProgressIndicator(
                color: CorviaColors.accent,
              ),
            )
          : _error != null
              ? _buildErrorState()
              : RefreshIndicator(
                  onRefresh: _refresh,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    children: [
                      Text(
                        'My Appointments',
                        style: TextStyle(
                          color: context.cTextPrimary,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Manage appointments, doctor notes, and patient status.',
                        style: TextStyle(
                          color: context.cTextSecondary,
                        ),
                      ),
                      const SizedBox(height: 18),
                      _buildFilterChips(),
                      const SizedBox(height: 18),
                      if (appointments.isEmpty)
                        _buildEmptyState()
                      else
                        ...appointments.map(
                          (appointment) => Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _buildAppointmentCard(appointment),
                          ),
                        ),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
    );
  }

  Widget _buildFilterChips() {
    const filters = <String>[
      'All',
      'Pending',
      'Confirmed',
      'Checked In',
      'Completed',
      'Cancelled',
    ];

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: filters.map((filter) {
        final selected = _filter == filter;

        return ChoiceChip(
          label: Text(filter),
          selected: selected,
          selectedColor: CorviaColors.accent.withValues(alpha: 0.2),
          labelStyle: TextStyle(
            color: selected ? CorviaColors.accent : context.cTextSecondary,
            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
          ),
          onSelected: (_) {
            setState(() {
              _filter = filter;
            });
          },
        );
      }).toList(),
    );
  }

  Widget _buildAppointmentCard(
    Map<String, dynamic> appointment,
  ) {
    final date = _appointmentDate(appointment);
    final status = appointment['status']?.toString() ?? 'pending';
    final reason = appointment['reason']?.toString().trim() ?? '';
    final type = appointment['type']?.toString().trim() ?? '';
    final notes = appointment['notes']?.toString().trim() ?? '';
    final duration = appointment['duration_minutes']?.toString();

    return Card(
      color: context.cBgSecondary,
      elevation: 1,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _showAppointmentActions(appointment),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      backgroundColor:
                          _statusColor(status).withValues(alpha: 0.14),
                      child: Icon(
                        _statusIcon(status),
                        color: _statusColor(status),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _patientName(appointment),
                        style: TextStyle(
                          color: context.cTextPrimary,
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    _buildStatusBadge(status),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  _patientContact(appointment),
                  style: TextStyle(
                    color: context.cTextSecondary,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 12),
                _buildDetailRow(
                  icon: Icons.calendar_today_outlined,
                  label: date == null
                      ? 'Appointment date unavailable'
                      : DateFormat('EEE, d MMM yyyy • HH:mm').format(date),
                ),
                if (duration != null && duration.isNotEmpty)
                  _buildDetailRow(
                    icon: Icons.timer_outlined,
                    label: '$duration minutes',
                  ),
                if (type.isNotEmpty)
                  _buildDetailRow(
                    icon: Icons.medical_services_outlined,
                    label: type,
                  ),
                if (reason.isNotEmpty)
                  _buildDetailRow(
                    icon: Icons.info_outline,
                    label: reason,
                  ),
                if (notes.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: context.cBgPrimary,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      notes,
                      style: TextStyle(
                        color: context.cTextSecondary,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _showDoctorNotesDialog(appointment),
                        icon: const Icon(Icons.edit_note_outlined),
                        label: Text(
                          notes.isEmpty ? 'Add Notes' : 'Edit Notes',
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => _showStatusDialog(appointment),
                        icon: const Icon(Icons.sync_alt_outlined),
                        label: const Text('Status'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatusBadge(String status) {
    final color = _statusColor(status);

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        _statusLabel(status),
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildDetailRow({
    required IconData icon,
    required String label,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: 7),
      child: Row(
        children: [
          Icon(
            icon,
            size: 17,
            color: context.cTextSecondary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: context.cTextSecondary,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(28),
        children: [
          const SizedBox(height: 80),
          Icon(
            Icons.error_outline,
            size: 58,
            color: Colors.red.shade400,
          ),
          const SizedBox(height: 16),
          Text(
            'Could not load appointments',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: context.cTextPrimary,
              fontSize: 19,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _error ?? 'Unknown error',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: context.cTextSecondary,
            ),
          ),
          const SizedBox(height: 22),
          Center(
            child: ElevatedButton.icon(
              onPressed: _refresh,
              icon: const Icon(Icons.refresh),
              label: const Text('Try Again'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Card(
      color: context.cBgSecondary,
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          children: [
            Icon(
              Icons.event_busy_outlined,
              size: 52,
              color: context.cTextSecondary,
            ),
            const SizedBox(height: 12),
            Text(
              'No appointments found',
              style: TextStyle(
                color: context.cTextPrimary,
                fontSize: 17,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _filter == 'All'
                  ? 'You do not have any appointments yet.'
                  : 'No $_filter appointments found.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: context.cTextSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
