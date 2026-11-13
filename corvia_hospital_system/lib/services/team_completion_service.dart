import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/dispatch/incident_history.dart';
import 'incident_workspace_service.dart';

abstract class Ws4TeamCompletionGateway {
  String? get userId;
  Future<Map<String, dynamic>> backupOverview(String? ws4IncidentId);
  Future<Map<String, dynamic>> backupDispatch(
      String ws4IncidentId,
      String operationId,
      String revision,
      String action,
      String? crewId,
      String reason);
  Future<Map<String, dynamic>> backupCrew(
      String backupId, String operationId, String version, String action);
  Future<Map<String, dynamic>> receiverInbox();
  Future<Map<String, dynamic>> receiverAck(
      String handoverId, String operationId, String reason);
}

abstract class Ws4TeamOperationsGateway {
  String? get userId;
  Future<String> linkedId(String hospitalId, String emsIncidentId);
  Future<Map<String, dynamic>> teamSnapshot(String ws4IncidentId);
  Future<Map<String, dynamic>> teamCommand(String ws4IncidentId,
      String operationId, String revision, String action,
      Map<String, dynamic> payload);
  Future<Map<String, dynamic>> backupDeadlines(String? ws4IncidentId);
  Future<Map<String, dynamic>> backupConversation(String backupId);
  Future<Map<String, dynamic>> backupMessage(
      String backupId, String operationId, String body);
  Future<Map<String, dynamic>> backupMarkRead(
      String messageId, String operationId);
}

class SupabaseWs4TeamCompletionService
    implements Ws4TeamCompletionGateway, Ws4TeamOperationsGateway {
  SupabaseWs4TeamCompletionService({SupabaseClient? client})
      : client = client ?? Supabase.instance.client;

  final SupabaseClient client;

  @override
  String? get userId => client.auth.currentUser?.id;

  Future<Map<String, dynamic>> _call(
      String name, Map<String, dynamic> params) async {
    final actor = userId;
    if (actor == null) throw const WorkspaceFailure('denied');
    Object? raw;
    try {
      raw = await client.rpc(name, params: params);
    } on PostgrestException catch (error) {
      if (const {'401', '403', '42501', 'PGRST301', 'PGRST302', 'PGRST303'}
          .contains(error.code)) {
        throw const WorkspaceFailure('denied');
      }
      if (error.code == 'PGRST202') {
        throw const WorkspaceFailure('unavailable');
      }
      if (const {'P0001', '23505'}.contains(error.code)) {
        throw const WorkspaceFailure('conflict');
      }
      if (error.code == '22023') throw const WorkspaceFailure('invalid');
      throw const WorkspaceFailure('unknown');
    } catch (_) {
      throw const WorkspaceFailure('unknown');
    }
    if (userId != actor) throw const WorkspaceFailure('denied');
    if (raw is! Map) throw const WorkspaceFailure('invalid');
    return Map<String, dynamic>.from(raw);
  }

  Future<Map<String, dynamic>> _receipt(
      Future<Map<String, dynamic>> Function() call,
      String operationId,
      String idKey,
      String expectedState) async {
    final result = await call();
    final validState = idKey == 'handover_id'
        ? result['acknowledged'] == true
        : result['state'] == expectedState;
    if (result['operation_id'] != operationId ||
        !isIncidentHistoryId(result[idKey]) ||
        !validState) {
      throw const WorkspaceFailure('unknown');
    }
    return result;
  }

  @override
  Future<Map<String, dynamic>> backupOverview(String? ws4IncidentId) {
    if (ws4IncidentId != null && !isIncidentHistoryId(ws4IncidentId)) {
      throw const WorkspaceFailure('invalid');
    }
    return _call(
        'corvia_ws4_backup_overview', {'p_ws4_incident_id': ws4IncidentId});
  }

  @override
  Future<Map<String, dynamic>> backupDispatch(
      String ws4IncidentId,
      String operationId,
      String revision,
      String action,
      String? crewId,
      String reason) {
    if (!isIncidentHistoryId(ws4IncidentId) ||
        !isIncidentHistoryId(revision) ||
        (crewId != null && !isIncidentHistoryId(crewId)) ||
        !const {'offer', 'release'}.contains(action)) {
      throw const WorkspaceFailure('invalid');
    }
    return _receipt(
        () => _call('corvia_ws4_backup_dispatch', {
              'p_ws4_incident_id': ws4IncidentId,
              'p_operation_id': operationId,
              'p_expected_revision': revision,
              'p_action': action,
              'p_crew_id': crewId,
              'p_reason': reason,
            }),
        operationId,
        'backup_id',
        action == 'offer' ? 'offered' : 'released');
  }

  @override
  Future<Map<String, dynamic>> backupCrew(
      String backupId, String operationId, String version, String action) {
    if (!isIncidentHistoryId(backupId) ||
        !isIncidentHistoryId(version) ||
        !const {'acknowledge', 'decline', 'en_route', 'on_scene'}
            .contains(action)) {
      throw const WorkspaceFailure('invalid');
    }
    return _receipt(
        () => _call('corvia_ws4_backup_crew', {
              'p_backup_id': backupId,
              'p_operation_id': operationId,
              'p_expected_version': version,
              'p_action': action,
            }),
        operationId,
        'backup_id',
        switch (action) {
          'acknowledge' => 'acknowledged',
          'decline' => 'declined',
          _ => action,
        });
  }

  @override
  Future<Map<String, dynamic>> receiverInbox() =>
      _call('corvia_ws4_receiver_inbox', {});

  @override
  Future<Map<String, dynamic>> receiverAck(
      String handoverId, String operationId, String reason) {
    if (!isIncidentHistoryId(handoverId)) {
      throw const WorkspaceFailure('invalid');
    }
    return _receipt(
        () => _call('corvia_ws4_receiver_ack', {
              'p_handover_id': handoverId,
              'p_operation_id': operationId,
              'p_reason': reason,
            }),
        operationId,
        'handover_id',
        'acknowledged');
  }

  @override
  Future<String> linkedId(String hospitalId, String emsIncidentId) async {
    if (!isIncidentHistoryId(emsIncidentId)) {
      throw const WorkspaceFailure('invalid');
    }
    final actor = userId;
    if (actor == null) throw const WorkspaceFailure('denied');
    try {
      final id = await client.rpc('corvia_ws4_team_linked_id', params: {
        'p_hospital_id': hospitalId,
        'p_ems_incident_id': emsIncidentId,
      });
      if (actor != userId) throw const WorkspaceFailure('denied');
      if (!isIncidentHistoryId(id)) throw const WorkspaceFailure('invalid');
      return id as String;
    } on PostgrestException catch (e) {
      if (const {'401', '403', '42501', 'PGRST301', 'PGRST302', 'PGRST303'}
          .contains(e.code)) {
        throw const WorkspaceFailure('denied');
      }
      if (e.code == 'PGRST202') {
        throw const WorkspaceFailure('unavailable');
      }
      throw const WorkspaceFailure('unknown');
    }
  }

  @override
  Future<Map<String, dynamic>> teamSnapshot(String ws4IncidentId) {
    if (!isIncidentHistoryId(ws4IncidentId)) {
      throw const WorkspaceFailure('invalid');
    }
    return _call('corvia_ws4_team_snapshot',
        {'p_ws4_incident_id': ws4IncidentId});
  }

  @override
  Future<Map<String, dynamic>> teamCommand(String ws4IncidentId,
      String operationId, String revision, String action,
      Map<String, dynamic> payload) async {
    if (!isIncidentHistoryId(ws4IncidentId) ||
        !isIncidentHistoryId(revision) ||
        !const {'destination', 'exception', 'resolve_exception',
          'terminal_exception', 'release_primary'}.contains(action)) {
      throw const WorkspaceFailure('invalid');
    }
    final result = await _call('corvia_ws4_team_completion_command', {
      'p_ws4_incident_id': ws4IncidentId,
      'p_operation_id': operationId,
      'p_expected_revision': revision,
      'p_action': action,
      'p_payload': payload,
    });
    if (result['operation_id'] != operationId ||
        result['action'] != action ||
        !isIncidentHistoryId(result['revision'])) {
      throw const WorkspaceFailure('unknown');
    }
    return result;
  }

  @override
  Future<Map<String, dynamic>> backupDeadlines(String? ws4IncidentId) {
    if (ws4IncidentId != null && !isIncidentHistoryId(ws4IncidentId)) {
      throw const WorkspaceFailure('invalid');
    }
    return _call('corvia_ws4_backup_deadlines',
        {'p_ws4_incident_id': ws4IncidentId});
  }

  @override
  Future<Map<String, dynamic>> backupConversation(String backupId) {
    if (!isIncidentHistoryId(backupId)) {
      throw const WorkspaceFailure('invalid');
    }
    return _call('corvia_ws4_backup_conversation', {'p_backup_id': backupId});
  }

  @override
  Future<Map<String, dynamic>> backupMessage(
      String backupId, String operationId, String body) async {
    if (!isIncidentHistoryId(backupId) || body.trim().isEmpty ||
        body.length > 2000) {
      throw const WorkspaceFailure('invalid');
    }
    final result = await _call('corvia_ws4_backup_message', {
      'p_backup_id': backupId,
      'p_operation_id': operationId,
      'p_body': body,
    });
    if (result['operation_id'] != operationId ||
        result['backup_id'] != backupId ||
        result['saved'] != true ||
        !isIncidentHistoryId(result['message_id'])) {
      throw const WorkspaceFailure('unknown');
    }
    return result;
  }

  @override
  Future<Map<String, dynamic>> backupMarkRead(
      String messageId, String operationId) async {
    if (!isIncidentHistoryId(messageId)) {
      throw const WorkspaceFailure('invalid');
    }
    final result = await _call('corvia_ws4_backup_mark_read', {
      'p_message_id': messageId,
      'p_operation_id': operationId,
    });
    if (result['operation_id'] != operationId ||
        result['message_id'] != messageId || result['read'] != true) {
      throw const WorkspaceFailure('unknown');
    }
    return result;
  }
}
