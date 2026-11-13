import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/nurse_service.dart';
import '../../theme/app_theme.dart';
import '../forms/corvia_forms_navigator.dart';

class NurseAssignedPatientsPage extends StatefulWidget {
  const NurseAssignedPatientsPage({super.key, this.service, this.showAppBar = true});

  final NurseService? service;

  /// The nurse workspace supplies the shared header when this page is embedded.
  final bool showAppBar;

  @override
  State<NurseAssignedPatientsPage> createState() =>
      _NurseAssignedPatientsPageState();
}

class _NurseAssignedPatientsPageState extends State<NurseAssignedPatientsPage> {
  final SupabaseClient _supabase = Supabase.instance.client;
  late final NurseService _service = widget.service ?? NurseService();
  NurseWorkspace? _workspace;

  final TextEditingController _searchController = TextEditingController();

  bool _isLoading = true;
  bool _isOpeningForm = false;

  String? _errorMessage;
  String? get _currentHospitalId => _workspace?.context.hospitalId;
  String? _openingPatientId;

  String _selectedFilter = 'All';

  List<Map<String, dynamic>> _assignments = [];

  static const List<String> _filters = [
    'All',
    'Day Shift',
    'Night Shift',
    'Other Shifts',
  ];

  @override
  void initState() {
    super.initState();
    _loadAssignedPatients();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadAssignedPatients() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final workspace = await _service.loadWorkspace();
      if (!mounted) return;
      setState(() {
        _workspace = workspace;
        _assignments = workspace.assignments;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = error.toString();
      });
    }
  }

  NursePatient _patient(Map<String, dynamic> assignment) =>
      _workspace!.patient(assignment['patient_id']?.toString());

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

  String _patientName(Map<String, dynamic> assignment) =>
      _patient(assignment).displayName;

  String _patientPhone(Map<String, dynamic> assignment) =>
      _firstText([_patient(assignment).phone], fallback: 'No phone number captured');

  String _patientIdNumber(Map<String, dynamic> assignment) =>
      _firstText([_patient(assignment).idNumber], fallback: 'No ID number captured');

  String _medicalAid(Map<String, dynamic> assignment) =>
      _firstText([_patient(assignment).medicalAidProvider], fallback: 'No medical aid captured');

  String _dateOfBirth(NursePatient patient) {
    final date = patient.dateOfBirth;
    if (date == null) return 'Not captured';
    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/${date.year}';
  }

  String _ward(
    Map<String, dynamic> assignment,
  ) {
    return _firstText(
      [
        assignment['ward'],
      ],
      fallback: 'No ward assigned',
    );
  }

  String _shiftType(
    Map<String, dynamic> assignment,
  ) {
    return _firstText(
      [
        assignment['shift_type'],
      ],
      fallback: 'No shift selected',
    );
  }

  String _assignmentNotes(
    Map<String, dynamic> assignment,
  ) {
    return _firstText(
      [
        assignment['notes'],
      ],
      fallback: 'No assignment notes',
    );
  }

  String _assignmentHospitalId(
    Map<String, dynamic> assignment,
  ) {
    return _firstText(
      [
        assignment['hospital_id'],
        _currentHospitalId,
      ],
      fallback: '',
    );
  }

  String _formatDateTime(
    dynamic value,
  ) {
    if (value == null) {
      return 'Not available';
    }

    try {
      final date = DateTime.parse(
        value.toString(),
      ).toLocal();

      final day = date.day.toString().padLeft(
            2,
            '0',
          );

      final month = date.month.toString().padLeft(
            2,
            '0',
          );

      final year = date.year.toString();

      final hour = date.hour.toString().padLeft(
            2,
            '0',
          );

      final minute = date.minute.toString().padLeft(
            2,
            '0',
          );

      return '$day/$month/$year '
          '$hour:$minute';
    } catch (_) {
      return value.toString();
    }
  }

  List<Map<String, dynamic>> get _visibleAssignments {
    final search = _searchController.text.trim().toLowerCase();

    return _assignments.where(
      (assignment) {
        final patientName = _patientName(
          assignment,
        ).toLowerCase();

        final phone = _patientPhone(
          assignment,
        ).toLowerCase();

        final idNumber = _patientIdNumber(
          assignment,
        ).toLowerCase();

        final ward = _ward(
          assignment,
        ).toLowerCase();

        final shift = _shiftType(
          assignment,
        ).toLowerCase();

        final notes = _assignmentNotes(
          assignment,
        ).toLowerCase();

        final matchesSearch = search.isEmpty ||
            _patient(assignment).patientNumber.toLowerCase().contains(search) ||
            patientName.contains(
              search,
            ) ||
            phone.contains(
              search,
            ) ||
            idNumber.contains(
              search,
            ) ||
            ward.contains(
              search,
            ) ||
            shift.contains(
              search,
            ) ||
            notes.contains(
              search,
            );

        bool matchesFilter = true;

        if (_selectedFilter == 'Day Shift') {
          matchesFilter = shift.contains(
            'day',
          );
        } else if (_selectedFilter == 'Night Shift') {
          matchesFilter = shift.contains(
            'night',
          );
        } else if (_selectedFilter == 'Other Shifts') {
          matchesFilter = !shift.contains(
                'day',
              ) &&
              !shift.contains(
                'night',
              );
        }

        return matchesSearch && matchesFilter;
      },
    ).toList();
  }

  Future<void> _openNursingForms(
    Map<String, dynamic> assignment,
  ) async {
    if (_isOpeningForm) {
      return;
    }

    final patientId = assignment['patient_id']?.toString().trim();

    if (patientId == null || patientId.isEmpty) {
      _showSnackBar(
        'This assignment does not contain a patient ID.',
      );

      return;
    }

    setState(() {
      _isOpeningForm = true;
      _openingPatientId = patientId;
    });

    try {
      final hospitalId = _assignmentHospitalId(
        assignment,
      );

      final admissionId = await _resolveActiveAdmission(
        patientId: patientId,
        hospitalId: hospitalId.isEmpty ? null : hospitalId,
      );

      if (!mounted) {
        return;
      }

      await CorviaFormsNavigator.openPatientForms(
        context,
        patientId: patientId,
        hospitalId: hospitalId.isEmpty ? null : hospitalId,
        admissionId: admissionId,
        contextType: 'nursing',
        contextId: assignment['id']?.toString(),
        title: 'Nursing Forms - ${_patientName(assignment)}',
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      _showSnackBar(
        'Could not open Nursing Forms. $error',
      );
    } finally {
      if (mounted) {
        setState(() {
          _isOpeningForm = false;
          _openingPatientId = null;
        });
      }
    }
  }

  Future<String?> _resolveActiveAdmission({
    required String patientId,
    String? hospitalId,
  }) async {
    try {
      dynamic response;

      if (hospitalId != null && hospitalId.trim().isNotEmpty) {
        response = await _supabase
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
              hospitalId.trim(),
            );
      } else {
        response = await _supabase
            .from(
              'hospital_admissions',
            )
            .select()
            .eq(
              'patient_id',
              patientId,
            );
      }

      final admissions = _mapRows(
        response,
      );

      if (admissions.isEmpty) {
        return null;
      }

      const statusPriority = <String, int>{
        'admitted': 0,
        'active': 1,
        'in_progress': 2,
        'observation': 3,
        'planned': 4,
        'pending': 5,
      };

      admissions.sort(
        (first, second) {
          final firstStatus = _normalise(
            first['status'],
          );

          final secondStatus = _normalise(
            second['status'],
          );

          final firstPriority = statusPriority[firstStatus] ?? 100;

          final secondPriority = statusPriority[secondStatus] ?? 100;

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
        final status = _normalise(
          admission['status'],
        );

        if (!statusPriority.containsKey(
          status,
        )) {
          continue;
        }

        final admissionId = admission['id']?.toString().trim();

        if (admissionId != null && admissionId.isNotEmpty) {
          return admissionId;
        }
      }

      return null;
    } catch (error) {
      debugPrint(
        'Could not resolve active admission: $error',
      );

      /*
       * Some hospital forms do not require an admission.
       * The form engine may therefore still open.
       */
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

  String _normalise(
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

  List<Map<String, dynamic>> _mapRows(
    dynamic response,
  ) {
    if (response is! List) {
      return [];
    }

    return response
        .whereType<Map>()
        .map(
          (row) => Map<String, dynamic>.from(
            row,
          ),
        )
        .toList();
  }

  void _showSnackBar(
    String message,
  ) {
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

  void _showPatientDetails(
    Map<String, dynamic> assignment,
  ) {
    showDialog<void>(
      context: context,
      builder: (
        dialogContext,
      ) {
        final patient = _patient(assignment);
        final patientId = assignment['patient_id']?.toString().trim();

        final opening = patientId != null && patientId == _openingPatientId;

        return AlertDialog(
          title: Text(
            _patientName(
              assignment,
            ),
          ),
          content: SizedBox(
            width: 500,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _detailLine('Patient number', patient.patientNumber),
                  _detailLine(
                    'Email',
                    _firstText([patient.email], fallback: 'Not captured'),
                  ),
                  _detailLine('Date of birth', _dateOfBirth(patient)),
                  _detailLine(
                    'Ward',
                    _ward(
                      assignment,
                    ),
                  ),
                  _detailLine(
                    'Shift',
                    _shiftType(
                      assignment,
                    ),
                  ),
                  _detailLine(
                    'Phone',
                    _patientPhone(
                      assignment,
                    ),
                  ),
                  _detailLine(
                    'ID number',
                    _patientIdNumber(
                      assignment,
                    ),
                  ),
                  _detailLine(
                    'Medical aid',
                    _medicalAid(
                      assignment,
                    ),
                  ),
                  _detailLine(
                    'Medical aid member',
                    _firstText([patient.medicalAidMemberNumber], fallback: 'Not captured'),
                  ),
                  _detailLine(
                    'Medical aid plan',
                    _firstText([patient.medicalAidPlan], fallback: 'Not captured'),
                  ),
                  _detailLine(
                    'Assigned',
                    _formatDateTime(
                      assignment['assigned_at'],
                    ),
                  ),
                  _detailLine(
                    'Assignment notes',
                    _assignmentNotes(
                      assignment,
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: _isOpeningForm
                  ? null
                  : () {
                      Navigator.of(
                        dialogContext,
                      ).pop();
                    },
              child: const Text(
                'Close',
              ),
            ),
            FilledButton.icon(
              onPressed: _isOpeningForm
                  ? null
                  : () async {
                      Navigator.of(
                        dialogContext,
                      ).pop();

                      await _openNursingForms(
                        assignment,
                      );
                    },
              icon: opening
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
              label: const Text(
                'Nursing Forms',
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _detailLine(
    String label,
    String value,
  ) {
    return Padding(
      padding: const EdgeInsets.only(
        bottom: 12,
      ),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '$label: ',
              style: TextStyle(
                color: context.cTextPrimary,
                fontWeight: FontWeight.bold,
              ),
            ),
            TextSpan(
              text: value,
              style: TextStyle(
                color: context.cTextSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(
    BuildContext context,
  ) {
    final visibleAssignments = _visibleAssignments;

    return Scaffold(
      backgroundColor: context.cBgPrimary,
      appBar: widget.showAppBar ? AppBar(
        title: const Text(
          'Assigned Patients',
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed:
                _isLoading || _isOpeningForm ? null : _loadAssignedPatients,
            icon: const Icon(
              Icons.refresh,
            ),
          ),
        ],
      ) : null,
      body: _buildBody(
        visibleAssignments,
      ),
    );
  }

  Widget _buildBody(
    List<Map<String, dynamic>> visibleAssignments,
  ) {
    if (_isLoading) {
      return Center(
        child: CircularProgressIndicator(
          color: CorviaColors.accent,
        ),
      );
    }

    if (_errorMessage != null) {
      return _buildErrorState();
    }

    return RefreshIndicator(
      onRefresh: _loadAssignedPatients,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(
          18,
        ),
        children: [
          _buildSummaryCard(),
          const SizedBox(
            height: 18,
          ),
          TextField(
            controller: _searchController,
            onChanged: (_) {
              setState(() {});
            },
            decoration: InputDecoration(
              prefixIcon: const Icon(
                Icons.search,
              ),
              hintText: 'Search patient, ward, shift or notes',
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
            height: 13,
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _filters.map(
              (filter) {
                return ChoiceChip(
                  label: Text(filter),
                  selected: _selectedFilter == filter,
                  selectedColor: CorviaColors.accent.withValues(
                    alpha: 0.14,
                  ),
                  onSelected: (_) {
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
          if (visibleAssignments.isEmpty)
            _buildEmptyState()
          else
            ...visibleAssignments.map(
              _buildPatientCard,
            ),
          const SizedBox(
            height: 24,
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCard() {
    final wardCount = _assignments
        .map(
          _ward,
        )
        .where(
          (ward) => ward != 'No ward assigned',
        )
        .toSet()
        .length;

    return Container(
      padding: const EdgeInsets.all(
        18,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            CorviaColors.accentDark,
            CorviaColors.accent,
          ],
        ),
        borderRadius: BorderRadius.circular(
          20,
        ),
      ),
      child: Row(
        children: [
          const CircleAvatar(
            radius: 29,
            backgroundColor: Colors.white,
            child: Icon(
              Icons.people_alt_outlined,
              color: Color(0xFF0F766E),
              size: 31,
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
                  'Active patient assignments',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(
                  height: 4,
                ),
                Text(
                  '${_assignments.length} patient assignment(s)',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 19,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(
                  height: 3,
                ),
                Text(
                  '$wardCount ward(s) represented',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                  ),
                ),
                if (_currentHospitalId != null &&
                    _currentHospitalId!.isNotEmpty) ...[
                  const SizedBox(
                    height: 3,
                  ),
                  const Text(
                    'Hospital-scoped assignments',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 11,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPatientCard(
    Map<String, dynamic> assignment,
  ) {
    final patientName = _patientName(
      assignment,
    );

    final patientId = assignment['patient_id']?.toString().trim();

    final initial =
        patientName.trim().isEmpty ? '?' : patientName.trim()[0].toUpperCase();

    final isOpening = patientId != null && patientId == _openingPatientId;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(
        bottom: 12,
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
          Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(
              18,
            ),
            child: InkWell(
              onTap: _isOpeningForm
                  ? null
                  : () {
                      _showPatientDetails(
                        assignment,
                      );
                    },
              borderRadius: BorderRadius.circular(
                18,
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: CorviaColors.accent.withValues(
                          alpha: 0.12,
                        ),
                        borderRadius: BorderRadius.circular(
                          16,
                        ),
                      ),
                      child: Text(
                        initial,
                        style: TextStyle(
                          color: CorviaColors.accent,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
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
                          Text(
                            patientName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: context.cTextPrimary,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(
                            height: 4,
                          ),
                          Text(
                            _patientPhone(
                              assignment,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: context.cTextSecondary,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(
                            height: 10,
                          ),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _InfoPill(
                                icon: Icons.apartment_outlined,
                                label: _ward(
                                  assignment,
                                ),
                                color: CorviaColors.accent,
                              ),
                              _InfoPill(
                                icon: Icons.schedule_outlined,
                                label: _shiftType(
                                  assignment,
                                ),
                                color: CorviaColors.success,
                              ),
                            ],
                          ),
                          if (_assignmentNotes(
                                assignment,
                              ) !=
                              'No assignment notes') ...[
                            const SizedBox(
                              height: 9,
                            ),
                            Text(
                              _assignmentNotes(
                                assignment,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
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
                    Icon(
                      Icons.chevron_right,
                      color: context.cTextMuted,
                    ),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              16,
              0,
              16,
              16,
            ),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _isOpeningForm
                    ? null
                    : () {
                        _openNursingForms(
                          assignment,
                        );
                      },
                icon: isOpening
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                        ),
                      )
                    : const Icon(
                        Icons.description_outlined,
                      ),
                label: Text(
                  isOpening ? 'Opening Forms...' : 'Open Nursing Forms',
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: CorviaColors.accent,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    final hasAssignments = _assignments.isNotEmpty;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(
        28,
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
            hasAssignments ? Icons.search_off : Icons.people_outline,
            color: context.cTextMuted,
            size: 56,
          ),
          const SizedBox(
            height: 14,
          ),
          Text(
            hasAssignments ? 'No matching patients' : 'No patients assigned',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: context.cTextPrimary,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(
            height: 8,
          ),
          Text(
            hasAssignments
                ? 'Try a different search or shift filter.'
                : 'A hospital administrator must assign patients '
                    'to your nurse account.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: context.cTextSecondary,
              fontSize: 14,
              height: 1.4,
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
            maxWidth: 500,
          ),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: context.cBgSecondary,
              borderRadius: BorderRadius.circular(
                22,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.error_outline,
                  color: CorviaColors.danger,
                  size: 58,
                ),
                const SizedBox(
                  height: 16,
                ),
                Text(
                  'Could not load assigned patients',
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
                  _cleanError(
                    _errorMessage ?? 'Unknown assignment error.',
                  ),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: context.cTextSecondary,
                    fontSize: 14,
                    height: 1.4,
                  ),
                ),
                const SizedBox(
                  height: 20,
                ),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _loadAssignedPatients,
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

  String _cleanError(
    String value,
  ) {
    return value
        .replaceFirst(
          'Exception: ',
          '',
        )
        .replaceFirst(
          'PostgrestException(message: ',
          '',
        );
  }
}

class _InfoPill extends StatelessWidget {
  const _InfoPill({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(
    BuildContext context,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 9,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: color.withValues(
          alpha: 0.12,
        ),
        borderRadius: BorderRadius.circular(
          99,
        ),
        border: Border.all(
          color: color.withValues(
            alpha: 0.30,
          ),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            color: color,
            size: 14,
          ),
          const SizedBox(
            width: 5,
          ),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
