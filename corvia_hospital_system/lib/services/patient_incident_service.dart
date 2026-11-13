import 'package:supabase_flutter/supabase_flutter.dart';

/// Compatibility adapter until the versioned patient command RPC is deployed.
/// RLS still provides authority; these predicates only narrow the legacy write.
class PatientIncidentService {
  PatientIncidentService(this.client);
  final SupabaseClient client;

  Future<void> cancelUnclaimedIncident(int incidentId) async {
    final userId = client.auth.currentUser?.id;
    if (userId == null) {
      throw const AuthException('Sign in required.', statusCode: '401');
    }
    final row = await client
        .from('incidents')
        .update({'status': 'cancelled'})
        .eq('id', incidentId)
        .eq('user_id', userId)
        .eq('status', 'pending')
        .isFilter('assigned_dispatcher_user_id', null)
        .select('id, status')
        .maybeSingle();
    if (row == null ||
        row['id'].toString() != incidentId.toString() ||
        row['status'] != 'cancelled') {
      throw StateError('Cancellation was not confirmed.');
    }
  }
}
