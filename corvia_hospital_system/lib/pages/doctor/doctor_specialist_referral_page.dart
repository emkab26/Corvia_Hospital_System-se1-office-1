import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../theme/app_theme.dart';

class DoctorSpecialistReferralPage extends StatefulWidget {
  const DoctorSpecialistReferralPage({
    super.key,
    required this.doctorId,
  });

  final String doctorId;

  @override
  State<DoctorSpecialistReferralPage> createState() =>
      _DoctorSpecialistReferralPageState();
}

class _DoctorSpecialistReferralPageState
    extends State<DoctorSpecialistReferralPage> {
  static const Duration _requestTimeout = Duration(seconds: 20);

  static const List<String> _specialties = <String>[
    'Cardiologist',
    'Neurologist',
    'Dermatologist',
    'Orthopaedic Specialist',
    'Gynaecologist',
    'Paediatric Specialist',
    'Psychiatrist',
    'Oncologist',
    'Endocrinologist',
    'Gastroenterologist',
    'Nephrologist',
    'Pulmonologist',
    'Rheumatologist',
    'Urologist',
    'Ophthalmologist',
    'ENT Specialist',
    'General Surgeon',
    'Other',
  ];

  static const List<String> _urgencies = <String>[
    'routine',
    'priority',
    'urgent',
    'emergency',
  ];

  final SupabaseClient _supabase = Supabase.instance.client;

  final TextEditingController _otherSpecialtyController =
      TextEditingController();
  final TextEditingController _reasonController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();

  List<_ReferralPatient> _patients = <_ReferralPatient>[];
  List<_HospitalOption> _hospitals = <_HospitalOption>[];
  List<_ReferralRecord> _recentReferrals = <_ReferralRecord>[];

  String? _selectedPatientId;
  String? _selectedHospitalId;

  String _selectedSpecialty = _specialties.first;
  String _selectedUrgency = 'routine';

  DateTime _selectedDate = DateTime.now().add(
    const Duration(days: 1),
  );

  TimeOfDay _selectedTime = const TimeOfDay(
    hour: 9,
    minute: 0,
  );

  bool _loading = true;
  bool _saving = false;
  bool _refreshingReferrals = false;
  bool _usePreferredDate = true;

  String? _error;

  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    _loadPage();
  }

  @override
  void dispose() {
    _otherSpecialtyController.dispose();
    _reasonController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  String get _resolvedSpecialty {
    if (_selectedSpecialty == 'Other') {
      return _otherSpecialtyController.text.trim();
    }

    return _selectedSpecialty.trim();
  }

  Future<void> _loadPage() async {
    final generation = ++_loadGeneration;

    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      if (widget.doctorId.trim().isEmpty) {
        throw Exception('No valid doctor record was supplied.');
      }

      final results = await Future.wait<dynamic>([
        _loadPatients(),
        _loadHospitals(),
        _loadRecentReferrals(),
      ]);

      if (!mounted || generation != _loadGeneration) {
        return;
      }

      final patients = results[0] as List<_ReferralPatient>;
      final hospitals = results[1] as List<_HospitalOption>;
      final referrals = results[2] as List<_ReferralRecord>;

      setState(() {
        _patients = patients;
        _hospitals = hospitals;
        _recentReferrals = referrals;

        if (_selectedPatientId == null && patients.isNotEmpty) {
          _selectedPatientId = patients.first.id;
        }

        if (_selectedHospitalId == null && hospitals.isNotEmpty) {
          _selectedHospitalId = hospitals.first.id;
        }
      });
    } on TimeoutException {
      if (!mounted || generation != _loadGeneration) {
        return;
      }

      setState(() {
        _error = 'The server took too long to load the referral page.';
      });
    } catch (error, stackTrace) {
      debugPrint(
        'Doctor specialist referral load failed: $error\n$stackTrace',
      );

      if (!mounted || generation != _loadGeneration) {
        return;
      }

      setState(() {
        _error = _friendlyError(error);
      });
    } finally {
      if (mounted && generation == _loadGeneration) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _refreshReferralsOnly() async {
    if (_refreshingReferrals) {
      return;
    }

    setState(() {
      _refreshingReferrals = true;
    });

    try {
      final referrals = await _loadRecentReferrals();

      if (!mounted) {
        return;
      }

      setState(() {
        _recentReferrals = referrals;
      });
    } on TimeoutException {
      _showMessage(
        'The server took too long to refresh referrals.',
        isError: true,
      );
    } catch (error) {
      _showMessage(
        _friendlyError(error),
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          _refreshingReferrals = false;
        });
      }
    }
  }

  Future<List<_ReferralPatient>> _loadPatients() async {
    final results = await Future.wait<dynamic>([
      _supabase
          .from('appointments')
          .select('patient_id')
          .eq('doctor_id', widget.doctorId)
          .timeout(_requestTimeout),
      _supabase
          .from('prescriptions')
          .select('patient_id')
          .eq('doctor_id', widget.doctorId)
          .timeout(_requestTimeout),
    ]);

    final appointmentRows = _rows(results[0]);
    final prescriptionRows = _rows(results[1]);

    final patientIds = <String>{
      for (final row in appointmentRows)
        if (_cleanId(row['patient_id']) != null) _cleanId(row['patient_id'])!,
      for (final row in prescriptionRows)
        if (_cleanId(row['patient_id']) != null) _cleanId(row['patient_id'])!,
    };

    if (patientIds.isEmpty) {
      return <_ReferralPatient>[];
    }

    final patientResponse = await _supabase
        .from('patients')
        .select()
        .inFilter(
          'id',
          patientIds.toList(),
        )
        .timeout(_requestTimeout);

    final patientRows = _rows(patientResponse);

    final profileIds = <String>{
      for (final row in patientRows)
        if (_cleanId(row['profile_id']) != null) _cleanId(row['profile_id'])!,
    };

    final profiles = await _loadProfiles(profileIds);

    final patients = <_ReferralPatient>[];

    for (final row in patientRows) {
      final patientId = _cleanId(row['id']);

      if (patientId == null) {
        continue;
      }

      final profileId = _cleanId(row['profile_id']);
      final profile = profileId == null ? null : profiles[profileId];

      final firstName = _firstText(
        <dynamic>[
          profile?['first_name'],
          row['first_name'],
          profile?['name'],
          row['name'],
        ],
        fallback: '',
      );

      final surname = _firstText(
        <dynamic>[
          profile?['surname'],
          profile?['last_name'],
          row['surname'],
          row['last_name'],
        ],
        fallback: '',
      );

      final fullName = '$firstName $surname'.trim();

      final dateOfBirth = DateTime.tryParse(
        row['date_of_birth']?.toString() ?? '',
      );

      patients.add(
        _ReferralPatient(
          id: patientId,
          name: fullName.isEmpty ? 'Unknown Patient' : fullName,
          patientNumber: _firstText(
            <dynamic>[
              row['patient_number'],
              row['medical_record_number'],
              row['patient_no'],
              row['id_number'],
            ],
            fallback: 'Patient number unavailable',
          ),
          age: dateOfBirth == null ? null : _calculateAge(dateOfBirth),
          gender: _firstText(
            <dynamic>[
              row['gender'],
            ],
            fallback: 'Unknown',
          ),
        ),
      );
    }

    patients.sort(
      (first, second) => first.name.toLowerCase().compareTo(
            second.name.toLowerCase(),
          ),
    );

    return patients;
  }

  Future<Map<String, Map<String, dynamic>>> _loadProfiles(
    Set<String> profileIds,
  ) async {
    if (profileIds.isEmpty) {
      return <String, Map<String, dynamic>>{};
    }

    final result = <String, Map<String, dynamic>>{};

    try {
      final byIdResponse = await _supabase
          .from('profiles')
          .select()
          .inFilter(
            'id',
            profileIds.toList(),
          )
          .timeout(_requestTimeout);

      for (final row in _rows(byIdResponse)) {
        final id = _cleanId(row['id']);
        final userId = _cleanId(row['user_id']);

        if (id != null) {
          result[id] = row;
        }

        if (userId != null) {
          result[userId] = row;
        }
      }
    } catch (error) {
      debugPrint('Could not load profiles by id: $error');
    }

    try {
      final byUserResponse = await _supabase
          .from('profiles')
          .select()
          .inFilter(
            'user_id',
            profileIds.toList(),
          )
          .timeout(_requestTimeout);

      for (final row in _rows(byUserResponse)) {
        final id = _cleanId(row['id']);
        final userId = _cleanId(row['user_id']);

        if (id != null) {
          result[id] = row;
        }

        if (userId != null) {
          result[userId] = row;
        }
      }
    } catch (error) {
      debugPrint('Could not load profiles by user_id: $error');
    }

    return result;
  }

  Future<List<_HospitalOption>> _loadHospitals() async {
    try {
      final response =
          await _supabase.from('hospitals').select().timeout(_requestTimeout);

      final hospitals = <_HospitalOption>[];

      for (final row in _rows(response)) {
        final id = _cleanId(row['id']);

        if (id == null) {
          continue;
        }

        hospitals.add(
          _HospitalOption(
            id: id,
            name: _firstText(
              <dynamic>[
                row['name'],
                row['hospital_name'],
                row['display_name'],
              ],
              fallback: 'Hospital',
            ),
          ),
        );
      }

      hospitals.sort(
        (first, second) => first.name.toLowerCase().compareTo(
              second.name.toLowerCase(),
            ),
      );

      return hospitals;
    } catch (error) {
      debugPrint('Could not load hospitals: $error');
      return <_HospitalOption>[];
    }
  }

  Future<List<_ReferralRecord>> _loadRecentReferrals() async {
    final response = await _supabase
        .from('specialist_requests')
        .select()
        .eq(
          'referring_doctor_id',
          widget.doctorId,
        )
        .order(
          'created_at',
          ascending: false,
        )
        .limit(30)
        .timeout(_requestTimeout);

    final rows = _rows(response);

    final patientIds = <String>{
      for (final row in rows)
        if (_cleanId(row['patient_id']) != null) _cleanId(row['patient_id'])!,
    };

    final assignedDoctorIds = <String>{
      for (final row in rows)
        if (_cleanId(row['assigned_doctor_id']) != null)
          _cleanId(row['assigned_doctor_id'])!,
    };

    final patientNames = await _loadPatientNames(patientIds);
    final doctorNames = await _loadDoctorNames(assignedDoctorIds);

    return rows.map(
      (row) {
        final patientId = _cleanId(row['patient_id']) ?? '';
        final assignedDoctorId = _cleanId(row['assigned_doctor_id']);

        return _ReferralRecord(
          id: _cleanId(row['id']) ?? '',
          patientName: patientNames[patientId] ?? 'Patient',
          specialty: _firstText(
            <dynamic>[
              row['requested_specialty'],
              row['specialty'],
            ],
            fallback: 'Specialist',
          ),
          urgency: _canonicalValue(
            row['urgency'],
            fallback: 'routine',
          ),
          status: _canonicalValue(
            row['status'],
            fallback: 'pending',
          ),
          referralStatus: _canonicalValue(
            row['referral_status'],
            fallback: 'not_provided',
          ),
          reason: _firstText(
            <dynamic>[
              row['reason'],
            ],
            fallback: 'No reason supplied.',
          ),
          createdAt: _parseDate(
            row['created_at'],
          ),
          preferredAt: _parseDate(
            row['preferred_appointment_at'],
          ),
          finalAt: _parseDate(
            row['final_appointment_at'],
          ),
          assignedDoctorId: assignedDoctorId,
          assignedDoctorName:
              assignedDoctorId == null ? null : doctorNames[assignedDoctorId],
          appointmentId: _cleanId(
            row['appointment_id'],
          ),
          receptionNotes: _nullableText(
            row['reception_notes'],
          ),
          rejectionReason: _nullableText(
            row['rejection_reason'],
          ),
        );
      },
    ).toList();
  }

  Future<Map<String, String>> _loadPatientNames(
    Set<String> patientIds,
  ) async {
    if (patientIds.isEmpty) {
      return <String, String>{};
    }

    try {
      final response = await _supabase
          .from('patients')
          .select()
          .inFilter(
            'id',
            patientIds.toList(),
          )
          .timeout(_requestTimeout);

      final rows = _rows(response);

      final profileIds = <String>{
        for (final row in rows)
          if (_cleanId(row['profile_id']) != null) _cleanId(row['profile_id'])!,
      };

      final profiles = await _loadProfiles(profileIds);

      final names = <String, String>{};

      for (final row in rows) {
        final patientId = _cleanId(row['id']);

        if (patientId == null) {
          continue;
        }

        final profileId = _cleanId(row['profile_id']);
        final profile = profileId == null ? null : profiles[profileId];

        final firstName = _firstText(
          <dynamic>[
            profile?['first_name'],
            row['first_name'],
          ],
          fallback: '',
        );

        final surname = _firstText(
          <dynamic>[
            profile?['surname'],
            profile?['last_name'],
            row['surname'],
            row['last_name'],
          ],
          fallback: '',
        );

        final fullName = '$firstName $surname'.trim();

        names[patientId] = fullName.isEmpty ? 'Patient' : fullName;
      }

      return names;
    } catch (error) {
      debugPrint('Could not load referral patient names: $error');
      return <String, String>{};
    }
  }

  Future<Map<String, String>> _loadDoctorNames(
    Set<String> doctorIds,
  ) async {
    if (doctorIds.isEmpty) {
      return <String, String>{};
    }

    try {
      final response = await _supabase
          .from('doctors')
          .select()
          .inFilter(
            'id',
            doctorIds.toList(),
          )
          .timeout(_requestTimeout);

      final rows = _rows(response);

      final profileIds = <String>{
        for (final row in rows)
          if (_cleanId(row['profile_id']) != null) _cleanId(row['profile_id'])!,
      };

      final profiles = await _loadProfiles(profileIds);

      final names = <String, String>{};

      for (final row in rows) {
        final doctorId = _cleanId(row['id']);

        if (doctorId == null) {
          continue;
        }

        final profileId = _cleanId(row['profile_id']);
        final profile = profileId == null ? null : profiles[profileId];

        final firstName = _firstText(
          <dynamic>[
            row['first_name'],
            profile?['first_name'],
            profile?['name'],
          ],
          fallback: '',
        );

        final surname = _firstText(
          <dynamic>[
            row['surname'],
            row['last_name'],
            profile?['surname'],
            profile?['last_name'],
          ],
          fallback: '',
        );

        final fullName = '$firstName $surname'.trim();

        final specialty = _firstText(
          <dynamic>[
            row['specialization'],
            row['specialisation'],
            row['specialty'],
            row['speciality'],
            row['department'],
          ],
          fallback: 'Specialist',
        );

        names[doctorId] = fullName.isEmpty
            ? 'Assigned specialist'
            : 'Dr. $fullName • $specialty';
      }

      return names;
    } catch (error) {
      debugPrint('Could not load assigned specialist names: $error');
      return <String, String>{};
    }
  }

  int _calculateAge(DateTime birthDate) {
    final now = DateTime.now();

    var age = now.year - birthDate.year;

    if (now.month < birthDate.month ||
        (now.month == birthDate.month && now.day < birthDate.day)) {
      age--;
    }

    return age < 0 ? 0 : age;
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();

    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate.isBefore(now) ? now : _selectedDate,
      firstDate: DateTime(
        now.year,
        now.month,
        now.day,
      ),
      lastDate: now.add(
        const Duration(days: 365),
      ),
    );

    if (picked == null || !mounted) {
      return;
    }

    setState(() {
      _selectedDate = picked;
    });
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _selectedTime,
    );

    if (picked == null || !mounted) {
      return;
    }

    setState(() {
      _selectedTime = picked;
    });
  }

  DateTime get _preferredDateTime {
    return DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
      _selectedTime.hour,
      _selectedTime.minute,
    );
  }

  Future<void> _submitReferral() async {
    if (_saving) {
      return;
    }

    final patientId = _selectedPatientId;

    if (patientId == null || patientId.isEmpty) {
      _showMessage(
        'Select a patient first.',
        isError: true,
      );
      return;
    }

    final reason = _reasonController.text.trim();
    final notes = _notesController.text.trim();
    final specialty = _resolvedSpecialty;

    if (specialty.isEmpty) {
      _showMessage(
        _selectedSpecialty == 'Other'
            ? 'Enter the custom specialist field.'
            : 'Select a specialist field.',
        isError: true,
      );
      return;
    }

    if (reason.length < 5) {
      _showMessage(
        'Enter a clear reason for the referral.',
        isError: true,
      );
      return;
    }

    if (notes.length < 10) {
      _showMessage(
        'Referral notes must contain at least 10 characters.',
        isError: true,
      );
      return;
    }

    DateTime? preferredDateTime;

    if (_usePreferredDate) {
      preferredDateTime = _preferredDateTime;

      if (!preferredDateTime.isAfter(DateTime.now())) {
        _showMessage(
          'The preferred appointment must be in the future.',
          isError: true,
        );
        return;
      }
    }

    setState(() {
      _saving = true;
    });

    try {
      await _supabase.rpc(
        'create_doctor_specialist_referral',
        params: <String, dynamic>{
          'p_doctor_id': widget.doctorId,
          'p_patient_id': patientId,
          'p_specialty': specialty,
          'p_hospital_id': _selectedHospitalId,
          'p_preferred_appointment_at':
              preferredDateTime?.toUtc().toIso8601String(),
          'p_reason': reason,
          'p_referral_notes': notes,
          'p_urgency': _selectedUrgency,
        },
      ).timeout(_requestTimeout);

      if (!mounted) {
        return;
      }

      _reasonController.clear();
      _notesController.clear();
      _otherSpecialtyController.clear();

      setState(() {
        _selectedUrgency = 'routine';
        _selectedDate = DateTime.now().add(
          const Duration(days: 1),
        );
        _selectedTime = const TimeOfDay(
          hour: 9,
          minute: 0,
        );
      });

      _showMessage(
        'Specialist referral submitted to Reception.',
      );

      final referrals = await _loadRecentReferrals();

      if (!mounted) {
        return;
      }

      setState(() {
        _recentReferrals = referrals;
      });
    } on TimeoutException {
      _showMessage(
        'The server took too long to submit the referral.',
        isError: true,
      );
    } catch (error, stackTrace) {
      debugPrint(
        'Doctor specialist referral failed: $error\n$stackTrace',
      );

      _showMessage(
        _friendlyError(error),
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
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
          content: Text(message),
        ),
      );
  }

  String _friendlyError(Object error) {
    final message =
        error is PostgrestException ? error.message : error.toString();

    final lower = message.toLowerCase();

    if (lower.contains('function') && lower.contains('does not exist')) {
      return 'The doctor referral database function is missing. Run the specialist workflow SQL in Supabase.';
    }

    if (lower.contains('permission denied') ||
        lower.contains('row-level security') ||
        lower.contains('42501')) {
      return 'This doctor account does not have permission to create the referral.';
    }

    if (lower.contains('doctor record')) {
      return 'The doctor account is not linked correctly in Supabase.';
    }

    if (lower.contains('patient')) {
      return 'The selected patient could not be used for this referral.';
    }

    if (lower.contains('future')) {
      return 'Select a preferred date and time in the future.';
    }

    if (lower.contains('network') ||
        lower.contains('socket') ||
        lower.contains('failed host')) {
      return 'Could not connect to Corvia. Check the connection and try again.';
    }

    return message
        .replaceFirst('Exception: ', '')
        .replaceAll(
          'PostgrestException(message: ',
          '',
        )
        .replaceAll(')', '');
  }

  List<Map<String, dynamic>> _rows(
    dynamic response,
  ) {
    if (response is! List) {
      return <Map<String, dynamic>>[];
    }

    return response
        .whereType<Map>()
        .map(
          (row) => Map<String, dynamic>.from(row),
        )
        .toList();
  }

  String? _cleanId(dynamic value) {
    final text = value?.toString().trim();

    if (text == null || text.isEmpty || text == 'null') {
      return null;
    }

    return text;
  }

  String? _nullableText(dynamic value) {
    final text = value?.toString().trim();

    if (text == null || text.isEmpty || text == 'null') {
      return null;
    }

    return text;
  }

  String _firstText(
    List<dynamic> values, {
    required String fallback,
  }) {
    for (final value in values) {
      final text = value?.toString().trim();

      if (text != null && text.isNotEmpty && text != 'null') {
        return text;
      }
    }

    return fallback;
  }

  String _canonicalValue(
    dynamic value, {
    required String fallback,
  }) {
    final text = value?.toString().trim().toLowerCase();

    if (text == null || text.isEmpty || text == 'null') {
      return fallback;
    }

    return text
        .replaceAll(
          RegExp(r'[\s-]+'),
          '_',
        )
        .replaceAll(
          RegExp(r'_+'),
          '_',
        );
  }

  DateTime? _parseDate(dynamic value) {
    final text = value?.toString().trim();

    if (text == null || text.isEmpty || text == 'null') {
      return null;
    }

    return DateTime.tryParse(text)?.toLocal();
  }

  String _prettyValue(String value) {
    return value
        .replaceAll('_', ' ')
        .split(' ')
        .where(
          (word) => word.isNotEmpty,
        )
        .map(
          (word) => '${word[0].toUpperCase()}${word.substring(1)}',
        )
        .join(' ');
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'pending':
        return Colors.orange.shade800;
      case 'assigned':
        return Colors.deepPurple;
      case 'confirmed':
        return Colors.green.shade700;
      case 'rescheduled':
        return Colors.blue.shade700;
      case 'referral_required':
        return Colors.amber.shade900;
      case 'rejected':
        return CorviaColors.danger;
      case 'cancelled':
        return Colors.grey.shade700;
      default:
        return context.cTextSecondary;
    }
  }

  Color _urgencyColor(String urgency) {
    switch (urgency) {
      case 'emergency':
        return CorviaColors.danger;
      case 'urgent':
        return Colors.deepOrange;
      case 'priority':
        return Colors.amber.shade900;
      default:
        return Colors.blueGrey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.cBgPrimary,
      appBar: AppBar(
        title: const Text(
          'Refer to Specialist',
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh full page',
            onPressed: _loading ? null : _loadPage,
            icon: const Icon(
              Icons.refresh_rounded,
            ),
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (_error != null) {
      return RefreshIndicator(
        onRefresh: _loadPage,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(24),
          children: [
            const SizedBox(height: 100),
            Icon(
              Icons.error_outline_rounded,
              color: CorviaColors.danger,
              size: 60,
            ),
            const SizedBox(height: 16),
            Text(
              'The specialist referral page could not load.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: context.cTextPrimary,
                fontSize: 20,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: context.cTextSecondary,
              ),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: _loadPage,
              icon: const Icon(
                Icons.refresh_rounded,
              ),
              label: const Text('Try Again'),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadPage,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          16,
          18,
          16,
          30,
        ),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: 1100,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeader(),
                  const SizedBox(height: 18),
                  _buildReferralForm(),
                  const SizedBox(height: 28),
                  _buildRecentReferrals(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: context.cBgSecondary,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: CorviaColors.accent.withValues(alpha: 0.28),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: CorviaColors.accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(15),
            ),
            child: Icon(
              Icons.medical_information_outlined,
              color: CorviaColors.accent,
              size: 28,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Create a Clinical Referral',
                  style: TextStyle(
                    color: context.cTextPrimary,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  'Select a patient, specialist field, urgency and clinical notes. Reception will assign the specialist and confirm the appointment.',
                  style: TextStyle(
                    color: context.cTextSecondary,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReferralForm() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: context.cBgSecondary,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: context.cDivider,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Referral Details',
            style: TextStyle(
              color: context.cTextPrimary,
              fontSize: 19,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 18),
          DropdownButtonFormField<String>(
            initialValue: _selectedPatientId,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Patient',
              prefixIcon: Icon(
                Icons.person_outline_rounded,
              ),
              border: OutlineInputBorder(),
            ),
            items: _patients.map(
              (patient) {
                return DropdownMenuItem<String>(
                  value: patient.id,
                  child: Text(
                    patient.displayName,
                    overflow: TextOverflow.ellipsis,
                  ),
                );
              },
            ).toList(),
            onChanged: _saving
                ? null
                : (value) {
                    setState(() {
                      _selectedPatientId = value;
                    });
                  },
          ),
          if (_patients.isEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'No patients are currently linked to this doctor through an appointment or prescription.',
              style: TextStyle(
                color: CorviaColors.warning,
                fontSize: 12,
              ),
            ),
          ],
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth < 650) {
                return Column(
                  children: [
                    _specialtyField(),
                    const SizedBox(height: 16),
                    _hospitalField(),
                  ],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _specialtyField(),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: _hospitalField(),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 18),
          Text(
            'Urgency',
            style: TextStyle(
              color: context.cTextPrimary,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 9),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _urgencies.map(
              (urgency) {
                final selected = _selectedUrgency == urgency;
                final color = _urgencyColor(urgency);

                return ChoiceChip(
                  label: Text(
                    _prettyValue(urgency),
                  ),
                  selected: selected,
                  selectedColor: color,
                  labelStyle: TextStyle(
                    color: selected ? Colors.white : context.cTextPrimary,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
                  ),
                  onSelected: _saving
                      ? null
                      : (_) {
                          setState(() {
                            _selectedUrgency = urgency;
                          });
                        },
                );
              },
            ).toList(),
          ),
          const SizedBox(height: 18),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text(
              'Add preferred appointment date',
            ),
            subtitle: const Text(
              'Reception may change this date when assigning the specialist.',
            ),
            value: _usePreferredDate,
            onChanged: _saving
                ? null
                : (value) {
                    setState(() {
                      _usePreferredDate = value;
                    });
                  },
          ),
          if (_usePreferredDate) ...[
            const SizedBox(height: 8),
            LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth < 520) {
                  return Column(
                    children: [
                      _dateChoice(),
                      const SizedBox(height: 10),
                      _timeChoice(),
                    ],
                  );
                }

                return Row(
                  children: [
                    Expanded(
                      child: _dateChoice(),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _timeChoice(),
                    ),
                  ],
                );
              },
            ),
          ],
          const SizedBox(height: 18),
          TextField(
            controller: _reasonController,
            enabled: !_saving,
            maxLength: 1000,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Reason for referral',
              hintText:
                  'Example: Persistent chest pain requiring cardiology assessment.',
              alignLabelWithHint: true,
              prefixIcon: Icon(
                Icons.description_outlined,
              ),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _notesController,
            enabled: !_saving,
            maxLength: 4000,
            minLines: 4,
            maxLines: 8,
            decoration: const InputDecoration(
              labelText: 'Clinical referral notes',
              hintText:
                  'Relevant history, examination, previous treatment, results and clinical question for the specialist.',
              alignLabelWithHint: true,
              prefixIcon: Icon(
                Icons.medical_information_outlined,
              ),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _saving || _patients.isEmpty ? null : _submitReferral,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                      ),
                    )
                  : const Icon(
                      Icons.send_rounded,
                    ),
              label: Text(
                _saving ? 'Submitting Referral...' : 'Submit to Reception',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _specialtyField() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        DropdownButtonFormField<String>(
          initialValue: _selectedSpecialty,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Specialist field',
            prefixIcon: Icon(
              Icons.health_and_safety_outlined,
            ),
            border: OutlineInputBorder(),
          ),
          items: _specialties.map(
            (specialty) {
              return DropdownMenuItem<String>(
                value: specialty,
                child: Text(
                  specialty,
                  overflow: TextOverflow.ellipsis,
                ),
              );
            },
          ).toList(),
          onChanged: _saving
              ? null
              : (value) {
                  if (value == null) {
                    return;
                  }

                  setState(() {
                    _selectedSpecialty = value;

                    if (value != 'Other') {
                      _otherSpecialtyController.clear();
                    }
                  });
                },
        ),
        if (_selectedSpecialty == 'Other') ...[
          const SizedBox(height: 12),
          TextFormField(
            controller: _otherSpecialtyController,
            enabled: !_saving,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Custom specialist field',
              hintText: 'Enter the specialist field',
              prefixIcon: Icon(Icons.edit_outlined),
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ],
    );
  }

  Widget _hospitalField() {
    return DropdownButtonFormField<String>(
      initialValue: _selectedHospitalId,
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: 'Preferred hospital',
        prefixIcon: Icon(
          Icons.local_hospital_outlined,
        ),
        border: OutlineInputBorder(),
      ),
      items: _hospitals.map(
        (hospital) {
          return DropdownMenuItem<String>(
            value: hospital.id,
            child: Text(
              hospital.name,
              overflow: TextOverflow.ellipsis,
            ),
          );
        },
      ).toList(),
      onChanged: _saving
          ? null
          : (value) {
              setState(() {
                _selectedHospitalId = value;
              });
            },
    );
  }

  Widget _dateChoice() {
    return _ChoicePanel(
      icon: Icons.calendar_today_outlined,
      label: 'Preferred date',
      value: DateFormat(
        'EEE, d MMM yyyy',
      ).format(_selectedDate),
      onTap: _saving ? null : _pickDate,
    );
  }

  Widget _timeChoice() {
    return _ChoicePanel(
      icon: Icons.access_time_rounded,
      label: 'Preferred time',
      value: _selectedTime.format(context),
      onTap: _saving ? null : _pickTime,
    );
  }

  Widget _buildRecentReferrals() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Recent Specialist Referrals',
                style: TextStyle(
                  color: context.cTextPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            IconButton(
              tooltip: 'Refresh referral status',
              onPressed: _refreshingReferrals ? null : _refreshReferralsOnly,
              icon: _refreshingReferrals
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                      ),
                    )
                  : const Icon(
                      Icons.refresh_rounded,
                    ),
            ),
          ],
        ),
        Text(
          'Track referrals created by this doctor.',
          style: TextStyle(
            color: context.cTextSecondary,
          ),
        ),
        const SizedBox(height: 14),
        if (_recentReferrals.isEmpty)
          _emptyReferrals()
        else
          ..._recentReferrals.map(
            (referral) {
              return Padding(
                padding: const EdgeInsets.only(
                  bottom: 11,
                ),
                child: _referralCard(referral),
              );
            },
          ),
      ],
    );
  }

  Widget _emptyReferrals() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: context.cBgSecondary,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: context.cDivider,
        ),
      ),
      child: Column(
        children: [
          Icon(
            Icons.medical_information_outlined,
            size: 44,
            color: context.cTextSecondary,
          ),
          const SizedBox(height: 10),
          Text(
            'No specialist referrals yet.',
            style: TextStyle(
              color: context.cTextPrimary,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'New referrals will appear here after submission.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: context.cTextSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _referralCard(
    _ReferralRecord referral,
  ) {
    final statusColor = _statusColor(referral.status);
    final urgencyColor = _urgencyColor(referral.urgency);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: context.cBgSecondary,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: statusColor.withValues(alpha: 0.28),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                backgroundColor: statusColor.withValues(alpha: 0.12),
                child: Icon(
                  Icons.health_and_safety_outlined,
                  color: statusColor,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      referral.patientName,
                      style: TextStyle(
                        color: context.cTextPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      referral.specialty,
                      style: TextStyle(
                        color: context.cAccentReadable,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              _badge(
                _prettyValue(referral.status),
                statusColor,
              ),
            ],
          ),
          const SizedBox(height: 13),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              _badge(
                _prettyValue(referral.urgency),
                urgencyColor,
              ),
              _badge(
                _prettyValue(referral.referralStatus),
                Colors.blueGrey,
              ),
              if (referral.createdAt != null)
                _detailChip(
                  Icons.history_rounded,
                  'Created ${DateFormat('d MMM yyyy • HH:mm').format(referral.createdAt!)}',
                ),
              if (referral.assignedDoctorName != null)
                _detailChip(
                  Icons.person_outline_rounded,
                  referral.assignedDoctorName!,
                ),
              if (referral.finalAt != null)
                _detailChip(
                  Icons.event_available_rounded,
                  'Final ${DateFormat('d MMM yyyy • HH:mm').format(referral.finalAt!)}',
                )
              else if (referral.preferredAt != null)
                _detailChip(
                  Icons.event_outlined,
                  'Preferred ${DateFormat('d MMM yyyy • HH:mm').format(referral.preferredAt!)}',
                ),
              if (referral.appointmentId != null)
                _detailChip(
                  Icons.confirmation_number_outlined,
                  'Appointment ${referral.shortAppointmentId}',
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            referral.reason,
            style: TextStyle(
              color: context.cTextPrimary,
              height: 1.35,
            ),
          ),
          if (referral.receptionNotes != null) ...[
            const SizedBox(height: 12),
            _infoPanel(
              icon: Icons.notes_outlined,
              title: 'Reception notes',
              text: referral.receptionNotes!,
              color: Colors.blueGrey,
            ),
          ],
          if (referral.rejectionReason != null) ...[
            const SizedBox(height: 12),
            _infoPanel(
              icon: Icons.cancel_outlined,
              title: 'Rejection reason',
              text: referral.rejectionReason!,
              color: CorviaColors.danger,
            ),
          ],
        ],
      ),
    );
  }

  Widget _infoPanel({
    required IconData icon,
    required String title,
    required String text,
    required Color color,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: color.withValues(alpha: 0.22),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            color: color,
            size: 19,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: context.cTextPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  text,
                  style: TextStyle(
                    color: context.cTextSecondary,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _badge(
    String label,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 9,
        vertical: 5,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: color.withValues(alpha: 0.30),
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  Widget _detailChip(
    IconData icon,
    String label,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 9,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: context.cBgPrimary,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: context.cDivider,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 14,
            color: context.cTextSecondary,
          ),
          const SizedBox(width: 5),
          ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: 360,
            ),
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: context.cTextSecondary,
                fontSize: 11,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReferralPatient {
  const _ReferralPatient({
    required this.id,
    required this.name,
    required this.patientNumber,
    required this.age,
    required this.gender,
  });

  final String id;
  final String name;
  final String patientNumber;
  final int? age;
  final String gender;

  String get displayName {
    final ageText = age == null ? '' : ' • $age yrs';
    return '$name$ageText • $patientNumber';
  }
}

class _HospitalOption {
  const _HospitalOption({
    required this.id,
    required this.name,
  });

  final String id;
  final String name;
}

class _ReferralRecord {
  const _ReferralRecord({
    required this.id,
    required this.patientName,
    required this.specialty,
    required this.urgency,
    required this.status,
    required this.referralStatus,
    required this.reason,
    required this.createdAt,
    required this.preferredAt,
    required this.finalAt,
    required this.assignedDoctorId,
    required this.assignedDoctorName,
    required this.appointmentId,
    required this.receptionNotes,
    required this.rejectionReason,
  });

  final String id;
  final String patientName;
  final String specialty;
  final String urgency;
  final String status;
  final String referralStatus;
  final String reason;

  final DateTime? createdAt;
  final DateTime? preferredAt;
  final DateTime? finalAt;

  final String? assignedDoctorId;
  final String? assignedDoctorName;
  final String? appointmentId;

  final String? receptionNotes;
  final String? rejectionReason;

  String get shortAppointmentId {
    final value = appointmentId;

    if (value == null || value.length <= 8) {
      return value ?? '';
    }

    return value.substring(0, 8);
  }
}

class _ChoicePanel extends StatelessWidget {
  const _ChoicePanel({
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.cBgPrimary,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: context.cDivider,
            ),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                color: context.cAccentReadable,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        color: context.cTextSecondary,
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      value,
                      style: TextStyle(
                        color: context.cTextPrimary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
