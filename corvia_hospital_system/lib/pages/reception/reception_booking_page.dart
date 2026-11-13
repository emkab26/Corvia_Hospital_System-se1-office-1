import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../services/reception_service.dart';
import '../../theme/app_theme.dart';

class ReceptionBookingPage extends StatefulWidget {
  const ReceptionBookingPage({super.key});

  @override
  State<ReceptionBookingPage> createState() => _ReceptionBookingPageState();
}

class _ReceptionBookingPageState extends State<ReceptionBookingPage> {
  final ReceptionService _service = ReceptionService();

  final TextEditingController _patientSearchController =
      TextEditingController();

  final TextEditingController _reasonController = TextEditingController();

  Timer? _searchDebounce;

  List<ReceptionPatient> _patients = <ReceptionPatient>[];
  List<ReceptionDepartment> _departments = <ReceptionDepartment>[];
  List<ReceptionDoctor> _doctors = <ReceptionDoctor>[];
  List<ReceptionBusySlot> _busySlots = <ReceptionBusySlot>[];

  ReceptionPatient? _selectedPatient;
  ReceptionDepartment? _selectedDepartment;
  ReceptionDoctor? _selectedDoctor;

  DateTime _selectedDate = DateTime.now();
  DateTime? _selectedSlot;

  String _appointmentType = 'in-person';

  bool _loadingDepartments = true;
  bool _searchingPatients = false;
  bool _loadingDoctors = false;
  bool _loadingSlots = false;
  bool _saving = false;

  String? _error;

  @override
  void initState() {
    super.initState();
    _loadDepartments();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _patientSearchController.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _loadDepartments() async {
    setState(() {
      _loadingDepartments = true;
      _error = null;
    });

    try {
      final departments = await _service.loadDepartments();

      if (!mounted) {
        return;
      }

      setState(() {
        _departments = departments;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _error = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _loadingDepartments = false;
        });
      }
    }
  }

  void _onPatientSearchChanged(String value) {
    _searchDebounce?.cancel();

    if (value.trim().length < 2) {
      setState(() {
        _patients = <ReceptionPatient>[];
        _searchingPatients = false;
      });
      return;
    }

    _searchDebounce = Timer(
      const Duration(milliseconds: 350),
      () => _searchPatients(value),
    );
  }

  Future<void> _searchPatients(String value) async {
    final searchText = value.trim();

    if (searchText.length < 2) {
      return;
    }

    setState(() {
      _searchingPatients = true;
    });

    try {
      final patients = await _service.searchPatients(searchText);

      if (!mounted || _patientSearchController.text.trim() != searchText) {
        return;
      }

      setState(() {
        _patients = patients;
      });
    } catch (error) {
      _snack(_cleanError(error));
    } finally {
      if (mounted && _patientSearchController.text.trim() == searchText) {
        setState(() {
          _searchingPatients = false;
        });
      }
    }
  }

  Future<void> _selectDepartment(
    ReceptionDepartment? department,
  ) async {
    setState(() {
      _selectedDepartment = department;
      _selectedDoctor = null;
      _selectedSlot = null;
      _doctors = <ReceptionDoctor>[];
      _busySlots = <ReceptionBusySlot>[];
    });

    if (department == null) {
      return;
    }

    setState(() {
      _loadingDoctors = true;
    });

    try {
      final doctors = await _service.loadDoctors(department.id);

      if (!mounted || _selectedDepartment?.id != department.id) {
        return;
      }

      setState(() {
        _doctors = doctors;
      });
    } catch (error) {
      _snack(_cleanError(error));
    } finally {
      if (mounted) {
        setState(() {
          _loadingDoctors = false;
        });
      }
    }
  }

  Future<void> _selectDoctor(
    ReceptionDoctor? doctor,
  ) async {
    setState(() {
      _selectedDoctor = doctor;
      _selectedSlot = null;
      _busySlots = <ReceptionBusySlot>[];
    });

    if (doctor == null) {
      return;
    }

    await _loadBusySlots();
  }

  Future<void> _loadBusySlots() async {
    final doctor = _selectedDoctor;

    if (doctor == null) {
      return;
    }

    setState(() {
      _loadingSlots = true;
      _selectedSlot = null;
    });

    try {
      final busySlots = await _service.loadDoctorBusySlots(
        doctorId: doctor.id,
        day: _selectedDate,
      );

      if (!mounted || _selectedDoctor?.id != doctor.id) {
        return;
      }

      setState(() {
        _busySlots = busySlots;
      });
    } catch (error) {
      _snack(_cleanError(error));
    } finally {
      if (mounted) {
        setState(() {
          _loadingSlots = false;
        });
      }
    }
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();

    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(
        _selectedDate.year,
        _selectedDate.month,
        _selectedDate.day,
      ),
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year, now.month, now.day).add(
        const Duration(days: 60),
      ),
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
      _selectedSlot = null;
    });

    await _loadBusySlots();
  }

  List<DateTime> _availableSlots() {
    final doctor = _selectedDoctor;

    if (doctor == null) {
      return <DateTime>[];
    }

    if (!doctor.workingDays.contains(_selectedDate.weekday)) {
      return <DateTime>[];
    }

    final slots = <DateTime>[];

    var cursor = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
      doctor.workStartMinutes ~/ 60,
      doctor.workStartMinutes % 60,
    );

    final end = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
      doctor.workEndMinutes ~/ 60,
      doctor.workEndMinutes % 60,
    );

    while (cursor
            .add(Duration(minutes: doctor.slotDurationMinutes))
            .isAtSameMomentAs(end) ||
        cursor
            .add(Duration(minutes: doctor.slotDurationMinutes))
            .isBefore(end)) {
      if (!_isPast(cursor) && !_isBusy(cursor)) {
        slots.add(cursor);
      }

      cursor = cursor.add(
        Duration(minutes: doctor.slotDurationMinutes),
      );
    }

    return slots;
  }

  bool _isPast(DateTime slot) {
    return slot.isBefore(DateTime.now());
  }

  bool _isBusy(DateTime slot) {
    final doctor = _selectedDoctor;

    if (doctor == null) {
      return true;
    }

    final slotEnd = slot.add(
      Duration(minutes: doctor.slotDurationMinutes),
    );

    for (final busy in _busySlots) {
      if (slot.isBefore(busy.endTime) && slotEnd.isAfter(busy.startTime)) {
        return true;
      }
    }

    return false;
  }

  Future<void> _saveBooking() async {
    final patient = _selectedPatient;
    final department = _selectedDepartment;
    final doctor = _selectedDoctor;
    final slot = _selectedSlot;
    final reason = _reasonController.text.trim();

    if (patient == null) {
      _snack('Select a patient first.');
      return;
    }

    if (department == null) {
      _snack('Select a department first.');
      return;
    }

    if (doctor == null) {
      _snack('Select a doctor first.');
      return;
    }

    if (slot == null) {
      _snack('Select an available time slot first.');
      return;
    }

    if (reason.length < 3) {
      _snack('Enter a short reason for the appointment.');
      return;
    }

    setState(() {
      _saving = true;
    });

    try {
      await _service.createAppointment(
        patientId: patient.id,
        doctorId: doctor.id,
        departmentId: department.id,
        startTime: slot,
        durationMinutes: doctor.slotDurationMinutes,
        reason: reason,
        appointmentType: _appointmentType,
      );

      if (!mounted) {
        return;
      }

      _snack('Appointment booked successfully.');
      Navigator.of(context).pop(true);
    } catch (error) {
      _snack(_cleanError(error));
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
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
        title: const Text('Reception Booking'),
      ),
      body: _loadingDepartments
          ? const Center(
              child: CircularProgressIndicator(),
            )
          : _error != null
              ? _errorView()
              : SafeArea(
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      _sectionTitle('1. Select Patient'),
                      _patientSearch(),
                      const SizedBox(height: 18),
                      _sectionTitle('2. Select Department and Doctor'),
                      _departmentPicker(),
                      const SizedBox(height: 12),
                      _doctorPicker(),
                      const SizedBox(height: 18),
                      _sectionTitle('3. Select Date and Time'),
                      _datePicker(),
                      const SizedBox(height: 12),
                      _slotGrid(),
                      const SizedBox(height: 18),
                      _sectionTitle('4. Appointment Details'),
                      _appointmentTypePicker(),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _reasonController,
                        maxLines: 3,
                        enabled: !_saving,
                        decoration: const InputDecoration(
                          labelText: 'Reason for visit',
                          hintText: 'Example: Follow-up consultation',
                          prefixIcon: Icon(Icons.notes_rounded),
                          alignLabelWithHint: true,
                        ),
                      ),
                      const SizedBox(height: 24),
                      FilledButton.icon(
                        onPressed: _saving ? null : _saveBooking,
                        icon: _saving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.event_available_rounded),
                        label: Text(
                          _saving ? 'Booking...' : 'Confirm Booking',
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
    );
  }

  Widget _errorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          _cleanError(_error!),
          textAlign: TextAlign.center,
          style: TextStyle(
            color: context.cTextSecondary,
          ),
        ),
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        title,
        style: TextStyle(
          color: context.cTextPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _patientSearch() {
    return Column(
      children: [
        TextField(
          controller: _patientSearchController,
          onChanged: _onPatientSearchChanged,
          decoration: InputDecoration(
            hintText: 'Search name, surname, patient number, ID or phone',
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: _searchingPatients
                ? const Padding(
                    padding: EdgeInsets.all(14),
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : _patientSearchController.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear_rounded),
                        onPressed: () {
                          _patientSearchController.clear();

                          setState(() {
                            _patients = <ReceptionPatient>[];
                            _selectedPatient = null;
                          });
                        },
                      ),
          ),
        ),
        if (_selectedPatient != null) ...[
          const SizedBox(height: 10),
          _selectedPatientCard(_selectedPatient!),
        ],
        if (_patients.isNotEmpty && _selectedPatient == null) ...[
          const SizedBox(height: 10),
          ..._patients.map(_patientResultCard),
        ],
      ],
    );
  }

  Widget _patientResultCard(ReceptionPatient patient) {
    return Card(
      color: context.cBgSecondary,
      child: ListTile(
        leading: Icon(
          Icons.person_rounded,
          color: CorviaColors.accent,
        ),
        title: Text(
          patient.fullName,
          style: TextStyle(
            color: context.cTextPrimary,
            fontWeight: FontWeight.w800,
          ),
        ),
        subtitle: Text(
          patient.patientNumber,
          style: TextStyle(
            color: context.cTextSecondary,
          ),
        ),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () {
          setState(() {
            _selectedPatient = patient;
            _patients = <ReceptionPatient>[];
            _patientSearchController.text = patient.fullName;
          });
        },
      ),
    );
  }

  Widget _selectedPatientCard(ReceptionPatient patient) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.cBgSecondary,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(
          color: CorviaColors.accent.withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.verified_user_rounded,
            color: CorviaColors.accent,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '${patient.fullName}\n${patient.patientNumber}',
              style: TextStyle(
                color: context.cTextPrimary,
                height: 1.35,
              ),
            ),
          ),
          TextButton(
            onPressed: _saving
                ? null
                : () {
                    setState(() {
                      _selectedPatient = null;
                      _patientSearchController.clear();
                      _patients = <ReceptionPatient>[];
                    });
                  },
            child: const Text('Change'),
          ),
        ],
      ),
    );
  }

  Widget _departmentPicker() {
    return DropdownButtonFormField<ReceptionDepartment>(
      initialValue: _selectedDepartment,
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: 'Department',
        prefixIcon: Icon(Icons.local_hospital_rounded),
      ),
      items: _departments
          .map(
            (department) => DropdownMenuItem(
              value: department,
              child: Text(
                department.locationName.isEmpty
                    ? department.name
                    : '${department.name} • ${department.locationName}',
                overflow: TextOverflow.ellipsis,
              ),
            ),
          )
          .toList(),
      onChanged: _saving ? null : _selectDepartment,
    );
  }

  Widget _doctorPicker() {
    if (_loadingDoctors) {
      return const Padding(
        padding: EdgeInsets.all(18),
        child: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return DropdownButtonFormField<ReceptionDoctor>(
      initialValue: _selectedDoctor,
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: 'Doctor',
        prefixIcon: Icon(Icons.medical_services_rounded),
      ),
      items: _doctors
          .map(
            (doctor) => DropdownMenuItem(
              value: doctor,
              child: Text(
                '${doctor.name} • ${doctor.statusLabel}',
                overflow: TextOverflow.ellipsis,
              ),
            ),
          )
          .toList(),
      onChanged: _selectedDepartment == null || _saving ? null : _selectDoctor,
    );
  }

  Widget _datePicker() {
    final label = DateFormat('EEE, d MMM yyyy').format(_selectedDate);

    return InkWell(
      onTap: _saving ? null : _pickDate,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: context.cBgSecondary,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: CorviaColors.divider),
        ),
        child: Row(
          children: [
            Icon(
              Icons.calendar_today_rounded,
              color: CorviaColors.accent,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: context.cTextPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const Text('Change'),
          ],
        ),
      ),
    );
  }

  Widget _slotGrid() {
    final doctor = _selectedDoctor;

    if (doctor == null) {
      return Text(
        'Select a doctor to see available time slots.',
        style: TextStyle(color: context.cTextSecondary),
      );
    }

    if (_loadingSlots) {
      return const Padding(
        padding: EdgeInsets.all(22),
        child: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    final slots = _availableSlots();

    if (slots.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: context.cBgSecondary,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: CorviaColors.divider),
        ),
        child: Text(
          'No free slots for this doctor on this date.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: context.cTextSecondary,
          ),
        ),
      );
    }

    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: 2.3,
      children: [
        for (final slot in slots)
          InkWell(
            onTap: _saving
                ? null
                : () {
                    setState(() {
                      _selectedSlot = slot;
                    });
                  },
            borderRadius: BorderRadius.circular(11),
            child: Container(
              decoration: BoxDecoration(
                color: _selectedSlot == slot
                    ? CorviaColors.accent
                    : context.cBgSecondary,
                borderRadius: BorderRadius.circular(11),
                border: Border.all(
                  color: _selectedSlot == slot
                      ? CorviaColors.accent
                      : CorviaColors.divider,
                ),
              ),
              child: Center(
                child: Text(
                  DateFormat('HH:mm').format(slot),
                  style: TextStyle(
                    color: _selectedSlot == slot
                        ? Colors.white
                        : context.cTextPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _appointmentTypePicker() {
    return Row(
      children: [
        Expanded(
          child: ChoiceChip(
            label: const Text('In-person'),
            selected: _appointmentType == 'in-person',
            onSelected: _saving
                ? null
                : (_) {
                    setState(() {
                      _appointmentType = 'in-person';
                    });
                  },
          ),
        ),
        //Telehealth temp disabled due to  missing backend
        /* const SizedBox(width: 8),
        Expanded(
          child: ChoiceChip(
            label: const Text('Telehealth'),
            selected: _appointmentType == 'telehealth',
            onSelected: _saving
                ? null
                : (_) {
                    setState(() {
                      _appointmentType = 'telehealth';
                    });
                  },
          ),
        ), */
      ],
    );
  }
}
