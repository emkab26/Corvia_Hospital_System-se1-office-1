import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/nurse_service.dart';
import '../../theme/app_theme.dart';

import 'hospital_nurse_tracker_page.dart';
import 'hospital_page_shared.dart';

class HospitalPatientsPage
    extends StatefulWidget {
  const HospitalPatientsPage({
    super.key,
  });

  @override
  State<HospitalPatientsPage>
      createState() {
    return _HospitalPatientsPageState();
  }
}

class _HospitalPatientsPageState
    extends State<HospitalPatientsPage> {
  final SupabaseClient _supabase =
      Supabase.instance.client;

  final NurseService _nurseService =
      NurseService();

  final TextEditingController
      _searchController =
      TextEditingController();

  bool _loading = true;

  String? _error;
  String? _hospitalId;

  String _hospitalName =
      'Hospital Patients';

  String _filter =
      'All';

  List<Map<String, dynamic>>
      _patients = [];

  List<Map<String, dynamic>>
      _emergencyProfiles = [];

  List<Map<String, dynamic>>
      _hospitalNurses = [];

  List<Map<String, dynamic>>
      _assignments = [];

  Map<String, Map<String, dynamic>>
      _profiles = {};

  static const List<String> _shiftTypes = [
    'Day Shift',
    'Night Shift',
    'Morning Shift',
    'Afternoon Shift',
    'Weekend Shift',
    'Overtime Shift',
  ];

  @override
  void initState() {
    super.initState();

    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();

    super.dispose();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final scope =
          await HospitalAdminScope.load(
        _supabase,
        fallbackName:
            'Hospital Patients',
      );

      _hospitalId =
          scope.hospitalId;

      _hospitalName =
          scope.hospitalName;

      final patientResponse =
          await _supabase
              .from('patients')
              .select()
              .eq(
                'hospital_id',
                scope.hospitalId,
              )
              .limit(
                500,
              );

      _patients =
          HospitalDataTools.rows(
        patientResponse,
      );

      _profiles =
          await HospitalDataTools.loadProfiles(
        _supabase,
        _patients,
      );

      await Future.wait([
        _loadEmergencyProfiles(),
        _loadNurses(),
        _loadAssignments(
          scope.hospitalId,
        ),
      ]);

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
        _error = _clean(
          error,
        );
      });
    }
  }

  Future<void> _loadEmergencyProfiles() async {
    try {
      final response =
          await _supabase
              .from(
                'emergency_profiles',
              )
              .select()
              .limit(
                1000,
              );

      _emergencyProfiles =
          HospitalDataTools.rows(
        response,
      );
    } catch (_) {
      _emergencyProfiles = [];
    }
  }

  Future<void> _loadNurses() async {
    _hospitalNurses =
        await _nurseService
            .loadAdminHospitalNurses();
  }

  Future<void> _loadAssignments(
    String hospitalId,
  ) async {
    _assignments =
        await _nurseService
            .loadAdminAssignments(
      hospitalId,
    );
  }

  String _patientName(
    Map<String, dynamic> patient,
  ) {
    return HospitalDataTools.personName(
      patient,
      _profiles,
      fallback:
          'Patient profile not linked',
    );
  }

  String _patientPhone(
    Map<String, dynamic> patient,
  ) {
    return HospitalDataTools.phone(
      patient,
      _profiles,
      fallback:
          'No phone number',
    );
  }

  String _patientEmail(
    Map<String, dynamic> patient,
  ) {
    return HospitalDataTools.email(
      patient,
      _profiles,
      fallback:
          'No email',
    );
  }

  String _patientIdNumber(
    Map<String, dynamic> patient,
  ) {
    final profile =
        HospitalDataTools.profileFor(
      patient,
      _profiles,
    );

    for (final value in [
      patient['id_number'],
      patient['identity_number'],
      patient['national_id'],
      profile?['id_number'],
      profile?['identity_number'],
    ]) {
      final text =
          value?.toString().trim();

      if (text != null &&
          text.isNotEmpty) {
        return text;
      }
    }

    return 'No ID number';
  }

  String _patientStatus(
    Map<String, dynamic> patient,
  ) {
    final status =
        patient['status']
            ?.toString()
            .trim();

    if (status != null &&
        status.isNotEmpty) {
      return status;
    }

    return patient['is_active'] ==
            false
        ? 'Inactive'
        : 'Active';
  }

  List<Map<String, dynamic>>
      _assignmentsForPatient(
    Map<String, dynamic> patient,
  ) {
    final patientId =
        patient['id']
            ?.toString();

    if (patientId == null) {
      return [];
    }

    return _assignments.where(
      (
        assignment,
      ) {
        return assignment['patient_id']
                    ?.toString() ==
                patientId &&
            assignment['status']
                    ?.toString()
                    .toLowerCase() ==
                'active';
      },
    ).toList();
  }

  Map<String, dynamic>? _nurseByUserId(
    String? userId,
  ) {
    if (userId == null ||
        userId.isEmpty) {
      return null;
    }

    for (final nurse
        in _hospitalNurses) {
      if (nurse['nurse_user_id']
              ?.toString() ==
          userId) {
        return nurse;
      }
    }

    return null;
  }

  String _assignmentNurseName(
    Map<String, dynamic> assignment,
  ) {
    final nurse =
        _nurseByUserId(
      assignment['nurse_user_id']
          ?.toString(),
    );

    if (nurse != null) {
      return nurse['nurse_name']
              ?.toString() ??
          'Nurse';
    }

    return assignment['nurse_name']
            ?.toString() ??
        'Assigned Nurse';
  }

  List<String> _nurseNames(
    Map<String, dynamic> patient,
  ) {
    return _assignmentsForPatient(
      patient,
    )
        .map(
          _assignmentNurseName,
        )
        .toSet()
        .toList();
  }

  bool _hasEmergencyProfile(
    Map<String, dynamic> patient,
  ) {
    final keys =
        <String>{};

    void addKeys(
      Map<String, dynamic>? row,
    ) {
      if (row == null) {
        return;
      }

      for (final key in [
        'id',
        'patient_id',
        'profile_id',
        'user_id',
      ]) {
        final value =
            row[key]
                ?.toString()
                .trim();

        if (value != null &&
            value.isNotEmpty) {
          keys.add(
            value,
          );
        }
      }
    }

    addKeys(
      patient,
    );

    addKeys(
      HospitalDataTools.profileFor(
        patient,
        _profiles,
      ),
    );

    for (final emergency
        in _emergencyProfiles) {
      for (final key in [
        'id',
        'patient_id',
        'profile_id',
        'user_id',
      ]) {
        final value =
            emergency[key]
                ?.toString()
                .trim();

        if (value != null &&
            keys.contains(
              value,
            )) {
          return true;
        }
      }
    }

    return false;
  }

  List<Map<String, dynamic>>
      get _visible {
    final search =
        _searchController.text
            .trim()
            .toLowerCase();

    return _patients.where(
      (
        patient,
      ) {
        final assigned =
            _assignmentsForPatient(
          patient,
        );

        final status =
            _patientStatus(
          patient,
        ).toLowerCase();

        final nurseSearch =
            _nurseNames(
          patient,
        ).join(' ').toLowerCase();

        final matchesSearch =
            search.isEmpty ||
                _patientName(
                  patient,
                )
                    .toLowerCase()
                    .contains(
                      search,
                    ) ||
                _patientPhone(
                  patient,
                )
                    .toLowerCase()
                    .contains(
                      search,
                    ) ||
                _patientEmail(
                  patient,
                )
                    .toLowerCase()
                    .contains(
                      search,
                    ) ||
                _patientIdNumber(
                  patient,
                )
                    .toLowerCase()
                    .contains(
                      search,
                    ) ||
                nurseSearch.contains(
                  search,
                );

        final matchesFilter =
            _filter == 'All' ||
                (_filter == 'Active' &&
                    !status.contains(
                      'inactive',
                    )) ||
                (_filter == 'Inactive' &&
                    status.contains(
                      'inactive',
                    )) ||
                (_filter == 'Emergency Ready' &&
                    _hasEmergencyProfile(
                      patient,
                    )) ||
                (_filter == 'Nurse Assigned' &&
                    assigned.isNotEmpty) ||
                (_filter ==
                        'No Nurse Assigned' &&
                    assigned.isEmpty);

        return matchesSearch &&
            matchesFilter;
      },
    ).toList();
  }

  Future<void> _openNurseTracker() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) {
          return const HospitalNurseTrackerPage();
        },
      ),
    );

    if (mounted) {
      await _load();
    }
  }

  Future<void> _manageNurses(
    Map<String, dynamic> patient,
  ) async {
    final hospitalId =
        _hospitalId;

    if (hospitalId == null ||
        hospitalId.isEmpty) {
      _message(
        'Hospital context is unavailable.',
      );
      return;
    }

    if (_hospitalNurses.isEmpty) {
      final openTracker =
          await showDialog<bool>(
        context:
            context,
        builder:
            (
              dialogContext,
            ) {
          return AlertDialog(
            title:
                const Text(
              'No Hospital Nurses',
            ),
            content:
                const Text(
              'No nurses are currently linked to this hospital. '
              'Open Nurse Tracker to link a nurse first.',
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
                child:
                    const Text(
                  'Cancel',
                ),
              ),
              FilledButton(
                onPressed: () {
                  Navigator.of(
                    dialogContext,
                  ).pop(
                    true,
                  );
                },
                child:
                    const Text(
                  'Nurse Tracker',
                ),
              ),
            ],
          );
        },
      );

      if (openTracker == true &&
          mounted) {
        await _openNurseTracker();
      }

      return;
    }

    final current =
        _assignmentsForPatient(
      patient,
    );

    final assignedUserIds =
        current
            .map(
              (
                assignment,
              ) =>
                  assignment['nurse_user_id']
                      ?.toString(),
            )
            .whereType<String>()
            .toSet();

    final available =
        _hospitalNurses.where(
      (
        nurse,
      ) {
        final active =
            nurse['is_active'] ==
                true;

        final userId =
            nurse['nurse_user_id']
                ?.toString();

        return active &&
            userId != null &&
            !assignedUserIds.contains(
              userId,
            );
      },
    ).toList();

    final wardController =
        TextEditingController();

    final notesController =
        TextEditingController();

    String shiftType =
        'Day Shift';

    String? selectedProfileId =
        available.isEmpty
            ? null
            : available.first['profile_id']
                ?.toString();

    bool saving =
        false;

    await showDialog<void>(
      context:
          context,
      barrierDismissible:
          false,
      builder:
          (
            dialogContext,
          ) {
        return StatefulBuilder(
          builder:
              (
                context,
                setDialogState,
              ) {
            return AlertDialog(
              title:
                  Text(
                'Manage Nurses • '
                '${_patientName(patient)}',
              ),
              content:
                  SizedBox(
                width:
                    560,
                child:
                    SingleChildScrollView(
                  child:
                      Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Current assignments',
                        style:
                            TextStyle(
                          color:
                              context.cTextPrimary,
                          fontWeight:
                              FontWeight.bold,
                        ),
                      ),
                      const SizedBox(
                        height: 10,
                      ),
                      if (current.isEmpty)
                        Text(
                          'No nurse currently assigned.',
                          style:
                              TextStyle(
                            color:
                                context.cTextSecondary,
                          ),
                        )
                      else
                        ...current.map(
                          (
                            assignment,
                          ) {
                            return Container(
                              margin:
                                  const EdgeInsets.only(
                                bottom:
                                    8,
                              ),
                              padding:
                                  const EdgeInsets.all(
                                12,
                              ),
                              decoration:
                                  BoxDecoration(
                                color:
                                    context.cBgPrimary,
                                borderRadius:
                                    BorderRadius.circular(
                                  12,
                                ),
                                border:
                                    Border.all(
                                  color:
                                      context.cDivider,
                                ),
                              ),
                              child:
                                  Row(
                                children: [
                                  const Icon(
                                    Icons.medical_services_outlined,
                                  ),
                                  const SizedBox(
                                    width:
                                        9,
                                  ),
                                  Expanded(
                                    child:
                                        Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          _assignmentNurseName(
                                            assignment,
                                          ),
                                          style:
                                              TextStyle(
                                            color:
                                                context.cTextPrimary,
                                            fontWeight:
                                                FontWeight.bold,
                                          ),
                                        ),
                                        Text(
                                          '${assignment['ward'] ?? 'No ward'} • '
                                          '${assignment['shift_type'] ?? 'No shift'}',
                                          style:
                                              TextStyle(
                                            color:
                                                context.cTextSecondary,
                                            fontSize:
                                                12,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    tooltip:
                                        'End assignment',
                                    onPressed:
                                        saving
                                            ? null
                                            : () async {
                                                setDialogState(() {
                                                  saving =
                                                      true;
                                                });

                                                try {
                                                  await _nurseService
                                                      .endAssignment(
                                                    assignmentId:
                                                        assignment['id']
                                                            .toString(),
                                                  );

                                                  if (dialogContext.mounted) {
                                                    Navigator.of(
                                                      dialogContext,
                                                    ).pop();
                                                  }

                                                  await _load();

                                                  _message(
                                                    'Nurse assignment ended.',
                                                  );
                                                } catch (error) {
                                                  setDialogState(() {
                                                    saving =
                                                        false;
                                                  });

                                                  _message(
                                                    'Could not end assignment. '
                                                    '${_clean(error)}',
                                                  );
                                                }
                                              },
                                    icon:
                                        Icon(
                                      Icons.person_remove_alt_1,
                                      color:
                                          CorviaColors.danger,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      const SizedBox(
                        height: 18,
                      ),
                      Divider(
                        color:
                            context.cDivider,
                      ),
                      const SizedBox(
                        height: 12,
                      ),
                      Text(
                        'Add nurse',
                        style:
                            TextStyle(
                          color:
                              context.cTextPrimary,
                          fontWeight:
                              FontWeight.bold,
                        ),
                      ),
                      const SizedBox(
                        height: 12,
                      ),
                      if (available.isEmpty)
                        Text(
                          'All linked nurses are already assigned to this patient.',
                          style:
                              TextStyle(
                            color:
                                context.cTextSecondary,
                          ),
                        )
                      else ...[
                        DropdownButtonFormField<String>(
                          initialValue:
                              selectedProfileId,
                          isExpanded:
                              true,
                          decoration:
                              const InputDecoration(
                            labelText:
                                'Hospital Nurse',
                            border:
                                OutlineInputBorder(),
                          ),
                          items:
                              available.map(
                            (
                              nurse,
                            ) {
                              return DropdownMenuItem<String>(
                                value:
                                    nurse['profile_id']
                                        ?.toString(),
                                child:
                                    Text(
                                  nurse['nurse_name']
                                          ?.toString() ??
                                      'Nurse',
                                ),
                              );
                            },
                          ).toList(),
                          onChanged:
                              saving
                                  ? null
                                  : (
                                      value,
                                    ) {
                                      selectedProfileId =
                                          value;
                                    },
                        ),
                        const SizedBox(
                          height: 12,
                        ),
                        TextField(
                          controller:
                              wardController,
                          enabled:
                              !saving,
                          decoration:
                              const InputDecoration(
                            labelText:
                                'Ward or Department',
                            border:
                                OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(
                          height: 12,
                        ),
                        DropdownButtonFormField<String>(
                          initialValue:
                              shiftType,
                          decoration:
                              const InputDecoration(
                            labelText:
                                'Shift Type',
                            border:
                                OutlineInputBorder(),
                          ),
                          items:
                              _shiftTypes.map(
                            (
                              value,
                            ) {
                              return DropdownMenuItem<String>(
                                value:
                                    value,
                                child:
                                    Text(
                                  value,
                                ),
                              );
                            },
                          ).toList(),
                          onChanged:
                              saving
                                  ? null
                                  : (
                                      value,
                                    ) {
                                      if (value != null) {
                                        shiftType =
                                            value;
                                      }
                                    },
                        ),
                        const SizedBox(
                          height: 12,
                        ),
                        TextField(
                          controller:
                              notesController,
                          enabled:
                              !saving,
                          minLines:
                              2,
                          maxLines:
                              4,
                          decoration:
                              const InputDecoration(
                            labelText:
                                'Assignment Notes',
                            border:
                                OutlineInputBorder(),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed:
                      saving
                          ? null
                          : () {
                              Navigator.of(
                                dialogContext,
                              ).pop();
                            },
                  child:
                      const Text(
                    'Close',
                  ),
                ),
                if (available.isNotEmpty)
                  FilledButton.icon(
                    onPressed:
                        saving
                            ? null
                            : () async {
                                final patientId =
                                    patient['id']
                                        ?.toString();

                                if (patientId == null ||
                                    selectedProfileId == null) {
                                  _message(
                                    'Select a nurse first.',
                                  );
                                  return;
                                }

                                setDialogState(() {
                                  saving =
                                      true;
                                });

                                try {
                                  await _nurseService.assignNurse(
                                    patientId:
                                        patientId,
                                    nurseProfileId:
                                        selectedProfileId!,
                                    ward:
                                        wardController.text,
                                    shiftType:
                                        shiftType,
                                    notes:
                                        notesController.text,
                                  );

                                  if (dialogContext.mounted) {
                                    Navigator.of(
                                      dialogContext,
                                    ).pop();
                                  }

                                  await _load();

                                  _message(
                                    'Nurse assigned successfully.',
                                  );
                                } catch (error) {
                                  setDialogState(() {
                                    saving =
                                        false;
                                  });

                                  _message(
                                    'Could not assign nurse. '
                                    '${_clean(error)}',
                                  );
                                }
                              },
                    icon:
                        const Icon(
                      Icons.person_add_alt_1,
                    ),
                    label:
                        Text(
                      saving
                          ? 'Saving...'
                          : 'Assign Nurse',
                    ),
                  ),
              ],
            );
          },
        );
      },
    );

    wardController.dispose();
    notesController.dispose();
  }

  String _clean(
    Object error,
  ) {
    return error
        .toString()
        .replaceFirst(
          'Exception: ',
          '',
        )
        .replaceFirst(
          'PostgrestException(message: ',
          '',
        );
  }

  void _message(
    String message,
  ) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content:
              Text(
            message,
          ),
        ),
      );
  }

  @override
  Widget build(
    BuildContext context,
  ) {
    final visible =
        _visible;

    return Scaffold(
      backgroundColor:
          context.cBgPrimary,
      body:
          SafeArea(
        child:
            RefreshIndicator(
          onRefresh:
              _load,
          child:
              _loading
                  ? ListView(
                      children: const [
                        SizedBox(
                          height:
                              500,
                          child:
                              Center(
                            child:
                                CircularProgressIndicator(),
                          ),
                        ),
                      ],
                    )
                  : SingleChildScrollView(
                      physics:
                          const AlwaysScrollableScrollPhysics(),
                      padding:
                          const EdgeInsets.all(
                        24,
                      ),
                      child:
                          Column(
                        crossAxisAlignment:
                            CrossAxisAlignment.start,
                        children: [
                          HospitalPageHeader(
                            title:
                                'Patients • $_hospitalName',
                            subtitle:
                                'Hospital patients and hospital-scoped nurse assignments.',
                            onRefresh:
                                _load,
                          ),
                          const SizedBox(
                            height: 12,
                          ),
                          Align(
                            alignment:
                                Alignment.centerRight,
                            child:
                                FilledButton.icon(
                              onPressed:
                                  _openNurseTracker,
                              icon:
                                  const Icon(
                                Icons.monitor_heart_outlined,
                              ),
                              label:
                                  const Text(
                                'Nurse Tracker',
                              ),
                            ),
                          ),
                          const SizedBox(
                            height: 18,
                          ),
                          if (_error != null)
                            Container(
                              padding:
                                  const EdgeInsets.all(
                                14,
                              ),
                              width:
                                  double.infinity,
                              decoration:
                                  BoxDecoration(
                                color:
                                    CorviaColors.danger.withValues(
                                  alpha:
                                      0.08,
                                ),
                                borderRadius:
                                    BorderRadius.circular(
                                  14,
                                ),
                              ),
                              child:
                                  Text(
                                _error!,
                              ),
                            ),
                          HospitalStatGrid(
                            items: [
                              HospitalStatItem(
                                title:
                                    'Patients',
                                value:
                                    '${_patients.length}',
                                subtitle:
                                    'Linked to hospital',
                                icon:
                                    Icons.people_alt,
                                color:
                                    context.cAccentReadable,
                              ),
                              HospitalStatItem(
                                title:
                                    'Hospital Nurses',
                                value:
                                    '${_hospitalNurses.length}',
                                subtitle:
                                    'Canonical nurse links',
                                icon:
                                    Icons.medical_services,
                                color:
                                    CorviaColors.accent,
                              ),
                              HospitalStatItem(
                                title:
                                    'Assigned Patients',
                                value:
                                    '${_patients.where((p) => _assignmentsForPatient(p).isNotEmpty).length}',
                                subtitle:
                                    'With active nurse assignment',
                                icon:
                                    Icons.assignment_ind,
                                color:
                                    CorviaColors.success,
                              ),
                              HospitalStatItem(
                                title:
                                    'Emergency Ready',
                                value:
                                    '${_patients.where(_hasEmergencyProfile).length}',
                                subtitle:
                                    'Emergency profile exists',
                                icon:
                                    Icons.emergency,
                                color:
                                    CorviaColors.danger,
                              ),
                            ],
                          ),
                          const SizedBox(
                            height: 22,
                          ),
                          HospitalPanel(
                            title:
                                'Hospital Patient Directory',
                            subtitle:
                                '${visible.length} patient(s) shown',
                            icon:
                                Icons.people_alt,
                            child:
                                Column(
                              children: [
                                HospitalSearchBox(
                                  controller:
                                      _searchController,
                                  hint:
                                      'Search patient, ID, phone, email or nurse',
                                  onChanged:
                                      (_) {
                                    setState(() {});
                                  },
                                ),
                                const SizedBox(
                                  height: 12,
                                ),
                                Wrap(
                                  spacing:
                                      8,
                                  runSpacing:
                                      8,
                                  children:
                                      [
                                    'All',
                                    'Active',
                                    'Inactive',
                                    'Emergency Ready',
                                    'Nurse Assigned',
                                    'No Nurse Assigned',
                                  ].map(
                                    (
                                      value,
                                    ) {
                                      return ChoiceChip(
                                        label:
                                            Text(
                                          value,
                                        ),
                                        selected:
                                            _filter ==
                                                value,
                                        onSelected:
                                            (_) {
                                          setState(() {
                                            _filter =
                                                value;
                                          });
                                        },
                                      );
                                    },
                                  ).toList(),
                                ),
                                const SizedBox(
                                  height: 18,
                                ),
                                if (visible.isEmpty)
                                  const HospitalEmptyState(
                                    icon:
                                        Icons.people_outline,
                                    title:
                                        'No patients found',
                                    message:
                                        'No patient records match the current search or filter.',
                                  )
                                else
                                  ...visible.map(
                                    (
                                      patient,
                                    ) {
                                      final nurses =
                                          _nurseNames(
                                        patient,
                                      );

                                      return Container(
                                        margin:
                                            const EdgeInsets.only(
                                          bottom:
                                              10,
                                        ),
                                        padding:
                                            const EdgeInsets.all(
                                          15,
                                        ),
                                        decoration:
                                            BoxDecoration(
                                          color:
                                              context.cBgPrimary,
                                          borderRadius:
                                              BorderRadius.circular(
                                            17,
                                          ),
                                          border:
                                              Border.all(
                                            color:
                                                context.cDivider,
                                          ),
                                        ),
                                        child:
                                            Row(
                                          children: [
                                            CircleAvatar(
                                              child:
                                                  Text(
                                                _patientName(
                                                  patient,
                                                ).isEmpty
                                                    ? '?'
                                                    : _patientName(
                                                        patient,
                                                      )[0]
                                                        .toUpperCase(),
                                              ),
                                            ),
                                            const SizedBox(
                                              width:
                                                  12,
                                            ),
                                            Expanded(
                                              child:
                                                  Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    _patientName(
                                                      patient,
                                                    ),
                                                    style:
                                                        TextStyle(
                                                      color:
                                                          context.cTextPrimary,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                    ),
                                                  ),
                                                  Text(
                                                    '${_patientIdNumber(patient)} • ${_patientPhone(patient)}',
                                                    style:
                                                        TextStyle(
                                                      color:
                                                          context.cTextSecondary,
                                                      fontSize:
                                                          12,
                                                    ),
                                                  ),
                                                  const SizedBox(
                                                    height:
                                                        5,
                                                  ),
                                                  Text(
                                                    nurses.isEmpty
                                                        ? 'No nurse assigned'
                                                        : 'Nurse: ${nurses.join(', ')}',
                                                    style:
                                                        TextStyle(
                                                      color:
                                                          nurses.isEmpty
                                                              ? context.cTextMuted
                                                              : context.cAccentReadable,
                                                      fontSize:
                                                          12,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            OutlinedButton.icon(
                                              onPressed:
                                                  () {
                                                _manageNurses(
                                                  patient,
                                                );
                                              },
                                              icon:
                                                  const Icon(
                                                Icons.person_add_alt_1,
                                              ),
                                              label:
                                                  Text(
                                                nurses.isEmpty
                                                    ? 'Assign'
                                                    : 'Manage',
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                    },
                                  ),
                              ],
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