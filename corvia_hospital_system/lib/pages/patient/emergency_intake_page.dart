import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../../controllers/patient_emergency_intake_controller.dart';
import '../../services/location_service.dart';
import '../../widgets/emergency_phone_card.dart';
import '../../widgets/incident_history_panel.dart';
import '../../widgets/incident_workspace_panel.dart';

/// Explicit Corvia intake; opening this screen never creates an incident.
class EmergencyIntakePage extends StatefulWidget {
  const EmergencyIntakePage(
      {super.key, this.controller, this.readLocation, this.historyLoader});

  final PatientEmergencyIntakeController? controller;
  final Future<Position?> Function()? readLocation;
  final IncidentHistoryLoader? historyLoader;

  @override
  State<EmergencyIntakePage> createState() => _EmergencyIntakePageState();
}

class _EmergencyIntakePageState extends State<EmergencyIntakePage> {
  late final PatientEmergencyIntakeController _controller;
  final _address = TextEditingController();
  final _details = TextEditingController();
  Position? _position;
  bool _locating = false;
  bool _locationFailed = false;
  bool _failurePromptShown = false;
  bool _cancelDialogOpen = false;
  String? _validationMessage;
  int _locationGeneration = 0;
  Timer? _refreshTimer;
  PatientEmergencyIntakePhase? _lastPhase;
  String? _displayedUserId;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? PatientEmergencyIntakeController();
    _controller.addListener(_changed);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_controller.initialize());
    });
    _refreshTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted &&
          !_controller.isBusy &&
          _controller.phase == PatientEmergencyIntakePhase.confirmed &&
          !_controller.canStartNewRequest &&
          (WidgetsBinding.instance.lifecycleState == null ||
              WidgetsBinding.instance.lifecycleState ==
                  AppLifecycleState.resumed)) {
        unawaited(_controller.reconcile());
      }
    });
  }

  void _changed() {
    if (!mounted) return;
    final previous = _lastPhase;
    _lastPhase = _controller.phase;
    if (_displayedUserId != _controller.activeUserId) {
      _failurePromptShown = false;
    }
    if (_controller.sessionEnded ||
        _displayedUserId != _controller.activeUserId ||
        _controller.phase == PatientEmergencyIntakePhase.blocked) {
      _locationGeneration++;
      _position = null;
      _locating = false;
      _address.clear();
      _details.clear();
      _validationMessage = null;
    }
    _displayedUserId = _controller.activeUserId;
    setState(() {});
    if (!_failurePromptShown &&
        !_controller.cancellationUnconfirmed &&
        _controller.phase == PatientEmergencyIntakePhase.unknown &&
        (previous == PatientEmergencyIntakePhase.submitting ||
            previous == PatientEmergencyIntakePhase.reconciling)) {
      _failurePromptShown = true;
      final promptUserId = _controller.activeUserId;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted &&
            !_controller.sessionEnded &&
            _controller.activeUserId == promptUserId &&
            _controller.phase == PatientEmergencyIntakePhase.unknown) {
          unawaited(showDialog<void>(
              context: context,
              builder: (context) => AlertDialog(
                    title: const Text('Request confirmation unavailable'),
                    content: const SingleChildScrollView(
                        child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                            'Your request may have reached Corvia. Check its status before '
                            'retrying. You can call directly if you need urgent help; tell '
                            'the operator about any request or call you already made.'),
                        SizedBox(height: 12),
                        EmergencyPhoneCard(),
                      ],
                    )),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Return to request'))
                    ],
                  )));
        }
      });
    }
  }

  Future<void> _getLocation() async {
    if (_locating || !_controller.canSubmit) return;
    final generation = ++_locationGeneration;
    setState(() {
      _locating = true;
      _locationFailed = false;
      _position = null;
    });
    Position? position;
    try {
      final result = await (widget.readLocation?.call() ??
              LocationService.currentPosition(accuracy: LocationAccuracy.high))
          .timeout(const Duration(seconds: 15));
      if (result != null) {
        final age = DateTime.now().difference(result.timestamp);
        if (result.latitude.isFinite &&
            result.longitude.isFinite &&
            result.latitude.abs() <= 90 &&
            result.longitude.abs() <= 180 &&
            result.accuracy.isFinite &&
            result.accuracy >= 0 &&
            age >= const Duration(seconds: -30) &&
            age <= const Duration(minutes: 2)) {
          position = result;
        }
      }
    } catch (_) {/* The direct phone option remains independent. */}
    if (!mounted || generation != _locationGeneration) return;
    setState(() {
      _locating = false;
      _position = position;
      _locationFailed = position == null;
    });
  }

  Future<void> _submit() async {
    if (!_controller.canSubmit) return;
    final fix = _position;
    _locationGeneration++;
    setState(() {
      _locating = false;
      _validationMessage = null;
    });
    try {
      final request = PatientEmergencyIntakeRequest(
        latitude: fix?.latitude,
        longitude: fix?.longitude,
        accuracy: fix?.accuracy,
        capturedAt: fix?.timestamp,
        address: _address.text,
        details: _details.text,
      );
      await _controller.submit(request);
    } on PatientEmergencyIntakeException catch (error) {
      if (mounted) setState(() => _validationMessage = error.message);
    }
  }

  Future<void> _newRequest() async {
    await _controller.startNewRequest();
    if (!mounted || !_controller.canSubmit) return;
    _locationGeneration++;
    _address.clear();
    _details.clear();
    setState(() {
      _position = null;
      _locationFailed = false;
      _validationMessage = null;
      _failurePromptShown = false;
    });
  }

  Future<void> _cancelRequest() async {
    if (_cancelDialogOpen || !_controller.canCancel) return;
    final original = _controller.incident!;
    final actor = _controller.activeUserId;
    setState(() => _cancelDialogOpen = true);
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Cancel this Corvia request?'),
          content: const Text(
              'Cancellation is possible only before a dispatcher '
              'accepts it. This does not cancel a phone call or help arranged '
              'directly with ER24 or another service.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Keep request')),
            FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Confirm cancellation')),
          ],
        ),
      );
      if (!mounted || confirmed != true) return;
      final current = _controller.incident;
      if (!_controller.canCancel ||
          actor != _controller.activeUserId ||
          current?.operationId != original.operationId ||
          current?.version != original.version) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'The request changed. Check its status before cancelling.')));
        return;
      }
      await _controller.cancel();
    } finally {
      if (mounted) setState(() => _cancelDialogOpen = false);
    }
  }

  @override
  void dispose() {
    _locationGeneration++;
    _refreshTimer?.cancel();
    _controller.removeListener(_changed);
    _controller.dispose();
    _address.dispose();
    _details.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final incident = _controller.incident;
    final editable =
        _controller.canSubmit && _controller.submittedRequest == null;
    return Scaffold(
      appBar: AppBar(title: const Text('Emergency help')),
      body: SafeArea(
          child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Center(
            child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const EmergencyPhoneCard(),
            const SizedBox(height: 16),
            Card(
                child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                            incident == null
                                ? 'Request Corvia dispatch assistance'
                                : 'Corvia request #${incident.incidentId}',
                            style: Theme.of(context).textTheme.titleLarge),
                        const SizedBox(height: 8),
                        const Text(
                            'A request or Corvia acceptance does not confirm that '
                            'ER24 or an ambulance is on the way. Use the direct phone '
                            'option whenever you need urgent help.'),
                        if (_controller.isBusy) ...[
                          const SizedBox(height: 16),
                          const LinearProgressIndicator(),
                          const SizedBox(height: 8),
                          Text(_controller.phase ==
                                  PatientEmergencyIntakePhase.submitting
                              ? 'Sending your request...'
                              : _controller.phase ==
                                      PatientEmergencyIntakePhase.cancelling
                                  ? 'Cancelling your request...'
                                  : 'Checking request status...'),
                        ],
                        if (_controller.errorMessage != null) ...[
                          const SizedBox(height: 12),
                          Semantics(
                              liveRegion: true,
                              child: Text(_controller.errorMessage!)),
                        ],
                        if (_validationMessage != null) ...[
                          const SizedBox(height: 12),
                          Semantics(
                              liveRegion: true,
                              child: Text(_validationMessage!)),
                        ],
                        if (incident != null) ...[
                          const SizedBox(height: 16),
                          if (_controller.phase !=
                              PatientEmergencyIntakePhase.confirmed)
                            const Text(
                                'Last confirmed information. The current status has not been confirmed.'),
                          Text(
                              switch (incident.status) {
                                'pending' => 'Waiting for a Corvia dispatcher',
                                'in_progress' => 'Accepted by Corvia dispatch',
                                'resolved' => 'Request closed',
                                'cancelled' => 'Request cancelled',
                                _ => 'Status needs review',
                              },
                              style: Theme.of(context).textTheme.titleMedium),
                          const SizedBox(height: 8),
                          Text('Recorded: ${incident.createdAt.toLocal()}'),
                          if (incident.address != null)
                            Text('Address: ${incident.address}'),
                          if (incident.details != null)
                            Text('Details: ${incident.details}'),
                          if (incident.locationSource == 'gps')
                            Text(
                                'Location snapshot: ${incident.latitude}, ${incident.longitude}\n'
                                'Accuracy: ${incident.locationAccuracy} m; '
                                'captured ${incident.locationCapturedAt?.toLocal()}')
                          else
                            Text(incident.locationSource == 'manual'
                                ? 'Location supplied as an address or landmark.'
                                : 'No location was available. Tell the operator where you are.'),
                        ] else if (!_controller.sessionEnded) ...[
                          const SizedBox(height: 16),
                          TextField(
                              controller: _address,
                              enabled: editable,
                              maxLength: 300,
                              maxLines: 3,
                              minLines: 1,
                              decoration: const InputDecoration(
                                  labelText: 'Address or landmark (optional)',
                                  border: OutlineInputBorder())),
                          const SizedBox(height: 12),
                          TextField(
                              controller: _details,
                              enabled: editable,
                              maxLength: 1000,
                              maxLines: 5,
                              minLines: 2,
                              decoration: const InputDecoration(
                                  labelText: 'What happened? (optional)',
                                  border: OutlineInputBorder())),
                          const SizedBox(height: 8),
                          Text(_position == null
                              ? 'Device location has not been added. '
                                  'You can still request help or call.'
                              : 'Location snapshot: ${_position!.latitude}, ${_position!.longitude}\n'
                                  'Accuracy: ${_position!.accuracy.round()} m; captured ${_position!.timestamp.toLocal()}'),
                          if (_locationFailed)
                            const Text(
                                'Location unavailable. Enter a landmark or tell the operator.'),
                          OutlinedButton.icon(
                              onPressed:
                                  editable && !_locating ? _getLocation : null,
                              icon: const Icon(Icons.my_location),
                              label: Text(_locating
                                  ? 'Finding location...'
                                  : 'Add device location')),
                          if (_position != null && editable)
                            TextButton(
                                onPressed: () =>
                                    setState(() => _position = null),
                                child: const Text('Use address only')),
                          const SizedBox(height: 8),
                          FilledButton(
                              onPressed: _controller.canSubmit ? _submit : null,
                              child: const Text('Send request to Corvia')),
                        ],
                        if (_controller.operationId != null) ...[
                          const SizedBox(height: 12),
                          OutlinedButton(
                              onPressed:
                                  _controller.isBusy || _controller.sessionEnded
                                      ? null
                                      : _controller.reconcile,
                              child: const Text('Check request status')),
                        ],
                        if (_controller.phase ==
                                PatientEmergencyIntakePhase.unknown &&
                            incident == null &&
                            _controller.submittedRequest != null)
                          OutlinedButton(
                              onPressed:
                                  _controller.isBusy ? null : _controller.retry,
                              child: const Text('Retry same request')),
                        if (_controller.canStartNewRequest)
                          OutlinedButton(
                              onPressed:
                                  _controller.isBusy ? null : _newRequest,
                              child: const Text('Start a new request')),
                        if (_controller.canCancel)
                          TextButton(
                            onPressed:
                                _cancelDialogOpen ? null : _cancelRequest,
                            child: const Text('Cancel request'),
                          ),
                        if (incident != null &&
                            _controller.phase ==
                                PatientEmergencyIntakePhase.confirmed) ...[
                          const SizedBox(height: 16),
                          IncidentHistoryPanel(
                            incidentId: incident.incidentId,
                            revision:
                                '${_controller.activeUserId}:${incident.version}',
                            loader: widget.historyLoader,
                          ),
                        ],
                        if (incident != null)
                          IncidentWorkspacePanel(
                            key: ValueKey(
                                'workspace:${_controller.activeUserId}:${incident.incidentId}'),
                            incidentId: incident.incidentId,
                            enabled: _controller.phase ==
                                PatientEmergencyIntakePhase.confirmed,
                            onChanged: () => unawaited(_controller.reconcile()),
                          ),
                      ],
                    ))),
          ]),
        )),
      )),
    );
  }
}
