import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/reception_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/staff_workspace_shell.dart';
import '../../widgets/workspace_navigation.dart';
import '../forms/corvia_forms_navigator.dart';
import '../shared/settings.dart';

import 'reception_booking_page.dart';
import 'reception_patient_search.dart';
import 'reception_qr_check_in_page.dart';
import 'reception_queue_page.dart';
import 'reception_walk_in_qr_page.dart';
import 'specialist/reception_specialist_requests_page.dart';

class ReceptionDashboard extends StatefulWidget {
  const ReceptionDashboard({
    super.key,
  });

  @override
  State<ReceptionDashboard> createState() {
    return _ReceptionDashboardState();
  }
}

class _ReceptionDashboardState extends State<ReceptionDashboard>
    with WorkspaceNavigation<ReceptionDashboard> {
  final ReceptionService _service = ReceptionService();

  ReceptionDashboardData? _dashboard;

  String? _receptionHospitalId;

  bool _openingForms = false;
  bool _loading = true;

  String? _error;

  @override
  void initState() {
    super.initState();

    _loadDashboard();
  }

  // ==========================================================================
  // DASHBOARD
  // ==========================================================================

  Future<void> _loadDashboard() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      /*
       * IMPORTANT:
       *
       * Reception hospital context is now resolved by the
       * database-authoritative RPC through ReceptionService.
       *
       * No direct profile/reception table guessing lives in
       * the dashboard anymore.
       */
      final hospitalContext =
          await _service.resolveHospitalContext();

      if (!hospitalContext.signedIn) {
        throw Exception(
          'Reception session has expired.',
        );
      }

      if (!hospitalContext.profileFound) {
        throw Exception(
          'Reception profile could not be resolved.',
        );
      }

      if (!hospitalContext.hospitalFound ||
          hospitalContext.hospitalId.trim().isEmpty) {
        throw Exception(
          'Reception hospital context could not be resolved. '
          'This reception account must be linked to a hospital.',
        );
      }

      final dashboard =
          await _service.loadDashboard();

      if (!mounted) {
        return;
      }

      setState(() {
        _receptionHospitalId =
            hospitalContext.hospitalId.trim();

        _dashboard = dashboard;
      });
    } catch (error) {
      debugPrint(
        'Reception dashboard load failed: $error',
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _error = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  // ==========================================================================
  // NAVIGATION
  // ==========================================================================

  Future<void> _openSearch(
    ReceptionPatientSearchMode mode,
  ) async {
    final changed =
        await pushWorkspace<bool>(
      MaterialPageRoute<bool>(
        builder: (_) {
          return ReceptionPatientSearchPage(
            mode: mode,
          );
        },
      ),
      label: mode == ReceptionPatientSearchMode.walkIn
          ? 'New Walk-In'
          : 'Search Patient',
    );

    if (!mounted) {
      return;
    }

    if (changed == true) {
      await _loadDashboard();
    }
  }

  Future<void> _openQueue() async {
    await pushWorkspace<void>(
      MaterialPageRoute<void>(
        builder: (_) {
          return const ReceptionQueuePage();
        },
      ),
      label: 'View Queue',
    );

    if (!mounted) {
      return;
    }

    await _loadDashboard();
  }

  Future<void> _openBooking() async {
    final changed =
        await pushWorkspace<bool>(
      MaterialPageRoute<bool>(
        builder: (_) {
          return const ReceptionBookingPage();
        },
      ),
      label: 'Book Appointment',
    );

    if (!mounted) {
      return;
    }

    if (changed == true) {
      await _loadDashboard();
    }
  }

  Future<void> _openQrCheckIn() async {
    final changed =
        await pushWorkspace<bool>(
      MaterialPageRoute<bool>(
        builder: (_) {
          return const ReceptionQrCheckInPage();
        },
      ),
      label: 'Scan QR',
    );

    if (!mounted) {
      return;
    }

    if (changed == true) {
      await _loadDashboard();
    }
  }

  Future<void> _openWalkInQr() async {
    await pushWorkspace<void>(
      MaterialPageRoute<void>(
        builder: (_) {
          return const ReceptionWalkInQrPage();
        },
      ),
      label: 'Reception QR',
    );
  }

  Future<void> _openSettings() async {
    await pushWorkspace<void>(
      MaterialPageRoute<void>(
        builder: (_) {
          return const SettingsPage(showAppBar: false);
        },
      ),
      label: 'Settings',
    );
  }

  Future<void> _openSpecialistRequests() async {
    await pushWorkspace<void>(
      MaterialPageRoute<void>(
        builder: (_) {
          return const ReceptionSpecialistRequestsPage();
        },
      ),
      label: 'Specialist Requests',
    );

    if (!mounted) {
      return;
    }

    await _loadDashboard();
  }

  // ==========================================================================
  // ADMISSION / CONSENT FORMS
  // ==========================================================================

  Future<void> _openAdmissionConsentForms() async {
    if (_openingForms) {
      return;
    }

    final hospitalId =
        _receptionHospitalId?.trim();

    if (hospitalId == null ||
        hospitalId.isEmpty) {
      _showMessage(
        'Reception hospital context could not be resolved. '
        'Admission forms cannot be opened until this '
        'reception account is linked to a hospital.',
      );

      return;
    }

    setState(() {
      _openingForms = true;
    });

    try {
      final selection =
          await showModalBottomSheet<
              _ReceptionFormsPatientSelection>(
        context: context,
        isScrollControlled: true,
        backgroundColor:
            context.cBgSecondary,
        shape:
            const RoundedRectangleBorder(
          borderRadius:
              BorderRadius.vertical(
            top: Radius.circular(
              22,
            ),
          ),
        ),
        builder: (_) {
          return _ReceptionFormsPatientPickerSheet(
            hospitalId:
                hospitalId,
          );
        },
      );

      if (selection == null ||
          !mounted) {
        return;
      }

      workspaceHome();
      await CorviaFormsNavigator.openPatientForms(
        workspaceContext,
        routeName: 'Admission & Consent',
        patientId:
            selection.patientId,
        hospitalId:
            hospitalId,
        admissionId:
            selection.admissionId,
        contextType:
            'reception_admission',
        contextId:
            selection.admissionId ??
                selection.checkInId ??
                selection.patientId,
        title:
            'Admission & Consent Forms - '
            '${selection.patientName}',
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      _showMessage(
        'Could not open Admission & Consent Forms. '
        '$error',
      );
    } finally {
      if (mounted) {
        setState(() {
          _openingForms = false;
        });
      }
    }
  }

  // ==========================================================================
  // AUTH
  // ==========================================================================

  Future<void> _signOut() async {
    try {
      await Supabase.instance.client.auth.signOut();
    } on AuthException catch (error) {
      _showMessage(
        'Sign out failed: ${error.message}',
      );
    } catch (error) {
      _showMessage(
        'Sign out failed. $error',
      );
    }
  }

  // ==========================================================================
  // HELPERS
  // ==========================================================================

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

  String _cleanError(
    String error,
  ) {
    return error
        .replaceFirst(
          'Exception: ',
          '',
        )
        .replaceAll(
          'PostgrestException(message: ',
          '',
        )
        .replaceAll(
          ')',
          '',
        );
  }

  // ==========================================================================
  // BUILD
  // ==========================================================================

  @override
  Widget build(
    BuildContext context,
  ) {
    final hospitalName = _dashboard?.hospitalName;

    return StaffWorkspaceShell(
      workspaceName: 'Reception Desk',
      breadcrumb: 'Reception',
      pageTitle: workspaceTitle ?? 'Dashboard',
      subtitle: hospitalName == null || hospitalName.isEmpty
          ? 'Arrivals, check-ins, appointments and the waiting queue.'
          : '$hospitalName · arrivals, check-ins, appointments and the queue.',
      onSignOut: _signOut,
      headerActions: [
        if (workspaceCanPop)
          workspaceBackButton
        else
          OutlinedButton.icon(
            onPressed: _loading ? null : _loadDashboard,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Refresh'),
          ),
      ],
      items: [
        StaffShellItem(
          label: 'Dashboard',
          icon: Icons.dashboard_rounded,
          selected: !workspaceCanPop,
          onTap: workspaceHome,
        ),
        StaffShellItem(
          label: 'Scan QR',
          selected: workspaceSelection == 'Scan QR',
          icon: Icons.qr_code_scanner_rounded,
          onTap: _openQrCheckIn,
        ),
        StaffShellItem(
          label: 'Search Patient',
          selected: workspaceSelection == 'Search Patient',
          icon: Icons.search_rounded,
          onTap: () => _openSearch(ReceptionPatientSearchMode.browse),
        ),
        StaffShellItem(
          label: 'New Walk-In',
          selected: workspaceSelection == 'New Walk-In',
          icon: Icons.person_add_alt_1_rounded,
          onTap: () => _openSearch(ReceptionPatientSearchMode.walkIn),
        ),
        StaffShellItem(
          label: 'Reception QR',
          selected: workspaceSelection == 'Reception QR',
          icon: Icons.qr_code_2_rounded,
          onTap: _openWalkInQr,
        ),
        StaffShellItem(
          label: 'View Queue',
          selected: workspaceSelection == 'View Queue',
          icon: Icons.groups_rounded,
          onTap: _openQueue,
        ),
        StaffShellItem(
          label: 'Book Appointment',
          selected: workspaceSelection == 'Book Appointment',
          icon: Icons.event_available_rounded,
          onTap: _openBooking,
        ),
        StaffShellItem(
          label: 'Specialist Requests',
          selected: workspaceSelection == 'Specialist Requests',
          icon: Icons.health_and_safety_outlined,
          onTap: _openSpecialistRequests,
        ),
        StaffShellItem(
          label: 'Admission & Consent',
          selected: workspaceSelection == 'Admission & Consent',
          icon: Icons.description_outlined,
          busy: _openingForms,
          onTap: _openAdmissionConsentForms,
        ),
        StaffShellItem(
          label: 'Settings',
          selected: workspaceSelection == 'Settings',
          icon: Icons.settings_rounded,
          onTap: _openSettings,
        ),
      ],
      body: workspaceBody(RefreshIndicator(
        color: CorviaColors.accent,
        onRefresh: _loadDashboard,
        child: _buildBody(),
      )),
    );
  }

  Widget _buildBody() {
    if (_loading &&
        _dashboard == null) {
      return const Center(
        child:
            CircularProgressIndicator(),
      );
    }

    if (_error != null &&
        _dashboard == null) {
      return ListView(
        physics:
            const AlwaysScrollableScrollPhysics(),
        padding:
            const EdgeInsets.all(
          24,
        ),
        children: [
          const SizedBox(
            height: 100,
          ),
          Icon(
            Icons.cloud_off_rounded,
            size: 64,
            color:
                Colors.red.shade400,
          ),
          const SizedBox(
            height: 18,
          ),
          Text(
            'Reception dashboard could not load.',
            textAlign:
                TextAlign.center,
            style:
                TextStyle(
              color:
                  context.cTextPrimary,
              fontSize: 20,
              fontWeight:
                  FontWeight.w800,
            ),
          ),
          const SizedBox(
            height: 10,
          ),
          Text(
            _cleanError(
              _error!,
            ),
            textAlign:
                TextAlign.center,
            style:
                TextStyle(
              color:
                  context.cTextSecondary,
            ),
          ),
          const SizedBox(
            height: 20,
          ),
          FilledButton.icon(
            onPressed:
                _loadDashboard,
            icon:
                const Icon(
              Icons.refresh_rounded,
            ),
            label:
                const Text(
              'Try Again',
            ),
          ),
        ],
      );
    }

    final dashboard =
        _dashboard;

    if (dashboard == null) {
      return const SizedBox.shrink();
    }

    return ListView(
      physics:
          const AlwaysScrollableScrollPhysics(),
      padding:
          const EdgeInsets.all(
        16,
      ),
      children: [
        _header(
          dashboard,
        ),
        const SizedBox(
          height: 18,
        ),
        _stats(
          dashboard,
        ),
        const SizedBox(
          height: 24,
        ),
        _quickActions(),
        const SizedBox(
          height: 24,
        ),
        _queuePreview(
          dashboard,
        ),
        const SizedBox(
          height: 22,
        ),
        _privacyNote(),
        const SizedBox(
          height: 20,
        ),
      ],
    );
  }

  // ==========================================================================
  // HEADER
  // ==========================================================================

  Widget _header(
    ReceptionDashboardData dashboard,
  ) {
    final date =
        DateFormat(
      'EEEE, d MMMM yyyy',
    ).format(
      DateTime.now(),
    );

    return Container(
      padding:
          const EdgeInsets.all(
        20,
      ),
      decoration:
          BoxDecoration(
        gradient:
            LinearGradient(
          colors: [
            CorviaColors.accentDark,
            CorviaColors.accent,
          ],
        ),
        borderRadius:
            BorderRadius.circular(
          20,
        ),
      ),
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.support_agent_rounded,
            size: 36,
            color: Colors.white,
          ),
          const SizedBox(
            height: 14,
          ),
          const Text(
            'Reception Command Centre',
            style:
                TextStyle(
              color:
                  Colors.white,
              fontSize: 23,
              fontWeight:
                  FontWeight.w800,
            ),
          ),
          const SizedBox(
            height: 5,
          ),
          Text(
            dashboard.hospitalName,
            style:
                const TextStyle(
              color:
                  Colors.white,
              fontWeight:
                  FontWeight.w600,
            ),
          ),
          const SizedBox(
            height: 3,
          ),
          Text(
            date,
            style:
                TextStyle(
              color:
                  Colors.white.withValues(
                alpha:
                    0.85,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================================================
  // STATS
  // ==========================================================================

  Widget _stats(
    ReceptionDashboardData dashboard,
  ) {
    return LayoutBuilder(
      builder: (
        context,
        constraints,
      ) {
        int columns;

        if (constraints.maxWidth >=
            1100) {
          columns = 5;
        } else if (constraints.maxWidth >=
            650) {
          columns = 3;
        } else {
          columns = 2;
        }

        return GridView.count(
          crossAxisCount:
              columns,
          shrinkWrap:
              true,
          physics:
              const NeverScrollableScrollPhysics(),
          mainAxisSpacing:
              12,
          crossAxisSpacing:
              12,
          mainAxisExtent:
              150,
          children: [
            _statCard(
              title:
                  'Check-Ins Today',
              value:
                  dashboard.checkInsToday.toString(),
              icon:
                  Icons.fact_check_rounded,
              color:
                  CorviaColors.accent,
            ),
            _statCard(
              title:
                  'Patients Waiting',
              value:
                  dashboard.patientsWaiting.toString(),
              icon:
                  Icons.people_alt_rounded,
              color:
                  Colors.deepPurple,
            ),
            _statCard(
              title:
                  'Urgent Patients',
              value:
                  dashboard.urgentPatients.toString(),
              icon:
                  Icons.priority_high_rounded,
              color:
                  Colors.red,
            ),
            _statCard(
              title:
                  'Appointments Today',
              value:
                  dashboard.appointmentsToday.toString(),
              icon:
                  Icons.calendar_month_rounded,
              color:
                  Colors.teal,
            ),
            _statCard(
              title:
                  'Walk-Ins Today',
              value:
                  dashboard.walkInsToday.toString(),
              icon:
                  Icons.directions_walk_rounded,
              color:
                  Colors.orange.shade800,
            ),
          ],
        );
      },
    );
  }

  Widget _statCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding:
          const EdgeInsets.all(
        14,
      ),
      decoration:
          BoxDecoration(
        color:
            context.cBgSecondary,
        borderRadius:
            BorderRadius.circular(
          17,
        ),
        border:
            Border.all(
          color:
              color.withValues(
            alpha: 0.28,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            color:
                color,
          ),
          const Spacer(),
          Text(
            value,
            style:
                TextStyle(
              color:
                  context.cTextPrimary,
              fontWeight:
                  FontWeight.w800,
              fontSize: 28,
            ),
          ),
          const SizedBox(
            height: 2,
          ),
          Text(
            title,
            maxLines: 2,
            overflow:
                TextOverflow.ellipsis,
            style:
                TextStyle(
              color:
                  context.cTextSecondary,
              fontSize: 12,
              fontWeight:
                  FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================================================
  // QUICK ACTIONS
  // ==========================================================================

  Widget _quickActions() {
    return Column(
      crossAxisAlignment:
          CrossAxisAlignment.start,
      children: [
        Text(
          'Quick Actions',
          style:
              TextStyle(
            color:
                context.cTextPrimary,
            fontSize: 19,
            fontWeight:
                FontWeight.w800,
          ),
        ),
        const SizedBox(
          height: 12,
        ),
        LayoutBuilder(
          builder: (
            context,
            constraints,
          ) {
            int columns;

            if (constraints.maxWidth >=
                1250) {
              columns = 8;
            } else if (constraints.maxWidth >=
                850) {
              columns = 4;
            } else if (constraints.maxWidth >=
                550) {
              columns = 3;
            } else {
              columns = 2;
            }

            return GridView.count(
              crossAxisCount:
                  columns,
              shrinkWrap:
                  true,
              physics:
                  const NeverScrollableScrollPhysics(),
              crossAxisSpacing:
                  10,
              mainAxisSpacing:
                  10,
              mainAxisExtent:
                  135,
              children: [
                _action(
                  label:
                      'Scan QR',
                  icon:
                      Icons.qr_code_scanner_rounded,
                  color:
                      CorviaColors.accent,
                  onTap:
                      _openQrCheckIn,
                ),
                _action(
                  label:
                      'Search Patient',
                  icon:
                      Icons.search_rounded,
                  color:
                      Colors.deepPurple,
                  onTap: () {
                    _openSearch(
                      ReceptionPatientSearchMode.browse,
                    );
                  },
                ),
                _action(
                  label:
                      'New Walk-In',
                  icon:
                      Icons.person_add_alt_1_rounded,
                  color:
                      Colors.orange.shade800,
                  onTap: () {
                    _openSearch(
                      ReceptionPatientSearchMode.walkIn,
                    );
                  },
                ),
                _action(
                  label:
                      'Reception QR',
                  icon:
                      Icons.qr_code_2_rounded,
                  color:
                      Colors.indigo,
                  onTap:
                      _openWalkInQr,
                ),
                _action(
                  label:
                      'View Queue',
                  icon:
                      Icons.groups_rounded,
                  color:
                      Colors.teal,
                  onTap:
                      _openQueue,
                ),
                _action(
                  label:
                      'Book Appointment',
                  icon:
                      Icons.event_available_rounded,
                  color:
                      Colors.green.shade700,
                  onTap:
                      _openBooking,
                ),
                _action(
                  label:
                      'Specialist Requests',
                  icon:
                      Icons.health_and_safety_outlined,
                  color:
                      Colors.deepPurpleAccent,
                  onTap:
                      _openSpecialistRequests,
                ),
                _action(
                  label:
                      'Admission & Consent',
                  icon:
                      Icons.description_outlined,
                  color:
                      Colors.blue.shade700,
                  onTap:
                      _openAdmissionConsentForms,
                ),
                _action(
                  label:
                      'Refresh',
                  icon:
                      Icons.refresh_rounded,
                  color:
                      Colors.blueGrey,
                  onTap:
                      _loadDashboard,
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _action({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap:
          onTap,
      borderRadius:
          BorderRadius.circular(
        16,
      ),
      child: Ink(
        decoration:
            BoxDecoration(
          color:
              context.cBgSecondary,
          borderRadius:
              BorderRadius.circular(
            16,
          ),
          border:
              Border.all(
            color:
                color.withValues(
              alpha: 0.24,
            ),
          ),
        ),
        child: Padding(
          padding:
              const EdgeInsets.all(
            10,
          ),
          child: Column(
            mainAxisAlignment:
                MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                color:
                    color,
                size:
                    28,
              ),
              const SizedBox(
                height: 8,
              ),
              Text(
                label,
                textAlign:
                    TextAlign.center,
                maxLines: 2,
                overflow:
                    TextOverflow.ellipsis,
                style:
                    TextStyle(
                  color:
                      context.cTextPrimary,
                  fontSize: 12,
                  fontWeight:
                      FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ==========================================================================
  // QUEUE PREVIEW
  // ==========================================================================

  Widget _queuePreview(
    ReceptionDashboardData dashboard,
  ) {
    return Column(
      crossAxisAlignment:
          CrossAxisAlignment.start,
      children: [
        Text(
          'Today’s Queue Preview',
          style:
              TextStyle(
            color:
                context.cTextPrimary,
            fontSize: 19,
            fontWeight:
                FontWeight.w800,
          ),
        ),
        const SizedBox(
          height: 4,
        ),
        Text(
          'Urgent patients appear first, then appointment '
          'and check-in time.',
          style:
              TextStyle(
            color:
                context.cTextSecondary,
            fontSize: 13,
          ),
        ),
        const SizedBox(
          height: 12,
        ),
        if (dashboard.queuePreview.isEmpty)
          _emptyQueue()
        else
          ...dashboard.queuePreview.map(
            _queueCard,
          ),
      ],
    );
  }

  Widget _emptyQueue() {
    return Container(
      width:
          double.infinity,
      padding:
          const EdgeInsets.all(
        22,
      ),
      decoration:
          BoxDecoration(
        color:
            context.cBgSecondary,
        borderRadius:
            BorderRadius.circular(
          16,
        ),
        border:
            Border.all(
          color:
              CorviaColors.divider,
        ),
      ),
      child: Column(
        children: [
          Icon(
            Icons.event_seat_outlined,
            color:
                context.cTextSecondary,
            size: 40,
          ),
          const SizedBox(
            height: 10,
          ),
          Text(
            'No check-ins for today yet.',
            style:
                TextStyle(
              color:
                  context.cTextPrimary,
              fontWeight:
                  FontWeight.w800,
            ),
          ),
          const SizedBox(
            height: 5,
          ),
          Text(
            'Patients will appear here after Reception checks them in.',
            textAlign:
                TextAlign.center,
            style:
                TextStyle(
              color:
                  context.cTextSecondary,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  Widget _queueCard(
    ReceptionQueueItem item,
  ) {
    final color =
        _statusColor(
      item,
    );

    final checkedIn =
        item.checkedInAt == null
            ? 'Unknown'
            : DateFormat(
                'HH:mm',
              ).format(
                item.checkedInAt!,
              );

    final appointment =
        item.appointmentTime == null
            ? 'Walk-in'
            : DateFormat(
                'HH:mm',
              ).format(
                item.appointmentTime!,
              );

    return Container(
      margin:
          const EdgeInsets.only(
        bottom: 10,
      ),
      padding:
          const EdgeInsets.all(
        15,
      ),
      decoration:
          BoxDecoration(
        color:
            context.cBgSecondary,
        borderRadius:
            BorderRadius.circular(
          16,
        ),
        border:
            Border.all(
          color:
              item.isUrgent
                  ? Colors.red.withValues(
                      alpha: 0.8,
                    )
                  : CorviaColors.divider,
          width:
              item.isUrgent
                  ? 1.5
                  : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  item.patientName,
                  style:
                      TextStyle(
                    color:
                        context.cTextPrimary,
                    fontSize:
                        16,
                    fontWeight:
                        FontWeight.w800,
                  ),
                ),
              ),
              _badge(
                item.isUrgent
                    ? 'URGENT'
                    : _prettyStatus(
                        item.queueStatus,
                      ),
                item.isUrgent
                    ? Colors.red
                    : color,
              ),
            ],
          ),
          const SizedBox(
            height: 5,
          ),
          Text(
            item.patientNumber,
            style:
                TextStyle(
              color:
                  context.cTextSecondary,
              fontSize: 12,
            ),
          ),
          const SizedBox(
            height: 11,
          ),
          Wrap(
            spacing: 14,
            runSpacing: 8,
            children: [
              _detail(
                Icons.local_hospital_rounded,
                item.departmentName,
              ),
              _detail(
                Icons.person_outline_rounded,
                item.doctorName,
              ),
              _detail(
                Icons.login_rounded,
                'Checked in $checkedIn',
              ),
              _detail(
                Icons.event_rounded,
                'Appointment $appointment',
              ),
              if (item.isWalkIn)
                _detail(
                  Icons.directions_walk_rounded,
                  'Walk-in',
                ),
            ],
          ),
          const SizedBox(
            height: 10,
          ),
          Text(
            item.visitReason,
            style:
                TextStyle(
              color:
                  context.cTextPrimary,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  Widget _detail(
    IconData icon,
    String text,
  ) {
    return Row(
      mainAxisSize:
          MainAxisSize.min,
      children: [
        Icon(
          icon,
          size:
              15,
          color:
              context.cTextSecondary,
        ),
        const SizedBox(
          width: 5,
        ),
        ConstrainedBox(
          constraints:
              const BoxConstraints(
            maxWidth:
                190,
          ),
          child: Text(
            text,
            overflow:
                TextOverflow.ellipsis,
            style:
                TextStyle(
              color:
                  context.cTextSecondary,
              fontSize: 12,
            ),
          ),
        ),
      ],
    );
  }

  Widget _badge(
    String label,
    Color color,
  ) {
    return Container(
      padding:
          const EdgeInsets.symmetric(
        horizontal: 9,
        vertical: 5,
      ),
      decoration:
          BoxDecoration(
        color:
            color.withValues(
          alpha: 0.13,
        ),
        borderRadius:
            BorderRadius.circular(
          20,
        ),
      ),
      child: Text(
        label,
        style:
            TextStyle(
          color:
              color,
          fontSize: 11,
          fontWeight:
              FontWeight.w800,
        ),
      ),
    );
  }

  Color _statusColor(
    ReceptionQueueItem item,
  ) {
    final status =
        item.queueStatus.toLowerCase();

    if (item.isUrgent ||
        status.contains(
          'emergency',
        )) {
      return Colors.red;
    }

    if (status.contains(
      'completed',
    )) {
      return Colors.green;
    }

    if (status.contains(
      'called',
    )) {
      return Colors.deepPurple;
    }

    if (status.contains(
      'doctor',
    )) {
      return Colors.teal;
    }

    if (status.contains(
          'cancel',
        ) ||
        status.contains(
          'no show',
        ) ||
        status.contains(
          'no_show',
        )) {
      return Colors.grey;
    }

    return Colors.orange.shade800;
  }

  String _prettyStatus(
    String value,
  ) {
    if (value.trim().isEmpty) {
      return 'Waiting';
    }

    return value
        .replaceAll(
          '_',
          ' ',
        )
        .split(
          RegExp(
            r'\s+',
          ),
        )
        .where(
          (word) =>
              word.isNotEmpty,
        )
        .map(
          (word) =>
              '${word[0].toUpperCase()}'
              '${word.substring(1).toLowerCase()}',
        )
        .join(
          ' ',
        );
  }

  // ==========================================================================
  // PRIVACY
  // ==========================================================================

  Widget _privacyNote() {
    return Container(
      padding:
          const EdgeInsets.all(
        16,
      ),
      decoration:
          BoxDecoration(
        color:
            Colors.blue.withValues(
          alpha: 0.09,
        ),
        borderRadius:
            BorderRadius.circular(
          16,
        ),
        border:
            Border.all(
          color:
              Colors.blue.withValues(
            alpha: 0.28,
          ),
        ),
      ),
      child: Row(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.privacy_tip_outlined,
            color:
                Colors.blue,
          ),
          const SizedBox(
            width: 12,
          ),
          Expanded(
            child: Text(
              'Reception manages arrivals, appointments, queue status '
              'and admission/consent forms permitted for the reception '
              'role. Private consultation notes and AI chats are not '
              'displayed here.',
              style:
                  TextStyle(
                color:
                    context.cTextPrimary,
                fontSize: 13,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// ADMISSION FORM PATIENT PICKER
// =============================================================================

class _ReceptionFormsPatientSelection {
  const _ReceptionFormsPatientSelection({
    required this.patientId,
    required this.patientName,
    this.admissionId,
    this.checkInId,
  });

  final String patientId;
  final String patientName;

  final String? admissionId;
  final String? checkInId;
}

class _ReceptionFormsPatientRecord {
  const _ReceptionFormsPatientRecord({
    required this.patientId,
    required this.patientName,
    required this.patientNumber,
    this.checkInId,
  });

  final String patientId;
  final String patientName;
  final String patientNumber;

  final String? checkInId;
}

class _ReceptionFormsPatientPickerSheet
    extends StatefulWidget {
  const _ReceptionFormsPatientPickerSheet({
    required this.hospitalId,
  });

  final String hospitalId;

  @override
  State<_ReceptionFormsPatientPickerSheet>
      createState() {
    return _ReceptionFormsPatientPickerSheetState();
  }
}

class _ReceptionFormsPatientPickerSheetState
    extends State<_ReceptionFormsPatientPickerSheet> {
  final SupabaseClient _supabase =
      Supabase.instance.client;

  final TextEditingController _searchController =
      TextEditingController();

  bool _loading = true;
  bool _opening = false;

  String _search = '';

  String? _error;
  String? _openingPatientId;

  List<_ReceptionFormsPatientRecord> _patients =
      const [];

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
  // PATIENT LOADING
  // ==========================================================================

  Future<void> _loadPatients() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final patientRows =
          await _loadHospitalPatients();

      final patientIds =
          patientRows
              .map(
                (row) =>
                    row['id']
                        ?.toString()
                        .trim(),
              )
              .whereType<String>()
              .where(
                (id) =>
                    id.isNotEmpty,
              )
              .toSet();

      final profileNames =
          await _loadProfileNames(
        patientRows,
      );

      final checkIns =
          await _loadCurrentCheckIns(
        patientIds,
      );

      final records =
          <_ReceptionFormsPatientRecord>[];

      for (final patient
          in patientRows) {
        final patientId =
            patient['id']
                ?.toString()
                .trim();

        if (patientId == null ||
            patientId.isEmpty) {
          continue;
        }

        final profileId =
            patient['profile_id']
                ?.toString()
                .trim();

        final directName =
            _firstReceptionText(
          [
            patient['full_name'],
            patient['display_name'],
            patient['name'],
          ],
          fallback:
              '',
        );

        // patients.first_name/surname is readable by reception even when
        // the linked profile is not; skip the "Corvia Patient" placeholder.
        final patientRowName =
            '${_firstReceptionText([patient['first_name']], fallback: '')} '
                    '${_firstReceptionText([patient['surname'], patient['last_name']], fallback: '')}'
                .trim();

        String patientName;

        if (directName.isNotEmpty) {
          patientName =
              directName;
        } else if (patientRowName.isNotEmpty &&
            patientRowName.toLowerCase() !=
                'corvia patient') {
          patientName =
              patientRowName;
        } else if (profileId != null &&
            profileNames.containsKey(
              profileId,
            )) {
          patientName =
              profileNames[
                  profileId]!;
        } else {
          patientName =
              _fallbackPatientName(
            patientId,
          );
        }

        final patientNumber =
            _firstReceptionText(
          [
            patient['patient_number'],
            patient['patient_no'],
            patient['record_number'],
            patient['medical_record_number'],
            patient['mrn'],
          ],
          fallback:
              _shortReceptionId(
            patientId,
          ),
        );

        final checkIn =
            checkIns[
                patientId];

        records.add(
          _ReceptionFormsPatientRecord(
            patientId:
                patientId,
            patientName:
                patientName,
            patientNumber:
                patientNumber,
            checkInId:
                checkIn?['id']
                    ?.toString(),
          ),
        );
      }

      records.sort(
        (
          first,
          second,
        ) {
          return first.patientName
              .toLowerCase()
              .compareTo(
                second.patientName
                    .toLowerCase(),
              );
        },
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _patients =
            records;
        _loading =
            false;
      });
    } catch (error) {
      debugPrint(
        'Reception Forms patient picker failed: $error',
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _patients =
            const [];
        _loading =
            false;
        _error =
            error.toString();
      });
    }
  }

  Future<List<Map<String, dynamic>>>
      _loadHospitalPatients() async {
    /*
     * Preferred newer schema:
     * patients.hospital_id
     */
    try {
      final response =
          await _supabase
              .from(
                'patients',
              )
              .select()
              .eq(
                'hospital_id',
                widget.hospitalId,
              )
              .limit(
                500,
              );

      return _mapReceptionRows(
        response,
      );
    } catch (directError) {
      debugPrint(
        'Direct hospital patient lookup failed: '
        '$directError',
      );
    }

    /*
     * Multi-hospital compatibility:
     * patient_hospital_links
     */
    try {
      final linksResponse =
          await _supabase
              .from(
                'patient_hospital_links',
              )
              .select()
              .eq(
                'hospital_id',
                widget.hospitalId,
              );

      final links =
          _mapReceptionRows(
        linksResponse,
      );

      final patientIds =
          links
              .map(
                (row) =>
                    row['patient_id']
                        ?.toString()
                        .trim(),
              )
              .whereType<String>()
              .where(
                (id) =>
                    id.isNotEmpty,
              )
              .toSet()
              .toList();

      if (patientIds.isEmpty) {
        return [];
      }

      final patientResponse =
          await _supabase
              .from(
                'patients',
              )
              .select()
              .inFilter(
                'id',
                patientIds,
              );

      return _mapReceptionRows(
        patientResponse,
      );
    } catch (linkError) {
      throw Exception(
        'Hospital patients could not be loaded. '
        '$linkError',
      );
    }
  }

  Future<Map<String, String>> _loadProfileNames(
    List<Map<String, dynamic>> patients,
  ) async {
    final profileIds =
        patients
            .map(
              (row) =>
                  row['profile_id']
                      ?.toString()
                      .trim(),
            )
            .whereType<String>()
            .where(
              (id) =>
                  id.isNotEmpty,
            )
            .toSet();

    if (profileIds.isEmpty) {
      return {};
    }

    final names =
        <String, String>{};

    try {
      final response =
          await _supabase
              .from(
                'profiles',
              )
              .select()
              .inFilter(
                'id',
                profileIds.toList(),
              );

      for (final profile
          in _mapReceptionRows(
        response,
      )) {
        final profileId =
            profile['id']
                ?.toString()
                .trim();

        if (profileId == null ||
            profileId.isEmpty) {
          continue;
        }

        names[profileId] =
            _profileReceptionName(
          profile,
        );
      }
    } catch (error) {
      debugPrint(
        'Reception profile-name lookup by id failed: $error',
      );
    }

    final missingIds =
        profileIds
            .where(
              (id) =>
                  !names.containsKey(
                    id,
                  ),
            )
            .toList();

    if (missingIds.isNotEmpty) {
      try {
        final response =
            await _supabase
                .from(
                  'profiles',
                )
                .select()
                .inFilter(
                  'user_id',
                  missingIds,
                );

        for (final profile
            in _mapReceptionRows(
          response,
        )) {
          final userId =
              profile['user_id']
                  ?.toString()
                  .trim();

          if (userId == null ||
              userId.isEmpty) {
            continue;
          }

          names[userId] =
              _profileReceptionName(
            profile,
          );
        }
      } catch (error) {
        debugPrint(
          'Reception legacy profile-name lookup failed: $error',
        );
      }
    }

    return names;
  }

  Future<Map<String, Map<String, dynamic>>>
      _loadCurrentCheckIns(
    Set<String> patientIds,
  ) async {
    if (patientIds.isEmpty) {
      return {};
    }

    try {
      final now =
          DateTime.now();

      final startOfDay =
          DateTime(
        now.year,
        now.month,
        now.day,
      ).toUtc();

      final response =
          await _supabase
              .from(
                'reception_checkins',
              )
              .select()
              .eq(
                'hospital_id',
                widget.hospitalId,
              )
              .gte(
                'created_at',
                startOfDay
                    .toIso8601String(),
              )
              .inFilter(
                'patient_id',
                patientIds.toList(),
              );

      final rows =
          _mapReceptionRows(
        response,
      );

      final map =
          <String, Map<String, dynamic>>{};

      rows.sort(
        (
          first,
          second,
        ) {
          final firstDate =
              _receptionDate(
                    first,
                    const [
                      'checked_in_at',
                      'created_at',
                    ],
                  ) ??
                  DateTime(
                    1970,
                  );

          final secondDate =
              _receptionDate(
                    second,
                    const [
                      'checked_in_at',
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

      for (final row
          in rows) {
        final patientId =
            row['patient_id']
                ?.toString()
                .trim();

        if (patientId == null ||
            patientId.isEmpty) {
          continue;
        }

        map.putIfAbsent(
          patientId,
          () => row,
        );
      }

      return map;
    } catch (error) {
      debugPrint(
        'Reception check-in context lookup failed: $error',
      );

      return {};
    }
  }

  // ==========================================================================
  // FILTER
  // ==========================================================================

  List<_ReceptionFormsPatientRecord>
      get _filteredPatients {
    final query =
        _search
            .trim()
            .toLowerCase();

    if (query.isEmpty) {
      return _patients;
    }

    return _patients.where(
      (
        patient,
      ) {
        return patient.patientName
                .toLowerCase()
                .contains(
                  query,
                ) ||
            patient.patientNumber
                .toLowerCase()
                .contains(
                  query,
                ) ||
            patient.patientId
                .toLowerCase()
                .contains(
                  query,
                );
      },
    ).toList();
  }

  // ==========================================================================
  // SELECT PATIENT
  // ==========================================================================

  Future<void> _selectPatient(
    _ReceptionFormsPatientRecord patient,
  ) async {
    if (_opening) {
      return;
    }

    setState(() {
      _opening = true;
      _openingPatientId =
          patient.patientId;
    });

    try {
      final admissionId =
          await _resolveReceptionAdmission(
        supabase:
            _supabase,
        hospitalId:
            widget.hospitalId,
        patientId:
            patient.patientId,
      );

      if (!mounted) {
        return;
      }

      Navigator.of(context).pop(
        _ReceptionFormsPatientSelection(
          patientId:
              patient.patientId,
          patientName:
              patient.patientName,
          admissionId:
              admissionId,
          checkInId:
              patient.checkInId,
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _opening =
            false;
        _openingPatientId =
            null;
      });

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content:
                Text(
              'Could not open patient forms. $error',
            ),
          ),
        );
    }
  }

  // ==========================================================================
  // BUILD
  // ==========================================================================

  @override
  Widget build(
    BuildContext context,
  ) {
    final keyboardHeight =
        MediaQuery.of(context)
            .viewInsets
            .bottom;

    return SafeArea(
      child: Padding(
        padding:
            EdgeInsets.fromLTRB(
          16,
          12,
          16,
          16 +
              keyboardHeight,
        ),
        child: SizedBox(
          height:
              MediaQuery.sizeOf(
                    context,
                  ).height *
                  0.78,
          child: Column(
            crossAxisAlignment:
                CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width:
                      44,
                  height:
                      4,
                  decoration:
                      BoxDecoration(
                    color:
                        context.cTextMuted,
                    borderRadius:
                        BorderRadius.circular(
                      99,
                    ),
                  ),
                ),
              ),
              const SizedBox(
                height: 18,
              ),
              Row(
                children: [
                  Container(
                    width:
                        46,
                    height:
                        46,
                    decoration:
                        BoxDecoration(
                      color:
                          CorviaColors.accent.withValues(
                        alpha: 0.14,
                      ),
                      borderRadius:
                          BorderRadius.circular(
                        13,
                      ),
                    ),
                    child:
                        Icon(
                      Icons.description_outlined,
                      color:
                          context.cAccentReadable,
                    ),
                  ),
                  const SizedBox(
                    width: 12,
                  ),
                  Expanded(
                    child:
                        Column(
                      crossAxisAlignment:
                          CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Admission & Consent Forms',
                          style:
                              TextStyle(
                            color:
                                context.cTextPrimary,
                            fontSize:
                                20,
                            fontWeight:
                                FontWeight.bold,
                          ),
                        ),
                        const SizedBox(
                          height: 3,
                        ),
                        Text(
                          'Select a hospital patient to open '
                          'their admission documentation.',
                          style:
                              TextStyle(
                            color:
                                context.cTextSecondary,
                            fontSize:
                                13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip:
                        'Close',
                    onPressed:
                        _opening
                            ? null
                            : () {
                                Navigator.of(
                                  context,
                                ).pop();
                              },
                    icon:
                        const Icon(
                      Icons.close,
                    ),
                  ),
                ],
              ),
              const SizedBox(
                height: 16,
              ),
              TextField(
                controller:
                    _searchController,
                enabled:
                    !_opening,
                onChanged: (
                  value,
                ) {
                  setState(() {
                    _search =
                        value
                            .trim()
                            .toLowerCase();
                  });
                },
                decoration:
                    InputDecoration(
                  labelText:
                      'Search patient',
                  hintText:
                      'Name, patient number or ID',
                  prefixIcon:
                      const Icon(
                    Icons.search,
                  ),
                  suffixIcon:
                      _searchController
                              .text
                              .isEmpty
                          ? null
                          : IconButton(
                              onPressed:
                                  () {
                                _searchController.clear();

                                setState(() {
                                  _search = '';
                                });
                              },
                              icon:
                                  const Icon(
                                Icons.clear,
                              ),
                            ),
                  border:
                      const OutlineInputBorder(),
                ),
              ),
              const SizedBox(
                height: 12,
              ),
              Expanded(
                child:
                    _buildPatientBody(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPatientBody() {
    if (_loading) {
      return const Center(
        child:
            CircularProgressIndicator(),
      );
    }

    if (_error != null) {
      return Center(
        child:
            SingleChildScrollView(
          child: Column(
            mainAxisSize:
                MainAxisSize.min,
            children: [
              const Icon(
                Icons.error_outline,
                color:
                    Colors.redAccent,
                size:
                    50,
              ),
              const SizedBox(
                height: 12,
              ),
              Text(
                _error!
                    .replaceFirst(
                  'Exception: ',
                  '',
                ),
                textAlign:
                    TextAlign.center,
                style:
                    TextStyle(
                  color:
                      context.cTextSecondary,
                ),
              ),
              const SizedBox(
                height: 15,
              ),
              FilledButton.icon(
                onPressed:
                    _loadPatients,
                icon:
                    const Icon(
                  Icons.refresh,
                ),
                label:
                    const Text(
                  'Try Again',
                ),
              ),
            ],
          ),
        ),
      );
    }

    final patients =
        _filteredPatients;

    if (_patients.isEmpty) {
      return Center(
        child:
            Column(
          mainAxisSize:
              MainAxisSize.min,
          children: [
            Icon(
              Icons.people_outline,
              color:
                  context.cTextMuted,
              size:
                  54,
            ),
            const SizedBox(
              height: 12,
            ),
            Text(
              'No hospital patients found',
              style:
                  TextStyle(
                color:
                    context.cTextPrimary,
                fontSize:
                    18,
                fontWeight:
                    FontWeight.bold,
              ),
            ),
          ],
        ),
      );
    }

    if (patients.isEmpty) {
      return Center(
        child:
            Column(
          mainAxisSize:
              MainAxisSize.min,
          children: [
            Icon(
              Icons.search_off,
              color:
                  context.cTextMuted,
              size:
                  50,
            ),
            const SizedBox(
              height: 10,
            ),
            Text(
              'No matching patients',
              style:
                  TextStyle(
                color:
                    context.cTextPrimary,
                fontWeight:
                    FontWeight.bold,
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh:
          _loadPatients,
      child:
          ListView.separated(
        physics:
            const AlwaysScrollableScrollPhysics(),
        itemCount:
            patients.length,
        separatorBuilder: (
          context,
          index,
        ) {
          return const SizedBox(
            height: 8,
          );
        },
        itemBuilder: (
          context,
          index,
        ) {
          final patient =
              patients[index];

          final opening =
              _openingPatientId ==
                  patient.patientId;

          return Card(
            margin:
                EdgeInsets.zero,
            color:
                context.cBgPrimary,
            child:
                ListTile(
              enabled:
                  !_opening,
              contentPadding:
                  const EdgeInsets.symmetric(
                horizontal:
                    14,
                vertical:
                    5,
              ),
              leading:
                  CircleAvatar(
                backgroundColor:
                    CorviaColors.accent.withValues(
                  alpha:
                      0.14,
                ),
                child:
                    Text(
                  _patientInitials(
                    patient.patientName,
                  ),
                  style:
                      TextStyle(
                    color:
                        context.cAccentReadable,
                    fontWeight:
                        FontWeight.bold,
                  ),
                ),
              ),
              title:
                  Text(
                patient.patientName,
                style:
                    TextStyle(
                  color:
                      context.cTextPrimary,
                  fontWeight:
                      FontWeight.w600,
                ),
              ),
              subtitle:
                  Text(
                patient.checkInId != null
                    ? '${patient.patientNumber} • Checked in today'
                    : patient.patientNumber,
                style:
                    TextStyle(
                  color:
                      context.cTextSecondary,
                  fontSize:
                      12,
                ),
              ),
              trailing:
                  opening
                      ? const SizedBox(
                          width:
                              22,
                          height:
                              22,
                          child:
                              CircularProgressIndicator(
                            strokeWidth:
                                2,
                          ),
                        )
                      : const Icon(
                          Icons.chevron_right,
                        ),
              onTap:
                  () {
                _selectPatient(
                  patient,
                );
              },
            ),
          );
        },
      ),
    );
  }
}

// =============================================================================
// ACTIVE ADMISSION LOOKUP
// =============================================================================

Future<String?> _resolveReceptionAdmission({
  required SupabaseClient supabase,
  required String hospitalId,
  required String patientId,
}) async {
  try {
    final response =
        await supabase
            .from(
              'hospital_admissions',
            )
            .select()
            .eq(
              'hospital_id',
              hospitalId,
            )
            .eq(
              'patient_id',
              patientId,
            );

    final rows =
        _mapReceptionRows(
      response,
    );

    if (rows.isEmpty) {
      return null;
    }

    const priority =
        <String, int>{
      'admitted': 0,
      'active': 1,
      'in_progress': 2,
      'observation': 3,
      'planned': 4,
      'pending': 5,
    };

    rows.sort(
      (
        first,
        second,
      ) {
        final firstStatus =
            _normaliseReceptionValue(
          first['status'],
        );

        final secondStatus =
            _normaliseReceptionValue(
          second['status'],
        );

        final firstPriority =
            priority[firstStatus] ??
                100;

        final secondPriority =
            priority[secondStatus] ??
                100;

        if (firstPriority !=
            secondPriority) {
          return firstPriority.compareTo(
            secondPriority,
          );
        }

        final firstDate =
            _receptionDate(
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

        final secondDate =
            _receptionDate(
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

    for (final row
        in rows) {
      final status =
          _normaliseReceptionValue(
        row['status'],
      );

      if (!priority.containsKey(
        status,
      )) {
        continue;
      }

      final admissionId =
          row['id']
              ?.toString()
              .trim();

      if (admissionId != null &&
          admissionId.isNotEmpty) {
        return admissionId;
      }
    }

    return null;
  } catch (error) {
    debugPrint(
      'Reception active admission lookup failed: $error',
    );

    return null;
  }
}

// =============================================================================
// SHARED HELPERS
// =============================================================================

List<Map<String, dynamic>> _mapReceptionRows(
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

DateTime? _receptionDate(
  Map<String, dynamic> row,
  List<String> columns,
) {
  for (final column
      in columns) {
    final value =
        row[column];

    if (value == null) {
      continue;
    }

    final parsed =
        DateTime.tryParse(
      value.toString(),
    );

    if (parsed != null) {
      return parsed;
    }
  }

  return null;
}

String _normaliseReceptionValue(
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

String _firstReceptionText(
  List<dynamic> values, {
  required String fallback,
}) {
  for (final value
      in values) {
    if (value != null &&
        value
            .toString()
            .trim()
            .isNotEmpty) {
      return value
          .toString()
          .trim();
    }
  }

  return fallback;
}

String _profileReceptionName(
  Map<String, dynamic> profile,
) {
  final direct =
      _firstReceptionText(
    [
      profile['full_name'],
      profile['display_name'],
      profile['name'],
    ],
    fallback:
        '',
  );

  if (direct.isNotEmpty) {
    return direct;
  }

  final firstName =
      _firstReceptionText(
    [
      profile['first_name'],
      profile['firstname'],
      profile['given_name'],
    ],
    fallback:
        '',
  );

  final surname =
      _firstReceptionText(
    [
      profile['surname'],
      profile['last_name'],
      profile['lastname'],
      profile['family_name'],
    ],
    fallback:
        '',
  );

  final combined =
      '$firstName $surname'
          .trim();

  if (combined.isNotEmpty) {
    return combined;
  }

  return _firstReceptionText(
    [
      profile['email'],
    ],
    fallback:
        'Patient',
  );
}

String _shortReceptionId(
  String value,
) {
  final clean =
      value.trim();

  if (clean.length <=
      8) {
    return clean;
  }

  return clean.substring(
    0,
    8,
  );
}

String _fallbackPatientName(
  String patientId,
) {
  return 'Patient '
      '${_shortReceptionId(patientId)}';
}

String _patientInitials(
  String name,
) {
  final parts =
      name
          .trim()
          .split(
            RegExp(
              r'\s+',
            ),
          )
          .where(
            (
              part,
            ) =>
                part.isNotEmpty,
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
          part,
        ) =>
            part[0].toUpperCase(),
      )
      .join();
}
