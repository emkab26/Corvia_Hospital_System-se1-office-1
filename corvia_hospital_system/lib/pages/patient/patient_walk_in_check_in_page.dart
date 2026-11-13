import 'package:flutter/material.dart';

import '../../services/walk_in_qr_service.dart';
import '../../theme/app_theme.dart';

class PatientWalkInCheckInPage extends StatefulWidget {
  const PatientWalkInCheckInPage({
    super.key,
    required this.destination,
  });

  final WalkInQrDestination destination;

  @override
  State<PatientWalkInCheckInPage> createState() =>
      _PatientWalkInCheckInPageState();
}

class _PatientWalkInCheckInPageState extends State<PatientWalkInCheckInPage> {
  final WalkInQrService _service = WalkInQrService();
  final TextEditingController _reasonController = TextEditingController();

  WalkInDepartment? _department;
  String _doctorChoice = 'auto';
  WalkInQueueReceipt? _receipt;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    if (widget.destination.departments.length == 1) {
      _department = widget.destination.departments.first;
    }
  }

  List<WalkInDoctor> get _availableDoctors {
    final departmentId = _department?.id;
    if (departmentId == null) return const <WalkInDoctor>[];

    final doctors = widget.destination.doctors
        .where((doctor) => doctor.departmentId == departmentId)
        .toList()
      ..sort((first, second) {
        final queueComparison = first.queueLength.compareTo(second.queueLength);
        if (queueComparison != 0) return queueComparison;
        return first.name.toLowerCase().compareTo(second.name.toLowerCase());
      });
    return doctors;
  }

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _joinQueue() async {
    final department = _department;
    final reason = _reasonController.text.trim();

    if (department == null) {
      _snack('Select the department you need to visit.');
      return;
    }
    if (reason.length < 3) {
      _snack('Enter a short reason for your visit.');
      return;
    }

    setState(() => _saving = true);
    try {
      final receipt = await _service.joinQueue(
        token: widget.destination.token,
        departmentId: department.id,
        doctorId: _doctorChoice == 'auto' ? null : _doctorChoice,
        reason: reason,
      );
      if (!mounted) return;
      setState(() => _receipt = receipt);
    } catch (error) {
      if (!mounted) return;
      _snack(_friendlyError(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _friendlyError(Object error) {
    final value = error.toString().toLowerCase();
    if (value.contains('active check-in')) {
      return 'You already have an active check-in at this hospital today.';
    }
    if (value.contains('expired') ||
        value.contains('invalid') ||
        value.contains('inactive')) {
      return 'This reception QR is no longer active. Please ask Reception for the current code.';
    }
    if (value.contains('patient profile')) {
      return 'Your signed-in account is not linked to an active patient profile.';
    }
    if (value.contains('no active doctors')) {
      return 'No doctor is currently available for this department. Please select another department or speak to Reception.';
    }
    return 'Could not join the walk-in queue. Please try again or speak to Reception.';
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final receipt = _receipt;
    return Scaffold(
      backgroundColor: context.cBgPrimary,
      appBar: AppBar(title: const Text('Walk-in Check-in')),
      body: receipt == null ? _buildForm() : _buildReceipt(receipt),
    );
  }

  Widget _buildForm() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: context.cBgSecondary,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: CorviaColors.divider),
          ),
          child: Column(
            children: [
              Icon(Icons.local_hospital_rounded,
                  size: 42, color: CorviaColors.accent),
              const SizedBox(height: 12),
              Text(
                widget.destination.hospitalName,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: context.cTextPrimary,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Complete these details to join the reception walk-in queue.',
                textAlign: TextAlign.center,
                style: TextStyle(color: context.cTextSecondary),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        DropdownButtonFormField<WalkInDepartment>(
          initialValue: _department,
          decoration: const InputDecoration(
            labelText: 'Department',
            prefixIcon: Icon(Icons.apartment_rounded),
          ),
          items: widget.destination.departments
              .map(
                (department) => DropdownMenuItem(
                  value: department,
                  child: Text(department.name),
                ),
              )
              .toList(),
          onChanged: _saving
              ? null
              : (value) => setState(() {
                    _department = value;
                    _doctorChoice = 'auto';
                  }),
        ),
        const SizedBox(height: 16),
        if (_department != null) ...[
          DropdownButtonFormField<String>(
            key: ValueKey(_department!.id),
            initialValue: _doctorChoice,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Doctor',
              prefixIcon: Icon(Icons.medical_services_rounded),
            ),
            items: [
              const DropdownMenuItem<String>(
                value: 'auto',
                child: Text('Automatically assign shortest queue'),
              ),
              ..._availableDoctors.map(
                (doctor) => DropdownMenuItem<String>(
                  value: doctor.id,
                  child: Text(
                    '${doctor.name} (${doctor.queueLength} waiting)',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
            onChanged: _saving
                ? null
                : (value) => setState(() {
                      _doctorChoice = value ?? 'auto';
                    }),
          ),
          const SizedBox(height: 8),
          Text(
            _availableDoctors.isEmpty
                ? 'No active doctor is currently listed for this department.'
                : 'Choose a doctor or let Corvia assign the doctor with the shortest active queue.',
            style: TextStyle(
              color: _availableDoctors.isEmpty
                  ? Colors.orange
                  : context.cTextSecondary,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 16),
        ],
        TextField(
          controller: _reasonController,
          enabled: !_saving,
          minLines: 3,
          maxLines: 5,
          maxLength: 500,
          decoration: const InputDecoration(
            labelText: 'Reason for visit',
            hintText:
                'Briefly describe why you need to see a healthcare professional',
            alignLabelWithHint: true,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.red.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.emergency_rounded, color: Colors.red),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'If this is an emergency, do not wait in the normal queue. Tell Reception immediately.',
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: _saving ? null : _joinQueue,
          icon: _saving
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.groups_rounded),
          label: Text(_saving ? 'Joining Queue...' : 'Join Walk-in Queue'),
        ),
      ],
    );
  }

  Widget _buildReceipt(WalkInQueueReceipt receipt) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const Icon(Icons.check_circle_rounded,
                size: 76, color: Colors.green),
            const SizedBox(height: 16),
            Text(
              'You are in the queue',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: context.cTextPrimary,
                fontSize: 25,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(receipt.hospitalName,
                style: TextStyle(color: context.cTextSecondary)),
            const SizedBox(height: 24),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: context.cBgSecondary,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: CorviaColors.divider),
              ),
              child: Column(
                children: [
                  _receiptRow('Department', receipt.departmentName),
                  const Divider(height: 26),
                  _receiptRow('Doctor', receipt.doctorName),
                  const Divider(height: 26),
                  _receiptRow('Status', 'Waiting'),
                  if (receipt.queuePosition > 0) ...[
                    const Divider(height: 26),
                    _receiptRow('Approximate queue position',
                        '${receipt.queuePosition}'),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Please remain near Reception and listen for your name. Queue order can change when urgent patients require care.',
              textAlign: TextAlign.center,
              style: TextStyle(color: context.cTextSecondary, height: 1.4),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Done'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _receiptRow(String label, String value) {
    return Row(
      children: [
        Expanded(
            child:
                Text(label, style: TextStyle(color: context.cTextSecondary))),
        const SizedBox(width: 12),
        Text(value,
            style: TextStyle(
                color: context.cTextPrimary, fontWeight: FontWeight.w700)),
      ],
    );
  }
}
