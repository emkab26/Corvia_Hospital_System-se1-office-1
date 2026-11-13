import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/dispatch/incident_history.dart';
import 'incident_workspace_service.dart';

class EmsHandoffStatus {
  EmsHandoffStatus._(
      this.mode,
      this.linked,
      this.teamAccess,
      this.canHandoff,
      this.hospitalId,
      this.emsIncidentId,
      this.emsNumber,
      this.emsStatus,
      this.dispatchState);

  factory EmsHandoffStatus.fromMap(Map<String, dynamic> map) {
    final rawMode = map['mode'];
    final rawLinked = map['linked'];
    if (!const {'team', 'unconfigured'}.contains(rawMode) ||
        rawLinked is! bool ||
        (rawMode == 'unconfigured' && rawLinked)) {
      throw const WorkspaceFailure('invalid');
    }
    final mode = rawMode as String;
    final linked = rawLinked;
    final teamAccess = map['team_access'] == true;
    final canHandoff = map['can_handoff'] == true;
    final hospitalId = map['hospital_id'] as String?;
    final emsIncidentId = map['ems_incident_id'] as String?;
    final emsNumber = map['ems_number'] as String?;
    final emsStatus = map['ems_status'] as String?;
    final dispatchState = map['dispatch_state'] as String?;
    if ((mode == 'team' && !_uuid(hospitalId)) ||
        (linked &&
            (!teamAccess ||
                !isIncidentHistoryId(emsIncidentId) ||
                emsNumber == null ||
                emsNumber.isEmpty ||
                emsNumber.length > 50 ||
                !const {
                  'Dispatched',
                  'Accepted',
                  'En Route',
                  'On Scene',
                  'Transporting',
                  'At Hospital',
                  'Handed Over',
                  'Closed'
                }.contains(emsStatus) ||
                !const {
                  'pending',
                  'claimed',
                  'assigned',
                  'escalated',
                  'closed',
                  'cancelled'
                }.contains(dispatchState))) ||
        (!linked && (emsIncidentId != null || emsStatus != null)) ||
        (canHandoff && (mode != 'team' || !teamAccess || linked))) {
      throw const WorkspaceFailure('invalid');
    }
    return EmsHandoffStatus._(mode, linked, teamAccess, canHandoff, hospitalId,
        emsIncidentId, emsNumber, emsStatus, dispatchState);
  }

  final String mode;
  final bool linked, teamAccess, canHandoff;
  final String? hospitalId, emsIncidentId, emsNumber, emsStatus, dispatchState;

  static bool _uuid(String? value) =>
      value != null &&
      RegExp(r'^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$')
          .hasMatch(value);
}

abstract class EmsHandoffGateway {
  String? get userId;
  Future<EmsHandoffStatus> load(String incidentId);
  Future<EmsHandoffStatus> handoff(String incidentId, String hospitalId,
      String operationId, String priority, String requiredCapability);
}

class SupabaseEmsHandoffService implements EmsHandoffGateway {
  SupabaseEmsHandoffService({SupabaseClient? client})
      : client = client ?? Supabase.instance.client;

  final SupabaseClient client;

  @override
  String? get userId => client.auth.currentUser?.id;

  EmsHandoffStatus _status(Object? response) {
    if (response is! Map<String, dynamic>) {
      throw const WorkspaceFailure('invalid');
    }
    return EmsHandoffStatus.fromMap(response);
  }

  Future<T> _call<T>(Future<T> Function() request) async {
    try {
      return await request();
    } on PostgrestException catch (error) {
      if (const {'401', '403', '42501', 'PGRST301', 'PGRST302', 'PGRST303'}
          .contains(error.code)) {
        throw const WorkspaceFailure('denied');
      }
      if (error.code == 'PGRST202') {
        throw const WorkspaceFailure('unavailable');
      }
      if (error.code == 'P0001' || error.code == '23505') {
        throw const WorkspaceFailure('conflict');
      }
      if (error.code == '22023') {
        throw const WorkspaceFailure('invalid');
      }
      throw const WorkspaceFailure('unknown');
    }
  }

  @override
  Future<EmsHandoffStatus> load(String incidentId) async {
    if (!isIncidentHistoryId(incidentId) || userId == null) {
      throw const WorkspaceFailure('denied');
    }
    final actor = userId;
    final response = await _call(() => client.rpc(
        'corvia_ws4_ems_handoff_status',
        params: {'p_incident_id': incidentId}));
    if (userId != actor) throw const WorkspaceFailure('denied');
    return _status(response);
  }

  @override
  Future<EmsHandoffStatus> handoff(String incidentId, String hospitalId,
      String operationId, String priority, String requiredCapability) async {
    if (!isIncidentHistoryId(incidentId) ||
        !EmsHandoffStatus._uuid(hospitalId) ||
        !EmsHandoffStatus._uuid(operationId) ||
        !const {'Critical', 'High', 'Medium', 'Low'}.contains(priority) ||
        !const {'BLS', 'ILS', 'ALS'}.contains(requiredCapability) ||
        userId == null) {
      throw const WorkspaceFailure('invalid');
    }
    final actor = userId;
    final session = await _call(() => client.rpc('corvia_ems_open',
        params: {'h': hospitalId, 'device': 'Corvia WS4 dispatch handoff'}));
    if (userId != actor ||
        session is! String ||
        !EmsHandoffStatus._uuid(session)) {
      throw const WorkspaceFailure('denied');
    }
    final response =
        await _call(() => client.rpc('corvia_ws4_handoff_to_ems', params: {
              'p_incident_id': incidentId,
              'p_hospital_id': hospitalId,
              'p_session': session,
              'p_operation_id': operationId,
              'p_priority': priority,
              'p_required_capability': requiredCapability,
            }));
    if (userId != actor) throw const WorkspaceFailure('denied');
    final status = _status(response);
    if (!status.linked || status.hospitalId != hospitalId) {
      throw const WorkspaceFailure('invalid');
    }
    return status;
  }
}
