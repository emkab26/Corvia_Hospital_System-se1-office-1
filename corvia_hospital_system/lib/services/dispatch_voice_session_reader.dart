
import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../pages/dispatch/incoming_call_session_panel.dart';
import 'emergency_dispatch_service.dart';

/// Read-only access to authorised voice-session metadata.
///
/// This service never exposes SDP, ICE candidates, audio streams,
/// or patient personal information. Voice-control permissions
/// remain disabled until a verified dispatcher signalling
/// contract is implemented.
abstract class DispatchVoiceSessionGateway {
  String? get currentUserId;

  Stream<String?> get userChanges;

  Future<List<IncomingCallSession>> load();
}

class SupabaseDispatchVoiceSessionReader
    implements DispatchVoiceSessionGateway {
  SupabaseDispatchVoiceSessionReader({
    SupabaseClient? client,
    EmergencyDispatchService? dispatchService,
    this.timeout = const Duration(seconds: 20),
  })  : _client = client ?? Supabase.instance.client,
        _dispatch = dispatchService ??
            EmergencyDispatchService(
              client: client ?? Supabase.instance.client,
            );

  final SupabaseClient _client;
  final EmergencyDispatchService _dispatch;
  final Duration timeout;

  @override
  String? get currentUserId {
    return _client.auth.currentUser?.id;
  }

  @override
  Stream<String?> get userChanges {
    return _client.auth.onAuthStateChange.map(
      (event) => event.session?.user.id,
    );
  }

  static bool _sameAccess(
    DispatchAccessContext before,
    DispatchAccessContext after,
  ) {
    if (before.userId != after.userId ||
        before.policyVersion != after.policyVersion ||
        before.canReadIncidents != after.canReadIncidents ||
        before.canUseIncidentWorkspace !=
            after.canUseIncidentWorkspace ||
        before.canClaimIncident != after.canClaimIncident ||
        before.canReadIncidentHistory !=
            after.canReadIncidentHistory ||
        before.canReadIntakeDetails !=
            after.canReadIntakeDetails) {
      return false;
    }

    final beforeMemberships = before.memberships
        .map(
          (member) =>
              '${member.organisationId}:${member.role}',
        )
        .toList()
      ..sort();

    final afterMemberships = after.memberships
        .map(
          (member) =>
              '${member.organisationId}:${member.role}',
        )
        .toList()
      ..sort();

    return beforeMemberships.join('|') ==
        afterMemberships.join('|');
  }

  @override
  Future<List<IncomingCallSession>> load() async {
    final actor = currentUserId;

    if (actor == null) {
      throw StateError('Dispatch sign-in required.');
    }

    return _read(actor).timeout(timeout);
  }

  Future<List<IncomingCallSession>> _read(
    String actor,
  ) async {
    final before = await _dispatch.loadAccessContext();

    if (before.userId != actor ||
        !before.canReadIncidents) {
      throw StateError(
        'Dispatch access could not be verified.',
      );
    }

    // Load only incidents permitted by the existing dispatch API.
    // This is an active-incident view, not historical call reporting.
    final incidents =
        await _dispatch.loadIncomingEmergencies(
      isCurrent: () => currentUserId == actor,
    );

    final authorisedIds = incidents
        .where(
          (incident) => incident.hasValidIdentity,
        )
        .map(
          (incident) => incident.id,
        )
        .toSet();

    List<Map<String, dynamic>> rows = [];

    if (authorisedIds.isNotEmpty) {
      // Supabase RLS must ALSO authorise access to call_sessions.
      final response = await _client
          .from('call_sessions')
          .select('id, incident_id, status')
          .inFilter(
            'incident_id',
            authorisedIds.toList(),
          )
          .order(
            'id',
            ascending: false,
          )
          .limit(200);

      if (response.length >= 200) {
        throw StateError(
          'Voice session results exceed the supported read window.',
        );
      }

      rows = response
          .map(
            (row) => Map<String, dynamic>.from(row),
          )
          .toList();
    }

    // The user may have signed out or lost dispatch access
    // while the database query was running.
    final after = await _dispatch.loadAccessContext();

    if (currentUserId != actor ||
        !_sameAccess(before, after)) {
      throw StateError(
        'Dispatch access changed during the read.',
      );
    }

    return parseRows(
      rows,
      authorisedIncidentIds: authorisedIds,
    );
  }

  /// Pure parser for a scoped call-session result.
  ///
  /// No call action permission is inferred from "ringing",
  /// "answered", "active" or incident claim status.
  static List<IncomingCallSession> parseRows(
    List<Map<String, dynamic>> rows, {
    required Set<String> authorisedIncidentIds,
  }) {
    final result = <IncomingCallSession>[];
    final seen = <String>{};

    for (final row in rows) {
      final id = _numericId(row['id']);

      final incidentId = _numericId(
        row['incident_id'],
      );

      if (id == null ||
          incidentId == null ||
          !authorisedIncidentIds.contains(incidentId) ||
          !seen.add(id)) {
        throw const FormatException(
          'Invalid voice-session response.',
        );
      }

      final rawStatus = row['status']
          ?.toString()
          .trim()
          .toLowerCase();

      final state = switch (rawStatus) {
        'ringing' => IncomingCallState.ringing,
        'answered' || 'connecting' =>
          IncomingCallState.connecting,
        'ended' => IncomingCallState.ended,
        'declined' => IncomingCallState.declined,
        _ => IncomingCallState.unknown,
      };

      result.add(
        IncomingCallSession(
          id: id,
          incidentId: incidentId,

          // The existing read contract does not expose
          // an authenticated call action revision.
          revision: '',

          state: state,

          displayName:
              'Incident $incidentId voice session',

          ownedByMe: false,
          ownedByOther: false,

          canAnswer: false,
          canDecline: false,
          canHangUp: false,
        ),
      );
    }

    return List<IncomingCallSession>.unmodifiable(
      result,
    );
  }

  static String? _numericId(Object? value) {
    if (value is String) {
      final id = value.trim();

      if (!RegExp(
        r'^[1-9][0-9]*$',
      ).hasMatch(id)) {
        return null;
      }

      final parsed = BigInt.tryParse(id);

      if (parsed == null ||
          parsed >
              BigInt.parse('9223372036854775807')) {
        return null;
      }

      return id;
    }

    if (value is num &&
        value.isFinite &&
        value > 0 &&
        value <= 9007199254740991 &&
        value == value.truncateToDouble()) {
      return value.toInt().toString();
    }

    return null;
  }
}
