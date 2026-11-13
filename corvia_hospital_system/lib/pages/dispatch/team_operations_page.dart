
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../controllers/patient_emergency_intake_controller.dart'
    show createEmergencyOperationId;
import '../../models/dispatch/incident_history.dart';
import '../../services/incident_workspace_service.dart';
import '../../services/team_completion_service.dart';

import 'completion_review_panel.dart';

/// The linked case's operational controls use team IDs and server authority.
class Ws4TeamOperationsPage extends StatefulWidget {
  const Ws4TeamOperationsPage({
    super.key,
    this.ws4IncidentId,
    this.hospitalId,
    this.emsIncidentId,
    this.gateway,
  });

  final String? ws4IncidentId;
  final String? hospitalId;
  final String? emsIncidentId;
  final Ws4TeamOperationsGateway? gateway;

  @override
  State<Ws4TeamOperationsPage> createState() =>
      _Ws4TeamOperationsPageState();
}

class _Ws4TeamOperationsPageState
    extends State<Ws4TeamOperationsPage> {
  late final Ws4TeamOperationsGateway gateway;

  final reason = TextEditingController();

  StreamSubscription<AuthState>? authSubscription;

  String? actor;
  String? incidentId;
  String? error;
  String? selectedFacility;

  Map<String, dynamic>? data;

  Future<void> Function()? retry;

  int generation = 0;

  bool busy = false;
  bool stale = false;

  @override
  void initState() {
    super.initState();

    gateway =
        widget.gateway ?? SupabaseWs4TeamCompletionService();

    actor = gateway.userId;

    if (gateway is SupabaseWs4TeamCompletionService) {
      authSubscription =
          (gateway as SupabaseWs4TeamCompletionService)
              .client
              .auth
              .onAuthStateChange
              .listen((_) {
        if (gateway.userId != actor && mounted) {
          _deny();
        }
      });
    }

    unawaited(_load());
  }

  bool _owns(int token) {
    return mounted &&
        token == generation &&
        gateway.userId == actor;
  }

  void _deny() {
    if (!mounted) return;

    generation++;

    setState(() {
      data = null;
      retry = null;
      stale = true;
      busy = false;
      selectedFacility = null;
      reason.clear();
      error = const WorkspaceFailure('denied').message;
    });
  }

  Future<void> _load() async {
    final token = ++generation;

    if (actor == null || gateway.userId != actor) {
      _deny();
      return;
    }

    setState(() {
      busy = true;
      error = null;
    });

    try {
      final id = incidentId ??
          widget.ws4IncidentId ??
          await gateway.linkedId(
            widget.hospitalId!,
            widget.emsIncidentId!,
          );

      final next = await gateway.teamSnapshot(id);

      if (!_owns(token)) return;

      if (next['ws4_incident_id'] != id ||
          !isIncidentHistoryId(next['revision'])) {
        throw const WorkspaceFailure('invalid');
      }

      final rawDestination = next['destination'];

      String? destinationId;

      if (rawDestination is Map &&
          rawDestination['facility_id'] != null) {
        destinationId =
            rawDestination['facility_id'].toString();
      }

      setState(() {
        incidentId = id;
        data = next;
        busy = false;
        stale = false;
        selectedFacility = destinationId;
      });
    } catch (e) {
      if (!_owns(token)) return;

      if (e is WorkspaceFailure && e.denied) {
        _deny();
        return;
      }

      setState(() {
        busy = false;
        stale = true;
        error = e is WorkspaceFailure
            ? e.message
            : const WorkspaceFailure('unknown').message;
      });
    }
  }

  Future<void> _act(
    String action,
    Map<String, dynamic> payload, {
    String? operationId,
    String? revision,
  }) async {
    if (busy ||
        stale ||
        data == null ||
        incidentId == null) {
      return;
    }

    final op =
        operationId ?? createEmergencyOperationId();

    final expected =
        revision ?? data!['revision'] as String;

    final token = ++generation;

    setState(() {
      busy = true;
      error = null;
    });

    try {
      await gateway.teamCommand(
        incidentId!,
        op,
        expected,
        action,
        payload,
      );

      if (!_owns(token)) return;

      retry = null;
      reason.clear();

      await _load();
    } catch (e) {
      if (!_owns(token)) return;

      if (e is WorkspaceFailure && e.denied) {
        _deny();
        return;
      }

      final definitive = e is WorkspaceFailure &&
          const {
            'conflict',
            'invalid',
            'unavailable',
          }.contains(e.kind);

      setState(() {
        busy = false;
        stale = definitive;

        retry = definitive
            ? null
            : () => _act(
                  action,
                  payload,
                  operationId: op,
                  revision: expected,
                );

        error = definitive
            ? e.message
            : 'Outcome unknown. Check saved state, then '
                'retry this exact action.';
      });
    }
  }

  void _submit(
    String action, [
    Map<String, dynamic> extra = const {},
  ]) {
    final why = reason.text.trim();

    if (why.length < 5 || why.length > 1000) {
      setState(() {
        error = 'Enter a reason of 5–1000 characters.';
      });
      return;
    }

    unawaited(
      _act(
        action,
        {
          'reason': why,
          ...extra,
        },
      ),
    );
  }

  /// Confirms a potentially significant operational action.
  ///
  /// The backend still checks the actor, revision and permitted transition.
  Future<void> _confirmAndSubmit(
    String action,
    String title,
    String explanation, [
    Map<String, dynamic> extra = const {},
  ]) async {
    if (busy ||
        stale ||
        retry != null ||
        data == null ||
        incidentId == null) {
      return;
    }

    final why = reason.text.trim();

    if (why.length < 5 || why.length > 1000) {
      setState(() {
        error = 'Enter a reason of 5–1000 characters.';
      });
      return;
    }

    final selectedIncident = incidentId;
    final selectedRevision = data!['revision'];
    final incidentLabel =
        data!['incident_number'] ?? selectedIncident;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(title),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                Text(explanation),

                const SizedBox(height: 12),

                Text(
                  'Incident: $incidentLabel',
                ),

                const SizedBox(height: 8),

                Text(
                  'Recorded reason: $why',
                ),

                const SizedBox(height: 8),

                const Text(
                  'The server will verify permissions and '
                  'incident revision. Do not repeat the action '
                  'with a new operation ID if its outcome is uncertain.',
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(false);
              },
              child: const Text('Cancel'),
            ),

            FilledButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(true);
              },
              child: const Text('Confirm operation'),
            ),
          ],
        );
      },
    );

    if (confirmed != true ||
        !mounted ||
        busy ||
        stale ||
        retry != null ||
        gateway.userId != actor ||
        incidentId != selectedIncident ||
        data?['revision'] != selectedRevision) {
      return;
    }

    await _act(
      action,
      {
        'reason': why,
        ...extra,
      },
    );
  }

  static bool _validPosition(
    Object? latitude,
    Object? longitude,
  ) {
    if (latitude is! num || longitude is! num) {
      return false;
    }

    final lat = latitude.toDouble();
    final lon = longitude.toDouble();

    return lat.isFinite &&
        lon.isFinite &&
        lat >= -90 &&
        lat <= 90 &&
        lon >= -180 &&
        lon <= 180;
  }

  Future<void> _map(
    double lat,
    double lon,
  ) async {
    if (!_validPosition(lat, lon)) return;

    final url = Uri.https(
      'www.openstreetmap.org',
      '/',
      {
        'mlat': '$lat',
        'mlon': '$lon',
        'zoom': '15',
      },
    );

    bool opened = false;

    try {
      opened = await launchUrl(
        url,
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      opened = false;
    }

    if (mounted && !opened) {
      setState(() {
        error =
            'Map could not open; recorded coordinates remain visible.';
      });
    }
  }

  @override
  void dispose() {
    generation++;
    authSubscription?.cancel();
    reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = data;

    final role = snapshot?['role'];

    final supervisor = role == 'supervisor';

    final dispatch =
        role == 'dispatch' || supervisor;

    final facilities =
        (snapshot?['facilities'] as List?)
                ?.whereType<Map>()
                .map(
                  (item) =>
                      Map<String, dynamic>.from(item),
                )
                .toList() ??
            <Map<String, dynamic>>[];

    final units =
        (snapshot?['units'] as List?)
                ?.whereType<Map>()
                .map(
                  (item) =>
                      Map<String, dynamic>.from(item),
                )
                .toList() ??
            <Map<String, dynamic>>[];

    final exceptions =
        (snapshot?['exceptions'] as List?)
                ?.whereType<Map>()
                .map(
                  (item) =>
                      Map<String, dynamic>.from(item),
                )
                .toList() ??
            <Map<String, dynamic>>[];

    final canAct = !busy &&
        !stale &&
        retry == null &&
        snapshot != null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Linked team response'),
        actions: [
          IconButton(
            onPressed: busy ? null : _load,
            tooltip: 'Refresh linked response',
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),

      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics:
              const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            if (busy)
              const LinearProgressIndicator(),

            if (error != null)
              Text(
                error!,
                style: TextStyle(
                  color:
                      Theme.of(context).colorScheme.error,
                ),
              ),

            if (retry != null)
              TextButton(
                onPressed: busy ? null : retry,
                child: const Text(
                  'Retry the same team action',
                ),
              ),

            if (snapshot != null) ...[
              Text(
                '${snapshot['incident_number']} · '
                '${snapshot['status']} · '
                '${snapshot['dispatch_state']}',
                style:
                    Theme.of(context).textTheme.titleLarge,
              ),

              const SizedBox(height: 12),

              // D2.4: NEW COMPLETION REVIEW
              CompletionReviewPanel(
                snapshot: snapshot,
                isStale: stale || busy,
              ),

              const SizedBox(height: 12),

              Text(
                'Scene: '
                '${snapshot['scene_address'] ?? 'Address not captured'}',
              ),

              if (_validPosition(
                snapshot['scene_latitude'],
                snapshot['scene_longitude'],
              ))
                TextButton.icon(
                  onPressed: () => _map(
                    (snapshot['scene_latitude'] as num)
                        .toDouble(),
                    (snapshot['scene_longitude'] as num)
                        .toDouble(),
                  ),
                  icon: const Icon(
                    Icons.map_outlined,
                  ),
                  label: const Text(
                    'Open recorded scene position',
                  ),
                ),

              const SizedBox(height: 16),

              Text(
                'Fleet units',
                style:
                    Theme.of(context).textTheme.titleMedium,
              ),

              if (units.isEmpty)
                const Text(
                  'No active team unit recorded.',
                ),

              for (final unit in units)
                ListTile(
                  title: Text(
                    '${unit['role']} · '
                    '${unit['unit_number']}',
                  ),
                  subtitle: Text(
                    !_validPosition(
                      unit['latitude'],
                      unit['longitude'],
                    )
                        ? 'Position unknown or invalid'
                        : '${unit['latitude']}, '
                            '${unit['longitude']} · '
                            '${unit['location_stale'] == true ? 'STALE' : unit['location_stale'] == false ? 'not stale (server)' : 'freshness unverified'} · '
                            '${unit['location_at'] ?? 'time unknown'} · '
                            '${unit['position_source'] ?? 'source unknown'}',
                  ),
                  trailing: _validPosition(
                    unit['latitude'],
                    unit['longitude'],
                  )
                      ? IconButton(
                          onPressed: () => _map(
                            (unit['latitude'] as num)
                                .toDouble(),
                            (unit['longitude'] as num)
                                .toDouble(),
                          ),
                          icon: const Icon(
                            Icons.open_in_new,
                          ),
                        )
                      : null,
                ),

              const SizedBox(height: 16),

              Text(
                'Receiving destination',
                style:
                    Theme.of(context).textTheme.titleMedium,
              ),

              Text(
                selectedFacility == null
                    ? 'No destination selected'
                    : facilities
                            .where(
                              (facility) =>
                                  facility['facility_id'] ==
                                  selectedFacility,
                            )
                            .map(
                              (facility) =>
                                  '${facility['name']} · '
                                  '${facility['address'] ?? 'Address unknown'} · '
                                  '${facility['phone'] ?? 'No directory phone'}',
                            )
                            .firstOrNull ??
                        'Selected facility '
                            '$selectedFacility is no longer active',
              ),

              const Text(
                'Directory entries do not confirm '
                'capacity or acceptance.',
              ),

              if (role != 'backup' &&
                  facilities.isNotEmpty)
                DropdownButtonFormField<String>(
                  initialValue: facilities.any(
                    (facility) =>
                        facility['facility_id'] ==
                        selectedFacility,
                  )
                      ? selectedFacility
                      : null,
                  decoration: const InputDecoration(
                    labelText:
                        'Team receiving facility',
                  ),
                  items: [
                    for (final facility in facilities)
                      DropdownMenuItem<String>(
                        value: facility['facility_id']
                            as String,
                        child: Text(
                          '${facility['name']}',
                        ),
                      ),
                  ],
                  onChanged: canAct
                      ? (value) {
                          setState(() {
                            selectedFacility = value;
                          });
                        }
                      : null,
                ),

              if (role != 'backup')
                FilledButton.tonal(
                  onPressed:
                      canAct && selectedFacility != null
                          ? () => _submit(
                                'destination',
                                {
                                  'facility_id':
                                      selectedFacility,
                                },
                              )
                          : null,
                  child: const Text(
                    'Record destination with reason',
                  ),
                ),

              const SizedBox(height: 16),

              Text(
                'Safety exceptions',
                style:
                    Theme.of(context).textTheme.titleMedium,
              ),

              if (exceptions.isEmpty)
                const Text(
                  'No unresolved exceptions.',
                ),

              for (final exception in exceptions)
                Card(
                  child: ListTile(
                    title: Text(
                      '${exception['kind']}',
                    ),
                    subtitle: Text(
                      '${exception['reason']} · '
                      '${exception['recorded_at']}',
                    ),
                    trailing: supervisor
                        ? Wrap(
                            children: [
                              TextButton(
                                onPressed: canAct
                                    ? () => _submit(
                                          'resolve_exception',
                                          {
                                            'exception_id':
                                                exception['id'],
                                          },
                                        )
                                    : null,
                                child: const Text('Resolve'),
                              ),

                              if (const {
                                'no_patient',
                                'refusal',
                              }.contains(exception['kind']))
                                TextButton(
                                  onPressed: canAct
                                      ? () => _confirmAndSubmit(
                                            'terminal_exception',
                                            'Close linked incident as cancelled?',
                                            'This records a terminal exception. '
                                            'It is not a completed patient handover.',
                                            {
                                              'exception_id':
                                                  exception['id'],
                                            },
                                          )
                                      : null,
                                  child: const Text(
                                    'Close as cancelled',
                                  ),
                                ),
                            ],
                          )
                        : null,
                  ),
                ),

              if (role != 'backup')
                Wrap(
                  spacing: 8,
                  children: [
                    for (final kind in const [
                      'no_resource',
                      'multiple_patients',
                      'handover_failed',
                    ])
                      if (kind != 'no_resource' ||
                          dispatch)
                        OutlinedButton(
                          onPressed: canAct
                              ? () => _submit(
                                    'exception',
                                    {
                                      'kind': kind,
                                    },
                                  )
                              : null,
                          child: Text(
                            'Record '
                            '${kind.replaceAll('_', ' ')}',
                          ),
                        ),
                  ],
                ),

              if (dispatch &&
                  (supervisor ||
                      snapshot['primary_overdue'] ==
                          true))
                FilledButton.tonal(
                  onPressed: canAct
                      ? () => _confirmAndSubmit(
                            'release_primary',
                            'Release primary crew?',
                            'This releases the current primary '
                            'crew for reassignment. Ensure '
                            'dispatch has reviewed the '
                            'current response.',
                          )
                      : null,
                  child: const Text(
                    'Release primary for reassignment',
                  ),
                ),

              if (role != 'backup')
                TextField(
                  controller: reason,
                  maxLength: 1000,
                  decoration: const InputDecoration(
                    labelText:
                        'Reason for the selected action',
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
