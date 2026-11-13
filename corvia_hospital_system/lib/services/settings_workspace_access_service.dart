import 'package:supabase_flutter/supabase_flutter.dart';

import 'blood_bank_service.dart';
import 'paramedic_workspace_service.dart';
import 'response_workflow_service.dart';

class SettingsWorkspaceAccess {
  const SettingsWorkspaceAccess({
    this.emergencyResponse = false,
    this.paramedic = false,
    this.bloodBank = false,
    this.backupResponses = false,
    this.receivingHandovers = false,
  });

  final bool emergencyResponse;
  final bool paramedic;
  final bool bloodBank;
  final bool backupResponses;
  final bool receivingHandovers;

  bool get hasStaffWorkspaces => paramedic || bloodBank;
}

/// Navigation visibility follows server membership checks, never profile roles.
/// Workspace pages continue to enforce their own access on entry and commands.
class SettingsWorkspaceAccessService {
  SettingsWorkspaceAccessService({SupabaseClient? client}) : _client = client;

  final SupabaseClient? _client;
  SupabaseClient get client => _client ?? Supabase.instance.client;
  String? get userId => client.auth.currentUser?.id;
  Stream<String?> get users =>
      client.auth.onAuthStateChange.map((event) => event.session?.user.id);

  static bool _hospitalId(Object? value) =>
      value is String &&
      RegExp(r'^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$')
          .hasMatch(value);

  Future<SettingsWorkspaceAccess> load({
    required bool includeStaff,
    required bool includeTeam,
  }) async {
    final actor = userId;
    if (actor == null) return const SettingsWorkspaceAccess();

    // Check each module independently: an unavailable module must not suppress
    // another module's verified membership. No clinical records are fetched.
    Future<bool> allowed(Future<bool> Function() check) async {
      try {
        return await check().timeout(const Duration(seconds: 15));
      } catch (_) {
        return false;
      }
    }

    var teamAccess = const SettingsWorkspaceAccess();
    final results = await Future.wait([
      allowed(() async {
        // This RPC denies callers without active response membership. An empty
        // authorised inbox still grants the workspace entry point.
        await ResponseWorkflowService(client: client).inbox();
        return true;
      }),
      if (includeStaff) ...[
        allowed(() async {
          final service = ParamedicWorkspaceService(client: client);
          try {
            return (await service.access())
                .any((row) => _hospitalId(row['id']));
          } finally {
            service.dispose();
          }
        }),
        allowed(() async => (await BloodBankService(client: client).access())
            .any((row) => _hospitalId(row['hospital_id']))),
      ] else ...[
        Future.value(false),
        Future.value(false),
      ],
      if (includeTeam)
        allowed(() async {
          final value = await client.rpc('corvia_ws4_team_settings_access');
          if (value is Map && value['user_id'] == actor) {
            teamAccess = SettingsWorkspaceAccess(
              backupResponses: value['backup_responses'] == true,
              receivingHandovers: value['receiving_handovers'] == true,
            );
          }
          return true;
        })
      else
        Future.value(false),
    ]);

    if (userId != actor) return const SettingsWorkspaceAccess();
    return SettingsWorkspaceAccess(
      emergencyResponse: results[0],
      paramedic: results[1],
      bloodBank: results[2],
      backupResponses: results[3] && teamAccess.backupResponses,
      receivingHandovers: results[3] && teamAccess.receivingHandovers,
    );
  }
}
