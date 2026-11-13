import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/dispatch/incident_history.dart';
import 'incident_workspace_service.dart';

const responseStates = {
  'offered',
  'acknowledged',
  'en_route',
  'on_scene',
  'transporting',
  'at_hospital',
  'handover_requested',
  'completed',
  'rejected',
  'withdrawn',
  'timed_out'
};

class ResponseWorkspace {
  ResponseWorkspace.fromMap(Map<String, dynamic> value, String id) {
    if (value['incident_id'] != id ||
        !isIncidentHistoryId(value['version']) ||
        !const {'dispatcher', 'dispatch_supervisor', 'crew', 'receiver'}
            .contains(value['role']) ||
        !const {'pending', 'in_progress', 'resolved', 'cancelled'}
            .contains(value['status']) ||
        value['can_manage'] is! bool ||
        value['older_events'] is! bool ||
        value['server_time'] is! String ||
        DateTime.tryParse(value['server_time']) == null) {
      throw const WorkspaceFailure('invalid');
    }
    incidentId = id;
    version = value['version'];
    role = value['role'];
    status = value['status'];
    canManage = value['can_manage'];
    serverTime = DateTime.parse(value['server_time']);
    olderEvents = value['older_events'];
    sceneDetails = value['scene_details'] as String?;
    priority = value['priority'] as String? ?? 'untriaged';
    if ((sceneDetails?.length ?? 0) > 1000 ||
        !const {'untriaged', 'urgent', 'standard'}.contains(priority)) {
      throw const WorkspaceFailure('invalid');
    }
    units = _rows(value['units'], 200);
    assignments = _rows(value['assignments'], 200);
    destinations = _rows(value['destinations'], 200);
    events = _rows(value['events'], 100);
    for (final u in units) {
      if (!_uuid(u['id']) ||
          u['label'] is! String ||
          u['reason'] is! String ||
          !isIncidentHistoryId(u['version'])) {
        throw const WorkspaceFailure('invalid');
      }
      final review = u['review'];
      if ((u['can_review'] != null && u['can_review'] is! bool) ||
          (review != null &&
              (review is! Map<String, dynamic> ||
                  !_uuid(review['actor']) ||
                  review['reason'] is! String ||
                  review['recorded_at'] is! String ||
                  DateTime.tryParse(review['recorded_at']) == null ||
                  review['valid_until'] is! String ||
                  DateTime.tryParse(review['valid_until']) == null))) {
        throw const WorkspaceFailure('invalid');
      }
    }
    for (final a in assignments) {
      if (!_uuid(a['id']) ||
          !_uuid(a['unit_id']) ||
          a['unit'] is! String ||
          a['crew'] is! String ||
          !responseStates.contains(a['state']) ||
          a['active'] is! bool ||
          a['crew_available'] is! bool ||
          a['patient_confirmed'] is! bool ||
          a['location_fresh'] is! bool ||
          a['mine'] is! bool ||
          a['overdue'] is! bool ||
          !const {'primary', 'backup'}.contains(a['purpose']) ||
          a['deadline'] is! String ||
          DateTime.tryParse(a['deadline']) == null ||
          (a['attention'] != null && a['attention'] is! String) ||
          (a['destination_id'] != null && !_uuid(a['destination_id']))) {
        throw const WorkspaceFailure('invalid');
      }
      _location(a);
    }
    for (final d in destinations) {
      if (!_uuid(d['id']) || d['label'] is! String) {
        throw const WorkspaceFailure('invalid');
      }
      _location(d);
    }
    for (final e in events) {
      if (!isIncidentHistoryId(e['id']) ||
          !isIncidentHistoryId(e['version']) ||
          !(e['actor_id'] == null && e['actor_role'] == 'incident') &&
              !_uuid(e['actor_id']) ||
          e['actor_role'] is! String ||
          e['command'] is! String ||
          e['detail'] is! String ||
          (e['detail'] as String).length > 1000 ||
          e['occurred_at'] is! String ||
          DateTime.tryParse(e['occurred_at']) == null ||
          e['recorded_at'] is! String ||
          DateTime.tryParse(e['recorded_at']) == null) {
        throw const WorkspaceFailure('invalid');
      }
    }
    _location(value);
    location = Map.unmodifiable({
      for (final key in [
        'latitude',
        'longitude',
        'location_source',
        'location_at',
        'accuracy_metres',
        'address'
      ])
        key: value[key]
    });
    if (!const {'dispatcher', 'dispatch_supervisor'}.contains(role) &&
        (canManage || units.isNotEmpty)) {
      throw const WorkspaceFailure('invalid');
    }
  }
  late final String incidentId, version, role, status;
  late final String priority;
  late final String? sceneDetails;
  late final bool canManage, olderEvents;
  late final DateTime serverTime;
  late final List<Map<String, dynamic>> units,
      assignments,
      destinations,
      events;
  late final Map<String, dynamic> location;
  static bool _uuid(dynamic v) =>
      v is String &&
      RegExp(r'^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$')
          .hasMatch(v);
  static List<Map<String, dynamic>> _rows(dynamic value, int limit) {
    if (value is! List ||
        value.length > limit ||
        value.any((e) => e is! Map<String, dynamic>)) {
      throw const WorkspaceFailure('invalid');
    }
    return List.unmodifiable(value.map(
        (e) => Map<String, dynamic>.unmodifiable(e as Map<String, dynamic>)));
  }

  static void _location(Map<String, dynamic> v) {
    final accuracy = v['accuracy_metres'];
    if (accuracy != null &&
        (accuracy is! num ||
            !accuracy.isFinite ||
            accuracy < 0 ||
            accuracy >= 100000)) {
      throw const WorkspaceFailure('invalid');
    }
    for (final pair in [('latitude', 90), ('longitude', 180)]) {
      final n = v[pair.$1];
      if (n != null && (n is! num || !n.isFinite || n.abs() > pair.$2)) {
        throw const WorkspaceFailure('invalid');
      }
    }
    if (v['location_at'] != null &&
        (v['location_at'] is! String ||
            DateTime.tryParse(v['location_at']) == null)) {
      throw const WorkspaceFailure('invalid');
    }
  }
}

abstract interface class ResponseWorkflowGateway {
  String? get userId;
  Stream<String?> get users;
  Future<List<String>> inbox({bool includeClosed = false});
  Future<Map<String, dynamic>?> unit();
  Future<void> unitLocation(String id, String operation, String version,
      Map<String, dynamic> payload);
  Future<void> reviewReadiness(String id, String operation, String version,
      Map<String, dynamic> payload);
  Future<ResponseWorkspace> load(String id);
  Future<void> command(String id, String operation, String version,
      String action, Map<String, dynamic> payload);
}

class ResponseWorkflowService implements ResponseWorkflowGateway {
  ResponseWorkflowService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;
  final SupabaseClient _client;
  @override
  String? get userId => _client.auth.currentUser?.id;
  @override
  Stream<String?> get users =>
      _client.auth.onAuthStateChange.map((e) => e.session?.user.id);
  Future<Map<String, dynamic>> _rpc(
      String name, Map<String, dynamic> params) async {
    final actor = userId;
    if (actor == null) throw const WorkspaceFailure('denied');
    try {
      final value = await _client
          .rpc(name, params: params)
          .timeout(const Duration(seconds: 15));
      if (actor != userId) throw const WorkspaceFailure('denied');
      if (value is! Map<String, dynamic>) {
        throw const WorkspaceFailure('invalid');
      }
      return value;
    } on PostgrestException catch (e) {
      if (actor != userId ||
          const {'401', '403', '42501', 'PGRST301', 'PGRST302', 'PGRST303'}
              .contains(e.code)) {
        throw const WorkspaceFailure('denied');
      }
      if (const {'PGRST202', '42883'}.contains(e.code)) {
        throw const WorkspaceFailure('unavailable');
      }
      if (const {'P0001', '22023', '22P02', '23505'}.contains(e.code)) {
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
  Future<Map<String, dynamic>?> unit() async {
    final data = await _rpc('corvia_response_my_unit', {});
    final u = data['unit'];
    if (u == null) return null;
    if (u is! Map<String, dynamic> ||
        !ResponseWorkspace._uuid(u['id']) ||
        u['label'] is! String ||
        !isIncidentHistoryId(u['version'])) {
      throw const WorkspaceFailure('invalid');
    }
    return Map.unmodifiable(u);
  }

  @override
  Future<void> unitLocation(String id, String operation, String version,
          Map<String, dynamic> payload) =>
      _unitCommand(
          'corvia_response_unit_location', id, operation, version, payload);

  @override
  Future<void> reviewReadiness(String id, String operation, String version,
          Map<String, dynamic> payload) =>
      _unitCommand(
          'corvia_response_review_readiness', id, operation, version, payload);

  Future<void> _unitCommand(String rpc, String id, String operation,
      String version, Map<String, dynamic> payload) async {
    if (!ResponseWorkspace._uuid(id) || !isIncidentHistoryId(version)) {
      throw const WorkspaceFailure('invalid');
    }
    final r = await _rpc(rpc, {
      'p_unit_id': id,
      'p_operation_id': operation,
      'p_expected_version': version,
      'p_payload': payload
    });
    if (r['unit_id'] != id ||
        r['operation_id'] != operation ||
        !isIncidentHistoryId(r['version']) ||
        BigInt.parse(r['version']) != BigInt.parse(version) + BigInt.one) {
      throw const WorkspaceFailure('unknown');
    }
  }

  @override
  Future<List<String>> inbox({bool includeClosed = false}) async {
    final v = await _rpc(
        'corvia_response_inbox', {'p_include_closed': includeClosed});
    final ids = v['incidents'];
    if (ids is! List ||
        ids.length > 100 ||
        ids.any((e) => !isIncidentHistoryId(e)) ||
        ids.toSet().length != ids.length) {
      throw const WorkspaceFailure('invalid');
    }
    return List<String>.unmodifiable(ids);
  }

  @override
  Future<ResponseWorkspace> load(String id) async {
    if (!isIncidentHistoryId(id)) throw const WorkspaceFailure('invalid');
    return ResponseWorkspace.fromMap(
        await _rpc('corvia_response_workspace', {'p_incident_id': id}), id);
  }

  @override
  Future<void> command(String id, String operation, String version,
      String action, Map<String, dynamic> payload) async {
    if (!isIncidentHistoryId(id) || !isIncidentHistoryId(version)) {
      throw const WorkspaceFailure('invalid');
    }
    final r = await _rpc('corvia_response_command', {
      'p_incident_id': id,
      'p_operation_id': operation,
      'p_expected_version': version,
      'p_command': action,
      'p_payload': payload
    });
    if (r['incident_id'] != id ||
        r['operation_id'] != operation ||
        !isIncidentHistoryId(r['version']) ||
        BigInt.parse(r['version']) != BigInt.parse(version) + BigInt.one ||
        !ResponseWorkspace._uuid(r['assignment_id'])) {
      throw const WorkspaceFailure('unknown');
    }
  }
}
