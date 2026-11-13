import 'dart:async';
import 'package:flutter/material.dart';
import '../../services/paramedic_workspace_service.dart';
import 'paramedic_forms.dart';
import 'paramedic_incident_page.dart';
import 'paramedic_operations_panel.dart';
import 'fleet_live_unit_card.dart';

class ParamedicWorkspacePage extends StatefulWidget {
  const ParamedicWorkspacePage(
      {super.key,
      this.showAppBar = true,
      this.initialSection = 'Incidents',
      this.title = 'Fleet & Paramedic',
      this.service,
      this.initialHospitalId,
      this.initialIncidentId,
      this.onSignOut});
  final bool showAppBar;

  /// Set when this is the account's home screen (dispatchers, fleet
  /// managers), which has no other way to sign out.
  final VoidCallback? onSignOut;
  final ParamedicWorkspaceService? service;
  final String initialSection, title;
  final String? initialHospitalId;
  final int? initialIncidentId;
  @override
  State<ParamedicWorkspacePage> createState() => _ParamedicWorkspacePageState();
}

class _ParamedicWorkspacePageState extends State<ParamedicWorkspacePage>
    with WidgetsBindingObserver {
  late final service = widget.service ?? ParamedicWorkspaceService();
  List<EmsRow> hospitals = [];
  EmsRow data = {};
  String? hospital, error;
  bool busy = true, locked = false;
  int _readGeneration = 0;
  DateTime activity = DateTime.now();
  Timer? timer;
  StreamSubscription<dynamic>? authSubscription;
  int tab = 0;
  bool initialSectionApplied = false;
  bool initialIncidentOpened = false;
  FleetUnitFilter vehicleFilter = FleetUnitFilter.all;
  bool get admin => data['is_admin'] == true;
  bool get dispatch => admin || data['can_dispatch'] == true;
  @override
  void initState() {
    super.initState();
    service.addListener(_sessionChanged);
    WidgetsBinding.instance.addObserver(this);
    _start();
    authSubscription = service.client.auth.onAuthStateChange.listen((event) {
      if (service.userId != null &&
          service.client.auth.currentUser?.id != service.userId) {
        _lock();
      }
    });
    timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!locked &&
          DateTime.now().difference(activity) > const Duration(minutes: 15)) {
        _lock();
      }
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    authSubscription?.cancel();
    service.removeListener(_sessionChanged);
    service.lock();
    service.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _lock();
    }
  }

  void _sessionChanged() {
    if (service.session == null && !locked) _lock();
  }

  void _lock() {
    if (!mounted || locked) return;
    _readGeneration++;
    locked = true;
    service.lock();
    final route = ModalRoute.of(context);
    Navigator.of(context).popUntil((r) => r == route);
    setState(() {
      locked = true;
      data = {};
    });
  }

  Future<void> _start() async {
    final generation = ++_readGeneration;
    final actor = service.client.auth.currentUser?.id;
    setState(() {
      busy = true;
      error = null;
      data = {};
    });
    try {
      hospitals = await service.access();
      if (!mounted || generation != _readGeneration) return;
      if (actor == null || service.client.auth.currentUser?.id != actor) {
        throw StateError('Workspace account changed. Reopen it to continue.');
      }
      if (hospitals.isEmpty) {
        throw StateError(
            'No workspace access. Ask the hospital administrator to link your existing account and verify your current credentials.');
      }
      hospital ??= widget.initialHospitalId ?? hospitals.first['id'].toString();
      if (!hospitals.any((entry) => entry['id'].toString() == hospital)) {
        throw StateError('Linked incident hospital access is unavailable.');
      }
      await service.open(hospital!);
      final next = await service.load();
      if (!mounted || generation != _readGeneration) return;
      data = next;
      if (!initialSectionApplied) {
        tab = admin
            ? (widget.initialSection != 'Vehicles' ? 3 : 0)
            : dispatch && widget.initialSection == 'Fleet overview'
                ? 1
                : 0;
        initialSectionApplied = true;
      }
      locked = false;
      activity = DateTime.now();
    } catch (e) {
      if (generation == _readGeneration) {
        data = {};
        error = emsError(e);
      }
    } finally {
      if (mounted && generation == _readGeneration) {
        setState(() => busy = false);
      }
    }
    if (mounted &&
        error == null &&
        widget.initialIncidentId != null &&
        !initialIncidentOpened) {
      initialIncidentOpened = true;
      unawaited(_incident({'incident_id': widget.initialIncidentId}));
    }
  }

  Future<void> refresh() async {
    final generation = ++_readGeneration;
    setState(() => busy = true);
    try {
      final next = await service.load();
      if (mounted && generation == _readGeneration) {
        setState(() {
          data = next;
          error = null;
        });
      }
    } catch (e) {
      if (mounted && generation == _readGeneration) {
        setState(() {
          data = {};
          error = emsError(e);
        });
      }
    } finally {
      if (mounted && generation == _readGeneration) {
        setState(() => busy = false);
      }
    }
  }

  List<EmsRow> rows(String key) => emsRows(data[key]);
  Future<EmsRow?> form(String action, String title,
      {List<EmsField>? fields,
      EmsRow initial = const {},
      EmsRow extra = const {}}) async {
    final result = await showDialog<EmsRow>(
        context: context,
        barrierDismissible: false,
        builder: (_) => EmsFormDialog(
            title: title,
            fields: fields ?? emsFields(action),
            initial: initial,
            save: (p, op) =>
                service.command(action, {...extra, ...p}, operationId: op)));
    if (result != null && mounted) await refresh();
    return result;
  }

  Future<void> _incident(EmsRow row) async {
    await Navigator.push(
        context,
        MaterialPageRoute<void>(
            builder: (_) => ParamedicIncidentPage(
                service: service,
                incidentId: row['incident_id'] as int,
                catalog: data,
                onActivity: () => activity = DateTime.now())));
    if (mounted && !locked) await refresh();
  }

  Widget button(String title, VoidCallback onTap,
          [IconData icon = Icons.add]) =>
      FilledButton.tonalIcon(
          onPressed: busy || locked || error != null ? null : onTap,
          icon: Icon(icon),
          label: Text(title));
  Widget cards(List<EmsRow> values, Widget Function(EmsRow) item) =>
      values.isEmpty
          ? const Padding(
              padding: EdgeInsets.all(24), child: Text('No records yet.'))
          : Column(children: values.map(item).toList());
  Widget _incidents() =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (dispatch)
          button(
              'New incident',
              () => form('incident', 'New incident', initial: const {
                    'priority': 'Medium',
                    'required_capability': 'BLS',
                    'incident_type': 'Medical Emergency'
                  })),
        const SizedBox(height: 12),
        const Text(
            'Most recent 200 incidents • Refresh to receive current assignments'),
        cards(
            rows('incidents'),
            (r) => Card(
                child: ListTile(
                    isThreeLine: true,
                    leading: const Icon(Icons.emergency),
                    title: Text('${r['incident_number']} • ${r['priority']}'),
                    subtitle: Text(
                        '${r['incident_type']} • ${r['dispatch_state'] ?? r['status']}\n${r['scene_address'] ?? 'Address not captured'}${_overdue(r) ? ' • CREW ACKNOWLEDGEMENT OVERDUE' : ''}'),
                    trailing: Chip(label: Text('${r['status']}')),
                    onTap: () => _incident(r)))),
      ]);
  Widget _units() {
    final allUnits = rows('units_actual');
    final visibleUnits = vehicleFilter == FleetUnitFilter.all
        ? allUnits
        : allUnits.where((u) => classifyFleetUnit(u) == vehicleFilter).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              'Hospital vehicles',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            button(
              'Add vehicle',
              () => form('unit', 'Add vehicle', initial: const {
                'vehicle_type': 'Ambulance',
                'response_capability': 'BLS'
              }),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Authorised hospital Fleet records. Refresh for the latest backend state. '
          'A listed vehicle is not automatically available for emergency dispatch.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final filter in FleetUnitFilter.values)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(filter.label),
                    selected: vehicleFilter == filter,
                    onSelected: (_) => setState(() => vehicleFilter = filter),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (visibleUnits.isEmpty)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              allUnits.isEmpty
                  ? 'No vehicles returned for this hospital.'
                  : 'No vehicles match this status filter.',
            ),
          )
        else
          for (final unit in visibleUnits)
            FleetLiveUnitCard(
              key: ValueKey('fleet-unit-${unit['unit_id']}'),
              unit: unit,
              onEdit: () => form(
                'unit',
                'Edit vehicle',
                initial: unit,
                extra: {'id': unit['unit_id']},
              ),
              onChangeReadiness: () => form(
                'unit_status',
                'Vehicle readiness',
                extra: {
                  'unit_id': unit['unit_id'],
                  'unit_revision': unit['availability_revision'],
                },
                fields: [
                  EmsField(
                    'status',
                    'Readiness',
                    required: true,
                    options: choices([
                      'ready',
                      'idle',
                      'maintenance',
                      'off_duty',
                    ]),
                  ),
                  const EmsField(
                    'reason',
                    'Reason',
                    required: true,
                    max: 1000,
                  ),
                ],
              ),
            ),
      ],
    );
  }

  Widget _staff() =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        button(
            'Add staff member',
            () => form('member', 'Register paramedic', initial: const {
                  'verification_status': 'pending',
                  'is_active': true
                })),
        const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text(
                'Use an existing account email. Verify qualifications and expiry before setting credentials to verified.')),
        cards(
            rows('ems_members'),
            (r) => Card(
                child: ListTile(
                    title: Text(
                        '${r['first_name']} ${r['last_name'] ?? ''} • ${r['employee_number']}'),
                    subtitle: Text(
                        '${r['email']}\n${r['verification_status']} • expiry ${r['verification_expiry_date'] ?? 'not recorded'}'),
                    isThreeLine: true,
                    trailing: IconButton(
                        tooltip: 'Edit staff',
                        icon: const Icon(Icons.edit),
                        onPressed: () => form('member', 'Edit staff member',
                            initial: r, extra: {'id': r['member_id']})))))
      ]);
  Map<String, String> options(String key, String id, String label) =>
      {for (final r in rows(key)) r[id].toString(): r[label].toString()};
  Widget _shifts() =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(spacing: 8, runSpacing: 8, children: [
          button(
              'Start crew shift',
              () => form('shift', 'Start crew shift', initial: {
                    'start_datetime': DateTime.now().toUtc().toIso8601String(),
                    'end_datetime': DateTime.now()
                        .toUtc()
                        .add(const Duration(hours: 12))
                        .toIso8601String()
                  }, fields: [
                    EmsField('member_id', 'Lead paramedic',
                        required: true,
                        options: {
                          for (final r in rows('ems_members'))
                            r['member_id'].toString():
                                '${r['first_name']} ${r['last_name'] ?? ''} • ${r['employee_number']}'
                        }),
                    EmsField('unit_id', 'Vehicle',
                        required: true,
                        options:
                            options('units_actual', 'unit_id', 'unit_number')),
                    const EmsField('start_datetime', 'Shift start',
                        required: true, time: true),
                    const EmsField('end_datetime', 'Shift end',
                        required: true, time: true)
                  ])),
          button(
              'Add crew member',
              () => form('crew_member', 'Add crew member', fields: [
                    EmsField('crew_id', 'Crew',
                        required: true,
                        options: options('crews', 'crew_id', 'crew_code')),
                    EmsField('member_id', 'Paramedic',
                        required: true,
                        options: {
                          for (final r in rows('ems_members'))
                            r['member_id'].toString():
                                '${r['first_name']} ${r['last_name'] ?? ''}'
                        }),
                    const EmsField('crew_role', 'Crew role',
                        required: true, max: 50)
                  ])),
        ]),
        cards(rows('crews'), (r) {
          final unit = rows('units_actual')
              .where((u) => u['unit_id'] == r['unit_id'])
              .firstOrNull;
          final members = rows('crew_members_actual')
              .where((m) => m['crew_id'] == r['crew_id']);
          return Card(
              child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                            '${r['crew_code']} • ${unit?['unit_number'] ?? 'Vehicle'}',
                            style: Theme.of(context).textTheme.titleMedium),
                        Text(
                            '${r['crew_status']} • ${emsTime(r['start_datetime'])} → ${emsTime(r['end_datetime'])}'),
                        for (final member in members)
                          Builder(builder: (_) {
                            final person = rows('ems_members')
                                .where((p) =>
                                    p['member_id'] == member['member_id'])
                                .firstOrNull;
                            return Text(
                                '${person?['first_name'] ?? ''} ${person?['last_name'] ?? ''} • ${member['crew_role']}');
                          }),
                        if (r['crew_status'] == 'Active')
                          TextButton(
                              onPressed: () => form(
                                      'end_shift', 'End shift', fields: const [
                                    EmsField(
                                        'reason', 'Reason / end-of-shift note',
                                        required: true, max: 1000)
                                  ], extra: {
                                    'shift_id': r['shift_id']
                                  }),
                              child: const Text('End shift')),
                      ])));
        })
      ]);
  Widget _facilities() =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        button('Add receiving facility',
            () => form('facility', 'Receiving facility')),
        cards(
            rows('receiving_facilities'),
            (r) => Card(
                child: ListTile(
                    title: Text('${r['facility_name']}'),
                    subtitle: Text(
                        '${r['address'] ?? ''}\n${r['phone_number'] ?? ''} • ${r['emergency_department'] ?? ''}'),
                    isThreeLine: true,
                    trailing: IconButton(
                        tooltip: 'Edit facility',
                        icon: const Icon(Icons.edit),
                        onPressed: () => form(
                            'facility', 'Edit receiving facility',
                            initial: r, extra: {'id': r['facility_id']})))))
      ]);
  Future<void> unlockOffline() async {
    await showDialog<EmsRow>(
        context: context,
        barrierDismissible: false,
        builder: (_) => EmsFormDialog(
              title: 'Unlock encrypted offline queue',
              fields: const [
                EmsField('passphrase', 'Offline passphrase (12+ characters)',
                    required: true, secret: true, max: 200)
              ],
              save: (p, _) async {
                await service.offline.unlock(
                    '${service.userId}:${service.hospitalId}',
                    p['passphrase'] as String);
                return {};
              },
            ));
    if (mounted) setState(() {});
  }

  Future<void> syncOffline() async {
    setState(() => busy = true);
    try {
      await service.sync();
      await refresh();
    } catch (e) {
      if (mounted) setState(() => error = emsError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget _settings() =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Last server response: ${emsTime(data['server_time'])}'),
        const SizedBox(height: 12),
        button(
            'Notification & navigation preferences',
            () => form('preferences', 'Workspace preferences', initial: {
                  'critical_alerts': true,
                  'navigation_app': 'none',
                  ...Map<String, dynamic>.from(
                      data['preferences'] as Map? ?? {})
                }, fields: [
                  EmsField('critical_alerts', 'Critical alerts in workspace',
                      required: true, options: choices(['true', 'false'])),
                  EmsField('navigation_app', 'Navigation application',
                      required: true,
                      options: {
                        'none': 'None',
                        for (final r in rows('navigation')
                            .where((r) => r['approved'] == true))
                          r['app'].toString(): emsLabel(r['app'].toString())
                      })
                ]),
            Icons.settings),
        const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text(
                'Notification preferences are recorded without patient information. External push notifications require a configured notification service.')),
        if (admin)
          button(
              'Approve navigation application',
              () => form('navigation', 'Hospital navigation approval', fields: [
                    EmsField('app', 'Application',
                        required: true,
                        options: choices(['google_maps', 'waze'])),
                    EmsField('approved', 'Approved by hospital',
                        required: true, options: choices(['true', 'false']))
                  ]),
              Icons.map),
        const SizedBox(height: 16),
        Text('Your device sessions',
            style: Theme.of(context).textTheme.titleLarge),
        cards(
            rows('sessions'),
            (r) => Card(
                child: ListTile(
                    title: Text('${r['device_id']} • ${r['session_status']}'),
                    subtitle: Text(
                        'Last activity ${emsTime(r['last_activity_datetime'])}\nExpires ${emsTime(r['expiry_datetime'])}'),
                    isThreeLine: true,
                    trailing: r['session_status'] == 'Active'
                        ? IconButton(
                            tooltip: 'Revoke this session',
                            icon: const Icon(Icons.lock),
                            onPressed: () => form(
                                'session_revoke', 'Revoke session',
                                fields: const [],
                                extra: {'id': r['session_id']}))
                        : null))),
        const SizedBox(height: 12),
        Text('Offline clinical records',
            style: Theme.of(context).textTheme.titleLarge),
        const Text(
            'Unlock before losing connectivity. Observations, clinical notes and treatments can then be queued for the incident already open on this device. Reopening a locked workspace needs connectivity. Keep the passphrase: it cannot be recovered.'),
        const SizedBox(height: 12),
        if (!service.offline.unlocked)
          button('Unlock offline queue', unlockOffline, Icons.key),
        if (service.offline.unlocked) ...[
          button('Sync ${service.offline.items.length} pending records',
              syncOffline, Icons.sync),
          for (final item in service.offline.items)
            Card(
                child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                              '${emsLabel(item['action'] as String)} • ${item['state']}'),
                          Text(
                              'Recorded ${emsTime((item['payload'] as Map)['recorded_at'])}'),
                          if (item['error'] != null)
                            Text(emsError(item['error'] as String)),
                          const Text(
                              'Failed records stay encrypted here. Resolve the reported assignment or access issue before retrying.'),
                        ]))),
        ],
        const SizedBox(height: 16),
        button('Lock workspace', _lock, Icons.lock_outline),
      ]);
  @override
  Widget build(BuildContext context) {
    final names = admin
        ? [
            'Vehicles',
            'Personnel',
            'Shifts & crews',
            'Incidents',
            'Receiving facilities',
            'Fleet operations',
            'Settings'
          ]
        : dispatch
            ? ['Dispatch incidents', 'Fleet overview', 'Settings']
            : ['My incidents', 'Settings'];
    if (tab >= names.length) tab = 0;
    final pages = admin
        ? [
            _units,
            _staff,
            _shifts,
            _incidents,
            _facilities,
            _operations,
            _settings
          ]
        : dispatch
            ? [_incidents, _operations, _settings]
            : [_incidents, _settings];
    return Listener(
        onPointerDown: (_) => activity = DateTime.now(),
        child: Scaffold(
            appBar:
                widget.showAppBar
                    ? AppBar(title: Text(widget.title), actions: [
                        if (widget.onSignOut != null)
                          IconButton(
                              tooltip: 'Sign out',
                              onPressed: widget.onSignOut,
                              icon: const Icon(Icons.logout_rounded)),
                      ])
                    : null,
            body: locked
                ? Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                    if (error != null) Text(error!),
                    FilledButton.icon(
                        onPressed: busy ? null : _start,
                        icon: const Icon(Icons.lock_open),
                        label: const Text('Reopen workspace'))
                  ]))
                : Column(
                    // Stretch so the scrolling section uses the full width
                    // instead of shrinking to its content and centring.
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                    Padding(
                        padding: const EdgeInsets.all(16),
                        child: Wrap(
                            spacing: 16,
                            runSpacing: 12,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              // The app bar or hospital shell header already
                              // shows the title, so it is not repeated here.
                              if (hospitals.isNotEmpty)
                                SizedBox(
                                    width: 280,
                                    child: DropdownButtonFormField<String>(
                                        key: ValueKey('ems-hospital-$hospital'),
                                        initialValue: hospital,
                                        isExpanded: true,
                                        decoration: const InputDecoration(
                                            labelText: 'Hospital'),
                                        items: hospitals
                                            .map((h) => DropdownMenuItem(
                                                value: h['id'].toString(),
                                                child: Text(
                                                    h['name'].toString(),
                                                    overflow:
                                                        TextOverflow.ellipsis)))
                                            .toList(),
                                        onChanged: busy
                                            ? null
                                            : (v) {
                                                hospital = v;
                                                data = {};
                                                service.lock();
                                                _start();
                                              })),
                              OutlinedButton.icon(
                                  onPressed: busy
                                      ? null
                                      : service.session == null
                                          ? _start
                                          : refresh,
                                  icon: const Icon(Icons.refresh),
                                  label: const Text('Refresh'))
                            ])),
                    if (busy) const LinearProgressIndicator(),
                    if (error != null)
                      Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(error!,
                              style: TextStyle(
                                  color: Theme.of(context).colorScheme.error))),
                    if (data.isNotEmpty) ...[
                      SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 16),
                              child: Wrap(spacing: 8, children: [
                                for (var n = 0; n < names.length; n++)
                                  ChoiceChip(
                                      label: Text(names[n]),
                                      selected: tab == n,
                                      onSelected: (_) =>
                                          setState(() => tab = n))
                              ]))),
                      Expanded(
                          child: SingleChildScrollView(
                              padding: const EdgeInsets.all(16),
                              child: pages[tab]()))
                    ]
                  ])));
  }

  bool _overdue(EmsRow row) {
    final due = DateTime.tryParse('${row['acknowledgement_due_at']}');
    return row['status'] == 'Dispatched' &&
        due != null &&
        due.isBefore(DateTime.now());
  }

  Widget _operations() => ParamedicOperationsPanel(
      data: data,
      admin: admin,
      onForm: (action, title, fields, extra, initial) =>
          form(action, title, fields: fields, extra: extra, initial: initial));
}
