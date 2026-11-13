# WS4 backend SQL handoff — 12 October 2026

This is the review package for the database owner, not a deployment record. The shared project has not been changed. The last read-only inspection found no WS4 core installation, no verified restorable backup, a callable anonymous `register_auth_user_temp(text,text)` function, nine legacy incidents, and no team EMS memberships or crews. Resolve these findings on the **exact target project** before installation. Do not paste the local test runner into the shared SQL editor.

## Read-only preflight queries

Run the existing [`preflight.sql`](preflight.sql) first. These additional catalog queries show which candidate contracts already exist without reading patient records:

```sql
BEGIN READ ONLY;
SELECT current_database(), current_user, now() AS checked_at;
SELECT to_regclass('ws4_private.installation') AS ws4_core,
       to_regclass('ws4_private.ems_handoff_routes') AS team_bridge,
       to_regclass('ws4_private.patient_callbacks') AS patient_callbacks,
       to_regclass('ws4_private.emergency_contacts') AS emergency_contacts,
       to_regclass('ws4_private.contact_alert_outbox') AS contact_alert_outbox,
       to_regclass('ws4_private.push_subscriptions') AS push_subscriptions,
       to_regclass('ws4_private.push_outbox') AS push_outbox;
SELECT p.proname, p.oid::regprocedure AS signature
FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
WHERE n.nspname='public' AND p.proname LIKE 'corvia_ws4_%'
ORDER BY p.proname,signature;
SELECT p.oid::regprocedure AS function, p.prosecdef AS security_definer,
       p.proacl AS grants
FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
WHERE n.nspname='public' AND p.proname='register_auth_user_temp';
ROLLBACK;
```

If any candidate object already exists, stop and compare its actual definition and grants. Do not rerun a migration to make a marker appear. Confirm the backup can be restored, resolve the anonymous signup-function decision, and check current client paths that write `public.incidents` before 001 changes those privileges. Preserve the nine legacy records until their owner confirms disposition. Obtain actual organisation/hospital IDs and memberships; do not infer them from matching names.

## Installation order on a reviewed, restorable target

Each linked file is the complete SQL query to review and execute as a database owner. Execute one file at a time and record its result. Do not concatenate the files or skip a prerequisite.

1. [`001_shared_upgrade.sql`](001_shared_upgrade.sql), generated and reviewed as described in this directory's README. On an already bootstrapped WS4 development project, check the installed core instead of applying the shared upgrade.
2. Team contracts [`11_install_fleet_paramedic.sql`](../workstreams/11_install_fleet_paramedic.sql) and [`13_dispatch_fleet_upgrade.sql`](../workstreams/13_dispatch_fleet_upgrade.sql), **only if absent**. Confirm their installed definitions against the current repository before applying; the owner must reconcile them with any later team migration.
3. [`002_team_ems_handoff.sql`](002_team_ems_handoff.sql), [`003_team_ems_completion.sql`](003_team_ems_completion.sql), [`004_team_backup_receiver.sql`](004_team_backup_receiver.sql), [`005_team_operational_completion.sql`](005_team_operational_completion.sql). The optional [`005_team_deadline_schedule.sql`](005_team_deadline_schedule.sql) needs a reviewed scheduler authority.
4. [`006_patient_progress.sql`](006_patient_progress.sql), [`007_incident_voice.sql`](007_incident_voice.sql), [`008_scoped_requester_identity.sql`](008_scoped_requester_identity.sql), [`009_patient_callback.sql`](009_patient_callback.sql), [`010_contact_alert_outbox.sql`](010_contact_alert_outbox.sql), [`011_patient_push_outbox.sql`](011_patient_push_outbox.sql).

The SQL creates no staff accounts, organisation route, team crew, receiver mapping, contact alert sender, push sender, device token, ER24 connector or external provider credential. The owner must map real organisation/hospital scopes and synthetic demo users after reviewing the installed schema. A dispatcher needs both WS4 and team scope for a linked response. An eligible team unit/crew and reviewed receiving account are required for the downstream demonstration.

## App gates and what they mean

Set `CORVIA_EMERGENCY_DISPATCH_ENABLED=true` only after the WS4 core and signed-in patient/dispatcher checks pass. Set `CORVIA_WS4_TEAM_EMS_HANDOFF_ENABLED=true` only after team routes, memberships and linked-case checks pass. Set the remaining flags independently after their corresponding SQL is installed and manually verified: `CORVIA_WS4_REQUESTER_IDENTITY_ENABLED` (008), `CORVIA_WS4_CALLBACK_ENABLED` (009), `CORVIA_WS4_CONTACTS_ENABLED` (010), `CORVIA_WS4_VOICE_ENABLED` (007 plus responder and two-device audio). Patient progress requires the team handoff flag and 006. No app push flag is supplied because no platform token source or sender is installed; 011 remains an integration contract. A Flutter `--dart-define` is a UI/configuration gate, never a substitute for server authorization.

## Provider work still required

For contact alerts, a server-side worker must call `corvia_ws4_contact_alert_claim`, send the generic emergency-contact message using an approved provider, then call `corvia_ws4_contact_alert_ack`; call `corvia_ws4_contact_alert_receipt` only on a verified delivery receipt. For device push, a platform adapter must obtain consent and a token, use `Ws4PushSubscriptionService.register`/`revoke`, and a server-side worker must use the analogous `corvia_ws4_push_claim`/`ack`/`receipt` contract. Keep service credentials only in the server worker. Configure retry scheduling, provider webhook authenticity, opt-out, retention and monitoring. A queued or provider-accepted row is **not** delivery. Do not enable automatic-alert claims in the demo until an actual provider path is tested. The patient must still have direct emergency calling when data/service is unavailable.

## Acceptance queries and checks

After installation, re-run the catalog query above and check the following without reading contact numbers or tokens:

```sql
BEGIN READ ONLY;
SELECT count(*) AS ws4_organisations FROM ws4_private.organisations;
SELECT count(*) AS active_ws4_memberships FROM ws4_private.memberships WHERE active;
SELECT count(*) AS active_team_memberships FROM public.corvia_ops_memberships WHERE active;
SELECT count(*) AS active_handoff_routes FROM ws4_private.ems_handoff_routes WHERE active;
SELECT count(*) AS contact_queue_size FROM ws4_private.contact_alert_outbox;
SELECT status,count(*) FROM ws4_private.contact_alert_outbox GROUP BY status ORDER BY status;
SELECT status,count(*) FROM ws4_private.push_outbox GROUP BY status ORDER BY status;
ROLLBACK;
```

Before a Testing rollout, use separate signed-in patient, dispatcher, supervisor, medic and receiver sessions with synthetic data. Check success and cross-account/organisation denial for every new RPC, duplicate intake operation and duplicate alerts, callback number access, claim revocation, voice timeout and two-device audio, contact opt-in, notification receipt semantics, unit/location freshness and patient-facing fallback. Do not call a real emergency number during testing. The current isolated PostgreSQL runner is `test/backend/ws4/run_dev1_patient_comms_tests.py`; it does not verify hosted Auth/PostgREST, the current shared catalog, manual operation or delivery.
