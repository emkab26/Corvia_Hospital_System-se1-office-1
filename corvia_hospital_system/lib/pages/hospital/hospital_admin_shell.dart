import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../theme/app_theme.dart';
import '../blood_bank/blood_bank_page.dart';
import '../admin/hospital_admissions_page.dart';
import '../admin/hospital_bed_board_page.dart';
import '../admin/hospital_fleet_paramedic_page.dart';
import '../admin/hospital_structure_page.dart';
import '../admin/hospital_visitor_scanner_page.dart';
import '../admin/hospital_visitors_page.dart';
import '../admin/interhospital_transfers_page.dart';
import 'hospital_ai_booking_queue_page.dart';
import 'hospital_appointments_page.dart';
import 'hospital_billing_page.dart';
import 'hospital_departments_page.dart';
import 'hospital_doctors_page.dart';
import 'hospital_emergency_page.dart';
import 'hospital_lab_results_page.dart';
import 'hospital_lab_governance_page.dart';
import 'hospital_locations_page.dart';
import 'hospital_patients_page.dart';
import 'hospital_pharmacists_page.dart';
import 'hospital_qr_checkins_page.dart';
import 'hospital_reports_page.dart';
import 'hospital_settings_page.dart';
import 'hospital_staff_accounts_page.dart';
import '../../widgets/corvia_logo.dart';

enum HospitalAdminSection {
  dashboard,
  patients,
  doctors,
  pharmacists,
  staffAccounts,
  appointments,
  labResults,
  labGovernance,
  admissions,
  visitors,
  transfers,
  qrCheckins,
  aiBookingQueue,
  departments,
  structure,
  bedBoard,
  fleetParamedic,
  locations,
  emergency,
  bloodBank,
  billing,
  reports,
  settings,
  fleetManagement,
}

class HospitalAdminShell extends StatefulWidget {
  const HospitalAdminShell({
    super.key,
    required this.dashboardPage,
    this.initialSection = HospitalAdminSection.dashboard,
  });

  final Widget dashboardPage;
  final HospitalAdminSection initialSection;

  static void openSection(
    BuildContext context, {
    required HospitalAdminSection section,
    required Widget fallbackPage,
  }) {
    final shellState =
        context.findAncestorStateOfType<_HospitalAdminShellState>();

    if (shellState != null) {
      shellState._navigateTo(section);
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => fallbackPage,
      ),
    );
  }

  @override
  State<HospitalAdminShell> createState() => _HospitalAdminShellState();
}

class _HospitalAdminShellState extends State<HospitalAdminShell> {
  final GlobalKey<NavigatorState> _pageNavigatorKey =
      GlobalKey<NavigatorState>();

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  late HospitalAdminSection _selectedSection;

  @override
  void initState() {
    super.initState();

    _selectedSection = widget.initialSection;
  }

  String get _pageTitle {
    switch (_selectedSection) {
      case HospitalAdminSection.dashboard:
        return 'Dashboard';

      case HospitalAdminSection.patients:
        return 'Patients';

      case HospitalAdminSection.doctors:
        return 'Doctors';

      case HospitalAdminSection.pharmacists:
        return 'Pharmacists';

      case HospitalAdminSection.staffAccounts:
        return 'Staff Accounts';

      case HospitalAdminSection.appointments:
        return 'Appointments';

      case HospitalAdminSection.labResults:
        return 'Lab Results';

      case HospitalAdminSection.labGovernance:
        return 'Laboratory Governance';

      case HospitalAdminSection.admissions:
        return 'Admissions';

      case HospitalAdminSection.visitors:
        return 'Visitor Access';

      case HospitalAdminSection.transfers:
        return 'Inter-Hospital Transfers';

      case HospitalAdminSection.qrCheckins:
        return 'QR Check-ins';

      case HospitalAdminSection.aiBookingQueue:
        return 'AI Booking Queue';

      case HospitalAdminSection.departments:
        return 'Departments';

      case HospitalAdminSection.structure:
        return 'Hospital Structure';

      case HospitalAdminSection.bedBoard:
        return 'Live Bed Board';

      case HospitalAdminSection.fleetParamedic:
        return 'Fleet Management';

      case HospitalAdminSection.locations:
        return 'Locations';

      case HospitalAdminSection.emergency:
        return 'Emergency';

      case HospitalAdminSection.bloodBank:
        return 'Blood Bank';

      case HospitalAdminSection.billing:
        return 'Billing';

      case HospitalAdminSection.reports:
        return 'Reports';

      case HospitalAdminSection.settings:
        return 'Settings';

      case HospitalAdminSection.fleetManagement:
        return 'Fleet Management';
    }
  }

  Widget _pageForSection(HospitalAdminSection section) {
    switch (section) {
      case HospitalAdminSection.dashboard:
        return widget.dashboardPage;

      case HospitalAdminSection.patients:
        return const HospitalPatientsPage();

      case HospitalAdminSection.doctors:
        return const HospitalDoctorsPage();

      case HospitalAdminSection.pharmacists:
        return const HospitalPharmacistsPage();

      case HospitalAdminSection.staffAccounts:
        return const HospitalStaffAccountsPage();

      case HospitalAdminSection.appointments:
        return const HospitalAppointmentsPage();

      case HospitalAdminSection.labResults:
        return const _HospitalLabResultsContextPage();

      case HospitalAdminSection.labGovernance:
        return const HospitalLabGovernancePage();

      case HospitalAdminSection.admissions:
        return const HospitalAdmissionsPage();

      case HospitalAdminSection.visitors:
        return const HospitalVisitorsPage();

      case HospitalAdminSection.transfers:
        return const InterhospitalTransfersPage();

      case HospitalAdminSection.qrCheckins:
        return const HospitalQrCheckinsPage();

      case HospitalAdminSection.aiBookingQueue:
        return HospitalAiBookingQueuePage(
          onBack: () => _navigateTo(HospitalAdminSection.dashboard),
        );

      case HospitalAdminSection.departments:
        return const HospitalDepartmentsPage();

      case HospitalAdminSection.structure:
        return const HospitalStructurePage();

      case HospitalAdminSection.bedBoard:
        return const HospitalBedBoardPage();

      case HospitalAdminSection.fleetParamedic:
        return const HospitalFleetParamedicPage();

      case HospitalAdminSection.locations:
        return const HospitalLocationsPage();

      case HospitalAdminSection.emergency:
        return const HospitalEmergencyPage();

      case HospitalAdminSection.bloodBank:
        return const BloodBankPage(showAppBar: false);

      case HospitalAdminSection.billing:
        return HospitalBillingPage(
          onBack: () => _navigateTo(HospitalAdminSection.dashboard),
        );

      case HospitalAdminSection.reports:
        return HospitalReportsPage(
          onBack: () => _navigateTo(HospitalAdminSection.dashboard),
        );

      case HospitalAdminSection.settings:
        return const HospitalSettingsPage();

      case HospitalAdminSection.fleetManagement:
        // Legacy entry stays safe, but no longer opens sample preview data.
        return const HospitalFleetParamedicPage();
    }
  }

  void _navigateTo(HospitalAdminSection section) {
    if (_selectedSection == section) {
      if (_scaffoldKey.currentState?.isDrawerOpen == true) {
        Navigator.of(context).pop();
      }

      return;
    }

    setState(() {
      _selectedSection = section;
    });

    _pageNavigatorKey.currentState?.pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => _pageForSection(section),
      ),
      (route) => false,
    );
  }

  void _openVisitorScanner() {
    _pageNavigatorKey.currentState?.push(
      MaterialPageRoute(
        builder: (_) => const HospitalVisitorScannerPage(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (
        context,
        constraints,
      ) {
        final isWide = constraints.maxWidth >= 1050;

        if (isWide) {
          return Scaffold(
            backgroundColor: context.cBgPrimary,
            body: SafeArea(
              child: Row(
                children: [
                  _buildSidebar(context),
                  Expanded(
                    child: Column(
                      children: [
                        _buildPageHeader(context),
                        Expanded(
                          child: _buildPageNavigator(),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        return Scaffold(
          key: _scaffoldKey,
          backgroundColor: context.cBgPrimary,
          drawer: Drawer(
            backgroundColor: Colors.transparent,
            child: SafeArea(
              child: _buildSidebar(
                context,
                compact: true,
              ),
            ),
          ),
          body: SafeArea(
            child: Column(
              children: [
                _buildPageHeader(
                  context,
                  showMenuButton: true,
                ),
                Expanded(
                  child: _buildPageNavigator(),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildPageNavigator() {
    return NavigatorPopHandler<Object?>(
        onPopWithResult: (result) =>
            _pageNavigatorKey.currentState?.pop(result),
        child: Navigator(
          key: _pageNavigatorKey,
          onGenerateInitialRoutes: (
            _,
            __,
          ) {
            return [
              MaterialPageRoute(
                builder: (_) => _pageForSection(
                  _selectedSection,
                ),
              ),
            ];
          },
          onGenerateRoute: (_) {
            return MaterialPageRoute(
              builder: (_) => _pageForSection(
                _selectedSection,
              ),
            );
          },
        ));
  }

  Widget _buildPageHeader(
    BuildContext context, {
    bool showMenuButton = false,
  }) {
    return LayoutBuilder(
      builder: (
        context,
        constraints,
      ) {
        final compact = constraints.maxWidth < 900;

        final titleSection = Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (showMenuButton) ...[
              Semantics(
                button: true,
                label: 'Open hospital navigation menu',
                child: Material(
                  color: context.cBgPrimary,
                  borderRadius: BorderRadius.circular(12),
                  child: IconButton(
                    tooltip: 'Hospital menu',
                    onPressed: () {
                      _scaffoldKey.currentState?.openDrawer();
                    },
                    icon: Icon(
                      Icons.menu_rounded,
                      color: context.cAccentReadable,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Hospital Admin / $_pageTitle',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: context.cTextPrimary,
                      fontSize: compact ? 18 : 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    _headerSubtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: context.cTextSecondary,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ],
        );

        final headerActions = Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (_selectedSection == HospitalAdminSection.dashboard)
              OutlinedButton.icon(
                onPressed: () {
                  _navigateTo(
                    HospitalAdminSection.labGovernance,
                  );
                },
                icon: const Icon(
                  Icons.admin_panel_settings_outlined,
                ),
                label: const Text(
                  'Laboratory',
                ),
              ),
            if (_selectedSection == HospitalAdminSection.dashboard)
              OutlinedButton.icon(
                onPressed: () {
                  _navigateTo(
                    HospitalAdminSection.visitors,
                  );
                },
                icon: const Icon(
                  Icons.badge_rounded,
                ),
                label: const Text(
                  'Visitor Access',
                ),
              ),
            if (_selectedSection == HospitalAdminSection.dashboard)
              FilledButton.tonalIcon(
                onPressed: _openVisitorScanner,
                icon: const Icon(
                  Icons.qr_code_scanner_rounded,
                ),
                label: const Text(
                  'Scan Visitor',
                ),
              ),
            if (_selectedSection == HospitalAdminSection.dashboard)
              FilledButton.tonalIcon(
                onPressed: () {
                  _navigateTo(
                    HospitalAdminSection.transfers,
                  );
                },
                icon: const Icon(
                  Icons.compare_arrows_rounded,
                ),
                label: const Text(
                  'Transfers',
                ),
              ),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 7,
              ),
              decoration: BoxDecoration(
                color: context.cAccentReadable.withValues(
                  alpha: 0.10,
                ),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: context.cAccentReadable.withValues(
                    alpha: 0.22,
                  ),
                ),
              ),
              child: Text(
                context.isDarkTheme ? 'Dark mode' : 'Light mode',
                style: TextStyle(
                  color: context.cAccentReadable,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        );

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(
            horizontal: 22,
            vertical: 16,
          ),
          decoration: BoxDecoration(
            color: context.cBgSecondary,
            border: Border(
              bottom: BorderSide(
                color: context.cDivider,
              ),
            ),
          ),
          child: compact
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    titleSection,
                    const SizedBox(height: 12),
                    headerActions,
                  ],
                )
              : Row(
                  children: [
                    Expanded(
                      child: titleSection,
                    ),
                    const SizedBox(width: 16),
                    headerActions,
                  ],
                ),
        );
      },
    );
  }

  String get _headerSubtitle {
    switch (_selectedSection) {
      case HospitalAdminSection.dashboard:
        return 'Live hospital operations, admissions, beds, visitors and patient transfers.';

      case HospitalAdminSection.labResults:
        return 'Review released and in-progress laboratory work across the hospital.';

      case HospitalAdminSection.labGovernance:
        return 'Manage internal laboratory leadership and outsourced laboratory availability.';

      case HospitalAdminSection.transfers:
        return 'Manage incoming and outgoing patient transfers between hospitals.';

      case HospitalAdminSection.visitors:
        return 'Manage visitor passes, restrictions, check-ins and check-outs.';

      case HospitalAdminSection.admissions:
        return 'Manage planned admissions, active admissions and patient discharge.';

      case HospitalAdminSection.bedBoard:
        return 'View and manage the live hospital bed allocation board.';

      case HospitalAdminSection.fleetParamedic:
        return 'Manage ambulances, EMS crews, shifts and paramedic dispatch.';

      case HospitalAdminSection.structure:
        return 'Manage buildings, floors, wards, rooms and beds.';

      case HospitalAdminSection.staffAccounts:
        return 'Link existing Corvia accounts to staff roles at this hospital.';

      case HospitalAdminSection.fleetManagement:
        return 'Manage authorised hospital Fleet vehicles and crews.';

      default:
        return 'You are currently viewing $_pageTitle.';
    }
  }

  Widget _buildSidebar(
    BuildContext context, {
    bool compact = false,
  }) {
    final sidebarColor = context.isDarkTheme
        ? Color.alphaBlend(
            CorviaColors.accentDark.withValues(
              alpha: 0.28,
            ),
            context.cBgPrimary,
          )
        : CorviaColors.accentDark;

    final items = [
      const _HospitalMenuItem(
        section: HospitalAdminSection.dashboard,
        icon: Icons.dashboard_rounded,
        label: 'Dashboard',
      ),
      const _HospitalMenuItem(
        section: HospitalAdminSection.patients,
        icon: Icons.people_alt_rounded,
        label: 'Patients',
      ),
      const _HospitalMenuItem(
        section: HospitalAdminSection.doctors,
        icon: Icons.medical_services_rounded,
        label: 'Doctors',
      ),
      const _HospitalMenuItem(
        section: HospitalAdminSection.pharmacists,
        icon: Icons.local_pharmacy_rounded,
        label: 'Pharmacists',
      ),
      const _HospitalMenuItem(
        section: HospitalAdminSection.staffAccounts,
        icon: Icons.manage_accounts_rounded,
        label: 'Staff Accounts',
      ),
      const _HospitalMenuItem(
        section: HospitalAdminSection.appointments,
        icon: Icons.calendar_month_rounded,
        label: 'Appointments',
      ),
      const _HospitalMenuItem(
        section: HospitalAdminSection.labResults,
        icon: Icons.science_rounded,
        label: 'Lab Results',
      ),
      const _HospitalMenuItem(
        section: HospitalAdminSection.labGovernance,
        icon: Icons.admin_panel_settings_outlined,
        label: 'Laboratory Governance',
      ),
      const _HospitalMenuItem(
        section: HospitalAdminSection.admissions,
        icon: Icons.hotel_rounded,
        label: 'Admissions',
      ),
      const _HospitalMenuItem(
        section: HospitalAdminSection.visitors,
        icon: Icons.badge_rounded,
        label: 'Visitor Access',
      ),
      const _HospitalMenuItem(
        section: HospitalAdminSection.transfers,
        icon: Icons.compare_arrows_rounded,
        label: 'Transfers',
      ),
      const _HospitalMenuItem(
        section: HospitalAdminSection.qrCheckins,
        icon: Icons.qr_code_scanner_rounded,
        label: 'QR Check-ins',
      ),
      const _HospitalMenuItem(
        section: HospitalAdminSection.aiBookingQueue,
        icon: Icons.auto_awesome_rounded,
        label: 'AI Booking Queue',
      ),
      const _HospitalMenuItem(
        section: HospitalAdminSection.departments,
        icon: Icons.local_hospital_rounded,
        label: 'Departments',
      ),
      const _HospitalMenuItem(
        section: HospitalAdminSection.structure,
        icon: Icons.account_tree_rounded,
        label: 'Hospital Structure',
      ),
      const _HospitalMenuItem(
        section: HospitalAdminSection.bedBoard,
        icon: Icons.bed_rounded,
        label: 'Live Bed Board',
      ),
      const _HospitalMenuItem(
        section: HospitalAdminSection.fleetParamedic,
        icon: Icons.local_shipping_rounded,
        label: 'Fleet Management',
      ),
      const _HospitalMenuItem(
        section: HospitalAdminSection.locations,
        icon: Icons.location_on_rounded,
        label: 'Locations',
      ),
      const _HospitalMenuItem(
        section: HospitalAdminSection.emergency,
        icon: Icons.emergency_rounded,
        label: 'Emergency',
      ),
      const _HospitalMenuItem(
        section: HospitalAdminSection.bloodBank,
        icon: Icons.bloodtype_outlined,
        label: 'Blood Bank',
      ),
      const _HospitalMenuItem(
        section: HospitalAdminSection.billing,
        icon: Icons.receipt_long_rounded,
        label: 'Billing',
      ),
      const _HospitalMenuItem(
        section: HospitalAdminSection.reports,
        icon: Icons.analytics_rounded,
        label: 'Reports',
      ),
      const _HospitalMenuItem(
        section: HospitalAdminSection.settings,
        icon: Icons.settings_rounded,
        label: 'Settings',
      ),
    ];

    return Container(
      width: compact ? 285 : 270,
      color: sidebarColor,
      padding: const EdgeInsets.fromLTRB(
        18,
        24,
        18,
        20,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(
                    alpha: 0.15,
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const CorviaLogo(size: 30, badge: true),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Corvia',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Hospital Command Centre',
            style: TextStyle(
              color: Colors.white.withValues(
                alpha: 0.72,
              ),
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 18),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(
                alpha: 0.10,
              ),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: Colors.white.withValues(
                  alpha: 0.20,
                ),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'CURRENT PAGE',
                  style: TextStyle(
                    color: Colors.white.withValues(
                      alpha: 0.64,
                    ),
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.1,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  _pageTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Expanded(
            child: ListView.separated(
              itemCount: items.length,
              separatorBuilder: (
                _,
                __,
              ) {
                return const SizedBox(height: 6);
              },
              itemBuilder: (
                context,
                index,
              ) {
                final item = items[index];
                final selected = item.section == _selectedSection;

                return Material(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(14),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () {
                      if (compact) {
                        Navigator.of(context).pop();
                      }

                      _navigateTo(item.section);
                    },
                    child: AnimatedContainer(
                      duration: const Duration(
                        milliseconds: 180,
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: selected
                            ? Colors.white.withValues(
                                alpha: 0.16,
                              )
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: selected
                              ? Colors.white.withValues(
                                  alpha: 0.30,
                                )
                              : Colors.transparent,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            item.icon,
                            size: 21,
                            color: selected
                                ? Colors.white
                                : Colors.white.withValues(
                                    alpha: 0.72,
                                  ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              item.label,
                              style: TextStyle(
                                color: selected
                                    ? Colors.white
                                    : Colors.white.withValues(
                                        alpha: 0.84,
                                      ),
                                fontSize: 14,
                                fontWeight: selected
                                    ? FontWeight.w900
                                    : FontWeight.w600,
                              ),
                            ),
                          ),
                          if (selected)
                            const Icon(
                              Icons.chevron_right_rounded,
                              color: Colors.white,
                              size: 20,
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white.withValues(
                alpha: 0.10,
              ),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: Colors.white.withValues(
                  alpha: 0.16,
                ),
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.verified_user_rounded,
                  color: Colors.white,
                  size: 21,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Secure hospital workspace',
                    style: TextStyle(
                      color: Colors.white.withValues(
                        alpha: 0.92,
                      ),
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HospitalLabResultsContextPage extends StatefulWidget {
  const _HospitalLabResultsContextPage();

  @override
  State<_HospitalLabResultsContextPage> createState() {
    return _HospitalLabResultsContextPageState();
  }
}

class _HospitalLabResultsContextPageState
    extends State<_HospitalLabResultsContextPage> {
  final SupabaseClient _supabase = Supabase.instance.client;

  bool _loading = true;

  String? _error;
  String? _hospitalId;

  String _hospitalName = 'Hospital';

  @override
  void initState() {
    super.initState();

    _loadHospitalContext();
  }

  Future<void> _loadHospitalContext() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
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

      final hospitalId = adminLink['hospital_id']?.toString().trim();

      if (hospitalId == null || hospitalId.isEmpty) {
        throw Exception(
          'Hospital admin record has no hospital ID.',
        );
      }

      var hospitalName = 'Hospital';

      final hospitalJoin = adminLink['hospitals'];

      if (hospitalJoin is Map && hospitalJoin['name'] != null) {
        hospitalName = hospitalJoin['name'].toString();
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _hospitalId = hospitalId;
        _hospitalName = hospitalName;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _loading = false;
        _error = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        backgroundColor: context.cBgPrimary,
        body: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (_error != null || _hospitalId == null || _hospitalId!.isEmpty) {
      return Scaffold(
        backgroundColor: context.cBgPrimary,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: 520,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.error_outline_rounded,
                    color: CorviaColors.danger,
                    size: 48,
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Lab Results could not be opened',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: context.cTextPrimary,
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _error ?? 'Hospital context is unavailable.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: context.cTextSecondary,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 18),
                  FilledButton.icon(
                    onPressed: _loadHospitalContext,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Try Again'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return HospitalLabResultsPage(
      hospitalId: _hospitalId!,
      hospitalName: _hospitalName,
    );
  }
}

class _HospitalMenuItem {
  const _HospitalMenuItem({
    required this.section,
    required this.icon,
    required this.label,
  });

  final HospitalAdminSection section;
  final IconData icon;
  final String label;
}
