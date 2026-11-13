import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../theme/app_theme.dart';
import '../../../widgets/status_view.dart';

class SpecialistRequestPage extends StatefulWidget {
  const SpecialistRequestPage({super.key});

  @override
  State<SpecialistRequestPage> createState() => _SpecialistRequestPageState();
}

class _SpecialistRequestPageState extends State<SpecialistRequestPage> {
  static const Duration _requestTimeout = Duration(seconds: 15);

  final SupabaseClient _supabase = Supabase.instance.client;

  final TextEditingController _reasonController = TextEditingController();

  List<_HospitalOption> _hospitals = [];

  String? _selectedHospitalId;
  String? _selectedSpecialty;

  DateTime _preferredDate = DateTime.now().add(
    const Duration(days: 7),
  );

  TimeOfDay _preferredTime = const TimeOfDay(
    hour: 9,
    minute: 0,
  );

  bool _hasReferral = false;
  bool _preauthorisationAcknowledged = false;

  /// Open doctor referrals. A specialist request is only offered once a
  /// doctor has referred the patient; the request is then limited to the
  /// referred specialties.
  List<_OpenReferral> _referrals = const [];

  bool _loadingHospitals = true;
  bool _submitting = false;

  String? _loadError;
  String? _formError;

  @override
  void initState() {
    super.initState();
    _loadHospitals();
  }

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _loadHospitals() async {
    if (mounted) {
      setState(() {
        _loadingHospitals = true;
        _loadError = null;
      });
    }

    try {
      final response =
          await _supabase.from('hospitals').select().timeout(_requestTimeout);

      final rows = _rows(response);

      final hospitals = <_HospitalOption>[];

      for (final row in rows) {
        final id = row['id']?.toString().trim();

        final name = _firstText(
          [
            row['name'],
            row['hospital_name'],
            row['display_name'],
          ],
          fallback: '',
        );

        if (id == null || id.isEmpty || name.isEmpty) {
          continue;
        }

        hospitals.add(
          _HospitalOption(
            id: id,
            name: name,
          ),
        );
      }

      hospitals.sort(
        (first, second) => first.name.toLowerCase().compareTo(
              second.name.toLowerCase(),
            ),
      );

      if (!mounted) {
        return;
      }

      final referrals = await _loadOpenReferrals();

      if (!mounted) {
        return;
      }

      setState(() {
        _hospitals = hospitals;
        _referrals = referrals;

        if (referrals.isNotEmpty) {
          final referral = referrals.first;
          _hasReferral = true;
          _selectedSpecialty ??= referral.specialty;
          final referredHospital = referral.hospitalId;
          if (_selectedHospitalId == null &&
              referredHospital != null &&
              hospitals.any((hospital) => hospital.id == referredHospital)) {
            _selectedHospitalId = referredHospital;
          }
        }

        if (_selectedHospitalId == null && hospitals.isNotEmpty) {
          _selectedHospitalId = hospitals.first.id;
        }
      });
    } on TimeoutException {
      if (!mounted) {
        return;
      }

      setState(() {
        _loadError = 'The hospital list took too long to load.';
      });
    } catch (error) {
      debugPrint(
        'Hospital loading failed: $error',
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _loadError = _friendlyError(error);
      });
    } finally {
      if (mounted) {
        setState(() {
          _loadingHospitals = false;
        });
      }
    }
  }

  Future<List<_OpenReferral>> _loadOpenReferrals() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) {
      return const [];
    }

    final patient = await _supabase
        .from('patients')
        .select('id')
        .eq('profile_id', userId)
        .maybeSingle()
        .timeout(_requestTimeout);

    final patientId = patient?['id']?.toString();
    if (patientId == null || patientId.isEmpty) {
      return const [];
    }

    final response = await _supabase
        .from('specialist_referrals')
        .select(
          'id, requested_specialty, requested_hospital_id, urgency, '
          'status, created_at',
        )
        .eq('patient_id', patientId)
        .inFilter('status', ['pending', 'accepted'])
        .isFilter('specialist_request_id', null)
        .order('created_at', ascending: false)
        .timeout(_requestTimeout);

    return _rows(response)
        .map(
          (row) => _OpenReferral(
            id: row['id']?.toString() ?? '',
            specialty: row['requested_specialty']?.toString().trim() ?? '',
            hospitalId: row['requested_hospital_id']?.toString(),
            urgency: row['urgency']?.toString() ?? 'routine',
          ),
        )
        .where((referral) => referral.specialty.isNotEmpty)
        .toList();
  }

  /// Specialties the patient may request: only those a doctor referred.
  List<String> get _allowedSpecialties {
    final referred = <String>[];
    for (final referral in _referrals) {
      if (!referred.contains(referral.specialty)) {
        referred.add(referral.specialty);
      }
    }
    return referred;
  }

  Widget _buildReferralRequired() {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.assignment_ind_outlined,
                size: 56,
                color: context.cAccentReadable,
              ),
              const SizedBox(height: 16),
              Text(
                'A doctor referral is needed first',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: context.cTextPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Specialist requests open once your doctor refers you to a '
                'specialist. Book a consultation or message your doctor to '
                'ask for a referral, then come back here.',
                textAlign: TextAlign.center,
                style: TextStyle(color: context.cTextSecondary, height: 1.4),
              ),
              const SizedBox(height: 20),
              OutlinedButton.icon(
                onPressed: _loadHospitals,
                icon: const Icon(Icons.refresh),
                label: const Text('Check again'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Map<String, dynamic>> _rows(
    dynamic response,
  ) {
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

  String _firstText(
    List<dynamic> values, {
    required String fallback,
  }) {
    for (final value in values) {
      final text = value?.toString().trim();

      if (text != null && text.isNotEmpty) {
        return text;
      }
    }

    return fallback;
  }

  DateTime get _preferredAppointment {
    return DateTime(
      _preferredDate.year,
      _preferredDate.month,
      _preferredDate.day,
      _preferredTime.hour,
      _preferredTime.minute,
    );
  }

  Future<void> _pickDate() async {
    final today = DateTime.now();

    final firstDate = DateTime(
      today.year,
      today.month,
      today.day,
    );

    final picked = await showDatePicker(
      context: context,
      initialDate: _preferredDate,
      firstDate: firstDate,
      lastDate: firstDate.add(
        const Duration(days: 180),
      ),
    );

    if (picked == null || !mounted) {
      return;
    }

    setState(() {
      _preferredDate = picked;
      _formError = null;
    });
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _preferredTime,
    );

    if (picked == null || !mounted) {
      return;
    }

    setState(() {
      _preferredTime = picked;
      _formError = null;
    });
  }

  Future<void> _submitRequest() async {
    if (_submitting) {
      return;
    }

    final hospitalId = _selectedHospitalId?.trim();

    final specialty = _selectedSpecialty?.trim();

    final reason = _reasonController.text.trim();

    final appointment = _preferredAppointment;

    if (hospitalId == null || hospitalId.isEmpty) {
      _setFormError(
        'Select a preferred hospital.',
      );
      return;
    }

    if (specialty == null || specialty.isEmpty) {
      _setFormError(
        'Select a specialty.',
      );
      return;
    }

    if (reason.length < 10) {
      _setFormError(
        'Enter a clear reason of at least '
        '10 characters.',
      );
      return;
    }

    if (!appointment.isAfter(
      DateTime.now().add(
        const Duration(minutes: 15),
      ),
    )) {
      _setFormError(
        'Select a future preferred date and time.',
      );
      return;
    }

    if (!_preauthorisationAcknowledged) {
      _setFormError(
        'Confirm that the hospital or medical aid '
        'may require preauthorisation.',
      );
      return;
    }

    setState(() {
      _submitting = true;
      _formError = null;
    });

    try {
      final requestId = await _supabase.rpc(
        'create_patient_specialist_request',
        params: {
          'p_hospital_id': hospitalId,
          'p_specialty': specialty,
          'p_preferred_appointment_at': appointment.toUtc().toIso8601String(),
          'p_reason': reason,
          'p_payment_type': null,
          'p_has_referral': _hasReferral,
          'p_preauthorisation_acknowledged': _preauthorisationAcknowledged,
        },
      ).timeout(_requestTimeout);

      if (!mounted) {
        return;
      }

      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          return AlertDialog(
            title: const Text(
              'Specialist request submitted',
            ),
            content: Text(
              'Your $specialty request is now Pending. '
              'Reception will assign a specialist and '
              'confirm the final date and time.\n\n'
              'Reference: ${requestId?.toString() ?? 'Created'}',
            ),
            actions: [
              FilledButton(
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                },
                child: const Text('Done'),
              ),
            ],
          );
        },
      );

      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } on TimeoutException {
      _setFormError(
        'The request took too long. Check your '
        'connection before trying again.',
      );
    } on PostgrestException catch (error) {
      debugPrint(
        'Specialist request database error: $error',
      );

      _setFormError(
        _friendlyError(error),
      );
    } catch (error) {
      debugPrint(
        'Specialist request failed: $error',
      );

      _setFormError(
        _friendlyError(error),
      );
    } finally {
      if (mounted) {
        setState(() {
          _submitting = false;
        });
      }
    }
  }

  void _setFormError(String message) {
    if (!mounted) {
      return;
    }

    setState(() {
      _formError = message;
    });
  }

  String _friendlyError(Object error) {
    final message =
        error is PostgrestException ? error.message : error.toString();

    final lower = message.toLowerCase();

    if (lower.contains(
      'create_patient_specialist_request',
    )) {
      return 'The specialist request database function '
          'is missing. Run the specialist workflow SQL '
          'in Supabase first.';
    }

    if (lower.contains(
          'row-level security',
        ) ||
        lower.contains(
          'permission denied',
        ) ||
        lower.contains('42501')) {
      return 'Your account does not have permission '
          'to submit this specialist request.';
    }

    if (lower.contains(
      'no patient record',
    )) {
      return 'No patient record is linked to this account.';
    }

    return message
        .replaceFirst('Exception: ', '')
        .replaceFirst('Bad state: ', '');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.cBgPrimary,
      appBar: AppBar(
        title: const Text(
          'Request a Specialist',
        ),
      ),
      body: _loadingHospitals
          ? StatusView.loading(
              message: 'Loading hospitals...',
            )
          : _loadError != null
              ? StatusView.error(
                  friendlyMessage:
                      "We couldn't load hospitals or check your referrals.",
                  error: _loadError,
                  onRetry: _loadHospitals,
                )
              : _referrals.isEmpty
                  ? _buildReferralRequired()
                  : _buildForm(),
    );
  }

  Widget _buildForm() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final horizontalPadding = constraints.maxWidth >= 800 ? 30.0 : 16.0;

        return ListView(
          padding: EdgeInsets.fromLTRB(
            horizontalPadding,
            18,
            horizontalPadding,
            40,
          ),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: 760,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(17),
                      decoration: BoxDecoration(
                        color: Colors.deepPurple.withValues(
                          alpha: 0.09,
                        ),
                        borderRadius: BorderRadius.circular(17),
                        border: Border.all(
                          color: Colors.deepPurple.withValues(
                            alpha: 0.27,
                          ),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.health_and_safety_outlined,
                            color: Colors.deepPurple,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'This is a request, not an immediate '
                              'booking. Reception will review the '
                              'request, assign a suitable specialist '
                              'and confirm the final appointment.',
                              style: TextStyle(
                                color: context.cTextPrimary,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    DropdownButtonFormField<String>(
                      initialValue: _selectedHospitalId,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Preferred Hospital',
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
                      onChanged: _submitting
                          ? null
                          : (value) {
                              setState(() {
                                _selectedHospitalId = value;
                                _formError = null;
                              });
                            },
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      initialValue: _selectedSpecialty,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Specialty',
                        prefixIcon: Icon(
                          Icons.medical_information_outlined,
                        ),
                        border: OutlineInputBorder(),
                      ),
                      items: _allowedSpecialties.map(
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
                      onChanged: _submitting
                          ? null
                          : (value) {
                              setState(() {
                                _selectedSpecialty = value;
                                _formError = null;
                              });
                            },
                    ),
                    const SizedBox(height: 16),
                    LayoutBuilder(
                      builder: (
                        context,
                        dateConstraints,
                      ) {
                        final dateField = _DateTimeChoice(
                          icon: Icons.calendar_today_outlined,
                          label: 'Preferred Date',
                          value: DateFormat(
                            'EEE, d MMM yyyy',
                          ).format(_preferredDate),
                          onTap: _submitting ? null : _pickDate,
                        );

                        final timeField = _DateTimeChoice(
                          icon: Icons.access_time_rounded,
                          label: 'Preferred Time',
                          value: _preferredTime.format(
                            context,
                          ),
                          onTap: _submitting ? null : _pickTime,
                        );

                        if (dateConstraints.maxWidth < 560) {
                          return Column(
                            children: [
                              dateField,
                              const SizedBox(height: 12),
                              timeField,
                            ],
                          );
                        }

                        return Row(
                          children: [
                            Expanded(child: dateField),
                            const SizedBox(width: 12),
                            Expanded(child: timeField),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _reasonController,
                      enabled: !_submitting,
                      minLines: 4,
                      maxLines: 7,
                      maxLength: 2000,
                      decoration: const InputDecoration(
                        labelText: 'Reason for specialist request',
                        hintText: 'Describe your symptoms, previous treatment '
                            'or why you need this specialist.',
                        alignLabelWithHint: true,
                        prefixIcon: Icon(
                          Icons.notes_outlined,
                        ),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Material(
                      color: Colors.transparent,
                      child: CheckboxListTile(
                        value: _hasReferral,
                        contentPadding: EdgeInsets.zero,
                        title: const Text(
                          'Referred by my doctor',
                        ),
                        subtitle: const Text(
                          'Your doctor\'s referral is on file. Reception may '
                          'still ask for the referral letter.',
                        ),
                        // Set from the open referral; not patient-editable.
                        onChanged: null,
                      ),
                    ),
                    Material(
                      color: Colors.transparent,
                      child: CheckboxListTile(
                        value: _preauthorisationAcknowledged,
                        contentPadding: EdgeInsets.zero,
                        title: const Text(
                          'I understand confirmation may require '
                          'medical-aid preauthorisation',
                        ),
                        onChanged: _submitting
                            ? null
                            : (value) {
                                setState(() {
                                  _preauthorisationAcknowledged =
                                      value ?? false;
                                  _formError = null;
                                });
                              },
                      ),
                    ),
                    if (_formError != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(13),
                        decoration: BoxDecoration(
                          color: CorviaColors.danger.withValues(alpha: 0.09),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: CorviaColors.danger.withValues(alpha: 0.30),
                          ),
                        ),
                        child: Text(
                          _formError!,
                          style: TextStyle(
                            color: context.cTextPrimary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 22),
                    FilledButton.icon(
                      onPressed: _submitting ? null : _submitRequest,
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.deepPurple,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          vertical: 15,
                        ),
                      ),
                      icon: _submitting
                          ? const SizedBox(
                              width: 19,
                              height: 19,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(
                              Icons.send_rounded,
                            ),
                      label: Text(
                        _submitting
                            ? 'Submitting...'
                            : 'Submit Specialist Request',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
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

class _DateTimeChoice extends StatelessWidget {
  const _DateTimeChoice({
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
      color: context.cBgSecondary,
      borderRadius: BorderRadius.circular(13),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(13),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(13),
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
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        color: context.cTextSecondary,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 3),
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
              Icon(
                Icons.edit_calendar_outlined,
                color: context.cTextSecondary,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OpenReferral {
  const _OpenReferral({
    required this.id,
    required this.specialty,
    required this.hospitalId,
    required this.urgency,
  });

  final String id;
  final String specialty;
  final String? hospitalId;
  final String urgency;
}
