import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/settings_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/staff_workspace_shell.dart';
import '../../widgets/workspace_navigation.dart';

import '../forms/corvia_forms_navigator.dart';
import '../shared/settings.dart';

import 'pharmacist_prescription_detail_page.dart';

class PharmacistDashboardPage extends StatefulWidget {
  const PharmacistDashboardPage({
    super.key,
  });

  @override
  State<PharmacistDashboardPage> createState() {
    return _PharmacistDashboardPageState();
  }
}

class _PharmacistDashboardPageState extends State<PharmacistDashboardPage>
    with WorkspaceNavigation<PharmacistDashboardPage> {
  final SupabaseClient _supabase = Supabase.instance.client;

  final TextEditingController _searchController = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  bool _signingOut = false;
  bool _openingForm = false;

  String? _error;
  String? _hospitalId;
  String? _openingDispenseId;

  String _pharmacistName = 'Pharmacist';
  String _hospitalName = 'Hospital Pharmacy';
  String _selectedFilter = 'Active';

  List<Map<String, dynamic>> _dispenses = [];

  Map<String, Map<String, dynamic>> _prescriptions = {};
  Map<String, Map<String, dynamic>> _patients = {};
  Map<String, Map<String, dynamic>> _profiles = {};

  static const List<String> _filters = [
    'Active',
    'Received',
    'Verified',
    'Preparing',
    'Ready',
    'Collected',
    'Problems',
    'All',
  ];

  @override
  void initState() {
    super.initState();

    _loadDashboard();
  }

  @override
  void dispose() {
    _searchController.dispose();

    super.dispose();
  }

  // ==========================================================================
  // DASHBOARD LOAD
  // ==========================================================================

  Future<void> _loadDashboard() async {
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

      final profileResponse = await _supabase
          .from('profiles')
          .select()
          .eq(
            'user_id',
            user.id,
          )
          .maybeSingle();

      if (profileResponse == null) {
        throw Exception(
          'No profile is linked to this pharmacist login.',
        );
      }

      final profile = Map<String, dynamic>.from(
        profileResponse,
      );

      if (profile['is_active'] == false) {
        throw Exception(
          'This pharmacist account is inactive.',
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

      final pharmacistResponse = await _supabase
          .from('pharmacists')
          .select()
          .eq(
            'profile_id',
            user.id,
          )
          .maybeSingle();

      if (pharmacistResponse == null) {
        throw Exception(
          'This account has the pharmacist role, '
          'but no pharmacist staff record is linked to it.',
        );
      }

      final pharmacist = Map<String, dynamic>.from(
        pharmacistResponse,
      );

      if (pharmacist['is_active'] == false) {
        throw Exception(
          'This pharmacist staff record is inactive.',
        );
      }

      final pharmacistId = _cleanId(
        pharmacist['id'],
      );

      _hospitalId = _cleanId(
        pharmacist['hospital_id'],
      );

      if (pharmacistId == null) {
        throw Exception(
          'The pharmacist record has no ID.',
        );
      }

      if (_hospitalId == null) {
        throw Exception(
          'No hospital is linked to this pharmacist.',
        );
      }

      final pharmacyName = _firstText(
        [
          pharmacist['pharmacy_name'],
          pharmacist['department_name'],
        ],
        fallback: '',
      );

      try {
        final hospitalResponse = await _supabase
            .from('hospitals')
            .select(
              'id, name',
            )
            .eq(
              'id',
              _hospitalId!,
            )
            .maybeSingle();

        final hospitalName = hospitalResponse?['name']?.toString().trim();

        if (hospitalName != null && hospitalName.isNotEmpty) {
          _hospitalName = pharmacyName.isEmpty
              ? hospitalName
              : '$hospitalName • $pharmacyName';
        } else if (pharmacyName.isNotEmpty) {
          _hospitalName = pharmacyName;
        }
      } catch (error) {
        debugPrint(
          'Hospital name lookup failed: $error',
        );

        if (pharmacyName.isNotEmpty) {
          _hospitalName = pharmacyName;
        }
      }

      final dispenseResponse = await _supabase
          .from(
            'prescription_dispenses',
          )
          .select()
          .eq(
            'hospital_id',
            _hospitalId!,
          )
          .order(
            'received_at',
            ascending: false,
          )
          .limit(
            500,
          );

      _dispenses = _rows(
        dispenseResponse,
      );

      await _loadRelatedData();

      if (!mounted) {
        return;
      }

      setState(() {
        _loading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _loading = false;
        _error = _cleanError(
          error,
        );
      });
    }
  }

  // ==========================================================================
  // RELATED DATA
  // ==========================================================================

  Future<void> _loadRelatedData() async {
    _prescriptions = {};
    _patients = {};
    _profiles = {};

    final prescriptionIds = _dispenses
        .map(
          (
            row,
          ) =>
              _cleanId(
            row['prescription_id'],
          ),
        )
        .whereType<String>()
        .toSet()
        .toList();

    final patientIds = _dispenses
        .map(
          (
            row,
          ) =>
              _cleanId(
            row['patient_id'],
          ),
        )
        .whereType<String>()
        .toSet()
        .toList();

    if (prescriptionIds.isNotEmpty) {
      try {
        final response =
            await _supabase.from('prescriptions').select().inFilter(
                  'id',
                  prescriptionIds,
                );

        for (final row in _rows(
          response,
        )) {
          final id = _cleanId(
            row['id'],
          );

          if (id != null) {
            _prescriptions[id] = row;
          }
        }
      } catch (error) {
        debugPrint(
          'Prescription lookup failed: $error',
        );
      }
    }

    if (patientIds.isNotEmpty) {
      try {
        final response = await _supabase.from('patients').select().inFilter(
              'id',
              patientIds,
            );

        for (final row in _rows(
          response,
        )) {
          final id = _cleanId(
            row['id'],
          );

          if (id != null) {
            _patients[id] = row;
          }
        }
      } catch (error) {
        debugPrint(
          'Patient lookup failed: $error',
        );
      }
    }

    final profileIds = _patients.values
        .map(
          (
            patient,
          ) =>
              _cleanId(
            patient['profile_id'],
          ),
        )
        .whereType<String>()
        .toSet()
        .toList();

    if (profileIds.isNotEmpty) {
      try {
        final response = await _supabase.from('profiles').select().inFilter(
              'user_id',
              profileIds,
            );

        for (final row in _rows(
          response,
        )) {
          final userId = _cleanId(
            row['user_id'],
          );

          if (userId != null) {
            _profiles[userId] = row;
          }
        }
      } catch (error) {
        debugPrint(
          'Patient profile lookup failed: $error',
        );
      }
    }
  }

  // ==========================================================================
  // GENERIC HELPERS
  // ==========================================================================

  List<Map<String, dynamic>> _rows(
    dynamic response,
  ) {
    if (response is! List) {
      return [];
    }

    return response
        .whereType<Map>()
        .map(
          (
            row,
          ) =>
              Map<String, dynamic>.from(
            row,
          ),
        )
        .toList();
  }

  String? _cleanId(
    dynamic value,
  ) {
    final text = value?.toString().trim();

    if (text == null || text.isEmpty || text.toLowerCase() == 'null') {
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

      if (text != null && text.isNotEmpty && text.toLowerCase() != 'null') {
        return text;
      }
    }

    return fallback;
  }

  String? _nullableText(
    dynamic value,
  ) {
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
          (
            part,
          ) =>
              part.isNotEmpty,
        )
        .join(
          ' ',
        );
  }

  String _cleanError(
    Object error,
  ) {
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

  bool _isPlaceholderPatientName(String name) {
    final lower = name.trim().toLowerCase();

    return lower.isEmpty ||
        lower == 'patient' ||
        lower == 'corvia patient' ||
        lower == 'test patient';
  }

  // ==========================================================================
  // PRESCRIPTION / PATIENT HELPERS
  // ==========================================================================

  Map<String, dynamic>? _prescriptionFor(
    Map<String, dynamic> dispense,
  ) {
    final prescriptionId = _cleanId(
      dispense['prescription_id'],
    );

    if (prescriptionId == null) {
      return null;
    }

    return _prescriptions[prescriptionId];
  }

  Map<String, dynamic>? _patientFor(
    Map<String, dynamic> dispense,
  ) {
    final patientId = _cleanId(
      dispense['patient_id'],
    );

    if (patientId == null) {
      return null;
    }

    return _patients[patientId];
  }

  String _patientName(
    Map<String, dynamic> dispense,
  ) {
    final patient = _patientFor(
      dispense,
    );

    if (patient == null) {
      return 'Patient record unavailable';
    }

    final profileId = _cleanId(
      patient['profile_id'],
    );

    final profile = profileId == null ? null : _profiles[profileId];

    final candidates = [
      patient['full_name'],
      patient['name'],
      _combineName(
        patient['first_name'],
        patient['surname'],
      ),
      profile?['full_name'],
      profile?['display_name'],
      profile?['name'],
      _combineName(
        profile?['first_name'],
        profile?['surname'],
      ),
    ];

    for (final candidate in candidates) {
      final name = candidate?.toString().trim() ?? '';

      if (!_isPlaceholderPatientName(name)) {
        return name;
      }
    }

    return _firstText(
      [
        patient['email'],
        profile?['email'],
      ],
      fallback: 'Patient ${patient['id'] ?? ''}',
    );
  }

  String _patientNumber(
    Map<String, dynamic> dispense,
  ) {
    final patient = _patientFor(
      dispense,
    );

    return _firstText(
      [
        patient?['patient_number'],
      ],
      fallback: 'No patient number',
    );
  }

  String _medicineName(
    Map<String, dynamic> dispense,
  ) {
    final prescription = _prescriptionFor(
      dispense,
    );

    if (prescription == null) {
      return 'Prescription details unavailable';
    }

    final directName = _firstText(
      [
        prescription['medication_name'],
        prescription['medicine_name'],
        prescription['medication'],
        prescription['drug_name'],
        prescription['name'],
      ],
      fallback: '',
    );

    if (directName.isNotEmpty) {
      return directName;
    }

    final medicines = prescription['medicines'];

    if (medicines is List) {
      final names = medicines
          .whereType<Map>()
          .map(
            (
              medicine,
            ) =>
                _firstText(
              [
                medicine['name'],
                medicine['medication_name'],
                medicine['medication'],
              ],
              fallback: '',
            ),
          )
          .where(
            (
              name,
            ) =>
                name.isNotEmpty,
          )
          .toList();

      if (names.isNotEmpty) {
        return names.join(
          ', ',
        );
      }
    }

    return 'Medication not captured';
  }

  String _dosageSummary(
    Map<String, dynamic> dispense,
  ) {
    final prescription = _prescriptionFor(
      dispense,
    );

    if (prescription == null) {
      return 'No dosage details';
    }

    final dosage = _firstText(
      [
        prescription['dosage'],
        prescription['dose'],
        prescription['dosage_amount'],
      ],
      fallback: '',
    );

    final dosageUnit = _firstText(
      [
        prescription['dosage_unit'],
      ],
      fallback: '',
    );

    final frequency = _firstText(
      [
        prescription['frequency'],
        prescription['dosage_frequency'],
        prescription['frequency_code'],
      ],
      fallback: '',
    );

    final duration = _firstText(
      [
        prescription['duration'],
        prescription['duration_days'],
        prescription['duration_value'],
      ],
      fallback: '',
    );

    final durationUnit = _firstText(
      [
        prescription['duration_unit'],
      ],
      fallback: '',
    );

    final doseText = [
      dosage,
      dosageUnit,
    ]
        .where(
          (
            part,
          ) =>
              part.isNotEmpty,
        )
        .join(
          ' ',
        );

    final durationText = [
      duration,
      durationUnit,
    ]
        .where(
          (
            part,
          ) =>
              part.isNotEmpty,
        )
        .join(
          ' ',
        );

    final parts = [
      doseText,
      frequency,
      durationText,
    ]
        .where(
          (
            part,
          ) =>
              part.isNotEmpty,
        )
        .toList();

    return parts.isEmpty
        ? 'No dosage details'
        : parts.join(
            ' • ',
          );
  }

  // ==========================================================================
  // STATUS
  // ==========================================================================

  String _status(
    Map<String, dynamic> dispense,
  ) {
    return _firstText(
      [
        dispense['status'],
      ],
      fallback: 'received',
    ).toLowerCase();
  }

  String _statusLabel(
    String status,
  ) {
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
        return status
            .replaceAll(
              '_',
              ' ',
            )
            .split(
              ' ',
            )
            .where(
              (
                word,
              ) =>
                  word.isNotEmpty,
            )
            .map(
              (
                word,
              ) =>
                  '${word[0].toUpperCase()}'
                  '${word.substring(1).toLowerCase()}',
            )
            .join(
              ' ',
            );
    }
  }

  Color _statusColor(
    String status,
  ) {
    switch (status) {
      case 'received':
        return CorviaColors.warning;

      case 'verified':
        return Colors.blue.shade700;

      case 'preparing':
        return Colors.deepPurple;

      case 'ready_for_collection':
        return CorviaColors.success;

      case 'collected':
        return Colors.teal.shade700;

      case 'unable_to_dispense':
      case 'cancelled':
        return CorviaColors.danger;

      default:
        return context.cAccentReadable;
    }
  }

  String _formatDate(
    dynamic value,
  ) {
    final date = DateTime.tryParse(
      value?.toString() ?? '',
    )?.toLocal();

    if (date == null) {
      return 'Date unavailable';
    }

    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/'
        '${date.year} '
        '${date.hour.toString().padLeft(2, '0')}:'
        '${date.minute.toString().padLeft(2, '0')}';
  }

  // ==========================================================================
  // FILTERING
  // ==========================================================================

  List<Map<String, dynamic>> get _visibleDispenses {
    final search = _searchController.text.trim().toLowerCase();

    return _dispenses.where(
      (
        dispense,
      ) {
        final status = _status(
          dispense,
        );

        final patient = _patientName(
          dispense,
        ).toLowerCase();

        final patientNumber = _patientNumber(
          dispense,
        ).toLowerCase();

        final medicine = _medicineName(
          dispense,
        ).toLowerCase();

        final reference = _firstText(
          [
            dispense['collection_reference'],
          ],
          fallback: '',
        ).toLowerCase();

        final matchesSearch = search.isEmpty ||
            patient.contains(
              search,
            ) ||
            patientNumber.contains(
              search,
            ) ||
            medicine.contains(
              search,
            ) ||
            reference.contains(
              search,
            );

        bool matchesFilter;

        switch (_selectedFilter) {
          case 'Received':
            matchesFilter = status == 'received';
            break;

          case 'Verified':
            matchesFilter = status == 'verified';
            break;

          case 'Preparing':
            matchesFilter = status == 'preparing';
            break;

          case 'Ready':
            matchesFilter = status == 'ready_for_collection';
            break;

          case 'Collected':
            matchesFilter = status == 'collected';
            break;

          case 'Problems':
            matchesFilter =
                status == 'unable_to_dispense' || status == 'cancelled';
            break;

          case 'All':
            matchesFilter = true;
            break;

          case 'Active':
          default:
            matchesFilter = status != 'collected' &&
                status != 'cancelled' &&
                status != 'unable_to_dispense';
        }

        return matchesSearch && matchesFilter;
      },
    ).toList();
  }

  int _countStatus(
    String status,
  ) {
    return _dispenses
        .where(
          (
            row,
          ) =>
              _status(
                row,
              ) ==
              status,
        )
        .length;
  }

  int get _problemCount {
    return _dispenses.where(
      (
        row,
      ) {
        final status = _status(
          row,
        );

        return status == 'unable_to_dispense' || status == 'cancelled';
      },
    ).length;
  }

  // ==========================================================================
  // SETTINGS
  // ==========================================================================

  Future<void> _openSettings() async {
    await pushWorkspace<void>(
      MaterialPageRoute<void>(
        builder: (_) {
          return const SettingsPage(showAppBar: false);
        },
      ),
      label: 'Settings',
    );
  }

  // ==========================================================================
  // PHARMACY FORM
  // ==========================================================================

  Future<void> _openPharmacyForm(
    Map<String, dynamic> dispense,
  ) async {
    if (_openingForm) {
      return;
    }

    final patientId = _cleanId(
      dispense['patient_id'],
    );

    final prescriptionId = _cleanId(
      dispense['prescription_id'],
    );

    final dispenseId = _cleanId(
      dispense['id'],
    );

    final hospitalId = _hospitalId;

    if (patientId == null) {
      _showMessage(
        'The patient ID is unavailable for this dispensing record.',
      );

      return;
    }

    if (hospitalId == null || hospitalId.isEmpty) {
      _showMessage(
        'The pharmacist hospital context is unavailable.',
      );

      return;
    }

    setState(() {
      _openingForm = true;
      _openingDispenseId = dispenseId;
    });

    try {
      final admissionId = await _resolveActiveAdmission(
        patientId: patientId,
        hospitalId: hospitalId,
      );

      if (!mounted) {
        return;
      }

      await CorviaFormsNavigator.openPatientForms(
        workspaceContext,
        patientId: patientId,
        hospitalId: hospitalId,
        admissionId: admissionId,
        contextType: 'pharmacy_dispensing',
        contextId: dispenseId ?? prescriptionId ?? patientId,
        title: 'Pharmacy Dispensing & Collection - '
            '${_patientName(dispense)}',
      );
    } catch (error) {
      if (mounted) {
        _showMessage(
          'Could not open the Pharmacy Dispensing '
          '& Collection Form. '
          '${_cleanError(error)}',
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _openingForm = false;
          _openingDispenseId = null;
        });
      }
    }
  }

  // ==========================================================================
  // ADMISSION RESOLUTION
  // ==========================================================================

  Future<String?> _resolveActiveAdmission({
    required String patientId,
    required String hospitalId,
  }) async {
    try {
      final response = await _supabase
          .from(
            'hospital_admissions',
          )
          .select()
          .eq(
            'patient_id',
            patientId,
          )
          .eq(
            'hospital_id',
            hospitalId,
          );

      final admissions = _rows(
        response,
      );

      if (admissions.isEmpty) {
        return null;
      }

      const priority = <String, int>{
        'admitted': 0,
        'active': 1,
        'in_progress': 2,
        'observation': 3,
        'planned': 4,
        'pending': 5,
      };

      admissions.sort(
        (
          first,
          second,
        ) {
          final firstStatus = _normaliseStatus(
            first['status'],
          );

          final secondStatus = _normaliseStatus(
            second['status'],
          );

          final firstPriority = priority[firstStatus] ?? 100;

          final secondPriority = priority[secondStatus] ?? 100;

          if (firstPriority != secondPriority) {
            return firstPriority.compareTo(
              secondPriority,
            );
          }

          final firstDate = _firstDate(
                first,
                const [
                  'admitted_at',
                  'planned_admission_at',
                  'updated_at',
                  'created_at',
                ],
              ) ??
              DateTime(
                1970,
              );

          final secondDate = _firstDate(
                second,
                const [
                  'admitted_at',
                  'planned_admission_at',
                  'updated_at',
                  'created_at',
                ],
              ) ??
              DateTime(
                1970,
              );

          return secondDate.compareTo(
            firstDate,
          );
        },
      );

      for (final admission in admissions) {
        final status = _normaliseStatus(
          admission['status'],
        );

        if (!priority.containsKey(
          status,
        )) {
          continue;
        }

        final admissionId = _cleanId(
          admission['id'],
        );

        if (admissionId != null) {
          return admissionId;
        }
      }

      return null;
    } catch (error) {
      debugPrint(
        'Pharmacy active admission lookup failed: $error',
      );

      return null;
    }
  }

  DateTime? _firstDate(
    Map<String, dynamic> row,
    List<String> columns,
  ) {
    for (final column in columns) {
      final value = row[column];

      if (value == null) {
        continue;
      }

      final parsed = DateTime.tryParse(
        value.toString(),
      );

      if (parsed != null) {
        return parsed;
      }
    }

    return null;
  }

  String _normaliseStatus(
    dynamic value,
  ) {
    return value
            ?.toString()
            .trim()
            .toLowerCase()
            .replaceAll(
              '-',
              '_',
            )
            .replaceAll(
              ' ',
              '_',
            ) ??
        '';
  }

  // ==========================================================================
  // DETAILS
  // ==========================================================================

  Future<void> _openPrescriptionDetails(
    Map<String, dynamic> dispense,
  ) async {
    final dispenseId = _cleanId(
      dispense['id'],
    );

    if (dispenseId == null) {
      _showMessage(
        'The dispensing record ID is unavailable.',
      );

      return;
    }

    final changed = await pushWorkspace<bool>(
      MaterialPageRoute<bool>(
        builder: (_) {
          return PharmacistPrescriptionDetailPage(
            dispenseId: dispenseId,
          );
        },
      ),
      label: 'Prescription details',
    );

    if (changed == true && mounted) {
      await _loadDashboard();
    }
  }

  // ==========================================================================
  // STATUS UPDATE
  // ==========================================================================

  Future<bool> _updateStatus({
    required Map<String, dynamic> dispense,
    required Map<String, dynamic> updates,
    required String successMessage,
  }) async {
    if (_saving) {
      return false;
    }

    final dispenseId = _cleanId(
      dispense['id'],
    );

    final newStatus = _firstText(
      [
        updates['status'],
      ],
      fallback: '',
    ).toLowerCase();

    if (dispenseId == null) {
      _showMessage(
        'Dispensing record ID is unavailable.',
      );

      return false;
    }

    if (newStatus.isEmpty) {
      _showMessage(
        'The new dispensing status is unavailable.',
      );

      return false;
    }

    if (!mounted) {
      return false;
    }

    setState(() {
      _saving = true;
    });

    try {
      final rpcResponse = await _supabase.rpc(
        'corvia_update_dispense_status',
        params: {
          'p_dispense_id': dispenseId,
          'p_new_status': newStatus,
          'p_verified_by_name': _nullableText(
            updates['verified_by_name'],
          ),
          'p_verification_method': _nullableText(
            updates['verification_method'],
          ),
          'p_collected_by_name': _nullableText(
            updates['collected_by_name'],
          ),
          'p_collector_relationship': _nullableText(
            updates['collector_relationship'],
          ),
          'p_unavailable_reason': _nullableText(
            updates['unavailable_reason'],
          ),
          'p_pharmacist_notes': _nullableText(
            updates['pharmacist_notes'],
          ),
          'p_collection_notes': _nullableText(
            updates['collection_notes'],
          ),
        },
      );

      if (rpcResponse is Map &&
          rpcResponse.containsKey(
            'success',
          ) &&
          rpcResponse['success'] != true) {
        throw Exception(
          rpcResponse['message']?.toString() ??
              'The pharmacy status update was not completed.',
        );
      }

      if (!mounted) {
        return true;
      }

      await _loadDashboard();

      if (mounted) {
        _showMessage(
          successMessage,
        );
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

  // ==========================================================================
  // CONFIRMATION
  // ==========================================================================

  Future<bool> _confirm({
    required String title,
    required String message,
    required String buttonText,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (
        dialogContext,
      ) {
        return AlertDialog(
          title: Text(
            title,
          ),
          content: Text(
            message,
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(
                  dialogContext,
                ).pop(
                  false,
                );
              },
              child: const Text(
                'Cancel',
              ),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(
                  dialogContext,
                ).pop(
                  true,
                );
              },
              child: Text(
                buttonText,
              ),
            ),
          ],
        );
      },
    );

    return result == true;
  }

  Future<void> _verify(
    Map<String, dynamic> dispense,
  ) async {
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
      dispense: dispense,
      updates: {
        'status': 'verified',
        'verified_by_name': _pharmacistName,
        'verification_method': 'Prescription and prescriber details checked',
      },
      successMessage: 'Prescription verified.',
    );
  }

  Future<void> _markPreparing(
    Map<String, dynamic> dispense,
  ) async {
    final confirmed = await _confirm(
      title: 'Start Preparing',
      message: 'Mark this medication as being prepared '
          'by the pharmacy?',
      buttonText: 'Start Preparing',
    );

    if (!confirmed || !mounted) {
      return;
    }

    await _updateStatus(
      dispense: dispense,
      updates: {
        'status': 'preparing',
      },
      successMessage: 'Medication is now being prepared.',
    );
  }

  Future<void> _markReady(
    Map<String, dynamic> dispense,
  ) async {
    final confirmed = await _confirm(
      title: 'Ready for Collection',
      message: 'Confirm that the medication is prepared '
          'and ready for collection.',
      buttonText: 'Mark Ready',
    );

    if (!confirmed || !mounted) {
      return;
    }

    await _updateStatus(
      dispense: dispense,
      updates: {
        'status': 'ready_for_collection',
      },
      successMessage: 'Medication marked ready for collection.',
    );
  }

  Future<void> _markCollected(
    Map<String, dynamic> dispense,
  ) async {
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
      dispense: dispense,
      updates: {
        'status': 'collected',
        'verified_by_name': result.collectorName,
        'verification_method': 'Identity confirmed at collection',
        'collected_by_name': result.collectorName,
        'collector_relationship': result.relationship,
        'collection_notes': result.notes.isEmpty ? null : result.notes,
      },
      successMessage: 'Medication collection confirmed.',
    );
  }

  Future<void> _markUnable(
    Map<String, dynamic> dispense,
  ) async {
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
      dispense: dispense,
      updates: {
        'status': 'unable_to_dispense',
        'unavailable_reason': reason.trim(),
        'pharmacist_notes': reason.trim(),
      },
      successMessage: 'Prescription marked unable to dispense.',
    );
  }

  Future<void> _performNextAction(
    Map<String, dynamic> dispense,
  ) async {
    switch (_status(dispense)) {
      case 'received':
        await _verify(
          dispense,
        );
        break;

      case 'verified':
        await _markPreparing(
          dispense,
        );
        break;

      case 'preparing':
        await _markReady(
          dispense,
        );
        break;

      case 'ready_for_collection':
        await _markCollected(
          dispense,
        );
        break;

      default:
        _showMessage(
          'No next action is available for this status.',
        );
    }
  }

  String? _nextActionLabel(
    String status,
  ) {
    switch (status) {
      case 'received':
        return 'Verify';

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

  IconData _nextActionIcon(
    String status,
  ) {
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

  // ==========================================================================
  // MESSAGES
  // ==========================================================================

  void _showMessage(
    String message,
  ) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            message,
          ),
        ),
      );
  }

  // ==========================================================================
  // SIGN OUT
  // ==========================================================================

  Future<void> _signOut() async {
    if (_signingOut) {
      return;
    }

    setState(() {
      _signingOut = true;
    });

    try {
      SettingsService.instance.sessionUnlocked = false;

      await _supabase.auth.signOut();

      if (!mounted) {
        return;
      }

      Navigator.of(context).popUntil(
        (
          route,
        ) =>
            route.isFirst,
      );
    } catch (error) {
      _showMessage(
        'Sign out failed. '
        '${_cleanError(error)}',
      );
    } finally {
      if (mounted) {
        setState(() {
          _signingOut = false;
        });
      }
    }
  }

  // ==========================================================================
  // BUILD
  // ==========================================================================

  static const Map<String, IconData> _filterIcons = {
    'Active': Icons.pending_actions_rounded,
    'Received': Icons.inbox_rounded,
    'Verified': Icons.verified_outlined,
    'Preparing': Icons.medication_rounded,
    'Ready': Icons.inventory_2_outlined,
    'Collected': Icons.task_alt_rounded,
    'Problems': Icons.report_problem_outlined,
    'All': Icons.list_alt_rounded,
  };

  @override
  Widget build(
    BuildContext context,
  ) {
    final busy = _loading || _saving;

    return StaffWorkspaceShell(
      workspaceName: 'Hospital Pharmacy',
      breadcrumb: 'Pharmacy',
      pageTitle: workspaceTitle ?? 'Prescriptions · $_selectedFilter',
      subtitle: _hospitalName,
      onSignOut: _signingOut ? null : _signOut,
      headerActions: [
        if (workspaceCanPop)
          workspaceBackButton
        else
          OutlinedButton.icon(
            onPressed: busy ? null : _loadDashboard,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Refresh'),
          ),
      ],
      items: [
        for (final filter in _filters)
          StaffShellItem(
            label: filter == 'Active' ? 'Active queue' : filter,
            icon: _filterIcons[filter] ?? Icons.list_alt_rounded,
            selected: !workspaceCanPop && _selectedFilter == filter,
            onTap: () {
              workspaceHome();
              setState(() => _selectedFilter = filter);
            },
          ),
        StaffShellItem(
          label: 'Settings',
          selected: workspaceSelection == 'Settings',
          icon: Icons.settings_rounded,
          onTap: busy ? null : _openSettings,
        ),
      ],
      body: workspaceBody(_buildBody()),
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

    final visible = _visibleDispenses;

    return RefreshIndicator(
      onRefresh: _loadDashboard,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(
          20,
        ),
        children: [
          _buildWelcomeCard(),
          const SizedBox(
            height: 20,
          ),
          _buildStats(),
          const SizedBox(
            height: 18,
          ),
          const SizedBox(
            height: 4,
          ),
          TextField(
            controller: _searchController,
            onChanged: (
              _,
            ) {
              setState(
                () {},
              );
            },
            decoration: InputDecoration(
              hintText: 'Search patient, medicine, patient number or reference',
              prefixIcon: const Icon(
                Icons.search,
              ),
              suffixIcon: _searchController.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear search',
                      onPressed: () {
                        _searchController.clear();

                        setState(
                          () {},
                        );
                      },
                      icon: const Icon(
                        Icons.clear,
                      ),
                    ),
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(
            height: 14,
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _filters.map(
              (
                filter,
              ) {
                return ChoiceChip(
                  label: Text(
                    filter,
                  ),
                  selected: _selectedFilter == filter,
                  onSelected: (
                    _,
                  ) {
                    setState(() {
                      _selectedFilter = filter;
                    });
                  },
                );
              },
            ).toList(),
          ),
          const SizedBox(
            height: 20,
          ),
          Text(
            'Prescription Queue (${visible.length})',
            style: TextStyle(
              color: context.cTextPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(
            height: 12,
          ),
          if (visible.isEmpty)
            _buildEmptyState()
          else
            ...visible.map(
              _buildDispenseCard,
            ),
          const SizedBox(
            height: 24,
          ),
        ],
      ),
    );
  }

  // ==========================================================================
  // WELCOME
  // ==========================================================================

  Widget _buildWelcomeCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(
        20,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            CorviaColors.accentDark,
            CorviaColors.accent,
          ],
        ),
        borderRadius: BorderRadius.circular(
          22,
        ),
      ),
      child: Row(
        children: [
          const CircleAvatar(
            radius: 29,
            backgroundColor: Colors.white,
            child: Icon(
              Icons.local_pharmacy_outlined,
              size: 30,
              color: Color(
                0xFF0F766E,
              ),
            ),
          ),
          const SizedBox(
            width: 14,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Welcome',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                  ),
                ),
                Text(
                  _pharmacistName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 21,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(
                  height: 3,
                ),
                Text(
                  _hospitalName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const Icon(
            Icons.verified_outlined,
            color: Colors.white,
          ),
        ],
      ),
    );
  }

  // ==========================================================================
  // WORKSPACE ACTIONS
  // ==========================================================================

  // ==========================================================================
  // STATS
  // ==========================================================================

  Widget _buildStats() {
    final cards = [
      _StatData(
        label: 'Received',
        value: _countStatus(
          'received',
        ),
        icon: Icons.inbox_outlined,
        color: CorviaColors.warning,
      ),
      _StatData(
        label: 'Preparing',
        value: _countStatus(
          'preparing',
        ),
        icon: Icons.medication_outlined,
        color: Colors.deepPurple,
      ),
      _StatData(
        label: 'Ready',
        value: _countStatus(
          'ready_for_collection',
        ),
        icon: Icons.inventory_2_outlined,
        color: CorviaColors.success,
      ),
      _StatData(
        label: 'Collected',
        value: _countStatus(
          'collected',
        ),
        icon: Icons.check_circle_outline,
        color: Colors.teal,
      ),
      _StatData(
        label: 'Problems',
        value: _problemCount,
        icon: Icons.warning_amber_rounded,
        color: CorviaColors.danger,
      ),
    ];

    return LayoutBuilder(
      builder: (
        context,
        constraints,
      ) {
        final width = constraints.maxWidth;

        final columns = width >= 1100
            ? 5
            : width >= 850
                ? 4
                : width >= 520
                    ? 2
                    : 1;

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: cards.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            mainAxisExtent: 125,
          ),
          itemBuilder: (
            context,
            index,
          ) {
            final card = cards[index];

            return Container(
              padding: const EdgeInsets.all(
                16,
              ),
              decoration: BoxDecoration(
                color: context.cBgSecondary,
                borderRadius: BorderRadius.circular(
                  18,
                ),
                border: Border.all(
                  color: context.cDivider,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: card.color.withValues(
                        alpha: 0.12,
                      ),
                      borderRadius: BorderRadius.circular(
                        14,
                      ),
                    ),
                    child: Icon(
                      card.icon,
                      color: card.color,
                    ),
                  ),
                  const SizedBox(
                    width: 14,
                  ),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          card.value.toString(),
                          style: TextStyle(
                            color: context.cTextPrimary,
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          card.label,
                          style: TextStyle(
                            color: context.cTextSecondary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // ==========================================================================
  // DISPENSE CARD
  // ==========================================================================

  Widget _buildDispenseCard(
    Map<String, dynamic> dispense,
  ) {
    final status = _status(
      dispense,
    );

    final statusColor = _statusColor(
      status,
    );

    final nextAction = _nextActionLabel(
      status,
    );

    final reference = _firstText(
      [
        dispense['collection_reference'],
      ],
      fallback: 'No collection reference',
    );

    final canMarkProblem = status != 'collected' &&
        status != 'cancelled' &&
        status != 'unable_to_dispense';

    final dispenseId = _cleanId(
      dispense['id'],
    );

    final openingForm =
        _openingForm && dispenseId != null && _openingDispenseId == dispenseId;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(
        bottom: 12,
      ),
      padding: const EdgeInsets.all(
        17,
      ),
      decoration: BoxDecoration(
        color: context.cBgSecondary,
        borderRadius: BorderRadius.circular(
          18,
        ),
        border: Border.all(
          color: context.cDivider,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: statusColor.withValues(
                    alpha: 0.12,
                  ),
                  borderRadius: BorderRadius.circular(
                    15,
                  ),
                ),
                child: Icon(
                  Icons.local_pharmacy_outlined,
                  color: statusColor,
                ),
              ),
              const SizedBox(
                width: 13,
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _patientName(
                        dispense,
                      ),
                      style: TextStyle(
                        color: context.cTextPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(
                      height: 3,
                    ),
                    Text(
                      _patientNumber(
                        dispense,
                      ),
                      style: TextStyle(
                        color: context.cTextMuted,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(
                      height: 6,
                    ),
                    Text(
                      _medicineName(
                        dispense,
                      ),
                      style: TextStyle(
                        color: context.cTextSecondary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(
                      height: 3,
                    ),
                    Text(
                      _dosageSummary(
                        dispense,
                      ),
                      style: TextStyle(
                        color: context.cTextMuted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(
                width: 8,
              ),
              _StatusPill(
                label: _statusLabel(
                  status,
                ),
                color: statusColor,
              ),
            ],
          ),
          const SizedBox(
            height: 14,
          ),
          Divider(
            color: context.cDivider,
          ),
          const SizedBox(
            height: 8,
          ),
          Wrap(
            spacing: 16,
            runSpacing: 8,
            children: [
              _InfoText(
                icon: Icons.qr_code_2,
                text: reference,
              ),
              _InfoText(
                icon: Icons.schedule,
                text: _formatDate(
                  dispense['received_at'],
                ),
              ),
            ],
          ),
          const SizedBox(
            height: 15,
          ),
          LayoutBuilder(
            builder: (
              context,
              constraints,
            ) {
              final compact = constraints.maxWidth < 760;

              final detailsButton = OutlinedButton.icon(
                onPressed: _saving || _openingForm
                    ? null
                    : () {
                        _openPrescriptionDetails(
                          dispense,
                        );
                      },
                icon: const Icon(
                  Icons.visibility_outlined,
                ),
                label: const Text(
                  'View Details',
                ),
              );

              final formButton = FilledButton.icon(
                onPressed: _saving || _openingForm
                    ? null
                    : () {
                        _openPharmacyForm(
                          dispense,
                        );
                      },
                icon: openingForm
                    ? const SizedBox(
                        width: 17,
                        height: 17,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                        ),
                      )
                    : const Icon(
                        Icons.description_outlined,
                      ),
                label: Text(
                  openingForm ? 'Opening Form...' : 'Pharmacy Form',
                ),
              );

              final nextButton = nextAction == null
                  ? OutlinedButton(
                      onPressed: null,
                      child: Text(
                        _statusLabel(
                          status,
                        ),
                      ),
                    )
                  : ElevatedButton.icon(
                      onPressed: _saving
                          ? null
                          : () {
                              _performNextAction(
                                dispense,
                              );
                            },
                      icon: Icon(
                        _nextActionIcon(
                          status,
                        ),
                      ),
                      label: Text(
                        nextAction,
                      ),
                    );

              final problemButton = canMarkProblem
                  ? OutlinedButton.icon(
                      onPressed: _saving
                          ? null
                          : () {
                              _markUnable(
                                dispense,
                              );
                            },
                      icon: const Icon(
                        Icons.report_problem_outlined,
                      ),
                      label: const Text(
                        'Problem',
                      ),
                    )
                  : null;

              if (compact) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    detailsButton,
                    const SizedBox(
                      height: 10,
                    ),
                    formButton,
                    const SizedBox(
                      height: 10,
                    ),
                    nextButton,
                    if (problemButton != null) ...[
                      const SizedBox(
                        height: 10,
                      ),
                      problemButton,
                    ],
                  ],
                );
              }

              return Row(
                children: [
                  Expanded(
                    child: detailsButton,
                  ),
                  const SizedBox(
                    width: 10,
                  ),
                  Expanded(
                    child: formButton,
                  ),
                  const SizedBox(
                    width: 10,
                  ),
                  Expanded(
                    child: nextButton,
                  ),
                  if (problemButton != null) ...[
                    const SizedBox(
                      width: 10,
                    ),
                    Expanded(
                      child: problemButton,
                    ),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  // ==========================================================================
  // EMPTY / ERROR
  // ==========================================================================

  Widget _buildEmptyState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(
        36,
      ),
      decoration: BoxDecoration(
        color: context.cBgSecondary,
        borderRadius: BorderRadius.circular(
          18,
        ),
        border: Border.all(
          color: context.cDivider,
        ),
      ),
      child: Column(
        children: [
          Icon(
            Icons.inventory_2_outlined,
            size: 46,
            color: context.cAccentReadable,
          ),
          const SizedBox(
            height: 12,
          ),
          Text(
            'No prescriptions found',
            style: TextStyle(
              color: context.cTextPrimary,
              fontSize: 17,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(
            height: 6,
          ),
          Text(
            'No pharmacy queue records match the '
            'selected filter or search.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: context.cTextSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(
          24,
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: 540,
          ),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(
              24,
            ),
            decoration: BoxDecoration(
              color: context.cBgSecondary,
              borderRadius: BorderRadius.circular(
                22,
              ),
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
                  size: 58,
                ),
                const SizedBox(
                  height: 16,
                ),
                Text(
                  'Pharmacist access could not load',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: context.cTextPrimary,
                    fontSize: 21,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(
                  height: 12,
                ),
                SelectableText(
                  _error ?? 'Unknown pharmacy error.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: context.cTextSecondary,
                    height: 1.4,
                  ),
                ),
                const SizedBox(
                  height: 22,
                ),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _loadDashboard,
                    icon: const Icon(
                      Icons.refresh,
                    ),
                    label: const Text(
                      'Try Again',
                    ),
                  ),
                ),
                const SizedBox(
                  height: 10,
                ),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _signOut,
                    icon: const Icon(
                      Icons.logout,
                    ),
                    label: const Text(
                      'Sign Out',
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

// =============================================================================
// COLLECTION DIALOG
// =============================================================================

class _CollectionDialog extends StatefulWidget {
  const _CollectionDialog();

  @override
  State<_CollectionDialog> createState() {
    return _CollectionDialogState();
  }
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
  Widget build(
    BuildContext context,
  ) {
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
              const SizedBox(
                height: 12,
              ),
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
              const SizedBox(
                height: 12,
              ),
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

// =============================================================================
// UNABLE TO DISPENSE DIALOG
// =============================================================================

class _UnableToDispenseDialog extends StatefulWidget {
  const _UnableToDispenseDialog();

  @override
  State<_UnableToDispenseDialog> createState() {
    return _UnableToDispenseDialogState();
  }
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

    Navigator.of(context).pop(
      reason,
    );
  }

  @override
  Widget build(
    BuildContext context,
  ) {
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

// =============================================================================
// SMALL MODELS
// =============================================================================

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

class _StatData {
  const _StatData({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final int value;
  final IconData icon;
  final Color color;
}

// =============================================================================
// STATUS PILL
// =============================================================================

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.label,
    required this.color,
  });

  final String label;
  final Color color;

  @override
  Widget build(
    BuildContext context,
  ) {
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
        borderRadius: BorderRadius.circular(
          999,
        ),
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

// =============================================================================
// INFO TEXT
// =============================================================================

class _InfoText extends StatelessWidget {
  const _InfoText({
    required this.icon,
    required this.text,
  });

  final IconData icon;
  final String text;

  @override
  Widget build(
    BuildContext context,
  ) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 16,
          color: context.cTextSecondary,
        ),
        const SizedBox(
          width: 6,
        ),
        Flexible(
          child: Text(
            text,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: context.cTextSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}
