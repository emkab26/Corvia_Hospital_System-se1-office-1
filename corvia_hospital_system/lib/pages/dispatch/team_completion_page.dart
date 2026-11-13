import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../controllers/patient_emergency_intake_controller.dart'
    show createEmergencyOperationId;
import '../../models/dispatch/incident_history.dart';
import '../../services/incident_workspace_service.dart';
import '../../services/team_completion_service.dart';

List<Map<String, dynamic>> _rows(Object? value) {
  if (value is! List || value.any((item) => item is! Map)) {
    throw const WorkspaceFailure('invalid');
  }
  return value.map((item) => Map<String, dynamic>.from(item as Map)).toList();
}

/// Dispatch opens one linked case; a backup medic opens their own offer list.
class Ws4BackupPage extends StatefulWidget {
  const Ws4BackupPage({super.key, this.incidentId, this.gateway});
  final String? incidentId;
  final Ws4TeamCompletionGateway? gateway;

  @override
  State<Ws4BackupPage> createState() => _Ws4BackupPageState();
}

class _Ws4BackupPageState extends State<Ws4BackupPage> {
  late final Ws4TeamCompletionGateway gateway;
  final reason = TextEditingController();
  StreamSubscription<AuthState>? authSubscription;
  String? actor, error, selectedCrew;
  Map<String, dynamic>? data;
  Map<String, Map<String, dynamic>> deadlines = {};
  Future<void> Function()? retry;
  bool busy = false, stale = false;
  int generation = 0;

  @override
  void initState() {
    super.initState();
    gateway = widget.gateway ?? SupabaseWs4TeamCompletionService();
    actor = gateway.userId;
    if (gateway is SupabaseWs4TeamCompletionService) {
      authSubscription = (gateway as SupabaseWs4TeamCompletionService)
          .client
          .auth
          .onAuthStateChange
          .listen((_) {
        if (mounted && gateway.userId != actor) _deny();
      });
    }
    _load();
  }

  bool _owns(int token) =>
      mounted && token == generation && gateway.userId == actor;

  void _deny() {
    generation++;
    setState(() {
      data = null;
      deadlines = {};
      retry = null;
      stale = true;
      reason.clear();
      busy = false;
      error = const WorkspaceFailure('denied').message;
    });
  }

  Future<void> _load() async {
    final token = ++generation;
    if (actor == null || gateway.userId != actor) return _deny();
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final next = await gateway.backupOverview(widget.incidentId);
      final nextDeadlines = <String, Map<String, dynamic>>{};
      if (gateway is Ws4TeamOperationsGateway) {
        final timing = await (gateway as Ws4TeamOperationsGateway)
            .backupDeadlines(widget.incidentId);
        for (final row in _rows(timing['items'])) {
          if (row['backup_id'] is String) {
            nextDeadlines[row['backup_id'] as String] = row;
          }
        }
      }
      _rows(next[widget.incidentId == null ? 'items' : 'backups']);
      if (widget.incidentId != null) {
        final candidates = _rows(next['candidates']);
        if (!candidates.any((c) =>
            c['crew_id'] == selectedCrew && c['eligibility_reason'] == null)) {
          selectedCrew = null;
        }
      }
      if (!_owns(token)) return;
      setState(() {
        data = next;
        deadlines = nextDeadlines;
        busy = false;
        stale = false;
      });
    } catch (e) {
      if (!_owns(token)) return;
      if (e is WorkspaceFailure && e.denied) return _deny();
      setState(() {
        busy = false;
        stale = true;
        error = e is WorkspaceFailure
            ? e.message
            : const WorkspaceFailure('unknown').message;
      });
    }
  }

  Future<void> _act(Future<Map<String, dynamic>> Function() action) async {
    final token = ++generation;
    if (actor == null || gateway.userId != actor) return _deny();
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await action();
      if (!_owns(token)) return;
      retry = null;
      selectedCrew = null;
      reason.clear();
      await _load();
    } catch (e) {
      if (!_owns(token)) return;
      if (e is WorkspaceFailure && e.denied) return _deny();
      final definite = e is WorkspaceFailure &&
          (e.kind == 'conflict' || e.kind == 'invalid');
      setState(() {
        busy = false;
        stale = definite;
        retry = definite ? null : () => _act(action);
        error = definite
            ? e.message
            : 'Outcome unknown. Refresh saved state, then retry this same action if needed.';
      });
    }
  }

  void _dispatch(String action) {
    final revision = data?['ems_revision'];
    final crew = action == 'offer' ? selectedCrew : null;
    final why = reason.text.trim();
    if (!isIncidentHistoryId(revision) ||
        (action == 'offer' && !isIncidentHistoryId(crew)) ||
        why.length < 5) {
      setState(() => error = 'Select an eligible crew and enter a reason.');
      return;
    }
    final operation = createEmergencyOperationId();
    _act(() => gateway.backupDispatch(
        widget.incidentId!, operation, revision as String, action, crew, why));
  }

  void _crew(String id, String version, String action) {
    final operation = createEmergencyOperationId();
    _act(() => gateway.backupCrew(id, operation, version, action));
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
    final dispatch = widget.incidentId != null;
    final backups = data == null
        ? <Map<String, dynamic>>[]
        : _rows(data![dispatch ? 'backups' : 'items']);
    final candidates = dispatch && data != null
        ? _rows(data!['candidates'])
        : <Map<String, dynamic>>[];
    final active = backups.any((b) => const {
          'offered',
          'acknowledged',
          'en_route',
          'on_scene'
        }.contains(b['state']));
    return Scaffold(
      appBar: AppBar(
          title: Text(dispatch ? 'Team EMS backup' : 'My backup responses')),
      body: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            children: [
              if (error != null)
                Text(error!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error)),
              if (busy) const LinearProgressIndicator(),
              if (retry != null)
                TextButton(
                    onPressed: busy ? null : retry,
                    child: const Text('Retry the same backup action')),
              if (dispatch && data != null) ...[
                Text(
                    'Linked EMS incident ${data!['incident_number']} · ${data!['status']}'),
                if (data!['backup_requested'] != true)
                  const Text(
                      'Record “Request backup” in the team incident first.'),
                if (!active && data!['backup_requested'] == true) ...[
                  DropdownButtonFormField<String>(
                      initialValue: selectedCrew,
                      decoration: const InputDecoration(
                          labelText: 'Eligible backup crew'),
                      items: candidates
                          .where((c) =>
                              c['eligibility_reason'] == null &&
                              isIncidentHistoryId(c['crew_id']))
                          .map((c) => DropdownMenuItem<String>(
                              value: c['crew_id'] as String,
                              child: Text(
                                  '${c['crew_code']} · ${c['unit_number']}')))
                          .toList(),
                      onChanged: busy || stale
                          ? null
                          : (v) => setState(() => selectedCrew = v)),
                  TextField(
                      controller: reason,
                      decoration: const InputDecoration(
                          labelText: 'Why backup is needed')),
                  FilledButton(
                      onPressed: busy || stale || retry != null
                          ? null
                          : () => _dispatch('offer'),
                      child: const Text('Offer backup crew')),
                ],
                if (active) ...[
                  TextField(
                      controller: reason,
                      decoration: const InputDecoration(
                          labelText: 'Reason to release backup')),
                  FilledButton.tonal(
                      onPressed: busy || stale || retry != null
                          ? null
                          : () => _dispatch('release'),
                      child: const Text('Release backup crew')),
                ],
              ],
              if (data != null && backups.isEmpty)
                const Text('No backup responses to show.'),
              for (final b in backups)
                Card(
                    child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(dispatch
                            ? '${b['crew_code']} · ${b['unit_number']}'
                            : '${b['incident_number']} · ${b['priority']}'),
                        Text('State: ${b['state']}'),
                        if (deadlines[b['backup_id']]?['due_at'] != null &&
                            b['state'] == 'offered')
                          Text('Acknowledge by ${deadlines[b['backup_id']]!['due_at']}'
                              '${deadlines[b['backup_id']]!['overdue'] == true ? ' · OVERDUE — dispatch review required' : ''}'),
                        if (b['reason'] != null) Text('Reason: ${b['reason']}'),
                        if (!dispatch && b['scene_address'] != null)
                          Text('Scene: ${b['scene_address']}'),
                        if (!dispatch &&
                            b['state'] == 'offered' &&
                            isIncidentHistoryId(b['backup_id']) &&
                            isIncidentHistoryId(b['version']))
                          Wrap(spacing: 8, children: [
                            FilledButton(
                                onPressed: busy || stale || retry != null ||
                                        deadlines[b['backup_id']]?['overdue'] == true
                                    ? null
                                    : () => _crew(b['backup_id'] as String,
                                        b['version'] as String, 'acknowledge'),
                                child: const Text('Acknowledge backup')),
                            OutlinedButton(
                                onPressed: busy || stale || retry != null
                                    ? null
                                    : () => _crew(b['backup_id'] as String,
                                        b['version'] as String, 'decline'),
                                child: const Text('Decline backup')),
                          ]),
                        if (!dispatch &&
                            const {'acknowledged', 'en_route'}
                                .contains(b['state']) &&
                            isIncidentHistoryId(b['backup_id']) &&
                            isIncidentHistoryId(b['version']))
                          FilledButton.tonal(
                            onPressed: busy || stale || retry != null
                                ? null
                                : () => _crew(
                                    b['backup_id'] as String,
                                    b['version'] as String,
                                    b['state'] == 'acknowledged'
                                        ? 'en_route'
                                        : 'on_scene'),
                            child: Text(b['state'] == 'acknowledged'
                                ? 'Mark en route'
                                : 'Mark on scene'),
                          ),
                        if (gateway is Ws4TeamOperationsGateway &&
                            isIncidentHistoryId(b['backup_id']) &&
                            (dispatch || const {'offered','acknowledged',
                              'en_route','on_scene'}.contains(b['state'])))
                          TextButton.icon(
                            onPressed: busy || stale ? null : () =>
                              Navigator.of(context).push(MaterialPageRoute<void>(
                                builder: (_) => Ws4BackupConversationPage(
                                  backupId: b['backup_id'] as String,
                                  active: const {'offered','acknowledged',
                                    'en_route','on_scene'}.contains(b['state']),
                                  gateway: gateway as Ws4TeamOperationsGateway))),
                            icon: const Icon(Icons.message_outlined),
                            label: const Text('Backup conversation')),
                      ]),
                )),
            ],
          )),
    );
  }
}

class Ws4ReceivingInboxPage extends StatefulWidget {
  const Ws4ReceivingInboxPage({super.key, this.gateway});
  final Ws4TeamCompletionGateway? gateway;

  @override
  State<Ws4ReceivingInboxPage> createState() => _Ws4ReceivingInboxPageState();
}

class Ws4BackupConversationPage extends StatefulWidget {
  const Ws4BackupConversationPage({super.key, required this.backupId,
    required this.gateway, this.active = true});
  final String backupId;
  final Ws4TeamOperationsGateway gateway;
  final bool active;

  @override
  State<Ws4BackupConversationPage> createState() =>
      _Ws4BackupConversationPageState();
}

class _Ws4BackupConversationPageState extends State<Ws4BackupConversationPage> {
  final input = TextEditingController();
  StreamSubscription<AuthState>? authSubscription;
  String? actor, error;
  List<Map<String, dynamic>>? messages;
  Future<void> Function()? retry;
  int generation = 0;
  bool busy = false, stale = false;

  @override
  void initState() {
    super.initState();
    actor = widget.gateway.userId;
    if (widget.gateway is SupabaseWs4TeamCompletionService) {
      authSubscription = (widget.gateway as SupabaseWs4TeamCompletionService)
          .client.auth.onAuthStateChange.listen((_) {
        if (mounted && widget.gateway.userId != actor) _deny();
      });
    }
    _load();
  }

  bool _owns(int token) => mounted && token == generation &&
      widget.gateway.userId == actor;

  void _deny() {
    generation++;
    setState(() {
      messages = null;
      retry = null;
      busy = false;
      stale = true;
      input.clear();
      error = const WorkspaceFailure('denied').message;
    });
  }

  Future<void> _load() async {
    final token = ++generation;
    if (actor == null || widget.gateway.userId != actor) return _deny();
    setState(() { busy = true; error = null; });
    try {
      final next = await widget.gateway.backupConversation(widget.backupId);
      if (next['backup_id'] != widget.backupId) {
        throw const WorkspaceFailure('invalid');
      }
      final rows = _rows(next['messages']);
      if (!_owns(token)) return;
      setState(() { messages = rows; busy = false; stale = false; });
    } catch (e) {
      if (!_owns(token)) return;
      if (e is WorkspaceFailure && e.denied) return _deny();
      setState(() {
        busy = false;
        stale = true;
        error = e is WorkspaceFailure ? e.message :
            const WorkspaceFailure('unknown').message;
      });
    }
  }

  Future<void> _send(String body, String operation) async {
    final token = ++generation;
    if (actor == null || widget.gateway.userId != actor) return _deny();
    setState(() { busy = true; error = null; });
    try {
      await widget.gateway.backupMessage(widget.backupId, operation, body);
      if (!_owns(token)) return;
      retry = null;
      input.clear();
      await _load();
    } catch (e) {
      if (!_owns(token)) return;
      if (e is WorkspaceFailure && e.denied) return _deny();
      final definitive = e is WorkspaceFailure &&
          const {'conflict','invalid','unavailable'}.contains(e.kind);
      setState(() {
        busy = false;
        stale = definitive;
        retry = definitive ? null : () => _send(body, operation);
        error = definitive ? e.message :
            'Outcome unknown. Check saved messages, then retry the same send.';
      });
    }
  }

  Future<void> _read(String messageId, String operation) async {
    final token = ++generation;
    if (actor == null || widget.gateway.userId != actor) return _deny();
    setState(() { busy = true; error = null; });
    try {
      await widget.gateway.backupMarkRead(messageId, operation);
      if (!_owns(token)) return;
      retry = null;
      await _load();
    } catch (e) {
      if (!_owns(token)) return;
      if (e is WorkspaceFailure && e.denied) return _deny();
      final definitive = e is WorkspaceFailure &&
          const {'conflict','invalid','unavailable'}.contains(e.kind);
      setState(() {
        busy = false;
        stale = definitive;
        retry = definitive ? null : () => _read(messageId, operation);
        error = definitive ? e.message :
            'Read outcome unknown. Check saved state, then retry the same action.';
      });
    }
  }

  @override
  void dispose() {
    generation++;
    authSubscription?.cancel();
    input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Backup conversation'), actions: [
      IconButton(onPressed: busy ? null : _load,
          tooltip: 'Refresh saved messages', icon: const Icon(Icons.refresh))
    ]),
    body: RefreshIndicator(onRefresh: _load, child: ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16), children: [
        const Text('Messages are saved to Corvia. Read status appears only after '
            'the other person explicitly marks a message read.'),
        if (busy) const LinearProgressIndicator(),
        if (error != null) Text(error!, style: TextStyle(
            color: Theme.of(context).colorScheme.error)),
        if (retry != null) TextButton(onPressed: busy ? null : retry,
            child: const Text('Retry the same message action')),
        for (final message in messages ?? <Map<String, dynamic>>[]) Card(
          child: ListTile(
            title: Text('${message['body']}'),
            subtitle: Text('${message['sender']} · Saved ${message['saved_at']}'
                '${message['read_by_other'] == true ? ' · Read by other person' : ''}'),
            trailing: message['sender'] == 'team' &&
                isIncidentHistoryId(message['id'])
              ? TextButton(onPressed: busy || stale || retry != null ? null :
                  () => _read(message['id'] as String,
                      createEmergencyOperationId()),
                child: const Text('Mark read')) : null)),
        if (widget.active) ...[
          TextField(controller: input, maxLength: 2000,
              decoration: const InputDecoration(labelText: 'Message dispatch or backup crew')),
          FilledButton(onPressed: busy || stale || retry != null ? null : () {
            final body = input.text.trim();
            if (body.isNotEmpty) _send(body, createEmergencyOperationId());
          }, child: const Text('Save and send message')),
        ],
      ],
    )),
  );
}

class _Ws4ReceivingInboxPageState extends State<Ws4ReceivingInboxPage> {
  late final Ws4TeamCompletionGateway gateway;
  final reason = TextEditingController();
  StreamSubscription<AuthState>? authSubscription;
  String? actor, error, selectedHandoverId;
  List<Map<String, dynamic>>? items;
  Future<void> Function()? retry;
  bool busy = false, stale = false;
  int generation = 0;

  @override
  void initState() {
    super.initState();
    gateway = widget.gateway ?? SupabaseWs4TeamCompletionService();
    actor = gateway.userId;
    if (gateway is SupabaseWs4TeamCompletionService) {
      authSubscription = (gateway as SupabaseWs4TeamCompletionService)
          .client
          .auth
          .onAuthStateChange
          .listen((_) {
        if (mounted && gateway.userId != actor) _deny();
      });
    }
    _load();
  }

  bool _owns(int token) =>
      mounted && token == generation && gateway.userId == actor;

  void _deny() {
    generation++;
    setState(() {
      items = null;
      retry = null;
      selectedHandoverId = null;
      stale = true;
      reason.clear();
      busy = false;
      error = const WorkspaceFailure('denied').message;
    });
  }

  Future<void> _load() async {
    final token = ++generation;
    if (actor == null || gateway.userId != actor) return _deny();
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final next = _rows((await gateway.receiverInbox())['items']);
      if (!_owns(token)) return;
      setState(() {
        items = next;
        busy = false;
        stale = false;
      });
    } catch (e) {
      if (!_owns(token)) return;
      if (e is WorkspaceFailure && e.denied) return _deny();
      setState(() {
        busy = false;
        stale = true;
        error = e is WorkspaceFailure
            ? e.message
            : const WorkspaceFailure('unknown').message;
      });
    }
  }

  Future<void> _confirm(String id, String operation, String explanation) async {
    final token = ++generation;
    if (actor == null || gateway.userId != actor) return _deny();
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await gateway.receiverAck(id, operation, explanation);
      if (!_owns(token)) return;
      retry = null;
      reason.clear();
      await _load();
    } catch (e) {
      if (!_owns(token)) return;
      if (e is WorkspaceFailure && e.denied) return _deny();
      final definite = e is WorkspaceFailure &&
          (e.kind == 'conflict' || e.kind == 'invalid');
      setState(() {
        busy = false;
        stale = definite;
        retry = definite ? null : () => _confirm(id, operation, explanation);
        error = definite
            ? e.message
            : 'Outcome unknown. Refresh, then retry this same confirmation if needed.';
      });
    }
  }

  void _submit(String id) {
    final explanation = reason.text.trim();
    if (explanation.length < 5) {
      setState(() => error = 'Describe how you received this handover.');
      return;
    }
    _confirm(id, createEmergencyOperationId(), explanation);
  }

  @override
  void dispose() {
    generation++;
    authSubscription?.cancel();
    reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Receiving handovers')),
        body: RefreshIndicator(
            onRefresh: _load,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              children: [
                const Text('Confirm only a handover you received in person.'),
                if (error != null)
                  Text(error!,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error)),
                if (busy) const LinearProgressIndicator(),
                if (retry != null)
                  TextButton(
                      onPressed: busy ? null : retry,
                      child: const Text('Retry the same confirmation')),
                if (items != null && items!.isEmpty)
                  const Text('No handovers for your assigned facility.'),
                for (final item in items ?? <Map<String, dynamic>>[])
                  Card(
                      child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                    '${item['incident_number']} · ${item['facility_name']}'),
                                Text(
                                    'Named receiver: ${item['receiver_name']}'),
                                Text('${item['handover_summary']}'),
                                Text(item['acknowledged'] == true
                                    ? 'Confirmed'
                                    : 'Awaiting confirmation'),
                                if (item['acknowledged'] != true &&
                                    isIncidentHistoryId(
                                        item['handover_id'])) ...[
                                  if (selectedHandoverId != item['handover_id'])
                                    OutlinedButton(
                                        onPressed:
                                            busy || stale || retry != null
                                                ? null
                                                : () => setState(() {
                                                      selectedHandoverId =
                                                          item['handover_id']
                                                              as String;
                                                      reason.clear();
                                                    }),
                                        child:
                                            const Text('Review this handover')),
                                  if (selectedHandoverId ==
                                      item['handover_id']) ...[
                                    TextField(
                                        controller: reason,
                                        decoration: const InputDecoration(
                                            labelText:
                                                'How you received this handover')),
                                    FilledButton(
                                        onPressed: busy ||
                                                stale ||
                                                retry != null
                                            ? null
                                            : () => _submit(
                                                item['handover_id'] as String),
                                        child: const Text(
                                            'Confirm handover received')),
                                  ],
                                ],
                              ]))),
              ],
            )),
      );
}
