import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/dispatch/patient_emergency_intake.dart';
export '../models/dispatch/patient_emergency_intake.dart';

abstract interface class PatientEmergencyIntakeGateway {
  String? get currentUserId;
  Future<PatientEmergencyIncident> request(
      {required String userId,
      required String operationId,
      required PatientEmergencyIntakeRequest input});
  Future<PatientEmergencyIncident?> lookup(
      {required String userId, required String operationId});
  Future<PatientEmergencyIncident> cancel(
      {required String userId,
      required String operationId,
      required String expectedVersion});
}

class PatientEmergencyIntakeService implements PatientEmergencyIntakeGateway {
  PatientEmergencyIntakeService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;
  final SupabaseClient _client;
  @override
  String? get currentUserId => _client.auth.currentUser?.id;
  Stream<String?> get userChanges =>
      _client.auth.onAuthStateChange.map((event) => event.session?.user.id);

  void _checkActor(String userId, String operationId) {
    if (!isEmergencyUuid(userId) || currentUserId != userId) {
      throw const PatientEmergencyIntakeException(
          PatientEmergencyFailureKind.authentication);
    }
    if (!isEmergencyUuid(operationId)) {
      throw const PatientEmergencyIntakeException(
          PatientEmergencyFailureKind.invalidInput);
    }
  }

  Future<dynamic> _rpc(String name, Map<String, dynamic> params, String userId,
      String operationId) async {
    _checkActor(userId, operationId);
    try {
      final response = await _client
          .rpc(name, params: params)
          .timeout(const Duration(seconds: 15));
      // A mutation may already have committed; withholding its result is not rollback.
      _checkActor(userId, operationId);
      return response;
    } on PostgrestException catch (error) {
      _checkActor(userId, operationId);
      final kind = const {'PGRST202', '42883'}.contains(error.code)
          ? PatientEmergencyFailureKind.configuration
          : const {'42501', '401', '403', 'PGRST301', 'PGRST302', 'PGRST303'}
                  .contains(error.code)
              ? PatientEmergencyFailureKind.authentication
              : error.code == '22023'
                  ? PatientEmergencyFailureKind.invalidInput
                  : error.code == 'P0001'
                      ? PatientEmergencyFailureKind.conflict
                      : PatientEmergencyFailureKind.unknown;
      throw PatientEmergencyIntakeException(kind);
    } on AuthException {
      throw const PatientEmergencyIntakeException(
          PatientEmergencyFailureKind.authentication);
    } on PatientEmergencyIntakeException {
      rethrow;
    } catch (_) {
      _checkActor(userId, operationId);
      throw const PatientEmergencyIntakeException(
          PatientEmergencyFailureKind.unknown);
    }
  }

  @override
  Future<PatientEmergencyIncident> request(
      {required String userId,
      required String operationId,
      required PatientEmergencyIntakeRequest input}) async {
    final response = await _rpc('corvia_patient_request_emergency',
        input.toRpc(operationId), userId, operationId);
    if (response is! Map<String, dynamic>) {
      throw const PatientEmergencyIntakeException(
          PatientEmergencyFailureKind.unknown);
    }
    final result = PatientEmergencyIncident.fromMap(response,
        expectedUserId: userId, expectedOperationId: operationId);
    if (result.request != input) {
      throw const PatientEmergencyIntakeException(
          PatientEmergencyFailureKind.unknown);
    }
    return result;
  }

  @override
  Future<PatientEmergencyIncident> cancel(
      {required String userId,
      required String operationId,
      required String expectedVersion}) async {
    _checkActor(userId, operationId);
    if (!RegExp(r'^[1-9][0-9]*$').hasMatch(expectedVersion) ||
        BigInt.parse(expectedVersion) >= BigInt.parse('9223372036854775807')) {
      throw const PatientEmergencyIntakeException(
          PatientEmergencyFailureKind.invalidInput);
    }
    final response = await _rpc(
        'corvia_patient_cancel_emergency',
        {
          'p_operation_id': operationId,
          'p_expected_version': expectedVersion,
        },
        userId,
        operationId);
    if (response is! Map<String, dynamic>) {
      throw const PatientEmergencyIntakeException(
          PatientEmergencyFailureKind.unknown);
    }
    final result = PatientEmergencyIncident.fromMap(response,
        expectedUserId: userId, expectedOperationId: operationId);
    if (result.status != 'cancelled' ||
        BigInt.parse(result.version) !=
            BigInt.parse(expectedVersion) + BigInt.one) {
      throw const PatientEmergencyIntakeException(
          PatientEmergencyFailureKind.unknown);
    }
    return result;
  }

  @override
  Future<PatientEmergencyIncident?> lookup(
      {required String userId, required String operationId}) async {
    final response = await _rpc('corvia_patient_request_status',
        {'p_operation_id': operationId}, userId, operationId);
    if (response == null) return null;
    if (response is! Map<String, dynamic>) {
      throw const PatientEmergencyIntakeException(
          PatientEmergencyFailureKind.unknown);
    }
    return PatientEmergencyIncident.fromMap(response,
        expectedUserId: userId, expectedOperationId: operationId);
  }
}
