import 'dart:async';

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

import '../../services/blood_bank_service.dart';
import '../../services/blood_bank_label_service.dart';
import '../../theme/app_theme.dart';
import 'blood_bank_picker.dart';
import 'blood_bank_scan_panel.dart';

class BloodBankPage extends StatefulWidget {
  const BloodBankPage({super.key, this.service, this.showAppBar = true});
  final BloodBankService? service;

  /// False inside the hospital admin shell, which already shows the title.
  final bool showAppBar;

  @override
  State<BloodBankPage> createState() => _BloodBankPageState();
}

class _BloodBankPageState extends State<BloodBankPage> {
  late final BloodBankService _service;
  StreamSubscription<dynamic>? _auth;
  Timer? _timer;
  final _search = TextEditingController();
  List<BloodBankRow> _access = [], _requests = [], _events = [];
  BloodBankRow? _board, _selected;
  String? _hospital, _error, _editing;
  String _status = '';
  bool _loading = true, _historyLoading = false;
  int _generation = 0, _offset = 0, _requestOffset = 0, _historyOffset = 0;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? BloodBankService();
    var lastUser = _service.userId;
    _auth = _service.client.auth.onAuthStateChange.listen((_) {
      if (lastUser == _service.userId) return;
      lastUser = _service.userId;
      _generation++;
      setState(() {
        _board = null;
        _access = [];
        _requests = [];
        _events = [];
        _hospital = null;
        _selected = null;
        _editing = null;
        _offset = 0;
        _requestOffset = 0;
        _search.clear();
      });
      _load();
    });
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _checkAccess());
    _load();
  }

  @override
  void dispose() {
    _generation++;
    _timer?.cancel();
    _auth?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _checkAccess() async {
    if (_loading) return;
    final generation = _generation;
    try {
      final access = await _service.access();
      if (!mounted || generation != _generation) return;
      final current = access.where((a) => a['hospital_id'] == _hospital);
      if (current.isEmpty || current.first['role'] != _board?['role']) {
        _deny('Your blood-bank access changed. Refresh to check access.');
      }
    } catch (e) {
      if (mounted && generation == _generation) {
        _deny(BloodBankService.message(e));
      }
    }
  }

  void _deny(String message) {
    _generation++;
    setState(() {
      _error = message;
      _loading = false;
      _board = null;
      _access = [];
      _requests = [];
      _events = [];
      _selected = null;
      _editing = null;
    });
  }

  Future<void> _load() async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
      _board = null;
      _requests = [];
      _events = [];
      _selected = null;
    });
    try {
      if (_service.userId == null) throw StateError('Sign in required');
      final access = await _service.access();
      if (!mounted || generation != _generation) return;
      final hospital = access.any((a) => a['hospital_id'] == _hospital)
          ? _hospital
          : access.firstOrNull?['hospital_id'] as String?;
      if (hospital == null) {
        setState(() {
          _access = [];
          _loading = false;
          _error = 'No blood-bank membership is assigned to your account. '
              'Ask your administrator to grant access for your hospital.';
        });
        return;
      }
      final board = await _service.dashboard(hospital,
          search: _search.text.trim(), status: _status, offset: _offset);
      final requests =
          await _service.requests(hospital, offset: _requestOffset);
      if (!mounted || generation != _generation) return;
      setState(() {
        _access = access;
        _hospital = hospital;
        _board = board;
        _requests = requests;
        _loading = false;
      });
    } catch (e) {
      if (mounted && generation == _generation) {
        _deny(BloodBankService.message(e));
      }
    }
  }

  Future<void> _history(BloodBankRow unit, {int offset = 0}) async {
    final generation = ++_generation;
    setState(() {
      _selected = unit;
      _historyOffset = offset;
      _events = [];
      _historyLoading = true;
    });
    try {
      final events = await _service.history(_hospital!, unit['id'] as String,
          offset: offset);
      if (!mounted || generation != _generation) return;
      setState(() {
        _events = events;
        _historyLoading = false;
      });
    } catch (e) {
      if (mounted && generation == _generation) {
        _deny(BloodBankService.message(e));
      }
    }
  }

  void _edit(String action, [BloodBankRow? record]) => setState(() {
        _selected = record;
        _editing = action;
        _events = [];
      });

  @override
  Widget build(BuildContext context) {
    final board = _board;
    final role = board?['role'];
    final canStock = role == 'manager' || role == 'technician';
    final issueEnabled = board?['settings']['clinical_issue_enabled'] == true;
    return Scaffold(
      appBar: !widget.showAppBar
          ? null
          : AppBar(title: const Text('Blood Bank'), actions: [
              if (_editing == null)
                IconButton(
                    onPressed: _loading ? null : _load,
                    icon: const Icon(Icons.refresh),
                    tooltip: 'Refresh'),
            ]),
      body: Container(
        decoration: BoxDecoration(gradient: context.cBgGradient),
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(
                    child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(_error!),
                            const SizedBox(height: 16),
                            FilledButton(
                                onPressed: _load,
                                child: const Text('Check access again'))
                          ],
                        )))
                : board == null
                    ? const SizedBox.shrink()
                    : _editing == 'scan'
                        ? BloodBankScanPanel(
                            service: _service,
                            hospitalId: _hospital!,
                            onDenied: _deny,
                            onBack: () => setState(() => _editing = null),
                            onFound: (number) {
                              _search.text = number;
                              _status = '';
                              _offset = 0;
                              _editing = null;
                              _load();
                            })
                        : _editing != null
                            ? _BloodBankForm(
                                key: ValueKey(
                                    '$_hospital:$_editing:${_selected?['id']}'),
                                service: _service,
                                hospitalId: _hospital!,
                                action: _editing!,
                                record: _selected,
                                board: board,
                                onDenied: _deny,
                                onDone: () {
                                  setState(() => _editing = null);
                                  _load();
                                },
                                onCancel: () => setState(() {
                                  _editing = null;
                                  _selected = null;
                                }),
                              )
                            : ListView(
                                padding: EdgeInsets.symmetric(
                                  horizontal: _sidePadding(context),
                                  vertical: 16,
                                ),
                                children: [
                                    Row(children: [
                                      Expanded(
                                        child: DropdownButtonFormField<String>(
                                      key: ValueKey(_hospital),
                                      isExpanded: true,
                                      initialValue: _hospital,
                                      decoration: const InputDecoration(
                                          labelText: 'Hospital'),
                                      items: _access
                                          .map((a) => DropdownMenuItem(
                                                value:
                                                    a['hospital_id'] as String,
                                                child: Text(
                                                    '${a['hospital_name']} · ${a['role']}'),
                                              ))
                                          .toList(),
                                      onChanged: (value) {
                                        _hospital = value;
                                        _offset = 0;
                                        _requestOffset = 0;
                                        _load();
                                      },
                                    ),
                                      ),
                                      if (!widget.showAppBar) ...[
                                        const SizedBox(width: 8),
                                        IconButton.outlined(
                                            onPressed: _loading ? null : _load,
                                            icon: const Icon(Icons.refresh),
                                            tooltip: 'Refresh'),
                                      ],
                                    ]),
                                    const SizedBox(height: 12),
                                    Text(
                                        'Inventory and chain of custody. Compatibility and transfusion '
                                        'decisions require approved clinical evidence.',
                                        style: TextStyle(
                                            color: context.cTextSecondary)),
                                    if (!issueEnabled)
                                      Padding(
                                          padding: const EdgeInsets.only(
                                              top: 6),
                                          child: Text(
                                              'Reservation and issue are disabled until hospital clinical authority is configured.',
                                              style: TextStyle(
                                                  color: CorviaColors.warning,
                                                  fontWeight:
                                                      FontWeight.w600))),
                                    const SizedBox(height: 12),
                                    Text(
                                        'Stock checked: ${_time(board['server_time'])}',
                                        style: TextStyle(
                                            color: context.cTextMuted,
                                            fontSize: 12)),
                                    const SizedBox(height: 8),
                                    SingleChildScrollView(
                                      scrollDirection: Axis.horizontal,
                                      child: Row(children: [
                                        for (final e
                                            in (board['counts'] as Map).entries)
                                          Padding(
                                            padding:
                                                const EdgeInsets.only(right: 10),
                                            child: _StockTile(
                                                label: '${e.key}',
                                                value: '${e.value}'),
                                          ),
                                      ]),
                                    ),
                                    const SizedBox(height: 12),
                                    Wrap(spacing: 10, runSpacing: 8, children: [
                                      OutlinedButton.icon(
                                          onPressed: () => _edit('scan'),
                                          icon:
                                              const Icon(Icons.qr_code_scanner),
                                          label:
                                              const Text('Scan / find unit')),
                                      if (canStock)
                                        FilledButton.icon(
                                            onPressed: () => _edit('receive'),
                                            icon: const Icon(Icons.add),
                                            label: const Text('Receive unit')),
                                      if (role == 'manager' ||
                                          role == 'clinician')
                                        OutlinedButton(
                                            onPressed: () => _edit('request'),
                                            child: const Text('New request')),
                                    ]),
                                    const SizedBox(height: 16),
                                    TextField(
                                        controller: _search,
                                        maxLength: 100,
                                        decoration: InputDecoration(
                                            labelText:
                                                'Find unit, lot or donation reference',
                                            suffixIcon: IconButton(
                                                icon: const Icon(Icons.search),
                                                onPressed: () {
                                                  _offset = 0;
                                                  _load();
                                                })),
                                        onSubmitted: (_) {
                                          _offset = 0;
                                          _load();
                                        }),
                                    DropdownButtonFormField<String>(
                                        initialValue: _status,
                                        decoration: const InputDecoration(
                                            labelText: 'Stock status'),
                                        items: [
                                          '',
                                          'available',
                                          'reserved',
                                          'issued',
                                          'quarantined',
                                          'recalled',
                                          'disposed'
                                        ]
                                            .map((s) => DropdownMenuItem(
                                                value: s,
                                                child: Text(s.isEmpty
                                                    ? 'All states'
                                                    : s)))
                                            .toList(),
                                        onChanged: (s) {
                                          _status = s ?? '';
                                          _offset = 0;
                                          _load();
                                        }),
                                    const SizedBox(height: 12),
                                    if (bloodBankRows(board['units']).isEmpty)
                                      const Text('No matching stock.'),
                                    for (final unit
                                        in bloodBankRows(board['units']))
                                      Card(
                                          child: Padding(
                                        padding: const EdgeInsets.all(12),
                                        child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                  '${unit['unit_number']} · ${unit['abo']}${unit['rhd'] == 'positive' ? '+' : '−'}',
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .titleMedium),
                                              Text(
                                                  '${unit['product_name']} · ${unit['status']} · ${unit['location_name']}'),
                                              Text(
                                                  'Expires ${_time(unit['expires_at'])}${unit['expired'] == true ? ' · EXPIRED' : ''}'
                                                  '${unit['expires_within_24h'] == true ? ' · Within 24 hours' : ''}'),
                                              Text(
                                                  'Group source: ${unit['group_source_reference']}'),
                                              Wrap(spacing: 8, children: [
                                                TextButton(
                                                    onPressed: () =>
                                                        _history(unit),
                                                    child:
                                                        const Text('History')),
                                                if (canStock)
                                                  TextButton.icon(
                                                      onPressed: () =>
                                                          _edit('label', unit),
                                                      icon: const Icon(
                                                          Icons.print_outlined),
                                                      label: const Text(
                                                          'Print label')),
                                                if (canStock &&
                                                    unit['status'] !=
                                                        'disposed')
                                                  PopupMenuButton<String>(
                                                      tooltip: 'Stock actions',
                                                      onSelected: (a) =>
                                                          _edit(a, unit),
                                                      itemBuilder: (_) => [
                                                            for (final a in [
                                                              if ([
                                                                'available',
                                                                'reserved'
                                                              ].contains(unit[
                                                                  'status']))
                                                                'transfer',
                                                              if (issueEnabled &&
                                                                  unit['expired'] !=
                                                                      true &&
                                                                  unit['status'] ==
                                                                      'available')
                                                                'reserve',
                                                              if (issueEnabled &&
                                                                  unit['expired'] !=
                                                                      true &&
                                                                  [
                                                                    'available',
                                                                    'reserved'
                                                                  ].contains(unit[
                                                                      'status']))
                                                                'issue',
                                                              if (unit[
                                                                      'status'] ==
                                                                  'reserved')
                                                                'cancel_reservation',
                                                              'quarantine',
                                                              if (role ==
                                                                  'manager') ...[
                                                                'recall',
                                                                'dispose'
                                                              ],
                                                              'return',
                                                            ])
                                                              PopupMenuItem(
                                                                  value: a,
                                                                  child: Text(a
                                                                      .replaceAll(
                                                                          '_',
                                                                          ' '))),
                                                          ],
                                                      child: const Padding(
                                                          padding:
                                                              EdgeInsets.all(
                                                                  12),
                                                          child: Text(
                                                              'Stock actions'))),
                                                if (role == 'ward' &&
                                                    [
                                                      'issued',
                                                      'recalled'
                                                    ].contains(unit['status']))
                                                  TextButton(
                                                      onPressed: () =>
                                                          _edit('return', unit),
                                                      child:
                                                          const Text('Return')),
                                              ]),
                                            ]),
                                      )),
                                    Row(children: [
                                      TextButton(
                                          onPressed: _offset == 0
                                              ? null
                                              : () {
                                                  _offset -= 50;
                                                  _load();
                                                },
                                          child: const Text('Previous')),
                                      Text(
                                          '${board['matching_count']} matching units'),
                                      TextButton(
                                          onPressed: _offset + 50 >=
                                                  (board['matching_count']
                                                      as num)
                                              ? null
                                              : () {
                                                  _offset += 50;
                                                  _load();
                                                },
                                          child: const Text('Next')),
                                    ]),
                                    if (_selected != null) ...[
                                      Text(
                                          'History · ${_selected!['unit_number']}',
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleLarge),
                                      if (_historyLoading)
                                        const LinearProgressIndicator(),
                                      for (final event in _events)
                                        ListTile(
                                            title: Text(
                                                '${event['action']} · ${_time(event['occurred_at'])}'),
                                            subtitle: Text(
                                                '${event['reason']}\nActor: ${event['actor_id']}\n'
                                                'Location: ${event['before_record']?['location_id'] ?? 'Receipt'} → '
                                                '${event['after_record']?['location_id'] ?? '—'}'),
                                            isThreeLine: true),
                                      if (!_historyLoading && _events.isEmpty)
                                        const Text('No events on this page.'),
                                      Row(children: [
                                        TextButton(
                                            onPressed: _historyOffset == 0
                                                ? null
                                                : () => _history(_selected!,
                                                    offset:
                                                        _historyOffset - 50),
                                            child: const Text('Newer events')),
                                        TextButton(
                                            onPressed: _events.length < 50
                                                ? null
                                                : () => _history(_selected!,
                                                    offset:
                                                        _historyOffset + 50),
                                            child: const Text('Older events')),
                                      ]),
                                    ],
                                    const Divider(),
                                    Text('Blood requests',
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleLarge),
                                    if (_requests.isEmpty)
                                      const Text('No requests on this page.'),
                                    for (final request in _requests)
                                      Card(
                                          child: Padding(
                                              padding: const EdgeInsets.all(12),
                                              child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    SelectableText(
                                                        'Request ${request['id']}'),
                                                    Text(
                                                        '${request['product_name']} · ${request['status']} · '
                                                        '${request['issued_count']}/${request['quantity']} issued'),
                                                    Text(
                                                        'Patient reference: ${request['patient_id']}'),
                                                    Text(
                                                        'Required ${_time(request['required_at'])}'),
                                                    if (request[
                                                            'approval_reference'] !=
                                                        null)
                                                      Text(
                                                          'Clinical approval: ${request['approval_reference']}'),
                                                    Wrap(children: [
                                                      if (role == 'manager' &&
                                                          issueEnabled &&
                                                          request['status'] ==
                                                              'pending')
                                                        TextButton(
                                                            onPressed: () => _edit(
                                                                'approve_request',
                                                                request),
                                                            child: const Text(
                                                                'Record clinical approval')),
                                                      if (request['status'] !=
                                                              'cancelled' &&
                                                          (role == 'manager' ||
                                                              (role ==
                                                                      'clinician' &&
                                                                  request['requested_by'] ==
                                                                      _service
                                                                          .userId)))
                                                        TextButton(
                                                            onPressed: () => _edit(
                                                                'cancel_request',
                                                                request),
                                                            child: const Text(
                                                                'Cancel request')),
                                                    ]),
                                                  ]))),
                                    Row(children: [
                                      TextButton(
                                          onPressed: _requestOffset == 0
                                              ? null
                                              : () {
                                                  _requestOffset -= 50;
                                                  _load();
                                                },
                                          child: const Text('Newer requests')),
                                      TextButton(
                                          onPressed: _requests.length < 50
                                              ? null
                                              : () {
                                                  _requestOffset += 50;
                                                  _load();
                                                },
                                          child: const Text('Older requests')),
                                    ]),
                                  ]),
      ),
    );
  }
}

String _time(dynamic value) {
  final date = DateTime.tryParse(value?.toString() ?? '');
  if (date == null) return 'Unknown time';
  return '${date.toUtc().add(const Duration(hours: 2)).toIso8601String().substring(0, 16).replaceAll('T', ' ')} SAST';
}

class _BloodBankForm extends StatefulWidget {
  const _BloodBankForm(
      {super.key,
      required this.service,
      required this.hospitalId,
      required this.action,
      required this.board,
      required this.record,
      required this.onDone,
      required this.onDenied,
      required this.onCancel});
  final BloodBankService service;
  final String hospitalId, action;
  final BloodBankRow board;
  final BloodBankRow? record;
  final VoidCallback onDone, onCancel;
  final ValueChanged<String> onDenied;

  @override
  State<_BloodBankForm> createState() => _BloodBankFormState();
}

class _BloodBankFormState extends State<_BloodBankForm> {
  final _form = GlobalKey<FormState>();
  final Map<String, TextEditingController> _fields = {};
  final Map<String, String> _choices = {};
  BloodBankCommand? _command;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    for (final c in _fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  Widget _field(String key, String label,
      {bool required = true,
      bool timestamp = false,
      bool uuid = false,
      bool integer = false,
      bool idNumber = false,
      String? helperText}) {
    final controller = _fields.putIfAbsent(key, TextEditingController.new);
    return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextFormField(
          controller: controller,
          enabled: !_saving && _command == null,
          maxLength: key == 'reason' ? 1000 : 300,
          decoration: InputDecoration(
              labelText: label,
              helperText: helperText ??
                  (timestamp ? 'SAST date and time: YYYY-MM-DD HH:MM' : null)),
          validator: (v) {
            final value = v?.trim() ?? '';
            if (value.isEmpty) return required ? 'Required' : null;
            if (timestamp && _parseSast(value) == null) {
              return 'Use YYYY-MM-DD HH:MM';
            }
            if (uuid &&
                !RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$')
                    .hasMatch(value)) {
              return 'Enter the full UUID reference';
            }
            if (integer &&
                ((int.tryParse(value) ?? 0) < 1 ||
                    (int.tryParse(value) ?? 0) > 100)) {
              return 'Enter 1 to 100';
            }
            if (idNumber &&
                !RegExp(r'^[A-Za-z0-9][A-Za-z0-9 -]{5,39}$').hasMatch(value)) {
              return 'Enter the donor ID number (6 to 40 characters)';
            }
            return null;
          },
        ));
  }

  DateTime? _parseSast(String input) {
    if (!RegExp(r'^\d{4}-\d{2}-\d{2} \d{2}:\d{2}$').hasMatch(input)) {
      return null;
    }
    final date = DateTime.tryParse('${input.replaceAll(' ', 'T')}:00+02:00');
    if (date == null || _time(date.toIso8601String()) != '$input SAST') {
      return null;
    }
    return date.toUtc();
  }

  Widget _choice(String key, String label, List<BloodBankRow> choices) =>
      Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: DropdownButtonFormField<String>(
            decoration: InputDecoration(labelText: label),
            initialValue: _choices[key],
            isExpanded: true,
            items: choices
                .map((r) => DropdownMenuItem(
                    value: r['id'] as String, child: Text(r['name'] as String)))
                .toList(),
            validator: (v) => v == null ? 'Select an option' : null,
            onChanged: _saving || _command != null
                ? null
                : (v) => setState(() {
                      if (v != null) _choices[key] = v;
                    }),
          ));

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    if (_command == null) {
      final payload = <String, dynamic>{..._choices};
      for (final e in _fields.entries) {
        final value = e.value.text.trim();
        if (value.isEmpty) continue;
        payload[e.key] =
            ['expires_at', 'collected_at', 'required_at'].contains(e.key)
                ? _parseSast(value)!.toIso8601String()
                : e.key == 'quantity'
                    ? int.parse(value)
                    : value;
      }
      if (_choices['source'] != 'internal') {
        payload.remove('donor_id_number');
      }
      if (widget.record != null) {
        if (widget.action.endsWith('_request')) {
          payload['request_id'] = widget.record!['id'];
        } else {
          payload['unit_id'] = widget.record!['id'];
          payload['version'] = widget.record!['version'];
        }
      }
      _command = BloodBankCommand(widget.hospitalId, widget.action, payload);
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      if (widget.action == 'label') {
        final snapshot = await widget.service.prepareLabel(_command!);
        if (!mounted) return;
        final bytes = await BloodBankLabelService.build(snapshot);
        if (!mounted) return;
        await Printing.layoutPdf(
          name: 'corvia-blood-unit-${snapshot['id']}.pdf',
          format: PdfPageFormat.a5,
          dynamicLayout: false,
          onLayout: (_) async => bytes,
        );
      } else if (widget.action == 'receive' &&
          _command!.payload['source'] == 'internal') {
        await widget.service.receiveDonor(_command!);
      } else {
        await widget.service.execute(_command!);
      }
      if (mounted) widget.onDone();
    } catch (e) {
      if (!mounted) return;
      if (BloodBankService.accessDenied(e)) {
        widget.onDenied(BloodBankService.message(e));
        return;
      }
      setState(() {
        _saving = false;
        _error = e is FormatException ? e.message : BloodBankService.message(e);
        if (BloodBankService.definitelyRejected(e)) _command = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final action = widget.action;
    final locations = bloodBankRows(widget.board['locations']).where((l) {
      if (['return', 'quarantine'].contains(action)) {
        return l['location_type'] == 'quarantine';
      }
      if (action == 'dispose') return l['location_type'] == 'disposal';
      return !['quarantine', 'disposal', 'transit']
          .contains(l['location_type']);
    }).toList();
    return Form(
        key: _form,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          Text(action.replaceAll('_', ' ').toUpperCase(),
              style: Theme.of(context).textTheme.titleLarge),
          if (widget.record != null)
            Text('${widget.record!['unit_number'] ?? widget.record!['id']}'),
          const SizedBox(height: 16),
          if (action == 'receive') ...[
            _field('unit_number', 'Unit number'),
            _choice('product_id', 'Product',
                bloodBankRows(widget.board['products'])),
            _choice('source', 'Origin', [
              if (widget.board['settings']['operating_mode'] != 'collector')
                {'id': 'external', 'name': 'External supplier'},
              if (widget.board['settings']['operating_mode'] != 'receiver')
                {'id': 'internal', 'name': 'Internal collection'},
            ]),
            _field('supplier', 'Supplier',
                required: _choices['source'] != 'internal'),
            _field('lot_number', 'Supplier lot',
                required: _choices['source'] != 'internal'),
            _field('donation_reference', 'Donation reference',
                required: _choices['source'] == 'internal'),
            if (_choices['source'] == 'internal')
              _field('donor_id_number', 'Donor ID number (private)',
                  idNumber: true,
                  helperText:
                      'The donor provides this after donating. It is stored privately and is not shown on stock labels.'),
            _field('collected_at', 'Collection time',
                timestamp: true, required: _choices['source'] == 'internal'),
            _choice('abo', 'ABO from unit evidence', [
              for (final s in ['A', 'B', 'AB', 'O']) {'id': s, 'name': s}
            ]),
            _choice('rhd', 'RhD from unit evidence', [
              {'id': 'positive', 'name': 'Positive'},
              {'id': 'negative', 'name': 'Negative'}
            ]),
            _field('group_source_reference',
                'Unit label / laboratory evidence reference'),
            _field('expires_at', 'Expiry from approved source',
                timestamp: true),
          ],
          if (['receive', 'transfer', 'return', 'quarantine', 'dispose']
              .contains(action))
            _choice('location_id', 'Destination location', locations),
          if (action == 'request') ...[
            BloodBankPicker(
              label: 'Patient',
              hintText: 'Name, patient number or full ID number',
              helperText:
                  'Search this hospital and select the correct patient. '
                  'Use the full ID number as recorded; confirm the patient number before saving.',
              enabled: !_saving && _command == null,
              load: (query) =>
                  widget.service.patientOptions(widget.hospitalId, query),
              describe: (row) =>
                  '${row['patient_name']} · ${row['patient_number'] ?? 'No patient number'}',
              onSelected: (row) {
                if (row == null) {
                  _choices.remove('patient_id');
                } else {
                  _choices['patient_id'] = row['id'] as String;
                }
              },
              onDenied: widget.onDenied,
            ),
            _choice('product_id', 'Product',
                bloodBankRows(widget.board['products'])),
            _field('quantity', 'Number of units', integer: true),
            _field('required_at', 'Required time', timestamp: true),
          ],
          if (['reserve', 'issue'].contains(action))
            BloodBankPicker(
              label: 'Approved request',
              minimumSearch: 0,
              enabled: !_saving && _command == null,
              load: (query) => widget.service.requestOptions(
                  widget.hospitalId, widget.record!['id'] as String, query),
              describe: (row) =>
                  '${row['patient_name']} · ${row['patient_number'] ?? row['patient_id']} · '
                  '${row['remaining']} remaining · ${_time(row['required_at'])} · ${row['id']}',
              onSelected: (row) {
                if (row == null) {
                  _choices.remove('request_id');
                } else {
                  _choices['request_id'] = row['id'] as String;
                }
              },
              onDenied: widget.onDenied,
            ),
          if (action == 'label')
            const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: Text(
                    'Prepare a supplemental inventory QR label. Keep the original supplier label. '
                    'Preparation and reprints are recorded; cancelling the print dialog does not undo that record.')),
          if (action == 'approve_request')
            _field(
                'approval_reference', 'External clinical approval reference'),
          if (action == 'issue') ...[
            _field('compatibility_reference',
                'External compatibility approval for this patient and unit'),
            _field('recipient', 'Receiving person / clinical area'),
          ],
          if (action == 'return') ...[
            const Text(
                'Returned units remain held in quarantine for clinical review.'),
            _field('condition', 'Condition on return'),
          ],
          if (['return', 'quarantine', 'recall', 'dispose'].contains(action))
            _choice('cold_chain_broken', 'Known cold-chain break', [
              {'id': 'false', 'name': 'No known break recorded'},
              {'id': 'true', 'name': 'Yes - hold unit'},
            ]),
          _field('reason', 'Reason / source document'),
          if (_error != null) ...[
            Text(_error!),
            if (_command != null)
              const Text(
                  'Retry resends the same operation. If the outcome is uncertain, '
                  'retry before leaving. This draft is kept only while this form stays open.'),
            if (_command != null)
              SelectableText('Operation: ${_command?.operationId}'),
          ],
          const SizedBox(height: 12),
          Wrap(spacing: 12, children: [
            FilledButton(
                onPressed: _saving ? null : _save,
                child: Text(_saving
                    ? 'Saving…'
                    : _command == null
                        ? action == 'label'
                            ? 'Prepare / print label'
                            : 'Save'
                        : 'Retry same operation')),
            TextButton(
                onPressed: _saving ? null : widget.onCancel,
                child: const Text('Back to stock')),
          ]),
        ]));
  }
}

/// Keeps the inventory at a readable width on wide screens.
double _sidePadding(BuildContext context) {
  final width = MediaQuery.sizeOf(context).width;
  return width > 1080 ? (width - 1000) / 2 : 16;
}

class _StockTile extends StatelessWidget {
  const _StockTile({required this.label, required this.value});
  final String label;
  final String value;

  Color get _color => switch (label) {
        'available' => CorviaColors.success,
        'held' || 'reserved' => CorviaColors.warning,
        'expired' => CorviaColors.danger,
        _ => CorviaColors.accent,
      };

  IconData get _icon => switch (label) {
        'available' => Icons.check_circle_outline,
        'held' || 'reserved' => Icons.pause_circle_outline,
        'expired' => Icons.event_busy_outlined,
        _ => Icons.bloodtype_outlined,
      };

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: context.cBgSecondary,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: context.cDivider),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_icon, color: _color, size: 22),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(value,
                    style: TextStyle(
                        color: context.cTextPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.bold)),
                Text(
                  label.isEmpty
                      ? ''
                      : label[0].toUpperCase() + label.substring(1),
                  style:
                      TextStyle(color: context.cTextSecondary, fontSize: 11),
                ),
              ],
            ),
          ],
        ),
      );
}
