import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../theme/app_theme.dart';
import '../../../widgets/text_controller_scope.dart';

class ReceptionSpecialistRequestsPage extends StatefulWidget {
  const ReceptionSpecialistRequestsPage({super.key});

  @override
  State<ReceptionSpecialistRequestsPage> createState() =>
      _ReceptionSpecialistRequestsPageState();
}

class _ReceptionSpecialistRequestsPageState
    extends State<ReceptionSpecialistRequestsPage> {
  static const Duration _requestTimeout = Duration(seconds: 20);

  final SupabaseClient _supabase = Supabase.instance.client;
  final TextEditingController _searchController = TextEditingController();

  List<_SpecialistRequestRecord> _requests = <_SpecialistRequestRecord>[];
  List<_DoctorSummary> _doctors = <_DoctorSummary>[];

  final Set<String> _busyRequestIds = <String>{};

  bool _loading = true;
  bool _refreshing = false;

  String? _error;
  String _statusFilter = 'active';

  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    _loadRequests(showFullLoader: true);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadRequests({
    required bool showFullLoader,
  }) async {
    final generation = ++_loadGeneration;

    if (mounted) {
      setState(() {
        _error = null;

        if (showFullLoader || _requests.isEmpty) {
          _loading = true;
          _refreshing = false;
        } else {
          _refreshing = true;
        }
      });
    }

    try {
      final requestResponse = await _supabase
          .from('specialist_requests')
          .select()
          .order(
            'created_at',
            ascending: false,
          )
          .timeout(_requestTimeout);

      final requestRows = _rows(requestResponse);

      final patientIds = requestRows
          .map(
            (row) => _cleanId(row['patient_id']),
          )
          .whereType<String>()
          .toSet()
          .toList();

      final hospitalIds = requestRows
          .map(
            (row) => _cleanId(row['requested_hospital_id']),
          )
          .whereType<String>()
          .toSet()
          .toList();

      final patientSummaries = await _loadPatients(patientIds);
      final hospitalNames = await _loadHospitalNames(hospitalIds);
      final doctors = await _loadDoctors();

      final records = <_SpecialistRequestRecord>[];

      for (final row in requestRows) {
        final requestId = _cleanId(row['id']);
        final patientId = _cleanId(row['patient_id']);

        if (requestId == null || patientId == null) {
          continue;
        }

        final hospitalId = _cleanId(row['requested_hospital_id']);
        final assignedDoctorId = _cleanId(row['assigned_doctor_id']);

        final assignedDoctor = assignedDoctorId == null
            ? null
            : doctors
                .where(
                  (doctor) => doctor.id == assignedDoctorId,
                )
                .firstOrNull;

        final patient = patientSummaries[patientId] ??
            _PatientSummary(
              id: patientId,
              fullName: 'Patient',
              patientNumber: 'Patient number unavailable',
            );

        final requestedSpecialty = _firstText(
          <dynamic>[
            row['requested_specialty'],
            row['specialty'],
            row['specialisation'],
            row['specialization'],
          ],
          fallback: 'Specialist',
        );

        records.add(
          _SpecialistRequestRecord(
            id: requestId,
            patient: patient,
            hospitalId: hospitalId,
            hospitalName: hospitalId == null
                ? 'Hospital not selected'
                : hospitalNames[hospitalId] ?? 'Hospital unavailable',
            requestedSpecialty: requestedSpecialty,
            preferredAppointmentAt: _parseDate(
              row['preferred_appointment_at'],
            ),
            finalAppointmentAt: _parseDate(
              row['final_appointment_at'],
            ),
            createdAt: _parseDate(
              row['created_at'],
            ),
            reason: _firstText(
              <dynamic>[
                row['reason'],
                row['referral_notes'],
              ],
              fallback: 'No reason supplied.',
            ),
            urgency: _canonicalValue(
              row['urgency'],
              fallback: 'routine',
            ),
            referralStatus: _canonicalValue(
              row['referral_status'],
              fallback: 'not_provided',
            ),
            status: _canonicalValue(
              row['status'],
              fallback: 'pending',
            ),
            assignedDoctorId: assignedDoctorId,
            assignedDoctorName: assignedDoctor?.name,
            durationMinutes: _asInt(
              row['duration_minutes'],
              fallback: 30,
            ),
            appointmentId: _cleanId(
              row['appointment_id'],
            ),
            receptionNotes: _nullableText(
              row['reception_notes'],
            ),
            rejectionReason: _nullableText(
              row['rejection_reason'],
            ),
            referralDocumentUrl: _nullableText(
              row['referral_document_url'],
            ),
          ),
        );
      }

      if (!mounted || generation != _loadGeneration) {
        return;
      }

      setState(() {
        _requests = records;
        _doctors = doctors;
        _error = null;
      });
    } on TimeoutException {
      if (!mounted || generation != _loadGeneration) {
        return;
      }

      setState(() {
        _error = 'The server took too long to load specialist requests.';
      });
    } catch (error) {
      debugPrint('Reception specialist requests load failed: $error');

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
          _refreshing = false;
        });
      }
    }
  }

  Future<Map<String, _PatientSummary>> _loadPatients(
    List<String> patientIds,
  ) async {
    if (patientIds.isEmpty) {
      return <String, _PatientSummary>{};
    }

    try {
      final response = await _supabase
          .from('patients')
          .select()
          .inFilter('id', patientIds)
          .timeout(_requestTimeout);

      final patientRows = _rows(response);

      final profileIds = patientRows
          .map(
            (row) => _cleanId(row['profile_id']),
          )
          .whereType<String>()
          .toSet()
          .toList();

      final profiles = await _loadProfiles(profileIds);

      final result = <String, _PatientSummary>{};

      for (final row in patientRows) {
        final patientId = _cleanId(row['id']);

        if (patientId == null) {
          continue;
        }

        final profileId = _cleanId(row['profile_id']);
        final profile = profileId == null ? null : profiles[profileId];

        final firstName = _firstText(
          <dynamic>[
            row['first_name'],
            row['name'],
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

        final combinedName = '$firstName $surname'.trim();

        result[patientId] = _PatientSummary(
          id: patientId,
          fullName: combinedName.isEmpty ? 'Patient' : combinedName,
          patientNumber: _firstText(
            <dynamic>[
              row['patient_number'],
              row['medical_record_number'],
              row['patient_no'],
              row['id_number'],
            ],
            fallback: 'Patient number unavailable',
          ),
        );
      }

      return result;
    } catch (error) {
      debugPrint('Patient details could not load: $error');
      return <String, _PatientSummary>{};
    }
  }

  Future<Map<String, Map<String, dynamic>>> _loadProfiles(
    List<String> profileIds,
  ) async {
    if (profileIds.isEmpty) {
      return <String, Map<String, dynamic>>{};
    }

    final result = <String, Map<String, dynamic>>{};

    try {
      final byIdResponse = await _supabase
          .from('profiles')
          .select()
          .inFilter('id', profileIds)
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
      debugPrint('Profiles by id could not load: $error');
    }

    try {
      final byUserIdResponse = await _supabase
          .from('profiles')
          .select()
          .inFilter('user_id', profileIds)
          .timeout(_requestTimeout);

      for (final row in _rows(byUserIdResponse)) {
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
      debugPrint('Profiles by user_id could not load: $error');
    }

    return result;
  }

  Future<Map<String, String>> _loadHospitalNames(
    List<String> hospitalIds,
  ) async {
    if (hospitalIds.isEmpty) {
      return <String, String>{};
    }

    try {
      final response = await _supabase
          .from('hospitals')
          .select()
          .inFilter('id', hospitalIds)
          .timeout(_requestTimeout);

      final result = <String, String>{};

      for (final row in _rows(response)) {
        final id = _cleanId(row['id']);

        if (id == null) {
          continue;
        }

        result[id] = _firstText(
          <dynamic>[
            row['name'],
            row['hospital_name'],
            row['display_name'],
          ],
          fallback: 'Hospital',
        );
      }

      return result;
    } catch (error) {
      debugPrint('Hospital names could not load: $error');
      return <String, String>{};
    }
  }

  Future<List<_DoctorSummary>> _loadDoctors() async {
    try {
      final response =
          await _supabase.from('doctors').select().timeout(_requestTimeout);

      final doctorRows = _rows(response);

      final profileIds = doctorRows
          .map(
            (row) => _cleanId(row['profile_id']),
          )
          .whereType<String>()
          .toSet()
          .toList();

      final profiles = await _loadProfiles(profileIds);

      final result = <_DoctorSummary>[];

      for (final row in doctorRows) {
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

        final status = _canonicalValue(
          row['status'],
          fallback: 'active',
        );

        final explicitlyInactive = row['is_active'] == false ||
            status == 'inactive' ||
            status == 'retired' ||
            status == 'suspended';

        if (explicitlyInactive) {
          continue;
        }

        result.add(
          _DoctorSummary(
            id: doctorId,
            name: fullName.isEmpty ? 'Doctor' : 'Dr. $fullName',
            specialty: _firstText(
              <dynamic>[
                row['specialization'],
                row['specialisation'],
                row['specialty'],
                row['speciality'],
                row['department'],
              ],
              fallback: 'Medical Practitioner',
            ),
            hospitalId: _cleanId(row['hospital_id']),
          ),
        );
      }

      result.sort(
        (first, second) => first.name.toLowerCase().compareTo(
              second.name.toLowerCase(),
            ),
      );

      return result;
    } catch (error) {
      debugPrint('Doctors could not load: $error');
      return <_DoctorSummary>[];
    }
  }

  List<_DoctorSummary> _candidateDoctors(
    _SpecialistRequestRecord request,
  ) {
    final sameHospital = _doctors.where(
      (doctor) {
        if (request.hospitalId == null || doctor.hospitalId == null) {
          return true;
        }

        return doctor.hospitalId == request.hospitalId;
      },
    ).toList();

    final requestedSpecialty = _normaliseSearch(
      request.requestedSpecialty,
    );

    final specialtyMatches = sameHospital.where(
      (doctor) {
        final doctorSpecialty = _normaliseSearch(
          doctor.specialty,
        );

        return doctorSpecialty.contains(requestedSpecialty) ||
            requestedSpecialty.contains(doctorSpecialty) ||
            _specialtyKeywordsMatch(
              requestedSpecialty,
              doctorSpecialty,
            );
      },
    ).toList();

    if (specialtyMatches.isNotEmpty) {
      return specialtyMatches;
    }

    if (sameHospital.isNotEmpty) {
      return sameHospital;
    }

    return _doctors;
  }

  bool _specialtyKeywordsMatch(
    String requested,
    String doctorSpecialty,
  ) {
    final requestedWords = requested
        .split(' ')
        .where(
          (word) => word.length >= 5,
        )
        .toSet();

    final doctorWords = doctorSpecialty
        .split(' ')
        .where(
          (word) => word.length >= 5,
        )
        .toSet();

    return requestedWords.intersection(doctorWords).isNotEmpty;
  }

  List<_SpecialistRequestRecord> get _visibleRequests {
    final query = _normaliseSearch(
      _searchController.text,
    );

    return _requests.where(
      (request) {
        if (_statusFilter == 'active') {
          if (request.isClosed) {
            return false;
          }
        } else if (_statusFilter != 'all' && request.status != _statusFilter) {
          return false;
        }

        if (query.isEmpty) {
          return true;
        }

        final searchableText = _normaliseSearch(
          <String>[
            request.patient.fullName,
            request.patient.patientNumber,
            request.requestedSpecialty,
            request.hospitalName,
            request.reason,
            request.assignedDoctorName ?? '',
            request.status,
            request.referralStatus,
          ].join(' '),
        );

        return searchableText.contains(query);
      },
    ).toList();
  }

  Future<void> _assignSpecialist(
    _SpecialistRequestRecord request,
  ) async {
    final candidates = _candidateDoctors(request);

    if (candidates.isEmpty) {
      _showMessage(
        'No available doctors could be loaded for this request.',
        isError: true,
      );
      return;
    }

    String? selectedDoctorId = request.assignedDoctorId ?? candidates.first.id;

    final result = await showDialog<_AssignResult>(
      context: context,
      builder: (dialogContext) {
        return TextControllerScope(
          initialText: request.receptionNotes ?? '',
          builder: (notesController) {
            return StatefulBuilder(
              builder: (context, setDialogState) {
                return AlertDialog(
                  title: const Text('Assign Specialist'),
                  content: SizedBox(
                    width: 520,
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _dialogRequestSummary(request),
                          const SizedBox(height: 16),
                          DropdownButtonFormField<String>(
                            initialValue: selectedDoctorId,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'Specialist',
                              prefixIcon: Icon(
                                Icons.medical_services_outlined,
                              ),
                              border: OutlineInputBorder(),
                            ),
                            items: candidates.map(
                              (doctor) {
                                return DropdownMenuItem<String>(
                                  value: doctor.id,
                                  child: Text(
                                    '${doctor.name} • ${doctor.specialty}',
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                );
                              },
                            ).toList(),
                            onChanged: (value) {
                              setDialogState(() {
                                selectedDoctorId = value;
                              });
                            },
                          ),
                          const SizedBox(height: 14),
                          TextField(
                            controller: notesController,
                            minLines: 2,
                            maxLines: 4,
                            maxLength: 2000,
                            decoration: const InputDecoration(
                              labelText: 'Reception notes',
                              alignLabelWithHint: true,
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
                        Navigator.of(dialogContext).pop();
                      },
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      onPressed: selectedDoctorId == null
                          ? null
                          : () {
                              Navigator.of(dialogContext).pop(
                                _AssignResult(
                                  doctorId: selectedDoctorId!,
                                  notes: notesController.text.trim(),
                                ),
                              );
                            },
                      child: const Text('Assign'),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );

    if (result == null) {
      return;
    }

    await _performAction(
      requestId: request.id,
      successMessage: 'Specialist assigned successfully.',
      action: () async {
        await _assignRequestInDatabase(
          requestId: request.id,
          doctorId: result.doctorId,
          notes: result.notes,
        );
      },
    );
  }

  Future<void> _confirmRequest(
    _SpecialistRequestRecord request,
  ) async {
    final candidates = _candidateDoctors(request);

    if (candidates.isEmpty) {
      _showMessage(
        'No available specialists could be loaded.',
        isError: true,
      );
      return;
    }

    String? selectedDoctorId = request.assignedDoctorId ?? candidates.first.id;

    DateTime selectedDate = _safeFutureDate(
      request.finalAppointmentAt ?? request.preferredAppointmentAt,
    );

    TimeOfDay selectedTime = TimeOfDay.fromDateTime(
      selectedDate,
    );

    int durationMinutes =
        request.durationMinutes <= 0 ? 30 : request.durationMinutes;

    final result = await showDialog<_ConfirmResult>(
      context: context,
      builder: (dialogContext) {
        return TextControllerScope(
          initialText: request.receptionNotes ?? '',
          builder: (notesController) {
            return StatefulBuilder(
              builder: (context, setDialogState) {
                final finalDateTime = DateTime(
                  selectedDate.year,
                  selectedDate.month,
                  selectedDate.day,
                  selectedTime.hour,
                  selectedTime.minute,
                );

                return AlertDialog(
                  title: const Text(
                    'Confirm Specialist Appointment',
                  ),
                  content: SizedBox(
                    width: 560,
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _dialogRequestSummary(request),
                          const SizedBox(height: 16),
                          DropdownButtonFormField<String>(
                            initialValue: selectedDoctorId,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'Assigned Specialist',
                              prefixIcon: Icon(
                                Icons.medical_services_rounded,
                              ),
                              border: OutlineInputBorder(),
                            ),
                            items: candidates.map(
                              (doctor) {
                                return DropdownMenuItem<String>(
                                  value: doctor.id,
                                  child: Text(
                                    '${doctor.name} • ${doctor.specialty}',
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                );
                              },
                            ).toList(),
                            onChanged: (value) {
                              setDialogState(() {
                                selectedDoctorId = value;
                              });
                            },
                          ),
                          const SizedBox(height: 14),
                          Row(
                            children: [
                              Expanded(
                                child: _DialogChoiceButton(
                                  icon: Icons.calendar_today_outlined,
                                  label: 'Date',
                                  value: DateFormat(
                                    'd MMM yyyy',
                                  ).format(selectedDate),
                                  onPressed: () async {
                                    final now = DateTime.now();

                                    final picked = await showDatePicker(
                                      context: dialogContext,
                                      initialDate: selectedDate.isBefore(now)
                                          ? now
                                          : selectedDate,
                                      firstDate: DateTime(
                                        now.year,
                                        now.month,
                                        now.day,
                                      ),
                                      lastDate: now.add(
                                        const Duration(days: 365),
                                      ),
                                    );

                                    if (picked == null ||
                                        !dialogContext.mounted) {
                                      return;
                                    }

                                    setDialogState(() {
                                      selectedDate = picked;
                                    });
                                  },
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: _DialogChoiceButton(
                                  icon: Icons.access_time_rounded,
                                  label: 'Time',
                                  value: selectedTime.format(
                                    dialogContext,
                                  ),
                                  onPressed: () async {
                                    final picked = await showTimePicker(
                                      context: dialogContext,
                                      initialTime: selectedTime,
                                    );

                                    if (picked == null ||
                                        !dialogContext.mounted) {
                                      return;
                                    }

                                    setDialogState(() {
                                      selectedTime = picked;
                                    });
                                  },
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          DropdownButtonFormField<int>(
                            initialValue: durationMinutes,
                            decoration: const InputDecoration(
                              labelText: 'Duration',
                              prefixIcon: Icon(
                                Icons.timer_outlined,
                              ),
                              border: OutlineInputBorder(),
                            ),
                            items: const <DropdownMenuItem<int>>[
                              DropdownMenuItem<int>(
                                value: 15,
                                child: Text('15 minutes'),
                              ),
                              DropdownMenuItem<int>(
                                value: 30,
                                child: Text('30 minutes'),
                              ),
                              DropdownMenuItem<int>(
                                value: 45,
                                child: Text('45 minutes'),
                              ),
                              DropdownMenuItem<int>(
                                value: 60,
                                child: Text('60 minutes'),
                              ),
                              DropdownMenuItem<int>(
                                value: 90,
                                child: Text('90 minutes'),
                              ),
                            ],
                            onChanged: (value) {
                              if (value == null) {
                                return;
                              }

                              setDialogState(() {
                                durationMinutes = value;
                              });
                            },
                          ),
                          const SizedBox(height: 14),
                          TextField(
                            controller: notesController,
                            minLines: 2,
                            maxLines: 5,
                            maxLength: 2000,
                            decoration: const InputDecoration(
                              labelText: 'Reception notes',
                              alignLabelWithHint: true,
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: CorviaColors.accent.withValues(
                                alpha: 0.08,
                              ),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              'Final appointment: '
                              '${DateFormat('EEE, d MMM yyyy • HH:mm').format(finalDateTime)}',
                              style: TextStyle(
                                color: context.cTextPrimary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () {
                        Navigator.of(dialogContext).pop();
                      },
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      onPressed: selectedDoctorId == null
                          ? null
                          : () {
                              Navigator.of(dialogContext).pop(
                                _ConfirmResult(
                                  doctorId: selectedDoctorId!,
                                  appointmentAt: finalDateTime,
                                  durationMinutes: durationMinutes,
                                  notes: notesController.text.trim(),
                                ),
                              );
                            },
                      child: const Text('Confirm Appointment'),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );

    if (result == null) {
      return;
    }

    if (!result.appointmentAt.isAfter(DateTime.now())) {
      _showMessage(
        'The confirmed appointment must be in the future.',
        isError: true,
      );
      return;
    }

    await _performAction(
      requestId: request.id,
      successMessage: 'Specialist appointment confirmed successfully.',
      action: () async {
        final needsAssign = request.assignedDoctorId == null ||
            request.assignedDoctorId != result.doctorId;

        if (needsAssign) {
          await _assignRequestInDatabase(
            requestId: request.id,
            doctorId: result.doctorId,
            notes: result.notes,
          );
        }

        await _supabase.rpc(
          'confirm_specialist_request',
          params: <String, dynamic>{
            'p_request_id': request.id,
            'p_final_appointment_at':
                result.appointmentAt.toUtc().toIso8601String(),
            'p_duration_minutes': result.durationMinutes,
          },
        ).timeout(_requestTimeout);
      },
    );
  }

  Future<void> _assignRequestInDatabase({
    required String requestId,
    required String doctorId,
    required String notes,
  }) async {
    await _supabase.rpc(
      'assign_specialist_request',
      params: <String, dynamic>{
        'p_request_id': requestId,
        'p_doctor_id': doctorId,
        'p_notes': notes.trim().isEmpty ? null : notes.trim(),
      },
    ).timeout(_requestTimeout);
  }

  DateTime _safeFutureDate(DateTime? value) {
    final now = DateTime.now();
    final tomorrow = now.add(const Duration(days: 1));

    if (value == null) {
      return DateTime(
        tomorrow.year,
        tomorrow.month,
        tomorrow.day,
        9,
        0,
      );
    }

    if (value.isAfter(now)) {
      return value;
    }

    return DateTime(
      tomorrow.year,
      tomorrow.month,
      tomorrow.day,
      9,
      0,
    );
  }

  Future<void> _rescheduleRequest(
    _SpecialistRequestRecord request,
  ) async {
    DateTime selectedDate = _safeFutureDate(
      request.finalAppointmentAt ?? request.preferredAppointmentAt,
    );

    TimeOfDay selectedTime = TimeOfDay.fromDateTime(
      selectedDate,
    );

    final result = await showDialog<_RescheduleResult>(
      context: context,
      builder: (dialogContext) {
        return TextControllerScope(
          initialText: request.receptionNotes ?? '',
          builder: (notesController) {
            return StatefulBuilder(
              builder: (context, setDialogState) {
                final newAppointmentAt = DateTime(
                  selectedDate.year,
                  selectedDate.month,
                  selectedDate.day,
                  selectedTime.hour,
                  selectedTime.minute,
                );

                return AlertDialog(
                  title: const Text(
                    'Reschedule Appointment',
                  ),
                  content: SizedBox(
                    width: 520,
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _dialogRequestSummary(request),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(
                                child: _DialogChoiceButton(
                                  icon: Icons.calendar_today_outlined,
                                  label: 'New date',
                                  value: DateFormat(
                                    'd MMM yyyy',
                                  ).format(selectedDate),
                                  onPressed: () async {
                                    final now = DateTime.now();

                                    final picked = await showDatePicker(
                                      context: dialogContext,
                                      initialDate: selectedDate.isBefore(now)
                                          ? now
                                          : selectedDate,
                                      firstDate: DateTime(
                                        now.year,
                                        now.month,
                                        now.day,
                                      ),
                                      lastDate: now.add(
                                        const Duration(days: 365),
                                      ),
                                    );

                                    if (picked == null ||
                                        !dialogContext.mounted) {
                                      return;
                                    }

                                    setDialogState(() {
                                      selectedDate = picked;
                                    });
                                  },
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: _DialogChoiceButton(
                                  icon: Icons.access_time_rounded,
                                  label: 'New time',
                                  value: selectedTime.format(
                                    dialogContext,
                                  ),
                                  onPressed: () async {
                                    final picked = await showTimePicker(
                                      context: dialogContext,
                                      initialTime: selectedTime,
                                    );

                                    if (picked == null ||
                                        !dialogContext.mounted) {
                                      return;
                                    }

                                    setDialogState(() {
                                      selectedTime = picked;
                                    });
                                  },
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          TextField(
                            controller: notesController,
                            minLines: 2,
                            maxLines: 5,
                            maxLength: 2000,
                            decoration: const InputDecoration(
                              labelText: 'Reason or notes',
                              alignLabelWithHint: true,
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            DateFormat(
                              'EEEE, d MMMM yyyy • HH:mm',
                            ).format(newAppointmentAt),
                            style: TextStyle(
                              color: context.cTextPrimary,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () {
                        Navigator.of(dialogContext).pop();
                      },
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      onPressed: () {
                        Navigator.of(dialogContext).pop(
                          _RescheduleResult(
                            appointmentAt: newAppointmentAt,
                            notes: notesController.text.trim(),
                          ),
                        );
                      },
                      child: const Text('Reschedule'),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );

    if (result == null) {
      return;
    }

    if (!result.appointmentAt.isAfter(DateTime.now())) {
      _showMessage(
        'The new appointment time must be in the future.',
        isError: true,
      );
      return;
    }

    await _performAction(
      requestId: request.id,
      successMessage: 'Appointment rescheduled successfully.',
      action: () async {
        await _supabase.rpc(
          'reschedule_specialist_request',
          params: <String, dynamic>{
            'p_request_id': request.id,
            'p_new_appointment_at':
                result.appointmentAt.toUtc().toIso8601String(),
            'p_notes': result.notes.isEmpty ? null : result.notes,
          },
        ).timeout(_requestTimeout);
      },
    );
  }

  Future<void> _requestReferralDocument(
    _SpecialistRequestRecord request,
  ) async {
    final notes = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return TextControllerScope(
          initialText: request.receptionNotes ?? '',
          builder: (notesController) {
            return AlertDialog(
              title: const Text(
                'Request Referral Document',
              ),
              content: SizedBox(
                width: 500,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _dialogRequestSummary(request),
                    const SizedBox(height: 16),
                    TextField(
                      controller: notesController,
                      minLines: 3,
                      maxLines: 6,
                      maxLength: 2000,
                      decoration: const InputDecoration(
                        labelText: 'Instructions to patient',
                        hintText:
                            'Example: Please upload a GP referral letter.',
                        alignLabelWithHint: true,
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.of(dialogContext).pop();
                  },
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () {
                    Navigator.of(dialogContext).pop(
                      notesController.text.trim(),
                    );
                  },
                  child: const Text('Request Document'),
                ),
              ],
            );
          },
        );
      },
    );

    if (notes == null) {
      return;
    }

    await _performAction(
      requestId: request.id,
      successMessage: 'Referral document requested from the patient.',
      action: () async {
        await _supabase.rpc(
          'request_specialist_referral_document',
          params: <String, dynamic>{
            'p_request_id': request.id,
            'p_notes': notes.isEmpty ? null : notes,
          },
        ).timeout(_requestTimeout);
      },
    );
  }

  Future<void> _rejectRequest(
    _SpecialistRequestRecord request,
  ) async {
    String? dialogError;

    final reason = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return TextControllerScope(
          builder: (reasonController) {
            return StatefulBuilder(
              builder: (context, setDialogState) {
                return AlertDialog(
                  title: const Text(
                    'Reject Specialist Request',
                  ),
                  content: SizedBox(
                    width: 500,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _dialogRequestSummary(request),
                        const SizedBox(height: 16),
                        TextField(
                          controller: reasonController,
                          minLines: 3,
                          maxLines: 6,
                          maxLength: 2000,
                          decoration: InputDecoration(
                            labelText: 'Rejection reason',
                            alignLabelWithHint: true,
                            border: const OutlineInputBorder(),
                            errorText: dialogError,
                          ),
                        ),
                      ],
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () {
                        Navigator.of(dialogContext).pop();
                      },
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: CorviaColors.danger,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () {
                        final reason = reasonController.text.trim();

                        if (reason.length < 5) {
                          setDialogState(() {
                            dialogError =
                                'Enter a clear reason of at least 5 characters.';
                          });
                          return;
                        }

                        Navigator.of(dialogContext).pop(reason);
                      },
                      child: const Text('Reject Request'),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );

    if (reason == null) {
      return;
    }

    await _performAction(
      requestId: request.id,
      successMessage: 'Specialist request rejected.',
      action: () async {
        await _supabase.rpc(
          'reject_specialist_request',
          params: <String, dynamic>{
            'p_request_id': request.id,
            'p_reason': reason,
          },
        ).timeout(_requestTimeout);
      },
    );
  }

  Future<void> _performAction({
    required String requestId,
    required String successMessage,
    required Future<void> Function() action,
  }) async {
    if (_busyRequestIds.contains(requestId)) {
      return;
    }

    setState(() {
      _busyRequestIds.add(requestId);
    });

    try {
      await action();

      if (!mounted) {
        return;
      }

      _showMessage(successMessage);
      await _loadRequests(showFullLoader: false);
    } on TimeoutException {
      _showMessage(
        'The server took too long to complete this action.',
        isError: true,
      );
    } catch (error) {
      debugPrint('Specialist request action failed: $error');

      _showMessage(
        _friendlyError(error),
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          _busyRequestIds.remove(requestId);
        });
      }
    }
  }

  Widget _dialogRequestSummary(
    _SpecialistRequestRecord request,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: context.cBgPrimary,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(
          color: context.cDivider,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            request.patient.fullName,
            style: TextStyle(
              color: context.cTextPrimary,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${request.requestedSpecialty} • ${request.hospitalName}',
            style: TextStyle(
              color: context.cTextSecondary,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            request.reason,
            style: TextStyle(
              color: context.cTextPrimary,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
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

    if (lower.contains('permission denied') ||
        lower.contains('row-level security') ||
        lower.contains('42501')) {
      return 'Your reception account does not have permission to manage this specialist request.';
    }

    if (lower.contains('function') && lower.contains('does not exist')) {
      return 'The specialist database function is missing or has the wrong parameters.';
    }

    if (lower.contains('not found') || lower.contains('could not be found')) {
      return 'The specialist request could not be found. Refresh the page and try again.';
    }

    if (lower.contains('future')) {
      return 'Select an appointment date and time in the future.';
    }

    if (lower.contains('network') ||
        lower.contains('socketexception') ||
        lower.contains('failed host lookup')) {
      return 'Could not connect to Corvia. Check the connection and try again.';
    }

    return message
        .replaceFirst('Exception: ', '')
        .replaceFirst('PostgrestException(message: ', '')
        .replaceAll(')', '');
  }

  List<Map<String, dynamic>> _rows(dynamic response) {
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
        .replaceAll(RegExp(r'[\s-]+'), '_')
        .replaceAll(RegExp(r'_+'), '_');
  }

  int _asInt(
    dynamic value, {
    required int fallback,
  }) {
    if (value is int) {
      return value;
    }

    if (value is num) {
      return value.toInt();
    }

    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }

  DateTime? _parseDate(dynamic value) {
    final text = value?.toString().trim();

    if (text == null || text.isEmpty || text == 'null') {
      return null;
    }

    return DateTime.tryParse(text)?.toLocal();
  }

  String _normaliseSearch(String value) {
    return value
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ');
  }

  int _countStatus(String status) {
    return _requests
        .where(
          (request) => request.status == status,
        )
        .length;
  }

  int get _activeCount {
    return _requests
        .where(
          (request) => !request.isClosed,
        )
        .length;
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

  Future<void> _refresh() {
    return _loadRequests(
      showFullLoader: false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.cBgPrimary,
      appBar: AppBar(
        title: const Text(
          'Specialist Requests',
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh specialist requests',
            onPressed: _loading || _refreshing ? null : _refresh,
            icon: const Icon(
              Icons.refresh_rounded,
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: _buildBody(),
          ),
          if (_refreshing)
            const Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: LinearProgressIndicator(),
            ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading && _requests.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (_error != null && _requests.isEmpty) {
      return RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(24),
          children: [
            const SizedBox(height: 100),
            Icon(
              Icons.cloud_off_rounded,
              size: 60,
              color: CorviaColors.danger,
            ),
            const SizedBox(height: 16),
            Text(
              'Specialist requests could not load.',
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
              onPressed: () {
                _loadRequests(
                  showFullLoader: true,
                );
              },
              icon: const Icon(
                Icons.refresh_rounded,
              ),
              label: const Text('Try Again'),
            ),
          ],
        ),
      );
    }

    final visibleRequests = _visibleRequests;

    return RefreshIndicator(
      color: CorviaColors.accent,
      onRefresh: _refresh,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final horizontalPadding = constraints.maxWidth >= 1000 ? 28.0 : 16.0;

          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(
              horizontalPadding,
              16,
              horizontalPadding,
              30,
            ),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: 1200,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _summaryHeader(),
                      const SizedBox(height: 18),
                      _searchAndFilters(),
                      const SizedBox(height: 18),
                      if (visibleRequests.isEmpty)
                        _emptyState()
                      else
                        ...visibleRequests.map(
                          (request) {
                            return Padding(
                              padding: const EdgeInsets.only(
                                bottom: 12,
                              ),
                              child: _requestCard(request),
                            );
                          },
                        ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _summaryHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Reception Specialist Workflow',
          style: TextStyle(
            color: context.cTextPrimary,
            fontSize: 23,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          'Assign specialists, confirm appointments, request referrals, reschedule or reject requests.',
          style: TextStyle(
            color: context.cTextSecondary,
          ),
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 800 ? 4 : 2;

            return GridView.count(
              crossAxisCount: columns,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: columns == 4 ? 2.0 : 1.65,
              children: [
                _summaryCard(
                  label: 'Active',
                  value: _activeCount,
                  icon: Icons.pending_actions_rounded,
                  color: CorviaColors.accent,
                ),
                _summaryCard(
                  label: 'Pending',
                  value: _countStatus('pending'),
                  icon: Icons.hourglass_top_rounded,
                  color: Colors.orange.shade800,
                ),
                _summaryCard(
                  label: 'Assigned',
                  value: _countStatus('assigned'),
                  icon: Icons.person_search_rounded,
                  color: Colors.deepPurple,
                ),
                _summaryCard(
                  label: 'Confirmed',
                  value: _countStatus('confirmed'),
                  icon: Icons.event_available_rounded,
                  color: Colors.green.shade700,
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _summaryCard({
    required String label,
    required int value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.cBgSecondary,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: color.withValues(alpha: 0.28),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(
              icon,
              color: color,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  value.toString(),
                  style: TextStyle(
                    color: context.cTextPrimary,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  label,
                  style: TextStyle(
                    color: context.cTextSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _searchAndFilters() {
    return Column(
      children: [
        TextField(
          controller: _searchController,
          onChanged: (_) {
            setState(() {});
          },
          decoration: InputDecoration(
            hintText: 'Search patient, specialty, hospital or specialist',
            prefixIcon: const Icon(
              Icons.search_rounded,
            ),
            suffixIcon: _searchController.text.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Clear search',
                    onPressed: () {
                      _searchController.clear();
                      setState(() {});
                    },
                    icon: const Icon(
                      Icons.clear_rounded,
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <String>[
              'active',
              'all',
              'pending',
              'assigned',
              'confirmed',
              'rescheduled',
              'referral_required',
              'rejected',
              'cancelled',
            ].map(
              (status) {
                return ChoiceChip(
                  label: Text(
                    _prettyValue(status),
                  ),
                  selected: _statusFilter == status,
                  onSelected: (_) {
                    setState(() {
                      _statusFilter = status;
                    });
                  },
                );
              },
            ).toList(),
          ),
        ),
      ],
    );
  }

  Widget _emptyState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: context.cBgSecondary,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: context.cDivider,
        ),
      ),
      child: Column(
        children: [
          Icon(
            Icons.medical_information_outlined,
            size: 52,
            color: context.cTextSecondary,
          ),
          const SizedBox(height: 12),
          Text(
            'No specialist requests found.',
            style: TextStyle(
              color: context.cTextPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            'New patient and doctor specialist requests will appear here.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: context.cTextSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _requestCard(
    _SpecialistRequestRecord request,
  ) {
    final statusColor = _statusColor(request.status);
    final isBusy = _busyRequestIds.contains(request.id);

    return Container(
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: context.cBgSecondary,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: statusColor.withValues(alpha: 0.30),
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
                      request.patient.fullName,
                      style: TextStyle(
                        color: context.cTextPrimary,
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      request.patient.patientNumber,
                      style: TextStyle(
                        color: context.cTextSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              _statusBadge(
                _prettyValue(request.status),
                statusColor,
              ),
            ],
          ),
          const SizedBox(height: 15),
          Wrap(
            spacing: 18,
            runSpacing: 10,
            children: [
              _detail(
                Icons.medical_services_outlined,
                request.requestedSpecialty,
              ),
              _detail(
                Icons.local_hospital_outlined,
                request.hospitalName,
              ),
              _detail(
                Icons.priority_high_rounded,
                _prettyValue(request.urgency),
              ),
              _detail(
                Icons.description_outlined,
                _prettyValue(request.referralStatus),
              ),
              if (request.assignedDoctorName != null)
                _detail(
                  Icons.person_outline_rounded,
                  request.assignedDoctorName!,
                ),
            ],
          ),
          if (request.preferredAppointmentAt != null) ...[
            const SizedBox(height: 12),
            _datePanel(
              label: 'Patient preferred',
              date: request.preferredAppointmentAt!,
              icon: Icons.event_outlined,
            ),
          ],
          if (request.finalAppointmentAt != null) ...[
            const SizedBox(height: 8),
            _datePanel(
              label: 'Final appointment',
              date: request.finalAppointmentAt!,
              icon: Icons.event_available_rounded,
            ),
          ],
          const SizedBox(height: 13),
          Text(
            'Reason',
            style: TextStyle(
              color: context.cTextSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            request.reason,
            style: TextStyle(
              color: context.cTextPrimary,
              height: 1.35,
            ),
          ),
          if (request.receptionNotes != null) ...[
            const SizedBox(height: 12),
            _noticePanel(
              icon: Icons.notes_outlined,
              title: 'Reception notes',
              text: request.receptionNotes!,
              color: Colors.blueGrey,
            ),
          ],
          if (request.referralDocumentUrl != null) ...[
            const SizedBox(height: 12),
            _noticePanel(
              icon: Icons.attach_file_rounded,
              title: 'Referral document received',
              text: request.referralDocumentUrl!,
              color: Colors.green,
            ),
          ],
          if (request.rejectionReason != null) ...[
            const SizedBox(height: 12),
            _noticePanel(
              icon: Icons.cancel_outlined,
              title: 'Rejection reason',
              text: request.rejectionReason!,
              color: CorviaColors.danger,
            ),
          ],
          const SizedBox(height: 16),
          if (isBusy)
            const LinearProgressIndicator()
          else
            _requestActions(request),
        ],
      ),
    );
  }

  Widget _requestActions(
    _SpecialistRequestRecord request,
  ) {
    if (request.isClosed) {
      return Text(
        'This request is closed.',
        style: TextStyle(
          color: context.cTextSecondary,
          fontStyle: FontStyle.italic,
        ),
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        OutlinedButton.icon(
          onPressed: () {
            _assignSpecialist(request);
          },
          icon: const Icon(
            Icons.person_add_alt_1_rounded,
          ),
          label: Text(
            request.assignedDoctorId == null
                ? 'Assign Specialist'
                : 'Change Specialist',
          ),
        ),
        FilledButton.icon(
          onPressed: () {
            _confirmRequest(request);
          },
          icon: const Icon(
            Icons.event_available_rounded,
          ),
          label: Text(
            request.status == 'confirmed'
                ? 'Update Confirmation'
                : 'Confirm Appointment',
          ),
        ),
        if (request.status == 'confirmed' || request.status == 'rescheduled')
          OutlinedButton.icon(
            onPressed: () {
              _rescheduleRequest(request);
            },
            icon: const Icon(
              Icons.edit_calendar_outlined,
            ),
            label: const Text('Reschedule'),
          ),
        OutlinedButton.icon(
          onPressed: () {
            _requestReferralDocument(request);
          },
          icon: const Icon(
            Icons.upload_file_outlined,
          ),
          label: const Text('Request Referral'),
        ),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: CorviaColors.danger,
          ),
          onPressed: () {
            _rejectRequest(request);
          },
          icon: const Icon(
            Icons.cancel_outlined,
          ),
          label: const Text('Reject'),
        ),
      ],
    );
  }

  Widget _detail(
    IconData icon,
    String text,
  ) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 16,
          color: context.cTextSecondary,
        ),
        const SizedBox(width: 5),
        ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: 260,
          ),
          child: Text(
            text,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: context.cTextSecondary,
              fontSize: 13,
            ),
          ),
        ),
      ],
    );
  }

  Widget _datePanel({
    required String label,
    required DateTime date,
    required IconData icon,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: context.cBgPrimary,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            color: CorviaColors.accent,
            size: 19,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              '$label: '
              '${DateFormat('EEE, d MMM yyyy • HH:mm').format(date)}',
              style: TextStyle(
                color: context.cTextPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _noticePanel({
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
          color: color.withValues(alpha: 0.24),
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
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusBadge(
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
}

class _SpecialistRequestRecord {
  const _SpecialistRequestRecord({
    required this.id,
    required this.patient,
    required this.hospitalId,
    required this.hospitalName,
    required this.requestedSpecialty,
    required this.preferredAppointmentAt,
    required this.finalAppointmentAt,
    required this.createdAt,
    required this.reason,
    required this.urgency,
    required this.referralStatus,
    required this.status,
    required this.assignedDoctorId,
    required this.assignedDoctorName,
    required this.durationMinutes,
    required this.appointmentId,
    required this.receptionNotes,
    required this.rejectionReason,
    required this.referralDocumentUrl,
  });

  final String id;
  final _PatientSummary patient;

  final String? hospitalId;
  final String hospitalName;

  final String requestedSpecialty;

  final DateTime? preferredAppointmentAt;
  final DateTime? finalAppointmentAt;
  final DateTime? createdAt;

  final String reason;
  final String urgency;
  final String referralStatus;
  final String status;

  final String? assignedDoctorId;
  final String? assignedDoctorName;

  final int durationMinutes;

  final String? appointmentId;
  final String? receptionNotes;
  final String? rejectionReason;
  final String? referralDocumentUrl;

  bool get isClosed {
    return status == 'rejected' || status == 'cancelled';
  }
}

class _PatientSummary {
  const _PatientSummary({
    required this.id,
    required this.fullName,
    required this.patientNumber,
  });

  final String id;
  final String fullName;
  final String patientNumber;
}

class _DoctorSummary {
  const _DoctorSummary({
    required this.id,
    required this.name,
    required this.specialty,
    required this.hospitalId,
  });

  final String id;
  final String name;
  final String specialty;
  final String? hospitalId;
}

class _AssignResult {
  const _AssignResult({
    required this.doctorId,
    required this.notes,
  });

  final String doctorId;
  final String notes;
}

class _ConfirmResult {
  const _ConfirmResult({
    required this.doctorId,
    required this.appointmentAt,
    required this.durationMinutes,
    required this.notes,
  });

  final String doctorId;
  final DateTime appointmentAt;
  final int durationMinutes;
  final String notes;
}

class _RescheduleResult {
  const _RescheduleResult({
    required this.appointmentAt,
    required this.notes,
  });

  final DateTime appointmentAt;
  final String notes;
}

class _DialogChoiceButton extends StatelessWidget {
  const _DialogChoiceButton({
    required this.icon,
    required this.label,
    required this.value,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.cBgPrimary,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(12),
        child: Container(
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
                color: CorviaColors.accent,
                size: 20,
              ),
              const SizedBox(width: 9),
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

extension _FirstOrNullExtension<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;

    if (!iterator.moveNext()) {
      return null;
    }

    return iterator.current;
  }
}
