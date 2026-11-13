import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mycorvia/services/supabase_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../theme/app_theme.dart';
import '../../utils/error_messages.dart';

/// Patient-facing page for confidential doctor reports.
///
/// Secure flow:
/// - Resolves the real Corvia patient record.
/// - Only shows doctors linked to the patient's care history.
/// - Submits through `corvia_submit_doctor_report`.
/// - Does NOT directly insert into `doctor_reports`.
/// - Prevents duplicate taps.
/// - Has network timeout protection.
/// - Always releases loading state.
/// - Supports hiding patient identity from the reported doctor.
///
/// Important:
/// `anonymous` means hidden from the reported doctor.
/// Authorized hospital governance/admin staff still retain the patient's
/// identity internally for investigation and safety purposes.
class ReportADoctorPage extends StatefulWidget {
  const ReportADoctorPage({
    super.key,
    this.initialDoctorId,
    this.initialDoctorName,
  });

  final String? initialDoctorId;
  final String? initialDoctorName;

  @override
  State<ReportADoctorPage> createState() {
    return _ReportADoctorPageState();
  }
}

class _ReportADoctorPageState extends State<ReportADoctorPage> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  final TextEditingController _descriptionCtrl = TextEditingController();

  final SupabaseClient _supabase = Supabase.instance.client;

  static const Duration _networkTimeout = Duration(
    seconds: 25,
  );

  static const List<String> _complaintReasons = [
    'Unprofessional conduct',
    'Long wait times',
    'Misdiagnosis or incorrect treatment',
    'Poor communication',
    'Billing or insurance issue',
    'Prescription error',
    'Other',
  ];

  List<Map<String, dynamic>> _realDoctors = [];

  String? _selectedDoctorId;
  String? _selectedReason;

  bool _hideIdentityFromDoctor = false;

  bool _isLoadingDoctors = true;
  bool _isSubmitting = false;

  String? _doctorLoadError;

  @override
  void initState() {
    super.initState();

    final initialDoctorId = widget.initialDoctorId?.trim();

    if (initialDoctorId != null && initialDoctorId.isNotEmpty) {
      _selectedDoctorId = initialDoctorId;
      _realDoctors = [
        {
          'id': initialDoctorId,
          'full_name': widget.initialDoctorName?.trim().isNotEmpty == true
              ? widget.initialDoctorName!.trim()
              : 'Doctor',
        },
      ];
      _isLoadingDoctors = false;
    } else {
      _loadDoctors();
    }
  }

  @override
  void dispose() {
    _descriptionCtrl.dispose();

    super.dispose();
  }

  // ==========================================================================
  // DOCTORS
  // ==========================================================================

  Future<void> _loadDoctors() async {
    if (_isSubmitting) {
      return;
    }

    if (mounted) {
      setState(() {
        _isLoadingDoctors = true;
        _doctorLoadError = null;
      });
    }

    try {
      final currentUser = _supabase.auth.currentUser;

      if (currentUser == null) {
        throw Exception(
          'Your Corvia session has expired. Please sign in again.',
        );
      }

      // ----------------------------------------------------------------------
      // Resolve the real patients.id value.
      //
      // Never use auth.users.id directly as doctor_reports.patient_id.
      // ----------------------------------------------------------------------

      final patientId = await SupabaseService.currentPatientId().timeout(
        _networkTimeout,
      );

      if (patientId == null || patientId.trim().isEmpty) {
        throw Exception(
          'Your Corvia account is not linked to a patient record.',
        );
      }

      final cleanPatientId = patientId.trim();

      // ----------------------------------------------------------------------
      // Build the set of doctors who actually have a Corvia care relationship
      // with this patient.
      //
      // The secure backend RPC verifies this again at submission time.
      // ----------------------------------------------------------------------

      final doctorIds = <String>{};

      await _collectDoctorIds(
        table: 'appointments',
        patientId: cleanPatientId,
        doctorColumn: 'doctor_id',
        target: doctorIds,
      );

      await _collectDoctorIds(
        table: 'prescriptions',
        patientId: cleanPatientId,
        doctorColumn: 'doctor_id',
        target: doctorIds,
      );

      await _collectDoctorIds(
        table: 'specialist_requests',
        patientId: cleanPatientId,
        doctorColumn: 'assigned_doctor_id',
        target: doctorIds,
      );

      await _collectDoctorIds(
        table: 'reception_checkins',
        patientId: cleanPatientId,
        doctorColumn: 'assigned_doctor_id',
        target: doctorIds,
      );

      if (doctorIds.isEmpty) {
        if (!mounted) {
          return;
        }

        setState(() {
          _realDoctors = [];
          _selectedDoctorId = null;
          _isLoadingDoctors = false;
          _doctorLoadError = null;
        });

        return;
      }

      final data = await SupabaseService.getDoctors().timeout(
        _networkTimeout,
      );

      final doctors = data
          .where(
            (doctor) {
              final id = doctor['id']?.toString().trim();

              if (id == null || id.isEmpty) {
                return false;
              }

              if (!doctorIds.contains(id)) {
                return false;
              }

              final isActive = doctor['is_active'];

              if (isActive == false) {
                return false;
              }

              final status = (doctor['status'] ?? '')
                  .toString()
                  .trim()
                  .toLowerCase();

              if ({
                'inactive',
                'disabled',
                'suspended',
                'terminated',
              }.contains(status)) {
                return false;
              }

              return true;
            },
          )
          .map(
            (doctor) => Map<String, dynamic>.from(
              doctor,
            ),
          )
          .toList();

      doctors.sort(
        (first, second) {
          return _doctorLabel(first).toLowerCase().compareTo(
                _doctorLabel(second).toLowerCase(),
              );
        },
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _realDoctors = doctors;

        if (_selectedDoctorId != null &&
            !_realDoctors.any(
              (doctor) =>
                  doctor['id']?.toString().trim() == _selectedDoctorId,
            )) {
          _selectedDoctorId = null;
        }

        _isLoadingDoctors = false;
        _doctorLoadError = null;
      });
    } on TimeoutException {
      if (!mounted) {
        return;
      }

      setState(() {
        _realDoctors = [];
        _isLoadingDoctors = false;
        _doctorLoadError =
            'Loading doctors timed out. Please check your connection.';
      });
    } catch (error) {
      debugPrint(
        'Report Doctor doctor-list error: $error',
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _realDoctors = [];
        _isLoadingDoctors = false;
        _doctorLoadError = friendlyErrorMessage(
          error,
          whatFailed: 'Doctors could not be loaded.',
        );
      });
    }
  }

  Future<void> _collectDoctorIds({
    required String table,
    required String patientId,
    required String doctorColumn,
    required Set<String> target,
  }) async {
    try {
      final rows = await _supabase
          .from(table)
          .select(doctorColumn)
          .eq(
            'patient_id',
            patientId,
          )
          .timeout(
            _networkTimeout,
          );

      for (final row in rows) {
        final doctorId = row[doctorColumn]?.toString().trim();

        if (doctorId == null ||
            doctorId.isEmpty ||
            doctorId.toLowerCase() == 'null') {
          continue;
        }

        target.add(
          doctorId,
        );
      }
    } catch (error) {
      // One legacy relationship source failing should not prevent
      // the remaining valid relationship sources from loading.
      debugPrint(
        'Report Doctor relationship lookup failed for $table: $error',
      );
    }
  }

  String _doctorLabel(
    Map<String, dynamic> doctor,
  ) {
    final name = _firstText(
      [
        doctor['full_name'],
        doctor['display_name'],
        doctor['name'],
        _combinedDoctorName(
          doctor,
        ),
      ],
      fallback: 'Doctor',
    );

    final specialty = _firstText(
      [
        doctor['specialization'],
        doctor['specialty'],
        doctor['speciality'],
      ],
      fallback: '',
    );

    final location = _firstText(
      [
        doctor['location'],
        doctor['hospital_name'],
        doctor['practice_name'],
        doctor['department_name'],
        doctor['department'],
      ],
      fallback: '',
    );

    final extraParts = <String>[
      if (specialty.isNotEmpty) specialty,
      if (location.isNotEmpty &&
          location.toLowerCase() != specialty.toLowerCase())
        location,
    ];

    if (extraParts.isEmpty) {
      return name;
    }

    return '$name - ${extraParts.join(' · ')}';
  }

  String _combinedDoctorName(
    Map<String, dynamic> doctor,
  ) {
    final firstName = _firstText(
      [
        doctor['first_name'],
        doctor['firstname'],
        doctor['given_name'],
      ],
      fallback: '',
    );

    final surname = _firstText(
      [
        doctor['surname'],
        doctor['last_name'],
        doctor['lastname'],
        doctor['family_name'],
      ],
      fallback: '',
    );

    return '$firstName $surname'.trim();
  }

  String _firstText(
    List<dynamic> values, {
    required String fallback,
  }) {
    for (final value in values) {
      if (value != null && value.toString().trim().isNotEmpty) {
        return value.toString().trim();
      }
    }

    return fallback;
  }

  // ==========================================================================
  // SUBMISSION
  // ==========================================================================

  Future<void> _submitReport() async {
    if (_isSubmitting) {
      return;
    }

    FocusScope.of(context).unfocus();

    final formState = _formKey.currentState;

    if (formState == null || !formState.validate()) {
      return;
    }

    final doctorId = _selectedDoctorId?.trim();
    final reason = _selectedReason?.trim();
    final description = _descriptionCtrl.text.trim();

    if (doctorId == null || doctorId.isEmpty) {
      _showMessage(
        'Please select a doctor.',
      );

      return;
    }

    if (!_realDoctors.any(
      (doctor) => doctor['id']?.toString().trim() == doctorId,
    )) {
      _showMessage(
        'The selected doctor is no longer available. '
        'Please refresh the doctor list.',
      );

      return;
    }

    if (reason == null || reason.isEmpty) {
      _showMessage(
        'Please select a reason for the complaint.',
      );

      return;
    }

    if (description.length < 10) {
      _showMessage(
        'Please provide at least 10 characters describing your experience.',
      );

      return;
    }

    if (description.length > 5000) {
      _showMessage(
        'The description cannot exceed 5000 characters.',
      );

      return;
    }

    final currentUser = _supabase.auth.currentUser;

    if (currentUser == null) {
      _showMessage(
        'Your Corvia session has expired. Please sign in again.',
      );

      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    try {
      // ----------------------------------------------------------------------
      // IMPORTANT:
      //
      // Do NOT use:
      //
      //   .from('doctor_reports').insert(...)
      //
      // All patient report creation now goes through the secure RPC.
      // ----------------------------------------------------------------------

      final result = await _supabase
          .rpc(
            'corvia_submit_doctor_report',
            params: {
              'p_doctor_id': doctorId,
              'p_category': reason,
              'p_details': description,
              'p_anonymous_to_doctor': _hideIdentityFromDoctor,
            },
          )
          .timeout(
            _networkTimeout,
          );

      final reportId = result?.toString().trim();

      if (!mounted) {
        return;
      }

      setState(() {
        _isSubmitting = false;
      });

      await _showSuccessDialog(
        reportId: reportId == null ||
                reportId.isEmpty ||
                reportId.toLowerCase() == 'null'
            ? null
            : reportId,
      );
    } on TimeoutException catch (error) {
      debugPrint(
        'Report Doctor timeout: $error',
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _isSubmitting = false;
      });

      _showMessage(
        'The report submission timed out. '
        'Please check your connection and try again.',
      );
    } on PostgrestException catch (error) {
      debugPrint(
        'Report Doctor database error: '
        '${error.message} | Code: ${error.code}',
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _isSubmitting = false;
      });

      _showMessage(
        friendlyErrorMessage(
          error,
          whatFailed: 'The report could not be submitted.',
        ),
      );
    } on AuthException catch (error) {
      debugPrint(
        'Report Doctor authentication error: ${error.message}',
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _isSubmitting = false;
      });

      _showMessage(
        'Your Corvia session could not be verified. '
        'Please sign in again.',
      );
    } catch (error) {
      debugPrint(
        'Report Doctor submission error: $error',
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _isSubmitting = false;
      });

      _showMessage(
        friendlyErrorMessage(
          error,
          whatFailed: 'The report could not be submitted.',
        ),
      );
    } finally {
      // ----------------------------------------------------------------------
      // Absolute safety net:
      // The button must never remain stuck in "Submitting...".
      // ----------------------------------------------------------------------

      if (mounted && _isSubmitting) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  Future<void> _showSuccessDialog({
    String? reportId,
  }) async {
    if (!mounted) {
      return;
    }

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (
        dialogContext,
      ) {
        return AlertDialog(
          backgroundColor: context.cBgSecondary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(
              16,
            ),
          ),
          title: Row(
            children: [
              Icon(
                Icons.check_circle_rounded,
                color: CorviaColors.success,
              ),
              const SizedBox(
                width: 10,
              ),
              Expanded(
                child: Text(
                  'Report Submitted',
                  style: TextStyle(
                    color: context.cTextPrimary,
                  ),
                ),
              ),
            ],
          ),
          content: Text(
            _hideIdentityFromDoctor
                ? 'Your report has been submitted securely. '
                    'Your identity will be hidden from the reported doctor, '
                    'but authorized hospital reviewers can still identify '
                    'the submitting patient when required.'
                : 'Your report has been submitted securely to the hospital '
                    'administration team for review.',
            style: TextStyle(
              color: context.cTextSecondary,
              height: 1.5,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(
                  dialogContext,
                ).pop();
              },
              child: Text(
                'Done',
                style: TextStyle(
                  color: context.cAccentReadable,
                ),
              ),
            ),
          ],
        );
      },
    );

    if (!mounted) {
      return;
    }

    Navigator.of(context).pop(
      true,
    );
  }

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
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  // ==========================================================================
  // BUILD
  // ==========================================================================

  @override
  Widget build(
    BuildContext context,
  ) {
    return Scaffold(
      backgroundColor: context.cBgPrimary,
      appBar: AppBar(
        backgroundColor: context.cBgSecondary,
        elevation: 0,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_ios_new_rounded,
            color: context.cTextPrimary,
            size: 18,
          ),
          onPressed: _isSubmitting
              ? null
              : () {
                  Navigator.maybePop(
                    context,
                  );
                },
        ),
        title: Text(
          'Report a Doctor',
          style: TextStyle(
            color: context.cTextPrimary,
            fontWeight: FontWeight.w700,
            fontSize: 18,
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: 'Refresh doctors',
            onPressed: _isSubmitting || _isLoadingDoctors
                ? null
                : _loadDoctors,
            icon: Icon(
              Icons.refresh_rounded,
              color: context.cTextPrimary,
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            20,
            20,
            20,
            40,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: 760,
              ),
              child: Form(
                key: _formKey,
                autovalidateMode: AutovalidateMode.onUserInteraction,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _IntroBlock(),

                    const SizedBox(
                      height: 28,
                    ),

                    // ========================================================
                    // DOCTOR
                    // ========================================================

                    const _FieldLabel(
                      'Doctor',
                      required: true,
                    ),

                    const SizedBox(
                      height: 8,
                    ),

                    _buildDoctorField(),

                    const SizedBox(
                      height: 22,
                    ),

                    // ========================================================
                    // REASON
                    // ========================================================

                    const _FieldLabel(
                      'Reason for Complaint',
                      required: true,
                    ),

                    const SizedBox(
                      height: 8,
                    ),

                    _DropdownField<String>(
                      hint: 'Select Reason',
                      value: _selectedReason,
                      items: _complaintReasons,
                      icon: Icons.report_gmailerrorred_outlined,
                      enabled: !_isSubmitting,
                      onChanged: (
                        value,
                      ) {
                        setState(() {
                          _selectedReason = value;
                        });
                      },
                      validator: (
                        value,
                      ) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Please select a reason for the complaint.';
                        }

                        return null;
                      },
                    ),

                    const SizedBox(
                      height: 22,
                    ),

                    // ========================================================
                    // DESCRIPTION
                    // ========================================================

                    const _FieldLabel(
                      'Describe Your Experience',
                      required: true,
                    ),

                    const SizedBox(
                      height: 8,
                    ),

                    _DescriptionField(
                      controller: _descriptionCtrl,
                      enabled: !_isSubmitting,
                    ),

                    const SizedBox(
                      height: 22,
                    ),

                    // ========================================================
                    // ANONYMITY
                    // ========================================================

                    _CheckRow(
                      label:
                          'Hide my identity from the reported doctor',
                      subtitle:
                          'Authorized hospital reviewers can still identify you for governance and investigation purposes.',
                      value: _hideIdentityFromDoctor,
                      enabled: !_isSubmitting,
                      onChanged: (
                        value,
                      ) {
                        setState(() {
                          _hideIdentityFromDoctor = value ?? false;
                        });
                      },
                    ),

                    const SizedBox(
                      height: 22,
                    ),

                    const _ConfidentialNotice(),

                    const SizedBox(
                      height: 28,
                    ),

                    _SubmitButton(
                      isSubmitting: _isSubmitting,
                      enabled: !_isLoadingDoctors &&
                          _doctorLoadError == null &&
                          _realDoctors.isNotEmpty,
                      onPressed: _submitReport,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDoctorField() {
    final initialDoctorId = widget.initialDoctorId?.trim();

    if (initialDoctorId != null && initialDoctorId.isNotEmpty) {
      final doctorName = widget.initialDoctorName?.trim();

      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(
          14,
        ),
        decoration: BoxDecoration(
          color: context.cBgSecondary,
          borderRadius: BorderRadius.circular(
            12,
          ),
          border: Border.all(
            color: context.cDivider,
          ),
        ),
        child: Row(
          children: [
            Icon(
              Icons.medical_services_outlined,
              color: context.cAccentReadable,
            ),
            const SizedBox(
              width: 12,
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    doctorName == null || doctorName.isEmpty
                        ? 'Doctor'
                        : doctorName,
                    style: TextStyle(
                      color: context.cTextPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(
                    height: 3,
                  ),
                  Text(
                    'Selected from your completed appointment',
                    style: TextStyle(
                      color: context.cTextSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.lock_outline_rounded,
              size: 18,
              color: context.cTextSecondary,
            ),
          ],
        ),
      );
    }

    if (_isLoadingDoctors) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(
          16,
        ),
        decoration: BoxDecoration(
          color: context.cBgSecondary,
          borderRadius: BorderRadius.circular(
            12,
          ),
          border: Border.all(
            color: context.cDivider,
          ),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: context.cAccentReadable,
              ),
            ),
            const SizedBox(
              width: 12,
            ),
            Expanded(
              child: Text(
                'Loading doctors from your care history...',
                style: TextStyle(
                  color: context.cTextSecondary,
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (_doctorLoadError != null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(
          14,
        ),
        decoration: BoxDecoration(
          color: CorviaColors.danger.withValues(
            alpha: 0.08,
          ),
          borderRadius: BorderRadius.circular(
            12,
          ),
          border: Border.all(
            color: CorviaColors.danger.withValues(
              alpha: 0.35,
            ),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _doctorLoadError!,
              style: TextStyle(
                color: context.cTextPrimary,
              ),
            ),
            const SizedBox(
              height: 10,
            ),
            TextButton.icon(
              onPressed: _loadDoctors,
              icon: const Icon(
                Icons.refresh,
              ),
              label: const Text(
                'Try Again',
              ),
            ),
          ],
        ),
      );
    }

    if (_realDoctors.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(
          14,
        ),
        decoration: BoxDecoration(
          color: CorviaColors.accent.withValues(
            alpha: 0.08,
          ),
          borderRadius: BorderRadius.circular(
            12,
          ),
          border: Border.all(
            color: CorviaColors.accent.withValues(
              alpha: 0.30,
            ),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.info_outline_rounded,
              color: context.cAccentReadable,
              size: 20,
            ),
            const SizedBox(
              width: 10,
            ),
            Expanded(
              child: Text(
                'No doctor linked to your Corvia care history '
                'is currently available to report.',
                style: TextStyle(
                  color: context.cTextSecondary,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return _DropdownField<String>(
      hint: 'Select a Doctor',
      value: _selectedDoctorId,
      items: _realDoctors
          .map(
            (
              doctor,
            ) =>
                doctor['id'].toString(),
          )
          .toList(),
      labels: _realDoctors
          .map(
            _doctorLabel,
          )
          .toList(),
      icon: Icons.medical_services_outlined,
      enabled: !_isSubmitting,
      onChanged: (
        value,
      ) {
        setState(() {
          _selectedDoctorId = value;
        });
      },
      validator: (
        value,
      ) {
        if (value == null || value.trim().isEmpty) {
          return 'Please select a doctor.';
        }

        return null;
      },
    );
  }
}

// ============================================================================
// INTRO
// ============================================================================

class _IntroBlock extends StatelessWidget {
  const _IntroBlock();

  @override
  Widget build(
    BuildContext context,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Report a Concern',
          style: TextStyle(
            color: context.cTextPrimary,
            fontSize: 22,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.3,
          ),
        ),
        const SizedBox(
          height: 8,
        ),
        Text(
          'Help us improve patient care by reporting concerns about '
          'a doctor who has been involved in your Corvia care.',
          style: TextStyle(
            color: context.cTextSecondary,
            fontSize: 14,
            height: 1.5,
          ),
        ),
      ],
    );
  }
}

// ============================================================================
// FIELD LABEL
// ============================================================================

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(
    this.text, {
    this.required = false,
  });

  final String text;
  final bool required;

  @override
  Widget build(
    BuildContext context,
  ) {
    return RichText(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: context.cTextPrimary,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
        children: [
          if (required)
            TextSpan(
              text: ' *',
              style: TextStyle(
                color: CorviaColors.danger,
              ),
            ),
        ],
      ),
    );
  }
}

// ============================================================================
// DROPDOWN
// ============================================================================

class _DropdownField<T> extends StatelessWidget {
  const _DropdownField({
    required this.hint,
    required this.value,
    required this.items,
    required this.icon,
    required this.onChanged,
    this.labels,
    this.validator,
    this.enabled = true,
  });

  final String hint;

  final T? value;

  final List<T> items;
  final List<String>? labels;

  final IconData icon;

  final ValueChanged<T?> onChanged;

  final FormFieldValidator<T>? validator;

  final bool enabled;

  @override
  Widget build(
    BuildContext context,
  ) {
    return DropdownButtonFormField<T>(
      initialValue: value,
      validator: validator,
      isExpanded: true,
      icon: Icon(
        Icons.keyboard_arrow_down_rounded,
        color: context.cTextSecondary,
      ),
      dropdownColor: context.cBgSecondary,
      decoration: InputDecoration(
        prefixIcon: Icon(
          icon,
          size: 20,
          color: context.cAccentReadable,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
        filled: true,
        fillColor: context.cBgSecondary,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(
            12,
          ),
          borderSide: BorderSide(
            color: context.cDivider,
            width: 0.8,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(
            12,
          ),
          borderSide: BorderSide(
            color: context.cDivider,
            width: 0.8,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(
            12,
          ),
          borderSide: BorderSide(
            color: context.cAccentReadable,
            width: 1.2,
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(
            12,
          ),
          borderSide: BorderSide(
            color: CorviaColors.danger,
            width: 0.8,
          ),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(
            12,
          ),
          borderSide: BorderSide(
            color: CorviaColors.danger,
            width: 1.2,
          ),
        ),
      ),
      hint: Text(
        hint,
        style: TextStyle(
          color: context.cTextMuted,
          fontSize: 14,
        ),
      ),
      style: TextStyle(
        color: context.cTextPrimary,
        fontSize: 14,
      ),
      items: items.asMap().entries.map(
        (
          entry,
        ) {
          final index = entry.key;
          final item = entry.value;

          final label = labels != null && index < labels!.length
              ? labels![index]
              : item.toString();

          return DropdownMenuItem<T>(
            value: item,
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
            ),
          );
        },
      ).toList(),
      onChanged: enabled ? onChanged : null,
    );
  }
}

// ============================================================================
// DESCRIPTION
// ============================================================================

class _DescriptionField extends StatelessWidget {
  const _DescriptionField({
    required this.controller,
    required this.enabled,
  });

  final TextEditingController controller;
  final bool enabled;

  @override
  Widget build(
    BuildContext context,
  ) {
    return TextFormField(
      controller: controller,
      enabled: enabled,
      maxLines: 6,
      minLines: 4,
      maxLength: 5000,
      style: TextStyle(
        color: context.cTextPrimary,
        fontSize: 14,
      ),
      validator: (
        value,
      ) {
        final text = value?.trim() ?? '';

        if (text.isEmpty) {
          return 'Please describe your experience.';
        }

        if (text.length < 10) {
          return 'Please provide a bit more detail '
              '(at least 10 characters).';
        }

        if (text.length > 5000) {
          return 'The description cannot exceed 5000 characters.';
        }

        return null;
      },
      decoration: InputDecoration(
        hintText:
            'Please provide factual details about your experience.',
        hintStyle: TextStyle(
          color: context.cTextMuted,
          fontSize: 13,
        ),
        counterStyle: TextStyle(
          color: context.cTextMuted,
        ),
        contentPadding: const EdgeInsets.all(
          14,
        ),
        filled: true,
        fillColor: context.cBgSecondary,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(
            12,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(
            12,
          ),
          borderSide: BorderSide(
            color: context.cDivider,
            width: 0.8,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(
            12,
          ),
          borderSide: BorderSide(
            color: context.cAccentReadable,
            width: 1.2,
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(
            12,
          ),
          borderSide: BorderSide(
            color: CorviaColors.danger,
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// CHECKBOX
// ============================================================================

class _CheckRow extends StatelessWidget {
  const _CheckRow({
    required this.label,
    required this.subtitle,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final String label;
  final String subtitle;

  final bool value;
  final bool enabled;

  final ValueChanged<bool?> onChanged;

  @override
  Widget build(
    BuildContext context,
  ) {
    return InkWell(
      borderRadius: BorderRadius.circular(
        8,
      ),
      onTap: enabled
          ? () {
              onChanged(
                !value,
              );
            }
          : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          vertical: 6,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Checkbox(
              value: value,
              onChanged: enabled ? onChanged : null,
              activeColor: CorviaColors.accent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(
                  4,
                ),
              ),
            ),
            const SizedBox(
              width: 4,
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(
                  top: 8,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 13.5,
                        color: enabled
                            ? context.cTextPrimary
                            : context.cTextMuted,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(
                      height: 3,
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: context.cTextMuted,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// CONFIDENTIAL NOTICE
// ============================================================================

class _ConfidentialNotice extends StatelessWidget {
  const _ConfidentialNotice();

  @override
  Widget build(
    BuildContext context,
  ) {
    return Container(
      padding: const EdgeInsets.all(
        14,
      ),
      decoration: BoxDecoration(
        color: CorviaColors.accent.withValues(
          alpha: 0.08,
        ),
        borderRadius: BorderRadius.circular(
          12,
        ),
        border: Border.all(
          color: CorviaColors.accent.withValues(
            alpha: 0.25,
          ),
          width: 0.8,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.verified_user_outlined,
            size: 20,
            color: context.cAccentReadable,
          ),
          const SizedBox(
            width: 10,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Confidential Governance Report',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: context.cTextPrimary,
                  ),
                ),
                const SizedBox(
                  height: 4,
                ),
                Text(
                  'Your report is handled through the hospital governance '
                  'process and is not automatically added to your normal '
                  'clinical timeline.',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: context.cTextSecondary,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// SUBMIT BUTTON
// ============================================================================

class _SubmitButton extends StatelessWidget {
  const _SubmitButton({
    required this.isSubmitting,
    required this.enabled,
    required this.onPressed,
  });

  final bool isSubmitting;
  final bool enabled;

  final VoidCallback onPressed;

  @override
  Widget build(
    BuildContext context,
  ) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: !enabled || isSubmitting ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: CorviaColors.accent,
          disabledBackgroundColor: CorviaColors.accent.withValues(
            alpha: 0.45,
          ),
          padding: const EdgeInsets.symmetric(
            vertical: 16,
          ),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(
              12,
            ),
          ),
        ),
        child: isSubmitting
            ? const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      color: Colors.white,
                    ),
                  ),
                  SizedBox(
                    width: 10,
                  ),
                  Text(
                    'Submitting...',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              )
            : const Text(
                'Submit Report',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                ),
              ),
      ),
    );
  }
}
