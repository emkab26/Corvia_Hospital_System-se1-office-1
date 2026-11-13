import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../theme/app_theme.dart';

class HospitalEmergencyPage extends StatefulWidget {
  const HospitalEmergencyPage({super.key});

  @override
  State<HospitalEmergencyPage> createState() => _HospitalEmergencyPageState();
}

class _HospitalEmergencyPageState extends State<HospitalEmergencyPage> {
  final SupabaseClient _supabase = Supabase.instance.client;
  final TextEditingController _searchController = TextEditingController();

  Color get primary =>
      context.isDarkTheme ? context.cBgSecondary : context.cTextPrimary;

  Color get accent => CorviaColors.accent;
  Color get success => CorviaColors.success;
  Color get warning => CorviaColors.warning;
  Color get error => CorviaColors.danger;

  Color get background => context.cBgPrimary;
  Color get textDark => context.cTextPrimary;
  Color get mutedText => context.cTextMuted;

  bool _loading = true;
  String? _error;

  String? _hospitalId;

  String _hospitalName = 'Emergency Profiles';
  String _selectedFilter = 'All';

  List<Map<String, dynamic>> _patients = [];
  List<Map<String, dynamic>> _emergencyProfiles = [];

  final Map<String, Map<String, dynamic>> _profilesByKey = {};

  @override
  void initState() {
    super.initState();

    _loadEmergencyPage();
  }

  @override
  void dispose() {
    _searchController.dispose();

    super.dispose();
  }

  // ============================================================
  // LOAD PAGE
  // ============================================================

  Future<void> _loadEmergencyPage() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      await _loadHospitalContext();
      await _loadPatients();
      await _loadEmergencyProfiles();
      await _loadPatientProfiles();
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  // ============================================================
  // HOSPITAL CONTEXT
  // ============================================================

  Future<void> _loadHospitalContext() async {
    final user = _supabase.auth.currentUser;

    if (user == null) {
      throw Exception(
        'You are not signed in.',
      );
    }

    final adminLink = await _supabase
        .from('hospital_admins')
        .select(
          'hospital_id, hospitals(name)',
        )
        .eq(
          'profile_id',
          user.id,
        )
        .maybeSingle();

    if (adminLink == null) {
      throw Exception(
        'This account is not linked to a hospital admin record.',
      );
    }

    final hospitalId =
        adminLink['hospital_id']?.toString();

    if (hospitalId == null ||
        hospitalId.trim().isEmpty) {
      throw Exception(
        'No hospital is linked to this admin account.',
      );
    }

    String hospitalName = 'Emergency Profiles';

    final hospital = adminLink['hospitals'];

    if (hospital is Map &&
        hospital['name'] != null) {
      hospitalName =
          hospital['name'].toString();
    }

    _hospitalId = hospitalId;
    _hospitalName = hospitalName;
  }

  // ============================================================
  // PATIENTS
  // ============================================================

  Future<void> _loadPatients() async {
    final hospitalId = _hospitalId;

    if (hospitalId == null) {
      throw Exception(
        'Hospital ID could not be found.',
      );
    }

    final rows = await _supabase
        .from('patients')
        .select()
        .eq(
          'hospital_id',
          hospitalId,
        )
        .limit(500);

    _patients = _mapRows(rows);
  }

  // ============================================================
  // EMERGENCY PROFILES
  // ============================================================

  Future<void> _loadEmergencyProfiles() async {
    final hospitalId = _hospitalId;

    if (hospitalId == null) {
      throw Exception(
        'Hospital ID could not be found.',
      );
    }

    List<Map<String, dynamic>> rawProfiles = [];

    try {
      final rows = await _supabase
          .from('emergency_profiles')
          .select()
          .eq(
            'hospital_id',
            hospitalId,
          )
          .limit(500);

      rawProfiles = _mapRows(rows);
    } catch (_) {
      try {
        final rows = await _supabase
            .from('emergency_profiles')
            .select()
            .limit(500);

        rawProfiles = _mapRows(rows);
      } catch (_) {
        rawProfiles = [];
      }
    }

    final hospitalPatientKeys = <String>{};

    for (final patient in _patients) {
      final patientId =
          patient['id']?.toString();

      final profileId =
          patient['profile_id']?.toString();

      final userId =
          patient['user_id']?.toString();

      if (patientId != null &&
          patientId.isNotEmpty) {
        hospitalPatientKeys.add(
          patientId,
        );
      }

      if (profileId != null &&
          profileId.isNotEmpty) {
        hospitalPatientKeys.add(
          profileId,
        );
      }

      if (userId != null &&
          userId.isNotEmpty) {
        hospitalPatientKeys.add(
          userId,
        );
      }
    }

    _emergencyProfiles = rawProfiles.where(
      (
        profile,
      ) {
        final directHospitalId =
            profile['hospital_id']?.toString();

        if (directHospitalId != null &&
            directHospitalId == hospitalId) {
          return true;
        }

        final patientId =
            profile['patient_id']?.toString();

        final profileId =
            profile['profile_id']?.toString();

        final userId =
            profile['user_id']?.toString();

        return hospitalPatientKeys.contains(
              patientId,
            ) ||
            hospitalPatientKeys.contains(
              profileId,
            ) ||
            hospitalPatientKeys.contains(
              userId,
            );
      },
    ).toList();
  }

  // ============================================================
  // PROFILE LOOKUPS
  // ============================================================

  Future<void> _loadPatientProfiles() async {
    _profilesByKey.clear();

    final keys = <String>{};

    for (final patient in _patients) {
      final profileId =
          patient['profile_id']?.toString();

      final userId =
          patient['user_id']?.toString();

      if (profileId != null &&
          profileId.isNotEmpty) {
        keys.add(
          profileId,
        );
      }

      if (userId != null &&
          userId.isNotEmpty) {
        keys.add(
          userId,
        );
      }
    }

    for (final emergencyProfile
        in _emergencyProfiles) {
      final profileId =
          emergencyProfile['profile_id']
              ?.toString();

      final userId =
          emergencyProfile['user_id']
              ?.toString();

      if (profileId != null &&
          profileId.isNotEmpty) {
        keys.add(
          profileId,
        );
      }

      if (userId != null &&
          userId.isNotEmpty) {
        keys.add(
          userId,
        );
      }
    }

    if (keys.isEmpty) {
      return;
    }

    final keyList = keys.toList();

    await _loadProfilesByColumn(
      'id',
      keyList,
    );

    await _loadProfilesByColumn(
      'user_id',
      keyList,
    );
  }

  Future<void> _loadProfilesByColumn(
    String column,
    List<String> keys,
  ) async {
    try {
      final rows = await _supabase
          .from('profiles')
          .select(
            'id, user_id, first_name, surname, email, phone, phone_number, id_number',
          )
          .inFilter(
            column,
            keys,
          );

      for (final row in rows.whereType<Map>()) {
        final profile =
            Map<String, dynamic>.from(
          row,
        );

        final id =
            profile['id']?.toString();

        final userId =
            profile['user_id']?.toString();

        if (id != null &&
            id.isNotEmpty) {
          _profilesByKey[id] = profile;
        }

        if (userId != null &&
            userId.isNotEmpty) {
          _profilesByKey[userId] = profile;
        }
      }
    } catch (_) {
      // Emergency records can still load if profile access
      // is restricted by RLS.
    }
  }

  // ============================================================
  // GENERIC HELPERS
  // ============================================================

  List<Map<String, dynamic>> _mapRows(
    dynamic rows,
  ) {
    if (rows is! List) {
      return [];
    }

    return rows
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

  bool _isPlaceholderName(
    String value,
  ) {
    final name =
        value.trim().toLowerCase();

    return name.isEmpty ||
        name == 'corvia patient' ||
        name == 'patient' ||
        name == 'unknown patient' ||
        name == 'emergency profile patient' ||
        name == 'qr scanned patient' ||
        name == 'patient profile not linked';
  }

  String _stringValue(
    Map<String, dynamic> map,
    List<String> keys, {
    String fallback = '',
  }) {
    for (final key in keys) {
      final value = map[key];

      if (value == null) {
        continue;
      }

      final formatted =
          _formatValue(
        value,
      );

      if (formatted.trim().isNotEmpty) {
        return formatted;
      }
    }

    return fallback;
  }

  String _formatValue(
    dynamic value,
  ) {
    if (value == null) {
      return '';
    }

    if (value is List) {
      return value
          .map(
            _formatValue,
          )
          .where(
            (
              item,
            ) =>
                item.isNotEmpty,
          )
          .join(', ');
    }

    if (value is Map) {
      return value.values
          .map(
            _formatValue,
          )
          .where(
            (
              item,
            ) =>
                item.isNotEmpty,
          )
          .join(', ');
    }

    return value.toString();
  }

  // ============================================================
  // NAME RESOLUTION
  // ============================================================

  String _nameFromProfile(
    Map<String, dynamic>? profile,
  ) {
    if (profile == null) {
      return '';
    }

    final firstName =
        profile['first_name']
                ?.toString()
                .trim() ??
            '';

    final surname =
        profile['surname']
                ?.toString()
                .trim() ??
            '';

    final fullName =
        '$firstName $surname'.trim();

    if (_isPlaceholderName(
      fullName,
    )) {
      return '';
    }

    return fullName;
  }

  String _nameFromPatientRow(
    Map<String, dynamic>? patient,
  ) {
    if (patient == null) {
      return '';
    }

    final directName = _stringValue(
      patient,
      [
        'full_name',
        'patient_name',
        'name',
      ],
    );

    if (!_isPlaceholderName(
      directName,
    )) {
      return directName;
    }

    final firstName =
        patient['first_name']
                ?.toString()
                .trim() ??
            '';

    final surname =
        patient['surname']
                ?.toString()
                .trim() ??
            patient['last_name']
                ?.toString()
                .trim() ??
            '';

    final fullName =
        '$firstName $surname'.trim();

    if (!_isPlaceholderName(
      fullName,
    )) {
      return fullName;
    }

    return '';
  }

  Map<String, dynamic>? _patientForEmergencyProfile(
    Map<String, dynamic> emergencyProfile,
  ) {
    final possibleKeys = [
      emergencyProfile['patient_id']
          ?.toString(),
      emergencyProfile['profile_id']
          ?.toString(),
      emergencyProfile['user_id']
          ?.toString(),
    ];

    for (final patient in _patients) {
      final patientId =
          patient['id']?.toString();

      final profileId =
          patient['profile_id']?.toString();

      final userId =
          patient['user_id']?.toString();

      for (final key in possibleKeys) {
        if (key == null ||
            key.isEmpty) {
          continue;
        }

        if (key == patientId ||
            key == profileId ||
            key == userId) {
          return patient;
        }
      }
    }

    return null;
  }

  Map<String, dynamic>? _profileForPatient(
    Map<String, dynamic>? patient,
  ) {
    if (patient == null) {
      return null;
    }

    final profileId =
        patient['profile_id']?.toString();

    final userId =
        patient['user_id']?.toString();

    if (profileId != null &&
        _profilesByKey.containsKey(
          profileId,
        )) {
      return _profilesByKey[profileId];
    }

    if (userId != null &&
        _profilesByKey.containsKey(
          userId,
        )) {
      return _profilesByKey[userId];
    }

    return null;
  }

  Map<String, dynamic>? _profileForEmergencyProfile(
    Map<String, dynamic> emergencyProfile,
  ) {
    final profileId =
        emergencyProfile['profile_id']
            ?.toString();

    final userId =
        emergencyProfile['user_id']
            ?.toString();

    if (profileId != null &&
        _profilesByKey.containsKey(
          profileId,
        )) {
      return _profilesByKey[profileId];
    }

    if (userId != null &&
        _profilesByKey.containsKey(
          userId,
        )) {
      return _profilesByKey[userId];
    }

    return null;
  }

  String _patientName(
    Map<String, dynamic> emergencyProfile,
  ) {
    final patient =
        _patientForEmergencyProfile(
      emergencyProfile,
    );

    final linkedPatientProfile =
        _profileForPatient(
      patient,
    );

    final emergencyProfileLink =
        _profileForEmergencyProfile(
      emergencyProfile,
    );

    final profileName =
        _nameFromProfile(
      linkedPatientProfile,
    );

    if (profileName.isNotEmpty) {
      return profileName;
    }

    final emergencyLinkedName =
        _nameFromProfile(
      emergencyProfileLink,
    );

    if (emergencyLinkedName.isNotEmpty) {
      return emergencyLinkedName;
    }

    final patientName =
        _nameFromPatientRow(
      patient,
    );

    if (patientName.isNotEmpty) {
      return patientName;
    }

    final directName = _stringValue(
      emergencyProfile,
      [
        'patient_name',
        'full_name',
        'name',
      ],
    );

    if (!_isPlaceholderName(
      directName,
    )) {
      return directName;
    }

    return 'Patient profile not linked';
  }

  // ============================================================
  // PHONE / EMERGENCY DATA
  // ============================================================

  String _patientPhone(
    Map<String, dynamic> emergencyProfile,
  ) {
    final patient =
        _patientForEmergencyProfile(
      emergencyProfile,
    );

    final linkedPatientProfile =
        _profileForPatient(
      patient,
    );

    final emergencyProfileLink =
        _profileForEmergencyProfile(
      emergencyProfile,
    );

    final patientPhone =
        patient?['phone'] ??
        patient?['phone_number'] ??
        linkedPatientProfile?['phone'] ??
        linkedPatientProfile?['phone_number'] ??
        emergencyProfileLink?['phone'] ??
        emergencyProfileLink?['phone_number'];

    if (patientPhone != null &&
        patientPhone
            .toString()
            .trim()
            .isNotEmpty) {
      return patientPhone.toString();
    }

    final directPhone = _stringValue(
      emergencyProfile,
      [
        'patient_phone',
        'phone',
        'phone_number',
      ],
    );

    if (directPhone.isNotEmpty) {
      return directPhone;
    }

    return 'No patient phone';
  }

  String _emergencyContactName(
    Map<String, dynamic> profile,
  ) {
    return _stringValue(
      profile,
      [
        'emergency_contact_name',
        'contact_name',
        'next_of_kin_name',
        'emergency_contact',
      ],
      fallback: 'Not captured',
    );
  }

  String _emergencyContactPhone(
    Map<String, dynamic> profile,
  ) {
    return _stringValue(
      profile,
      [
        'emergency_contact_phone',
        'contact_phone',
        'next_of_kin_phone',
        'emergency_phone',
      ],
      fallback: 'Not captured',
    );
  }

  String _bloodType(
    Map<String, dynamic> profile,
  ) {
    return _stringValue(
      profile,
      [
        'blood_type',
        'blood_group',
      ],
      fallback: 'Not captured',
    );
  }

  String _allergies(
    Map<String, dynamic> profile,
  ) {
    return _stringValue(
      profile,
      [
        'allergies',
        'known_allergies',
        'allergy_notes',
      ],
      fallback: 'No allergies captured',
    );
  }

  String _medicalConditions(
    Map<String, dynamic> profile,
  ) {
    return _stringValue(
      profile,
      [
        'medical_conditions',
        'chronic_conditions',
        'conditions',
        'medical_notes',
      ],
      fallback: 'No conditions captured',
    );
  }

  String _medicalNotes(
    Map<String, dynamic> profile,
  ) {
    return _stringValue(
      profile,
      [
        'emergency_notes',
        'notes',
        'special_instructions',
      ],
      fallback: 'No emergency notes captured',
    );
  }

  bool _hasContactDetails(
    Map<String, dynamic> profile,
  ) {
    return _emergencyContactName(
              profile,
            ) !=
            'Not captured' &&
        _emergencyContactPhone(
              profile,
            ) !=
            'Not captured';
  }

  bool _hasMedicalAlerts(
    Map<String, dynamic> profile,
  ) {
    final allergies =
        _allergies(
      profile,
    ).toLowerCase();

    final conditions =
        _medicalConditions(
      profile,
    ).toLowerCase();

    return allergies !=
            'no allergies captured' ||
        conditions !=
            'no conditions captured';
  }

  // ============================================================
  // DATE FORMAT
  // ============================================================

  String _formatDateTime(
    dynamic value,
  ) {
    if (value == null) {
      return 'Unknown date';
    }

    final date = DateTime.tryParse(
      value.toString(),
    );

    if (date == null) {
      return value.toString();
    }

    final local = date.toLocal();

    final day =
        local.day.toString().padLeft(
              2,
              '0',
            );

    final month =
        local.month.toString().padLeft(
              2,
              '0',
            );

    final hour =
        local.hour.toString().padLeft(
              2,
              '0',
            );

    final minute =
        local.minute.toString().padLeft(
              2,
              '0',
            );

    return '$day/$month/${local.year} • $hour:$minute';
  }

  // ============================================================
  // FILTERING
  // ============================================================

  List<Map<String, dynamic>>
  get _visibleProfiles {
    final search =
        _searchController.text
            .trim()
            .toLowerCase();

    return _emergencyProfiles.where(
      (
        profile,
      ) {
        final patient =
            _patientName(
          profile,
        ).toLowerCase();

        final phone =
            _patientPhone(
          profile,
        ).toLowerCase();

        final contactName =
            _emergencyContactName(
          profile,
        ).toLowerCase();

        final contactPhone =
            _emergencyContactPhone(
          profile,
        ).toLowerCase();

        final bloodType =
            _bloodType(
          profile,
        ).toLowerCase();

        final allergies =
            _allergies(
          profile,
        ).toLowerCase();

        final conditions =
            _medicalConditions(
          profile,
        ).toLowerCase();

        final matchesSearch =
            search.isEmpty ||
            patient.contains(search) ||
            phone.contains(search) ||
            contactName.contains(search) ||
            contactPhone.contains(search) ||
            bloodType.contains(search) ||
            allergies.contains(search) ||
            conditions.contains(search);

        bool matchesFilter = true;

        if (_selectedFilter ==
            'Contact Ready') {
          matchesFilter =
              _hasContactDetails(
            profile,
          );
        } else if (_selectedFilter ==
            'Medical Alerts') {
          matchesFilter =
              _hasMedicalAlerts(
            profile,
          );
        } else if (_selectedFilter ==
            'Blood Type Added') {
          matchesFilter =
              _bloodType(
                profile,
              ) !=
              'Not captured';
        }

        return matchesSearch &&
            matchesFilter;
      },
    ).toList();
  }

  int get _contactReadyCount {
    return _emergencyProfiles
        .where(
          _hasContactDetails,
        )
        .length;
  }

  int get _medicalAlertCount {
    return _emergencyProfiles
        .where(
          _hasMedicalAlerts,
        )
        .length;
  }

  int get _bloodTypeCount {
    return _emergencyProfiles
        .where(
          (
            profile,
          ) =>
              _bloodType(
                profile,
              ) !=
              'Not captured',
        )
        .length;
  }

  // ============================================================
  // DETAIL DIALOG
  // ============================================================

  void _showEmergencyDetails(
    Map<String, dynamic> profile,
  ) {
    showDialog<void>(
      context: context,
      builder: (
        dialogContext,
      ) {
        return AlertDialog(
          backgroundColor: context.cBgSecondary,
          title: Text(
            _patientName(
              profile,
            ),
            style: TextStyle(
              color: textDark,
              fontWeight: FontWeight.w900,
            ),
          ),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              mainAxisSize:
                  MainAxisSize.min,
              children: [
                _detailLine(
                  'Patient phone',
                  _patientPhone(
                    profile,
                  ),
                ),
                _detailLine(
                  'Emergency contact',
                  _emergencyContactName(
                    profile,
                  ),
                ),
                _detailLine(
                  'Emergency contact phone',
                  _emergencyContactPhone(
                    profile,
                  ),
                ),
                _detailLine(
                  'Blood type',
                  _bloodType(
                    profile,
                  ),
                ),
                _detailLine(
                  'Allergies',
                  _allergies(
                    profile,
                  ),
                ),
                _detailLine(
                  'Medical conditions',
                  _medicalConditions(
                    profile,
                  ),
                ),
                _detailLine(
                  'Emergency notes',
                  _medicalNotes(
                    profile,
                  ),
                ),
                _detailLine(
                  'Last updated',
                  _formatDateTime(
                    profile['updated_at'] ??
                        profile['created_at'],
                  ),
                ),
                const SizedBox(
                  height: 8,
                ),
                Text(
                  'Emergency information shown here is linked to the patient emergency profile.',
                  style: TextStyle(
                    color: mutedText,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(
                  dialogContext,
                );
              },
              child: const Text(
                'Close',
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
      padding:
          const EdgeInsets.only(
        bottom: 10,
      ),
      child: RichText(
        text: TextSpan(
          style: TextStyle(
            color: textDark,
            fontSize: 14,
          ),
          children: [
            TextSpan(
              text: '$label: ',
              style: const TextStyle(
                fontWeight:
                    FontWeight.w900,
              ),
            ),
            TextSpan(
              text: value,
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // PAGE
  // ============================================================

  @override
  Widget build(
    BuildContext context,
  ) {
    final profiles =
        _visibleProfiles;

    return Scaffold(
      backgroundColor: background,
      body: SafeArea(
        child: RefreshIndicator(
          color: accent,
          onRefresh:
              _loadEmergencyPage,
          child: _loading
              ? Center(
                  child:
                      CircularProgressIndicator(
                    color: accent,
                  ),
                )
              : SingleChildScrollView(
                  physics:
                      const AlwaysScrollableScrollPhysics(),
                  padding:
                      const EdgeInsets.all(
                    24,
                  ),
                  child: Center(
                    child: ConstrainedBox(
                      constraints:
                          const BoxConstraints(
                        maxWidth: 1500,
                      ),
                      child: Column(
                        crossAxisAlignment:
                            CrossAxisAlignment
                                .start,
                        children: [
                          _buildHeader(),
                          const SizedBox(
                            height: 22,
                          ),
                          if (_error !=
                              null)
                            _buildErrorBox(),
                          _buildStats(),
                          const SizedBox(
                            height: 22,
                          ),
                          _buildEmergencyDirectory(
                            profiles,
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

  // ============================================================
  // HEADER
  // ============================================================

  Widget _buildHeader() {
    return LayoutBuilder(
      builder: (
        context,
        constraints,
      ) {
        final compact =
            constraints.maxWidth <
                720;

        final titleSection =
            Row(
          children: [
            IconButton(
              tooltip:
                  'Back to hospital dashboard',
              onPressed: () {
                Navigator.of(
                  context,
                ).maybePop();
              },
              icon: const Icon(
                Icons.arrow_back_rounded,
              ),
              color: textDark,
            ),
            const SizedBox(
              width: 8,
            ),
            Expanded(
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment
                        .start,
                children: [
                  Text(
                    'Emergency • $_hospitalName',
                    style: TextStyle(
                      color: textDark,
                      fontSize:
                          compact
                              ? 21
                              : 27,
                      fontWeight:
                          FontWeight.w900,
                    ),
                  ),
                  const SizedBox(
                    height: 5,
                  ),
                  Text(
                    'Review emergency contacts, allergies, conditions and important patient information.',
                    style: TextStyle(
                      color: mutedText,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ],
        );

        final refreshButton =
            OutlinedButton.icon(
          onPressed:
              _loadEmergencyPage,
          icon: const Icon(
            Icons.refresh_rounded,
          ),
          label: const Text(
            'Refresh',
          ),
          style:
              OutlinedButton.styleFrom(
            foregroundColor:
                textDark,
            side: BorderSide(
              color:
                  context.cDivider,
            ),
          ),
        );

        if (compact) {
          return Column(
            crossAxisAlignment:
                CrossAxisAlignment
                    .stretch,
            children: [
              titleSection,
              const SizedBox(
                height: 14,
              ),
              Align(
                alignment:
                    Alignment.centerRight,
                child:
                    refreshButton,
              ),
            ],
          );
        }

        return Row(
          children: [
            Expanded(
              child:
                  titleSection,
            ),
            const SizedBox(
              width: 12,
            ),
            refreshButton,
          ],
        );
      },
    );
  }

  // ============================================================
  // ERROR
  // ============================================================

  Widget _buildErrorBox() {
    return Container(
      width: double.infinity,
      margin:
          const EdgeInsets.only(
        bottom: 18,
      ),
      padding:
          const EdgeInsets.all(
        14,
      ),
      decoration:
          BoxDecoration(
        color:
            error.withValues(
          alpha: 0.08,
        ),
        borderRadius:
            BorderRadius.circular(
          16,
        ),
        border:
            Border.all(
          color:
              error.withValues(
            alpha: 0.18,
          ),
        ),
      ),
      child:
          Row(
        children: [
          Icon(
            Icons.info_outline_rounded,
            color:
                error,
          ),
          const SizedBox(
            width:
                10,
          ),
          Expanded(
            child:
                Text(
              'Could not load all emergency profile information. $_error',
              style:
                  TextStyle(
                color:
                    textDark,
                fontWeight:
                    FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // STATS
  // FIXED: REMOVES YELLOW / BLACK OVERFLOW PIXELS
  // ============================================================

  Widget _buildStats() {
    final stats = [
      _EmergencyStat(
        title:
            'Emergency Profiles',
        value:
            _emergencyProfiles.length
                .toString(),
        subtitle:
            'Patient emergency records',
        icon:
            Icons.emergency_rounded,
        color:
            error,
      ),
      _EmergencyStat(
        title:
            'Contact Ready',
        value:
            _contactReadyCount
                .toString(),
        subtitle:
            'Emergency contact captured',
        icon:
            Icons.contact_phone_rounded,
        color:
            success,
      ),
      _EmergencyStat(
        title:
            'Medical Alerts',
        value:
            _medicalAlertCount
                .toString(),
        subtitle:
            'Allergies or conditions listed',
        icon:
            Icons.warning_amber_rounded,
        color:
            warning,
      ),
      _EmergencyStat(
        title:
            'Blood Type Added',
        value:
            _bloodTypeCount
                .toString(),
        subtitle:
            'Blood group recorded',
        icon:
            Icons.bloodtype_rounded,
        color:
            accent,
      ),
    ];

    return LayoutBuilder(
      builder: (
        context,
        constraints,
      ) {
        int columns;

        if (constraints.maxWidth >=
            1100) {
          columns = 4;
        } else if (constraints
                .maxWidth >=
            650) {
          columns = 2;
        } else {
          columns = 1;
        }

        final textScale =
            MediaQuery.textScalerOf(
              context,
            ).scale(
              1,
            );

        final cardHeight =
            textScale > 1.20
                ? 205.0
                : 185.0;

        return GridView.builder(
          itemCount:
              stats.length,
          shrinkWrap:
              true,
          physics:
              const NeverScrollableScrollPhysics(),
          gridDelegate:
              SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount:
                columns,
            mainAxisExtent:
                cardHeight,
            mainAxisSpacing:
                14,
            crossAxisSpacing:
                14,
          ),
          itemBuilder: (
            context,
            index,
          ) {
            final stat =
                stats[index];

            return Container(
              padding:
                  const EdgeInsets.all(
                18,
              ),
              decoration:
                  BoxDecoration(
                color:
                    context
                        .cBgSecondary,
                borderRadius:
                    BorderRadius.circular(
                  20,
                ),
                border:
                    Border.all(
                  color:
                      context
                          .cDivider,
                ),
                boxShadow: [
                  BoxShadow(
                    color:
                        context
                            .cCardShadow,
                    blurRadius:
                        8,
                    offset:
                        const Offset(
                      0,
                      3,
                    ),
                  ),
                ],
              ),
              child:
                  Column(
                crossAxisAlignment:
                    CrossAxisAlignment
                        .start,
                children: [
                  Container(
                    height:
                        44,
                    width:
                        44,
                    decoration:
                        BoxDecoration(
                      color:
                          stat.color
                              .withValues(
                        alpha:
                            0.10,
                      ),
                      borderRadius:
                          BorderRadius.circular(
                        14,
                      ),
                    ),
                    child:
                        Icon(
                      stat.icon,
                      color:
                          stat.color,
                      size:
                          24,
                    ),
                  ),

                  const Spacer(),

                  Text(
                    stat.value,
                    maxLines:
                        1,
                    overflow:
                        TextOverflow
                            .ellipsis,
                    style:
                        TextStyle(
                      color:
                          textDark,
                      fontSize:
                          27,
                      fontWeight:
                          FontWeight
                              .w900,
                      height:
                          1,
                    ),
                  ),

                  const SizedBox(
                    height:
                        6,
                  ),

                  Text(
                    stat.title,
                    maxLines:
                        1,
                    overflow:
                        TextOverflow
                            .ellipsis,
                    style:
                        TextStyle(
                      color:
                          textDark,
                      fontSize:
                          14,
                      fontWeight:
                          FontWeight
                              .w800,
                    ),
                  ),

                  const SizedBox(
                    height:
                        4,
                  ),

                  Text(
                    stat.subtitle,
                    maxLines:
                        2,
                    overflow:
                        TextOverflow
                            .ellipsis,
                    style:
                        TextStyle(
                      color:
                          mutedText,
                      fontSize:
                          12,
                      height:
                          1.25,
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

  // ============================================================
  // DIRECTORY
  // ============================================================

  Widget _buildEmergencyDirectory(
    List<Map<String, dynamic>> profiles,
  ) {
    return Container(
      width:
          double.infinity,
      padding:
          const EdgeInsets.all(
        20,
      ),
      decoration:
          BoxDecoration(
        color:
            context
                .cBgSecondary,
        borderRadius:
            BorderRadius.circular(
          24,
        ),
        border:
            Border.all(
          color:
              context
                  .cDivider,
        ),
      ),
      child:
          Column(
        crossAxisAlignment:
            CrossAxisAlignment
                .start,
        children: [
          Row(
            children: [
              Icon(
                Icons.health_and_safety_rounded,
                color:
                    error,
              ),
              const SizedBox(
                width:
                    10,
              ),
              Expanded(
                child:
                    Text(
                  'Emergency Patient Directory',
                  style:
                      TextStyle(
                    color:
                        textDark,
                    fontSize:
                        18,
                    fontWeight:
                        FontWeight
                            .w900,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(
            height:
                5,
          ),

          Text(
            '${profiles.length} emergency profile(s) currently shown',
            style:
                TextStyle(
              color:
                  mutedText,
              fontSize:
                  13,
            ),
          ),

          const SizedBox(
            height:
                18,
          ),

          TextField(
            controller:
                _searchController,
            onChanged: (_) {
              setState(
                () {},
              );
            },
            style:
                TextStyle(
              color:
                  textDark,
            ),
            decoration:
                InputDecoration(
              hintText:
                  'Search patient, contact, blood type, allergies or conditions',
              hintStyle:
                  TextStyle(
                color:
                    mutedText,
              ),
              prefixIcon:
                  Icon(
                Icons.search_rounded,
                color:
                    accent,
              ),
              suffixIcon:
                  _searchController
                          .text
                          .isEmpty
                      ? null
                      : IconButton(
                          onPressed:
                              () {
                            _searchController
                                .clear();

                            setState(
                              () {},
                            );
                          },
                          icon:
                              const Icon(
                            Icons.clear_rounded,
                          ),
                        ),
              filled:
                  true,
              fillColor:
                  context
                      .cBgPrimary,
              border:
                  OutlineInputBorder(
                borderRadius:
                    BorderRadius.circular(
                  15,
                ),
                borderSide:
                    BorderSide(
                  color:
                      context
                          .cDivider,
                ),
              ),
              enabledBorder:
                  OutlineInputBorder(
                borderRadius:
                    BorderRadius.circular(
                  15,
                ),
                borderSide:
                    BorderSide(
                  color:
                      context
                          .cDivider,
                ),
              ),
              focusedBorder:
                  OutlineInputBorder(
                borderRadius:
                    BorderRadius.circular(
                  15,
                ),
                borderSide:
                    BorderSide(
                  color:
                      accent,
                  width:
                      1.5,
                ),
              ),
            ),
          ),

          const SizedBox(
            height:
                14,
          ),

          Wrap(
            spacing:
                8,
            runSpacing:
                8,
            children:
                [
              'All',
              'Contact Ready',
              'Medical Alerts',
              'Blood Type Added',
            ].map(
              (
                filter,
              ) {
                return ChoiceChip(
                  label:
                      Text(
                    filter,
                  ),
                  selected:
                      _selectedFilter ==
                          filter,
                  selectedColor:
                      accent.withValues(
                    alpha:
                        0.13,
                  ),
                  onSelected:
                      (_) {
                    setState(
                      () {
                        _selectedFilter =
                            filter;
                      },
                    );
                  },
                );
              },
            ).toList(),
          ),

          const SizedBox(
            height:
                20,
          ),

          if (profiles.isEmpty)
            _buildEmptyState()
          else
            ...profiles.map(
              _buildEmergencyCard,
            ),
        ],
      ),
    );
  }

  // ============================================================
  // EMPTY STATE
  // ============================================================

  Widget _buildEmptyState() {
    return Container(
      width:
          double.infinity,
      padding:
          const EdgeInsets.symmetric(
        vertical:
            42,
        horizontal:
            20,
      ),
      decoration:
          BoxDecoration(
        color:
            context
                .cBgPrimary,
        borderRadius:
            BorderRadius.circular(
          18,
        ),
        border:
            Border.all(
          color:
              context
                  .cDivider,
        ),
      ),
      child:
          Column(
        children: [
          Icon(
            Icons.emergency_outlined,
            color:
                error,
            size:
                42,
          ),
          const SizedBox(
            height:
                12,
          ),
          Text(
            'No emergency profiles found',
            style:
                TextStyle(
              color:
                  textDark,
              fontSize:
                  16,
              fontWeight:
                  FontWeight
                      .w900,
            ),
          ),
          const SizedBox(
            height:
                6,
          ),
          Text(
            'Emergency-ready profiles created by patients will appear here.',
            textAlign:
                TextAlign
                    .center,
            style:
                TextStyle(
              color:
                  mutedText,
              fontSize:
                  13,
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // PATIENT CARD
  // ============================================================

  Widget _buildEmergencyCard(
    Map<String, dynamic> profile,
  ) {
    final patientName =
        _patientName(
      profile,
    );

    final patientPhone =
        _patientPhone(
      profile,
    );

    final contactName =
        _emergencyContactName(
      profile,
    );

    final contactPhone =
        _emergencyContactPhone(
      profile,
    );

    final bloodType =
        _bloodType(
      profile,
    );

    final allergies =
        _allergies(
      profile,
    );

    final conditions =
        _medicalConditions(
      profile,
    );

    final contactReady =
        _hasContactDetails(
      profile,
    );

    final medicalAlerts =
        _hasMedicalAlerts(
      profile,
    );

    return InkWell(
      onTap:
          () {
        _showEmergencyDetails(
          profile,
        );
      },
      borderRadius:
          BorderRadius.circular(
        18,
      ),
      child:
          Container(
        margin:
            const EdgeInsets.only(
          bottom:
              12,
        ),
        padding:
            const EdgeInsets.all(
          16,
        ),
        decoration:
            BoxDecoration(
          color:
              context
                  .cBgPrimary,
          borderRadius:
              BorderRadius.circular(
            18,
          ),
          border:
              Border.all(
            color:
                medicalAlerts
                    ? error.withValues(
                        alpha:
                            0.35,
                      )
                    : context
                        .cDivider,
          ),
        ),
        child:
            LayoutBuilder(
          builder:
              (
            context,
            constraints,
          ) {
            final compact =
                constraints.maxWidth <
                    740;

            final details =
                Column(
              crossAxisAlignment:
                  CrossAxisAlignment
                      .start,
              children: [
                Text(
                  patientName,
                  style:
                      TextStyle(
                    color:
                        textDark,
                    fontSize:
                        16,
                    fontWeight:
                        FontWeight
                            .w900,
                  ),
                ),

                const SizedBox(
                  height:
                      4,
                ),

                Text(
                  patientPhone,
                  style:
                      TextStyle(
                    color:
                        mutedText,
                    fontSize:
                        12,
                  ),
                ),

                const SizedBox(
                  height:
                      10,
                ),

                Text(
                  'Emergency contact: $contactName • $contactPhone',
                  maxLines:
                      2,
                  overflow:
                      TextOverflow
                          .ellipsis,
                  style:
                      TextStyle(
                    color:
                        mutedText,
                    fontSize:
                        13,
                    fontWeight:
                        FontWeight
                            .w600,
                  ),
                ),

                const SizedBox(
                  height:
                      10,
                ),

                Wrap(
                  spacing:
                      8,
                  runSpacing:
                      8,
                  children: [
                    _EmergencyPill(
                      icon:
                          Icons.bloodtype_rounded,
                      label:
                          bloodType,
                      color:
                          accent,
                    ),
                    _EmergencyPill(
                      icon:
                          Icons.contact_phone_rounded,
                      label:
                          contactReady
                              ? 'Contact ready'
                              : 'Contact incomplete',
                      color:
                          contactReady
                              ? success
                              : warning,
                    ),
                    if (medicalAlerts)
                      _EmergencyPill(
                        icon:
                            Icons.warning_amber_rounded,
                        label:
                            'Medical alert',
                        color:
                            error,
                      ),
                  ],
                ),

                const SizedBox(
                  height:
                      10,
                ),

                Text(
                  'Allergies: $allergies',
                  maxLines:
                      2,
                  overflow:
                      TextOverflow
                          .ellipsis,
                  style:
                      TextStyle(
                    color:
                        textDark,
                    fontSize:
                        12,
                    fontWeight:
                        FontWeight
                            .w600,
                  ),
                ),

                const SizedBox(
                  height:
                      4,
                ),

                Text(
                  'Conditions: $conditions',
                  maxLines:
                      2,
                  overflow:
                      TextOverflow
                          .ellipsis,
                  style:
                      TextStyle(
                    color:
                        mutedText,
                    fontSize:
                        12,
                  ),
                ),
              ],
            );

            final openButton =
                OutlinedButton.icon(
              onPressed:
                  () {
                _showEmergencyDetails(
                  profile,
                );
              },
              icon:
                  const Icon(
                Icons.visibility_rounded,
                size:
                    18,
              ),
              label:
                  const Text(
                'View',
              ),
              style:
                  OutlinedButton.styleFrom(
                foregroundColor:
                    textDark,
                side:
                    BorderSide(
                  color:
                      context
                          .cDivider,
                ),
              ),
            );

            if (compact) {
              return Column(
                crossAxisAlignment:
                    CrossAxisAlignment
                        .start,
                children: [
                  Row(
                    crossAxisAlignment:
                        CrossAxisAlignment
                            .start,
                    children: [
                      Container(
                        height:
                            50,
                        width:
                            50,
                        decoration:
                            BoxDecoration(
                          color:
                              error.withValues(
                            alpha:
                                0.10,
                          ),
                          borderRadius:
                              BorderRadius.circular(
                            16,
                          ),
                        ),
                        child:
                            Icon(
                          Icons.emergency_rounded,
                          color:
                              error,
                        ),
                      ),
                      const SizedBox(
                        width:
                            12,
                      ),
                      Expanded(
                        child:
                            details,
                      ),
                    ],
                  ),
                  const SizedBox(
                    height:
                        14,
                  ),
                  Align(
                    alignment:
                        Alignment.centerRight,
                    child:
                        openButton,
                  ),
                ],
              );
            }

            return Row(
              crossAxisAlignment:
                  CrossAxisAlignment
                      .start,
              children: [
                Container(
                  height:
                      50,
                  width:
                      50,
                  decoration:
                      BoxDecoration(
                    color:
                        error.withValues(
                      alpha:
                          0.10,
                    ),
                    borderRadius:
                        BorderRadius.circular(
                      16,
                    ),
                  ),
                  child:
                      Icon(
                    Icons.emergency_rounded,
                    color:
                        error,
                  ),
                ),

                const SizedBox(
                  width:
                      14,
                ),

                Expanded(
                  child:
                      details,
                ),

                const SizedBox(
                  width:
                      14,
                ),

                openButton,
              ],
            );
          },
        ),
      ),
    );
  }
}

// ============================================================
// STAT MODEL
// ============================================================

class _EmergencyStat {
  const _EmergencyStat({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.icon,
    required this.color,
  });

  final String title;
  final String value;
  final String subtitle;
  final IconData icon;
  final Color color;
}

// ============================================================
// STATUS PILL
// ============================================================

class _EmergencyPill extends StatelessWidget {
  const _EmergencyPill({
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
      constraints:
          const BoxConstraints(
        maxWidth:
            250,
      ),
      padding:
          const EdgeInsets.symmetric(
        horizontal:
            9,
        vertical:
            6,
      ),
      decoration:
          BoxDecoration(
        color:
            color.withValues(
          alpha:
              0.10,
        ),
        borderRadius:
            BorderRadius.circular(
          999,
        ),
        border:
            Border.all(
          color:
              color.withValues(
            alpha:
                0.20,
          ),
        ),
      ),
      child:
          Row(
        mainAxisSize:
            MainAxisSize.min,
        children: [
          Icon(
            icon,
            size:
                13,
            color:
                color,
          ),
          const SizedBox(
            width:
                5,
          ),
          Flexible(
            child:
                Text(
              label,
              maxLines:
                  1,
              overflow:
                  TextOverflow
                      .ellipsis,
              style:
                  TextStyle(
                color:
                    color,
                fontSize:
                    11,
                fontWeight:
                    FontWeight
                        .w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}