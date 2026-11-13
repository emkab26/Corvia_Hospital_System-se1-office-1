import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../services/paramedic_workspace_service.dart';
import '../../widgets/corvia_scanner.dart';
import 'paramedic_forms.dart';
import '../dispatch/team_operations_page.dart';

class ParamedicIncidentPage extends StatefulWidget {
  const ParamedicIncidentPage(
      {super.key,
      required this.service,
      required this.incidentId,
      required this.catalog,
      required this.onActivity});
  final ParamedicWorkspaceService service;
  final int incidentId;
  final EmsRow catalog;
  final VoidCallback onActivity;
  @override
  State<ParamedicIncidentPage> createState() => _ParamedicIncidentPageState();
}

class _ParamedicIncidentPageState extends State<ParamedicIncidentPage> {
  EmsRow data = {};
  String? error;
  int? patient;
  int tab = 0;
  bool busy = true;
  int _readGeneration = 0;
  EmsRow get incident =>
      Map<String, dynamic>.from(data['incident'] as Map? ?? {});
  bool get closed => incident['status'] == 'Closed';
  bool get dispatch => data['can_dispatch'] == true || data['is_admin'] == true;
  bool get clinicalAccess =>
      !['dispatcher', 'supervisor'].contains(data['operations_role']);
  List<EmsRow> rows(String key) => emsRows(data[key]);
  List<EmsRow> get patients => rows('patients_actual');
  @override
  void initState() {
    super.initState();
    refresh();
  }

  Future<void> refresh() async {
    final generation = ++_readGeneration;
    if (mounted) setState(() => busy = true);
    try {
      final next = await widget.service.load(widget.incidentId);
      if (mounted && generation == _readGeneration) {
        setState(() {
          data = next;
          error = null;
          patient ??= patients.firstOrNull?['patient_id'] as int?;
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

  @override
  void dispose() {
    _readGeneration++;
    super.dispose();
  }

  Future<EmsRow?> form(String action, String title,
      {List<EmsField>? fields,
      EmsRow initial = const {},
      EmsRow extra = const {},
      bool forPatient = false}) async {
    if (forPatient && patient == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Capture or select a patient first.')));
      return null;
    }
    final snapshot = {
      'incident_id': widget.incidentId,
      'revision': incident['revision'],
      if (['observation', 'note', 'treatment'].contains(action))
        'assignment_id': rows('incident_assignments_actual')
            .where((a) => a['is_active'] == true)
            .firstOrNull?['assignment_id'],
      if (forPatient) 'patient_id': patient,
      ...extra
    };
    final result = await showDialog<EmsRow>(
        context: context,
        barrierDismissible: false,
        builder: (_) => EmsFormDialog(
            title: title,
            fields: fields ?? emsFields(action),
            initial: initial,
            save: (p, op) => widget.service
                .command(action, {...snapshot, ...p}, operationId: op)));
    if (result != null && mounted) {
      if (result['declined'] == true ||
          result['status'] == 'Closed' ||
          result['exception'] == 'cancelled') {
        Navigator.pop(context);
        return result;
      }
      if (result['queued'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'Encrypted on this device. Not sent yet — sync from Workspace Settings when connected.')));
      } else {
        await refresh();
      }
    }
    return result;
  }

  Future<void> editPatient(EmsRow currentPatient) async {
    final patientId = currentPatient['patient_id'] as int?;
    if (patientId == null) return;

    final result = await showDialog<EmsRow>(
      context: context,
      barrierDismissible: false,
      builder: (_) => EmsFormDialog(
        title: 'Update patient identification',
        fields: emsFields('patient'),
        initial: currentPatient,
        save: (data, _) => widget.service.updatePatient(
          incidentId: widget.incidentId,
          patientId: patientId,
          data: data,
        ),
      ),
    );

    if (result != null && mounted) await refresh();
  }

  Widget button(String text, VoidCallback fn, [IconData icon = Icons.add]) =>
      FilledButton.tonalIcon(
          onPressed: busy || closed || error != null || data.isEmpty ? null : fn,
          icon: Icon(icon),
          label: Text(text));
  Widget records(String title, String table, List<String> keys,
      {bool patientOnly = false}) {
    final entries = rows(table)
        .where((r) => !patientOnly || r['patient_id'] == patient)
        .toList()
        .reversed;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
          padding: const EdgeInsets.only(top: 20, bottom: 8),
          child: Text(title, style: Theme.of(context).textTheme.titleLarge)),
      if (entries.isEmpty) const Text('No records yet.'),
      for (final r in entries)
        Card(
            child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final k in keys)
                        if (r[k] != null)
                          Text(
                              '${emsLabel(k)}: ${k.endsWith('_at') || k.endsWith('_datetime') ? emsTime(r[k]) : r[k]}')
                    ])))
    ]);
  }

  Future<void> confirmQr([String? code]) async {
    final result = await form('qr', 'Confirm assigned patient',
        fields: const [
          EmsField('code', 'QR content or patient number',
              required: true, max: 300)
        ],
        initial: code == null ? {} : {'code': code},
        forPatient: true);
    if (result != null && result['match'] == false && mounted) {
      await form(
          'qr_acknowledge', 'Patient mismatch — stop and verify identity',
          fields: const [
            EmsField('reason', 'How will you verify this patient?',
                required: true, multiline: true, max: 500)
          ],
          extra: {'id': result['id']},
          forPatient: true);
    }
  }

  Future<void> scan() async {
    if (patient == null) return;
    final code = await Navigator.push<String>(context,
        MaterialPageRoute(builder: (_) => const _PatientScannerPage()));
    if (code != null && mounted) await confirmQr(code);
  }

  Future<void> navigate() async {
    final latest = await widget.service.load();
    if (!mounted) return;
    final prefs = latest['preferences'] as Map? ?? {};
    final app = prefs['navigation_app'];
    if (app == null ||
        app == 'none' ||
        !emsRows(latest['navigation'])
            .any((r) => r['app'] == app && r['approved'] == true)) {
      throw StateError(
          'Choose a hospital-approved navigation app in Settings.');
    }
    final lat = incident['latitude'], lng = incident['longitude'];
    if (lat == null || lng == null) {
      throw StateError('Scene coordinates have not been recorded.');
    }
    final uri = app == 'waze'
        ? Uri.https(
            'www.waze.com', '/ul', {'ll': '$lat,$lng', 'navigate': 'yes'})
        : Uri.https('www.google.com', '/maps/dir/',
            {'api': '1', 'destination': '$lat,$lng', 'travelmode': 'driving'});
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      throw StateError('Navigation could not be opened.');
    }
  }

  Future<void> safe(Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(emsError(e))));
      }
    }
  }

  Future<void> location() async {
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      throw StateError(
          'Location permission is unavailable. Enter coordinates manually.');
    }
    final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 20)));
    if (mounted) {
      await form('location', 'Record current location', initial: {
        'latitude': pos.latitude,
        'longitude': pos.longitude,
        'location_type': 'Crew'
      }, extra: {
        'accuracy_meters': pos.accuracy
      });
    }
  }

  Widget overview() {
    const transitions = {
      'Dispatched': 'Accepted',
      'Accepted': 'En Route',
      'En Route': 'On Scene',
      'On Scene': 'Transporting',
      'Transporting': 'At Hospital',
      'At Hospital': 'Handed Over',
      'Handed Over': 'Closed'
    };
    final next = transitions[incident['status']];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('${incident['incident_type']} • ${incident['priority']}',
          style: Theme.of(context).textTheme.titleLarge),
      Text('${incident['scene_address'] ?? 'No scene address'}'),
      Text('${incident['dispatch_notes'] ?? ''}'),
      if (data['ws4_linked'] == true && widget.service.hospitalId != null)
        OutlinedButton.icon(
          onPressed: busy || error != null ? null : () =>
            Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => Ws4TeamOperationsPage(
                hospitalId: widget.service.hospitalId,
                emsIncidentId: widget.incidentId.toString()))),
          icon: const Icon(Icons.fact_check_outlined),
          label: const Text('Linked WS4 operations and destination')),
      if (data.containsKey('operations_role')) ...[
        Text(
            'Dispatch: ${incident['dispatch_state']} • Required capability: ${incident['required_capability']}'),
        Text(incident['claimed_by'] == null
            ? 'Unclaimed'
            : incident['claimed_by'] == widget.service.userId
                ? 'Claimed by you'
                : 'Claimed by another dispatcher'),
        if (incident['acknowledgement_due_at'] != null &&
            incident['status'] == 'Dispatched')
          Text(
              'Crew acknowledgement due ${emsTime(incident['acknowledgement_due_at'])}${DateTime.tryParse('${incident['acknowledgement_due_at']}')?.isBefore(DateTime.now()) == true ? ' • OVERDUE — contact crew or escalate' : ''}')
      ],
      const SizedBox(height: 16),
      Wrap(spacing: 8, runSpacing: 8, children: [
        if (dispatch && data.containsKey('operations_role'))
          button(
              'Claim / take over',
              () => form('claim', 'Claim incident', fields: const [
                    EmsField('reason',
                        'Supervisor takeover reason (if owned by someone else)',
                        max: 1000)
                  ]),
              Icons.person_pin),
        if (dispatch)
          button(
              'Assign / reassign crew',
              () => form('assign', 'Dispatch crew', fields: [
                    EmsField('crew_id', 'Crew', required: true, options: {
                      for (final c in emsRows(widget.catalog['crews']))
                        c['crew_id'].toString():
                            '${c['crew_code']} • ${c['crew_status']}'
                    }),
                    const EmsField(
                        'reason', 'Reassignment reason (if already assigned)',
                        max: 1000)
                  ]),
              Icons.local_shipping),
        if (next != null && clinicalAccess)
          button(
              'Mark $next',
              () => form('status', 'Confirm: $next',
                  fields: const [], extra: {'status': next}),
              Icons.check_circle),
        if (incident['status'] == 'Dispatched' &&
            rows('incident_assignments_actual')
                .any((r) => r['is_active'] == true))
          button(
              'Decline assignment',
              () => form('decline', 'Decline assignment', fields: const [
                    EmsField('reason', 'Reason for declining',
                        required: true, max: 1000)
                  ]),
              Icons.cancel_outlined),
        OutlinedButton.icon(
            onPressed: () => safe(navigate),
            icon: const Icon(Icons.navigation),
            label: const Text('Navigate to scene')),
        button('Current location', () => safe(location), Icons.my_location),
        button(
            'Manual location',
            () => form('location', 'Location',
                initial: const {'location_type': 'Scene'}),
            Icons.location_on),
        button('Record hazard', () => form('hazard', 'Scene hazard'),
            Icons.warning_amber),
        if (data.containsKey('operations_role'))
          button(
              'Escalate / exception',
              () => form('exception', 'Record incident exception', fields: [
                    EmsField('kind', 'Exception', required: true, options: {
                      'no_patient': 'No patient found',
                      'unsafe_scene': 'Unsafe scene',
                      'refusal': 'Patient refusal',
                      'unit_failure': 'Unit failure',
                      'backup_required': 'Request backup',
                      if (['admin', 'supervisor']
                          .contains(data['operations_role']))
                        'cancelled': 'Cancel (no linked patients)'
                    }),
                    const EmsField('reason', 'Reason and action required',
                        required: true, multiline: true, max: 1000)
                  ]),
              Icons.report_problem_outlined)
      ]),
      records('Scene hazards', 'incident_hazards',
          ['hazard_type', 'severity', 'description', 'identified_at']),
      records('Location history', 'incident_locations',
          ['location_type', 'address', 'latitude', 'longitude', 'recorded_at']),
      records('Assignment history', 'incident_assignments_actual',
          ['assignment_status', 'assigned_datetime', 'accepted_datetime'])
    ]);
  }

  Widget patientPage() {
    final p = patients.where((r) => r['patient_id'] == patient).firstOrNull;
    final link = rows('incident_patients')
        .where((r) => r['patient_id'] == patient)
        .firstOrNull;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Wrap(spacing: 8, runSpacing: 8, children: [
        button('Capture patient', () => form('patient', 'Patient details')),
        button(
            'Link existing patient',
            () => form('patient_link', 'Find patient by ID / number'),
            Icons.search)
      ]),
      if (p != null) ...[
        const SizedBox(height: 20),
        Text('${p['first_name']} ${p['last_name'] ?? ''}',
            style: Theme.of(context).textTheme.titleLarge),
        Text('Patient number: ${p['patient_number']}'),
        Text('ID / passport: ${p['identity_number'] ?? 'Not recorded'}'),
        Text(
            'Birth date: ${p['date_of_birth'] ?? 'Unknown'} • Sex: ${p['sex'] ?? 'Unknown'}'),
        Text(
            'Patient-reported blood type: ${p['patient_recorded_blood_type'] ?? 'Unknown'} (unverified)'),
        Text(
            'Identity confirmation: ${link?['confirmation_status'] ?? 'Unconfirmed'}',
            style: TextStyle(
                color: link?['confirmation_status'] == 'Mismatch'
                    ? Theme.of(context).colorScheme.error
                    : null)),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          button(
              'Edit patient details', () => editPatient(p), Icons.edit_rounded),
          button('Scan patient QR', scan, Icons.qr_code_scanner),
          button('Enter patient code', confirmQr, Icons.keyboard),
          OutlinedButton.icon(
              onPressed: () => showDialog<void>(
                  context: context,
                  builder: (dialogContext) => AlertDialog(
                          title: Text(
                              '${p['first_name']} • ${p['patient_number']}'),
                          content: SizedBox(
                              width: 240,
                              height: 240,
                              child: ColoredBox(
                                  color: Colors.white,
                                  child: QrImageView(
                                      data:
                                          'CORVIA_EMS_PATIENT|v=1|patient_number=${p['patient_number']}'))),
                          actions: [
                            TextButton(
                                onPressed: () =>
                                    Navigator.of(dialogContext).pop(),
                                child: const Text('Close'))
                          ])),
              icon: const Icon(Icons.qr_code),
              label: const Text('Patient QR'))
        ]),
        const SizedBox(height: 16),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final action in [
            'allergy',
            'medication',
            'condition',
            'contact',
            'risk'
          ])
            button('Add ${emsLabel(action).toLowerCase()}',
                () => form(action, emsLabel(action), forPatient: true))
        ]),
        records('Allergies', 'patient_allergies',
            ['allergen', 'reaction', 'severity'],
            patientOnly: true),
        records('Current medications', 'patient_medications',
            ['medication_name', 'dosage', 'frequency', 'notes'],
            patientOnly: true),
        records('Medical conditions', 'patient_conditions',
            ['condition_name', 'severity', 'notes'],
            patientOnly: true),
        records('Special risks', 'patient_special_risks',
            ['risk_type', 'description', 'severity'],
            patientOnly: true),
        records('Emergency contacts', 'emergency_contacts',
            ['name', 'relationship', 'phone_number'],
            patientOnly: true),
        records('QR confirmations', 'patient_qr_confirmations',
            ['match_status', 'scanned_at', 'acknowledged'])
      ]
    ]);
  }

  Widget clinical() =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text(
            'Record observed findings and care performed. Corrections are appended to preserve the clinical history.'),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final action in ['observation', 'note', 'treatment'])
            button(
                'Add ${emsLabel(action).toLowerCase()}',
                () => form(action, emsLabel(action), forPatient: true, fields: [
                      ...emsFields(action),
                      const EmsField('recorded_at', 'Recorded time',
                          required: true, time: true)
                    ], initial: {
                      'recorded_at': DateTime.now().toUtc().toIso8601String()
                    }))
        ]),
        records(
            'Observations',
            'observations',
            [
              'recorded_at',
              'heart_rate',
              'respiratory_rate',
              'systolic_bp',
              'diastolic_bp',
              'spo2',
              'temperature',
              'gcs',
              'notes'
            ],
            patientOnly: true),
        records(
            'Clinical notes', 'clinical_notes', ['recorded_at', 'note_text'],
            patientOnly: true),
        records('Treatments', 'treatments',
            ['performed_at', 'treatment_type', 'description', 'outcome'],
            patientOnly: true)
      ]);
  Widget handover() =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text(
            'At hospital: record the receiving clinician and summary, then record their acknowledgement.'),
        const SizedBox(height: 12),
        button(
            'Record handover',
            () => form('handover', 'Clinical handover',
                    forPatient: true,
                    fields: [
                      EmsField('facility_id', 'Receiving facility',
                          required: true,
                          options: {
                            for (final f in emsRows(
                                widget.catalog['receiving_facilities']))
                              f['facility_id'].toString():
                                  f['facility_name'].toString()
                          }),
                      ...emsFields('handover')
                    ])),
        for (final r
            in rows('handovers').where((r) => r['patient_id'] == patient))
          Card(
              child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                            '${r['receiver_name']} • ${r['receiver_role'] ?? ''}',
                            style: Theme.of(context).textTheme.titleMedium),
                        Text('${r['handover_summary']}'),
                        Text(emsTime(r['handover_datetime'])),
                        Text(r['acknowledged'] == true
                            ? 'Acknowledged ${emsTime(r['acknowledged_datetime'])}'
                            : 'Awaiting receiver acknowledgement'),
                        if (r['acknowledged'] != true &&
                            data['ws4_linked'] == true)
                          const Text(
                              'Awaiting confirmation from the receiving user in Corvia.'),
                        if (r['acknowledged'] != true &&
                            data['ws4_linked'] != true)
                          TextButton(
                              onPressed: closed
                                  ? null
                                  : () => form('handover_acknowledge',
                                          'Record receiver acknowledgement',
                                          forPatient: true,
                                          extra: {
                                            'id': r['handover_id']
                                          },
                                          fields: const [
                                            EmsField('reason',
                                                'How the receiver acknowledged receipt',
                                                required: true,
                                                multiline: true,
                                                max: 1000)
                                          ]),
                              child: const Text('Record acknowledgement'))
                      ])))
      ]);
  Widget history() =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        records('Status timeline', 'incident_status_history',
            ['status', 'status_datetime', 'sync_status']),
        records('Treatment timeline', 'treatment_timeline',
            ['event_type', 'event_description', 'event_datetime'],
            patientOnly: true),
        records('Audit trail', 'audit_logs',
            ['action_type', 'action_datetime', 'reason'])
      ]);
  Widget messages() =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text(
            'Messages are saved to this incident. Saved does not mean the other person has read it; they must refresh and acknowledge. Use your operational call channel for an urgent response.'),
        button(
            'Send message',
            () => form('message', 'Incident message', fields: const [
                  EmsField('message', 'Message',
                      required: true, multiline: true, max: 2000)
                ]),
            Icons.send),
        for (final r in rows('messages'))
          Card(
              child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${r['message']}'),
                        Text(
                            '${r['sender'] == widget.service.userId ? 'You' : 'Team member'} • Saved ${emsTime(r['received_at'])}'),
                        Text(r['acknowledged'] == true
                            ? 'Acknowledged by another team member'
                            : 'Awaiting acknowledgement'),
                        if (r['sender'] != widget.service.userId &&
                            r['acknowledged'] != true)
                          button(
                              'Acknowledge',
                              () => form('message_read', 'Acknowledge message',
                                  fields: const [],
                                  extra: {'message_id': r['message_id']}),
                              Icons.done_all)
                      ])))
      ]);
  @override
  Widget build(BuildContext context) {
    final pages = [
      overview,
      if (clinicalAccess) ...[patientPage, clinical, handover],
      if (data.containsKey('operations_role')) messages,
      history
    ];
    final labels = [
      'Overview',
      if (clinicalAccess) ...['Patient', 'Clinical record', 'Handover'],
      if (data.containsKey('operations_role')) 'Messages',
      'Timeline & audit'
    ];
    if (tab >= pages.length) tab = 0;
    return Listener(
        onPointerDown: (_) => widget.onActivity(),
        child: Scaffold(
            appBar: AppBar(
                title: Text(
                    '${incident['incident_number'] ?? 'Incident'} • ${incident['status'] ?? ''}'),
                actions: [
                  IconButton(
                      tooltip: 'Refresh',
                      onPressed: busy ? null : refresh,
                      icon: const Icon(Icons.refresh))
                ]),
            body: Column(children: [
              if (busy) const LinearProgressIndicator(),
              if (error != null)
                Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(error!,
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error))),
              if (patients.isNotEmpty && clinicalAccess)
                Padding(
                    padding: const EdgeInsets.all(16),
                    child: DropdownButtonFormField<int>(
                        key: ValueKey(patient),
                        initialValue: patient,
                        isExpanded: true,
                        decoration:
                            const InputDecoration(labelText: 'Current patient'),
                        items: patients
                            .map((p) => DropdownMenuItem(
                                value: p['patient_id'] as int,
                                child: Text(
                                    '${p['first_name']} ${p['last_name'] ?? ''} • ${p['patient_number']}',
                                    overflow: TextOverflow.ellipsis)))
                            .toList(),
                        onChanged: (v) => setState(() => patient = v))),
              SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Wrap(spacing: 8, children: [
                    for (final (n, label) in labels.indexed)
                      ChoiceChip(
                          label: Text(label),
                          selected: tab == n,
                          onSelected: (_) => setState(() => tab = n))
                  ])),
              if (data.isNotEmpty)
                Expanded(
                    child: SingleChildScrollView(
                        padding: const EdgeInsets.all(16), child: pages[tab]()))
            ])));
  }
}

class _PatientScannerPage extends StatefulWidget {
  const _PatientScannerPage();
  @override
  State<_PatientScannerPage> createState() => _PatientScannerPageState();
}

class _PatientScannerPageState extends State<_PatientScannerPage> {
  final controller = CorviaScannerController();
  bool returned = false;
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('Scan patient QR')),
      body: CorviaScanner(
          controller: controller,
          onDetect: (capture) {
            final code = capture.barcodes.firstOrNull?.rawValue;
            if (!returned && code != null) {
              returned = true;
              Navigator.pop(context, code);
            }
          }));
}
