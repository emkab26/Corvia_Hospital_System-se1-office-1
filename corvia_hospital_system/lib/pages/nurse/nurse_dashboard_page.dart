import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/account_mode_service.dart';
import '../../services/nurse_service.dart';
import '../../services/settings_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/staff_workspace_shell.dart';

import '../shared/settings.dart';

import 'nurse_assigned_patients_page.dart';
import 'nurse_lab_collection_page.dart';
import 'nurse_medication_rounds_page.dart';
import 'nurse_observations_page.dart';
import 'nurse_shift_page.dart';
import 'nurse_tasks_page.dart';
import 'vital_signs_simulator_page.dart';

enum _NurseSection {
  dashboard('/', 'Dashboard', Icons.dashboard_rounded),
  shifts('/shifts', 'Shift Management', Icons.schedule_rounded),
  patients('/patients', 'Assigned Patients', Icons.people_alt_rounded),
  observations('/observations', 'Observations & Vitals', Icons.monitor_heart_outlined),
  specimens('/specimens', 'Specimen Collection', Icons.biotech_outlined),
  tasks('/tasks', 'Nursing Tasks', Icons.task_alt_rounded),
  medications('/medications', 'Medication Rounds', Icons.medication_rounded),
  settings('/settings', 'Settings', Icons.settings_rounded),
  vitalSigns('/vital-signs', 'Vital Signs Simulator', Icons.monitor_heart);

  const _NurseSection(this.route, this.label, this.icon);

  final String route;
  final String label;
  final IconData icon;
}


class NurseDashboardPage extends StatefulWidget {
  const NurseDashboardPage({
    super.key,
    this.service,
  });

  final NurseService? service;

  @override
  State<NurseDashboardPage> createState() {
    return _NurseDashboardPageState();
  }
}

class _NurseDashboardPageState extends State<NurseDashboardPage> {
  late final NurseService _service = widget.service ?? NurseService();
  final _navigatorKey = GlobalKey<NavigatorState>();
  late final _NurseNavigationObserver _navigationObserver =
      _NurseNavigationObserver(_onNavigationChanged);
  final _pageRevisions = {
    for (final section in _NurseSection.values) section: ValueNotifier<int>(0),
  };
  _NurseSection _section = _NurseSection.dashboard;
  String? _currentRoute = '/';
  bool _canGoBack = false;

  final SupabaseClient _supabase =
      Supabase.instance.client;

  bool _isLoading = true;
  bool _isSigningOut = false;
  bool _canSwitchMode = false;

  String? _errorMessage;

  NurseContext? _nurseContext;

  Map<String, dynamic>? _activeShift;

  NurseWorkspaceCounts _workspaceCounts =
      const NurseWorkspaceCounts(
    assignedPatients: 0,
    activeTasks: 0,
    activeMedications: null,
  );

  @override
  void initState() {
    super.initState();

    _loadDashboard();
  }

  @override
  void dispose() {
    for (final revision in _pageRevisions.values) {
      revision.dispose();
    }
    super.dispose();
  }

  // ==========================================================================
  // LOAD DASHBOARD Testing
  // ==========================================================================

  Future<void> _loadDashboard() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
      _pageRevisions[_NurseSection.dashboard]!.value++;
    }

    try {
      final workspace = await _service.loadWorkspace();
      final nurseContext = workspace.context;

      final activeShift =
          await _service.loadActiveShift(
        nurseContext,
      );

      final workspaceCounts =
          await _service.loadWorkspaceCounts(
        workspace,
      );

      final modeAccess =
          await AccountModeService.current();

      if (!mounted) {
        return;
      }

      setState(() {
        _nurseContext = nurseContext;
        _activeShift = activeShift;
        _workspaceCounts = workspaceCounts;

        /*
         * This value comes from the existing
         * DB-authoritative corvia_current_mode_access()
         * relationship logic.
         */
        _canSwitchMode =
            modeAccess.canSwitchNursePatient;

        _isLoading = false;
      });
      _pageRevisions[_NurseSection.dashboard]!.value++;
    } catch (error) {
      debugPrint(
        'Nurse Dashboard load error: $error',
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _isLoading = false;
        _errorMessage = _cleanError(
          error,
        );
      });
      _pageRevisions[_NurseSection.dashboard]!.value++;
    }
  }

  // ==========================================================================
  // NAVIGATION
  // ==========================================================================

  void _openSection(_NurseSection section) {
    final navigator = _navigatorKey.currentState;
    if (navigator == null || _currentRoute == section.route) return;
    if (section == _NurseSection.dashboard) {
      navigator.popUntil((route) => route.isFirst);
    } else if (_section == section) {
      // Return from a detail/form route to its menu page.
      navigator.popUntil((route) => route.settings.name == section.route);
    } else {
      // Keep Dashboard as the only history entry below the selected menu page.
      navigator.pushNamedAndRemoveUntil(section.route, (route) => route.isFirst);
    }
  }

  void _onNavigationChanged(List<Route<dynamic>> routes) {
    // Navigator reports its initial route during build. Update the surrounding
    // header after that frame, and use the latest stack when several routes move.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || routes.isEmpty) return;
      var section = _NurseSection.dashboard;
      for (final route in routes) {
        for (final candidate in _NurseSection.values) {
          if (route.settings.name == candidate.route) section = candidate;
        }
      }
      final routeName = routes.last.settings.name;
      final canGoBack = routes.length > 1;
      if (_section == section && _currentRoute == routeName && _canGoBack == canGoBack) return;
      final returningToDashboard = section == _NurseSection.dashboard &&
          _section != _NurseSection.dashboard;
      setState(() {
        _section = section;
        _currentRoute = routeName;
        _canGoBack = canGoBack;
      });
      if (returningToDashboard && !_isLoading) _loadDashboard();
    });
  }

  void _refreshCurrentPage() {
    if (_section == _NurseSection.dashboard) {
      _loadDashboard();
    } else {
      _pageRevisions[_section]!.value++;
    }
  }

  Route<void>? _workspaceRoute(RouteSettings settings) {
    final section = _NurseSection.values.where((section) => section.route == settings.name).firstOrNull;
    if (section == null) return null;
    return MaterialPageRoute<void>(
      settings: settings,
      builder: (_) => ValueListenableBuilder<int>(
        valueListenable: _pageRevisions[section]!,
        builder: (context, revision, __) => _sectionPage(section, revision, context),
      ),
    );
  }

  Widget _sectionPage(_NurseSection section, int revision, BuildContext context) {
    final key = ValueKey('${section.route}-$revision');
    return switch (section) {
      _NurseSection.dashboard => _buildBody(context),
      _NurseSection.shifts => NurseShiftPage(key: key, service: _service, showAppBar: false),
      _NurseSection.patients => NurseAssignedPatientsPage(key: key, service: _service, showAppBar: false),
      _NurseSection.observations => NurseObservationsPage(key: key, service: _service, showAppBar: false),
      _NurseSection.vitalSigns => VitalSignsSimulatorPage(key: key, showAppBar: false),
      _NurseSection.specimens => NurseLabCollectionPage(key: key, service: _service, showAppBar: false),
      _NurseSection.tasks => NurseTasksPage(key: key, service: _service, showAppBar: false),
      _NurseSection.medications => NurseMedicationRoundsPage(key: key, service: _service, showAppBar: false),
      _NurseSection.settings => SettingsPage(key: key, showAppBar: false, showStaffWorkspaces: true),
    };
  }

  Future<void> _switchMode() async {
    if (!_canSwitchMode) {
      _showMessage(
        'This nurse account does not have a linked patient mode.',
      );

      return;
    }

    /*
     * IMPORTANT:
     *
     * Nurse + Patient accounts are routed:
     *
     * AuthGate
     *   -> RoleChoicePage
     *      -> NurseDashboardPage
     *
     * Therefore Switch Mode simply returns to the
     * existing RoleChoicePage.
     *
     * We deliberately do NOT import RoleChoicePage here.
     * This prevents a circular dependency:
     *
     * RoleChoicePage -> NurseDashboardPage
     * NurseDashboardPage -> RoleChoicePage
     */

    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();

      return;
    }

    _showMessage(
      'The mode selection screen is not available from this route.',
    );
  }

  // ==========================================================================
  // LOGOUT
  // ==========================================================================

  Future<void> _signOut() async {
    if (_isSigningOut) {
      return;
    }

    setState(() {
      _isSigningOut = true;
    });

    try {
      SettingsService.instance.sessionUnlocked =
          false;

      await _supabase.auth.signOut();

      if (!mounted) {
        return;
      }

      /*
       * main.dart owns the root AuthGate.
       *
       * Return to that root route after the Supabase
       * session has been removed.
       */
      Navigator.of(context).popUntil(
        (route) => route.isFirst,
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
  // HELPERS
  // ==========================================================================

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

  String _formatDateTime(
    dynamic value,
  ) {
    final parsed = DateTime.tryParse(
      value?.toString() ?? '',
    )?.toLocal();

    if (parsed == null) {
      return 'Not available';
    }

    final day =
        parsed.day.toString().padLeft(
              2,
              '0',
            );

    final month =
        parsed.month.toString().padLeft(
              2,
              '0',
            );

    final hour =
        parsed.hour.toString().padLeft(
              2,
              '0',
            );

    final minute =
        parsed.minute.toString().padLeft(
              2,
              '0',
            );

    return '$day/$month/${parsed.year} '
        '$hour:$minute';
  }

  String _currentShiftDuration() {
    final clockIn = DateTime.tryParse(
      _activeShift?['clock_in_at']
              ?.toString() ??
          '',
    )?.toLocal();

    if (clockIn == null) {
      return '0 min';
    }

    final difference =
        DateTime.now().difference(
      clockIn,
    );

    if (difference.isNegative) {
      return '0 min';
    }

    final hours =
        difference.inHours;

    final minutes =
        difference.inMinutes.remainder(
      60,
    );

    if (hours <= 0) {
      return '$minutes min';
    }

    return '${hours}h ${minutes}m';
  }

  String _prettyRole(
    String value,
  ) {
    final cleaned = value
        .replaceAll(
          '_',
          ' ',
        )
        .trim();

    if (cleaned.isEmpty) {
      return 'NURSE';
    }

    return cleaned.toUpperCase();
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
    final busy = _isLoading;

    return StaffWorkspaceShell(
      workspaceName: 'Nursing Station',
      breadcrumb: 'Nurse',
      pageTitle: _section.label,
      subtitle: [
        if ((_nurseContext?.hospitalName ?? '').isNotEmpty)
          _nurseContext!.hospitalName,
        'shifts, patients, observations, tasks and medication rounds',
      ].join(' · '),
      onSignOut: _isSigningOut ? null : _signOut,
      headerActions: [
        if (_canGoBack)
          OutlinedButton.icon(
            onPressed: () => _navigatorKey.currentState?.maybePop(),
            icon: const Icon(Icons.arrow_back),
            label: const Text('Back'),
          ),
        if (_canSwitchMode)
          OutlinedButton.icon(
            onPressed: busy ? null : _switchMode,
            icon: const Icon(Icons.swap_horiz_rounded),
            label: const Text('Switch Mode'),
          ),
        if (_currentRoute == _section.route)
          OutlinedButton.icon(
            onPressed: busy ? null : _refreshCurrentPage,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Refresh'),
          ),
      ],
      items: [
        for (final section in _NurseSection.values)
          StaffShellItem(
            label: section.label,
            icon: section.icon,
            selected: _section == section,
            onTap: busy ? null : () => _openSection(section),
          ),
      ],
      body: NavigatorPopHandler<Object?>(
        onPopWithResult: (result) => _navigatorKey.currentState?.pop(result),
        child: Navigator(
          key: _navigatorKey,
          observers: [_navigationObserver],
          onGenerateRoute: _workspaceRoute,
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
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

    final nurseContext =
        _nurseContext;

    if (nurseContext == null) {
      return _buildMissingContextState();
    }

    return RefreshIndicator(
      color: context.cAccentReadable,
      onRefresh: _loadDashboard,
      child: ListView(
        physics:
            const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(
          18,
        ),
        children: [
          _buildWelcomeCard(
            nurseContext,
          ),
          const SizedBox(
            height: 16,
          ),
          _buildHospitalContextCard(
            nurseContext,
          ),
          const SizedBox(
            height: 16,
          ),
          _buildShiftSummary(),
          const SizedBox(
            height: 22,
          ),
          Text(
            'Nurse Workspace',
            style: TextStyle(
              color: context.cTextPrimary,
              fontSize: 19,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(
            height: 12,
          ),
          _NurseActionCard(
            icon: Icons.schedule_outlined,
            title: 'Shift Management',
            subtitle:
                'Clock in, manage breaks, save handover notes '
                'and clock out.',
            onTap: () {
              _openSection(_NurseSection.shifts);
            },
          ),
          const SizedBox(
            height: 12,
          ),
          _NurseActionCard(
            icon: Icons.people_outline,
            title: 'Assigned Patients',
            subtitle:
                '${_workspaceCounts.assignedPatients} '
                'active patient assignment(s).',
            badgeText:
                _workspaceCounts.assignedPatients
                    .toString(),
            onTap: () {
              _openSection(_NurseSection.patients);
            },
          ),
          const SizedBox(
            height: 12,
          ),
         
          _NurseActionCard(
            icon: Icons.monitor_heart_outlined,
            title: 'Observations and Vitals',
            subtitle:
                'Record observations and vital signs '
                'for assigned patients.',
            onTap: () {
              _openSection(_NurseSection.observations);
            },
          ),

          const SizedBox(height: 12),

          _NurseActionCard(
            icon: Icons.monitor_heart_sharp,
            title: 'Vital Signs Simulator',
            subtitle:
                'Practise monitoring patient vital signs '
      'using simulated readings and emergency scenarios.',
            onTap: () {
              _openSection(_NurseSection.vitalSigns);
            },
          ),

          const SizedBox(height: 12),

          _NurseActionCard(
            icon: Icons.science_outlined,
            title: 'Specimen Collection',
            subtitle:
                'Collect doctor-requested specimens and create '
                'secure QR container labels for the laboratory.',
            onTap: () {
              _openSection(_NurseSection.specimens);
            },
          ),

          const SizedBox(
            height: 12,
          ),
          _NurseActionCard(
            icon: Icons.task_alt_outlined,
            title: 'Nursing Tasks',
            subtitle:
                '${_workspaceCounts.activeTasks} '
                'active nursing task(s).',
            badgeText:
                _workspaceCounts.activeTasks
                    .toString(),
            onTap: () {
              _openSection(_NurseSection.tasks);
            },
          ),
          const SizedBox(
            height: 12,
          ),
          _NurseActionCard(
            icon: Icons.medication_outlined,
            title: 'Medication Rounds',
            subtitle: _workspaceCounts.activeMedications == null
                ? 'Active prescription count unavailable.'
                : '${_workspaceCounts.activeMedications} '
                    'active prescription(s) for assigned patients.',
            badgeText: _workspaceCounts.activeMedications?.toString(),
            onTap: () {
              _openSection(_NurseSection.medications);
            },
          ),
          if (_workspaceCounts.activeMedications == null)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: _loadDashboard,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry prescription count'),
              ),
            ),
          const SizedBox(
            height: 12,
          ),
          _NurseActionCard(
            icon: Icons.settings_outlined,
            title: 'Settings',
            subtitle:
                'Appearance, accessibility, notifications, '
                'biometrics and device permissions.',
            onTap: () {
              _openSection(_NurseSection.settings);
            },
          ),
          if (_canSwitchMode) ...[
            const SizedBox(
              height: 12,
            ),
            _NurseActionCard(
              icon: Icons.swap_horiz_rounded,
              title: 'Switch Mode',
              subtitle:
                  'Return to mode selection and continue '
                  'as a patient.',
              onTap: _switchMode,
            ),
          ],
          const SizedBox(
            height: 24,
          ),
        ],
      ),
    );
  }

  // ==========================================================================
  // WELCOME CARD
  // ==========================================================================

  Widget _buildWelcomeCard(
    NurseContext nurseContext,
  ) {
    return Container(
      padding: const EdgeInsets.all(
        20,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF1E3A8A),
            const Color(0xFF2563EB),
          ],
        ),
        borderRadius: BorderRadius.circular(
          22,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(
              alpha: 0.08,
            ),
            blurRadius: 18,
            offset: const Offset(
              0,
              8,
            ),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (
          context,
          constraints,
        ) {
          final compact =
              constraints.maxWidth < 430;

          final avatar =
              const CircleAvatar(
            radius: 31,
            backgroundColor: Colors.white,
            child: Icon(
              Icons.badge_outlined,
              size: 32,
              color: Color(
                0xFF0F766E,
              ),
            ),
          );

          final details =
              Expanded(
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                const Text(
                  'Welcome back',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(
                  height: 3,
                ),
                Text(
                  nurseContext.nurseName,
                  maxLines: 1,
                  overflow:
                      TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 21,
                    fontWeight:
                        FontWeight.bold,
                  ),
                ),
                if (nurseContext
                    .email
                    .trim()
                    .isNotEmpty) ...[
                  const SizedBox(
                    height: 3,
                  ),
                  Text(
                    nurseContext.email,
                    maxLines: 1,
                    overflow:
                        TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          );

          final badge = Container(
            padding:
                const EdgeInsets.symmetric(
              horizontal: 11,
              vertical: 7,
            ),
            decoration: BoxDecoration(
              color: Colors.white.withValues(
                alpha: 0.16,
              ),
              borderRadius:
                  BorderRadius.circular(
                99,
              ),
            ),
            child: Text(
              _prettyRole(
                nurseContext.role,
              ),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight:
                    FontWeight.bold,
              ),
            ),
          );

          if (compact) {
            return Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    avatar,
                    const SizedBox(
                      width: 15,
                    ),
                    details,
                  ],
                ),
                const SizedBox(
                  height: 14,
                ),
                badge,
              ],
            );
          }

          return Row(
            children: [
              avatar,
              const SizedBox(
                width: 15,
              ),
              details,
              const SizedBox(
                width: 12,
              ),
              badge,
            ],
          );
        },
      ),
    );
  }

  // ==========================================================================
  // HOSPITAL CONTEXT
  // ==========================================================================

  Widget _buildHospitalContextCard(
    NurseContext nurseContext,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(
        16,
      ),
      decoration: BoxDecoration(
        color: context.cBgSecondary,
        borderRadius: BorderRadius.circular(
          18,
        ),
        border: Border.all(
          color: CorviaColors.accent.withValues(
            alpha: 0.28,
          ),
        ),
      ),
      child: Row(
        children: [
          Container(
            height: 47,
            width: 47,
            decoration: BoxDecoration(
              color: CorviaColors.accent.withValues(
                alpha: 0.12,
              ),
              borderRadius: BorderRadius.circular(
                14,
              ),
            ),
            child: Icon(
              Icons.local_hospital_outlined,
              color: context.cAccentReadable,
            ),
          ),
          const SizedBox(
            width: 13,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                Text(
                  nurseContext.hospitalName,
                  style: TextStyle(
                    color: context.cTextPrimary,
                    fontSize: 15,
                    fontWeight:
                        FontWeight.bold,
                  ),
                ),
                const SizedBox(
                  height: 3,
                ),
                Text(
                  'Active hospital nurse workspace',
                  style: TextStyle(
                    color: context.cTextSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Icon(
            Icons.verified_outlined,
            color: CorviaColors.success,
          ),
        ],
      ),
    );
  }

  // ==========================================================================
  // SHIFT SUMMARY
  // ==========================================================================

  Widget _buildShiftSummary() {
    if (_activeShift == null) {
      return Material(
        color: context.cBgSecondary,
        borderRadius: BorderRadius.circular(
          18,
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () {
            _openSection(_NurseSection.shifts);
          },
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(
              18,
            ),
            decoration: BoxDecoration(
              borderRadius:
                  BorderRadius.circular(
                18,
              ),
              border: Border.all(
                color: context.cDivider,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.access_time_outlined,
                  color: CorviaColors.warning,
                  size: 34,
                ),
                const SizedBox(
                  width: 13,
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                      Text(
                        'You are not clocked in',
                        style: TextStyle(
                          color:
                              context.cTextPrimary,
                          fontSize: 16,
                          fontWeight:
                              FontWeight.bold,
                        ),
                      ),
                      const SizedBox(
                        height: 4,
                      ),
                      Text(
                        'Open Shift Management to start '
                        'your hospital shift.',
                        style: TextStyle(
                          color:
                              context.cTextSecondary,
                          fontSize: 13,
                        ),
                      ),
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
      );
    }

    final status = _activeShift?['status']
            ?.toString()
            .trim()
            .toLowerCase() ??
        'active';

    final onBreak =
        status == 'on_break';

    return Material(
      color: context.cBgSecondary,
      borderRadius: BorderRadius.circular(
        18,
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          _openSection(_NurseSection.shifts);
        },
        child: Container(
          padding: const EdgeInsets.all(
            18,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(
              18,
            ),
            border: Border.all(
              color: (onBreak
                      ? CorviaColors.warning
                      : CorviaColors.success)
                  .withValues(
                alpha: 0.35,
              ),
            ),
          ),
          child: Column(
            crossAxisAlignment:
                CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    onBreak
                        ? Icons
                            .pause_circle_outline
                        : Icons
                            .check_circle_outline,
                    color: onBreak
                        ? CorviaColors.warning
                        : CorviaColors.success,
                    size: 32,
                  ),
                  const SizedBox(
                    width: 11,
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment.start,
                      children: [
                        Text(
                          onBreak
                              ? 'Currently on break'
                              : 'Currently on shift',
                          style: TextStyle(
                            color:
                                context.cTextPrimary,
                            fontSize: 16,
                            fontWeight:
                                FontWeight.bold,
                          ),
                        ),
                        const SizedBox(
                          height: 3,
                        ),
                        Text(
                          '${_activeShift?['ward'] ?? 'Unknown Ward'} • '
                          '${_activeShift?['shift_type'] ?? 'Nurse Shift'}',
                          style: TextStyle(
                            color:
                                context.cTextSecondary,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right,
                    color: context.cTextMuted,
                  ),
                ],
              ),
              const SizedBox(
                height: 14,
              ),
              Row(
                children: [
                  Expanded(
                    child: _ShiftInfoBox(
                      label: 'Clocked in',
                      value: _formatDateTime(
                        _activeShift?[
                            'clock_in_at'],
                      ),
                    ),
                  ),
                  const SizedBox(
                    width: 10,
                  ),
                  Expanded(
                    child: _ShiftInfoBox(
                      label: 'Duration',
                      value:
                          _currentShiftDuration(),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ==========================================================================
  // ERROR STATES
  // ==========================================================================

  Widget _buildErrorState() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(
          24,
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: 520,
          ),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(
              24,
            ),
            decoration: BoxDecoration(
              color: context.cBgSecondary,
              borderRadius:
                  BorderRadius.circular(
                22,
              ),
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
                const SizedBox(
                  height: 16,
                ),
                Text(
                  'Could not load Nurse Dashboard',
                  textAlign:
                      TextAlign.center,
                  style: TextStyle(
                    color:
                        context.cTextPrimary,
                    fontSize: 21,
                    fontWeight:
                        FontWeight.bold,
                  ),
                ),
                const SizedBox(
                  height: 12,
                ),
                SelectableText(
                  _errorMessage ??
                      'Unknown nurse dashboard error.',
                  textAlign:
                      TextAlign.center,
                  style: TextStyle(
                    color:
                        context.cTextSecondary,
                    fontSize: 14,
                    height: 1.4,
                  ),
                ),
                const SizedBox(
                  height: 20,
                ),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed:
                        _loadDashboard,
                    icon: const Icon(
                      Icons.refresh_rounded,
                    ),
                    label: const Text(
                      'Try Again',
                    ),
                  ),
                ),
                const SizedBox(
                  height: 10,
                ),
                SizedBox(
                  width: double.infinity,
                  child:
                      OutlinedButton.icon(
                    onPressed:
                        _isSigningOut
                            ? null
                            : _signOut,
                    icon: const Icon(
                      Icons.logout_rounded,
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

  Widget _buildMissingContextState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(
          24,
        ),
        child: Text(
          'The nurse hospital context could not be resolved.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: context.cTextSecondary,
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// ACTION CARD
// =============================================================================

class _NurseActionCard extends StatelessWidget {
  const _NurseActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.badgeText,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final String? badgeText;

  @override
  Widget build(
    BuildContext context,
  ) {
    return Material(
      color: context.cBgSecondary,
      borderRadius: BorderRadius.circular(
        18,
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(
          18,
        ),
        child: Container(
          padding: const EdgeInsets.all(
            17,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(
              18,
            ),
            border: Border.all(
              color: context.cDivider,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 53,
                height: 53,
                decoration: BoxDecoration(
                  color: CorviaColors.accent
                      .withValues(
                    alpha: 0.12,
                  ),
                  borderRadius:
                      BorderRadius.circular(
                    15,
                  ),
                ),
                child: Icon(
                  icon,
                  color: CorviaColors.accent,
                  size: 29,
                ),
              ),
              const SizedBox(
                width: 14,
              ),
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
                        fontSize: 16,
                        fontWeight:
                            FontWeight.bold,
                      ),
                    ),
                    const SizedBox(
                      height: 4,
                    ),
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
              if (badgeText != null) ...[
                Container(
                  padding:
                      const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: CorviaColors.accent
                        .withValues(
                      alpha: 0.12,
                    ),
                    borderRadius:
                        BorderRadius.circular(
                      99,
                    ),
                  ),
                  child: Text(
                    badgeText!,
                    style: TextStyle(
                      color:
                          context.cAccentReadable,
                      fontWeight:
                          FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
                const SizedBox(
                  width: 8,
                ),
              ],
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

// =============================================================================
// SHIFT INFO
// =============================================================================

class _ShiftInfoBox extends StatelessWidget {
  const _ShiftInfoBox({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(
    BuildContext context,
  ) {
    return Container(
      padding: const EdgeInsets.all(
        11,
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
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: context.cTextSecondary,
              fontSize: 11,
            ),
          ),
          const SizedBox(
            height: 4,
          ),
          Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: context.cTextPrimary,
              fontSize: 13,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

/// Tracks content routes without moving the surrounding nurse sidebar.
class _NurseNavigationObserver extends NavigatorObserver {
  _NurseNavigationObserver(this.onChanged);

  final void Function(List<Route<dynamic>>) onChanged;
  final List<Route<dynamic>> _routes = [];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.add(route);
    onChanged(_routes);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.remove(route);
    onChanged(_routes);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.remove(route);
    onChanged(_routes);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final index = oldRoute == null ? -1 : _routes.indexOf(oldRoute);
    if (index >= 0) {
      if (newRoute == null) {
        _routes.removeAt(index);
      } else {
        _routes[index] = newRoute;
      }
    }
    onChanged(_routes);
  }
}
