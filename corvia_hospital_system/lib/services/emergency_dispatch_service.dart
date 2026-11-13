import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/dispatch/dispatch_access_context.dart';
import '../models/dispatch/dispatch_emergency.dart';
export '../models/dispatch/dispatch_access_context.dart';
export '../models/dispatch/dispatch_emergency.dart';

class EmergencyDispatchService {
  EmergencyDispatchService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;
  final SupabaseClient _client;

  Future<DispatchAccessContext> loadAccessContext() async {
    final actor = _client.auth.currentUser?.id;
    if (actor == null) {
      throw const AuthException('Sign in to dispatch.', statusCode: '401');
    }
    final dynamic response;
    try {
      response = await _client.rpc('corvia_dispatch_access_context');
    } on PostgrestException catch (error) {
      if (const {'PGRST202', '42883'}.contains(error.code)) {
        throw const DispatchAccessException.configuration();
      }
      rethrow;
    }
    if (_client.auth.currentUser?.id != actor) {
      throw const AuthException('Your dispatch session changed.',
          statusCode: '401');
    }
    if (response is! Map<String, dynamic>) {
      throw const DispatchAccessException();
    }
    return DispatchAccessContext.fromMap(response, expectedUserId: actor);
  }

  /// [limit] is the page size, not a limit on visible active emergencies.
  /// Numeric ID cursors avoid offset shifts when other rows close during reads.
  Future<List<DispatchEmergency>> loadIncomingEmergencies(
      {int limit = 100,
      bool Function()? isCurrent,
      bool includeIntakeDetails = false}) async {
    if (limit < 1 || limit > 1000) throw ArgumentError.value(limit, 'limit');
    final incidents = <DispatchEmergency>[];
    String? cursor;
    for (var page = 0; page < 50; page++) {
      if (isCurrent != null && !isCurrent()) {
        throw StateError('This queue read is no longer current.');
      }
      var query = _client
          .from('incidents')
          .select(
            'id, user_id, latitude, longitude, status, created_at, '
            'assigned_dispatcher_user_id, accepted_at'
            '${includeIntakeDetails ? ', address, details, location_source, location_accuracy, location_captured_at' : ''}',
          )
          .or('status.is.null,and(status.not.ilike.resolved,status.not.ilike.cancelled)');
      if (cursor != null) query = query.gt('id', cursor);
      final rows = await query.order('id', ascending: true).limit(limit);
      if (isCurrent != null && !isCurrent()) {
        throw StateError('This queue read is no longer current.');
      }
      incidents.addAll(rows.map((row) => DispatchEmergency.fromMap(row,
          expectIntakeDetails: includeIntakeDetails)));
      if (rows.length < limit) return incidents;
      // Raw JSON numbers may already have rounded on web. A cursor must use
      // the model's validated identity or it could silently skip an incident.
      final last = incidents.last;
      if (!last.hasValidIdentity) {
        throw const FormatException('Invalid incident pagination response.');
      }
      final next = last.id;
      if (cursor != null && BigInt.parse(next) <= BigInt.parse(cursor)) {
        throw const FormatException('Invalid incident pagination response.');
      }
      cursor = next;
    }
    // Never present a silently truncated queue as a successful complete read.
    throw StateError('The incident queue exceeds the supported read window.');
  }

  Future<DispatchEmergency> acceptEmergency(String incidentId) async {
    final numericId = int.tryParse(incidentId);
    if (numericId == null ||
        numericId <= 0 ||
        numericId.toString() != incidentId) {
      throw const FormatException('The incident identifier is invalid.');
    }
    final actor = _client.auth.currentUser?.id;
    if (actor == null) {
      throw const AuthException('Sign in to dispatch.', statusCode: '401');
    }
    final response =
        await _client.rpc('corvia_dispatch_accept_incident', params: {
      'p_incident_id': numericId,
    });
    if (_client.auth.currentUser?.id != actor) {
      // The claim may have committed. Never expose its result to another
      // session or interpret this local identity check as a rollback.
      throw const AuthException(
        'Your dispatch session changed. Reconcile the incident before retrying.',
        statusCode: '401',
      );
    }
    if (response is! Map) {
      throw const FormatException('Invalid claim response.');
    }
    final result =
        DispatchEmergency.fromMap(Map<String, dynamic>.from(response));
    if (result.id != incidentId ||
        !result.isAccepted ||
        result.needsReview ||
        result.assignedDispatcherUserId != actor ||
        result.acceptedAt == null) {
      // The mutation may already have committed. Caller must reconcile, not retry blindly.
      throw const FormatException('The claim result could not be confirmed.');
    }
    return result;
  }
}
