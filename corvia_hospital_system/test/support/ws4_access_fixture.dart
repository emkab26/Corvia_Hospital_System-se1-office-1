import 'package:mycorvia/services/emergency_dispatch_service.dart';

DispatchAccessContext fixtureDispatchAccess({
  bool supervisor = false,
  bool canClaim = true,
  bool canReadIntake = false,
  bool canReadHistory = false,
  bool canUseWorkspace = false,
  String organisationId = '00000000-0000-4000-8000-000000000002',
}) =>
    DispatchAccessContext.fromMap({
      'user_id': '00000000-0000-4000-8000-000000000001',
      'memberships': [
        {
          'organisation_id': organisationId,
          'role': supervisor ? 'dispatch_supervisor' : 'dispatcher'
        },
      ],
      'capabilities': [
        'read_incidents',
        if (canClaim) 'claim_incident',
        if (canReadIntake) 'read_intake_details',
        if (canReadHistory) 'read_incident_history',
        if (canUseWorkspace) 'incident_workspace',
      ],
      'policy_version': 'ws4-dev-core-1',
      'server_time': '2026-10-07T10:00:00Z',
    }, expectedUserId: '00000000-0000-4000-8000-000000000001');
