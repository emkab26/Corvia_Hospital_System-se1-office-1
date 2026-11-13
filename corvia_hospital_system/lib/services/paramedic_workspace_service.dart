import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/env.dart';
import 'paramedic_offline_queue.dart';

typedef EmsRow = Map<String, dynamic>;

List<EmsRow> emsRows(dynamic value) => value is List
    ? value.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
    : [];

String emsOperationId() {
  final r = Random.secure();
  final b = List<int>.generate(16, (_) => r.nextInt(256));
  b[6] = (b[6] & 15) | 64;
  b[8] = (b[8] & 63) | 128;
  final hex = b.map((e) => e.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

class ParamedicWorkspaceService extends ChangeNotifier {
  ParamedicWorkspaceService({SupabaseClient? client})
      : client = client ?? Supabase.instance.client;
  final SupabaseClient client;
  final offline = ParamedicOfflineQueue();
  String? hospitalId;
  String? session;
  String? userId;

  bool _isDenial(Object error) => error is PostgrestException &&
      const {'401', '403', '42501', 'PGRST301', 'PGRST302', 'PGRST303'}
          .contains(error.code);

  void _checkActor(String? actor) {
    if (actor == null || client.auth.currentUser?.id != actor) {
      lock();
      throw StateError('Workspace account changed. Reopen it to continue.');
    }
  }

  Future<List<EmsRow>> access() async =>
      emsRows(await client.rpc('corvia_ems_access'));

  Future<void> open(String hospital) async {
    hospitalId = hospital;
    final actor = client.auth.currentUser?.id;
    userId = actor;
    final nextSession = await client.rpc('corvia_ems_open', params: {
      'h': hospital,
      'device': 'Corvia Fleet & Paramedic workspace',
    }) as String;
    _checkActor(actor);
    session = nextSession;
  }

  void lock() {
    session = null;
    offline.lock();
    notifyListeners();
  }

  Map<String, dynamic> get _scope {
    if (session == null ||
        userId == null ||
        client.auth.currentUser?.id != userId) {
      throw StateError('Workspace locked. Reopen it to continue.');
    }
    return {'h': hospitalId, 's': session};
  }

  Future<EmsRow> load([int? incident]) async {
    final actor = userId;
    try {
      final result = Map<String, dynamic>.from(await client
              .rpc('corvia_ems_workspace', params: {..._scope, 'i': incident})
          as Map);
      if (incident != null && Env.ws4TeamEmsHandoffEnabled) {
        final linked = await client.rpc('corvia_ws4_team_case_mode', params: {
          'p_hospital_id': hospitalId,
          'p_incident_id': incident,
        });
        if (linked is! bool) {
          throw StateError('Team handover mode could not be verified.');
        }
        result['ws4_linked'] = linked;
      }
      _checkActor(actor);
      return result;
    } catch (e) {
      if (_isDenial(e)) lock();
      rethrow;
    }
  }

  Future<EmsRow> command(String action, EmsRow data,
      {required String operationId}) async {
    final scope = _scope;
    final actor = userId;
    try {
      final result = Map<String, dynamic>.from(
          await client.rpc('corvia_ems_command', params: {
        ...scope,
        'op': operationId,
        'action': action,
        'p': data,
      }) as Map);
      _checkActor(actor);
      return result;
    } catch (e) {
      if (_isDenial(e)) {
        lock();
        rethrow;
      }
      _checkActor(actor);
      final network = e.toString().contains('SocketException') ||
          e.toString().contains('ClientException') ||
          e.toString().contains('Failed to fetch');
      if (network &&
          offline.unlocked &&
          ['observation', 'note', 'treatment'].contains(action)) {
        await offline.add(operationId, action, data);
        return {'queued': true};
      }
      rethrow;
    }
  }

  Future<EmsRow> updatePatient({
    required int incidentId,
    required int patientId,
    required EmsRow data,
  }) async {
    return Map<String, dynamic>.from(
      await client.rpc('corvia_ems_update_patient', params: {
        ..._scope,
        'i': incidentId,
        'pid': patientId,
        'p': data,
      }) as Map,
    );
  }

  Future<void> sync() async {
    final actor = userId;
    for (final item in List<EmsRow>.from(offline.items)) {
      try {
        await client.rpc('corvia_ems_command', params: {
          ..._scope,
          'op': item['op'],
          'action': item['action'],
          'p': item['payload']
        });
        _checkActor(actor);
        await offline.remove(item['op'] as String);
      } catch (e) {
        await offline.fail(item['op'] as String, e.toString());
        break;
      }
    }
  }
}
