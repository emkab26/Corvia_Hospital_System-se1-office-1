import 'dart:async';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../controllers/patient_emergency_intake_controller.dart'
    show createEmergencyOperationId;
import '../services/incident_workspace_service.dart';
import '../config/env.dart';
import 'emergency_phone_card.dart';
import '../pages/dispatch/response_workspace_page.dart';

/// Persisted Corvia operations and messages. Provider demo is server-enabled only.
class IncidentWorkspacePanel extends StatefulWidget {
  const IncidentWorkspacePanel(
      {super.key,
      required this.incidentId,
      this.gateway,
      this.enabled = true,
      this.onChanged});
  final String incidentId;
  final IncidentWorkspaceGateway? gateway;
  final bool enabled;
  final VoidCallback? onChanged;
  @override
  State<IncidentWorkspacePanel> createState() => _IncidentWorkspacePanelState();
}

class _IncidentWorkspacePanelState extends State<IncidentWorkspacePanel> {
  late final IncidentWorkspaceGateway _gateway;
  late final String? _actor;
  StreamSubscription<String?>? _subscription;
  Timer? _timer;
  final _text = TextEditingController();
  IncidentWorkspace? _data;
  IncidentMessagePage? _messages;
  String? _error, _notice;
  String? _callbackOutcome;
  void _recordCallback() {
    if (_callbackOutcome == null || _text.text.trim().length < 5) {
      setState(() => _error = 'Describe the observed callback outcome.');
      return;
    }
    unawaited(_action('callback_outcome', {
      'outcome': _callbackOutcome,
      'text': '${_callbackOutcome!}: ${_text.text.trim()}'
    }));
  }
  Future<void> _callPatient(String number) async {
    if (_denied || _busy || !widget.enabled || _gateway.userId != _actor) {
      return;
    }
    var opened = false;
    try {
      opened = await launchUrl(Uri(scheme: 'tel', path: number),
          mode: LaunchMode.externalApplication);
    } catch (_) {}
    if (mounted && !_denied && _gateway.userId == _actor && !opened) {
      setState(() => _notice =
          'The phone app could not open. Dial the displayed callback number manually.');
    }
  }

  bool _busy = false, _denied = false;
  int _generation = 0;
  // Retain exact identity/payload after a timeout; refreshing never resends it.
  ({
    String id,
    String version,
    String action,
    Map<String, dynamic> payload
  })? _pending;
  @override
  void initState() {
    super.initState();
    try {
      _gateway = widget.gateway ?? IncidentWorkspaceService();
      _actor = _gateway.userId;
      _subscription = _gateway.users.listen((id) {
        if (id != _actor) _invalidate();
      }, onError: (Object _) => _invalidate());
      unawaited(_refresh());
      _timer = Timer.periodic(const Duration(seconds: 15), (_) {
        if (!_busy && !_denied && _pending == null && widget.enabled) {
          unawaited(_refresh());
        }
      });
    } catch (_) {
      _denied = true;
      _error = const WorkspaceFailure('unavailable').message;
    }
  }

  bool _owns(int generation) {
    if (!mounted || generation != _generation || _denied) return false;
    if (_gateway.userId != _actor) {
      _invalidate();
      return false;
    }
    return true;
  }

  void _invalidate() {
    if (!mounted) return;
    _generation++;
    _timer?.cancel();
    _text.clear();
    setState(() {
      _denied = true;
      _busy = false;
      _pending = null;
      _data = null;
      _messages = null;
      _error = const WorkspaceFailure('denied').message;
    });
  }

  void _failed(Object e) {
    final failure =
        e is WorkspaceFailure ? e : const WorkspaceFailure('unknown');
    if (failure.denied || _gateway.userId != _actor) {
      _invalidate();
      return;
    }
    setState(() {
      _error = failure.message;
      _data = null;
      _messages = null;
    });
  }

  Future<void> _refresh({String? before}) async {
    if (_busy || _denied) return;
    if (_gateway.userId != _actor || _actor == null) {
      _invalidate();
      return;
    }
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final data = await _gateway
          .load(widget.incidentId)
          .timeout(const Duration(seconds: 15));
      final messages = await _gateway
          .messages(widget.incidentId, before: before)
          .timeout(const Duration(seconds: 15));
      if (!_owns(generation)) return;
      setState(() {
        _data = data;
        _messages = messages;
      });
    } catch (e) {
      if (_owns(generation)) _failed(e);
    } finally {
      if (_owns(generation)) setState(() => _busy = false);
    }
  }

  Future<void> _action(String action, Map<String, dynamic> payload) async {
    if (_busy ||
        _denied ||
        !widget.enabled ||
        _data == null ||
        _pending != null) {
      return;
    }
    if (payload.containsKey('text') &&
        ((payload['text'] as String).trim().isEmpty ||
            (payload['text'] as String).runes.length > 1000)) {
      setState(
          () => _error = 'Enter a message or reason (up to 1,000 characters).');
      return;
    }
    if (action == 'close' || action == 'provider_completed') {
      final version = _data!.version;
      final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
                  title: Text(action == 'close'
                      ? 'Close this Corvia incident?'
                      : 'Record provider completion?'),
                  content: const Text(
                      'Record only what a person has confirmed. This does not cancel an external response or confirm medical treatment.'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Go back')),
                    FilledButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('Confirm'))
                  ]));
      if (!mounted ||
          confirmed != true ||
          _busy ||
          _denied ||
          !widget.enabled ||
          _data?.version != version ||
          _pending != null) {
        return;
      }
    }
    _pending = (
      id: createEmergencyOperationId(),
      version: _data!.version,
      action: action,
      payload: Map.unmodifiable(payload)
    );
    await _sendPending();
  }

  Future<void> _sendPending() async {
    final pending = _pending;
    if (pending == null || _busy || _denied || !widget.enabled) return;
    if (_gateway.userId != _actor) {
      _invalidate();
      return;
    }
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      if (pending.action == 'message') {
        await _gateway
            .send(widget.incidentId, pending.id,
                pending.payload['text'] as String)
            .timeout(const Duration(seconds: 15));
      } else {
        await _gateway
            .command(widget.incidentId, pending.id, pending.version,
                pending.action, pending.payload)
            .timeout(const Duration(seconds: 15));
      }
      if (!_owns(generation)) return;
      setState(() {
        _pending = null;
        _text.clear();
        if (pending.action == 'callback_outcome') _callbackOutcome = null;
        _notice = pending.action == 'message'
            ? 'Saved to Corvia. Read receipt is not available.'
            : 'Action recorded.';
      });
      widget.onChanged?.call();
    } catch (e) {
      if (!_owns(generation)) return;
      // A definitive conflict means this attempt did not mutate; next attempt
      // must use a newly loaded version. Unknown outcomes keep the original ID.
      if (e is WorkspaceFailure &&
          (e.kind == 'conflict' || e.kind == 'unavailable')) {
        _pending = null;
        if (e.kind == 'conflict') _notice = e.message;
      }
      _failed(e);
    } finally {
      if (_owns(generation)) setState(() => _busy = false);
    }
    if (_owns(generation) && _pending == null) await _refresh();
  }

  @override
  void didUpdateWidget(covariant IncidentWorkspacePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Hosts key by incident/account; never carry an uncertain action to a new ID.
    if (oldWidget.incidentId != widget.incidentId ||
        oldWidget.gateway != widget.gateway) {
      _invalidate();
    }
  }

  @override
  void dispose() {
    _generation++;
    _timer?.cancel();
    unawaited(_subscription?.cancel());
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    final editable = widget.enabled && !_busy && !_denied && _pending == null;
    return Card(
        child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Incident tools and messages',
                      style: Theme.of(context).textTheme.titleMedium),
                  if (_busy) const LinearProgressIndicator(),
                  if (_error != null) Text(_error!, semanticsLabel: _error),
                  if (_notice != null) Text(_notice!),
                  if (!widget.enabled)
                    const Text(
                        'Incident tools are paused while access and status are checked.'),
                  if (_pending != null) ...[
                    const Text(
                        'The last action has no confirmed result. Check saved state before retrying the same action.'),
                    OutlinedButton(
                        onPressed: !_busy && !_denied && widget.enabled
                            ? _sendPending
                            : null,
                        child: const Text('Retry same action')),
                  ],
                  if (data != null && widget.enabled) ...[
                    Text('Corvia status: ${data.status.replaceAll('_', ' ')}'),
                    if (!data.isPatient)
                      OutlinedButton.icon(
                        onPressed: editable
                            ? () => Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                    builder: (_) => ResponseWorkspacePage(
                                        incidentId: widget.incidentId)))
                            : null,
                        icon: const Icon(Icons.emergency),
                        label: const Text('Open unit and crew response'),
                      ),
                    if (!data.isPatient && data.callbackNumber != null) ...[
                      SelectableText(
                          'Patient-provided callback number: ${data.callbackNumber}'),
                      OutlinedButton.icon(
                          onPressed: editable
                              ? () => _callPatient(data.callbackNumber!)
                              : null,
                          icon: const Icon(Icons.phone),
                          label: const Text('Open phone to call patient')),
                    ],
                    if (data.cancellationRequested)
                      const Text(
                          'Patient requested cancellation. The incident remains active until dispatch reviews it.'),
                    Text(data.providerDemo
                        ? 'Provider DEMO: ${data.providerState.replaceAll('_', ' ')}. No request was sent to ER24.'
                        : 'ER24 API is not connected. Direct calling remains available.'),
                    if (data.providerState == 'unknown')
                      const Text(
                          'Provider confirmation is unknown. Do not create another provider request.'),
                    if (data.providerState == 'unknown' ||
                        data.providerState == 'rejected' ||
                        data.providerState == 'unavailable')
                      const EmergencyPhoneCard(),
                    if (data.canManage) ...[
                      DropdownButtonFormField<String>(
                          key: ValueKey('${data.version}:priority'),
                          initialValue: data.priority,
                          decoration: const InputDecoration(
                              labelText:
                                  'Dispatcher priority (not a clinical diagnosis)'),
                          items: const [
                            DropdownMenuItem(
                                value: 'untriaged', child: Text('Untriaged')),
                            DropdownMenuItem(
                                value: 'urgent', child: Text('Urgent')),
                            DropdownMenuItem(
                                value: 'standard', child: Text('Standard'))
                          ],
                          onChanged: editable
                              ? (v) {
                                  if (v != null) {
                                    unawaited(_action(
                                        'set_priority', {'priority': v}));
                                  }
                                }
                              : null),
                      if (data.demoAvailable &&
                          data.providerState == 'not_requested')
                        Wrap(spacing: 8, children: [
                          for (final state in [
                            'accepted',
                            'rejected',
                            'unavailable',
                            'unknown'
                          ])
                            OutlinedButton(
                                onPressed: editable
                                    ? () => _action('simulate_provider',
                                        {'scenario': state})
                                    : null,
                                child: Text('Demo $state'))
                        ]),
                      if (data.providerState == 'unknown')
                        OutlinedButton(
                            onPressed: editable
                                ? () => _action('reconcile_provider', {})
                                : null,
                            child: const Text('Check existing demo request')),
                    ],
                    const SizedBox(height: 8),
                    if (!data.closed) ...[
                      TextField(
                          controller: _text,
                          enabled: editable,
                          maxLength: 1000,
                          maxLines: 3,
                          decoration: InputDecoration(
                              labelText: data.isPatient
                                  ? 'Message or cancellation reason'
                                  : 'Message, internal note or closure reason')),
                      Wrap(spacing: 8, children: [
                        FilledButton(
                            onPressed: editable &&
                                    (data.isPatient || data.canManage)
                                ? () => _action('message', {'text': _text.text})
                                : null,
                            child: const Text('Send message')),
                        if (data.canManage) ...[
                          if (Env.ws4TeamEmsHandoffEnabled &&
                              data.callbackNumber != null) ...[
                            DropdownButtonFormField<String>(
                              key: ValueKey('${data.version}:callback-outcome'),
                              initialValue: _callbackOutcome,
                              decoration: const InputDecoration(
                                  labelText: 'Observed callback outcome'),
                              items: const [
                                DropdownMenuItem(value: 'connected',
                                    child: Text('Connected to patient')),
                                DropdownMenuItem(value: 'no_answer',
                                    child: Text('No answer')),
                                DropdownMenuItem(value: 'failed',
                                    child: Text('Call failed')),
                                DropdownMenuItem(value: 'not_attempted',
                                    child: Text('Call not attempted')),
                              ],
                              onChanged: editable ? (value) =>
                                setState(() => _callbackOutcome = value) : null),
                            OutlinedButton(
                              onPressed: editable && _callbackOutcome != null
                                  ? _recordCallback : null,
                              child: const Text('Record observed callback outcome')),
                          ],
                          OutlinedButton(
                              onPressed: editable
                                  ? () => _action('note', {'text': _text.text})
                                  : null,
                              child: const Text('Save internal note')),
                          OutlinedButton(
                              onPressed: editable
                                  ? () => _action('close', {'text': _text.text})
                                  : null,
                              child: const Text('Close with reason')),
                          if (data.providerState == 'accepted')
                            OutlinedButton(
                                onPressed: editable
                                    ? () => _action('provider_completed',
                                        {'text': _text.text})
                                    : null,
                                child: const Text('Record demo completion')),
                        ],
                        if (data.isPatient &&
                            data.status == 'in_progress' &&
                            !data.cancellationRequested)
                          OutlinedButton(
                              onPressed: editable
                                  ? () => _action('request_cancellation',
                                      {'text': _text.text})
                                  : null,
                              child: const Text('Ask dispatch to cancel')),
                      ]),
                    ],
                    if (!data.isPatient && data.actions.isNotEmpty) ...[
                      const Text('Recent internal actions (latest 50)'),
                      for (final action in data.actions)
                        Text(
                            '${action['recorded_at']} · ${action['action']}\n${action['text'] ?? ''}'),
                    ],
                    const Divider(),
                    const Text('Saved messages — newest first'),
                    if (_messages?.messages.isEmpty == true)
                      const Text('No messages on this page.'),
                    for (final message
                        in _messages?.messages ?? <Map<String, dynamic>>[])
                      Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Text(
                              '${message['sender']} · ${message['recorded_at']}\n${message['body']}')),
                    if (_messages?.nextCursor != null)
                      TextButton(
                          onPressed: !_busy
                              ? () => _refresh(before: _messages!.nextCursor)
                              : null,
                          child: const Text('Older messages')),
                  ],
                  TextButton(
                      onPressed: !_busy && !_denied ? () => _refresh() : null,
                      child: const Text('Refresh saved state')),
                ])));
  }
}
