import 'dart:async';
import 'package:mycorvia/services/settings_workspace_access_service.dart';

class FakeSettingsAccess extends SettingsWorkspaceAccessService {
  String? actor = 'account-a';
  final changes = StreamController<String?>.broadcast(sync: true);
  SettingsWorkspaceAccess access = const SettingsWorkspaceAccess();
  Future<SettingsWorkspaceAccess> Function()? onLoad;
  int loads = 0;

  @override
  String? get userId => actor;
  @override
  Stream<String?> get users => changes.stream;
  @override
  Future<SettingsWorkspaceAccess> load({
    required bool includeStaff,
    required bool includeTeam,
  }) async {
    loads++;
    if (onLoad != null) return await onLoad!();
    return access;
  }
}
