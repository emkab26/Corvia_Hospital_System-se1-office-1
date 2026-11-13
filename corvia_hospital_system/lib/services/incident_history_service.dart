import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/dispatch/incident_history.dart';
import '../models/dispatch/patient_emergency_intake.dart' show isEmergencyUuid;
export '../models/dispatch/incident_history.dart';

/// The server scopes access. No user identifier is accepted as an RPC argument.
class IncidentHistoryService {
  IncidentHistoryService(
      {SupabaseClient? client, Duration timeout = const Duration(seconds: 15)})
      : _client = client ?? Supabase.instance.client,
        _timeout = timeout;
  final SupabaseClient _client;
  final Duration _timeout;
  String? get currentUserId => _client.auth.currentUser?.id;
  Stream<String?> get userChanges =>
      _client.auth.onAuthStateChange.map((event) => event.session?.user.id);

  void _checkActor(String? userId) {
    if (!isEmergencyUuid(userId) || currentUserId != userId) {
      throw const IncidentHistoryException(
          IncidentHistoryFailureKind.authentication);
    }
  }

  Future<IncidentHistory> load(String incidentId) async {
    final userId = currentUserId;
    _checkActor(userId);
    if (!isIncidentHistoryId(incidentId)) {
      throw const IncidentHistoryException(
          IncidentHistoryFailureKind.invalidResponse);
    }
    try {
      final response = await _client.rpc('corvia_incident_history', params: {
        'p_incident_id': incidentId,
      }).timeout(_timeout);
      _checkActor(userId);
      if (response is! Map<String, dynamic>) {
        throw const IncidentHistoryException(
            IncidentHistoryFailureKind.invalidResponse);
      }
      return IncidentHistory.fromMap(response, expectedIncidentId: incidentId);
    } on PostgrestException catch (error) {
      _checkActor(userId);
      final kind = const {
        '42501',
        '401',
        '403',
        'PGRST301',
        'PGRST302',
        'PGRST303'
      }.contains(error.code)
          ? IncidentHistoryFailureKind.authentication
          : const {'PGRST202', '42883'}.contains(error.code)
              ? IncidentHistoryFailureKind.configuration
              : IncidentHistoryFailureKind.unavailable;
      throw IncidentHistoryException(kind);
    } on AuthException {
      throw const IncidentHistoryException(
          IncidentHistoryFailureKind.authentication);
    } on IncidentHistoryException {
      rethrow;
    } catch (_) {
      _checkActor(userId);
      throw const IncidentHistoryException(
          IncidentHistoryFailureKind.unavailable);
    }
  }
}
