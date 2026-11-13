import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../theme/app_theme.dart';

class PharmacistPrescriptionDetailPage extends StatefulWidget {
  const PharmacistPrescriptionDetailPage({
    super.key,
    required this.dispenseId,
  });

  final String dispenseId;

  @override
  State<PharmacistPrescriptionDetailPage> createState() =>
      _PharmacistPrescriptionDetailPageState();
}

class _PharmacistPrescriptionDetailPageState
    extends State<PharmacistPrescriptionDetailPage> {
  final SupabaseClient _supabase = Supabase.instance.client;

  bool _loading = true;
  bool _saving = false;
  bool _changed = false;

  String? _error;
  String _pharmacistName = 'Pharmacist';

  Map<String, dynamic>? _dispense;
  Map<String, dynamic>? _prescription;
  Map<String, dynamic>? _patient;
  Map<String, dynamic>? _patientProfile;
  Map<String, dynamic>? _doctor;
  Map<String, dynamic>? _doctorProfile;
  Map<String, dynamic>? _hospital;

  List<Map<String, dynamic>> _events = [];
  Map<String, Map<String, dynamic>> _eventProfiles = {};

  @override
  void initState() {
    super.initState();

    _loadDetails();
  }

  Future<void> _loadDetails() async {
    if (!mounted) {
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final user = _supabase.auth.currentUser;

      if (user == null) {
        throw Exception(
          'No signed-in Corvia account was found.',
        );
      }

      final profile = await _supabase
          .from('profiles')
          .select()
          .eq('user_id', user.id)
          .maybeSingle();

      if (profile == null) {
        throw Exception(
          'No Corvia profile is linked to this account.',
        );
      }

      final role = profile['role']?.toString().trim().toLowerCase() ?? '';

      final userType =
          profile['user_type']?.toString().trim().toLowerCase() ?? '';

      if (role != 'pharmacist' && userType != 'pharmacist') {
        throw Exception(
          'This account does not have pharmacist access.',
        );
      }

      if (profile['is_active'] == false) {
        throw Exception(
          'This pharmacist profile is inactive.',
        );
      }

      _pharmacistName = _firstText(
        [
          profile['full_name'],
          profile['display_name'],
          profile['name'],
          _combineName(
            profile['first_name'],
            profile['surname'],
          ),
          profile['email'],
          user.email,
        ],
        fallback: 'Pharmacist',
      );

      final pharmacist = await _supabase
          .from('pharmacists')
          .select()
          .eq('profile_id', user.id)
          .maybeSingle();

      if (pharmacist == null) {
        throw Exception(
          'No pharmacist staff record is linked to this account.',
        );
      }

      if (pharmacist['is_active'] == false) {
        throw Exception(
          'This pharmacist staff record is inactive.',
        );
      }

      final hospitalId = _cleanId(pharmacist['hospital_id']);

      if (hospitalId == null) {
        throw Exception(
          'No hospital is linked to this pharmacist.',
        );
      }

      final dispense = await _supabase
          .from('prescription_dispenses')
          .select()
          .eq('id', widget.dispenseId)
          .eq('hospital_id', hospitalId)
          .maybeSingle();

      if (dispense == null) {
        throw Exception(
          'The pharmacy record could not be found or belongs '
          'to another hospital.',
        );
      }

      final loadedDispense = Map<String, dynamic>.from(dispense);

      final prescriptionId = _cleanId(loadedDispense['prescription_id']);

      final patientId = _cleanId(loadedDispense['patient_id']);

      final dispenseHospitalId = _cleanId(loadedDispense['hospital_id']);

      Map<String, dynamic>? loadedPrescription;
      Map<String, dynamic>? loadedPatient;
      Map<String, dynamic>? loadedPatientProfile;
      Map<String, dynamic>? loadedDoctor;
      Map<String, dynamic>? loadedDoctorProfile;
      Map<String, dynamic>? loadedHospital;

      if (prescriptionId != null) {
        final response = await _supabase
            .from('prescriptions')
            .select()
            .eq('id', prescriptionId)
            .maybeSingle();

        if (response != null) {
          loadedPrescription = Map<String, dynamic>.from(response);
        }
      }

      if (patientId != null) {
        final response = await _supabase
            .from('patients')
            .select()
            .eq('id', patientId)
            .maybeSingle();

        if (response != null) {
          loadedPatient = Map<String, dynamic>.from(response);

          final patientProfileId = _cleanId(loadedPatient['profile_id']);

          if (patientProfileId != null) {
            final profileResponse = await _supabase
                .from('profiles')
                .select()
                .eq('user_id', patientProfileId)
                .maybeSingle();

            if (profileResponse != null) {
              loadedPatientProfile = Map<String, dynamic>.from(
                profileResponse,
              );
            }
          }
        }
      }

      final doctorId = _cleanId(loadedPrescription?['doctor_id']);

      if (doctorId != null) {
        final response = await _supabase
            .from('doctors')
            .select()
            .eq('id', doctorId)
            .maybeSingle();

        if (response != null) {
          loadedDoctor = Map<String, dynamic>.from(response);

          final doctorProfileId = _cleanId(loadedDoctor['profile_id']);

          if (doctorProfileId != null) {
            try {
              final profileResponse = await _supabase
                  .from('profiles')
                  .select()
                  .eq('user_id', doctorProfileId)
                  .maybeSingle();

              if (profileResponse != null) {
                loadedDoctorProfile = Map<String, dynamic>.from(
                  profileResponse,
                );
              }
            } catch (error) {
              debugPrint(
                'Doctor profile lookup failed: $error',
              );
            }
          }
        }
      }

      if (dispenseHospitalId != null) {
        final response = await _supabase
            .from('hospitals')
            .select()
            .eq('id', dispenseHospitalId)
            .maybeSingle();

        if (response != null) {
          loadedHospital = Map<String, dynamic>.from(response);
        }
      }

      final eventResponse = await _supabase
          .from('prescription_dispense_events')
          .select()
          .eq('dispense_id', widget.dispenseId)
          .order(
            'created_at',
            ascending: true,
          );

      final loadedEvents = _rows(eventResponse);

      final changedByIds = loadedEvents
          .map(
            (event) => _cleanId(
              event['changed_by'],
            ),
          )
          .whereType<String>()
          .toSet()
          .toList();

      final eventProfiles = <String, Map<String, dynamic>>{};

      if (changedByIds.isNotEmpty) {
        try {
          final eventProfileResponse =
              await _supabase.from('profiles').select().inFilter(
                    'user_id',
                    changedByIds,
                  );

          for (final row in _rows(eventProfileResponse)) {
            final userId = _cleanId(row['user_id']);

            if (userId != null) {
              eventProfiles[userId] = row;
            }
          }
        } catch (error) {
          debugPrint(
            'Dispense event profile lookup failed: $error',
          );
        }
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _dispense = loadedDispense;
        _prescription = loadedPrescription;
        _patient = loadedPatient;
        _patientProfile = loadedPatientProfile;
        _doctor = loadedDoctor;
        _doctorProfile = loadedDoctorProfile;
        _hospital = loadedHospital;
        _events = loadedEvents;
        _eventProfiles = eventProfiles;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _loading = false;
        _error = _cleanError(error);
      });
    }
  }

  List<Map<String, dynamic>> _rows(dynamic response) {
    if (response is! List) {
      return [];
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

    if (text == null || text.isEmpty || text.toLowerCase() == 'null') {
      return null;
    }

    return text;
  }

  String _cleanError(Object error) {
    if (error is PostgrestException) {
      final details = error.details?.toString().trim() ?? '';

      if (details.isNotEmpty &&
          details.toLowerCase() != 'null' &&
          details != error.message) {
        return '${error.message} $details';
      }

      return error.message;
    }

    return error.toString().replaceFirst(
          'Exception: ',
          '',
        );
  }

  String _firstText(
    List<dynamic> values, {
    required String fallback,
  }) {
    for (final value in values) {
      final text = value?.toString().trim();

      if (text != null && text.isNotEmpty && text.toLowerCase() != 'null') {
        return text;
      }
    }

    return fallback;
  }

  String? _nullableText(dynamic value) {
    final text = value?.toString().trim();

    if (text == null || text.isEmpty || text.toLowerCase() == 'null') {
      return null;
    }

    return text;
  }

  String _combineName(
    dynamic firstName,
    dynamic surname,
  ) {
    return [
      firstName?.toString().trim() ?? '',
      surname?.toString().trim() ?? '',
    ]
        .where(
          (part) => part.isNotEmpty,
        )
        .join(' ');
  }

  String get _patientName {
    return _firstText(
      [
        _patientProfile?['full_name'],
        _patientProfile?['display_name'],
        _patientProfile?['name'],
        _combineName(
          _patientProfile?['first_name'],
          _patientProfile?['surname'],
        ),
        _patient?['full_name'],
        _patient?['name'],
        _combineName(
          _patient?['first_name'],
          _patient?['surname'],
        ),
        _patientProfile?['email'],
        _patient?['email'],
      ],
      fallback: 'Patient details unavailable',
    );
  }

  String get _doctorName {
    return _firstText(
      [
        _doctor?['full_name'],
        _doctorProfile?['full_name'],
        _doctorProfile?['display_name'],
        _doctorProfile?['name'],
        _combineName(
          _doctor?['first_name'],
          _doctor?['surname'],
        ),
        _combineName(
          _doctorProfile?['first_name'],
          _doctorProfile?['surname'],
        ),
        _doctor?['email'],
        _doctorProfile?['email'],
      ],
      fallback: 'Prescriber details unavailable',
    );
  }

  String get _hospitalName {
    return _firstText(
      [
        _hospital?['name'],
      ],
      fallback: 'Hospital pharmacy',
    );
  }

  String get _medicineName {
    final directName = _firstText(
      [
        _prescription?['medication_name'],
        _prescription?['medicine_name'],
        _prescription?['medication'],
        _prescription?['drug_name'],
        _prescription?['name'],
      ],
      fallback: '',
    );

    if (directName.isNotEmpty) {
      return directName;
    }

    final medicines = _prescription?['medicines'];

    if (medicines is List) {
      final names = medicines
          .whereType<Map>()
          .map(
            (medicine) => _firstText(
              [
                medicine['name'],
                medicine['medication_name'],
                medicine['medication'],
              ],
              fallback: '',
            ),
          )
          .where(
            (name) => name.isNotEmpty,
          )
          .toList();

      if (names.isNotEmpty) {
        return names.join(', ');
      }
    }

    return 'Medication details unavailable';
  }

  String get _dosageSummary {
    final dosage = _firstText(
      [
        _prescription?['dosage'],
        _prescription?['dose'],
        _prescription?['dosage_amount'],
      ],
      fallback: '',
    );

    final dosageUnit = _firstText(
      [
        _prescription?['dosage_unit'],
      ],
      fallback: '',
    );

    final frequency = _firstText(
      [
        _prescription?['frequency'],
        _prescription?['frequency_code'],
      ],
      fallback: '',
    );

    final duration = _firstText(
      [
        _prescription?['duration'],
        _prescription?['duration_value'],
      ],
      fallback: '',
    );

    final durationUnit = _firstText(
      [
        _prescription?['duration_unit'],
      ],
      fallback: '',
    );

    final doseText = [
      dosage,
      dosageUnit,
    ]
        .where(
          (part) => part.isNotEmpty,
        )
        .join(' ');

    final durationText = [
      duration,
      durationUnit,
    ]
        .where(
          (part) => part.isNotEmpty,
        )
        .join(' ');

    final parts = [
      doseText,
      frequency,
      durationText,
    ]
        .where(
          (part) => part.isNotEmpty,
        )
        .toList();

    return parts.isEmpty ? 'Not recorded' : parts.join(' • ');
  }

  String get _instructions {
    return _firstText(
      [
        _prescription?['instructions'],
        _prescription?['notes'],
      ],
      fallback: 'No instructions recorded.',
    );
  }

  String get _status {
    return _firstText(
      [
        _dispense?['status'],
      ],
      fallback: 'received',
    ).toLowerCase();
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'received':
        return 'Received';

      case 'verified':
        return 'Verified';

      case 'preparing':
        return 'Preparing';

      case 'ready_for_collection':
        return 'Ready for Collection';

      case 'collected':
        return 'Collected';

      case 'unable_to_dispense':
        return 'Unable to Dispense';

      case 'cancelled':
        return 'Cancelled';

      default:
        return _pretty(status);
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'received':
        return Colors.orange.shade800;

      case 'verified':
        return Colors.blue.shade700;

      case 'preparing':
        return Colors.deepPurple;

      case 'ready_for_collection':
        return Colors.green.shade700;

      case 'collected':
        return Colors.teal.shade700;

      case 'unable_to_dispense':
        return CorviaColors.danger;

      case 'cancelled':
        return Colors.grey.shade700;

      default:
        return context.cAccentReadable;
    }
  }

  String _formatDateTime(dynamic value) {
    final date = DateTime.tryParse(
      value?.toString() ?? '',
    )?.toLocal();

    if (date == null) {
      return 'Not recorded';
    }

    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/'
        '${date.year} '
        '${date.hour.toString().padLeft(2, '0')}:'
        '${date.minute.toString().padLeft(2, '0')}';
  }

  String _formatDate(dynamic value) {
    final date = DateTime.tryParse(
      value?.toString() ?? '',
    )?.toLocal();

    if (date == null) {
      return _firstText(
        [value],
        fallback: 'Not recorded',
      );
    }

    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/'
        '${date.year}';
  }

  String _formatListOrText(
    dynamic value, {
    required String fallback,
  }) {
    if (value is List) {
      final values = value
          .map(
            (item) => item?.toString().trim() ?? '',
          )
          .where(
            (item) => item.isNotEmpty,
          )
          .toList();

      if (values.isNotEmpty) {
        return values.join(', ');
      }
    }

    return _firstText(
      [value],
      fallback: fallback,
    );
  }

  String _pretty(String value) {
    final cleaned = value.trim().replaceAll('-', '_').replaceAll(' ', '_');

    return cleaned
        .split('_')
        .where(
          (word) => word.isNotEmpty,
        )
        .map(
      (word) {
        return '${word[0].toUpperCase()}'
            '${word.substring(1).toLowerCase()}';
      },
    ).join(' ');
  }

  String _eventStaffName(
    Map<String, dynamic> event,
  ) {
    final changedBy = _cleanId(event['changed_by']);

    if (changedBy == null) {
      return 'Corvia system';
    }

    final profile = _eventProfiles[changedBy];

    return _firstText(
      [
        profile?['full_name'],
        profile?['display_name'],
        profile?['name'],
        _combineName(
          profile?['first_name'],
          profile?['surname'],
        ),
        profile?['email'],
      ],
      fallback: changedBy == _supabase.auth.currentUser?.id
          ? _pharmacistName
          : 'Pharmacy staff',
    );
  }

  String? _nextActionLabel(String status) {
    switch (status) {
      case 'received':
        return 'Verify Prescription';

      case 'verified':
        return 'Start Preparing';

      case 'preparing':
        return 'Mark Ready';

      case 'ready_for_collection':
        return 'Confirm Collection';

      default:
        return null;
    }
  }

  IconData _nextActionIcon(String status) {
    switch (status) {
      case 'received':
        return Icons.verified_outlined;

      case 'verified':
        return Icons.medication_outlined;

      case 'preparing':
        return Icons.inventory_2_outlined;

      case 'ready_for_collection':
        return Icons.check_circle_outline;

      default:
        return Icons.arrow_forward;
    }
  }

  Future<bool> _confirm({
    required String title,
    required String message,
    required String buttonText,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(false);
              },
              child: const Text(
                'Cancel',
              ),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(true);
              },
              child: Text(buttonText),
            ),
          ],
        );
      },
    );

    return result == true;
  }

  Future<bool> _updateStatus({
    required String newStatus,
    String? verifiedByName,
    String? verificationMethod,
    String? collectedByName,
    String? collectorRelationship,
    String? unavailableReason,
    String? pharmacistNotes,
    String? collectionNotes,
    required String successMessage,
  }) async {
    if (_saving || _dispense == null) {
      return false;
    }

    final dispenseId = _cleanId(_dispense?['id']);

    if (dispenseId == null) {
      _showMessage(
        'The dispensing record ID is unavailable.',
      );

      return false;
    }

    setState(() {
      _saving = true;
    });

    try {
      final response = await _supabase.rpc(
        'corvia_update_dispense_status',
        params: {
          'p_dispense_id': dispenseId,
          'p_new_status': newStatus,
          'p_verified_by_name': _nullableText(verifiedByName),
          'p_verification_method': _nullableText(verificationMethod),
          'p_collected_by_name': _nullableText(collectedByName),
          'p_collector_relationship': _nullableText(collectorRelationship),
          'p_unavailable_reason': _nullableText(unavailableReason),
          'p_pharmacist_notes': _nullableText(pharmacistNotes),
          'p_collection_notes': _nullableText(collectionNotes),
        },
      );

      if (response is Map &&
          response.containsKey('success') &&
          response['success'] != true) {
        throw Exception(
          response['message']?.toString() ??
              'The pharmacy status update was not completed.',
        );
      }

      _changed = true;

      await _loadDetails();

      if (mounted) {
        _showMessage(successMessage);
      }

      return true;
    } catch (error) {
      if (mounted) {
        _showMessage(
          'Could not update prescription. '
          '${_cleanError(error)}',
        );
      }

      return false;
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  Future<void> _verify() async {
    final confirmed = await _confirm(
      title: 'Verify Prescription',
      message: 'Confirm that the patient, prescriber, medication, '
          'dosage and instructions were checked.',
      buttonText: 'Verify',
    );

    if (!confirmed || !mounted) {
      return;
    }

    await _updateStatus(
      newStatus: 'verified',
      verifiedByName: _pharmacistName,
      verificationMethod: 'Prescription and prescriber details checked',
      successMessage: 'Prescription verified.',
    );
  }

  Future<void> _markPreparing() async {
    final confirmed = await _confirm(
      title: 'Start Preparing',
      message: 'Mark this medication as being prepared by the pharmacy?',
      buttonText: 'Start Preparing',
    );

    if (!confirmed || !mounted) {
      return;
    }

    await _updateStatus(
      newStatus: 'preparing',
      successMessage: 'Medication is now being prepared.',
    );
  }

  Future<void> _markReady() async {
    final confirmed = await _confirm(
      title: 'Ready for Collection',
      message: 'Confirm that the medication is prepared and ready '
          'for collection.',
      buttonText: 'Mark Ready',
    );

    if (!confirmed || !mounted) {
      return;
    }

    await _updateStatus(
      newStatus: 'ready_for_collection',
      successMessage: 'Medication marked ready for collection.',
    );
  }

  Future<void> _markCollected() async {
    final result = await showDialog<_CollectionResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) {
        return const _CollectionDialog();
      },
    );

    if (result == null || !mounted) {
      return;
    }

    await _updateStatus(
      newStatus: 'collected',
      verifiedByName: result.collectorName,
      verificationMethod: 'Identity confirmed at collection',
      collectedByName: result.collectorName,
      collectorRelationship: result.relationship,
      collectionNotes: result.notes,
      successMessage: 'Medication collection confirmed.',
    );
  }

  Future<void> _markUnable() async {
    final reason = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) {
        return const _UnableToDispenseDialog();
      },
    );

    if (reason == null || reason.trim().isEmpty || !mounted) {
      return;
    }

    await _updateStatus(
      newStatus: 'unable_to_dispense',
      unavailableReason: reason.trim(),
      pharmacistNotes: reason.trim(),
      successMessage: 'Prescription marked unable to dispense.',
    );
  }

  Future<void> _performNextAction() async {
    switch (_status) {
      case 'received':
        await _verify();
        break;

      case 'verified':
        await _markPreparing();
        break;

      case 'preparing':
        await _markReady();
        break;

      case 'ready_for_collection':
        await _markCollected();
        break;

      default:
        _showMessage(
          'No next action is available for this status.',
        );
    }
  }

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
        ),
      );
  }

  Future<bool> _handleBack() async {
    Navigator.of(context).pop(_changed);

    return false;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (
        didPop,
        result,
      ) {
        if (!didPop) {
          _handleBack();
        }
      },
      child: Scaffold(
        backgroundColor: context.cBgPrimary,
        appBar: AppBar(
          leading: IconButton(
            tooltip: 'Back',
            onPressed: _handleBack,
            icon: const Icon(
              Icons.arrow_back,
            ),
          ),
          title: const Text(
            'Prescription Details',
          ),
          actions: [
            IconButton(
              tooltip: 'Refresh',
              onPressed: _loading || _saving ? null : _loadDetails,
              icon: const Icon(
                Icons.refresh,
              ),
            ),
          ],
        ),
        body: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return Center(
        child: CircularProgressIndicator(
          color: CorviaColors.accent,
        ),
      );
    }

    if (_error != null) {
      return _buildErrorState();
    }

    final dispense = _dispense;

    if (dispense == null) {
      return _buildErrorState(
        customMessage: 'The prescription dispensing record is unavailable.',
      );
    }

    final statusColor = _statusColor(_status);

    final nextAction = _nextActionLabel(_status);

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        18,
        18,
        18,
        32,
      ),
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: context.cBgSecondary,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: context.cDivider,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: statusColor.withValues(
                    alpha: 0.12,
                  ),
                  borderRadius: BorderRadius.circular(17),
                ),
                child: Icon(
                  Icons.local_pharmacy_outlined,
                  color: statusColor,
                  size: 30,
                ),
              ),
              const SizedBox(width: 15),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _medicineName,
                      style: TextStyle(
                        color: context.cTextPrimary,
                        fontSize: 21,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      _patientName,
                      style: TextStyle(
                        color: context.cTextSecondary,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      _hospitalName,
                      style: TextStyle(
                        color: context.cTextMuted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              _StatusBadge(
                label: _statusLabel(_status),
                color: statusColor,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _DetailSection(
          title: 'Patient',
          icon: Icons.person_outline,
          children: [
            _DetailRow(
              label: 'Patient',
              value: _patientName,
            ),
            _DetailRow(
              label: 'Patient number',
              value: _firstText(
                [
                  _patient?['patient_number'],
                ],
                fallback: 'Not recorded',
              ),
            ),
            _DetailRow(
              label: 'Date of birth',
              value: _formatDate(
                _patientProfile?['date_of_birth'] ?? _patient?['date_of_birth'],
              ),
            ),
            _DetailRow(
              label: 'Gender',
              value: _pretty(
                _firstText(
                  [
                    _patient?['gender'],
                    _patientProfile?['gender'],
                  ],
                  fallback: 'Not recorded',
                ),
              ),
            ),
            _DetailRow(
              label: 'Blood type',
              value: _firstText(
                [
                  _patient?['blood_type'],
                ],
                fallback: 'Not recorded',
              ),
            ),
            _DetailRow(
              label: 'Phone',
              value: _firstText(
                [
                  _patient?['phone'],
                  _patientProfile?['phone'],
                  _patientProfile?['phone_number'],
                ],
                fallback: 'Not recorded',
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _SafetySection(
          allergies: _formatListOrText(
            _patient?['allergies'],
            fallback: 'No allergies recorded',
          ),
          conditions: _firstText(
            [
              _patient?['medical_conditions'],
              _patient?['primary_condition'],
              _patient?['medical_history'],
            ],
            fallback: 'No medical conditions recorded',
          ),
        ),
        const SizedBox(height: 16),
        _DetailSection(
          title: 'Prescription',
          icon: Icons.description_outlined,
          children: [
            _DetailRow(
              label: 'Medication',
              value: _medicineName,
            ),
            _DetailRow(
              label: 'Dosage',
              value: _dosageSummary,
            ),
            _DetailRow(
              label: 'Instructions',
              value: _instructions,
            ),
            _DetailRow(
              label: 'Prescription status',
              value: _pretty(
                _firstText(
                  [
                    _prescription?['status'],
                  ],
                  fallback: 'active',
                ),
              ),
            ),
            _DetailRow(
              label: 'Issued',
              value: _formatDateTime(
                _prescription?['issued_at'] ?? _prescription?['created_at'],
              ),
            ),
            _DetailRow(
              label: 'Refillable',
              value: _prescription?['refillable'] == true ? 'Yes' : 'No',
            ),
            _DetailRow(
              label: 'Refills',
              value: '${_prescription?['refills_used'] ?? 0} used '
                  'of ${_prescription?['refills_allowed'] ?? 0}',
            ),
          ],
        ),
        const SizedBox(height: 16),
        _DetailSection(
          title: 'Prescriber',
          icon: Icons.medical_services_outlined,
          children: [
            _DetailRow(
              label: 'Doctor',
              value: _doctorName,
            ),
            _DetailRow(
              label: 'Specialisation',
              value: _firstText(
                [
                  _doctor?['specialization'],
                  _doctor?['specialty'],
                  _doctor?['department'],
                ],
                fallback: 'Not recorded',
              ),
            ),
            _DetailRow(
              label: 'Practice number',
              value: _firstText(
                [
                  _doctor?['practice_number'],
                  _doctor?['license_number'],
                ],
                fallback: 'Not recorded',
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _DetailSection(
          title: 'Pharmacy and Collection',
          icon: Icons.local_pharmacy_outlined,
          children: [
            _DetailRow(
              label: 'Hospital',
              value: _hospitalName,
            ),
            _DetailRow(
              label: 'Collection reference',
              value: _firstText(
                [
                  dispense['collection_reference'],
                ],
                fallback: 'Not recorded',
              ),
            ),
            _DetailRow(
              label: 'Current status',
              value: _statusLabel(_status),
            ),
            _DetailRow(
              label: 'Received',
              value: _formatDateTime(
                dispense['received_at'],
              ),
            ),
            _DetailRow(
              label: 'Verified',
              value: _formatDateTime(
                dispense['verified_at'],
              ),
            ),
            _DetailRow(
              label: 'Preparing',
              value: _formatDateTime(
                dispense['preparing_at'],
              ),
            ),
            _DetailRow(
              label: 'Ready',
              value: _formatDateTime(
                dispense['ready_at'],
              ),
            ),
            _DetailRow(
              label: 'Collected',
              value: _formatDateTime(
                dispense['collected_at'],
              ),
            ),
            _DetailRow(
              label: 'Collected by',
              value: _firstText(
                [
                  dispense['collected_by_name'],
                ],
                fallback: 'Not recorded',
              ),
            ),
            _DetailRow(
              label: 'Relationship',
              value: _firstText(
                [
                  dispense['collector_relationship'],
                ],
                fallback: 'Not recorded',
              ),
            ),
            _DetailRow(
              label: 'Collection notes',
              value: _firstText(
                [
                  dispense['collection_notes'],
                ],
                fallback: 'No collection notes',
              ),
            ),
            _DetailRow(
              label: 'Pharmacist notes',
              value: _firstText(
                [
                  dispense['pharmacist_notes'],
                ],
                fallback: 'No pharmacist notes',
              ),
            ),
          ],
        ),
        if (_status == 'unable_to_dispense') ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(17),
            decoration: BoxDecoration(
              color: CorviaColors.danger.withValues(
                alpha: 0.08,
              ),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: CorviaColors.danger.withValues(
                  alpha: 0.28,
                ),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      color: CorviaColors.danger,
                    ),
                    const SizedBox(width: 9),
                    Text(
                      'Unable to Dispense',
                      style: TextStyle(
                        color: CorviaColors.danger,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  _firstText(
                    [
                      dispense['unavailable_reason'],
                      dispense['pharmacist_notes'],
                    ],
                    fallback: 'No reason was recorded.',
                  ),
                  style: TextStyle(
                    color: context.cTextPrimary,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 16),
        _buildHistorySection(),
        const SizedBox(height: 18),
        if (nextAction != null)
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _saving ? null : _performNextAction,
              icon: _saving
                  ? const SizedBox(
                      width: 19,
                      height: 19,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                      ),
                    )
                  : Icon(
                      _nextActionIcon(_status),
                    ),
              label: Text(
                _saving ? 'Saving...' : nextAction,
              ),
            ),
          ),
        if (_status != 'collected' &&
            _status != 'cancelled' &&
            _status != 'unable_to_dispense') ...[
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _saving ? null : _markUnable,
              icon: const Icon(
                Icons.report_problem_outlined,
              ),
              label: const Text(
                'Unable to Dispense',
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildHistorySection() {
    return Container(
      padding: const EdgeInsets.all(17),
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
          Row(
            children: [
              Icon(
                Icons.history_rounded,
                color: context.cAccentReadable,
              ),
              const SizedBox(width: 9),
              Text(
                'Status History',
                style: TextStyle(
                  color: context.cTextPrimary,
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 15),
          if (_events.isEmpty)
            Text(
              'No status history is available.',
              style: TextStyle(
                color: context.cTextSecondary,
              ),
            )
          else
            ...List.generate(
              _events.length,
              (index) {
                final event = _events[index];

                final newStatus = _firstText(
                  [
                    event['new_status'],
                  ],
                  fallback: 'received',
                ).toLowerCase();

                final oldStatus = _firstText(
                  [
                    event['old_status'],
                  ],
                  fallback: '',
                ).toLowerCase();

                final notes = _firstText(
                  [
                    event['notes'],
                  ],
                  fallback: '',
                );

                return _HistoryItem(
                  isLast: index == _events.length - 1,
                  color: _statusColor(newStatus),
                  title: _statusLabel(newStatus),
                  subtitle: oldStatus.isEmpty
                      ? 'Pharmacy record created'
                      : 'Changed from '
                          '${_statusLabel(oldStatus)}',
                  staffName: _eventStaffName(event),
                  date: _formatDateTime(
                    event['created_at'],
                  ),
                  notes: notes,
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildErrorState({
    String? customMessage,
  }) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: 540,
          ),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: context.cBgSecondary,
              borderRadius: BorderRadius.circular(21),
              border: Border.all(
                color: context.cDivider,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.local_pharmacy_outlined,
                  color: CorviaColors.danger,
                  size: 56,
                ),
                const SizedBox(height: 16),
                Text(
                  'Prescription details could not load',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: context.cTextPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 11),
                SelectableText(
                  customMessage ?? _error ?? 'Unknown pharmacy error.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: context.cTextSecondary,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _loadDetails,
                    icon: const Icon(
                      Icons.refresh,
                    ),
                    label: const Text(
                      'Try Again',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CollectionDialog extends StatefulWidget {
  const _CollectionDialog();

  @override
  State<_CollectionDialog> createState() => _CollectionDialogState();
}

class _CollectionDialogState extends State<_CollectionDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _relationshipController;
  late final TextEditingController _notesController;

  String? _nameError;
  String? _relationshipError;

  @override
  void initState() {
    super.initState();

    _nameController = TextEditingController();

    _relationshipController = TextEditingController(
      text: 'Self',
    );

    _notesController = TextEditingController();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _relationshipController.dispose();
    _notesController.dispose();

    super.dispose();
  }

  void _submit() {
    final name = _nameController.text.trim();

    final relationship = _relationshipController.text.trim();

    final notes = _notesController.text.trim();

    setState(() {
      _nameError = name.isEmpty ? 'Collector name is required.' : null;

      _relationshipError =
          relationship.isEmpty ? 'Relationship is required.' : null;
    });

    if (_nameError != null || _relationshipError != null) {
      return;
    }

    Navigator.of(context).pop(
      _CollectionResult(
        collectorName: name,
        relationship: relationship,
        notes: notes,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text(
        'Confirm Collection',
      ),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _nameController,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  labelText: 'Collected By',
                  hintText: 'Patient or collector full name',
                  errorText: _nameError,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _relationshipController,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  labelText: 'Relationship',
                  hintText: 'Self, parent or guardian',
                  errorText: _relationshipError,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _notesController,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Collection Notes (Optional)',
                  hintText: 'Leave empty when there are no notes',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.of(context).pop();
          },
          child: const Text(
            'Cancel',
          ),
        ),
        ElevatedButton.icon(
          onPressed: _submit,
          icon: const Icon(
            Icons.check_circle_outline,
          ),
          label: const Text(
            'Confirm Collection',
          ),
        ),
      ],
    );
  }
}

class _UnableToDispenseDialog extends StatefulWidget {
  const _UnableToDispenseDialog();

  @override
  State<_UnableToDispenseDialog> createState() =>
      _UnableToDispenseDialogState();
}

class _UnableToDispenseDialogState extends State<_UnableToDispenseDialog> {
  late final TextEditingController _reasonController;

  String? _reasonError;

  @override
  void initState() {
    super.initState();

    _reasonController = TextEditingController();
  }

  @override
  void dispose() {
    _reasonController.dispose();

    super.dispose();
  }

  void _submit() {
    final reason = _reasonController.text.trim();

    setState(() {
      _reasonError = reason.isEmpty ? 'A reason is required.' : null;
    });

    if (_reasonError != null) {
      return;
    }

    Navigator.of(context).pop(reason);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text(
        'Unable to Dispense',
      ),
      content: SizedBox(
        width: 480,
        child: TextField(
          controller: _reasonController,
          autofocus: true,
          minLines: 3,
          maxLines: 6,
          decoration: InputDecoration(
            labelText: 'Reason Required',
            hintText: 'Example: medication unavailable',
            errorText: _reasonError,
            border: const OutlineInputBorder(),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.of(context).pop();
          },
          child: const Text(
            'Cancel',
          ),
        ),
        ElevatedButton.icon(
          onPressed: _submit,
          icon: const Icon(
            Icons.warning_amber_rounded,
          ),
          label: const Text(
            'Save Reason',
          ),
        ),
      ],
    );
  }
}

class _CollectionResult {
  const _CollectionResult({
    required this.collectorName,
    required this.relationship,
    required this.notes,
  });

  final String collectorName;
  final String relationship;
  final String notes;
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({
    required this.label,
    required this.color,
  });

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(
        maxWidth: 165,
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: color.withValues(
          alpha: 0.10,
        ),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: color.withValues(
            alpha: 0.24,
          ),
        ),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _DetailSection extends StatelessWidget {
  const _DetailSection({
    required this.title,
    required this.icon,
    required this.children,
  });

  final String title;
  final IconData icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(17),
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
          Row(
            children: [
              Icon(
                icon,
                color: context.cAccentReadable,
              ),
              const SizedBox(width: 9),
              Text(
                title,
                style: TextStyle(
                  color: context.cTextPrimary,
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 15),
          ...children,
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(
        bottom: 12,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 145,
            child: Text(
              label,
              style: TextStyle(
                color: context.cTextMuted,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: context.cTextPrimary,
                fontWeight: FontWeight.w600,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SafetySection extends StatelessWidget {
  const _SafetySection({
    required this.allergies,
    required this.conditions,
  });

  final String allergies;
  final String conditions;

  @override
  Widget build(BuildContext context) {
    final noAllergies = allergies.toLowerCase().contains(
          'no allergies',
        );

    final allergyColor =
        noAllergies ? Colors.green.shade700 : CorviaColors.danger;

    return Container(
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: allergyColor.withValues(
          alpha: 0.08,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: allergyColor.withValues(
            alpha: 0.30,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.health_and_safety_outlined,
                color: allergyColor,
              ),
              const SizedBox(width: 9),
              Text(
                'Patient Safety Information',
                style: TextStyle(
                  color: allergyColor,
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 15),
          Text(
            'Allergies',
            style: TextStyle(
              color: context.cTextMuted,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            allergies,
            style: TextStyle(
              color: context.cTextPrimary,
              fontWeight: FontWeight.w800,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 13),
          Text(
            'Medical conditions',
            style: TextStyle(
              color: context.cTextMuted,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            conditions,
            style: TextStyle(
              color: context.cTextPrimary,
              fontWeight: FontWeight.w600,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

class _HistoryItem extends StatelessWidget {
  const _HistoryItem({
    required this.isLast,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.staffName,
    required this.date,
    required this.notes,
  });

  final bool isLast;
  final Color color;
  final String title;
  final String subtitle;
  final String staffName;
  final String date;
  final String notes;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 28,
          child: Column(
            children: [
              Container(
                width: 13,
                height: 13,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                ),
              ),
              if (!isLast)
                Container(
                  width: 2,
                  height: notes.isEmpty ? 68 : 88,
                  color: context.cDivider,
                ),
            ],
          ),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(
              bottom: isLast ? 0 : 14,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: context.cTextPrimary,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: context.cTextSecondary,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '$staffName • $date',
                  style: TextStyle(
                    color: context.cTextMuted,
                    fontSize: 11,
                  ),
                ),
                if (notes.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    notes,
                    style: TextStyle(
                      color: context.cTextSecondary,
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}
