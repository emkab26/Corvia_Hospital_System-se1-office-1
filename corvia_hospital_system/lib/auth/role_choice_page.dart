import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../pages/doctor/doctor_dashboard.dart';
import '../pages/hospital/hospital_dashboard_page.dart';
import '../pages/lab/hospital_lab_admin_page.dart';
import '../pages/lab/lab_workspace_page.dart';
import '../pages/nurse/nurse_dashboard_page.dart';
import '../pages/patient/dashboard.dart';
import '../pages/reception/reception_dashboard.dart';
import '../services/settings_service.dart';
import '../theme/app_theme.dart';

class RoleChoicePage extends StatefulWidget {
  const RoleChoicePage({super.key});

  @override
  State<RoleChoicePage> createState() => _RoleChoicePageState();
}

class _RoleChoicePageState extends State<RoleChoicePage> {
  final SupabaseClient _supabase = Supabase.instance.client;

  bool _isLoading = true;
  bool _isOpeningMode = false;
  bool _isSigningOut = false;
  bool _isInactive = false;

  bool _hasDoctorProfile = false;
  bool _hasLabWorkerProfile = false;
  bool _hasPatientProfile = false;

  String _role = '';
  String _profileId = '';
  String? _errorMessage;

  Widget? _directDestination;

  @override
  void initState() {
    super.initState();
    _loadAccountRole();
  }

  Future<void> _loadAccountRole() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _isOpeningMode = false;
        _errorMessage = null;
        _isInactive = false;
        _directDestination = null;
        _hasDoctorProfile = false;
        _hasLabWorkerProfile = false;
        _hasPatientProfile = false;
        _profileId = '';
      });
    }

    try {
      final user = _supabase.auth.currentUser;

      if (user == null) {
        if (!mounted) {
          return;
        }

        _returnToAuthGate();
        return;
      }

      final profile = await _supabase
          .from('profiles')
          .select()
          .eq('user_id', user.id)
          .maybeSingle();

      if (!mounted) {
        return;
      }

      if (profile == null) {
        setState(() {
          _isLoading = false;
          _errorMessage =
              'No Corvia profile was found for this account. '
              'Please contact the hospital administrator.';
        });

        return;
      }

      if (profile['is_active'] == false) {
        setState(() {
          _isLoading = false;
          _isInactive = true;
        });

        return;
      }

      final role = _normaliseRole(
        profile['role'] ?? profile['user_type'],
      );

      final profileId = profile['id']?.toString().trim() ?? '';

      final hasDoctorProfile = await _recordExistsByProfileId(
        table: 'doctors',
        profileId: profileId,
        authUserId: user.id,
      );

      final hasPatientProfile = await _recordExistsByProfileId(
        table: 'patients',
        profileId: profileId,
        authUserId: user.id,
      );
      final hasLabWorkerProfile = await _recordExistsByProfileId(
        table: 'lab_worker_accounts',
        profileId: profileId,
        authUserId: user.id,
      );

      if (!mounted) {
        return;
      }

      /*
       * Hospital Admin accounts are admin-only.
       * They must never receive Patient Mode.
       */
      if (_isHospitalAdminRole(role)) {
        setState(() {
          _role = role;
          _profileId = profileId;
          _hasDoctorProfile = hasDoctorProfile;
          _hasLabWorkerProfile = hasLabWorkerProfile;
          _hasPatientProfile = hasPatientProfile;
          _isLoading = false;
          _directDestination = const HospitalDashboardPage();
        });

        return;
      }

      /*
       * Reception accounts are reception-only.
       */
      if (_isReceptionRole(role)) {
        setState(() {
          _role = role;
          _profileId = profileId;
          _hasDoctorProfile = hasDoctorProfile;
          _hasLabWorkerProfile = hasLabWorkerProfile;
          _hasPatientProfile = hasPatientProfile;
          _isLoading = false;
          _directDestination = const ReceptionDashboard();
        });

        return;
      }

      /*
       * IMPORTANT:
       *
       * Do not rely only on profiles.role.
       *
       * A Corvia doctor can also have:
       *
       * profiles.role = patient
       *
       * while a real doctors record exists for that same account.
       *
       * In that case we MUST show the role-choice page instead
       * of forcing the user into Patient Dashboard.
       */
      final hasStaffAccess = hasDoctorProfile ||
          hasLabWorkerProfile ||
          _isClinicalStaffRole(role) ||
          _isLabRole(role);

      if (hasStaffAccess) {
        setState(() {
          _role = role;
          _profileId = profileId;
          _hasDoctorProfile = hasDoctorProfile;
          _hasLabWorkerProfile = hasLabWorkerProfile;
          _hasPatientProfile = hasPatientProfile;
          _isLoading = false;
        });

        return;
      }

      /*
       * Only a genuine patient-only account should bypass
       * RoleChoicePage.
       */
      if (_isPatientRole(role) || hasPatientProfile) {
        setState(() {
          _role = role;
          _profileId = profileId;
          _hasDoctorProfile = hasDoctorProfile;
          _hasLabWorkerProfile = hasLabWorkerProfile;
          _hasPatientProfile = hasPatientProfile;
          _isLoading = false;
          _directDestination = const DashboardPage();
        });

        return;
      }

      setState(() {
        _role = role;
        _profileId = profileId;
        _hasDoctorProfile = hasDoctorProfile;
        _hasLabWorkerProfile = hasLabWorkerProfile;
        _hasPatientProfile = hasPatientProfile;
        _isLoading = false;

        _errorMessage = role.isEmpty
            ? 'No account role has been assigned to this profile.'
            : 'The account role "$role" is not supported by Corvia.';
      });
    } on PostgrestException catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isLoading = false;
        _errorMessage =
            'Could not load your Corvia account role.\n\n'
            '${error.message}';
      });
    } on AuthException catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isLoading = false;
        _errorMessage =
            'Could not confirm your signed-in account.\n\n'
            '${error.message}';
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isLoading = false;
        _errorMessage =
            'Could not load your account access.\n\n$error';
      });
    }
  }

  Future<bool> _recordExistsByProfileId({
    required String table,
    required String profileId,
    required String authUserId,
  }) async {
    /*
     * Corvia has used both relationships in previous builds:
     *
     * auth.users.id -> doctors.profile_id
     *
     * and
     *
     * profiles.id -> doctors.profile_id
     *
     * Check both so old doctor accounts continue working.
     */

    if (authUserId.trim().isNotEmpty) {
      try {
        final response = await _supabase
            .from(table)
            .select('id')
            .eq(
              'profile_id',
              authUserId,
            )
            .limit(1);

        final rows = response as List<dynamic>;

        if (rows.isNotEmpty) {
          return true;
        }
      } catch (error) {
        debugPrint(
          'Could not check $table.profile_id using '
          'auth user ID: $error',
        );
      }
    }

    if (profileId.trim().isNotEmpty &&
        profileId != authUserId) {
      try {
        final response = await _supabase
            .from(table)
            .select('id')
            .eq(
              'profile_id',
              profileId,
            )
            .limit(1);

        final rows = response as List<dynamic>;

        if (rows.isNotEmpty) {
          return true;
        }
      } catch (error) {
        debugPrint(
          'Could not check $table.profile_id using '
          'profile ID: $error',
        );
      }
    }

    return false;
  }

  String _normaliseRole(dynamic value) {
    return value
            ?.toString()
            .trim()
            .toLowerCase()
            .replaceAll('-', '_')
            .replaceAll(' ', '_') ??
        '';
  }

  bool _isHospitalAdminRole(String role) {
    return role == 'hospital_admin' ||
        role == 'hospitaladmin' ||
        role == 'admin';
  }

  bool _isReceptionRole(String role) {
    return role == 'reception' ||
        role == 'receptionist' ||
        role == 'reception_staff' ||
        role == 'receptionist_staff';
  }

  bool _isDoctorRole(String role) {
    return role == 'doctor' ||
        role == 'medical_doctor' ||
        role == 'general_practitioner' ||
        role == 'gp';
  }

  bool _isSpecialistRole(String role) {
    return role == 'specialist' ||
        role == 'medical_specialist' ||
        role == 'specialist_doctor';
  }

  bool _isNurseRole(String role) {
    return role == 'nurse' ||
        role == 'registered_nurse' ||
        role == 'staff_nurse' ||
        role == 'nursing_staff';
  }

  bool _isPatientRole(String role) {
    return role == 'patient' ||
        role == 'member' ||
        role == 'user';
  }

  bool _isClinicalStaffRole(String role) {
    return _isDoctorRole(role) ||
        _isSpecialistRole(role) ||
        _isNurseRole(role);
  }

  bool _isLabRole(String role) {
    return role == 'lab_worker' || _isLabAdminRole(role);
  }

  bool _isLabAdminRole(String role) =>
      {'lab_admin', 'private_lab_admin', 'private_lab_administrator'}.contains(role);

  bool get _canOpenLabDashboard {
    return _hasLabWorkerProfile || _isLabRole(_role);
  }

  bool get _canOpenDoctorDashboard {
    return _hasDoctorProfile ||
        _isDoctorRole(_role) ||
        _isSpecialistRole(_role);
  }

  bool get _canOpenNurseDashboard {
    return _isNurseRole(_role);
  }

  String get _staffRoleName {
    if (_canOpenLabDashboard) {
      return _isLabAdminRole(_role) ? 'Lab Admin' : 'Lab Worker';
    }
    if (_canOpenNurseDashboard) {
      return 'Nurse';
    }

    if (_isSpecialistRole(_role)) {
      return 'Specialist';
    }

    if (_canOpenDoctorDashboard) {
      return 'Doctor';
    }

    return 'Staff';
  }

  String get _staffButtonTitle {
    return 'Continue as $_staffRoleName';
  }

  String get _staffDescription {
    if (_canOpenLabDashboard) {
      return _isLabAdminRole(_role)
          ? 'Open Laboratory Administration to manage your organisation’s technicians and verifiers.'
          : 'Open your assigned Technician or Verifier workspace.';
    }
    if (_canOpenNurseDashboard) {
      return 'Open the Nurse Dashboard to manage your shift, '
          'assigned patients, observations, nursing tasks and '
          'medication rounds.';
    }

    if (_isSpecialistRole(_role)) {
      return 'Open the clinical dashboard to manage specialist '
          'appointments, patients and medical records.';
    }

    return 'Open the Doctor Dashboard to manage patients, '
        'appointments, prescriptions and medical records.';
  }

  IconData get _staffIcon {
    if (_canOpenLabDashboard) {
      return Icons.science_outlined;
    }
    if (_canOpenNurseDashboard) {
      return Icons.badge_outlined;
    }

    if (_isSpecialistRole(_role)) {
      return Icons.local_hospital_outlined;
    }

    return Icons.medical_services_outlined;
  }

  Future<void> _openModePage(
    Widget page,
  ) async {
    if (!mounted) {
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => page,
      ),
    );
  }

  void _returnToAuthGate() {
    if (!mounted) {
      return;
    }

    Navigator.of(context).popUntil(
      (route) => route.isFirst,
    );
  }

  Future<void> _continueAsStaff() async {
    if (_isLoading ||
        _isOpeningMode ||
        _isSigningOut) {
      return;
    }

    setState(() {
      _isOpeningMode = true;
    });

    try {
      if (_canOpenLabDashboard) {
        await _openModePage(
          _isLabAdminRole(_role)
              ? const HospitalLabAdminPage()
              : const LabWorkspacePage(),
        );
        return;
      }

      if (_canOpenNurseDashboard) {
        await _openModePage(
          const NurseDashboardPage(),
        );

        return;
      }

      if (_canOpenDoctorDashboard) {
        await _openModePage(
          const DoctorDashboard(),
        );

        return;
      }

      throw Exception(
        'This account does not have a linked staff dashboard.',
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              'Could not open the staff dashboard. $error',
            ),
          ),
        );
    } finally {
      if (mounted) {
        setState(() {
          _isOpeningMode = false;
        });
      }
    }
  }

  Future<void> _continueAsPatient() async {
    if (_isLoading ||
        _isOpeningMode ||
        _isSigningOut) {
      return;
    }

    setState(() {
      _isOpeningMode = true;
    });

    try {
      /*
       * This changes only the displayed dashboard.
       *
       * DO NOT modify profiles.role here.
       *
       * A doctor remains a doctor even while using their
       * personal Patient Mode.
       */
      await _openModePage(
        const DashboardPage(),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              'Could not open patient mode. $error',
            ),
          ),
        );
    } finally {
      if (mounted) {
        setState(() {
          _isOpeningMode = false;
        });
      }
    }
  }

  Future<void> _signOut() async {
    if (_isSigningOut) {
      return;
    }

    setState(() {
      _isSigningOut = true;
    });

    try {
      SettingsService.instance.sessionUnlocked = false;

      await _supabase.auth.signOut();

      if (!mounted) {
        return;
      }

      _returnToAuthGate();
    } on AuthException catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              'Sign out failed: ${error.message}',
            ),
          ),
        );
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              'Sign out failed. $error',
            ),
          ),
        );
    } finally {
      if (mounted) {
        setState(() {
          _isSigningOut = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_directDestination != null) {
      return _directDestination!;
    }

    if (_isLoading) {
      return _buildLoadingPage();
    }

    if (_isInactive) {
      return _buildInactivePage();
    }

    if (_errorMessage != null) {
      return _buildErrorPage();
    }

    return Scaffold(
      backgroundColor: context.cBgPrimary,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text(
          'Choose Mode',
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh access',
            onPressed:
                _isOpeningMode || _isSigningOut
                    ? null
                    : _loadAccountRole,
            icon: const Icon(
              Icons.refresh_rounded,
            ),
          ),
          IconButton(
            tooltip: 'Sign out',
            onPressed:
                _isSigningOut ? null : _signOut,
            icon: _isSigningOut
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: CorviaColors.accent,
                    ),
                  )
                : const Icon(
                    Icons.logout,
                  ),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const SizedBox(height: 12),
            CircleAvatar(
              radius: 38,
              backgroundColor:
                  CorviaColors.accent.withValues(
                alpha: 0.12,
              ),
              child: Icon(
                Icons.compare_arrows_rounded,
                size: 40,
                color: CorviaColors.accent,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'How would you like to continue?',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: context.cTextPrimary,
                fontSize: 23,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'This account has staff or laboratory access. '
              'You can open your assigned workspace '
              'or use Corvia as a patient.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: context.cTextSecondary,
                fontSize: 15,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 18),
            Center(
              child: Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  _AccessPill(
                    label:
                        'Profile role: ${_role.isEmpty ? 'not assigned' : _role}',
                    icon: Icons.badge_outlined,
                  ),
                  if (_hasDoctorProfile)
                    const _AccessPill(
                      label: 'Doctor record linked',
                      icon:
                          Icons.medical_services_outlined,
                    ),
                  if (_hasLabWorkerProfile)
                    const _AccessPill(
                      label: 'Lab access linked',
                      icon: Icons.science_outlined,
                    ),
                  if (_hasPatientProfile)
                    const _AccessPill(
                      label: 'Patient record linked',
                      icon: Icons.person_outline,
                    ),
                  if (_profileId.isNotEmpty)
                    const _AccessPill(
                      label: 'Profile linked',
                      icon:
                          Icons.verified_user_outlined,
                    ),
                ],
              ),
            ),
            const SizedBox(height: 32),
            _ModeCard(
              icon: Icons.person_outline,
              title: 'Continue as Patient',
              subtitle:
                  'View your own appointments, records, '
                  'prescriptions and patient health services.',
              onTap:
                  _isOpeningMode || _isSigningOut
                      ? null
                      : _continueAsPatient,
            ),
            const SizedBox(height: 16),
            _ModeCard(
              icon: _staffIcon,
              title: _staffButtonTitle,
              subtitle: _staffDescription,
              onTap:
                  _isOpeningMode || _isSigningOut
                      ? null
                      : _continueAsStaff,
              trailing: _isOpeningMode
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child:
                          CircularProgressIndicator(
                        strokeWidth: 2,
                        color: CorviaColors.accent,
                      ),
                    )
                  : null,
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: context.cBgSecondary,
                borderRadius:
                    BorderRadius.circular(14),
                border: Border.all(
                  color:
                      context.cTextMuted.withValues(
                    alpha: 0.20,
                  ),
                ),
              ),
              child: Row(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.info_outline,
                    color: CorviaColors.accent,
                    size: 22,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Changing modes does not change '
                      'your database role or remove '
                      'your doctor access.',
                      style: TextStyle(
                        color:
                            context.cTextSecondary,
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingPage() {
    return Scaffold(
      backgroundColor: context.cBgPrimary,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(
              color: CorviaColors.accent,
            ),
            const SizedBox(height: 16),
            Text(
              'Loading your account access...',
              style: TextStyle(
                color: context.cTextSecondary,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInactivePage() {
    return Scaffold(
      backgroundColor: context.cBgPrimary,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding:
                const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints:
                  const BoxConstraints(
                maxWidth: 480,
              ),
              child: Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: context.cBgSecondary,
                  borderRadius:
                      BorderRadius.circular(22),
                  border: Border.all(
                    color: context.cDivider,
                  ),
                ),
                child: Column(
                  mainAxisSize:
                      MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.block,
                      color: CorviaColors.danger,
                      size: 58,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Account inactive',
                      textAlign:
                          TextAlign.center,
                      style: TextStyle(
                        color:
                            context.cTextPrimary,
                        fontSize: 22,
                        fontWeight:
                            FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'This account has been '
                      'deactivated. Please contact '
                      'the hospital administrator.',
                      textAlign:
                          TextAlign.center,
                      style: TextStyle(
                        color:
                            context.cTextSecondary,
                        fontSize: 15,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 22),
                    SizedBox(
                      width: double.infinity,
                      child:
                          OutlinedButton.icon(
                        onPressed:
                            _isSigningOut
                                ? null
                                : _signOut,
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
        ),
      ),
    );
  }

  Widget _buildErrorPage() {
    return Scaffold(
      backgroundColor: context.cBgPrimary,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding:
                const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints:
                  const BoxConstraints(
                maxWidth: 500,
              ),
              child: Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: context.cBgSecondary,
                  borderRadius:
                      BorderRadius.circular(22),
                  border: Border.all(
                    color: context.cDivider,
                  ),
                ),
                child: Column(
                  mainAxisSize:
                      MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.error_outline,
                      color: CorviaColors.danger,
                      size: 58,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Could not load account mode',
                      textAlign:
                          TextAlign.center,
                      style: TextStyle(
                        color:
                            context.cTextPrimary,
                        fontSize: 22,
                        fontWeight:
                            FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    SelectableText(
                      _errorMessage ??
                          'Unknown account access error.',
                      textAlign:
                          TextAlign.center,
                      style: TextStyle(
                        color:
                            context.cTextSecondary,
                        fontSize: 14,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 22),
                    SizedBox(
                      width: double.infinity,
                      child:
                          ElevatedButton.icon(
                        onPressed:
                            _loadAccountRole,
                        icon: const Icon(
                          Icons.refresh,
                        ),
                        label: const Text(
                          'Try Again',
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child:
                          OutlinedButton.icon(
                        onPressed:
                            _isSigningOut
                                ? null
                                : _signOut,
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
        ),
      ),
    );
  }
}

class _AccessPill extends StatelessWidget {
  const _AccessPill({
    required this.label,
    required this.icon,
  });

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 13,
        vertical: 7,
      ),
      decoration: BoxDecoration(
        color: CorviaColors.accent.withValues(
          alpha: 0.12,
        ),
        borderRadius:
            BorderRadius.circular(99),
        border: Border.all(
          color: CorviaColors.accent.withValues(
            alpha: 0.30,
          ),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            color: context.cAccentReadable,
            size: 14,
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: context.cAccentReadable,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.cBgSecondary,
      borderRadius:
          BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        borderRadius:
            BorderRadius.circular(18),
        child: Container(
          padding:
              const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius:
                BorderRadius.circular(18),
            border: Border.all(
              color:
                  context.cTextMuted.withValues(
                alpha: 0.16,
              ),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color:
                      CorviaColors.accent.withValues(
                    alpha: 0.12,
                  ),
                  borderRadius:
                      BorderRadius.circular(16),
                ),
                child: Icon(
                  icon,
                  color: CorviaColors.accent,
                  size: 31,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color:
                            context.cTextPrimary,
                        fontSize: 17,
                        fontWeight:
                            FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color:
                            context.cTextSecondary,
                        fontSize: 13,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              trailing ??
                  Icon(
                    Icons.chevron_right,
                    color: context.cTextMuted,
                  ),
            ],
          ),
        ),
      ),
    );
  }
}
