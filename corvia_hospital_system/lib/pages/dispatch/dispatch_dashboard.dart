import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'response_workspace_page.dart';
import 'dispatch_voice_sessions_view.dart';
import 'dispatch_terminal_history_view.dart';
import '../../services/dispatch_terminal_history_service.dart';
import '../../services/dispatch_voice_session_reader.dart';

import '../../services/emergency_dispatch_service.dart';
import '../../services/settings_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/error_messages.dart';
import '../../widgets/incident_history_panel.dart';
import '../../widgets/incident_workspace_panel.dart';
import '../../services/incident_workspace_service.dart';
import '../../widgets/incident_location_panel.dart';
import '../shared/settings.dart';
import '../../widgets/corvia_logo.dart';
import '../../widgets/workspace_navigation.dart';

typedef IncomingEmergencyLoader = Future<List<DispatchEmergency>> Function();
typedef DispatchAccessLoader = Future<DispatchAccessContext> Function();
typedef IncomingEmergencyAccepter = Future<DispatchEmergency> Function(
  String incidentId,
);

enum DispatchAccessLevel {
  dispatcher,
  supervisor,
}

DispatchAccessLevel? dispatchAccessLevelForRole(
  String? value,
) {
  final role =
      value?.trim().toLowerCase().replaceAll('-', '_').replaceAll(' ', '_') ??
          '';

  if ({
    'dispatch_supervisor',
    'dispatcher_supervisor',
    'dispatchsupervisor',
    'ems_dispatch_supervisor',
  }.contains(role)) {
    return DispatchAccessLevel.supervisor;
  }

  if ({
    'dispatch',
    'dispatcher',
    'ems_dispatcher',
  }.contains(role)) {
    return DispatchAccessLevel.dispatcher;
  }

  return null;
}

class EmergencyDispatchDashboard extends StatefulWidget {
  const EmergencyDispatchDashboard({
    super.key,
    this.accessLevel = DispatchAccessLevel.dispatcher,
    this.accessLoader,
    this.incomingEmergencyAccepter,
    this.incomingEmergencyLoader,
    this.historyLoader,
    this.workspaceGateway,
    this.playIncomingAlert,
    this.voiceSessionGateway,
    this.terminalHistoryGateway,
    this.onSignOut,
  });

  // Profile-derived entry hint only. Server context grants dashboard access.
  final DispatchAccessLevel accessLevel;
  final DispatchAccessLoader? accessLoader;
  final IncomingEmergencyAccepter? incomingEmergencyAccepter;
  final IncomingEmergencyLoader? incomingEmergencyLoader;
  final IncidentHistoryLoader? historyLoader;
  final IncidentWorkspaceGateway? workspaceGateway;
  final Future<void> Function()? playIncomingAlert;
  final DispatchVoiceSessionGateway? voiceSessionGateway;
  final DispatchTerminalHistoryGateway? terminalHistoryGateway;
  final Future<void> Function()? onSignOut;

  @override
  State<EmergencyDispatchDashboard> createState() {
    return _EmergencyDispatchDashboardState();
  }
}

class _EmergencyDispatchDashboardState extends State<EmergencyDispatchDashboard>
    with WorkspaceNavigation<EmergencyDispatchDashboard> {
  _DispatchSection _selectedSection = _DispatchSection.liveOperations;

  _DispatchSection get _navigationSection =>
      _destinations
          .where((destination) => destination.label == workspaceSelection)
          .map((destination) => destination.section)
          .firstOrNull ??
      _selectedSection;
  final List<DispatchEmergency> _incomingEmergencies = [];
  DateTime? _lastRefreshed;
  String? _emergencyLoadError;
  String? _emergencyAcceptanceError;
  String? _selectedEmergencyId;
  Timer? _emergencyRefreshTimer;
  bool _isLoadingEmergencies = true;
  bool _isAcceptingEmergency = false;
  bool _isSigningOut = false;
  bool _readInFlight = false;
  bool _sessionEnded = false;
  int _generation = 0;
  DispatchAccessContext? _accessContext;
  final Set<String> _knownPendingIds = {};
  final Set<String> _newPendingIds = {};
  bool _hasQueueSnapshot = false;
  bool _soundEnabled = false;
  String? _soundError;
  AudioPlayer? _alertPlayer;

  // A local UI bound, matching the legacy queue; not a dispatch response SLA.
  static const _readTimeout = Duration(seconds: 15);

  bool get _queueReady =>
      mounted &&
      !_sessionEnded &&
      _accessContext?.canReadIncidents == true &&
      !_isLoadingEmergencies &&
      !_isAcceptingEmergency &&
      _emergencyLoadError == null &&
      _lastRefreshed != null;

  bool _ownsGeneration(int generation) =>
      mounted && !_sessionEnded && generation == _generation;

  bool _isJwtDenial(Object error) =>
      error is PostgrestException &&
      const ['PGRST301', 'PGRST302', 'PGRST303'].contains(error.code);

  bool _isAccessDenial(Object error) =>
      (error is AuthException &&
          const ['401', '403'].contains(error.statusCode)) ||
      (error is PostgrestException &&
          const ['401', '403', '42501'].contains(error.code)) ||
      _isJwtDenial(error);

  String _safeError(Object error, String operation) {
    if (error is DispatchAccessException) return '$operation $error';
    return _isJwtDenial(error)
        ? '$operation Your session has expired. Please sign in and try again.'
        : friendlyErrorMessage(error, whatFailed: operation);
  }

  void _startPolling() {
    _emergencyRefreshTimer?.cancel();
    if (!_queueReady) return;
    _emergencyRefreshTimer = Timer.periodic(_readTimeout, (_) {
      unawaited(_loadIncomingEmergencies(quiet: true));
    });
  }

  bool get _isSupervisor {
    return _accessContext?.isSupervisor == true;
  }

  Future<DispatchAccessContext> _loadAccess() =>
      (widget.accessLoader ?? EmergencyDispatchService().loadAccessContext)();

  bool _sameAccess(DispatchAccessContext? before, DispatchAccessContext after) {
    if (before == null ||
        before.userId != after.userId ||
        before.policyVersion != after.policyVersion ||
        before.canClaimIncident != after.canClaimIncident ||
        before.canReadIntakeDetails != after.canReadIntakeDetails ||
        before.canReadIncidentHistory != after.canReadIncidentHistory ||
        before.canUseIncidentWorkspace != after.canUseIncidentWorkspace ||
        before.canReadIncidents != after.canReadIncidents) {
      return false;
    }
    final oldScope = before.memberships
        .map((entry) => '${entry.organisationId}:${entry.role}')
        .toList()
      ..sort();
    final newScope = after.memberships
        .map((entry) => '${entry.organisationId}:${entry.role}')
        .toList()
      ..sort();
    return oldScope.join('|') == newScope.join('|');
  }

  String get _roleLabel {
    return _isSupervisor ? 'Dispatch Supervisor' : 'Dispatcher';
  }

  DispatchEmergency? get _selectedEmergency {
    final selectedId = _selectedEmergencyId;

    if (selectedId == null) {
      return null;
    }

    for (final emergency in _incomingEmergencies) {
      if (emergency.id == selectedId) {
        return emergency;
      }
    }

    return null;
  }

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadIncomingEmergencies();
    });
  }

  @override
  void dispose() {
    _sessionEnded = true;
    _generation++;
    _emergencyRefreshTimer?.cancel();
    unawaited(_disposeArrivalSound());
    super.dispose();
  }

  Future<void> _disposeArrivalSound() async {
    try {
      await _alertPlayer?.dispose();
    } catch (_) {
      // A sound-device failure must not interrupt dashboard teardown.
    }
  }

  Future<void> _stopArrivalSound() async {
    try {
      await _alertPlayer?.stop();
    } catch (_) {
      // The visual queue remains authoritative when audio fails.
    }
  }

  void _clearArrivalAlerts() {
    _knownPendingIds.clear();
    _newPendingIds.clear();
    _hasQueueSnapshot = false;
    _soundEnabled = false;
    _soundError = null;
    unawaited(_stopArrivalSound());
  }

  void _toggleArrivalSound() {
    if (!_queueReady) return;
    setState(() {
      _soundEnabled = !_soundEnabled;
      _soundError = null;
    });
    if (!_soundEnabled) {
      unawaited(_stopArrivalSound());
    }
  }

  Future<void> _playArrivalSound(int generation) async {
    if (!_soundEnabled || !_ownsGeneration(generation)) return;
    try {
      final play = widget.playIncomingAlert;
      if (play != null) {
        await play();
      } else {
        _alertPlayer ??= AudioPlayer();
        await _alertPlayer!.play(AssetSource('ringing.mp3'));
      }
      if (!_ownsGeneration(generation) || !_soundEnabled) {
        await _stopArrivalSound();
      }
    } catch (_) {
      if (!_ownsGeneration(generation) || !_soundEnabled) return;
      setState(() {
        _soundEnabled = false;
        _soundError = 'Sound unavailable. Watch the visible emergency queue.';
      });
    }
  }

  void _selectSection(
    _DispatchSection section, {
    bool closeDrawer = false,
  }) {
    if (closeDrawer && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
    if (const {
      _DispatchSection.activeIncidents,
      _DispatchSection.fleetAvailability,
      _DispatchSection.liveMap,
      _DispatchSection.completedIncidents,
      _DispatchSection.hospitals
    }.contains(section)) {
      pushWorkspace<void>(
          MaterialPageRoute<void>(
              builder: (_) => ResponseWorkspacePage(
                  incidentId: section == _DispatchSection.completedIncidents
                      ? null
                      : _selectedEmergencyId,
                  includeClosed:
                      section == _DispatchSection.completedIncidents)),
          label: _destinations
              .firstWhere((item) => item.section == section)
              .label);
      return;
    }
    workspaceHome();
    if (_selectedSection != section) {
      setState(() {
        _selectedSection = section;
      });
    }
  }

  void _openResponseWorkspace(
      {bool includeClosed = false, bool showAll = false}) {
    // The server still owns incident and operation authorisation. The UI
    // only exposes navigation when the current scoped access allows it.
    if (!_queueReady || _accessContext?.canUseIncidentWorkspace != true) {
      return;
    }
    pushWorkspace<void>(
      MaterialPageRoute<void>(
        builder: (_) => ResponseWorkspacePage(
          incidentId: includeClosed || showAll ? null : _selectedEmergencyId,
          includeClosed: includeClosed,
        ),
      ),
      label: 'Emergency response workspace',
    );
  }

  Future<void> _refreshDashboard() async {
    final expectedGeneration = _generation + 1;
    final refreshed = await _loadIncomingEmergencies();
    if (refreshed && _ownsGeneration(expectedGeneration)) {
      _showMessage('Incoming emergencies refreshed.');
    }
  }

  Future<bool> _loadIncomingEmergencies({bool quiet = false}) async {
    if (!mounted ||
        _sessionEnded ||
        _readInFlight ||
        _isAcceptingEmergency ||
        (quiet && _emergencyLoadError != null)) {
      return false;
    }
    final generation = ++_generation;
    _emergencyRefreshTimer?.cancel();
    setState(() {
      _readInFlight = true;
      _isLoadingEmergencies = true;
      _emergencyLoadError = null;
      _emergencyAcceptanceError = null;
    });
    var accessValidated = false;
    try {
      final emergencies = await (() async {
        final access = await _loadAccess();
        if (!_ownsGeneration(generation)) return <DispatchEmergency>[];
        setState(() {
          if (!_sameAccess(_accessContext, access)) {
            _incomingEmergencies.clear();
            _clearArrivalAlerts();
            _selectedEmergencyId = null;
            _lastRefreshed = null;
            _selectedSection = _DispatchSection.liveOperations;
          }
          _accessContext = access;
        });
        accessValidated = true;
        final loader = widget.incomingEmergencyLoader ??
            () => EmergencyDispatchService().loadIncomingEmergencies(
                  includeIntakeDetails: access.canReadIntakeDetails,
                  isCurrent: () => _ownsGeneration(generation),
                );
        final rows = await loader();
        if (!_ownsGeneration(generation)) return <DispatchEmergency>[];
        // Revocation can make RLS return a successful empty list. Recheck
        // before presenting it as an authorized snapshot, not just before I/O.
        accessValidated = false;
        final confirmedAccess = await _loadAccess();
        if (!_ownsGeneration(generation)) return <DispatchEmergency>[];
        if (!_sameAccess(access, confirmedAccess)) {
          throw const DispatchAccessException();
        }
        accessValidated = true;
        return rows;
      })()
          .timeout(_readTimeout);
      if (!_ownsGeneration(generation)) return false;
      final pendingIds = emergencies
          .where((incident) => incident.isPending && incident.hasValidIdentity)
          .map((incident) => incident.id)
          .toSet();
      final newlyDiscovered = _hasQueueSnapshot
          ? pendingIds.difference(_knownPendingIds)
          : <String>{};
      setState(() {
        _readInFlight = false;
        _incomingEmergencies
          ..clear()
          ..addAll(emergencies);
        _lastRefreshed = DateTime.now();
        _isLoadingEmergencies = false;
        _emergencyLoadError = null;
        _newPendingIds.retainAll(pendingIds);
        if (!_hasQueueSnapshot) _newPendingIds.addAll(pendingIds);
        _newPendingIds.addAll(newlyDiscovered);
        _knownPendingIds
          ..clear()
          ..addAll(pendingIds);
        _hasQueueSnapshot = true;
        if (!emergencies.any((item) => item.id == _selectedEmergencyId)) {
          _selectedEmergencyId =
              emergencies.isEmpty ? null : emergencies.first.id;
        }
      });
      _startPolling();
      if (newlyDiscovered.isNotEmpty) unawaited(_playArrivalSound(generation));
      return true;
    } catch (error) {
      if (!_ownsGeneration(generation)) return false;
      _failQueue(error, "Couldn't load incoming emergencies.",
          clearProtectedData: !accessValidated);
      return false;
    }
  }

  void _failQueue(Object error, String operation,
      {bool clearProtectedData = false}) {
    _generation++;
    _emergencyRefreshTimer?.cancel();
    setState(() {
      _readInFlight = false;
      _isLoadingEmergencies = false;
      _isAcceptingEmergency = false;
      _emergencyLoadError = _safeError(error, operation);
      _emergencyAcceptanceError = null;
      if (clearProtectedData ||
          _isAccessDenial(error) ||
          error is DispatchAccessException) {
        _clearArrivalAlerts();
        _accessContext = null;
        _incomingEmergencies.clear();
        _selectedEmergencyId = null;
        _selectedSection = _DispatchSection.liveOperations;
      }
    });
  }

  Future<void> _acceptEmergency(DispatchEmergency emergency) async {
    // Validate the live selected row as well as the render's generation. A
    // captured callback is not authority to act on an outdated snapshot.
    if (!_queueReady ||
        _accessContext?.canClaimIncident != true ||
        !identical(_selectedEmergency, emergency) ||
        !emergency.canBeClaimed) {
      return;
    }
    final generation = ++_generation;
    _emergencyRefreshTimer?.cancel();
    setState(() {
      _isAcceptingEmergency = true;
      _emergencyAcceptanceError = null;
    });
    var claimStarted = false;
    try {
      final access = await _loadAccess().timeout(_readTimeout);
      if (!_ownsGeneration(generation)) return;
      if (!access.canClaimIncident || !_sameAccess(_accessContext, access)) {
        _failQueue(const DispatchAccessException(),
            'Dispatch access changed. Refresh before accepting an emergency.',
            clearProtectedData: true);
        return;
      }
      final accepter = widget.incomingEmergencyAccepter ??
          EmergencyDispatchService().acceptEmergency;
      claimStarted = true;
      // A timeout cannot roll back a sent mutation. The catch path marks its
      // outcome unknown and requires an authoritative queue reconciliation.
      final claimResult = await accepter(emergency.id).timeout(_readTimeout);
      if (!_ownsGeneration(generation)) return;
      final acceptedEmergency =
          claimResult.withRetainedIntakeDetailsFrom(emergency);
      setState(() {
        final index = _incomingEmergencies.indexWhere(
          (item) => item.id == acceptedEmergency.id,
        );
        if (index == -1) {
          _incomingEmergencies.insert(0, acceptedEmergency);
        } else {
          _incomingEmergencies[index] = acceptedEmergency;
        }
        _selectedEmergencyId = acceptedEmergency.id;
        _newPendingIds.remove(acceptedEmergency.id);
        _knownPendingIds.remove(acceptedEmergency.id);
        _isAcceptingEmergency = false;
        _emergencyAcceptanceError = null;
      });
      _startPolling();
      _showMessage('Emergency accepted. The dispatch process has started.');
    } catch (error) {
      if (!_ownsGeneration(generation)) return;
      if (!claimStarted) {
        _failQueue(error, "Couldn't verify dispatch access. No claim was sent.",
            clearProtectedData: true);
        return;
      }
      if (_isAccessDenial(error)) {
        _failQueue(error, "Couldn't accept the emergency.");
        return;
      }

      // Preserve the existing server-conflict reconciliation. Text only
      // identifies this legacy conflict; it never grants or denies access.
      final details = error is PostgrestException
          ? error.message.toLowerCase()
          : error.toString().toLowerCase();
      final conflict = details.contains('already been accepted') ||
          details.contains('no longer pending');
      _generation++;
      setState(() {
        _isAcceptingEmergency = false;
        _emergencyLoadError =
            'The queue is outdated. Refresh to reconcile the claim result.';
        _emergencyAcceptanceError = conflict
            ? 'This emergency is no longer pending. Refreshing the queue.'
            : 'Could not confirm whether the emergency was accepted. '
                'Refresh the queue before trying again.';
      });
      if (conflict) {
        final reconciliationGeneration = _generation + 1;
        final refreshed = await _loadIncomingEmergencies();
        if (refreshed && _ownsGeneration(reconciliationGeneration)) {
          setState(() {
            _emergencyAcceptanceError =
                'Another dispatcher has already accepted this emergency. '
                'The queue has been refreshed.';
          });
        }
      }
    }
  }

  void _selectEmergency(DispatchEmergency emergency) {
    if (!_queueReady || !_incomingEmergencies.contains(emergency)) return;
    setState(() {
      _selectedEmergencyId = emergency.id;
      _newPendingIds.remove(emergency.id);
    });
  }

  Future<void> _confirmAndSignOut() async {
    if (_isSigningOut) {
      return;
    }

    final shouldSignOut = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          icon: const Icon(
            Icons.logout_rounded,
            color: CorviaColors.danger,
          ),
          title: const Text(
            'Sign out?',
          ),
          content: const Text(
            'You will leave the Emergency Dispatch Command Centre and return to the Corvia sign-in screen.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(false);
              },
              child: const Text(
                'Cancel',
              ),
            ),
            FilledButton.icon(
              onPressed: () {
                Navigator.of(dialogContext).pop(true);
              },
              style: FilledButton.styleFrom(
                backgroundColor: CorviaColors.danger,
                foregroundColor: Colors.white,
              ),
              icon: const Icon(
                Icons.logout_rounded,
              ),
              label: const Text(
                'Sign out',
              ),
            ),
          ],
        );
      },
    );

    if (shouldSignOut != true || !mounted) {
      return;
    }

    _generation++;
    _emergencyRefreshTimer?.cancel();
    setState(() {
      _sessionEnded = true;
      _isSigningOut = true;
      _readInFlight = false;
      _isLoadingEmergencies = false;
      _isAcceptingEmergency = false;
      _incomingEmergencies.clear();
      _clearArrivalAlerts();
      _accessContext = null;
      _lastRefreshed = null;
      _selectedEmergencyId = null;
      _emergencyAcceptanceError = null;
      _emergencyLoadError = 'Dispatch queue closed for sign-out.';
    });

    try {
      SettingsService.instance.sessionUnlocked = false;

      final signOut = widget.onSignOut;
      if (signOut != null) {
        await signOut();
      } else {
        await Supabase.instance.client.auth.signOut();
      }

      if (!mounted) {
        return;
      }

      Navigator.of(context).popUntil(
        (route) => route.isFirst,
      );
    } catch (error) {
      _showMessage(_safeError(error, "Couldn't sign out."));
    } finally {
      if (mounted) {
        setState(() {
          _isSigningOut = false;
        });
      }
    }
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

  @override
  Widget build(
    BuildContext context,
  ) {
    final renderedGeneration = _generation;
    final canRefresh =
        !_isLoadingEmergencies && !_isAcceptingEmergency && !_sessionEnded;
    void refresh() {
      if (_ownsGeneration(renderedGeneration)) unawaited(_refreshDashboard());
    }

    void retry() {
      if (_ownsGeneration(renderedGeneration)) {
        unawaited(_loadIncomingEmergencies());
      }
    }

    return LayoutBuilder(
      builder: (
        context,
        constraints,
      ) {
        final showSidebar = constraints.maxWidth >= 1080;

        return Scaffold(
          backgroundColor: context.cBgPrimary,
          appBar: showSidebar
              ? null
              : AppBar(
                  title: const Text(
                    'Emergency Dispatch',
                  ),
                  actions: [
                    if (workspaceCanPop)
                      IconButton(
                          onPressed: workspaceBack,
                          tooltip: 'Back',
                          icon: const Icon(Icons.arrow_back)),
                    IconButton(
                      onPressed: canRefresh ? refresh : null,
                      tooltip: 'Refresh',
                      icon: _isLoadingEmergencies
                          ? const SizedBox.square(
                              dimension: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                              ),
                            )
                          : const Icon(
                              Icons.refresh_rounded,
                            ),
                    ),
                    IconButton(
                      onPressed: _isSigningOut ? null : _confirmAndSignOut,
                      tooltip: 'Sign out',
                      icon: _isSigningOut
                          ? const SizedBox.square(
                              dimension: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                              ),
                            )
                          : const Icon(
                              Icons.logout_rounded,
                            ),
                    ),
                  ],
                ),
          drawer: showSidebar
              ? null
              : Drawer(
                  backgroundColor: context.cBgSecondary,
                  child: SafeArea(
                    child: _DispatchNavigation(
                      selectedSection: _navigationSection,
                      isSupervisor: _isSupervisor,
                      isSigningOut: _isSigningOut,
                      onSignOut: _confirmAndSignOut,
                      onSelected: (section) {
                        _selectSection(
                          section,
                          closeDrawer: true,
                        );
                      },
                    ),
                  ),
                ),
          body: SafeArea(
            child: Row(
              children: [
                if (showSidebar)
                  SizedBox(
                    width: 252,
                    child: _DispatchNavigation(
                      selectedSection: _navigationSection,
                      isSupervisor: _isSupervisor,
                      isSigningOut: _isSigningOut,
                      onSignOut: _confirmAndSignOut,
                      onSelected: _selectSection,
                    ),
                  ),
                Expanded(
                  child: workspaceBody(_DashboardWorkspace(
                    selectedSection: _selectedSection,
                    voiceSessions:
                        _selectedSection == _DispatchSection.incomingCalls &&
                                _queueReady &&
                                (widget.accessLoader == null ||
                                    widget.voiceSessionGateway != null)
                            ? DispatchVoiceSessionsView(
                                key: ValueKey(
                                  'dispatch-voice:${_accessContext?.userId}',
                                ),
                                gateway: widget.voiceSessionGateway,
                              )
                            : null,
                    terminalHistory: _selectedSection ==
                                _DispatchSection.reports &&
                            _queueReady &&
                            _accessContext?.canReadIncidentHistory == true &&
                            (widget.accessLoader == null ||
                                widget.terminalHistoryGateway != null)
                        ? DispatchTerminalHistoryView(
                            key: ValueKey(
                              'dispatch-history:${_accessContext?.userId}',
                            ),
                            gateway: widget.terminalHistoryGateway,
                          )
                        : null,
                    roleLabel: _roleLabel,
                    isSupervisor: _isSupervisor,
                    emergencies: _incomingEmergencies,
                    emergencyAcceptanceError: _emergencyAcceptanceError,
                    emergencyLoadError: _emergencyLoadError,
                    isAcceptingEmergency: _isAcceptingEmergency,
                    isLoadingEmergencies: _isLoadingEmergencies,
                    lastRefreshed: _lastRefreshed,
                    newPendingCount: _newPendingIds.length,
                    soundEnabled: _soundEnabled,
                    soundError: _soundError,
                    onToggleSound: _queueReady ? _toggleArrivalSound : null,
                    onAcknowledgeArrivals:
                        _queueReady && _newPendingIds.isNotEmpty
                            ? () => setState(_newPendingIds.clear)
                            : null,
                    onAcceptEmergency:
                        _queueReady && _accessContext?.canClaimIncident == true
                            ? (emergency) {
                                if (_ownsGeneration(renderedGeneration)) {
                                  unawaited(_acceptEmergency(emergency));
                                }
                              }
                            : null,
                    onEmergencySelected: (emergency) {
                      if (_ownsGeneration(renderedGeneration)) {
                        _selectEmergency(emergency);
                      }
                    },
                    onRefresh: canRefresh ? refresh : null,
                    onRetryEmergencies: canRefresh ? retry : null,
                    onOpenSettings: () {
                      _selectSection(
                        _DispatchSection.settings,
                      );
                    },
                    selectedEmergency: _selectedEmergency,
                    onOpenResponseWorkspace: _queueReady &&
                            _accessContext?.canUseIncidentWorkspace == true &&
                            _selectedEmergency != null
                        ? () => _openResponseWorkspace()
                        : null,
                    onOpenAllResponseWorkspaces: _queueReady &&
                            _accessContext?.canUseIncidentWorkspace == true
                        ? () => _openResponseWorkspace(showAll: true)
                        : null,
                    incidentHistory: !_sessionEnded &&
                            _lastRefreshed != null &&
                            _accessContext?.canReadIncidentHistory == true &&
                            _selectedEmergency?.hasValidIdentity == true &&
                            _selectedEmergency?.needsReview == false
                        ? Visibility(
                            visible: _queueReady,
                            maintainState: true,
                            child: Column(children: [
                              if (_accessContext?.canUseIncidentWorkspace ==
                                  true)
                                IncidentWorkspacePanel(
                                    key: ValueKey(
                                        'workspace:${_selectedEmergency!.id}'),
                                    incidentId: _selectedEmergency!.id,
                                    gateway: widget.workspaceGateway,
                                    enabled: _queueReady,
                                    onChanged: refresh),
                              IncidentHistoryPanel(
                                key: ValueKey(_selectedEmergency!.id),
                                incidentId: _selectedEmergency!.id,
                                revision: (
                                  _lastRefreshed,
                                  _selectedEmergency!.status,
                                  _selectedEmergency!.acceptedAt,
                                ),
                                loader: widget.historyLoader,
                              ),
                            ]))
                        : null,
                  )),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

enum _DispatchSection {
  liveOperations,
  incomingCalls,
  activeIncidents,
  liveMap,
  fleetAvailability,
  hospitals,
  completedIncidents,
  reports,
  settings,
}

class _DispatchDestination {
  const _DispatchDestination({
    required this.section,
    required this.label,
    required this.icon,
    required this.description,
    required this.features,
  });

  final _DispatchSection section;
  final String label;
  final IconData icon;
  final String description;
  final List<String> features;
}

const List<_DispatchDestination> _destinations = [
  _DispatchDestination(
    section: _DispatchSection.liveOperations,
    label: 'Live Operations',
    icon: Icons.space_dashboard_outlined,
    description: 'The combined emergency queue, map and incident workspace.',
    features: [],
  ),
  _DispatchDestination(
    section: _DispatchSection.incomingCalls,
    label: 'Incoming Calls',
    icon: Icons.ring_volume_outlined,
    description: 'Receive, claim and answer new Corvia emergency calls.',
    features: [
      'Unanswered call queue and elapsed waiting time',
      'Voice, chat, callback and connection state',
      'Single-dispatcher call ownership',
      'Supervisor join and takeover controls',
    ],
  ),
  _DispatchDestination(
    section: _DispatchSection.activeIncidents,
    label: 'Active Incidents',
    icon: Icons.emergency_outlined,
    description: 'Track triage, assignment and response progress.',
    features: [
      'Structured triage and dispatch notes',
      'Assignment acknowledgement and timeout tracking',
      'Incident status timeline',
      'Escalation and additional-unit requests',
    ],
  ),
  _DispatchDestination(
    section: _DispatchSection.liveMap,
    label: 'Live Map',
    icon: Icons.map_outlined,
    description: 'Monitor incidents, ambulance units and receiving hospitals.',
    features: [
      'Patient and incident locations',
      'Ambulance position and GPS freshness',
      'Routes, distance and estimated arrival time',
      'Hospitals, bases and coverage areas',
    ],
  ),
  _DispatchDestination(
    section: _DispatchSection.fleetAvailability,
    label: 'Fleet Availability',
    icon: Icons.airport_shuttle_outlined,
    description: 'View verified units that are eligible for dispatch.',
    features: [
      'Available, busy and out-of-service units',
      'Current crew and response capability',
      'Readiness and communications status',
      'Assignment eligibility explanation',
    ],
  ),
  _DispatchDestination(
    section: _DispatchSection.hospitals,
    label: 'Hospitals',
    icon: Icons.local_hospital_outlined,
    description: 'Compare suitable receiving facilities and contacts.',
    features: [
      'Hospital location, distance and ETA',
      'Emergency and specialist capabilities',
      'Receiving desk contact details',
      'Availability source and last verified time',
    ],
  ),
  _DispatchDestination(
    section: _DispatchSection.completedIncidents,
    label: 'Completed Incidents',
    icon: Icons.task_alt_outlined,
    description: 'Review resolved, cancelled and handed-over incidents.',
    features: [
      'Searchable completed incident history',
      'Full assignment and status timeline',
      'Cancellation and closure outcomes',
      'Audit-safe operational summary',
    ],
  ),
  _DispatchDestination(
    section: _DispatchSection.reports,
    label: 'Reports',
    icon: Icons.query_stats_outlined,
    description: 'Measure dispatch workload and response performance.',
    features: [
      'Call answer and assignment time',
      'Response and hospital handover time',
      'Missed-call and escalation review',
      'Supervisor quality review',
    ],
  ),
  _DispatchDestination(
    section: _DispatchSection.settings,
    label: 'Settings',
    icon: Icons.settings_outlined,
    description: 'Manage Corvia theme, accessibility and device preferences.',
    features: [],
  ),
];

class _DispatchNavigation extends StatelessWidget {
  const _DispatchNavigation({
    required this.selectedSection,
    required this.isSupervisor,
    required this.isSigningOut,
    required this.onSelected,
    required this.onSignOut,
  });

  final _DispatchSection selectedSection;
  final bool isSupervisor;
  final bool isSigningOut;
  final ValueChanged<_DispatchSection> onSelected;
  final VoidCallback onSignOut;

  @override
  Widget build(
    BuildContext context,
  ) {
    return Material(
      color: context.cBgSecondary,
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(
              20,
              22,
              20,
              20,
            ),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  CorviaColors.accentDark,
                  CorviaColors.accent,
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      padding: const EdgeInsets.all(
                        7,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(
                          alpha: 0.14,
                        ),
                        borderRadius: BorderRadius.circular(
                          14,
                        ),
                      ),
                      child: const CorviaLogo(size: 40, badge: true),
                    ),
                    const SizedBox(
                      width: 12,
                    ),
                    const Expanded(
                      child: Text(
                        'CORVIA EMS',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(
                  height: 18,
                ),
                const Text(
                  'Emergency Dispatch\nCommand Centre',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    height: 1.16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(
                  height: 10,
                ),
                _DispatchPill(
                  label:
                      isSupervisor ? 'Supervisor access' : 'Dispatcher access',
                  icon: isSupervisor
                      ? Icons.admin_panel_settings_outlined
                      : Icons.headset_mic_outlined,
                  foregroundColor: Colors.white,
                  backgroundColor: Colors.white.withValues(
                    alpha: 0.14,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 16,
              ),
              itemCount: _destinations.length,
              separatorBuilder: (_, __) {
                return const SizedBox(
                  height: 4,
                );
              },
              itemBuilder: (
                context,
                index,
              ) {
                final destination = _destinations[index];
                final selected = destination.section == selectedSection;

                return Material(
                  color: selected
                      ? CorviaColors.accent.withValues(
                          alpha: 0.12,
                        )
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(
                    14,
                  ),
                  child: InkWell(
                    onTap: () {
                      onSelected(
                        destination.section,
                      );
                    },
                    borderRadius: BorderRadius.circular(
                      14,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 13,
                        vertical: 12,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            destination.icon,
                            size: 21,
                            color: selected
                                ? context.cAccentReadable
                                : context.cTextSecondary,
                          ),
                          const SizedBox(
                            width: 12,
                          ),
                          Expanded(
                            child: Text(
                              destination.label,
                              style: TextStyle(
                                color: selected
                                    ? context.cAccentReadable
                                    : context.cTextPrimary,
                                fontWeight: selected
                                    ? FontWeight.w900
                                    : FontWeight.w700,
                              ),
                            ),
                          ),
                          if (selected)
                            Container(
                              width: 7,
                              height: 7,
                              decoration: BoxDecoration(
                                color: CorviaColors.accent,
                                shape: BoxShape.circle,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(
              14,
            ),
            child: Column(
              children: [
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: isSigningOut ? null : onSignOut,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: CorviaColors.danger,
                      side: BorderSide(
                        color: CorviaColors.danger.withValues(
                          alpha: 0.45,
                        ),
                      ),
                      padding: const EdgeInsets.symmetric(
                        vertical: 12,
                      ),
                    ),
                    icon: isSigningOut
                        ? const SizedBox.square(
                            dimension: 17,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                            ),
                          )
                        : const Icon(
                            Icons.logout_rounded,
                            size: 19,
                          ),
                    label: Text(
                      isSigningOut ? 'Signing out...' : 'Sign out',
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

class _DashboardWorkspace extends StatelessWidget {
  const _DashboardWorkspace({
    required this.selectedSection,
    required this.voiceSessions,
    required this.terminalHistory,
    required this.roleLabel,
    required this.isSupervisor,
    required this.emergencies,
    required this.emergencyAcceptanceError,
    required this.emergencyLoadError,
    required this.isAcceptingEmergency,
    required this.isLoadingEmergencies,
    required this.lastRefreshed,
    required this.newPendingCount,
    required this.soundEnabled,
    required this.soundError,
    required this.onToggleSound,
    required this.onAcknowledgeArrivals,
    required this.onAcceptEmergency,
    required this.onEmergencySelected,
    required this.onRefresh,
    required this.onRetryEmergencies,
    required this.onOpenSettings,
    required this.selectedEmergency,
    required this.onOpenResponseWorkspace,
    required this.onOpenAllResponseWorkspaces,
    required this.incidentHistory,
  });

  final _DispatchSection selectedSection;
  final Widget? voiceSessions;
  final Widget? terminalHistory;
  final String roleLabel;
  final bool isSupervisor;
  final List<DispatchEmergency> emergencies;
  final String? emergencyAcceptanceError;
  final String? emergencyLoadError;
  final bool isAcceptingEmergency;
  final bool isLoadingEmergencies;
  final DateTime? lastRefreshed;
  final int newPendingCount;
  final bool soundEnabled;
  final String? soundError;
  final VoidCallback? onToggleSound;
  final VoidCallback? onAcknowledgeArrivals;
  final ValueChanged<DispatchEmergency>? onAcceptEmergency;
  final ValueChanged<DispatchEmergency> onEmergencySelected;
  final VoidCallback? onRefresh;
  final VoidCallback? onRetryEmergencies;
  final VoidCallback onOpenSettings;
  final DispatchEmergency? selectedEmergency;
  final VoidCallback? onOpenResponseWorkspace;
  final VoidCallback? onOpenAllResponseWorkspaces;
  final Widget? incidentHistory;

  String get _refreshedLabel {
    final refreshed = lastRefreshed;
    if (refreshed == null) return 'Not updated yet';
    final time = '${refreshed.hour.toString().padLeft(2, '0')}:'
        '${refreshed.minute.toString().padLeft(2, '0')}';
    if (isLoadingEmergencies) return 'Refreshing · Last update $time';
    if (emergencyLoadError != null) return 'Outdated · Last update $time';
    return 'Updated $time';
  }

  String get _feedLabel {
    if (emergencyLoadError != null) return 'Queue read failed';
    if (isLoadingEmergencies) return 'Checking queue';
    return lastRefreshed == null
        ? 'Queue not verified'
        : 'Queue read succeeded';
  }

  @override
  Widget build(
    BuildContext context,
  ) {
    final destination = _destinations.firstWhere(
      (item) => item.section == selectedSection,
    );

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            20,
            20,
            20,
            12,
          ),
          child: _DispatchWelcomeBar(
            roleLabel: roleLabel,
            isSupervisor: isSupervisor,
            refreshedLabel: _refreshedLabel,
            feedLabel: _feedLabel,
            feedHealthy: emergencyLoadError == null &&
                !isLoadingEmergencies &&
                lastRefreshed != null,
            onRefresh: onRefresh,
            onOpenSettings: onOpenSettings,
          ),
        ),
        Expanded(
          child: selectedSection == _DispatchSection.settings
              ? const SettingsPage(
                  showAppBar: false,
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(
                    20,
                    0,
                    20,
                    24,
                  ),
                  child: switch (selectedSection) {
                    _DispatchSection.liveOperations => _LiveOperationsView(
                        isSupervisor: isSupervisor,
                        emergencies: emergencies,
                        emergencyAcceptanceError: emergencyAcceptanceError,
                        emergencyLoadError: emergencyLoadError,
                        isAcceptingEmergency: isAcceptingEmergency,
                        isLoadingEmergencies: isLoadingEmergencies,
                        newPendingCount: newPendingCount,
                        soundEnabled: soundEnabled,
                        soundError: soundError,
                        onToggleSound: onToggleSound,
                        onAcknowledgeArrivals: onAcknowledgeArrivals,
                        onAcceptEmergency: onAcceptEmergency,
                        onEmergencySelected: onEmergencySelected,
                        onRetryEmergencies: onRetryEmergencies,
                        selectedEmergency: selectedEmergency,
                        onOpenResponseWorkspace: onOpenResponseWorkspace,
                        incidentHistory: incidentHistory,
                      ),
                    _DispatchSection.incomingCalls => _IncomingCallsView(
                        voiceSessions: voiceSessions,
                        emergencies: emergencies,
                        emergencyAcceptanceError: emergencyAcceptanceError,
                        emergencyLoadError: emergencyLoadError,
                        isAcceptingEmergency: isAcceptingEmergency,
                        isLoadingEmergencies: isLoadingEmergencies,
                        newPendingCount: newPendingCount,
                        soundEnabled: soundEnabled,
                        soundError: soundError,
                        onToggleSound: onToggleSound,
                        onAcknowledgeArrivals: onAcknowledgeArrivals,
                        onAcceptEmergency: onAcceptEmergency,
                        onEmergencySelected: onEmergencySelected,
                        onRetryEmergencies: onRetryEmergencies,
                        selectedEmergency: selectedEmergency,
                        onOpenResponseWorkspace: onOpenResponseWorkspace,
                        incidentHistory: incidentHistory,
                      ),
                    _DispatchSection.reports => Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _DispatchQueueReportView(
                            emergencies: emergencies,
                            isLoading: isLoadingEmergencies,
                            errorMessage: emergencyLoadError,
                            lastRefreshed: lastRefreshed,
                            onRetry: onRetryEmergencies,
                            onOpenWorkspace: onOpenAllResponseWorkspaces,
                          ),
                          if (terminalHistory != null) terminalHistory!,
                        ],
                      ),
                    _ => _DispatchSectionPreview(destination: destination),
                  },
                ),
        ),
      ],
    );
  }
}

class _IncomingCallsView extends StatelessWidget {
  const _IncomingCallsView({
    required this.voiceSessions,
    required this.emergencies,
    required this.emergencyAcceptanceError,
    required this.emergencyLoadError,
    required this.isAcceptingEmergency,
    required this.isLoadingEmergencies,
    required this.newPendingCount,
    required this.soundEnabled,
    required this.soundError,
    required this.onToggleSound,
    required this.onAcknowledgeArrivals,
    required this.onAcceptEmergency,
    required this.onEmergencySelected,
    required this.onRetryEmergencies,
    required this.selectedEmergency,
    required this.onOpenResponseWorkspace,
    required this.incidentHistory,
  });

  final Widget? voiceSessions;
  final List<DispatchEmergency> emergencies;
  final String? emergencyAcceptanceError;
  final String? emergencyLoadError;
  final bool isAcceptingEmergency;
  final bool isLoadingEmergencies;
  final int newPendingCount;
  final bool soundEnabled;
  final String? soundError;
  final VoidCallback? onToggleSound;
  final VoidCallback? onAcknowledgeArrivals;
  final ValueChanged<DispatchEmergency>? onAcceptEmergency;
  final ValueChanged<DispatchEmergency> onEmergencySelected;
  final VoidCallback? onRetryEmergencies;
  final DispatchEmergency? selectedEmergency;
  final VoidCallback? onOpenResponseWorkspace;
  final Widget? incidentHistory;

  @override
  Widget build(BuildContext context) {
    // This is an actual scoped incoming incident queue. A ringing incident
    // does not prove that a voice session exists or can be answered here.
    final pending = emergencies.where((entry) => entry.isPending).toList();
    final visibleSelection =
        selectedEmergency?.isPending == true ? selectedEmergency : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Incoming incidents',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 6),
        Text(
          'Live, authorised incidents awaiting a dispatcher claim. '
          'Call answering requires an authorised voice session and is not '
          'available from this queue.',
          style: TextStyle(color: context.cTextSecondary),
        ),
        const SizedBox(height: 14),
        LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 920;
            final queue = _IncomingQueuePanel(
              emergencies: pending,
              errorMessage: emergencyLoadError,
              isLoading: isLoadingEmergencies,
              newPendingCount: newPendingCount,
              soundEnabled: soundEnabled,
              soundError: soundError,
              onToggleSound: onToggleSound,
              onAcknowledgeArrivals: onAcknowledgeArrivals,
              onEmergencySelected: onEmergencySelected,
              onRetry: onRetryEmergencies,
              selectedEmergencyId: visibleSelection?.id,
              pendingOnly: true,
            );
            final details = _IncidentDetailPanel(
              acceptanceError: emergencyAcceptanceError,
              emergency: visibleSelection,
              isAccepting: isAcceptingEmergency,
              onAccept: onAcceptEmergency,
              onOpenResponseWorkspace: onOpenResponseWorkspace,
              incidentHistory:
                  visibleSelection == null ? null : incidentHistory,
            );
            if (wide) {
              return SizedBox(
                height: 650,
                child: Row(
                  children: [
                    Expanded(flex: 3, child: queue),
                    const SizedBox(width: 14),
                    Expanded(flex: 4, child: details),
                  ],
                ),
              );
            }
            return Column(
              children: [
                SizedBox(height: 460, child: queue),
                const SizedBox(height: 14),
                SizedBox(height: 620, child: details),
              ],
            );
          },
        ),
        if (voiceSessions != null) ...[
          const SizedBox(height: 20),
          Text(
            'Voice call sessions (read only)',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 6),
          Text(
            'These are saved call-session records, not proof of a live '
            'audio connection. Answer and hang-up require a verified '
            'dispatcher signalling service.',
            style: TextStyle(color: context.cTextSecondary),
          ),
          const SizedBox(height: 12),
          voiceSessions!,
        ],
      ],
    );
  }
}

class _DispatchQueueReportView extends StatelessWidget {
  const _DispatchQueueReportView({
    required this.emergencies,
    required this.isLoading,
    required this.errorMessage,
    required this.lastRefreshed,
    required this.onRetry,
    required this.onOpenWorkspace,
  });

  final List<DispatchEmergency> emergencies;
  final bool isLoading;
  final String? errorMessage;
  final DateTime? lastRefreshed;
  final VoidCallback? onRetry;
  final VoidCallback? onOpenWorkspace;

  @override
  Widget build(BuildContext context) {
    if (isLoading && lastRefreshed == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (errorMessage != null) {
      return _QueueLoadFailure(message: errorMessage!, onRetry: onRetry);
    }
    if (lastRefreshed == null) {
      return _QueueLoadFailure(
        message: 'No verified dispatch snapshot is available.',
        onRetry: onRetry,
      );
    }
    final pending = emergencies.where((item) => item.isPending).length;
    final accepted = emergencies.where((item) => item.isAccepted).length;
    final otherStatuses =
        emergencies.where((item) => !item.isPending && !item.isAccepted).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Current queue snapshot',
            style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 6),
        Text(
          'Counts are calculated from the current authorised incident queue, '
          'not a complete historical reporting dataset.',
          style: TextStyle(color: context.cTextSecondary),
        ),
        const SizedBox(height: 16),
        LayoutBuilder(builder: (context, constraints) {
          final columns = constraints.maxWidth >= 900
              ? 4
              : constraints.maxWidth >= 480
                  ? 2
                  : 1;
          final width = (constraints.maxWidth - (columns - 1) * 12) / columns;
          return Wrap(spacing: 12, runSpacing: 12, children: [
            _StatusMetricCard(
              width: width,
              label: 'Queue entries',
              value: emergencies.length.toString(),
              icon: Icons.list_alt_outlined,
              color: CorviaColors.accent,
            ),
            _StatusMetricCard(
              width: width,
              label: 'Pending',
              value: pending.toString(),
              icon: Icons.schedule_outlined,
              color: CorviaColors.danger,
            ),
            _StatusMetricCard(
              width: width,
              label: 'Accepted',
              value: accepted.toString(),
              icon: Icons.task_alt_outlined,
              color: CorviaColors.success,
            ),
            _StatusMetricCard(
              width: width,
              label: 'Other statuses',
              value: otherStatuses.toString(),
              icon: Icons.info_outline_rounded,
              color: CorviaColors.warning,
            ),
          ]);
        }),
        const SizedBox(height: 16),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: context.cBgSecondary,
            border: Border.all(color: context.cDivider),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Metrics not recorded in the incident queue',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(
                'Call-answer time, assignment time, response time, hospital '
                'handover time and closed-case totals are unavailable here. '
                'They require authorised call events, team operations and '
                'closed-incident reports; values are not estimated.',
                style: TextStyle(color: context.cTextSecondary),
              ),
              const SizedBox(height: 14),
              OutlinedButton.icon(
                onPressed: onOpenWorkspace,
                icon: const Icon(Icons.open_in_new_rounded),
                label: const Text('Open operations workspace'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DispatchWelcomeBar extends StatelessWidget {
  const _DispatchWelcomeBar({
    required this.roleLabel,
    required this.isSupervisor,
    required this.refreshedLabel,
    required this.feedLabel,
    required this.feedHealthy,
    required this.onRefresh,
    required this.onOpenSettings,
  });

  final String roleLabel;
  final bool isSupervisor;
  final String refreshedLabel;
  final String feedLabel;
  final bool feedHealthy;
  final VoidCallback? onRefresh;
  final VoidCallback onOpenSettings;

  @override
  Widget build(
    BuildContext context,
  ) {
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
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.circular(
          24,
        ),
        boxShadow: [
          BoxShadow(
            color: CorviaColors.accent.withValues(
              alpha: 0.18,
            ),
            blurRadius: 24,
            offset: const Offset(
              0,
              9,
            ),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (
          context,
          constraints,
        ) {
          final compact = constraints.maxWidth < 720;
          final identity = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(
                    alpha: 0.15,
                  ),
                  borderRadius: BorderRadius.circular(
                    17,
                  ),
                ),
                child: Icon(
                  isSupervisor
                      ? Icons.admin_panel_settings_rounded
                      : Icons.headset_mic_rounded,
                  color: Colors.white,
                  size: 28,
                ),
              ),
              const SizedBox(
                width: 14,
              ),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Welcome, $roleLabel',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(
                      height: 4,
                    ),
                    Text(
                      'Emergency Dispatch Command Centre',
                      style: TextStyle(
                        color: Colors.white.withValues(
                          alpha: 0.82,
                        ),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );

          final controls = Wrap(
            spacing: 9,
            runSpacing: 9,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _DispatchPill(
                label: feedLabel,
                icon: feedHealthy
                    ? Icons.cloud_done_outlined
                    : Icons.cloud_off_outlined,
                foregroundColor: Colors.white,
                backgroundColor: Colors.white.withValues(
                  alpha: 0.15,
                ),
              ),
              _DispatchPill(
                label: refreshedLabel,
                icon: Icons.schedule_rounded,
                foregroundColor: Colors.white,
                backgroundColor: Colors.white.withValues(
                  alpha: 0.15,
                ),
              ),
              IconButton.filledTonal(
                onPressed: onRefresh,
                tooltip: 'Refresh incoming emergencies',
                style: IconButton.styleFrom(
                  backgroundColor: Colors.white.withValues(
                    alpha: 0.16,
                  ),
                  foregroundColor: Colors.white,
                ),
                icon: const Icon(
                  Icons.refresh_rounded,
                ),
              ),
              IconButton.filledTonal(
                onPressed: onOpenSettings,
                tooltip: 'Settings',
                style: IconButton.styleFrom(
                  backgroundColor: Colors.white.withValues(
                    alpha: 0.16,
                  ),
                  foregroundColor: Colors.white,
                ),
                icon: const Icon(
                  Icons.settings_outlined,
                ),
              ),
            ],
          );

          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                identity,
                const SizedBox(
                  height: 16,
                ),
                controls,
              ],
            );
          }

          return Row(
            children: [
              Expanded(
                child: identity,
              ),
              const SizedBox(
                width: 18,
              ),
              controls,
            ],
          );
        },
      ),
    );
  }
}

class _LiveOperationsView extends StatelessWidget {
  const _LiveOperationsView({
    required this.isSupervisor,
    required this.emergencies,
    required this.emergencyAcceptanceError,
    required this.emergencyLoadError,
    required this.isAcceptingEmergency,
    required this.isLoadingEmergencies,
    required this.newPendingCount,
    required this.soundEnabled,
    required this.soundError,
    required this.onToggleSound,
    required this.onAcknowledgeArrivals,
    required this.onAcceptEmergency,
    required this.onEmergencySelected,
    required this.onRetryEmergencies,
    required this.selectedEmergency,
    required this.onOpenResponseWorkspace,
    required this.incidentHistory,
  });

  final bool isSupervisor;
  final List<DispatchEmergency> emergencies;
  final String? emergencyAcceptanceError;
  final String? emergencyLoadError;
  final bool isAcceptingEmergency;
  final bool isLoadingEmergencies;
  final int newPendingCount;
  final bool soundEnabled;
  final String? soundError;
  final VoidCallback? onToggleSound;
  final VoidCallback? onAcknowledgeArrivals;
  final ValueChanged<DispatchEmergency>? onAcceptEmergency;
  final ValueChanged<DispatchEmergency> onEmergencySelected;
  final VoidCallback? onRetryEmergencies;
  final DispatchEmergency? selectedEmergency;
  final VoidCallback? onOpenResponseWorkspace;
  final Widget? incidentHistory;

  @override
  Widget build(
    BuildContext context,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (
            context,
            constraints,
          ) {
            final columns = constraints.maxWidth >= 1000
                ? 4
                : constraints.maxWidth >= 560
                    ? 2
                    : 1;
            final spacing = 12.0;
            final cardWidth =
                (constraints.maxWidth - (spacing * (columns - 1))) / columns;

            return Wrap(
              spacing: spacing,
              runSpacing: spacing,
              children: [
                _StatusMetricCard(
                  width: cardWidth,
                  label: 'Pending incidents',
                  value: emergencies
                      .where(
                        (emergency) => emergency.isPending,
                      )
                      .length
                      .toString(),
                  icon: Icons.ring_volume_outlined,
                  color: CorviaColors.danger,
                ),
                _StatusMetricCard(
                  width: cardWidth,
                  label: 'Visible queue entries',
                  value: emergencies.length.toString(),
                  icon: Icons.emergency_outlined,
                  color: CorviaColors.warning,
                ),
                _StatusMetricCard(
                  width: cardWidth,
                  label: 'Fleet availability',
                  value: 'See workspace',
                  icon: Icons.airport_shuttle_outlined,
                  color: CorviaColors.success,
                ),
                _StatusMetricCard(
                  width: cardWidth,
                  label: 'Queue read',
                  value: emergencyLoadError != null
                      ? 'Failed'
                      : isLoadingEmergencies
                          ? 'Checking'
                          : 'Verified',
                  icon: emergencyLoadError != null
                      ? Icons.cloud_off_outlined
                      : Icons.cloud_done_outlined,
                  color: emergencyLoadError != null
                      ? CorviaColors.danger
                      : CorviaColors.success,
                ),
              ],
            );
          },
        ),
        const SizedBox(
          height: 14,
        ),
        LayoutBuilder(
          builder: (
            context,
            constraints,
          ) {
            final wide = constraints.maxWidth >= 1180;

            if (wide) {
              return SizedBox(
                height: 620,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      width: 322,
                      child: _IncomingQueuePanel(
                        emergencies: emergencies,
                        errorMessage: emergencyLoadError,
                        isLoading: isLoadingEmergencies,
                        newPendingCount: newPendingCount,
                        soundEnabled: soundEnabled,
                        soundError: soundError,
                        onToggleSound: onToggleSound,
                        onAcknowledgeArrivals: onAcknowledgeArrivals,
                        onEmergencySelected: onEmergencySelected,
                        onRetry: onRetryEmergencies,
                        selectedEmergencyId: selectedEmergency?.id,
                      ),
                    ),
                    const SizedBox(
                      width: 14,
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                          child: IncidentLocationPanel(
                              incident: selectedEmergency)),
                    ),
                    const SizedBox(
                      width: 14,
                    ),
                    SizedBox(
                      width: 346,
                      child: _IncidentDetailPanel(
                        acceptanceError: emergencyAcceptanceError,
                        emergency: selectedEmergency,
                        incidentHistory: incidentHistory,
                        isAccepting: isAcceptingEmergency,
                        onAccept: onAcceptEmergency,
                        onOpenResponseWorkspace: onOpenResponseWorkspace,
                      ),
                    ),
                  ],
                ),
              );
            }

            return Column(
              children: [
                SizedBox(
                  height: 480,
                  child: _IncomingQueuePanel(
                    emergencies: emergencies,
                    errorMessage: emergencyLoadError,
                    isLoading: isLoadingEmergencies,
                    newPendingCount: newPendingCount,
                    soundEnabled: soundEnabled,
                    soundError: soundError,
                    onToggleSound: onToggleSound,
                    onAcknowledgeArrivals: onAcknowledgeArrivals,
                    onEmergencySelected: onEmergencySelected,
                    onRetry: onRetryEmergencies,
                    selectedEmergencyId: selectedEmergency?.id,
                  ),
                ),
                const SizedBox(
                  height: 14,
                ),
                SizedBox(
                  height: 330,
                  child: SingleChildScrollView(
                      child:
                          IncidentLocationPanel(incident: selectedEmergency)),
                ),
                const SizedBox(
                  height: 14,
                ),
                SizedBox(
                  height: 640,
                  child: _IncidentDetailPanel(
                    acceptanceError: emergencyAcceptanceError,
                    emergency: selectedEmergency,
                    incidentHistory: incidentHistory,
                    isAccepting: isAcceptingEmergency,
                    onAccept: onAcceptEmergency,
                    onOpenResponseWorkspace: onOpenResponseWorkspace,
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _StatusMetricCard extends StatelessWidget {
  const _StatusMetricCard({
    required this.width,
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final double width;
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(
    BuildContext context,
  ) {
    return Container(
      width: width,
      padding: const EdgeInsets.all(
        16,
      ),
      decoration: BoxDecoration(
        color: context.cBgSecondary,
        borderRadius: BorderRadius.circular(
          19,
        ),
        border: Border.all(
          color: context.cDivider,
        ),
        boxShadow: [
          BoxShadow(
            color: context.cCardShadow,
            blurRadius: 15,
            offset: const Offset(
              0,
              5,
            ),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color.withValues(
                alpha: 0.12,
              ),
              borderRadius: BorderRadius.circular(
                14,
              ),
            ),
            child: Icon(
              icon,
              color: color,
            ),
          ),
          const SizedBox(
            width: 12,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: context.cTextPrimary,
                    fontSize: 21,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(
                  height: 2,
                ),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: context.cTextSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
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

class _PanelShell extends StatelessWidget {
  const _PanelShell({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.child,
    this.trailing,
    this.attention = false,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Widget child;
  final Widget? trailing;
  final bool attention;

  @override
  Widget build(
    BuildContext context,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: context.cBgSecondary,
        borderRadius: BorderRadius.circular(
          22,
        ),
        border: Border.all(
          color: attention ? CorviaColors.danger : context.cDivider,
        ),
        boxShadow: [
          BoxShadow(
            color: context.cCardShadow,
            blurRadius: 18,
            offset: const Offset(
              0,
              6,
            ),
          ),
        ],
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              16,
              16,
              14,
              13,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 39,
                  height: 39,
                  decoration: BoxDecoration(
                    color: CorviaColors.accent.withValues(
                      alpha: 0.11,
                    ),
                    borderRadius: BorderRadius.circular(
                      13,
                    ),
                  ),
                  child: Icon(
                    icon,
                    size: 21,
                    color: context.cAccentReadable,
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
                        title,
                        style: TextStyle(
                          color: context.cTextPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(
                        height: 3,
                      ),
                      Semantics(
                        liveRegion: attention,
                        child: Text(
                          subtitle,
                          style: TextStyle(
                            color: attention
                                ? CorviaColors.danger
                                : context.cTextSecondary,
                            fontSize: 11,
                            height: 1.25,
                            fontWeight:
                                attention ? FontWeight.w700 : FontWeight.normal,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (trailing != null) ...[
                  const SizedBox(
                    width: 8,
                  ),
                  trailing!,
                ],
              ],
            ),
          ),
          Divider(
            height: 1,
            color: context.cDivider,
          ),
          Expanded(
            child: child,
          ),
        ],
      ),
    );
  }
}

enum _QueueViewFilter { all, pending, accepted }

class _IncomingQueuePanel extends StatefulWidget {
  const _IncomingQueuePanel({
    required this.emergencies,
    required this.errorMessage,
    required this.isLoading,
    required this.newPendingCount,
    required this.soundEnabled,
    required this.soundError,
    required this.onToggleSound,
    required this.onAcknowledgeArrivals,
    required this.onEmergencySelected,
    required this.onRetry,
    required this.selectedEmergencyId,
    this.pendingOnly = false,
  });

  final List<DispatchEmergency> emergencies;
  final String? errorMessage;
  final bool isLoading;
  final int newPendingCount;
  final bool soundEnabled;
  final String? soundError;
  final VoidCallback? onToggleSound;
  final VoidCallback? onAcknowledgeArrivals;
  final ValueChanged<DispatchEmergency> onEmergencySelected;
  final VoidCallback? onRetry;
  final String? selectedEmergencyId;
  final bool pendingOnly;

  @override
  State<_IncomingQueuePanel> createState() => _IncomingQueuePanelState();
}

class _IncomingQueuePanelState extends State<_IncomingQueuePanel> {
  _QueueViewFilter _filter = _QueueViewFilter.all;

  int get _pendingCount =>
      widget.emergencies.where((entry) => entry.isPending).length;

  List<DispatchEmergency> get _visibleIncidents {
    if (widget.pendingOnly) {
      return widget.emergencies.where((entry) => entry.isPending).toList();
    }
    return switch (_filter) {
      _QueueViewFilter.all => widget.emergencies,
      _QueueViewFilter.pending =>
        widget.emergencies.where((entry) => entry.isPending).toList(),
      _QueueViewFilter.accepted =>
        widget.emergencies.where((entry) => entry.isAccepted).toList(),
    };
  }

  @override
  Widget build(BuildContext context) {
    final emergencies = widget.emergencies;
    final errorMessage = widget.errorMessage;
    final isLoading = widget.isLoading;
    final newPendingCount = widget.newPendingCount;
    final soundError = widget.soundError;
    final soundEnabled = widget.soundEnabled;
    final onToggleSound = widget.onToggleSound;
    final onAcknowledgeArrivals = widget.onAcknowledgeArrivals;
    final onRetry = widget.onRetry;

    return _PanelShell(
      title:
          widget.pendingOnly ? 'Pending dispatch requests' : 'Incident queue',
      subtitle: _pendingCount == 0
          ? 'No pending incidents in this authorised queue'
          : '$_pendingCount pending ${_pendingCount == 1 ? 'incident' : 'incidents'}'
              '${newPendingCount > 0 ? ' · $newPendingCount newly received' : ''}',
      icon: Icons.ring_volume_outlined,
      attention: _pendingCount > 0,
      trailing: _DispatchPill(
        label: isLoading
            ? 'Updating'
            : errorMessage != null
                ? 'Unavailable'
                : '$_pendingCount pending',
        icon: Icons.schedule_rounded,
        foregroundColor: CorviaColors.danger,
        backgroundColor: const Color(0x1AEF4444),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            if (soundError != null)
              Semantics(liveRegion: true, child: Text(soundError)),
            Row(
              children: [
                Expanded(
                  child: widget.pendingOnly
                      ? Text('Awaiting claim',
                          style: TextStyle(color: context.cTextSecondary))
                      : SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              _QueueFilterChip(
                                label: 'All',
                                selected: _filter == _QueueViewFilter.all,
                                onTap: () => setState(
                                    () => _filter = _QueueViewFilter.all),
                              ),
                              const SizedBox(width: 7),
                              _QueueFilterChip(
                                label: 'Pending',
                                selected: _filter == _QueueViewFilter.pending,
                                onTap: () => setState(
                                    () => _filter = _QueueViewFilter.pending),
                              ),
                              const SizedBox(width: 7),
                              _QueueFilterChip(
                                label: 'Accepted',
                                selected: _filter == _QueueViewFilter.accepted,
                                onTap: () => setState(
                                    () => _filter = _QueueViewFilter.accepted),
                              ),
                            ],
                          ),
                        ),
                ),
                IconButton(
                  onPressed: onToggleSound,
                  tooltip:
                      soundEnabled ? 'Queue sound on' : 'Enable queue sound',
                  icon: Icon(soundEnabled ? Icons.volume_up : Icons.volume_off),
                  constraints:
                      const BoxConstraints.tightFor(width: 36, height: 36),
                  padding: EdgeInsets.zero,
                ),
                if (newPendingCount > 0 && onAcknowledgeArrivals != null)
                  IconButton(
                    onPressed: onAcknowledgeArrivals,
                    tooltip: 'Mark alerts seen',
                    icon: const Icon(Icons.done_all),
                    constraints:
                        const BoxConstraints.tightFor(width: 36, height: 36),
                    padding: EdgeInsets.zero,
                  ),
              ],
            ),
            const SizedBox(height: 10),
            if (isLoading && emergencies.isNotEmpty) ...[
              const LinearProgressIndicator(),
              const Text('Refreshing. Displayed incidents are read-only.'),
              const SizedBox(height: 8),
            ],
            if (errorMessage != null && emergencies.isNotEmpty) ...[
              Text(errorMessage),
              TextButton(onPressed: onRetry, child: const Text('Try again')),
            ],
            Expanded(child: _buildQueueBody()),
            if (emergencies.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(11),
                decoration: BoxDecoration(
                  color: CorviaColors.danger.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.sync_rounded,
                        color: CorviaColors.danger, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        errorMessage != null
                            ? 'Updates paused. Displayed incidents may be outdated.'
                            : isLoading
                                ? 'Waiting for an updated queue.'
                                : 'The queue refreshes automatically every 15 seconds.',
                        style: TextStyle(
                          color: context.cTextSecondary,
                          fontSize: 11,
                          height: 1.3,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildQueueBody() {
    if (widget.isLoading && widget.emergencies.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (widget.errorMessage != null && widget.emergencies.isEmpty) {
      return _QueueLoadFailure(
        message: widget.errorMessage!,
        onRetry: widget.onRetry,
      );
    }
    final visible = _visibleIncidents;
    if (visible.isEmpty) {
      return Center(
        child: _EmptyState(
          icon: Icons.notifications_none_rounded,
          title: 'No matching incidents',
          message: widget.emergencies.isEmpty
              ? 'There are no current incidents in this queue.'
              : 'No incidents match the selected filter.',
          color: CorviaColors.success,
        ),
      );
    }
    return ListView.separated(
      itemCount: visible.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final emergency = visible[index];
        return _EmergencyQueueCard(
          emergency: emergency,
          isSelected: emergency.id == widget.selectedEmergencyId,
          onTap: () => widget.onEmergencySelected(emergency),
        );
      },
    );
  }
}

class _QueueLoadFailure extends StatelessWidget {
  const _QueueLoadFailure({
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.cloud_off_outlined,
              color: CorviaColors.danger,
              size: 36,
            ),
            const SizedBox(height: 10),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: context.cTextSecondary,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmergencyQueueCard extends StatelessWidget {
  const _EmergencyQueueCard({
    required this.emergency,
    required this.isSelected,
    required this.onTap,
  });

  final DispatchEmergency emergency;
  final bool isSelected;
  final VoidCallback onTap;

  String get _incidentLabel {
    final id = emergency.id;
    final shortened = id.length <= 8 ? id : id.substring(0, 8);
    return 'Emergency #$shortened';
  }

  String get _statusLabel {
    return emergency.status
        .split('_')
        .where((part) => part.isNotEmpty)
        .map(
          (part) => '${part[0].toUpperCase()}${part.substring(1)}',
        )
        .join(' ');
  }

  String get _timeLabel {
    final createdAt = emergency.createdAt;
    if (createdAt == null) {
      return 'Time unavailable';
    }

    final elapsed = DateTime.now().difference(createdAt);
    if (elapsed.inMinutes < 1) {
      return 'Just now';
    }
    if (elapsed.inHours < 1) {
      return '${elapsed.inMinutes} min ago';
    }
    if (elapsed.inDays < 1) {
      return '${elapsed.inHours} hr ago';
    }

    return '${createdAt.day.toString().padLeft(2, '0')}/'
        '${createdAt.month.toString().padLeft(2, '0')} '
        '${createdAt.hour.toString().padLeft(2, '0')}:'
        '${createdAt.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isSelected
          ? CorviaColors.danger.withValues(alpha: 0.09)
          : context.cBgPrimary,
      borderRadius: BorderRadius.circular(15),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(15),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(15),
            border: Border.all(
              color: isSelected
                  ? CorviaColors.danger.withValues(alpha: 0.55)
                  : context.cDivider,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: CorviaColors.danger.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: const Icon(
                      Icons.emergency_rounded,
                      color: CorviaColors.danger,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _incidentLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: context.cTextPrimary,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _timeLabel,
                          style: TextStyle(
                            color: context.cTextSecondary,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  _DispatchPill(
                    label: _statusLabel,
                    icon: Icons.circle,
                    foregroundColor: CorviaColors.danger,
                    backgroundColor:
                        CorviaColors.danger.withValues(alpha: 0.08),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(
                    Icons.location_on_outlined,
                    color: context.cTextSecondary,
                    size: 16,
                  ),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      emergency.coordinateLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: context.cTextSecondary,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
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
}

class _QueueFilterChip extends StatelessWidget {
  const _QueueFilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(
    BuildContext context,
  ) {
    return Material(
      color: selected
          ? CorviaColors.accent.withValues(
              alpha: 0.12,
            )
          : context.cBgPrimary,
      borderRadius: BorderRadius.circular(
        999,
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(
          999,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: 11,
            vertical: 8,
          ),
          child: Text(
            label,
            style: TextStyle(
              color:
                  selected ? context.cAccentReadable : context.cTextSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }
}

class _IncidentDetailPanel extends StatelessWidget {
  const _IncidentDetailPanel({
    required this.acceptanceError,
    required this.emergency,
    required this.isAccepting,
    required this.onAccept,
    required this.onOpenResponseWorkspace,
    required this.incidentHistory,
  });

  final String? acceptanceError;
  final DispatchEmergency? emergency;
  final Widget? incidentHistory;
  final bool isAccepting;
  final ValueChanged<DispatchEmergency>? onAccept;
  final VoidCallback? onOpenResponseWorkspace;

  String get _patientLabel {
    final userId = emergency?.userId ?? '';
    if (userId.isEmpty) {
      return 'Patient account unavailable';
    }

    final shortened = userId.length <= 12 ? userId : userId.substring(0, 12);
    return 'Patient account $shortened…';
  }

  String get _statusLabel {
    final status = emergency?.status ?? '';
    if (status.isEmpty) {
      return 'Not selected';
    }

    return status
        .split('_')
        .where((part) => part.isNotEmpty)
        .map(
          (part) => '${part[0].toUpperCase()}${part.substring(1)}',
        )
        .join(' ');
  }

  String get _acceptedLabel {
    final acceptedAt = emergency?.acceptedAt;
    if (acceptedAt == null) {
      return 'Accepted by dispatch';
    }

    return 'Accepted at '
        '${acceptedAt.hour.toString().padLeft(2, '0')}:'
        '${acceptedAt.minute.toString().padLeft(2, '0')}';
  }

  String get _locationInformationLabel {
    final incident = emergency;
    if (incident == null || incident.intakeNeedsReview) {
      return 'Location information needs review.';
    }
    switch (incident.locationSource) {
      case 'gps':
        final captured = incident.locationCapturedAt?.toLocal();
        if (captured == null || incident.locationAccuracy == null) {
          return 'GPS capture information unavailable.';
        }
        return 'Recorded GPS fix (not live). Captured '
            '${captured.day.toString().padLeft(2, '0')}/'
            '${captured.month.toString().padLeft(2, '0')}/${captured.year} '
            '${captured.hour.toString().padLeft(2, '0')}:'
            '${captured.minute.toString().padLeft(2, '0')}:'
            '${captured.second.toString().padLeft(2, '0')} local time. '
            'Reported accuracy ${incident.locationAccuracy!.toStringAsFixed(1)} m.';
      case 'manual':
        return 'Patient-reported address; no GPS fix supplied.';
      case 'unavailable':
        return 'No location supplied. Confirm the location with the patient.';
      case 'legacy':
        return 'Legacy coordinates; capture time and accuracy are unknown.';
      default:
        return 'Location source unavailable.';
    }
  }

  @override
  Widget build(
    BuildContext context,
  ) {
    return _PanelShell(
      title: 'Selected incident',
      subtitle: 'Patient, triage and assignment',
      icon: Icons.assignment_outlined,
      trailing: _DispatchPill(
        label: emergency == null ? 'No selection' : _statusLabel,
        icon: emergency == null
            ? Icons.remove_circle_outline
            : Icons.emergency_rounded,
        foregroundColor:
            emergency == null ? context.cTextSecondary : CorviaColors.danger,
        backgroundColor: emergency == null
            ? context.cBgPrimary
            : CorviaColors.danger.withValues(alpha: 0.08),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(
          15,
        ),
        child: Column(
          children: [
            _IncidentField(
              label: 'Patient',
              value: emergency == null ? 'Select an incident' : _patientLabel,
              icon: Icons.person_outline_rounded,
            ),
            const SizedBox(
              height: 9,
            ),
            _IncidentField(
              label: 'Location',
              value:
                  emergency?.coordinateLabel ?? 'Waiting for incident location',
              icon: Icons.location_on_outlined,
            ),
            if (emergency?.hasIntakeDetails == true) ...[
              const SizedBox(height: 9),
              _IncidentField(
                label: 'Location information',
                value: _locationInformationLabel,
                icon: Icons.info_outline,
              ),
              const SizedBox(height: 9),
              _IncidentField(
                label: 'Patient-reported address',
                value: emergency!.address ?? 'No address supplied',
                icon: Icons.place_outlined,
              ),
              const SizedBox(height: 9),
              _IncidentField(
                label: 'Patient-reported details',
                value: emergency!.details ?? 'No details supplied',
                icon: Icons.notes_outlined,
              ),
            ],
            const SizedBox(
              height: 9,
            ),
            if (emergency?.needsReview == true)
              const Text('Incident data needs review. Claim is unavailable.'),
            _IncidentField(
              label: 'Incident status',
              value: emergency == null ? 'Not selected' : _statusLabel,
              icon: Icons.priority_high_rounded,
            ),
            const SizedBox(
              height: 12,
            ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(
                12,
              ),
              decoration: BoxDecoration(
                color: CorviaColors.danger.withValues(
                  alpha: 0.07,
                ),
                borderRadius: BorderRadius.circular(
                  14,
                ),
                border: Border.all(
                  color: CorviaColors.danger.withValues(
                    alpha: 0.28,
                  ),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.health_and_safety_outlined,
                    color: CorviaColors.danger,
                    size: 20,
                  ),
                  const SizedBox(
                    width: 9,
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Clinical warnings',
                          style: TextStyle(
                            color: context.cTextPrimary,
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(
                          height: 3,
                        ),
                        Text(
                          'Clinical records are not connected here. Confirm relevant information with the patient or authorized clinical team.',
                          style: TextStyle(
                            color: context.cTextSecondary,
                            fontSize: 11,
                            height: 1.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(
              height: 13,
            ),
            if (incidentHistory != null) ...[
              incidentHistory!,
              const SizedBox(height: 12),
            ],
            if (acceptanceError != null) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: CorviaColors.danger.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: CorviaColors.danger.withValues(alpha: 0.30),
                  ),
                ),
                child: Text(
                  acceptanceError!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: CorviaColors.danger,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(height: 10),
            ],
            if (emergency?.canBeClaimed == true)
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: isAccepting || onAccept == null
                      ? null
                      : () {
                          onAccept!(emergency!);
                        },
                  style: FilledButton.styleFrom(
                    backgroundColor: CorviaColors.danger,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                  ),
                  icon: isAccepting
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Icon(Icons.task_alt_rounded),
                  label: Text(
                    isAccepting ? 'Accepting emergency...' : 'Accept emergency',
                  ),
                ),
              )
            else if (emergency?.isAccepted == true &&
                emergency?.needsReview != true)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 11,
                ),
                decoration: BoxDecoration(
                  color: CorviaColors.success.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: CorviaColors.success.withValues(alpha: 0.35),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.verified_rounded,
                      color: CorviaColors.success,
                      size: 18,
                    ),
                    const SizedBox(width: 7),
                    Flexible(
                      child: Text(
                        _acceptedLabel,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: CorviaColors.success,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: emergency == null ? null : onOpenResponseWorkspace,
                icon: const Icon(Icons.open_in_new_rounded),
                label: const Text('Open response workspace'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _IncidentField extends StatelessWidget {
  const _IncidentField({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(
    BuildContext context,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: 11,
        vertical: 10,
      ),
      decoration: BoxDecoration(
        color: context.cBgPrimary,
        borderRadius: BorderRadius.circular(
          13,
        ),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            size: 19,
            color: context.cAccentReadable,
          ),
          const SizedBox(
            width: 9,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: context.cTextSecondary,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(
                  height: 2,
                ),
                Text(
                  value,
                  style: TextStyle(
                    color: context.cTextPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
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

class _DispatchSectionPreview extends StatelessWidget {
  const _DispatchSectionPreview({
    required this.destination,
  });

  final _DispatchDestination destination;

  @override
  Widget build(
    BuildContext context,
  ) {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(
        minHeight: 520,
      ),
      padding: const EdgeInsets.all(
        24,
      ),
      decoration: BoxDecoration(
        color: context.cBgSecondary,
        borderRadius: BorderRadius.circular(
          24,
        ),
        border: Border.all(
          color: context.cDivider,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: CorviaColors.accent.withValues(
                alpha: 0.12,
              ),
              borderRadius: BorderRadius.circular(
                20,
              ),
            ),
            child: Icon(
              destination.icon,
              color: context.cAccentReadable,
              size: 31,
            ),
          ),
          const SizedBox(
            height: 18,
          ),
          Text(
            destination.label,
            style: TextStyle(
              color: context.cTextPrimary,
              fontSize: 27,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(
            height: 7,
          ),
          Text(
            destination.description,
            style: TextStyle(
              color: context.cTextSecondary,
              fontSize: 15,
              height: 1.45,
            ),
          ),
          const SizedBox(
            height: 22,
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(
              16,
            ),
            decoration: BoxDecoration(
              color: CorviaColors.warning.withValues(
                alpha: 0.08,
              ),
              borderRadius: BorderRadius.circular(
                16,
              ),
              border: Border.all(
                color: CorviaColors.warning.withValues(
                  alpha: 0.30,
                ),
              ),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.construction_outlined,
                  color: CorviaColors.warning,
                ),
                SizedBox(
                  width: 11,
                ),
                Expanded(
                  child: Text(
                    'The interface section is reserved. Its backend and operational actions are intentionally not connected in this dashboard phase.',
                  ),
                ),
              ],
            ),
          ),
          if (destination.features.isNotEmpty) ...[
            const SizedBox(
              height: 24,
            ),
            Text(
              'Planned capabilities',
              style: TextStyle(
                color: context.cTextPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(
              height: 11,
            ),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: destination.features.map((feature) {
                return Container(
                  constraints: const BoxConstraints(
                    maxWidth: 360,
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 13,
                    vertical: 11,
                  ),
                  decoration: BoxDecoration(
                    color: context.cBgPrimary,
                    borderRadius: BorderRadius.circular(
                      14,
                    ),
                    border: Border.all(
                      color: context.cDivider,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.check_circle_outline_rounded,
                        size: 18,
                        color: context.cAccentReadable,
                      ),
                      const SizedBox(
                        width: 8,
                      ),
                      Flexible(
                        child: Text(
                          feature,
                          style: TextStyle(
                            color: context.cTextPrimary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.message,
    required this.color,
  });

  final IconData icon;
  final String title;
  final String message;
  final Color color;

  @override
  Widget build(
    BuildContext context,
  ) {
    return Padding(
      padding: const EdgeInsets.all(
        14,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 62,
            height: 62,
            decoration: BoxDecoration(
              color: color.withValues(
                alpha: 0.10,
              ),
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              size: 30,
              color: color,
            ),
          ),
          const SizedBox(
            height: 13,
          ),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: context.cTextPrimary,
              fontWeight: FontWeight.w900,
              fontSize: 14,
            ),
          ),
          const SizedBox(
            height: 5,
          ),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: context.cTextSecondary,
              fontSize: 11,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

class _DispatchPill extends StatelessWidget {
  const _DispatchPill({
    required this.label,
    required this.icon,
    required this.foregroundColor,
    required this.backgroundColor,
  });

  final String label;
  final IconData icon;
  final Color foregroundColor;
  final Color backgroundColor;

  @override
  Widget build(
    BuildContext context,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 7,
      ),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(
          999,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            color: foregroundColor,
            size: 15,
          ),
          const SizedBox(
            width: 6,
          ),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: foregroundColor,
                fontSize: 10,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
