import 'dart:async';

import 'package:flutter/material.dart';

import '../../auth/role_choice_page.dart';
import '../../config/env.dart';
import '../../maptiler_map_screen_state.dart';
import '../../services/account_mode_service.dart';
import '../../services/supabase_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/patient_notification_bell.dart';
import '../../widgets/status_view.dart';

import '../forms/role_hospital_forms_page.dart';
import '../shared/settings.dart';
import 'appointments_page.dart';
import 'chat_with_doctor.dart';
import 'doctor_patient_timeline.dart';
import 'emergency.dart';
import 'emergency_contacts_page.dart';
import 'emergency_qr_profile.dart';
import 'find_a_doctor.dart';
import 'lab_results.dart';
import 'my_prescriptions.dart';
import 'patient_records.dart';
import 'patient_visitor_access_page.dart';
import 'profile.dart';
import 'reception_check_in_qr.dart';
import 'reminders.dart';
import 'specialist/specialist_request_page.dart';
import 'wearables.dart';
import '../../widgets/corvia_logo.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({
    super.key,
  });

  @override
  State<DashboardPage> createState() {
    return _DashboardPageState();
  }
}

class _DashboardPageState extends State<DashboardPage> {
  int _selectedTab = 0;

  bool _canSwitchMode = false;

  static const _profileTab = 1;

  static const _tabTitles = [
    'Corvia',
    'Profile',
    'Settings',
  ];

  late final List<Widget> _tabs;

  @override
  void initState() {
    super.initState();

    _tabs = const [
      DashboardHomeContent(),
      ProfilePage(
        showAppBar: false,
      ),
      SettingsPage(
        showAppBar: false,
      ),
    ];

    unawaited(
      _loadModeAccess(),
    );
  }

  Future<void> _loadModeAccess() async {
    try {
      final access = await AccountModeService.current();

      if (!mounted) {
        return;
      }

      setState(() {
        _canSwitchMode = access.isActive &&
            (access.canSwitchClinicalPatient ||
                access.canSwitchLabPatient ||
                (access.hasPatientAccess && access.hasLabAccess));
      });
    } catch (error) {
      debugPrint(
        'Patient mode access lookup failed: $error',
      );
    }
  }

  Future<void> _changeTab(
    int index,
  ) async {
    if (index == _selectedTab) {
      return;
    }

    // Leaving Profile mid-edit must warn about unsaved changes and must not
    // leave the form half-edited for next time (#240).
    if (_selectedTab == _profileTab && !await confirmLeaveProfile(context)) {
      return;
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _selectedTab = index;
    });
  }

  Future<void> _openSwitchMode() async {
    if (_selectedTab == _profileTab && !await confirmLeaveProfile(context)) {
      return;
    }
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) {
          return const RoleChoicePage();
        },
      ),
    );
  }

  Widget? _buildLeading() {
    if (_selectedTab != 0) {
      return IconButton(
        tooltip: 'Back to dashboard',
        icon: const Icon(
          Icons.arrow_back,
        ),
        onPressed: () {
          unawaited(
            _changeTab(
              0,
            ),
          );
        },
      );
    }

    return null;
  }

  Widget _buildTitle() {
    if (_selectedTab != 0) {
      return Text(
        _tabTitles[_selectedTab],
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 34,
          height: 34,
          padding: const EdgeInsets.all(
            4,
          ),
          decoration: const BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
          ),
          child: const CorviaLogo(size: 26),
        ),
        const SizedBox(
          width: 8,
        ),
        const Text(
          'Corvia',
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.cBgPrimary,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: _buildLeading(),
        title: _buildTitle(),
        actions: [
          const PatientNotificationBell(),
          if (_canSwitchMode)
            IconButton(
              tooltip: 'Switch Mode',
              onPressed: _openSwitchMode,
              icon: const Icon(
                Icons.swap_horiz_rounded,
              ),
            ),
        ],
      ),
      body: IndexedStack(
        index: _selectedTab,
        children: _tabs,
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedTab,
        onTap: _changeTab,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(
              Icons.home_rounded,
            ),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(
              Icons.person_rounded,
            ),
            label: 'Profile',
          ),
          BottomNavigationBarItem(
            icon: Icon(
              Icons.settings_rounded,
            ),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}

class DashboardHomeContent extends StatefulWidget {
  const DashboardHomeContent({
    super.key,
  });

  @override
  State<DashboardHomeContent> createState() {
    return _DashboardHomeContentState();
  }
}

class _DashboardHomeContentState extends State<DashboardHomeContent> {
  Future<_DashboardStats>? _statsFuture;
  Future<String?>? _firstNameFuture;

  @override
  void initState() {
    super.initState();

    _statsFuture = _DashboardStats.load();
    _firstNameFuture = _loadFirstName();
  }

  Future<void> _refresh() async {
    if (!mounted) {
      return;
    }

    setState(() {
      _statsFuture = _DashboardStats.load();
      _firstNameFuture = _loadFirstName();
    });

    await _statsFuture;
  }

  static Future<String?> _loadFirstName() async {
    try {
      final profile = await SupabaseService.currentProfile();

      final name = (profile?['first_name'] as String?)?.trim();
      if (name != null && name.isNotEmpty) return name;
      final userId = SupabaseService.currentUserId;
      if (userId == null) return null;
      final patient = await SupabaseService.client
          .from('patients')
          .select('first_name')
          .eq('profile_id', userId)
          .maybeSingle();
      final patientName = patient?['first_name']?.toString().trim();
      return patientName == null || patientName.isEmpty ? null : patientName;
    } catch (_) {
      return null;
    }
  }

  int _gridColumns(
    double width,
  ) {
    if (width >= 1200) {
      return 5;
    }

    if (width >= 900) {
      return 4;
    }

    if (width >= 650) {
      return 3;
    }

    if (width >= 350) {
      return 2;
    }

    return 1;
  }

  String get _timeOfDayGreeting {
    final hour = DateTime.now().hour;

    if (hour < 12) {
      return 'Good morning';
    }

    if (hour < 18) {
      return 'Good afternoon';
    }

    return 'Good evening';
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _refresh,
      child: LayoutBuilder(
        builder: (
          context,
          constraints,
        ) {
          final columns = _gridColumns(
            constraints.maxWidth,
          );

          final textScale = MediaQuery.textScalerOf(
            context,
          ).scale(
            1,
          );

          final cardHeight = textScale > 1.25 ? 175.0 : 150.0;

          final horizontalPadding = constraints.maxWidth >= 900 ? 28.0 : 16.0;

          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(
              horizontalPadding,
              16,
              horizontalPadding,
              32,
            ),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: 1300,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      FutureBuilder<String?>(
                        future: _firstNameFuture,
                        builder: (
                          context,
                          snapshot,
                        ) {
                          final name = snapshot.data;

                          final greeting = _timeOfDayGreeting;

                          return Text(
                            name == null ? greeting : '$greeting, $name',
                            style: TextStyle(
                              color: context.cTextPrimary,
                              fontSize: 26,
                              fontWeight: FontWeight.bold,
                            ),
                          );
                        },
                      ),
                      const SizedBox(
                        height: 8,
                      ),
                      Text(
                        'Quick Actions',
                        style: TextStyle(
                          color: context.cAccentReadable,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(
                        height: 12,
                      ),
                      FutureBuilder<_DashboardStats>(
                        future: _statsFuture,
                        builder: (
                          context,
                          snapshot,
                        ) {
                          final stats = snapshot.data;

                          return GridView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: _DashboardAction.all.length,
                            gridDelegate:
                                SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: columns,
                              crossAxisSpacing: 14,
                              mainAxisSpacing: 14,
                              mainAxisExtent: cardHeight,
                            ),
                            itemBuilder: (
                              context,
                              index,
                            ) {
                              final action = _DashboardAction.all[index];

                              final readyCount = action.showReadyPharmacyBadge
                                  ? stats?.readyPharmacyCollections
                                  : null;

                              return _DashboardCard(
                                action: action,
                                badgeCount: readyCount,
                                onReturn: action.showReadyPharmacyBadge
                                    ? _refresh
                                    : null,
                              );
                            },
                          );
                        },
                      ),
                      const SizedBox(
                        height: 28,
                      ),
                      Text(
                        'Health Stats',
                        style: TextStyle(
                          color: context.cAccentReadable,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(
                        height: 12,
                      ),
                      FutureBuilder<_DashboardStats>(
                        future: _statsFuture,
                        builder: (
                          context,
                          snapshot,
                        ) {
                          if (snapshot.connectionState !=
                              ConnectionState.done) {
                            return const _StatsSkeleton();
                          }

                          if (snapshot.hasError || !snapshot.hasData) {
                            return InlineStatus(
                              icon: Icons.cloud_off,
                              message: "We couldn't refresh your stats. "
                                  'Pull down to try again.',
                              tint: CorviaColors.warning,
                            );
                          }

                          final stats = snapshot.data!;

                          return Column(
                            children: [
                              _StatRow(
                                title: 'Upcoming Appointments',
                                value: stats.upcomingAppointments,
                              ),
                              _StatRow(
                                title: 'Active Lab Orders',
                                value: stats.pendingLabResults,
                              ),
                              _StatRow(
                                title: 'Active Prescriptions',
                                value: stats.activePrescriptions,
                              ),
                              _StatRow(
                                title: 'Ready Pharmacy Collections',
                                value: stats.readyPharmacyCollections,
                              ),
                              _StatRow(
                                title: 'Bills Pending',
                                value: stats.billsPending,
                              ),
                            ],
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
}

class _DashboardAction {
  const _DashboardAction({
    required this.icon,
    required this.title,
    required this.color,
    required this.builder,
    this.isEnabled = true,
    this.statusLabel,
    this.requiredLongPress = false,
    this.isEmergency = false,
    this.showReadyPharmacyBadge = false,
  });

  final IconData icon;
  final String title;
  final Color color;
  final WidgetBuilder builder;
  final bool isEnabled;
  final String? statusLabel;

  final bool requiredLongPress;
  final bool isEmergency;
  final bool showReadyPharmacyBadge;

  static final List<_DashboardAction> all = [
    // ==========================================================
    // EMERGENCY
    // ==========================================================

    _DashboardAction(
      icon: Icons.warning_rounded,
      title: 'Emergency',
      color: CorviaColors.danger,
      requiredLongPress: Env.emergencyDispatchEnabled,
      isEmergency: true,
      builder: (_) {
        return const EmergencyPage();
      },
    ),

    _DashboardAction(
      icon: Icons.qr_code_rounded,
      title: 'Emergency QR',
      color: CorviaColors.danger,
      builder: (_) {
        return const EmergencyQrProfilePage();
      },
    ),

    _DashboardAction(
      icon: Icons.contact_phone_rounded,
      title: 'Emergency Contacts',
      color: CorviaColors.danger,
      builder: (_) {
        return const EmergencyContactsPage();
      },
    ),

    // ==========================================================
    // APPOINTMENTS / SPECIALISTS
    // ==========================================================

    _DashboardAction(
      icon: Icons.health_and_safety_rounded,
      title: 'Specialist Request',
      color: Colors.deepPurpleAccent,
      builder: (_) {
        return const SpecialistRequestPage();
      },
    ),

    _DashboardAction(
      icon: Icons.calendar_month_rounded,
      title: 'Appointments',
      color: Colors.blueAccent,
      builder: (_) {
        return const AppointmentsPage();
      },
    ),

    // ==========================================================
    // PRESCRIPTIONS / PHARMACY
    // ==========================================================

    _DashboardAction(
      icon: Icons.medical_services_rounded,
      title: 'My Prescriptions',
      color: Colors.greenAccent,
      showReadyPharmacyBadge: true,
      builder: (_) {
        return const MyPrescriptionsPage();
      },
    ),

    _DashboardAction(
      icon: Icons.qr_code_2_rounded,
      title: 'Check-In QR',
      color: Colors.lightBlueAccent,
      builder: (_) {
        return const ReceptionCheckInQrPage();
      },
    ),

    // ==========================================================
    // AI / CLINICAL
    // ==========================================================

    _DashboardAction(
      icon: Icons.smart_toy_rounded,
      title: 'AI Nurse',
      color: Colors.greenAccent,
      isEnabled: false,
      statusLabel: 'Work in progress',
      builder: (_) {
        return const SizedBox.shrink();
      },
    ),

    _DashboardAction(
      icon: Icons.timeline_rounded,
      title: 'Patient Timeline',
      color: Colors.deepOrangeAccent,
      builder: (_) {
        return const DoctorPatientTimelinePage();
      },
    ),

    _DashboardAction(
      icon: Icons.chat_bubble_rounded,
      title: 'Chat with Doctor',
      color: Colors.purpleAccent,
      builder: (_) {
        return const ChatWithDoctorPage();
      },
    ),

    _DashboardAction(
      icon: Icons.notifications_active_rounded,
      title: 'Reminders',
      color: Colors.pinkAccent,
      builder: (_) {
        return const RemindersPage();
      },
    ),

    // ==========================================================
    // PATIENT RECORDS
    // ==========================================================

    _DashboardAction(
      icon: Icons.folder_shared_rounded,
      title: 'Patient Records',
      color: Colors.cyanAccent,
      builder: (_) {
        return const PatientRecordsPage();
      },
    ),

    // ==========================================================
    // DIGITAL HOSPITAL FORMS
    // ==========================================================

    _DashboardAction(
      icon: Icons.description_rounded,
      title: 'My Hospital Forms',
      color: Colors.lightBlueAccent,
      builder: (_) {
        return const RoleHospitalFormsPage(
          title: 'My Hospital Forms',
          patientVisibleOnly: true,
          allowCreate: true,
        );
      },
    ),

    // ==========================================================
    // VISITOR ACCESS
    // ==========================================================

    _DashboardAction(
      icon: Icons.badge_outlined,
      title: 'Visitor Access',
      color: Colors.indigoAccent,
      builder: (_) {
        return const PatientVisitorAccessPage();
      },
    ),

    // ==========================================================
    // LAB RESULTS
    // ==========================================================

    _DashboardAction(
      icon: Icons.science_rounded,
      title: 'Lab Results',
      color: Colors.deepPurpleAccent,
      builder: (_) {
        return const LabResultsPage();
      },
    ),

    // ==========================================================
    // DOCTOR / SERVICES
    // ==========================================================

    _DashboardAction(
      icon: Icons.local_hospital_rounded,
      title: 'Find a Doctor',
      color: Colors.indigoAccent,
      builder: (_) {
        return const FindADoctorPage();
      },
    ),

    _DashboardAction(
      icon: Icons.map_rounded,
      title: 'Nearby Services',
      color: Colors.tealAccent,
      builder: (_) {
        return const MapTilerMapScreen();
      },
    ),

    // ==========================================================
    // WEARABLES
    // ==========================================================

    _DashboardAction(
      icon: Icons.monitor_heart_rounded,
      title: 'Wearables',
      color: Colors.blueAccent,
      builder: (_) {
        return const CorviaWearableApp();
      },
    ),
  ];
}

class LongPressGuard extends StatefulWidget {
  const LongPressGuard({
    super.key,
    required this.child,
    required this.onSuccess,
    this.onTap,
    this.duration = const Duration(
      seconds: 3,
    ),
  });

  final Widget child;
  final FutureOr<void> Function() onSuccess;
  final VoidCallback? onTap;
  final Duration duration;

  @override
  State<LongPressGuard> createState() {
    return _LongPressGuardState();
  }
}

class _LongPressGuardState extends State<LongPressGuard> {
  Timer? _timer;

  bool _completed = false;

  void _startTimer() {
    _timer?.cancel();

    _completed = false;

    _timer = Timer(
      widget.duration,
      () async {
        if (!mounted || _completed) {
          return;
        }

        _completed = true;

        await widget.onSuccess();
      },
    );
  }

  void _cancelTimer() {
    _timer?.cancel();

    _timer = null;
  }

  @override
  void dispose() {
    _timer?.cancel();

    super.dispose();
  }

  @override
  Widget build(
    BuildContext context,
  ) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      onLongPressStart: (_) {
        _startTimer();
      },
      onLongPressEnd: (_) {
        _cancelTimer();
      },
      onLongPressCancel: _cancelTimer,
      child: widget.child,
    );
  }
}

class _DashboardCard extends StatefulWidget {
  const _DashboardCard({
    required this.action,
    this.badgeCount,
    this.onReturn,
  });

  final _DashboardAction action;
  final int? badgeCount;
  final Future<void> Function()? onReturn;

  @override
  State<_DashboardCard> createState() {
    return _DashboardCardState();
  }
}

class _DashboardCardState extends State<_DashboardCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;

  late final Animation<double> _pulseAnimation;

  bool _opening = false;

  bool get _isEmergency {
    return widget.action.isEmergency;
  }

  bool get _showBadge {
    return (widget.badgeCount ?? 0) > 0;
  }

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(
        milliseconds: 900,
      ),
    );

    _pulseAnimation = Tween<double>(
      begin: 1,
      end: 1.045,
    ).animate(
      CurvedAnimation(
        parent: _pulseController,
        curve: Curves.easeInOut,
      ),
    );

    if (_isEmergency) {
      _pulseController.repeat(
        reverse: true,
      );
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();

    super.dispose();
  }

  Future<void> _openPage() async {
    if (_opening || !mounted || !widget.action.isEnabled) {
      return;
    }

    setState(() {
      _opening = true;
    });

    try {
      await Navigator.of(
        context,
      ).push(
        MaterialPageRoute<void>(
          builder: widget.action.builder,
        ),
      );

      if (widget.onReturn != null) {
        await widget.onReturn!();
      }
    } finally {
      if (mounted) {
        setState(() {
          _opening = false;
        });
      }
    }
  }

  void _showEmergencyInstruction() {
    ScaffoldMessenger.of(
      context,
    )
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text(
            'Hold for 3 seconds to '
            'confirm emergency access.',
          ),
        ),
      );
  }

  @override
  Widget build(
    BuildContext context,
  ) {
    final action = widget.action;

    final cardContent = Stack(
      fit: StackFit.expand,
      clipBehavior: Clip.none,
      children: [
        Padding(
          padding: const EdgeInsets.all(
            12,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (_opening)
                const SizedBox(
                  width: 38,
                  height: 38,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                  ),
                )
              else
                Icon(
                  action.icon,
                  color: _isEmergency ? Colors.white : action.color,
                  size: 42,
                ),
              const SizedBox(
                height: 12,
              ),
              Text(
                action.title,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: _isEmergency ? Colors.white : context.cTextPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (action.statusLabel != null) ...[
                const SizedBox(
                  height: 5,
                ),
                Text(
                  action.statusLabel!,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: context.cTextSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              if (_isEmergency) ...[
                const SizedBox(
                  height: 5,
                ),
                Text(
                  action.requiredLongPress
                      ? 'Hold for 3 seconds'
                      : 'Tap for emergency help',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 11,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (_showBadge)
          Positioned(
            top: 9,
            right: 9,
            child: Semantics(
              label:
                  '${widget.badgeCount} pharmacy orders ready for collection',
              child: Container(
                constraints: const BoxConstraints(
                  minWidth: 27,
                  minHeight: 27,
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 7,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: CorviaColors.danger,
                  borderRadius: BorderRadius.circular(
                    999,
                  ),
                  border: Border.all(
                    color: Colors.white,
                    width: 2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(
                        alpha: 0.20,
                      ),
                      blurRadius: 6,
                      offset: const Offset(
                        0,
                        2,
                      ),
                    ),
                  ],
                ),
                child: Center(
                  child: Text(
                    '${widget.badgeCount}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );

    final card = Semantics(
      button: action.isEnabled,
      enabled: action.isEnabled,
      label: action.title,
      hint: !action.isEnabled
          ? action.statusLabel
          : action.requiredLongPress
              ? 'Hold for three seconds to open'
              : _showBadge
                  ? '${widget.badgeCount} pharmacy orders are ready. Double tap to open.'
                  : 'Double tap to open',
      child: Material(
        color: _isEmergency ? CorviaColors.danger : context.cBgSecondary,
        borderRadius: BorderRadius.circular(
          16,
        ),
        elevation: _isEmergency ? 8 : 3,
        shadowColor: _isEmergency
            ? CorviaColors.danger.withValues(
                alpha: 0.5,
              )
            : context.cCardShadow,
        child: action.requiredLongPress
            ? LongPressGuard(
                onTap: _showEmergencyInstruction,
                onSuccess: _openPage,
                child: cardContent,
              )
            : InkWell(
                key: Key(
                  '${action.title}Card',
                ),
                borderRadius: BorderRadius.circular(
                  16,
                ),
                onTap: _opening || !action.isEnabled ? null : _openPage,
                child: cardContent,
              ),
      ),
    );

    if (!_isEmergency) {
      return card;
    }

    return AnimatedBuilder(
      animation: _pulseAnimation,
      builder: (
        context,
        child,
      ) {
        return Transform.scale(
          scale: _pulseAnimation.value,
          child: child,
        );
      },
      child: card,
    );
  }
}

class _StatRow extends StatelessWidget {
  const _StatRow({
    required this.title,
    required this.value,
  });

  final String title;
  final int? value;

  @override
  Widget build(
    BuildContext context,
  ) {
    final failed = value == null;

    return Container(
      margin: const EdgeInsets.symmetric(
        vertical: 6,
      ),
      padding: const EdgeInsets.all(
        16,
      ),
      decoration: BoxDecoration(
        color: context.cBgSecondary,
        borderRadius: BorderRadius.circular(
          16,
        ),
        border: Border.all(
          color: context.cDivider,
        ),
        boxShadow: [
          BoxShadow(
            color: context.cCardShadow,
            blurRadius: 4,
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                color: context.cTextPrimary,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(
            width: 12,
          ),
          Text(
            failed ? '—' : '$value',
            style: TextStyle(
              color: failed ? CorviaColors.warning : context.cAccentReadable,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatsSkeleton extends StatelessWidget {
  const _StatsSkeleton();

  @override
  Widget build(
    BuildContext context,
  ) {
    return Column(
      children: List.generate(
        5,
        (_) {
          return Container(
            margin: const EdgeInsets.symmetric(
              vertical: 6,
            ),
            height: 58,
            decoration: BoxDecoration(
              color: context.cBgSecondary.withValues(
                alpha: 0.6,
              ),
              borderRadius: BorderRadius.circular(
                16,
              ),
            ),
          );
        },
      ),
    );
  }
}

class _DashboardStats {
  const _DashboardStats({
    required this.upcomingAppointments,
    required this.pendingLabResults,
    required this.activePrescriptions,
    required this.readyPharmacyCollections,
    required this.billsPending,
  });

  static const Duration _timeout = Duration(
    seconds: 12,
  );

  final int? upcomingAppointments;
  final int? pendingLabResults;
  final int? activePrescriptions;
  final int? readyPharmacyCollections;
  final int? billsPending;

  static Future<_DashboardStats> load() async {
    try {
      final patientId = await SupabaseService.currentPatientId().timeout(
        _timeout,
      );

      if (patientId == null || patientId.trim().isEmpty) {
        return const _DashboardStats(
          upcomingAppointments: 0,
          pendingLabResults: 0,
          activePrescriptions: 0,
          readyPharmacyCollections: 0,
          billsPending: 0,
        );
      }

      final client = SupabaseService.client;

      final userId = SupabaseService.currentUserId;

      Future<int?> safeCount(
        Future<dynamic> Function() query,
      ) async {
        try {
          final response = await query().timeout(
            _timeout,
          );

          if (response is List) {
            return response.length;
          }

          return null;
        } catch (error) {
          debugPrint(
            'Dashboard count failed: $error',
          );

          return null;
        }
      }

      final upcomingFuture = safeCount(
        () {
          return client
              .from(
                'appointments',
              )
              .select(
                'id',
              )
              .eq(
                'patient_id',
                patientId,
              )
              .inFilter(
            'status',
            [
              'scheduled',
              'confirmed',
            ],
          ).gte(
            'appointment_date',
            DateTime.now().toUtc().toIso8601String(),
          );
        },
      );

      final prescriptionFuture = safeCount(
        () {
          return client
              .from(
                'prescriptions',
              )
              .select(
                'id',
              )
              .eq(
                'patient_id',
                patientId,
              )
              .eq(
                'status',
                'active',
              );
        },
      );

      final pharmacyReadyFuture = safeCount(
        () {
          return client
              .from(
                'prescription_dispenses',
              )
              .select(
                'id',
              )
              .eq(
                'patient_id',
                patientId,
              )
              .eq(
                'status',
                'ready_for_collection',
              );
        },
      );

      final billingFuture = userId == null
          ? Future<int?>.value(
              0,
            )
          : safeCount(
              () {
                return client
                    .from(
                      'subscriptions',
                    )
                    .select(
                      'id',
                    )
                    .eq(
                      'user_id',
                      userId,
                    )
                    .inFilter(
                  'status',
                  [
                    'pending',
                    'expired',
                  ],
                );
              },
            );

      final labFuture = _countActivePatientLabOrders();

      final results = await Future.wait<int?>(
        [
          upcomingFuture,
          prescriptionFuture,
          pharmacyReadyFuture,
          billingFuture,
          labFuture,
        ],
      ).timeout(
        _timeout,
      );

      return _DashboardStats(
        upcomingAppointments: results[0],
        activePrescriptions: results[1],
        readyPharmacyCollections: results[2],
        billsPending: results[3],
        pendingLabResults: results[4],
      );
    } on TimeoutException {
      return const _DashboardStats(
        upcomingAppointments: null,
        pendingLabResults: null,
        activePrescriptions: null,
        readyPharmacyCollections: null,
        billsPending: null,
      );
    } catch (error) {
      debugPrint(
        'Dashboard stats load failed: $error',
      );

      return const _DashboardStats(
        upcomingAppointments: null,
        pendingLabResults: null,
        activePrescriptions: null,
        readyPharmacyCollections: null,
        billsPending: null,
      );
    }
  }

  static Future<int?> _countActivePatientLabOrders() async {
    try {
      final response = await SupabaseService.client
          .rpc('corvia_patient_lab_order_timeline')
          .timeout(_timeout);

      if (response is! List) return 0;

      const finalStatuses = {
        'released',
        'completed',
        'complete',
        'done',
        'resulted',
        'finalised',
        'finalized',
        'cancelled',
        'canceled',
        'rejected',
        'void',
      };

      return response.whereType<Map>().where((order) {
        final status = order['status']
                ?.toString()
                .trim()
                .toLowerCase()
                .replaceAll('-', '_')
                .replaceAll(' ', '_') ??
            'pending';
        return !finalStatuses.contains(status);
      }).length;
    } catch (error) {
      debugPrint(
        'Active laboratory order count failed: $error',
      );

      return null;
    }
  }
}
