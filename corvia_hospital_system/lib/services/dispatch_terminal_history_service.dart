import 'package:supabase_flutter/supabase_flutter.dart';

import '../pages/dispatch/dispatch_history_report_panel.dart';
import 'emergency_dispatch_service.dart';
import 'incident_history_service.dart';

/// Authorised, read-only snapshot. This is NOT the complete hospital history.
class DispatchTerminalHistorySnapshot {
  const DispatchTerminalHistorySnapshot({
    required this.records,
    required this.receivedAt,
    required this.hasMore,
  });

  final List<DispatchHistoryRecord> records;
  final DateTime receivedAt;
  final bool hasMore;
}

abstract class DispatchTerminalHistoryGateway {
  String? get currentUserId;
  Stream<String?> get userChanges;
  Future<DispatchTerminalHistorySnapshot> loadRecent();
}

/// Uses existing RLS, corvia_dispatch_access_context and
/// corvia_incident_history. Creates no new tables/RPCs/policies.
class SupabaseDispatchTerminalHistoryService
    implements DispatchTerminalHistoryGateway {
  SupabaseDispatchTerminalHistoryService({
    SupabaseClient? client,
    EmergencyDispatchService? dispatch,
    IncidentHistoryService? history,
    this.limit = 20,
  })  : assert(limit > 0 && limit <= 30),
        _client = client ?? Supabase.instance.client,
        _dispatch = dispatch ??
            EmergencyDispatchService(
              client: client ?? Supabase.instance.client,
            ),
        _history = history ??
            IncidentHistoryService(
              client: client ?? Supabase.instance.client,
            );

  final SupabaseClient _client;
  final EmergencyDispatchService _dispatch;
  final IncidentHistoryService _history;
  final int limit;

  @override
  String? get currentUserId => _client.auth.currentUser?.id;

  @override
  Stream<String?> get userChanges => _client.auth.onAuthStateChange
      .map((event) => event.session?.user.id);

  static bool _sameAccess(
    DispatchAccessContext before,
    DispatchAccessContext after,
  ) {
    if (before.userId != after.userId ||
        before.policyVersion != after.policyVersion ||
        before.canReadIncidents != after.canReadIncidents ||
        before.canReadIncidentHistory != after.canReadIncidentHistory ||
        before.canReadIntakeDetails != after.canReadIntakeDetails ||
        before.canClaimIncident != after.canClaimIncident ||
        before.canUseIncidentWorkspace != after.canUseIncidentWorkspace) {
      return false;
    }

    final first = before.memberships
        .map((m) => '${m.organisationId}:${m.role}')
        .toList()..sort();
    final second = after.memberships
        .map((m) => '${m.organisationId}:${m.role}')
        .toList()..sort();
    return first.join('|') == second.join('|');
  }

  /// Only a ledger's terminal event confirms case resolution/cancellation.
  /// Resolution must NOT be interpreted as clinical handover.
  static DispatchHistoryRecord recordFromLedger({
    required String incidentId,
    required String databaseStatus,
    required IncidentHistory history,
  }) {
    if (!isIncidentHistoryId(incidentId) ||
        history.incidentId != incidentId ||
        history.events.isEmpty) {
      throw const FormatException('Incident history identity mismatch.');
    }

    final last = history.events.last;
    final status = databaseStatus.trim().toLowerCase();
    final verifiedResolved =
        status == 'resolved' && last.eventType == 'resolved' &&
        last.status == 'resolved';
    final verifiedCancelled =
        status == 'cancelled' && last.eventType == 'cancelled' &&
        last.status == 'cancelled';

    if (!verifiedResolved && !verifiedCancelled) {
      throw const FormatException('Terminal incident history mismatch.');
    }

    return DispatchHistoryRecord(
      incidentId: incidentId,
      status: status,
      // This means verified INCIDENT resolution, not patient handover.
      completion: verifiedResolved
          ? DispatchCompletionState.completed
          : DispatchCompletionState.notCompleted,
      // No clinical outcome field exists in this response.
      outcome: null,
      createdAt: history.events.first.recordedAt,
      completedAt: verifiedResolved ? last.recordedAt : null,
    );
  }

  static String _id(Object? raw) {
    if (raw is String && isIncidentHistoryId(raw)) return raw;
    if (raw is int && raw > 0 && raw <= 9007199254740991) {
      return raw.toString();
    }
    throw const FormatException('Untrusted incident identifier.');
  }

  @override
  Future<DispatchTerminalHistorySnapshot> loadRecent() async {
    final actor = currentUserId;
    if (actor == null) {
      throw StateError('Dispatch sign-in required.');
    }
    final before = await _dispatch.loadAccessContext();
    if (before.userId != actor ||
        !before.canReadIncidents ||
        !before.canReadIncidentHistory) {
      throw StateError('Authorised dispatch history access required.');
    }

    // Existing incidents table, scoped by the current user's Supabase RLS.
    // Restrict the query to known terminal states and safe, non-PII fields.
    final rows = await _client
        .from('incidents')
        .select('id,status')
        .inFilter('status', const ['resolved', 'cancelled'])
        .order('id', ascending: false)
        .limit(limit + 1);

    final hasMore = rows.length > limit;
    final selected = rows.take(limit).toList(growable: false);
    final seen = <String>{};
    final verified = <DispatchHistoryRecord>[];

    // RPCs run sequentially to avoid a burst of clinical-data queries.
    for (final row in selected) {
      if (currentUserId != actor) {
        throw StateError('Dispatch session changed during history read.');
      }
      final id = _id(row['id']);
      if (!seen.add(id)) {
        throw const FormatException('Duplicate incident in report response.');
      }
      final status = row['status'];
      if (status is! String) {
        throw const FormatException('Missing terminal incident status.');
      }
      final ledger = await _history.load(id);
      verified.add(recordFromLedger(
        incidentId: id,
        databaseStatus: status,
        history: ledger,
      ));
    }

    final after = await _dispatch.loadAccessContext();
    if (currentUserId != actor || !_sameAccess(before, after)) {
      throw StateError('Dispatch access changed during history read.');
    }

    return DispatchTerminalHistorySnapshot(
      records: List<DispatchHistoryRecord>.unmodifiable(verified),
      receivedAt: after.serverTime,
      hasMore: hasMore,
    );
  }
}
