import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../pages/doctor/doctor_dashboard.dart';
import '../pages/dispatch/dispatch_dashboard.dart';
import '../pages/paramedic/paramedic_workspace_page.dart';
import '../pages/hospital/hospital_dashboard_page.dart';
import '../pages/lab/lab_workspace_page.dart';
import '../pages/lab/hospital_lab_admin_page.dart';
import '../pages/nurse/nurse_dashboard_page.dart';
import '../pages/patient/dashboard.dart';
import '../pages/pharmacist/pharmacist_dashboard_page.dart';
import '../pages/reception/reception_dashboard.dart';
import '../services/account_mode_service.dart';
import '../services/settings_service.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';

import 'biometric_lock_page.dart';
import 'device_verification_page.dart';
import 'login.dart';
import 'role_choice_page.dart';

// =============================================================================
// ROOT AUTH GATE
// =============================================================================

class AuthGate extends StatefulWidget {
  const AuthGate({
    super.key,
  });

  @override
  State<AuthGate> createState() {
    return _AuthGateState();
  }
}

class _AuthGateState
    extends State<AuthGate>
    with WidgetsBindingObserver {
  final SettingsService _settings =
      SettingsService.instance;

  bool _resumeRebuildScheduled =
      false;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addObserver(
      this,
    );

    /*
     * IMPORTANT:
     *
     * Do NOT listen to every SettingsService notification here.
     *
     * sessionUnlocked changes during app lifecycle transitions.
     * Rebuilding AuthGate from both the listener and
     * didChangeAppLifecycleState can cause duplicate rebuilds.
     */
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(
      this,
    );

    super.dispose();
  }

  // =============================================================================
  // APP LIFECYCLE
  // =============================================================================

  @override
  void didChangeAppLifecycleState(
    AppLifecycleState state,
  ) {
    /*
     * ---------------------------------------------------------------
     * APP LEAVING FOREGROUND
     * ---------------------------------------------------------------
     *
     * Mark biometric session as locked.
     *
     * IMPORTANT:
     * Do NOT call setState while Android is pausing/detaching.
     *
     * We wait until RESUMED before changing the widget tree.
     */
    if (state ==
            AppLifecycleState.paused ||
        state ==
            AppLifecycleState.detached) {
      if (_settings.anyBiometricEnabled &&
          _settings.sessionUnlocked) {
        _settings.sessionUnlocked =
            false;
      }

      return;
    }

    /*
     * ---------------------------------------------------------------
     * APP RETURNED TO FOREGROUND
     * ---------------------------------------------------------------
     */
    if (state ==
        AppLifecycleState.resumed) {
      _scheduleResumeRebuild();
    }
  }

  void _scheduleResumeRebuild() {
    if (_resumeRebuildScheduled) {
      return;
    }

    _resumeRebuildScheduled =
        true;

    WidgetsBinding.instance
        .addPostFrameCallback(
      (_) {
        _resumeRebuildScheduled =
            false;

        if (!mounted) {
          return;
        }

        setState(() {});
      },
    );
  }

  // =============================================================================
  // BIOMETRIC / DEVICE UNLOCK
  // =============================================================================

  void _onUnlocked() {
    _settings.sessionUnlocked =
        true;

    if (!mounted) {
      return;
    }

    setState(() {});
  }

  // =============================================================================
  // BUILD
  // =============================================================================

  @override
  Widget build(
    BuildContext context,
  ) {
    return StreamBuilder<AuthState>(
      stream:
          Supabase.instance.client.auth
              .onAuthStateChange,

      builder:
          (
        context,
        snapshot,
      ) {
        final session =
            Supabase.instance.client.auth
                .currentSession;

        /*
         * -----------------------------------------------------------
         * SIGNED OUT
         * -----------------------------------------------------------
         */
        if (session == null) {
          if (_settings.sessionUnlocked) {
            _settings.sessionUnlocked =
                false;
          }

          return const LoginPage();
        }

        /*
         * -----------------------------------------------------------
         * DEVICE VERIFICATION
         * -----------------------------------------------------------
         */
        if (!_settings.deviceVerified) {
          return DeviceVerificationPage(
            onVerified:
                _onUnlocked,
          );
        }

        /*
         * -----------------------------------------------------------
         * BIOMETRIC LOCK
         * -----------------------------------------------------------
         */
        if (_settings.anyBiometricEnabled &&
            !_settings.sessionUnlocked) {
          return BiometricLockPage(
            onUnlocked:
                _onUnlocked,
          );
        }

        /*
         * -----------------------------------------------------------
         * ROLE RESOLUTION
         * -----------------------------------------------------------
         */
        return _RoleResolver(
          key:
              ValueKey<String>(
            'role-${session.user.id}',
          ),
        );
      },
    );
  }
}

// =============================================================================
// ROLE RESOLVER
// =============================================================================

class _RoleResolver
    extends StatefulWidget {
  const _RoleResolver({
    super.key,
  });

  @override
  State<_RoleResolver> createState() {
    return _RoleResolverState();
  }
}

class _RoleResolverState
    extends State<_RoleResolver> {
  late Future<_AccountAccess>
      _accountFuture;

  @override
  void initState() {
    super.initState();

    _accountFuture =
        _loadAccountAccess();
  }

  void _retry() {
    setState(() {
      _accountFuture =
          _loadAccountAccess();
    });
  }

  String _normaliseRole(
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

  Future<Map<String, dynamic>?>
      _loadProfile({
    required SupabaseClient client,
    required String userId,
  }) async {
    final profile =
        await client
            .from(
              'profiles',
            )
            .select()
            .eq(
              'user_id',
              userId,
            )
            .maybeSingle();

    if (profile == null) {
      return null;
    }

    return Map<String, dynamic>.from(
      profile,
    );
  }

  Future<_AccountAccess>
      _loadAccountAccess() async {
    final client =
        Supabase.instance.client;

    final user =
        client.auth.currentUser;

    if (user == null) {
      return const _AccountAccess
          .signedOut();
    }

    var profile =
        await _loadProfile(
      client:
          client,
      userId:
          user.id,
    );

    /*
     * Normal patient registration bootstrap.
     */
    if (profile == null &&
        SupabaseService
            .isPatientSelfRegistration(
          user,
        )) {
      await SupabaseService
          .ensureUserMedicalRecords(
        createPatientRow:
            true,
      );

      profile =
          await _loadProfile(
        client:
            client,
        userId:
            user.id,
      );
    }

    if (profile == null) {
      return _AccountAccess(
        userId:
            user.id,
        profileId:
            '',
        role:
            '',
        isActive:
            true,
        profileFound:
            false,
        hasDoctorProfile:
            false,
        hasNurseProfile:
            false,
        hasPharmacistProfile:
            false,
        hasLabWorkerProfile:
            false,
        hasPatientProfile:
            false,
      );
    }

    final profileId =
        profile['id']
                ?.toString()
                .trim() ??
            '';

    final role =
        _normaliseRole(
      profile['role'] ??
          profile['user_type'],
    );

    final isActive =
        profile['is_active'] !=
            false;

    /*
     * Switch Mode is based on actual database relationships.
     */
    final modeAccess =
        await AccountModeService
            .current();

    var hasEmsWorkspace = false;
    try {
      final ems = await client
          .rpc('corvia_ems_access')
          .timeout(const Duration(seconds: 8));
      hasEmsWorkspace = ems is List && ems.isNotEmpty;
    } catch (_) {
      // No EMS access or the EMS package is not installed.
    }

    return _AccountAccess(
      userId:
          user.id,
      profileId:
          profileId,
      role:
          role,
      isActive:
          isActive,
      profileFound:
          true,
      hasDoctorProfile:
          modeAccess
              .hasDoctorProfile,
      hasNurseProfile:
          modeAccess
              .hasNurseProfile,
      hasPharmacistProfile:
          modeAccess
              .hasPharmacistProfile,
      hasLabWorkerProfile:
          modeAccess
              .hasLabWorkerProfile,
      hasPatientProfile:
          modeAccess
              .hasPatientProfile,
      hasEmsWorkspace:
          hasEmsWorkspace,
    );
  }

  // =============================================================================
  // DESTINATION
  // =============================================================================

  Widget _destinationFor(
    _AccountAccess account,
  ) {
    final dispatchAccess = dispatchAccessLevelForRole(
      account.role,
    );

    if (dispatchAccess != null) {
      // The WS4 dispatch RPCs have not passed the hosted release gate, so
      // dispatchers use the installed Fleet & Dispatch workspace, which shows
      // live vehicles and incidents for their linked hospital.
      return ParamedicWorkspacePage(
        title: 'Fleet & Dispatch',
        initialSection: 'Fleet overview',
        onSignOut: () {
          SupabaseService.signOut();
        },
      );
    }

    /*
     * Hospital Admin:
     * Admin-only account.
     */
    if (account.isHospitalAdmin) {
      return const HospitalDashboardPage();
    }

    // Lab staff go straight to their workspace; its Switch button opens
    // the patient side when the account also has a patient record.
    if (account.isLabWorker) {
      return const LabWorkspacePage();
    }

    if (account.isHospitalLabAdmin) {
      return const HospitalLabAdminPage();
    }

    /*
     * Reception:
     * Reception-only account.
     */
    if (account.isReceptionist) {
      return const ReceptionDashboard();
    }

    /*
     * Pharmacist.
     */
    if (account.hasPharmacistProfile ||
        account.isPharmacist) {
      return const PharmacistDashboardPage();
    }

    /*
     * Doctor / Specialist.
     *
     * Doctor + Patient
     * -> RoleChoicePage
     *
     * Doctor only
     * -> DoctorDashboard
     */
    if (account.hasDoctorProfile) {
      if (account.hasPatientProfile) {
        return const RoleChoicePage();
      }

      return const DoctorDashboard();
    }

    /*
     * Nurse.
     *
     * Nurse + Patient
     * -> RoleChoicePage
     *
     * Nurse only
     * -> NurseDashboard
     */
    if (account.hasNurseProfile) {
      if (account.hasPatientProfile) {
        return const RoleChoicePage();
      }

      return const NurseDashboardPage();
    }

    /*
     * Fleet manager / EMS crew: linked through Fleet > Personnel, while the
     * profile role usually stays `patient`.
     */
    if (account.hasEmsWorkspace) {
      return ParamedicWorkspacePage(
        title: 'Fleet & Paramedic',
        initialSection: 'Vehicles',
        onSignOut: () {
          SupabaseService.signOut();
        },
      );
    }

    /*
     * Normal Patient.
     */
    if (account.hasPatientProfile ||
        account.isPatient) {
      return const DashboardPage();
    }

    return _AccountMessagePage(
      icon:
          Icons.manage_accounts_outlined,
      iconColor:
          CorviaColors.warning,
      title:
          'Account role not supported',
      message:
          account.role.isEmpty
              ? 'No account role has been assigned to this Corvia profile.'
              : 'The role "${account.role}" does not have a matching Corvia staff or patient record.',
      primaryLabel:
          'Check Again',
      onPrimary:
          _retry,
      showSignOut:
          true,
    );
  }

  // =============================================================================
  // BUILD
  // =============================================================================

  @override
  Widget build(
    BuildContext context,
  ) {
    return FutureBuilder<_AccountAccess>(
      future:
          _accountFuture,

      builder:
          (
        context,
        snapshot,
      ) {
        if (snapshot.connectionState !=
            ConnectionState.done) {
          return const _RoleLoadingPage();
        }

        if (snapshot.hasError) {
          return _AccountMessagePage(
            icon:
                Icons.cloud_off_outlined,
            iconColor:
                CorviaColors.danger,
            title:
                'Could not load account access',
            message:
                'Corvia could not confirm your profile and role.\n\n${snapshot.error}',
            primaryLabel:
                'Retry',
            onPrimary:
                _retry,
            showSignOut:
                true,
          );
        }

        final account =
            snapshot.data ??
                const _AccountAccess
                    .signedOut();

        if (!account.isSignedIn) {
          return const LoginPage();
        }

        if (!account.profileFound) {
          return _AccountMessagePage(
            icon:
                Icons.person_search_outlined,
            iconColor:
                CorviaColors.warning,
            title:
                'Profile not found',
            message:
                'The login exists, but no matching row was found in the profiles table.\n\nUser ID: ${account.userId}',
            primaryLabel:
                'Try Again',
            onPrimary:
                _retry,
            showSignOut:
                true,
          );
        }

        if (!account.isActive) {
          return _AccountMessagePage(
            icon:
                Icons.block_rounded,
            iconColor:
                CorviaColors.danger,
            title:
                'Account inactive',
            message:
                'This account has been deactivated. Contact the hospital administrator.',
            primaryLabel:
                'Check Again',
            onPrimary:
                _retry,
            showSignOut:
                true,
          );
        }

        return _destinationFor(
          account,
        );
      },
    );
  }
}

// =============================================================================
// ACCOUNT ACCESS MODEL
// =============================================================================

class _AccountAccess {
  const _AccountAccess({
    required this.userId,
    required this.profileId,
    required this.role,
    required this.isActive,
    required this.profileFound,
    required this.hasDoctorProfile,
    required this.hasNurseProfile,
    required this.hasPharmacistProfile,
    required this.hasLabWorkerProfile,
    required this.hasPatientProfile,
    this.hasEmsWorkspace = false,
  });

  const _AccountAccess.signedOut()
      : userId = '',
        profileId = '',
        role = '',
        isActive = true,
        profileFound = false,
        hasDoctorProfile = false,
        hasNurseProfile = false,
        hasPharmacistProfile = false,
        hasLabWorkerProfile = false,
        hasPatientProfile = false,
        hasEmsWorkspace = false;

  final String userId;
  final String profileId;
  final String role;

  final bool isActive;
  final bool profileFound;

  final bool hasDoctorProfile;
  final bool hasNurseProfile;
  final bool hasPharmacistProfile;
  final bool hasLabWorkerProfile;
  final bool hasPatientProfile;

  /// Linked to a hospital Fleet / EMS workspace (fleet manager, crew).
  /// Their profile role is often still `patient`.
  final bool hasEmsWorkspace;

  bool get isSignedIn {
    return userId.trim().isNotEmpty;
  }

  bool get isHospitalAdmin {
    return {
      'hospital_admin',
      'hospitaladmin',
      'admin',
    }.contains(
      role,
    );
  }

  bool get isLabWorker {
    return {
      'lab_worker',
      'lab_technician',
      'laboratory_technician',
      'laboratory_worker',
    }.contains(
      role,
    );
  }

  bool get isHospitalLabAdmin {
    return {'lab_admin', 'private_lab_admin', 'private_lab_administrator'}.contains(role);
  }

  bool get isReceptionist {
    return {
      'reception',
      'receptionist',
      'reception_staff',
      'receptionist_staff',
    }.contains(
      role,
    );
  }

  bool get isPharmacist {
    return {
      'pharmacist',
      'hospital_pharmacist',
      'pharmacy_staff',
      'pharmacy',
    }.contains(
      role,
    );
  }

  bool get isPatient {
    return {
      'patient',
      'member',
      'user',
    }.contains(
      role,
    );
  }
}

// =============================================================================
// ROLE LOADING
// =============================================================================

class _RoleLoadingPage
    extends StatelessWidget {
  const _RoleLoadingPage();

  @override
  Widget build(
    BuildContext context,
  ) {
    return Scaffold(
      backgroundColor:
          context.cBgPrimary,
      body:
          Center(
        child:
            Column(
          mainAxisSize:
              MainAxisSize.min,
          children: [
            CircularProgressIndicator(
              color:
                  CorviaColors.accent,
            ),
            const SizedBox(
              height:
                  16,
            ),
            Text(
              'Loading your Corvia account...',
              style:
                  TextStyle(
                color:
                    context.cTextSecondary,
                fontSize:
                    14,
                fontWeight:
                    FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// ACCOUNT MESSAGE
// =============================================================================

class _AccountMessagePage
    extends StatelessWidget {
  const _AccountMessagePage({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.message,
    required this.primaryLabel,
    required this.onPrimary,
    required this.showSignOut,
  });

  final IconData icon;
  final Color iconColor;

  final String title;
  final String message;

  final String primaryLabel;

  final VoidCallback onPrimary;

  final bool showSignOut;

  Future<void> _signOut() async {
    SettingsService.instance
        .sessionUnlocked = false;

    await Supabase.instance.client.auth
        .signOut();
  }

  @override
  Widget build(
    BuildContext context,
  ) {
    return Scaffold(
      backgroundColor:
          context.cBgPrimary,

      body:
          SafeArea(
        child:
            Center(
          child:
              SingleChildScrollView(
            padding:
                const EdgeInsets.all(
              24,
            ),
            child:
                ConstrainedBox(
              constraints:
                  const BoxConstraints(
                maxWidth:
                    500,
              ),
              child:
                  Container(
                width:
                    double.infinity,
                padding:
                    const EdgeInsets.all(
                  24,
                ),
                decoration:
                    BoxDecoration(
                  color:
                      context.cBgSecondary,
                  borderRadius:
                      BorderRadius.circular(
                    22,
                  ),
                  border:
                      Border.all(
                    color:
                        context.cDivider,
                  ),
                ),
                child:
                    Column(
                  mainAxisSize:
                      MainAxisSize.min,
                  children: [
                    Icon(
                      icon,
                      color:
                          iconColor,
                      size:
                          58,
                    ),

                    const SizedBox(
                      height:
                          16,
                    ),

                    Text(
                      title,
                      textAlign:
                          TextAlign.center,
                      style:
                          TextStyle(
                        color:
                            context.cTextPrimary,
                        fontSize:
                            22,
                        fontWeight:
                            FontWeight.bold,
                      ),
                    ),

                    const SizedBox(
                      height:
                          12,
                    ),

                    SelectableText(
                      message,
                      textAlign:
                          TextAlign.center,
                      style:
                          TextStyle(
                        color:
                            context.cTextSecondary,
                        fontSize:
                            14,
                        height:
                            1.4,
                      ),
                    ),

                    const SizedBox(
                      height:
                          22,
                    ),

                    SizedBox(
                      width:
                          double.infinity,
                      child:
                          ElevatedButton.icon(
                        onPressed:
                            onPrimary,
                        icon:
                            const Icon(
                          Icons.refresh_rounded,
                        ),
                        label:
                            Text(
                          primaryLabel,
                        ),
                      ),
                    ),

                    if (showSignOut) ...[
                      const SizedBox(
                        height:
                            10,
                      ),

                      SizedBox(
                        width:
                            double.infinity,
                        child:
                            OutlinedButton.icon(
                          onPressed:
                              _signOut,
                          icon:
                              const Icon(
                            Icons.logout_rounded,
                          ),
                          label:
                              const Text(
                            'Sign Out',
                          ),
                        ),
                      ),
                    ],
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

// =============================================================================
// CENTRAL ROUTING HELPERS
// =============================================================================

Future<void> routeAfterLogin(
  BuildContext context,
) async {
  if (!context.mounted) {
    return;
  }

  /*
   * AuthGate already owns the root route.
   *
   * Never push another AuthGate.
   */
  Navigator.of(
    context,
  ).popUntil(
    (
      route,
    ) =>
        route.isFirst,
  );
}

Future<void> routeToDoctorDashboard(
  BuildContext context,
) async {
  if (!context.mounted) {
    return;
  }

  Navigator.of(
    context,
  ).pushAndRemoveUntil(
    MaterialPageRoute<void>(
      builder:
          (_) =>
              const DoctorDashboard(),
    ),
    (
      route,
    ) =>
        false,
  );
}

Future<void> routeToNurseDashboard(
  BuildContext context,
) async {
  if (!context.mounted) {
    return;
  }

  Navigator.of(
    context,
  ).pushAndRemoveUntil(
    MaterialPageRoute<void>(
      builder:
          (_) =>
              const NurseDashboardPage(),
    ),
    (
      route,
    ) =>
        false,
  );
}

Future<void> routeToPharmacistDashboard(
  BuildContext context,
) async {
  if (!context.mounted) {
    return;
  }

  Navigator.of(
    context,
  ).pushAndRemoveUntil(
    MaterialPageRoute<void>(
      builder:
          (_) =>
              const PharmacistDashboardPage(),
    ),
    (
      route,
    ) =>
        false,
  );
}

Future<void> routeToHospitalDashboard(
  BuildContext context,
) async {
  if (!context.mounted) {
    return;
  }

  Navigator.of(
    context,
  ).pushAndRemoveUntil(
    MaterialPageRoute<void>(
      builder:
          (_) =>
              const HospitalDashboardPage(),
    ),
    (
      route,
    ) =>
        false,
  );
}

Future<void> routeToPatientDashboard(
  BuildContext context,
) async {
  if (!context.mounted) {
    return;
  }

  Navigator.of(
    context,
  ).pushAndRemoveUntil(
    MaterialPageRoute<void>(
      builder:
          (_) =>
              const DashboardPage(),
    ),
    (
      route,
    ) =>
        false,
  );
}

Future<void> routeToReceptionDashboard(
  BuildContext context,
) async {
  if (!context.mounted) {
    return;
  }

  Navigator.of(
    context,
  ).pushAndRemoveUntil(
    MaterialPageRoute<void>(
      builder:
          (_) =>
              const ReceptionDashboard(),
    ),
    (
      route,
    ) =>
        false,
  );
}
