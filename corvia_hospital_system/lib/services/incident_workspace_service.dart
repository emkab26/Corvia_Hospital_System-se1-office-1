import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/env.dart';
import '../models/dispatch/incident_history.dart';

class WorkspaceFailure implements Exception {
  const WorkspaceFailure(this.kind);
  final String kind;
  bool get denied => kind == 'denied';
  String get message => switch (kind) {
        'denied' => 'Access could not be verified. Sign in again.',
        'unavailable' =>
          'These incident tools are not installed on this backend.',
        'conflict' =>
          'The request changed or this action is not allowed in its current state. Refresh before trying again.',
        'invalid' =>
          'The action or returned information could not be verified.',
        _ =>
          'Confirmation unavailable. Refresh to check the saved state. Retry only the same action if needed.',
      };
}

class IncidentWorkspace {
  IncidentWorkspace.fromMap(Map<String, dynamic> map, String id) {
    if (map['incident_id'] != id ||
        !isIncidentHistoryId(map['version']) ||
        !const {'pending', 'in_progress', 'resolved', 'cancelled'}
            .contains(map['status']) ||
        !const {'untriaged', 'urgent', 'standard'}.contains(map['priority']) ||
        !const {
          'not_requested',
          'accepted',
          'rejected',
          'unavailable',
          'unknown',
          'completed'
        }.contains(map['provider_state']) ||
        [
          'can_manage',
          'is_patient',
          'provider_demo',
          'demo_available',
          'cancellation_requested'
        ].any((k) => map[k] is! bool) ||
        map['recent_actions'] is! List ||
        (map['recent_actions'] as List).length > 50) {
      throw const WorkspaceFailure('invalid');
    }
    version = map['version'];
    status = map['status'];
    priority = map['priority'];
    providerState = map['provider_state'];
    canManage = map['can_manage'];
    isPatient = map['is_patient'];
    providerDemo = map['provider_demo'];
    demoAvailable = map['demo_available'];
    cancellationRequested = map['cancellation_requested'];
    final callback = map['callback_number'];
    if (callback != null &&
        (callback is! String ||
            !RegExp(r'^\+?[0-9]{7,15}$').hasMatch(callback))) {
      throw const WorkspaceFailure('invalid');
    }
    callbackNumber = callback as String?;
    actions = List.unmodifiable((map['recent_actions'] as List).map((raw) {
      if (raw is! Map<String, dynamic> ||
          raw['action'] is! String ||
          (raw['text'] != null &&
              (raw['text'] is! String ||
                  (raw['text'] as String).runes.length > 1000)) ||
          raw['recorded_at'] is! String ||
          DateTime.tryParse(raw['recorded_at']) == null) {
        throw const WorkspaceFailure('invalid');
      }
      return Map<String, dynamic>.unmodifiable(raw);
    }));
    if (isPatient &&
        (canManage || actions.isNotEmpty || callbackNumber != null)) {
      throw const WorkspaceFailure('invalid');
    }
  }
  late final String version, status, priority, providerState;
  late final String? callbackNumber;
  late final bool canManage,
      isPatient,
      providerDemo,
      demoAvailable,
      cancellationRequested;
  late final List<Map<String, dynamic>> actions;
  bool get closed => status == 'resolved' || status == 'cancelled';
}

class IncidentMessagePage {
  IncidentMessagePage.fromMap(Map<String, dynamic> map, String id) {
    if (map['incident_id'] != id ||
        map['messages'] is! List ||
        (map['messages'] as List).length > 50 ||
        (map['next_cursor'] != null &&
            !isIncidentHistoryId(map['next_cursor']))) {
      throw const WorkspaceFailure('invalid');
    }
    BigInt? previous;
    messages = List.unmodifiable((map['messages'] as List).map((raw) {
      if (raw is! Map<String, dynamic> ||
          raw.length != 4 ||
          !isIncidentHistoryId(raw['id']) ||
          !const {'patient', 'dispatch'}.contains(raw['sender']) ||
          raw['body'] is! String ||
          (raw['body'] as String).trim().isEmpty ||
          (raw['body'] as String).runes.length > 1000 ||
          raw['recorded_at'] is! String ||
          DateTime.tryParse(raw['recorded_at']) == null) {
        throw const WorkspaceFailure('invalid');
      }
      final number = BigInt.parse(raw['id']);
      if (previous != null && number >= previous!) {
        throw const WorkspaceFailure('invalid');
      }
      previous = number;
      return Map<String, dynamic>.unmodifiable(raw);
    }));
    nextCursor = map['next_cursor'];
    if (nextCursor != null &&
        (messages.length != 50 || nextCursor != messages.last['id'])) {
      throw const WorkspaceFailure('invalid');
    }
  }
  late final List<Map<String, dynamic>> messages;
  late final String? nextCursor;
}

abstract interface class IncidentWorkspaceGateway {
  String? get userId;
  Stream<String?> get users;
  Future<IncidentWorkspace> load(String id);
  Future<IncidentMessagePage> messages(String id, {String? before});
  Future<void> command(String id, String operation, String version,
      String command, Map<String, dynamic> payload);
  Future<void> send(String id, String operation, String body);
}

class IncidentWorkspaceService implements IncidentWorkspaceGateway {
  IncidentWorkspaceService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;
  final SupabaseClient _client;
  @override
  String? get userId => _client.auth.currentUser?.id;
  @override
  Stream<String?> get users =>
      _client.auth.onAuthStateChange.map((e) => e.session?.user.id);
  Future<Map<String, dynamic>> _rpc(
      String name, String id, Map<String, dynamic> params) async {
    final actor = userId;
    if (actor == null) throw const WorkspaceFailure('denied');
    if (!isIncidentHistoryId(id)) throw const WorkspaceFailure('invalid');
    try {
      final value = await _client.rpc(name, params: {
        'p_incident_id': id,
        ...params
      }).timeout(const Duration(seconds: 15));
      if (actor != userId) throw const WorkspaceFailure('denied');
      if (value is! Map<String, dynamic> || value['incident_id'] != id) {
        throw const WorkspaceFailure('invalid');
      }
      return value;
    } on PostgrestException catch (e) {
      if (actor != userId ||
          const {'401', '403', '42501', 'PGRST301', 'PGRST302', 'PGRST303'}
              .contains(e.code)) {
        throw const WorkspaceFailure('denied');
      }
      if (const {'42883', 'PGRST202'}.contains(e.code)) {
        throw const WorkspaceFailure('unavailable');
      }
      if (const {'22023', 'P0001'}.contains(e.code)) {
        throw const WorkspaceFailure('conflict');
      }
      throw const WorkspaceFailure('unknown');
    } on AuthException {
      throw const WorkspaceFailure('denied');
    } on WorkspaceFailure {
      rethrow;
    } catch (_) {
      throw WorkspaceFailure(actor != userId ? 'denied' : 'unknown');
    }
  }

  @override
  Future<IncidentWorkspace> load(String id) async => IncidentWorkspace.fromMap(
      await _rpc('corvia_incident_workspace', id, {}), id);
  @override
  Future<IncidentMessagePage> messages(String id, {String? before}) async =>
      IncidentMessagePage.fromMap(
          await _rpc('corvia_incident_messages', id, {'p_before_id': before}),
          id);
  @override
  Future<void> command(String id, String operation, String version,
      String command, Map<String, dynamic> payload) async {
    final result = await _rpc(
        command == 'callback_outcome' && Env.ws4TeamEmsHandoffEnabled
            ? 'corvia_ws4_callback_outcome'
            : command == 'close' && Env.ws4TeamEmsHandoffEnabled
                ? 'corvia_ws4_close_incident'
                : 'corvia_dispatch_command',
        id,
        {
          'p_operation_id': operation,
          'p_expected_version': version,
          'p_command': command,
          'p_payload': payload
        });
    if (result.length != 4 ||
        result['operation_id'] != operation ||
        result['command'] != command ||
        !isIncidentHistoryId(result['version']) ||
        BigInt.parse(result['version']) != BigInt.parse(version) + BigInt.one) {
      throw const WorkspaceFailure('unknown');
    }
  }

  @override
  Future<void> send(String id, String operation, String body) async {
    final result = await _rpc('corvia_send_incident_message', id,
        {'p_operation_id': operation, 'p_body': body});
    if (result.length != 4 ||
        result['operation_id'] != operation ||
        !isIncidentHistoryId(result['id']) ||
        result['recorded_at'] is! String ||
        DateTime.tryParse(result['recorded_at']) == null) {
      throw const WorkspaceFailure('unknown');
    }
  }
}
