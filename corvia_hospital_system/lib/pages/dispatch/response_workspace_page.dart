
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config/env.dart';
import '../../controllers/patient_emergency_intake_controller.dart'
    show createEmergencyOperationId;
import '../../services/incident_workspace_service.dart';
import '../../services/response_workflow_service.dart';
import '../../services/ems_handoff_service.dart';
import '../paramedic/paramedic_workspace_page.dart';

import 'team_completion_page.dart';
import 'team_operations_page.dart';
import 'triage_review_panel.dart';
import 'fleet_availability_panel.dart';
import 'fleet_readiness_panel.dart';
import 'crew_readiness_panel.dart';

/// Existing authenticated response workflow for dispatch,
/// assigned crews and authorised hospital receivers.
class ResponseWorkspacePage extends StatefulWidget {
  const ResponseWorkspacePage({
    super.key,
    this.incidentId,
    this.gateway,
    this.handoffGateway,
    this.includeClosed = false,
  });

  final String? incidentId;
  final ResponseWorkflowGateway? gateway;
  final EmsHandoffGateway? handoffGateway;
  final bool includeClosed;

  @override
  State<ResponseWorkspacePage> createState() =>
      _ResponseWorkspacePageState();
}

class _ResponseWorkspacePageState
    extends State<ResponseWorkspacePage> {
  ResponseWorkflowGateway? _gateway;
  EmsHandoffGateway? _handoffGateway;

  String? _actor;
  String? _selected;
  String? _error;
  String? _notice;

  ResponseWorkspace? _data;
  EmsHandoffStatus? _team;

  String? _teamError;
  String? _handoffOperationId;
  String? _priority;
  String? _capability;

  Map<String, dynamic>? _unit;
  List<String> _inbox = [];

  final _text = TextEditingController();

  StreamSubscription<String?>? _auth;
  Timer? _timer;

  bool _busy = false;
  bool _denied = false;
  bool _includeClosed = false;
  bool _reviewOpen = false;

  int _generation = 0;

  ({
    String incident,
    String operation,
    String version,
    String action,
    Map<String, dynamic> payload,
  })? _pending;

  bool get _editable =>
      !_busy &&
      !_denied &&
      _pending == null &&
      _error == null &&
      _data?.status == 'in_progress';

  bool get _legacyAssignmentAllowed =>
      _handoffGateway == null ||
      !const {
        'dispatcher',
        'dispatch_supervisor',
      }.contains(_data?.role) ||
      _team?.mode == 'unconfigured';

  @override
  void initState() {
    super.initState();

    _selected = widget.incidentId;
    _includeClosed = widget.includeClosed;

    try {
      _gateway = widget.gateway ?? ResponseWorkflowService();

      _handoffGateway = widget.handoffGateway ??
          (widget.gateway == null && Env.ws4TeamEmsHandoffEnabled
              ? SupabaseEmsHandoffService()
              : null);

      _actor = _gateway!.userId;

      if (_actor == null) {
        _denied = true;
        _error = const WorkspaceFailure('denied').message;
        return;
      }

      _auth = _gateway!.users.listen(
        (id) {
          if (id != _actor) {
            _invalidate();
          }
        },
        onError: (Object _) => _invalidate(),
      );

      unawaited(_refresh());

      _timer = Timer.periodic(
        const Duration(seconds: 15),
        (_) {
          if (!_busy &&
              !_denied &&
              !_reviewOpen &&
              _pending == null) {
            unawaited(_refresh());
          }
        },
      );
    } catch (_) {
      _denied = true;
      _error = const WorkspaceFailure('unavailable').message;
    }
  }

  bool _owns(int generation) {
    if (!mounted ||
        _denied ||
        generation != _generation) {
      return false;
    }

    if (_gateway?.userId != _actor) {
      _invalidate();
      return false;
    }

    return true;
  }

  void _invalidate() {
    if (!mounted) return;

    if (_reviewOpen) {
      Navigator.of(context).pop();
      _reviewOpen = false;
    }

    _generation++;
    _timer?.cancel();
    _text.clear();

    setState(() {
      _denied = true;
      _busy = false;
      _data = null;
      _team = null;
      _teamError = null;
      _handoffOperationId = null;
      _priority = null;
      _capability = null;
      _unit = null;
      _inbox = [];
      _pending = null;
      _error = const WorkspaceFailure('denied').message;
    });
  }

  void _fail(Object error) {
    if (_gateway?.userId != _actor ||
        (error is WorkspaceFailure && error.denied)) {
      _invalidate();
      return;
    }

    setState(() {
      _busy = false;
      _error = (error is WorkspaceFailure
              ? error
              : const WorkspaceFailure('unknown'))
          .message;
    });
  }

  Future<void> _refresh() async {
    if (_busy || _denied || _gateway == null) return;

    final generation = ++_generation;

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final inbox = await _gateway!.inbox(
        includeClosed: _includeClosed,
      );

      if (!_owns(generation)) {
        if (mounted && _gateway?.userId != _actor) {
          _invalidate();
        }
        return;
      }

      final unit = await _gateway!.unit();

      if (!_owns(generation)) return;

      final data = _selected == null
          ? null
          : await _gateway!.load(_selected!);

      if (!_owns(generation)) return;

      EmsHandoffStatus? team;
      String? teamError;

      if (data != null &&
          _handoffGateway != null &&
          const {
            'dispatcher',
            'dispatch_supervisor',
          }.contains(data.role)) {
        try {
          team = await _handoffGateway!.load(
            data.incidentId,
          );
        } on WorkspaceFailure catch (error) {
          if (error.denied) rethrow;
          teamError = error.message;
        } catch (_) {
          teamError = const WorkspaceFailure('unknown').message;
        }
      }

      if (!_owns(generation)) return;

      setState(() {
        _inbox = inbox;
        _data = data;
        _team = team;
        _teamError = teamError;

        if (team?.linked == true) {
          _handoffOperationId = null;
        }

        _unit = unit;
        _busy = false;
      });
    } catch (error) {
      if (_owns(generation)) {
        _fail(error);
      } else if (mounted && _gateway?.userId != _actor) {
        _invalidate();
      }
    }
  }

  Future<void> _handoffToTeam() async {
    final data = _data;
    final team = _team;
    final gateway = _handoffGateway;

    if (!_editable ||
        data == null ||
        !data.canManage ||
        team?.canHandoff != true ||
        team?.hospitalId == null ||
        gateway == null ||
        _priority == null ||
        _capability == null) {
      return;
    }

    final generation = ++_generation;

    final operation =
        _handoffOperationId ?? createEmergencyOperationId();

    _handoffOperationId = operation;

    setState(() {
      _busy = true;
      _teamError = null;
    });

    try {
      final linked = await gateway.handoff(
        data.incidentId,
        team!.hospitalId!,
        operation,
        _priority!,
        _capability!,
      );

      if (!_owns(generation)) return;

      setState(() {
        _team = linked;
        _handoffOperationId = null;
        _busy = false;
        _notice =
            'Team EMS incident created. Open its workspace to assign a crew.';
      });

      await _refresh();
    } catch (error) {
      if (!_owns(generation)) return;

      if (error is WorkspaceFailure && error.denied) {
        _invalidate();
        return;
      }

      final conflict =
          error is WorkspaceFailure && error.kind == 'conflict';

      setState(() {
        _busy = false;

        if (conflict) {
          _handoffOperationId = null;
        }

        _teamError = conflict
            ? 'Handoff was rejected. Refresh its status before trying a new handoff.'
            : 'Handoff not confirmed. Refresh its status, then retry the '
                'same handoff if it is still unlinked.';
      });
    }
  }

  Future<void> _act(
    String action,
    Map<String, dynamic> payload,
  ) async {
    if (!_editable || _data == null) return;

    _pending = (
      incident: _data!.incidentId,
      operation: createEmergencyOperationId(),
      version: _data!.version,
      action: action,
      payload: Map.unmodifiable({
        ...payload,
        'text': _text.text.trim(),
        'occurred_at': payload['occurred_at'] ??
            DateTime.now().toUtc().toIso8601String(),
      }),
    );

    await _sendPending();
  }

  Future<void> _shareLocation() async {
    if (_busy ||
        _denied ||
        _pending != null ||
        _error != null ||
        _unit == null) {
      return;
    }

    final unit = _unit!;
    final generation = ++_generation;

    setState(() => _busy = true);

    try {
      var permission = await Geolocator.checkPermission();

      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw StateError('Location unavailable');
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 12),
        ),
      );

      if (!_owns(generation)) return;

      setState(() => _busy = false);

      _pending = (
        incident: unit['id'] as String,
        operation: createEmergencyOperationId(),
        version: unit['version'] as String,
        action: 'unit_location',
        payload: Map.unmodifiable({
          'latitude': position.latitude,
          'longitude': position.longitude,
          'accuracy_metres': position.accuracy,
          'occurred_at':
              position.timestamp.toUtc().toIso8601String(),
        }),
      );

      await _sendPending();
    } catch (_) {
      if (_owns(generation)) {
        setState(() {
          _busy = false;
          _notice =
              'Location could not be obtained. The previous position remains unchanged.';
        });
      }
    }
  }

  Future<void> _sendPending() async {
    final p = _pending;

    if (p == null || _busy || _denied) return;

    final generation = ++_generation;

    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });

    try {
      if (p.action == 'readiness') {
        await _gateway!.reviewReadiness(
          p.incident,
          p.operation,
          p.version,
          p.payload,
        );
      } else if (p.action == 'unit_location') {
        await _gateway!.unitLocation(
          p.incident,
          p.operation,
          p.version,
          p.payload,
        );
      } else {
        await _gateway!.command(
          p.incident,
          p.operation,
          p.version,
          p.action,
          p.payload,
        );
      }

      if (!_owns(generation)) return;

      setState(() {
        _busy = false;
        _pending = null;
        _text.clear();

        _notice =
            'Saved to Corvia. This is not a message read receipt.';

        if (p.action == 'reject' ||
            p.action == 'handover_accept') {
          _selected = null;
          _data = null;
          _team = null;
          _teamError = null;
          _handoffOperationId = null;
          _priority = null;
          _capability = null;
        }
      });

      await _refresh();
    } catch (error) {
      if (!_owns(generation)) {
        if (mounted && _gateway?.userId != _actor) {
          _invalidate();
        }
        return;
      }

      if (error is WorkspaceFailure &&
          const {
            'conflict',
            'invalid',
            'unavailable',
          }.contains(error.kind)) {
        _pending = null;
      }

      _fail(error);
    }
  }

  @override
  void dispose() {
    _generation++;
    _timer?.cancel();
    unawaited(_auth?.cancel());
    _text.dispose();
    super.dispose();
  }

  Widget _button(
    String label,
    String action,
    Map<String, dynamic> payload, {
    bool allowed = true,
  }) {
    return OutlinedButton(
      onPressed:
          _editable && allowed ? () => _act(action, payload) : null,
      child: Text(label),
    );
  }

  Widget _map(
    String label,
    Map<String, dynamic> point, {
    bool unit = false,
  }) {
    final lat = point['latitude'];
    final lon = point['longitude'];
    final at = DateTime.tryParse(
      point['location_at']?.toString() ?? '',
    );

    final stale = unit && point['location_fresh'] != true;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$label: ${lat == null || lon == null ? 'location unavailable' : '$lat, $lon'}'
          '${stale ? ' · STALE' : ''}',
        ),
        Text(
          'Source: ${point['location_source'] ?? 'directory; freshness unverified'}'
          ' · Captured: ${at?.toLocal() ?? 'unknown'}'
          ' · Accuracy: ${point['accuracy_metres'] ?? 'unknown'} m',
        ),
        if (lat != null && lon != null)
          TextButton(
            onPressed: _denied || _busy
                ? null
                : () async {
                    final url = Uri.https(
                      'www.openstreetmap.org',
                      '/',
                      {
                        'mlat': '$lat',
                        'mlon': '$lon',
                      },
                    );

                    var opened = false;

                    try {
                      opened = await launchUrl(
                        url,
                        mode: LaunchMode.externalApplication,
                      );
                    } catch (_) {}

                    if (mounted && !opened) {
                      setState(() {
                        _notice =
                            'Map could not open. Coordinates remain displayed.';
                      });
                    }
                  },
            child: const Text(
              'Open these coordinates in OpenStreetMap',
            ),
          ),
      ],
    );
  }

  Widget _teamHandoffPanel(ResponseWorkspace data) {
    final team = _team;

    if (_handoffGateway == null ||
        !const {
          'dispatcher',
          'dispatch_supervisor',
        }.contains(data.role)) {
      return const SizedBox.shrink();
    }

    final emsIncidentNumber =
        int.tryParse(team?.emsIncidentId ?? '');

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Fleet & Paramedic handoff',
              style: Theme.of(context).textTheme.titleLarge,
            ),

            if (_teamError != null)
              Text(
                _teamError!,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                ),
              ),

            if (team == null)
              const Text(
                'Team routing could not be verified. Vehicle assignment '
                'is disabled until it can be refreshed.',
              ),

            if (team?.mode == 'unconfigured')
              const Text(
                'No reviewed team EMS route is configured for this '
                'organisation. The existing WS4 response workspace remains in use.',
              ),

            if (team?.mode == 'team' && team?.teamAccess == false)
              const Text(
                'This account needs current Fleet/Paramedic membership '
                'for the routed hospital. Do not create a separate incident.',
              ),

            if (team?.linked == true) ...[
              Text(
                'Linked EMS incident ${team!.emsNumber} '
                '(ID ${team.emsIncidentId})',
              ),
              Text(
                'EMS status: ${team.emsStatus} · dispatch: '
                '${team.dispatchState}. This is the team resource workflow.',
              ),

              TextButton.icon(
                onPressed: !_busy &&
                        team.teamAccess &&
                        emsIncidentNumber != null
                    ? () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => ParamedicWorkspacePage(
                              initialHospitalId: team.hospitalId,
                              initialIncidentId: emsIncidentNumber,
                            ),
                          ),
                        )
                    : null,
                icon: const Icon(Icons.open_in_new),
                label: const Text(
                  'Open Fleet & Paramedic workspace',
                ),
              ),

              if (data.canManage)
                TextButton.icon(
                  onPressed: !_busy && team.teamAccess
                      ? () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => Ws4BackupPage(
                                incidentId: data.incidentId,
                              ),
                            ),
                          )
                      : null,
                  icon: const Icon(Icons.group_add_outlined),
                  label: const Text('Review backup crew'),
                ),

              TextButton.icon(
                onPressed: !_busy && team.teamAccess
                    ? () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => Ws4TeamOperationsPage(
                              ws4IncidentId: data.incidentId,
                            ),
                          ),
                        )
                    : null,
                icon: const Icon(Icons.fact_check_outlined),
                label: const Text(
                  'Team operations and destination',
                ),
              ),
            ],

            if (team?.mode == 'team' &&
                team?.linked == false &&
                team?.teamAccess == true) ...[
              const Text(
                'A claimed dispatcher must choose the response priority '
                'and minimum clinical capability. Confirm the scene details '
                'before handing off; the team will assign its own unit and crew.',
              ),

              DropdownButtonFormField<String>(
                key: ValueKey('${data.incidentId}:priority'),
                initialValue: _priority,
                decoration: const InputDecoration(
                  labelText: 'Response priority',
                ),
                items: [
                  for (final value in [
                    'Critical',
                    'High',
                    'Medium',
                    'Low',
                  ])
                    DropdownMenuItem(
                      value: value,
                      child: Text(value),
                    ),
                ],
                onChanged: _handoffOperationId == null && !_busy
                    ? (value) => setState(() {
                          _priority = value;
                        })
                    : null,
              ),

              DropdownButtonFormField<String>(
                key: ValueKey('${data.incidentId}:capability'),
                initialValue: _capability,
                decoration: const InputDecoration(
                  labelText: 'Minimum crew capability',
                ),
                items: [
                  for (final value in [
                    'BLS',
                    'ILS',
                    'ALS',
                  ])
                    DropdownMenuItem(
                      value: value,
                      child: Text(value),
                    ),
                ],
                onChanged: _handoffOperationId == null && !_busy
                    ? (value) => setState(() {
                          _capability = value;
                        })
                    : null,
              ),

              FilledButton(
                onPressed: team!.canHandoff &&
                        _editable &&
                        _priority != null &&
                        _capability != null
                    ? _handoffToTeam
                    : null,
                child: Text(
                  _handoffOperationId == null
                      ? 'Create linked team EMS incident'
                      : 'Retry the same handoff',
                ),
              ),

              if (!team.canHandoff)
                const Text(
                  'Only the current WS4 claim owner can hand off an '
                  'uncommitted incident. Refresh after resolving any prior '
                  'response or provider commitment.',
                ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _reviewReadiness(
    Map<String, dynamic> unit,
  ) async {
    if (!_editable || _text.text.trim().isEmpty) return;

    final generation = _generation;
    final reason = _text.text.trim();

    final checks = <String, bool>{
      for (final key in [
        'inspection',
        'equipment',
        'oxygen',
        'fuel',
        'communications',
        'cleaning',
        'documents',
        'no_faults',
        'capability',
      ])
        key: false,
    };

    _reviewOpen = true;

    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: Text('Readiness: ${unit['label']}'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Confirm only checks you have independently verified. '
                    'Any unchecked item marks the unit unavailable. '
                    'The review expires in 8 hours; this demo duration '
                    'needs operational approval before real use.',
                  ),
                  for (final key in checks.keys)
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        key.replaceAll('_', ' '),
                      ),
                      value: checks[key],
                      onChanged: (value) {
                        update(() {
                          checks[key] = value ?? false;
                        });
                      },
                    ),
                  Text('Review reason: $reason'),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Record review'),
            ),
          ],
        ),
      ),
    );

    _reviewOpen = false;

    if (accepted != true ||
        !_owns(generation) ||
        !_editable) {
      return;
    }

    _pending = (
      incident: unit['id'] as String,
      operation: createEmergencyOperationId(),
      version: unit['version'] as String,
      action: 'readiness',
      payload: Map.unmodifiable({
        ...checks,
        'text': reason,
        'valid_until': DateTime.now()
            .toUtc()
            .add(const Duration(hours: 8))
            .toIso8601String(),
      }),
    );

    await _sendPending();
  }

  Widget _assignment(Map<String, dynamic> assignment) {
    final data = _data!;

    final payload = {
      'assignment_id': assignment['id'],
    };

    final crew = data.role == 'crew' &&
        assignment['mine'] == true;

    final active = assignment['active'] == true;

    final next = {
      'acknowledged': 'en_route',
      'en_route': 'on_scene',
      'on_scene': 'transporting',
      'transporting': 'at_hospital',
      'at_hospital': 'handover_requested',
    }[assignment['state']];

    final deadline = DateTime.tryParse(
      assignment['deadline']?.toString() ?? '',
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${assignment['unit']} · '
              '${assignment['crew']} · '
              '${assignment['purpose']}',
              style: Theme.of(context).textTheme.titleMedium,
            ),

            SelectableText(
              'Assignment ${assignment['id']}',
            ),

            Text(
              'State: ${assignment['state'].toString().replaceAll('_', ' ')}'
              '${assignment['overdue'] == true ? ' · ACKNOWLEDGEMENT OVERDUE' : ''}',
            ),

            if (assignment['state'] == 'offered')
              Text(
                'Acknowledge by '
                '${deadline?.toLocal() ?? 'unknown'}',
              ),

            if (assignment['attention'] != null)
              Text(
                'Supervisor attention: ${assignment['attention']}',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                ),
              ),

            if (active && assignment['crew_available'] != true)
              const Text(
                'Crew eligibility changed. Contact dispatch '
                'for review or reassignment.',
              ),

            if (assignment['destination_id'] != null)
              Text(
                'Destination: ${data.destinations.where(
                      (destination) =>
                          destination['id'] ==
                          assignment['destination_id'],
                    ).map(
                      (destination) => destination['label'],
                    ).firstOrNull ?? assignment['destination_id']}',
              ),

            Text(
              assignment['patient_confirmed'] == true
                  ? 'Patient match recorded by crew.'
                  : 'Patient match has not been recorded by crew.',
            ),

            _map(
              'Unit position',
              assignment,
              unit: true,
            ),

            if (active)
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  if (crew && assignment['state'] == 'offered') ...[
                    _button(
                      'Acknowledge',
                      'acknowledge',
                      payload,
                      allowed: assignment['overdue'] != true &&
                          assignment['crew_available'] == true,
                    ),

                    _button(
                      'Reject with reason',
                      'reject',
                      payload,
                      allowed: _text.text.trim().isNotEmpty &&
                          assignment['overdue'] != true,
                    ),
                  ],

                  if (crew &&
                      assignment['state'] == 'on_scene' &&
                      assignment['patient_confirmed'] != true)
                    _button(
                      'Record patient match with evidence',
                      'confirm_patient',
                      payload,
                      allowed: assignment['attention'] == null &&
                          _text.text.trim().isNotEmpty,
                    ),

                  if (crew && next != null)
                    _button(
                      'Record ${next.replaceAll('_', ' ')}',
                      'progress',
                      {
                        ...payload,
                        'state': next,
                      },
                      allowed: assignment['attention'] == null &&
                          assignment['crew_available'] == true &&
                          (next != 'transporting' ||
                              (assignment['patient_confirmed'] ==
                                      true &&
                                  assignment['destination_id'] !=
                                      null)) &&
                          (next != 'handover_requested' ||
                              _text.text.trim().isNotEmpty),
                    ),

                  if (data.canManage &&
                      assignment['overdue'] == true)
                    _button(
                      'Release timed-out offer',
                      'expire',
                      payload,
                    ),

                  if (data.canManage &&
                      (assignment['state'] == 'offered' ||
                          data.role == 'dispatch_supervisor'))
                    _button(
                      'Withdraw / reassign with reason',
                      'withdraw',
                      payload,
                      allowed: _text.text.trim().isNotEmpty,
                    ),

                  if (data.role == 'dispatch_supervisor' &&
                      assignment['attention'] != null)
                    _button(
                      'Resolve exception with reason',
                      'resolve_exception',
                      payload,
                      allowed: _text.text.trim().isNotEmpty,
                    ),

                  if (data.role == 'receiver' &&
                      assignment['state'] ==
                          'handover_requested')
                    _button(
                      'Confirm patient received',
                      'handover_accept',
                      payload,
                      allowed: _text.text.trim().isNotEmpty,
                    ),

                  if (data.canManage ||
                      crew ||
                      data.role == 'receiver')
                    _button(
                      'Send response-team message',
                      'message',
                      payload,
                      allowed: _text.text.trim().isNotEmpty,
                    ),
                ],
              ),

            if (active && (crew || data.canManage)) ...[
              Wrap(
                spacing: 8,
                children: [
                  for (final reason in [
                    'no_patient',
                    'unsafe_scene',
                    'multiple_patients',
                    'refusal',
                    'unit_failure',
                    'backup',
                    'handover_failed',
                  ])
                    _button(
                      reason.replaceAll('_', ' '),
                      'exception',
                      {
                        ...payload,
                        'reason': reason,
                      },
                      allowed: _text.text.trim().isNotEmpty,
                    ),
                ],
              ),

              if (!const {
                    'at_hospital',
                    'handover_requested',
                  }.contains(assignment['state']) ||
                  (data.role == 'dispatch_supervisor' &&
                      assignment['attention'] ==
                          'handover_failed'))
                DropdownButtonFormField<String>(
                  key: ValueKey(
                    '${assignment['id']}:${data.version}:destination',
                  ),
                  decoration: const InputDecoration(
                    labelText:
                        'Select receiving hospital (reason required)',
                  ),
                  items: [
                    for (final hospital in data.destinations)
                      DropdownMenuItem(
                        value: hospital['id'] as String,
                        child: Text(
                          hospital['label'] as String,
                        ),
                      ),
                  ],
                  onChanged:
                      _editable && _text.text.trim().isNotEmpty
                          ? (id) {
                              if (id != null) {
                                unawaited(
                                  _act(
                                    'destination',
                                    {
                                      ...payload,
                                      'hospital_id': id,
                                    },
                                  ),
                                );
                              }
                            }
                          : null,
                ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Emergency response workspace'),
        actions: [
          IconButton(
            tooltip: 'Refresh response',
            onPressed: _busy || _denied ? null : _refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),

      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'Corvia response team. ER24 is not connected. '
              'Opening this screen does not acknowledge an assignment.',
            ),

            if (_busy)
              const LinearProgressIndicator(),

            if (_error != null)
              Text(
                _error!,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                ),
              ),

            if (_notice != null)
              Text(_notice!),

            if (_unit != null &&
                !_denied &&
                _legacyAssignmentAllowed) ...[
              Text(
                'Your unit: ${_unit!['label']} · position recorded '
                '${_unit!['location_at'] ?? 'unknown'}',
              ),

              OutlinedButton(
                onPressed:
                    _busy || _pending != null || _error != null
                        ? null
                        : _shareLocation,
                child: const Text(
                  'Share current device location once',
                ),
              ),
            ],

            if (_pending != null) ...[
              const Text(
                'Outcome unknown. Refresh saved state or retry this '
                'exact action. Do not submit a replacement action.',
              ),

              OutlinedButton(
                onPressed:
                    _busy || _denied ? null : _sendPending,
                child: const Text(
                  'Retry same response action',
                ),
              ),
            ],

            if (!_denied)
              SwitchListTile(
                title: const Text(
                  'Include completed incidents (dispatch access)',
                ),
                value: _includeClosed,
                onChanged: _busy || _pending != null
                    ? null
                    : (value) {
                        setState(() {
                          _includeClosed = value;
                          _selected = null;
                          _data = null;
                          _team = null;
                          _teamError = null;
                          _handoffOperationId = null;
                          _priority = null;
                          _capability = null;
                          _text.clear();
                        });

                        unawaited(_refresh());
                      },
              ),

            if (!_denied)
              DropdownButtonFormField<String>(
                key: ValueKey(
                  '$_selected:${_inbox.join(',')}',
                ),
                initialValue: _inbox.contains(_selected)
                    ? _selected
                    : null,
                decoration: const InputDecoration(
                  labelText: 'Incident',
                ),
                items: [
                  for (final id in _inbox)
                    DropdownMenuItem(
                      value: id,
                      child: Text('Incident #$id'),
                    ),
                ],
                onChanged: _busy || _pending != null
                    ? null
                    : (id) {
                        setState(() {
                          _selected = id;
                          _data = null;
                          _team = null;
                          _teamError = null;
                          _handoffOperationId = null;
                          _priority = null;
                          _capability = null;
                          _text.clear();
                        });

                        unawaited(_refresh());
                      },
              ),

            if (!_busy && !_denied && _inbox.isEmpty)
              const Text(
                'No active incidents are assigned to your current access.',
              ),

            if (data != null && !_denied) ...[
              // D2.2 TRIAGE REVIEW
              Ws4TriageReviewPanel(
                incidentId: data.incidentId,
                status: data.status,
                priority: data.priority,
                sceneDetails: data.sceneDetails,
                location: data.location,
                assignments: data.assignments,
                events: data.events,
                lastVerifiedAt: data.serverTime,
              ),

              const SizedBox(height: 12),

              Text(
                'Incident #${data.incidentId} · '
                '${data.status} · ${data.role} '
                '· version ${data.version}',
              ),

              Text(
                'Dispatch priority: ${data.priority}',
              ),

              if (data.sceneDetails != null)
                Text(
                  'Patient-reported scene details: '
                  '${data.sceneDetails}',
                ),

              Text(
                'Last verified ${data.serverTime.toLocal()}. '
                'Refreshes every 15 seconds; '
                'updates require a connection.',
              ),

              if (_error != null)
                const Text(
                  'Displayed information may be outdated. '
                  'Actions are disabled until a successful refresh.',
                ),

              _map(
                'Recorded incident location',
                data.location,
              ),

              // EXISTING TEAM EMS HANDOFF
              _teamHandoffPanel(data),

              if (data.location['address'] != null)
                Text(
                  'Patient-provided address: '
                  '${data.location['address']}',
                ),

              TextField(
                controller: _text,
                enabled: _editable,
                maxLength: 900,
                minLines: 1,
                maxLines: 3,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText:
                      'Message, reason or handover summary',
                  helperText:
                      'Visible to the assigned response team. '
                      'Use only necessary information.',
                ),
              ),

              // D2.3 FLEET AVAILABILITY AND READINESS
              if (data.canManage &&
                  _legacyAssignmentAllowed) ...[
                Text(
                  'Units',
                  style: Theme.of(context).textTheme.titleLarge,
                ),

                const SizedBox(height: 8),

                FleetAvailabilityPanel(
                  units: data.units
                      .map(
                        (unit) =>
                            Map<String, dynamic>.from(unit),
                      )
                      .toList(),

                  assignments: data.assignments
                      .map(
                        (assignment) =>
                            Map<String, dynamic>.from(assignment),
                      )
                      .toList(),

                  canAct: _editable,
                  hasReviewReason:
                      _text.text.trim().isNotEmpty,

                  onReviewReadiness: (unit) {
                    unawaited(_reviewReadiness(unit));
                  },

                  onAssignPrimary: (unit) {
                    unawaited(
                      _act(
                        'assign',
                        {
                          'unit_id': unit['id'],
                          'unit_version': unit['version'],
                          'purpose': 'primary',
                        },
                      ),
                    );
                  },

                  onAssignBackup: (unit) {
                    unawaited(
                      _act(
                        'assign',
                        {
                          'unit_id': unit['id'],
                          'unit_version': unit['version'],
                          'purpose': 'backup',
                        },
                      ),
                    );
                  },
                ),

                FleetReadinessPanel(
                  units: data.units
                      .map(
                        (unit) =>
                            Map<String, dynamic>.from(unit),
                      )
                      .toList(),
                  snapshotVerifiedAt: data.serverTime,
                ),
              ],

              // D2.3 CREW READINESS
              if (data.assignments.isNotEmpty)
                CrewReadinessPanel(
                  assignments: data.assignments
                      .map(
                        (assignment) =>
                            Map<String, dynamic>.from(assignment),
                      )
                      .toList(),
                  snapshotVerifiedAt: data.serverTime,
                ),

              // EXISTING ASSIGNMENT ACTIONS
              for (final assignment in data.assignments)
                _assignment(assignment),

              if (data.destinations.isNotEmpty)
                ExpansionTile(
                  title: const Text(
                    'Receiving hospital locations',
                  ),
                  children: [
                    for (final hospital
                        in data.destinations) ...[
                      _map(
                        '${hospital['label']}',
                        hospital,
                      ),

                      SelectableText(
                        'Directory contact: '
                        '${hospital['phone'] ?? 'not recorded'}'
                        ' · ${hospital['address'] ?? 'address not recorded'}'
                        '\nDirectory updated: '
                        '${hospital['directory_updated_at'] ?? 'unknown'}. '
                        'Clinical capabilities and current receiving '
                        'capacity are not verified; confirm with the '
                        'hospital before choosing it.',
                      ),
                    ],
                  ],
                ),

              Text(
                'Saved response timeline',
                style: Theme.of(context).textTheme.titleLarge,
              ),

              const Text(
                'Messages shown here are persisted. '
                'No delivery or read receipt is implied.',
              ),

              if (data.olderEvents)
                const Text(
                  'Latest 100 events shown. '
                  'Earlier events remain in the audit record.',
                ),

              for (final event in data.events)
                ListTile(
                  title: Text(
                    '${event['command']} · '
                    '${event['actor_role']}',
                  ),
                  subtitle: Text(
                    '${event['detail']}'
                    '\nActor ${event['actor_id'] ?? 'not recorded'}'
                    ' · version ${event['version']}'
                    '\nOccurred ${event['occurred_at']}'
                    ' · saved ${event['recorded_at']}',
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
