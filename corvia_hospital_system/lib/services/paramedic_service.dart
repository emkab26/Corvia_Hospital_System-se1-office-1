import 'package:supabase_flutter/supabase_flutter.dart';

import '../pages/hospital/hospital_page_shared.dart';

class Workstream6ParamedicService {
  Workstream6ParamedicService({SupabaseClient? client})
      : _supabase = client ?? Supabase.instance.client;

  final SupabaseClient _supabase;

  Future<HospitalAdminScope> loadScope() {
    return HospitalAdminScope.load(
      _supabase,
      fallbackName: 'Hospital',
    );
  }

  Future<Workstream6Dashboard> loadDashboard(String hospitalId) async {
    final result = await _supabase.rpc(
      'corvia_ws6_actual_dashboard',
      params: {'p_hospital_id': hospitalId},
    );
    final payload = result is Map
        ? Map<String, dynamic>.from(result)
        : const <String, dynamic>{};

    return Workstream6Dashboard(
      units: _rows(payload['units']),
      incidents: _rows(payload['incidents']),
      assignments: _rows(payload['assignments']),
      activeShifts: _rows(payload['active_shifts']),
    );
  }

  Future<Map<String, dynamic>> createIncident({
    required String hospitalId,
    required String priority,
    required String summary,
  }) async {
    final result = await _supabase.rpc(
      'corvia_ws6_actual_create_incident',
      params: {
        'p_hospital_id': hospitalId,
        'p_priority': priority,
        'p_summary': summary,
      },
    );
    return Map<String, dynamic>.from(result as Map);
  }

  Future<Map<String, dynamic>> createUnit({
    required String hospitalId,
    required String callSign,
    required String unitType,
    String? registrationNumber,
    String? baseLocation,
  }) async {
    final result = await _supabase.rpc(
      'corvia_ws6_actual_create_unit',
      params: {
        'p_hospital_id': hospitalId,
        'p_unit_number': callSign,
        'p_vehicle_type': unitType,
        'p_registration_number': registrationNumber,
        'p_base_location': baseLocation,
      },
    );
    return Map<String, dynamic>.from(result as Map);
  }

  Future<Map<String, dynamic>> registerShift({
    required String hospitalId,
    required String unitId,
    required String displayName,
    required String staffIdentifier,
    required String role,
    required String credentialStatus,
    String? authUserId,
  }) async {
    final result = await _supabase.rpc(
      'corvia_ws6_actual_register_shift',
      params: {
        'p_hospital_id': hospitalId,
        'p_unit_id': int.parse(unitId),
        'p_display_name': displayName,
        'p_employee_number': staffIdentifier,
        'p_role': role,
        'p_verification_status': credentialStatus,
        'p_auth_user_id': authUserId,
      },
    );
    return Map<String, dynamic>.from(result as Map);
  }

  Future<void> assignUnit({
    required String hospitalId,
    required String incidentId,
    required String unitId,
    required int expectedRevision,
  }) async {
    await _supabase.rpc(
      'corvia_ws6_actual_assign_unit',
      params: {
        'p_hospital_id': hospitalId,
        'p_incident_id': int.parse(incidentId),
        'p_unit_id': int.parse(unitId),
        'p_expected_revision': expectedRevision,
      },
    );
  }

  Future<void> setUnitStatus({
    required String hospitalId,
    required String unitId,
    required String status,
    required int expectedRevision,
    String? reason,
  }) async {
    await _supabase.rpc(
      'corvia_ws6_actual_set_unit_status',
      params: {
        'p_hospital_id': hospitalId,
        'p_unit_id': int.parse(unitId),
        'p_new_status': status,
        'p_expected_revision': expectedRevision,
        'p_reason': reason,
      },
    );
  }

  List<Map<String, dynamic>> _rows(dynamic value) {
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
  }
}

class Workstream6Dashboard {
  const Workstream6Dashboard({
    required this.units,
    required this.incidents,
    required this.assignments,
    required this.activeShifts,
  });

  final List<Map<String, dynamic>> units;
  final List<Map<String, dynamic>> incidents;
  final List<Map<String, dynamic>> assignments;
  final List<Map<String, dynamic>> activeShifts;
}
