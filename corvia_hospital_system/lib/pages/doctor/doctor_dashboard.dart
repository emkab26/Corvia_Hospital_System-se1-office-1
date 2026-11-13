import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../responsive_layout.dart';
import '../../services/account_mode_service.dart';
import '../../services/doctor_clinical_service.dart';
import '../../services/settings_service.dart';
import '../../theme/app_theme.dart';

import '../forms/corvia_forms_navigator.dart';
import '../shared/settings.dart';

import 'doctor_appointments.dart';
import 'doctor_clinical_lab_request_sheet.dart';
import 'doctor_medical_records.dart';
import 'doctor_messages_page.dart';
import 'doctor_patient_management.dart';
import 'doctor_patient_records.dart';
import 'doctor_prescription_dashboard.dart';
import 'doctor_qr_scanner.dart';
import 'doctor_reception_queue_page.dart';
import 'doctor_specialist_referral_page.dart';
import 'doctor_telehealth.dart';
import 'doctor_bottom_navigation.dart';

// =============================================================================
// DOCTOR DASHBOARD
// =============================================================================

class DoctorDashboard extends StatefulWidget {
  const DoctorDashboard({
    super.key,
  });

  @override
  State<DoctorDashboard> createState() {
    return _DoctorDashboardState();
  }
}

class _DoctorDashboardState extends State<DoctorDashboard> {
  final SupabaseClient _supabase = Supabase.instance.client;

  final DoctorClinicalService _clinicalService = DoctorClinicalService();

  final List<Widget> _pages = [];

  DoctorClinicalContext? _doctorContext;

  int _currentIndex = 0;

  bool _isLoading = true;
  bool _isSigningOut = false;
  bool _canSwitchMode = false;

  String? _errorMessage;

  String _doctorName = 'Doctor';
  String _doctorSpecialization = 'General Practitioner';
  String _doctorLocation = 'Medical Center';

  @override
  void initState() {
    super.initState();

    _initializeDoctor();
  }

  // ==========================================================================
  // INITIALISE DOCTOR
  // ==========================================================================

  Future<void> _initializeDoctor() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
        _currentIndex = 0;
        _pages.clear();
      });
    }

    try {
      final doctorContext = await _clinicalService.currentContext();

      bool canSwitchMode = false;

      try {
        final modeAccess = await AccountModeService.current();

        canSwitchMode = modeAccess.canSwitchDoctorPatient;
      } catch (error) {
        debugPrint(
          'Doctor mode access lookup failed: $error',
        );
      }

      Map<String, dynamic> doctorRow = {};

      try {
        final response = await _supabase
            .from('doctors')
            .select()
            .eq(
              'id',
              doctorContext.doctorId,
            )
            .maybeSingle();

        if (response != null) {
          doctorRow = Map<String, dynamic>.from(
            response,
          );
        }
      } catch (error) {
        debugPrint(
          'Doctor detail lookup failed: $error',
        );
      }

      final specialization = _firstText(
        [
          doctorRow['specialization'],
          doctorRow['speciality'],
          doctorRow['specialty'],
        ],
        fallback: 'General Practitioner',
      );

      final location = _firstText(
        [
          doctorRow['location'],
          doctorRow['location_name'],
          doctorRow['hospital_name'],
          doctorRow['practice_name'],
          doctorRow['room_name'],
        ],
        fallback: 'Medical Center',
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _doctorContext = doctorContext;

        _doctorName = doctorContext.doctorName;

        _doctorSpecialization = specialization;

        _doctorLocation = location;

        _canSwitchMode = canSwitchMode;

        _pages
          ..clear()
          ..addAll(
            [
              DoctorDashboardHome(
                doctorName: doctorContext.doctorName,
                doctorSpecialization: specialization,
                doctorLocation: location,
                currentDoctorId: doctorContext.doctorId,
                currentHospitalId: doctorContext.hospitalId,
                onAppointments: () {
                  _selectTab(
                    1,
                  );
                },
                onPatients: () {
                  _selectTab(
                    2,
                  );
                },
                onPrescriptions: () {
                  _selectTab(
                    3,
                  );
                },
                onLabs: () {
                  _selectTab(
                    4,
                  );
                },
                onRecords: _openPatientRecords,
                onForms: _openPatientForms,
                onMessages: _openMessages,
              ),
              const DoctorAppointmentsPage(),
              const DoctorPatientManagementPage(),
              DoctorPrescriptionDashboard(
                doctorName: doctorContext.doctorName,
                doctorSpecialization: specialization,
                doctorLocation: location,
              ),
              DoctorLabRequestPage(
                doctorId: doctorContext.doctorId,
              ),
            ],
          );

        _isLoading = false;
      });
    } catch (error) {
      debugPrint(
        'Doctor Dashboard initialization failed: $error',
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _pages.clear();

        _isLoading = false;

        _errorMessage = _cleanError(
          error,
        );
      });
    }
  }

  // ==========================================================================
  // MAIN TABS
  // ==========================================================================

  void _selectTab(
    int index,
  ) {
    if (index < 0 || index >= _pages.length) {
      return;
    }

    setState(() {
      _currentIndex = index;
    });
  }

  // ==========================================================================
  // GENERIC PAGE OPEN
  // ==========================================================================

  Future<void> _openPage(
    Widget page,
  ) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) {
          return page;
        },
      ),
    );

    if (!mounted) {
      return;
    }

    await _refreshHome();
  }

  Future<void> _refreshHome() async {
    final doctorContext = _doctorContext;

    if (doctorContext == null || _pages.isEmpty) {
      return;
    }

    setState(() {
      _pages[0] = DoctorDashboardHome(
        doctorName: doctorContext.doctorName,
        doctorSpecialization: _doctorSpecialization,
        doctorLocation: _doctorLocation,
        currentDoctorId: doctorContext.doctorId,
        currentHospitalId: doctorContext.hospitalId,
        onAppointments: () {
          _selectTab(
            1,
          );
        },
        onPatients: () {
          _selectTab(
            2,
          );
        },
        onPrescriptions: () {
          _selectTab(
            3,
          );
        },
        onLabs: () {
          _selectTab(
            4,
          );
        },
        onRecords: _openPatientRecords,
        onForms: _openPatientForms,
        onMessages: _openMessages,
      );
    });
  }

  // ==========================================================================
  // PATIENT FORMS
  // ==========================================================================

  Future<void> _openPatientForms() async {
    final doctorContext = _doctorContext;

    if (doctorContext == null) {
      _showMessage(
        'Doctor context is unavailable.',
      );

      return;
    }

    /*
     * FIX:
     *
     * We no longer call a missing global
     * openDoctorPatientForms() helper.
     *
     * The full patient forms selector is now a real page
     * declared lower down in THIS file.
     */

    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) {
          return DoctorPatientFormSelectorPage(
            doctorId: doctorContext.doctorId,
            hospitalId: doctorContext.hospitalId,
          );
        },
      ),
    );
  }

  // ==========================================================================
  // OTHER WORKSPACES
  // ==========================================================================

  Future<void> _openReceptionQueue() async {
    await _openPage(
      const DoctorReceptionQueuePage(),
    );
  }

  Future<void> _openQrScanner() async {
    await _openPage(
      const DoctorQrScannerPage(),
    );
  }

  Future<void> _openMessages() async {
    final doctorContext = _doctorContext;

    if (doctorContext == null) {
      _showMessage(
        'Doctor context is unavailable.',
      );

      return;
    }

    await _openPage(
      DoctorMessagesPage(
        doctorId: doctorContext.doctorId,
        doctorAuthUserId: doctorContext.authUserId,
        doctorName: doctorContext.doctorName,
      ),
    );
  }

  Future<void> _openMedicalRecords() async {
    await _openPage(
      const DoctorMedicalRecordsPage(),
    );
  }

  Future<void> _openPatientRecords() async {
    await _openPage(
      const PatientRecordsPage(),
    );
  }

  Future<void> _openTelehealth() async {
    await _openPage(
      const DoctorTelehealthPage(),
    );
  }

  Future<void> _openSettings() async {
    await _openPage(
      const SettingsPage(showSignOut: true, showStaffWorkspaces: true),
    );
  }

  Future<void> _openAnalytics() async {
    final doctorContext = _doctorContext;

    if (doctorContext == null) {
      _showMessage(
        'Doctor context is unavailable.',
      );

      return;
    }

    await _openPage(
      DoctorAnalyticsPage(
        doctorId: doctorContext.doctorId,
        doctorName: doctorContext.doctorName,
      ),
    );
  }

  Future<void> _openSpecialistReferral() async {
    final doctorContext = _doctorContext;

    if (doctorContext == null) {
      _showMessage(
        'Doctor context is unavailable.',
      );

      return;
    }

    await _openPage(
      DoctorSpecialistReferralPage(
        doctorId: doctorContext.doctorId,
      ),
    );
  }

  // ==========================================================================
  // SWITCH MODE
  // ==========================================================================

  Future<void> _switchMode() async {
    if (!_canSwitchMode) {
      _showMessage(
        'This doctor account does not have '
        'a linked patient mode.',
      );

      return;
    }

    /*
     * Doctor + Patient accounts reach this dashboard
     * from the existing RoleChoicePage.
     *
     * Therefore pop back instead of importing
     * RoleChoicePage here and creating a circular import.
     */
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();

      return;
    }

    _showMessage(
      'The mode-selection screen is not available '
      'from this route.',
    );
  }

  // ==========================================================================
  // SIGN OUT
  // ==========================================================================

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

      Navigator.of(context).popUntil(
        (
          route,
        ) =>
            route.isFirst,
      );
    } on AuthException catch (error) {
      if (!mounted) {
        return;
      }

      _showMessage(
        'Sign out failed: ${error.message}',
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      _showMessage(
        'Sign out failed. $error',
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSigningOut = false;
        });
      }
    }
  }

  // ==========================================================================
  // DISPLAY HELPERS
  // ==========================================================================

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

  String _initials(
    String name,
  ) {
    final cleaned = name
        .replaceFirst(
          RegExp(
            r'^Dr\.?\s+',
            caseSensitive: false,
          ),
          '',
        )
        .trim();

    final parts = cleaned
        .split(
          RegExp(
            r'\s+',
          ),
        )
        .where(
          (
            value,
          ) =>
              value.isNotEmpty,
        )
        .toList();

    if (parts.isEmpty) {
      return '?';
    }

    return parts
        .take(
          2,
        )
        .map(
          (
            value,
          ) =>
              value[0].toUpperCase(),
        )
        .join();
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
    final isDesktop = ResponsiveLayout.isDesktop(
      context,
    );

    final isTablet = ResponsiveLayout.isTablet(
      context,
    );

    return Scaffold(
      backgroundColor: context.cBgPrimary,
      appBar: _buildAppBar(
        isDesktop: isDesktop,
        hasSideNavigation: isDesktop || isTablet,
      ),
      body: _isLoading
          ? Center(
              child: CircularProgressIndicator(
                color: CorviaColors.accent,
              ),
            )
          : _errorMessage != null || _pages.isEmpty
              ? _buildErrorState()
              : Row(
                  children: [
                    if (isDesktop || isTablet)
                      _buildSideNavigation(
                        isDesktop: isDesktop,
                      ),
                    Expanded(
                      child: IndexedStack(
                        index: _currentIndex,
                        children: _pages,
                      ),
                    ),
                  ],
                ),
      bottomNavigationBar: !isDesktop &&
              !isTablet &&
              !_isLoading &&
              _errorMessage == null &&
              _pages.isNotEmpty
          ? _buildBottomNavigation()
          : null,
    );
  }

  PreferredSizeWidget _buildAppBar({
    required bool isDesktop,
    required bool hasSideNavigation,
  }) {
    final signOutButton = IconButton(
      tooltip: 'Sign Out',
      onPressed: _isSigningOut ? null : _signOut,
      icon: _isSigningOut
          ? const SizedBox(
              width: 19,
              height: 19,
              child: CircularProgressIndicator(
                strokeWidth: 2,
              ),
            )
          : const Icon(
              Icons.logout_rounded,
            ),
    );

    final qrButton = IconButton(
      tooltip: 'Scan Patient QR',
      onPressed: _doctorContext == null ? null : _openQrScanner,
      icon: const Icon(
        Icons.qr_code_scanner,
      ),
    );

    // The side navigation already lists messages, queue, forms, analytics,
    // referral, settings and mode switching, so only show what it lacks.
    if (hasSideNavigation) {
      return AppBar(
        automaticallyImplyLeading: false,
        title: Text(
          isDesktop ? 'Corvia Doctor Portal' : 'Doctor Portal',
          style: const TextStyle(
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          qrButton,
          signOutButton,
          const SizedBox(
            width: 8,
          ),
        ],
      );
    }

    return AppBar(
      automaticallyImplyLeading: false,
      title: Text(
        isDesktop ? 'Corvia Doctor Portal' : 'Doctor Portal',
        style: const TextStyle(
          fontWeight: FontWeight.bold,
        ),
      ),
      actions: [
        IconButton(
          tooltip: 'Patient Messages',
          onPressed: _doctorContext == null ? null : _openMessages,
          icon: const Icon(
            Icons.mark_chat_unread_outlined,
          ),
        ),
        IconButton(
          tooltip: 'Reception Queue',
          onPressed: _doctorContext == null ? null : _openReceptionQueue,
          icon: const Icon(
            Icons.event_seat_rounded,
          ),
        ),
        qrButton,
        if (_canSwitchMode)
          IconButton(
            tooltip: 'Switch Mode',
            onPressed: _switchMode,
            icon: const Icon(
              Icons.swap_horiz_rounded,
            ),
          ),
        PopupMenuButton<String>(
          tooltip: 'More',
          icon: const Icon(Icons.more_vert),
          onSelected: (value) {
            switch (value) {
              case 'forms':
                _openPatientForms();
                break;
              case 'analytics':
                _openAnalytics();
                break;
              case 'referral':
                _openSpecialistReferral();
                break;
              case 'settings':
                _openSettings();
                break;
              case 'signout':
                _signOut();
                break;
            }
          },
          itemBuilder: (context) {
            final hasContext = _doctorContext != null;
            return [
              PopupMenuItem(
                value: 'forms',
                enabled: hasContext,
                child: const Row(
                  children: [
                    Icon(Icons.description_outlined),
                    SizedBox(width: 12),
                    Text('Patient Forms'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'analytics',
                enabled: hasContext,
                child: const Row(
                  children: [
                    Icon(Icons.analytics),
                    SizedBox(width: 12),
                    Text('Analytics'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'referral',
                enabled: hasContext,
                child: const Row(
                  children: [
                    Icon(Icons.health_and_safety_outlined),
                    SizedBox(width: 12),
                    Text('Refer to Specialist'),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              PopupMenuItem(
                value: 'settings',
                child: const Row(
                  children: [
                    Icon(Icons.settings_outlined),
                    SizedBox(width: 12),
                    Text('Settings'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'signout',
                enabled: !_isSigningOut,
                child: const Row(
                  children: [
                    Icon(Icons.logout_rounded),
                    SizedBox(width: 12),
                    Text('Sign Out'),
                  ],
                ),
              ),
            ];
          },
        ),
      ],
    );
  }

  // ==========================================================================
  // SIDE NAVIGATION
  // ==========================================================================

  Widget _buildSideNavigation({
    required bool isDesktop,
  }) {
    return Material(
      color: context.cBgSecondary,
      child: SizedBox(
        width: isDesktop ? 280 : 215,
        child: Column(
          children: [
            _buildDoctorIdentityCard(),
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  _buildNavItem(
                    icon: Icons.dashboard_outlined,
                    label: 'Dashboard',
                    index: 0,
                  ),
                  _buildNavItem(
                    icon: Icons.calendar_month_outlined,
                    label: 'Appointments',
                    index: 1,
                  ),
                  _buildNavItem(
                    icon: Icons.people_outline,
                    label: 'Patients',
                    index: 2,
                  ),
                  _buildNavItem(
                    icon: Icons.medication_outlined,
                    label: 'Prescriptions',
                    index: 3,
                  ),
                  _buildNavItem(
                    icon: Icons.biotech_outlined,
                    label: 'Labs',
                    index: 4,
                  ),
                  Divider(
                    color: context.cDivider,
                  ),
                  _buildActionNavItem(
                    icon: Icons.mark_chat_unread_outlined,
                    label: 'Patient Messages',
                    onTap: _openMessages,
                  ),
                  _buildActionNavItem(
                    icon: Icons.event_seat_outlined,
                    label: 'Reception Queue',
                    onTap: _openReceptionQueue,
                  ),
                  _buildActionNavItem(
                    icon: Icons.folder_shared,
                    label: 'Patient Records',
                    onTap: _openPatientRecords,
                  ),
                  //Disabled pending review same as patient records
                  /* _buildActionNavItem(
                    icon: Icons.medical_information,
                    label: 'Medical Records',
                    onTap: _openMedicalRecords,
                  ), */
                  _buildActionNavItem(
                    icon: Icons.description_outlined,
                    label: 'Patient Forms',
                    onTap: _openPatientForms,
                  ),
                  //Telehealth temp disabled due to  missing backend
                  /* _buildActionNavItem(
                    icon: Icons.video_call_outlined,
                    label: 'Telehealth',
                    onTap: _openTelehealth,
                  ), */
                  _buildActionNavItem(
                    icon: Icons.analytics,
                    label: 'Analytics',
                    onTap: _openAnalytics,
                  ),
                  _buildActionNavItem(
                    icon: Icons.health_and_safety_outlined,
                    label: 'Specialist Referral',
                    onTap: _openSpecialistReferral,
                  ),
                  _buildActionNavItem(
                    icon: Icons.settings_outlined,
                    label: 'Settings',
                    onTap: _openSettings,
                  ),
                  if (_canSwitchMode)
                    _buildActionNavItem(
                      icon: Icons.swap_horiz_rounded,
                      label: 'Switch Mode',
                      onTap: _switchMode,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDoctorIdentityCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(
        20,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: context.isDarkTheme
              ? const [
                  Color(
                    0xFF172536,
                  ),
                  Color(
                    0xFF22364A,
                  ),
                ]
              : const [
                  Color(
                    0xFFE8F1F8,
                  ),
                  Color(
                    0xFFDCE8F0,
                  ),
                ],
        ),
        border: Border(
          bottom: BorderSide(
            color: context.cDivider,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 30,
            backgroundColor: CorviaColors.accent,
            child: Text(
              _initials(
                _doctorName,
              ),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(
            height: 12,
          ),
          Text(
            _doctorName,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: context.cTextPrimary,
              fontSize: 17,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(
            height: 3,
          ),
          Text(
            _doctorSpecialization,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: context.cTextSecondary,
              fontSize: 13,
            ),
          ),
          const SizedBox(
            height: 3,
          ),
          Text(
            _doctorLocation,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: context.cTextMuted,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavItem({
    required IconData icon,
    required String label,
    required int index,
  }) {
    final selected = index == _currentIndex;

    return ListTile(
      selected: selected,
      selectedTileColor: CorviaColors.accent.withValues(
        alpha: 0.10,
      ),
      leading: Icon(
        icon,
        color: selected ? context.cAccentReadable : context.cTextSecondary,
      ),
      title: Text(
        label,
        style: TextStyle(
          color: selected ? context.cAccentReadable : context.cTextPrimary,
          fontWeight: selected ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      onTap: () {
        _selectTab(
          index,
        );
      },
    );
  }

  Widget _buildActionNavItem({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Icon(
        icon,
        color: context.cTextSecondary,
      ),
      title: Text(
        label,
        style: TextStyle(
          color: context.cTextPrimary,
        ),
      ),
      trailing: Icon(
        Icons.chevron_right,
        color: context.cTextMuted,
      ),
      onTap: onTap,
    );
  }

  // ==========================================================================
  // BOTTOM NAVIGATION
  // ==========================================================================

  Widget _buildBottomNavigation() {
    return DoctorBottomNavigation(
      selectedIndex: _currentIndex,
      onDestinationSelected: _selectTab,
    );
  }

  // ==========================================================================
  // ERROR STATE
  // ==========================================================================

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
                  Icons.error_outline,
                  size: 58,
                  color: CorviaColors.danger,
                ),
                const SizedBox(
                  height: 15,
                ),
                Text(
                  'Doctor Dashboard could not load',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: context.cTextPrimary,
                    fontSize: 21,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(
                  height: 11,
                ),
                SelectableText(
                  _errorMessage ?? 'Unknown doctor dashboard error.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: context.cTextSecondary,
                  ),
                ),
                const SizedBox(
                  height: 20,
                ),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _initializeDoctor,
                    icon: const Icon(
                      Icons.refresh,
                    ),
                    label: const Text(
                      'Try Again',
                    ),
                  ),
                ),
                const SizedBox(
                  height: 9,
                ),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _isSigningOut ? null : _signOut,
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
// DASHBOARD HOME
// =============================================================================

class DoctorDashboardHome extends StatefulWidget {
  const DoctorDashboardHome({
    super.key,
    required this.doctorName,
    required this.doctorSpecialization,
    required this.doctorLocation,
    required this.currentDoctorId,
    required this.currentHospitalId,
    required this.onAppointments,
    required this.onPatients,
    required this.onPrescriptions,
    required this.onLabs,
    required this.onRecords,
    required this.onForms,
    required this.onMessages,
  });

  final String doctorName;
  final String doctorSpecialization;
  final String doctorLocation;

  final String currentDoctorId;
  final String? currentHospitalId;

  final VoidCallback onAppointments;
  final VoidCallback onPatients;
  final VoidCallback onPrescriptions;
  final VoidCallback onLabs;
  final VoidCallback onRecords;
  final VoidCallback onForms;
  final VoidCallback onMessages;

  @override
  State<DoctorDashboardHome> createState() {
    return _DoctorDashboardHomeState();
  }
}

class _DoctorDashboardHomeState extends State<DoctorDashboardHome> {
  final SupabaseClient _supabase = Supabase.instance.client;

  final DoctorClinicalService _clinicalService = DoctorClinicalService();

  bool _loading = true;

  int _appointmentsToday = 0;
  int _totalPatients = 0;
  int _activePrescriptions = 0;
  int _outstandingLabs = 0;
  int _completedVisits = 0;

  List<Map<String, dynamic>> _todaySchedule = [];

  String? _error;

  @override
  void initState() {
    super.initState();

    _load();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final appointments = await _safeDoctorRows(
        'appointments',
      );

      final prescriptions = await _safeDoctorRows(
        'prescriptions',
      );

      final labs = await _safeDoctorRows(
        'lab_results',
      );

      List<DoctorClinicalPatient> clinicalPatients = [];

      try {
        final context = await _clinicalService.currentContext();

        clinicalPatients = await _clinicalService.loadDoctorPatients(
          context,
        );
      } catch (error) {
        debugPrint(
          'Doctor patient summary load failed: $error',
        );
      }

      final patientNames = <String, String>{
        for (final patient in clinicalPatients) patient.id: patient.name,
      };

      final now = DateTime.now();

      final todayAppointments = appointments.where(
        (
          appointment,
        ) {
          final date = _appointmentDate(
            appointment,
          );

          if (date == null) {
            return false;
          }

          return date.year == now.year &&
              date.month == now.month &&
              date.day == now.day;
        },
      ).toList();

      todayAppointments.sort(
        (
          first,
          second,
        ) {
          final firstDate = _appointmentDate(
                first,
              ) ??
              DateTime(
                2100,
              );

          final secondDate = _appointmentDate(
                second,
              ) ??
              DateTime(
                2100,
              );

          return firstDate.compareTo(
            secondDate,
          );
        },
      );

      final schedule = todayAppointments
          .take(
        8,
      )
          .map(
        (
          appointment,
        ) {
          final patientId = appointment['patient_id']?.toString();

          return {
            ...appointment,
            'patient_name': patientId == null
                ? 'Patient'
                : patientNames[patientId] ?? 'Patient',
          };
        },
      ).toList();

      if (!mounted) {
        return;
      }

      setState(() {
        _appointmentsToday = todayAppointments.length;

        _totalPatients = clinicalPatients.length;

        _activePrescriptions = prescriptions.where(
          (
            row,
          ) {
            final status = _normalise(
              row['status'],
            );

            return {
              'active',
              'pending',
              'ready',
              'preparing',
              'verified',
            }.contains(
              status,
            );
          },
        ).length;

        _outstandingLabs = labs
            .where(
              (
                row,
              ) =>
                  _labBucket(
                    row['status'],
                  ) !=
                  'completed',
            )
            .length;

        _completedVisits = appointments
            .where(
              (
                row,
              ) =>
                  _normalise(
                    row['status'],
                  ) ==
                  'completed',
            )
            .length;

        _todaySchedule = schedule;

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

  Future<List<Map<String, dynamic>>> _safeDoctorRows(
    String table,
  ) async {
    try {
      final response = await _supabase
          .from(table)
          .select()
          .eq(
            'doctor_id',
            widget.currentDoctorId,
          )
          .limit(
            1000,
          );

      return _mapRows(
        response,
      );
    } catch (error) {
      debugPrint(
        'Doctor dashboard $table lookup failed: $error',
      );

      return [];
    }
  }

  @override
  Widget build(
    BuildContext context,
  ) {
    if (_loading) {
      return Center(
        child: CircularProgressIndicator(
          color: CorviaColors.accent,
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(
          18,
        ),
        children: [
          _buildWelcomeBanner(),
          const SizedBox(
            height: 18,
          ),
          if (_error != null) ...[
            _buildWarningBanner(
              _error!,
            ),
            const SizedBox(
              height: 14,
            ),
          ],
          _buildStatistics(),
          const SizedBox(
            height: 24,
          ),
          Text(
            'Quick Actions',
            style: TextStyle(
              color: context.cTextPrimary,
              fontSize: 19,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(
            height: 12,
          ),
          _buildQuickActions(),
          const SizedBox(
            height: 24,
          ),
          _buildTodaySchedule(),
          const SizedBox(
            height: 30,
          ),
        ],
      ),
    );
  }

  Widget _buildWelcomeBanner() {
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
            radius: 30,
            backgroundColor: Colors.white,
            child: Icon(
              Icons.medical_services,
              size: 31,
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
                  'Welcome back',
                  style: TextStyle(
                    color: Colors.white70,
                  ),
                ),
                const SizedBox(
                  height: 2,
                ),
                Text(
                  widget.doctorName,
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
                  '${widget.doctorSpecialization} • '
                  '${widget.doctorLocation}',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const Icon(
            Icons.verified,
            color: Colors.white,
          ),
        ],
      ),
    );
  }

  // ==========================================================================
  // STATS
  // ==========================================================================

  Widget _buildStatistics() {
    final items = [
      _DoctorStatData(
        title: 'Appointments Today',
        value: '$_appointmentsToday',
        icon: Icons.calendar_month_outlined,
        color: Colors.blue,
        onTap: widget.onAppointments,
      ),
      _DoctorStatData(
        title: 'My Patients',
        value: '$_totalPatients',
        icon: Icons.people_outline,
        color: Colors.deepPurple,
        onTap: widget.onPatients,
      ),
      _DoctorStatData(
        title: 'Active Prescriptions',
        value: '$_activePrescriptions',
        icon: Icons.medication_outlined,
        color: Colors.green,
        onTap: widget.onPrescriptions,
      ),
      _DoctorStatData(
        title: 'Outstanding Labs',
        value: '$_outstandingLabs',
        icon: Icons.biotech_outlined,
        color: Colors.orange,
        onTap: widget.onLabs,
      ),
      _DoctorStatData(
        title: 'Completed Visits',
        value: '$_completedVisits',
        icon: Icons.check_circle_outline,
        color: Colors.teal,
        onTap: widget.onAppointments,
      ),
    ];

    return LayoutBuilder(
      builder: (
        context,
        constraints,
      ) {
        int columns;

        if (constraints.maxWidth >= 1000) {
          columns = 5;
        } else if (constraints.maxWidth >= 650) {
          columns = 3;
        } else {
          columns = 2;
        }

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: items.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            mainAxisExtent: 145,
          ),
          itemBuilder: (
            context,
            index,
          ) {
            final item = items[index];

            return Material(
              color: context.cBgSecondary,
              borderRadius: BorderRadius.circular(
                17,
              ),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: item.onTap,
                child: Container(
                  padding: const EdgeInsets.all(
                    15,
                  ),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: item.color.withValues(
                        alpha: 0.25,
                      ),
                    ),
                    borderRadius: BorderRadius.circular(
                      17,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        item.icon,
                        color: item.color,
                      ),
                      const Spacer(),
                      Text(
                        item.value,
                        style: TextStyle(
                          color: context.cTextPrimary,
                          fontSize: 27,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(
                        height: 2,
                      ),
                      Text(
                        item.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: context.cTextSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ==========================================================================
  // QUICK ACTIONS
  // ==========================================================================

  Widget _buildQuickActions() {
    final actions = [
      _DoctorActionData(
        title: 'Appointments',
        icon: Icons.calendar_month_outlined,
        onTap: widget.onAppointments,
      ),
      _DoctorActionData(
        title: 'Patients',
        icon: Icons.people_outline,
        onTap: widget.onPatients,
      ),
      _DoctorActionData(
        title: 'Prescriptions',
        icon: Icons.medication_outlined,
        onTap: widget.onPrescriptions,
      ),
      _DoctorActionData(
        title: 'Lab Requests',
        icon: Icons.biotech_outlined,
        onTap: widget.onLabs,
      ),
      _DoctorActionData(
        title: 'Messages',
        icon: Icons.mark_chat_unread_outlined,
        onTap: widget.onMessages,
      ),
      _DoctorActionData(
        title: 'Patient Records',
        icon: Icons.folder_shared,
        onTap: widget.onRecords,
      ),
      _DoctorActionData(
        title: 'Patient Forms',
        icon: Icons.description_outlined,
        onTap: widget.onForms,
      ),
    ];

    return LayoutBuilder(
      builder: (
        context,
        constraints,
      ) {
        int columns;

        if (constraints.maxWidth >= 900) {
          columns = 6;
        } else if (constraints.maxWidth >= 550) {
          columns = 3;
        } else {
          columns = 2;
        }

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: actions.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            mainAxisExtent: 120,
          ),
          itemBuilder: (
            context,
            index,
          ) {
            final action = actions[index];

            return Material(
              color: context.cBgSecondary,
              borderRadius: BorderRadius.circular(
                16,
              ),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: action.onTap,
                child: Container(
                  padding: const EdgeInsets.all(
                    12,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(
                      16,
                    ),
                    border: Border.all(
                      color: context.cDivider,
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        action.icon,
                        color: context.cAccentReadable,
                        size: 29,
                      ),
                      const SizedBox(
                        height: 9,
                      ),
                      Text(
                        action.title,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: context.cTextPrimary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ==========================================================================
  // TODAY SCHEDULE
  // ==========================================================================

  Widget _buildTodaySchedule() {
    return Container(
      width: double.infinity,
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
            children: [
              Expanded(
                child: Text(
                  'Today’s Schedule',
                  style: TextStyle(
                    color: context.cTextPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              TextButton(
                onPressed: widget.onAppointments,
                child: const Text(
                  'View All',
                ),
              ),
            ],
          ),
          const SizedBox(
            height: 6,
          ),
          if (_todaySchedule.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(
                vertical: 20,
              ),
              child: Center(
                child: Column(
                  children: [
                    Icon(
                      Icons.event_available_outlined,
                      size: 42,
                      color: context.cTextMuted,
                    ),
                    const SizedBox(
                      height: 8,
                    ),
                    Text(
                      'No appointments scheduled for today.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: context.cTextSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            ..._todaySchedule.map(
              (
                appointment,
              ) {
                final date = _appointmentDate(
                  appointment,
                );

                final status = _normalise(
                  appointment['status'],
                );

                final reason = _firstAvailableText(
                  [
                    appointment['reason'],
                    appointment['appointment_reason'],
                    appointment['title'],
                  ],
                  fallback: 'No reason supplied',
                );

                return Container(
                  margin: const EdgeInsets.only(
                    bottom: 9,
                  ),
                  padding: const EdgeInsets.all(
                    12,
                  ),
                  decoration: BoxDecoration(
                    color: context.cBgPrimary,
                    borderRadius: BorderRadius.circular(
                      13,
                    ),
                    border: Border.all(
                      color: context.cDivider,
                    ),
                  ),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 58,
                        child: Text(
                          date == null
                              ? '--:--'
                              : DateFormat(
                                  'HH:mm',
                                ).format(
                                  date,
                                ),
                          style: TextStyle(
                            color: context.cAccentReadable,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(
                        width: 8,
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              appointment['patient_name']?.toString() ??
                                  'Patient',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: context.cTextPrimary,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(
                              height: 2,
                            ),
                            Text(
                              reason,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: context.cTextSecondary,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      _StatusChip(
                        status: status,
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildWarningBanner(
    String message,
  ) {
    return Container(
      padding: const EdgeInsets.all(
        13,
      ),
      decoration: BoxDecoration(
        color: CorviaColors.warning.withValues(
          alpha: 0.10,
        ),
        borderRadius: BorderRadius.circular(
          13,
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.warning_amber,
            color: CorviaColors.warning,
          ),
          const SizedBox(
            width: 9,
          ),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: context.cTextPrimary,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// LAB REQUEST PAGE
// =============================================================================

class DoctorLabRequestPage extends StatefulWidget {
  const DoctorLabRequestPage({
    super.key,
    required this.doctorId,
  });

  final String doctorId;

  @override
  State<DoctorLabRequestPage> createState() {
    return _DoctorLabRequestPageState();
  }
}

class _DoctorLabRequestPageState extends State<DoctorLabRequestPage>
    with SingleTickerProviderStateMixin {
  final DoctorClinicalService _clinicalService = DoctorClinicalService();

  final TextEditingController _searchController = TextEditingController();

  late final TabController _tabController;

  List<Map<String, dynamic>> _orders = [];

  final Set<String> _releasingOrders = {};
  String? _loadError;

  bool _loading = true;

  String _searchQuery = '';

  @override
  void initState() {
    super.initState();

    _tabController = TabController(
      length: 5,
      vsync: this,
    );

    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();

    super.dispose();
  }

  // ==========================================================================
  // LOAD LABS
  // ==========================================================================

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _loadError = null;
      });
    }

    try {
      final response = await _clinicalService.loadDoctorLabOrders();

      final rows = _mapRows(
        response,
      );

      Map<String, String> patientNames = {};

      try {
        final context = await _clinicalService.currentContext();

        final patients = await _clinicalService.loadDoctorPatients(
          context,
        );

        patientNames = {
          for (final patient in patients) patient.id: patient.name,
        };
      } catch (error) {
        debugPrint(
          'Lab patient-name lookup failed: $error',
        );
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _orders = rows.map(
          (
            row,
          ) {
            final patientId = row['patient_id']?.toString();

            return {
              ...row,
              'patient_name': patientId == null
                  ? 'Patient'
                  : row['patient_name'] ??
                      patientNames[patientId] ??
                      'Patient $patientId',
              'bucket': row['result_release_status'] == 'awaiting_doctor_review'
                  ? 'review'
                  : _labBucket(row['status']),
            };
          },
        ).toList();

        _loading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _loading = false;
        _orders = [];
        _loadError = 'Lab orders could not load. ${_cleanError(error)}';
      });

      _showMessage(
        'Lab orders could not load. '
        '${_cleanError(error)}',
      );
    }
  }

  // ==========================================================================
  // CREATE LAB REQUEST
  // ==========================================================================

  Future<void> _openNewRequest() async {
    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.cBgSecondary,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(
            22,
          ),
        ),
      ),
      builder: (_) {
        return DoctorClinicalLabRequestSheet(
          doctorId: widget.doctorId,
        );
      },
    );

    if (created == true && mounted) {
      await _load();
    }
  }

  Future<void> _releaseVerifiedResult(Map<String, dynamic> order) async {
    final id = order['id']?.toString() ?? '';
    if (id.isEmpty || _releasingOrders.contains(id)) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Release result to patient?'),
        content: Text(
            'Release the verified ${order['test_name']} result for ${order['patient_name']}? The patient will be able to view it.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Release to patient')),
        ],
      ),
    );
    if (confirmed != true || !mounted || _releasingOrders.contains(id)) return;
    setState(() => _releasingOrders.add(id));
    try {
      await _clinicalService.releaseVerifiedLabResult(id);
      if (!mounted) return;
      _showMessage('Verified result released to the patient.');
      await _load();
    } catch (error) {
      _showMessage('Could not release result. ${_cleanError(error)}');
    } finally {
      if (mounted) setState(() => _releasingOrders.remove(id));
    }
  }

  // ==========================================================================
  // UPDATE STATUS
  // ==========================================================================

  List<Map<String, dynamic>> _filteredOrders(
    String bucket,
  ) {
    Iterable<Map<String, dynamic>> values = _orders;

    if (bucket != 'all') {
      values = values.where(
        (
          order,
        ) =>
            order['bucket'] == bucket,
      );
    }

    if (_searchQuery.isNotEmpty) {
      values = values.where(
        (
          order,
        ) {
          final testName = order['test_name']?.toString().toLowerCase() ?? '';

          final patientName =
              order['patient_name']?.toString().toLowerCase() ?? '';

          return testName.contains(
                _searchQuery,
              ) ||
              patientName.contains(
                _searchQuery,
              );
        },
      );
    }

    return values.toList();
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
        ),
      );
  }

  // ==========================================================================
  // BUILD LAB PAGE
  // ==========================================================================

  @override
  Widget build(
    BuildContext context,
  ) {
    final pendingCount = _orders
        .where(
          (
            order,
          ) =>
              order['bucket'] == 'pending',
        )
        .length;

    final inProgressCount = _orders
        .where(
          (
            order,
          ) =>
              order['bucket'] == 'in_progress',
        )
        .length;

    final completedCount = _orders
        .where(
          (
            order,
          ) =>
              order['bucket'] == 'completed',
        )
        .length;
    final reviewCount =
        _orders.where((order) => order['bucket'] == 'review').length;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            16,
            16,
            16,
            8,
          ),
          child: LayoutBuilder(
            builder: (
              context,
              constraints,
            ) {
              if (constraints.maxWidth < 520) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Lab Orders',
                      style: TextStyle(
                        color: context.cTextPrimary,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(
                      height: 10,
                    ),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _openNewRequest,
                        icon: const Icon(
                          Icons.add,
                        ),
                        label: const Text(
                          'New Request',
                        ),
                      ),
                    ),
                  ],
                );
              }

              return Row(
                children: [
                  Expanded(
                    child: Text(
                      'Lab Orders',
                      style: TextStyle(
                        color: context.cTextPrimary,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: _openNewRequest,
                    icon: const Icon(
                      Icons.add,
                    ),
                    label: const Text(
                      'New Request',
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: 16,
          ),
          child: TextField(
            controller: _searchController,
            onChanged: (
              value,
            ) {
              setState(() {
                _searchQuery = value.trim().toLowerCase();
              });
            },
            decoration: const InputDecoration(
              hintText: 'Search patient or test',
              prefixIcon: Icon(
                Icons.search,
              ),
              border: OutlineInputBorder(),
            ),
          ),
        ),
        const SizedBox(
          height: 12,
        ),
        TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: [
            Tab(
              text: 'All (${_orders.length})',
            ),
            Tab(text: 'Awaiting my release ($reviewCount)'),
            Tab(
              text: 'Awaiting collection ($pendingCount)',
            ),
            Tab(
              text: 'In Progress ($inProgressCount)',
            ),
            Tab(
              text: 'Completed ($completedCount)',
            ),
          ],
        ),
        Expanded(
          child: _loading
              ? const Center(
                  child: CircularProgressIndicator(),
                )
              : _loadError != null
                  ? Center(
                      child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Text(_loadError!, textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        FilledButton(
                            onPressed: _load, child: const Text('Retry')),
                      ]),
                    ))
                  : TabBarView(
                      controller: _tabController,
                      children: [
                        _buildLabList(
                          'all',
                        ),
                        _buildLabList('review'),
                        _buildLabList(
                          'pending',
                        ),
                        _buildLabList(
                          'in_progress',
                        ),
                        _buildLabList(
                          'completed',
                        ),
                      ],
                    ),
        ),
      ],
    );
  }

  Widget _buildLabList(
    String bucket,
  ) {
    final orders = _filteredOrders(
      bucket,
    );

    if (orders.isEmpty) {
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            const SizedBox(
              height: 120,
            ),
            Icon(
              Icons.biotech_outlined,
              size: 55,
              color: context.cTextMuted,
            ),
            const SizedBox(
              height: 12,
            ),
            Text(
              'No lab orders found',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: context.cTextPrimary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(
          16,
        ),
        itemCount: orders.length,
        itemBuilder: (
          context,
          index,
        ) {
          return _buildLabCard(
            orders[index],
          );
        },
      ),
    );
  }

  Widget _buildLabCard(
    Map<String, dynamic> order,
  ) {
    final bucket = order['bucket']?.toString() ?? _labBucket(order['status']);

    final status = _normalise(
      bucket == 'review' ? 'awaiting_doctor_review' : order['status'],
    );

    final date = _parseDate(
      order['created_at'],
    );

    final result = order['result']?.toString().trim() ?? '';

    final color = bucket == 'completed'
        ? CorviaColors.success
        : bucket == 'in_progress'
            ? Colors.blue
            : CorviaColors.warning;

    return Container(
      margin: const EdgeInsets.only(
        bottom: 11,
      ),
      padding: const EdgeInsets.all(
        15,
      ),
      decoration: BoxDecoration(
        color: context.cBgSecondary,
        borderRadius: BorderRadius.circular(
          17,
        ),
        border: Border.all(
          color: context.cDivider,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 43,
                height: 43,
                decoration: BoxDecoration(
                  color: color.withValues(
                    alpha: 0.12,
                  ),
                  borderRadius: BorderRadius.circular(
                    12,
                  ),
                ),
                child: Icon(
                  Icons.biotech,
                  color: color,
                ),
              ),
              const SizedBox(
                width: 11,
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      order['test_name']?.toString() ?? 'Lab Test',
                      style: TextStyle(
                        color: context.cTextPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      order['patient_name']?.toString() ?? 'Patient',
                      style: TextStyle(
                        color: context.cTextSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              _StatusChip(
                status: status,
              ),
            ],
          ),
          const SizedBox(
            height: 10,
          ),
          Text(
            date == null
                ? 'Requested date unavailable'
                : 'Requested '
                    '${DateFormat('d MMM yyyy, HH:mm').format(date)}',
            style: TextStyle(
              color: context.cTextSecondary,
              fontSize: 12,
            ),
          ),
          if (result.isNotEmpty) ...[
            const SizedBox(
              height: 10,
            ),
            Text(
              'Result',
              style: TextStyle(
                color: context.cTextSecondary,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(
              height: 3,
            ),
            SelectableText(
              result,
              style: TextStyle(
                color: context.cTextPrimary,
              ),
            ),
          ],
          if (order['doctor_release_managed'] == true) ...[
            const SizedBox(height: 10),
            Text(
              order['requires_doctor_review'] == true
                  ? 'Patient release: ordering doctor review required'
                  : 'Patient release: automatic after verification',
              style: TextStyle(color: context.cTextSecondary, fontSize: 12),
            ),
          ],
          if (bucket == 'review') ...[
            const SizedBox(height: 12),
            const Text('Lab verified · Awaiting your release to the patient'),
            if ((order['file_url']?.toString() ?? '').isNotEmpty) ...[
              const SizedBox(height: 8),
              SelectableText('Result document: ${order['file_url']}'),
            ],
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _releasingOrders.contains(order['id']?.toString())
                  ? null
                  : () => _releaseVerifiedResult(order),
              icon: const Icon(Icons.send_outlined),
              label: Text(_releasingOrders.contains(order['id']?.toString())
                  ? 'Releasing...'
                  : 'Release to patient'),
            ),
          ],
          if (bucket != 'completed') ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  color: context.cTextSecondary,
                  size: 17,
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    bucket == 'review'
                        ? 'This verified result is withheld from the patient until you release it.'
                        : 'The nursing and laboratory teams collect and process the specimen. Every new result must be verified before patient release.',
                    style: TextStyle(
                      color: context.cTextSecondary,
                      fontSize: 12,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// =============================================================================
// PATIENT FORMS SELECTOR
//
// This replaces the removed openDoctorPatientForms() global helper.
// =============================================================================

class DoctorPatientFormSelectorPage extends StatefulWidget {
  const DoctorPatientFormSelectorPage({
    super.key,
    required this.doctorId,
    this.hospitalId,
  });

  final String doctorId;
  final String? hospitalId;

  @override
  State<DoctorPatientFormSelectorPage> createState() {
    return _DoctorPatientFormSelectorPageState();
  }
}

class _DoctorPatientFormSelectorPageState
    extends State<DoctorPatientFormSelectorPage> {
  final DoctorClinicalService _clinicalService = DoctorClinicalService();

  final SupabaseClient _supabase = Supabase.instance.client;

  final TextEditingController _searchController = TextEditingController();

  bool _loading = true;
  bool _opening = false;

  String _searchQuery = '';

  String? _errorMessage;
  String? _openingPatientId;

  List<DoctorClinicalPatient> _patients = [];

  @override
  void initState() {
    super.initState();

    _loadPatients();
  }

  @override
  void dispose() {
    _searchController.dispose();

    super.dispose();
  }

  // ==========================================================================
  // LOAD PATIENTS
  // ==========================================================================

  Future<void> _loadPatients() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _errorMessage = null;
      });
    }

    try {
      final doctorContext = await _clinicalService.currentContext();

      if (doctorContext.doctorId != widget.doctorId) {
        throw Exception(
          'The signed-in doctor does not match '
          'this clinical forms workspace.',
        );
      }

      final patients = await _clinicalService.loadDoctorPatients(
        doctorContext,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _patients = patients;

        _loading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _patients = [];

        _loading = false;

        _errorMessage = _cleanError(
          error,
        );
      });
    }
  }

  List<DoctorClinicalPatient> get _filteredPatients {
    if (_searchQuery.isEmpty) {
      return _patients;
    }

    return _patients.where(
      (
        patient,
      ) {
        return patient.name.toLowerCase().contains(
                  _searchQuery,
                ) ||
            patient.id.toLowerCase().contains(
                  _searchQuery,
                );
      },
    ).toList();
  }

  // ==========================================================================
  // OPEN FORMS
  // ==========================================================================

  Future<void> _openPatient(
    DoctorClinicalPatient patient,
  ) async {
    if (_opening) {
      return;
    }

    setState(() {
      _opening = true;

      _openingPatientId = patient.id;
    });

    try {
      final admissionId = await _resolveActiveAdmission(
        patientId: patient.id,
      );

      if (!mounted) {
        return;
      }

      await CorviaFormsNavigator.openPatientForms(
        context,
        patientId: patient.id,
        hospitalId: widget.hospitalId,
        admissionId: admissionId,
        contextType: 'doctor_patient',
        contextId: widget.doctorId,
        title: 'Clinical Forms - '
            '${patient.name}',
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      _showMessage(
        'Could not open patient forms. '
        '${_cleanError(error)}',
      );
    } finally {
      if (mounted) {
        setState(() {
          _opening = false;

          _openingPatientId = null;
        });
      }
    }
  }

  // ==========================================================================
  // ACTIVE ADMISSION
  // ==========================================================================

  Future<String?> _resolveActiveAdmission({
    required String patientId,
  }) async {
    try {
      dynamic response;

      final hospitalId = widget.hospitalId?.trim();

      if (hospitalId != null && hospitalId.isNotEmpty) {
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
              hospitalId,
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
        (
          first,
          second,
        ) {
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

          final firstDate = _firstAdmissionDate(
                first,
              ) ??
              DateTime(
                1970,
              );

          final secondDate = _firstAdmissionDate(
                second,
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

        final id = admission['id']?.toString().trim();

        if (id != null && id.isNotEmpty) {
          return id;
        }
      }

      return null;
    } catch (error) {
      debugPrint(
        'Doctor active admission lookup failed: $error',
      );

      /*
       * Some forms do not require an admission,
       * therefore the form navigator can still open
       * with admissionId = null.
       */
      return null;
    }
  }

  DateTime? _firstAdmissionDate(
    Map<String, dynamic> row,
  ) {
    for (final column in const [
      'admitted_at',
      'planned_admission_at',
      'updated_at',
      'created_at',
    ]) {
      final parsed = _parseDate(
        row[column],
      );

      if (parsed != null) {
        return parsed;
      }
    }

    return null;
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
    final patients = _filteredPatients;

    return Scaffold(
      backgroundColor: context.cBgPrimary,
      appBar: AppBar(
        title: const Text(
          'Patient Clinical Forms',
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh Patients',
            onPressed: _loading || _opening ? null : _loadPatients,
            icon: const Icon(
              Icons.refresh,
            ),
          ),
        ],
      ),
      body: _loading
          ? Center(
              child: CircularProgressIndicator(
                color: CorviaColors.accent,
              ),
            )
          : _errorMessage != null
              ? _buildErrorState()
              : RefreshIndicator(
                  onRefresh: _loadPatients,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(
                      18,
                    ),
                    children: [
                      _buildHeader(),
                      const SizedBox(
                        height: 16,
                      ),
                      TextField(
                        controller: _searchController,
                        enabled: !_opening,
                        onChanged: (
                          value,
                        ) {
                          setState(() {
                            _searchQuery = value.trim().toLowerCase();
                          });
                        },
                        decoration: InputDecoration(
                          labelText: 'Search Patient',
                          hintText: 'Patient name or ID',
                          prefixIcon: const Icon(
                            Icons.search,
                          ),
                          suffixIcon: _searchController.text.isEmpty
                              ? null
                              : IconButton(
                                  tooltip: 'Clear Search',
                                  onPressed: () {
                                    _searchController.clear();

                                    setState(() {
                                      _searchQuery = '';
                                    });
                                  },
                                  icon: const Icon(
                                    Icons.clear,
                                  ),
                                ),
                          border: const OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(
                        height: 16,
                      ),
                      if (_patients.isEmpty)
                        _buildNoPatients()
                      else if (patients.isEmpty)
                        _buildNoMatches()
                      else
                        ...patients.map(
                          _buildPatientCard,
                        ),
                    ],
                  ),
                ),
    );
  }

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
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
            radius: 26,
            backgroundColor: Colors.white,
            child: Icon(
              Icons.description_outlined,
              color: Color(
                0xFF0F766E,
              ),
            ),
          ),
          const SizedBox(
            width: 13,
          ),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Clinical Hospital Forms',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(
                  height: 3,
                ),
                Text(
                  'Select an authorised doctor-linked patient.',
                  style: TextStyle(
                    color: Colors.white70,
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

  Widget _buildPatientCard(
    DoctorClinicalPatient patient,
  ) {
    final opening = _openingPatientId == patient.id;

    return Container(
      margin: const EdgeInsets.only(
        bottom: 10,
      ),
      decoration: BoxDecoration(
        color: context.cBgSecondary,
        borderRadius: BorderRadius.circular(
          16,
        ),
        border: Border.all(
          color: context.cDivider,
        ),
      ),
      child: ListTile(
        enabled: !_opening,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 6,
        ),
        leading: CircleAvatar(
          backgroundColor: CorviaColors.accent.withValues(
            alpha: 0.12,
          ),
          child: Text(
            _patientInitials(
              patient.name,
            ),
            style: TextStyle(
              color: context.cAccentReadable,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        title: Text(
          patient.name,
          style: TextStyle(
            color: context.cTextPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Text(
          'Patient ID: ${_shortId(patient.id)}',
          style: TextStyle(
            color: context.cTextSecondary,
            fontSize: 12,
          ),
        ),
        trailing: opening
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                ),
              )
            : const Icon(
                Icons.chevron_right,
              ),
        onTap: () {
          _openPatient(
            patient,
          );
        },
      ),
    );
  }

  Widget _buildNoPatients() {
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
      ),
      child: Column(
        children: [
          Icon(
            Icons.people_outline,
            size: 54,
            color: context.cTextMuted,
          ),
          const SizedBox(
            height: 12,
          ),
          Text(
            'No linked patients yet',
            style: TextStyle(
              color: context.cTextPrimary,
              fontSize: 17,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(
            height: 6,
          ),
          Text(
            'Patients connected to this doctor through '
            'appointments, prescriptions, lab requests or '
            'clinical relationships will appear here.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: context.cTextSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoMatches() {
    return Padding(
      padding: const EdgeInsets.all(
        30,
      ),
      child: Column(
        children: [
          Icon(
            Icons.search_off,
            size: 50,
            color: context.cTextMuted,
          ),
          const SizedBox(
            height: 10,
          ),
          Text(
            'No matching patients',
            style: TextStyle(
              color: context.cTextPrimary,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(
          24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline,
              size: 54,
              color: CorviaColors.danger,
            ),
            const SizedBox(
              height: 13,
            ),
            Text(
              'Patient forms could not load',
              style: TextStyle(
                color: context.cTextPrimary,
                fontSize: 19,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(
              height: 9,
            ),
            SelectableText(
              _errorMessage!,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: context.cTextSecondary,
              ),
            ),
            const SizedBox(
              height: 15,
            ),
            FilledButton.icon(
              onPressed: _loadPatients,
              icon: const Icon(
                Icons.refresh,
              ),
              label: const Text(
                'Try Again',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// DOCTOR ANALYTICS
// =============================================================================

class DoctorAnalyticsPage extends StatefulWidget {
  const DoctorAnalyticsPage({
    super.key,
    required this.doctorId,
    required this.doctorName,
  });

  final String doctorId;
  final String doctorName;

  @override
  State<DoctorAnalyticsPage> createState() {
    return _DoctorAnalyticsPageState();
  }
}

class _DoctorAnalyticsPageState extends State<DoctorAnalyticsPage> {
  final SupabaseClient _supabase = Supabase.instance.client;

  bool _loading = true;

  int _appointments = 0;
  int _completedVisits = 0;
  int _patients = 0;
  int _activePrescriptions = 0;
  int _labOrders = 0;
  int _outstandingLabs = 0;

  String? _error;

  @override
  void initState() {
    super.initState();

    _load();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final appointments = await _doctorRows(
        'appointments',
      );

      final prescriptions = await _doctorRows(
        'prescriptions',
      );

      final labs = await _doctorRows(
        'lab_results',
      );

      final patientIds = <String>{
        ...appointments
            .map(
              (
                row,
              ) =>
                  row['patient_id']?.toString().trim(),
            )
            .whereType<String>()
            .where(
              (
                id,
              ) =>
                  id.isNotEmpty,
            ),
        ...prescriptions
            .map(
              (
                row,
              ) =>
                  row['patient_id']?.toString().trim(),
            )
            .whereType<String>()
            .where(
              (
                id,
              ) =>
                  id.isNotEmpty,
            ),
        ...labs
            .map(
              (
                row,
              ) =>
                  row['patient_id']?.toString().trim(),
            )
            .whereType<String>()
            .where(
              (
                id,
              ) =>
                  id.isNotEmpty,
            ),
      };

      if (!mounted) {
        return;
      }

      setState(() {
        _appointments = appointments.length;

        _completedVisits = appointments
            .where(
              (
                appointment,
              ) =>
                  _normalise(
                    appointment['status'],
                  ) ==
                  'completed',
            )
            .length;

        _patients = patientIds.length;

        _activePrescriptions = prescriptions.where(
          (
            prescription,
          ) {
            final status = _normalise(
              prescription['status'],
            );

            return {
              'active',
              'pending',
              'preparing',
              'ready',
            }.contains(
              status,
            );
          },
        ).length;

        _labOrders = labs.length;

        _outstandingLabs = labs
            .where(
              (
                lab,
              ) =>
                  _labBucket(
                    lab['status'],
                  ) !=
                  'completed',
            )
            .length;

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

  Future<List<Map<String, dynamic>>> _doctorRows(
    String table,
  ) async {
    try {
      final response = await _supabase
          .from(table)
          .select()
          .eq(
            'doctor_id',
            widget.doctorId,
          )
          .limit(
            1000,
          );

      return _mapRows(
        response,
      );
    } catch (error) {
      debugPrint(
        'Analytics $table load failed: $error',
      );

      return [];
    }
  }

  @override
  Widget build(
    BuildContext context,
  ) {
    return Scaffold(
      backgroundColor: context.cBgPrimary,
      appBar: AppBar(
        title: const Text(
          'Doctor Analytics',
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : _load,
            icon: const Icon(
              Icons.refresh,
            ),
          ),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(),
            )
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(
                      24,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.error_outline,
                          color: CorviaColors.danger,
                          size: 50,
                        ),
                        const SizedBox(
                          height: 12,
                        ),
                        SelectableText(
                          _error!,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(
                          height: 14,
                        ),
                        FilledButton.icon(
                          onPressed: _load,
                          icon: const Icon(
                            Icons.refresh,
                          ),
                          label: const Text(
                            'Try Again',
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(
                      18,
                    ),
                    children: [
                      Text(
                        widget.doctorName,
                        style: TextStyle(
                          color: context.cTextPrimary,
                          fontSize: 23,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(
                        height: 4,
                      ),
                      Text(
                        'Clinical workload summary',
                        style: TextStyle(
                          color: context.cTextSecondary,
                        ),
                      ),
                      const SizedBox(
                        height: 20,
                      ),
                      _buildAnalyticsGrid(),
                    ],
                  ),
                ),
    );
  }

  Widget _buildAnalyticsGrid() {
    final items = [
      _DoctorStatData(
        title: 'Appointments',
        value: '$_appointments',
        icon: Icons.calendar_month_outlined,
        color: Colors.blue,
        onTap: () {},
      ),
      _DoctorStatData(
        title: 'Completed Visits',
        value: '$_completedVisits',
        icon: Icons.check_circle_outline,
        color: CorviaColors.success,
        onTap: () {},
      ),
      _DoctorStatData(
        title: 'Patients',
        value: '$_patients',
        icon: Icons.people_outline,
        color: Colors.deepPurple,
        onTap: () {},
      ),
      _DoctorStatData(
        title: 'Active Prescriptions',
        value: '$_activePrescriptions',
        icon: Icons.medication_outlined,
        color: Colors.green,
        onTap: () {},
      ),
      _DoctorStatData(
        title: 'Lab Orders',
        value: '$_labOrders',
        icon: Icons.biotech_outlined,
        color: Colors.teal,
        onTap: () {},
      ),
      _DoctorStatData(
        title: 'Outstanding Labs',
        value: '$_outstandingLabs',
        icon: Icons.pending_actions_outlined,
        color: Colors.orange,
        onTap: () {},
      ),
    ];

    return LayoutBuilder(
      builder: (
        context,
        constraints,
      ) {
        int columns;

        if (constraints.maxWidth >= 900) {
          columns = 3;
        } else {
          columns = 2;
        }

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: items.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            mainAxisExtent: 135,
          ),
          itemBuilder: (
            context,
            index,
          ) {
            final item = items[index];

            return Container(
              padding: const EdgeInsets.all(
                15,
              ),
              decoration: BoxDecoration(
                color: context.cBgSecondary,
                borderRadius: BorderRadius.circular(
                  16,
                ),
                border: Border.all(
                  color: item.color.withValues(
                    alpha: 0.25,
                  ),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    item.icon,
                    color: item.color,
                  ),
                  const Spacer(),
                  Text(
                    item.value,
                    style: TextStyle(
                      color: context.cTextPrimary,
                      fontSize: 25,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    item.title,
                    style: TextStyle(
                      color: context.cTextSecondary,
                      fontSize: 12,
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
}

// =============================================================================
// SMALL UI MODELS
// =============================================================================

class _DoctorStatData {
  const _DoctorStatData({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String title;
  final String value;

  final IconData icon;
  final Color color;

  final VoidCallback onTap;
}

class _DoctorActionData {
  const _DoctorActionData({
    required this.title,
    required this.icon,
    required this.onTap,
  });

  final String title;
  final IconData icon;
  final VoidCallback onTap;
}

// =============================================================================
// STATUS CHIP
// =============================================================================

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.status,
  });

  final String status;

  @override
  Widget build(
    BuildContext context,
  ) {
    final normalised = _normalise(
      status,
    );

    Color color;

    switch (normalised) {
      case 'completed':
      case 'complete':
      case 'done':
      case 'collected':
        color = CorviaColors.success;
        break;

      case 'confirmed':
      case 'checked_in':
      case 'in_progress':
      case 'processing':
        color = Colors.blue;
        break;

      case 'cancelled':
      case 'unable':
      case 'rejected':
        color = CorviaColors.danger;
        break;

      case 'no_show':
        color = Colors.orange;
        break;

      default:
        color = CorviaColors.warning;
    }

    final label = _prettyStatus(
      normalised,
    );

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 8,
        vertical: 4,
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
            alpha: 0.35,
          ),
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

// =============================================================================
// SHARED HELPERS
// =============================================================================

List<Map<String, dynamic>> _mapRows(
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

DateTime? _parseDate(
  dynamic value,
) {
  if (value == null) {
    return null;
  }

  return DateTime.tryParse(
    value.toString(),
  )?.toLocal();
}

DateTime? _appointmentDate(
  Map<String, dynamic> appointment,
) {
  for (final column in const [
    'appointment_date',
    'scheduled_for',
    'start_time',
    'appointment_time',
  ]) {
    final parsed = _parseDate(
      appointment[column],
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

String _prettyStatus(
  dynamic value,
) {
  final status = _normalise(
    value,
  );

  if (status.isEmpty) {
    return 'Pending';
  }

  return status
      .split(
        '_',
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
            '${word.substring(1)}',
      )
      .join(
        ' ',
      );
}

String _labBucket(
  dynamic value,
) {
  final status = _normalise(
    value,
  );

  if ({
    'completed',
    'complete',
    'done',
    'resulted',
    'finalised',
    'finalized',
  }.contains(
    status,
  )) {
    return 'completed';
  }

  if ({
    'in_progress',
    'processing',
    'received',
    'started',
  }.contains(
    status,
  )) {
    return 'in_progress';
  }

  return 'pending';
}

String _firstAvailableText(
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

String _cleanError(
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

String _shortId(
  String value,
) {
  final clean = value.trim();

  if (clean.length <= 8) {
    return clean;
  }

  return clean.substring(
    0,
    8,
  );
}

String _patientInitials(
  String name,
) {
  final parts = name
      .trim()
      .split(
        RegExp(
          r'\s+',
        ),
      )
      .where(
        (
          value,
        ) =>
            value.isNotEmpty,
      )
      .toList();

  if (parts.isEmpty) {
    return '?';
  }

  return parts
      .take(
        2,
      )
      .map(
        (
          value,
        ) =>
            value[0].toUpperCase(),
      )
      .join();
}
