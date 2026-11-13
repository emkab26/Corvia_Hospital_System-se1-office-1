# WS4 shared-backend rollout and demo handoff

## 10 October team Fleet/Paramedic handoff

The current Testing code has a separate Fleet/Paramedic incident model. WS4 uses
`public.incidents.id`; the team uses
`public.corvia_ws6_incidents_actual.incident_id`. Their unit and crew IDs also
belong to separate models. Do not copy IDs between them or allocate a unit in
both systems. The additive
[`002_team_ems_handoff.sql`](002_team_ems_handoff.sql) creates a durable link and
uses the team's `corvia_ems_command` to create its incident. Team Fleet/Paramedic
then owns allocation and clinical progression; WS4 retains patient intake,
dispatch claim, messages and patient-facing closure. The linked EMS case must
reach a matching terminal state before WS4 can close. This is a Corvia team
integration, not an ER24 connection.

On an **isolated, backed-up target** the database owner first checks that the
reviewed WS4 `001_shared_upgrade.sql` and team workstream scripts
`11_install_fleet_paramedic.sql` and `13_dispatch_fleet_upgrade.sql` are
installed in that order. The owner then reviews and installs
`002_team_ems_handoff.sql` once. It creates no routes or accounts. The owner
then reviews and installs `003_team_ems_completion.sql` and
`004_team_backup_receiver.sql` in that order. The former prevents a second provider response after
team handoff and adds the WS4 close RPC needed to show a team-confirmed
cancellation as cancelled to the patient. The latter reserves one separately
acknowledged backup crew alongside the team's primary assignment and requires a
different, owner-mapped receiving user to confirm linked handovers. Install both
before enabling the team handoff build flag; that build uses their RPCs.

**11 October completion candidate:** after 004, the owner reviews and installs
`005_team_operational_completion.sql` on the same isolated, backed-up target.
It adds linked-case primary/backup acknowledgement deadlines, a repeat-safe
overdue audit worker, backup-to-dispatch messages and explicit reads, callback
outcomes, destination selection, exception review, patient-match and receiving
guards, and safe resource release. The enabled build now calls these RPCs, so
install 005 before deploying that build. Where `pg_cron` is already available,
the owner may review and run `005_team_deadline_schedule.sql` to call the worker
every minute. Otherwise an owner-operated scheduler must call
`corvia_ws4_team_deadline_scan()` with service authority; the UI still computes
overdue state from server timestamps, but autonomous overdue audit records will
not appear until a scheduler runs. Do not install either script on a shared
backend until its current schema, memberships, real receiving directory and
restore path have been checked. Neither script contacts ER24.

For each approved WS4 organisation, the owner explicitly maps its real
`ws4_private.organisations.id` to the correct `public.hospitals.id` in
`ws4_private.ems_handoff_routes`, with `active=false` until existing WS4
assignments are cleared and the two memberships are verified. Only then set
`active=true`. A dispatcher needs active WS4 organisation membership and active
team `corvia_ops_memberships` for that hospital. Never guess this mapping or
enable it globally. The app build must use
`CORVIA_EMERGENCY_DISPATCH_ENABLED=true` and, **only after the bridge is
installed and verified**, `CORVIA_WS4_TEAM_EMS_HANDOFF_ENABLED=true`. The latter
defaults to false so a code rollout before the database change retains existing
WS4 response behavior.

Before using receiving confirmation, the owner maps each authorized existing
Auth user and actual team receiving-facility ID in
`ws4_private.ems_receivers`, with `active=false` until the person's scope is
reviewed. Set only reviewed synthetic/demo memberships active. The medic who
created a handover cannot confirm their own receipt. Installation refuses
previously acknowledged linked handovers until the owner reviews them; it never
fabricates independent evidence. Backup crew must have the team's current,
verified shift, vehicle and readiness records. The backup is kept in
`ws4_private.ems_backups` because the team's clinical assignment command supports
one primary crew. The backup medic acknowledges or declines the offer and can
record en route and on scene; the primary crew remains responsible for the
patient's clinical status sequence. Dispatch must
release an active backup with a reason before team closure. The released vehicle
needs another readiness review before reuse.

Manual acceptance with synthetic accounts: submit a patient request; claim it
as a dual-member dispatcher; choose priority and minimum capability; create a
linked EMS incident; verify exactly one team incident and link; use team Fleet
to claim and assign a genuinely ready unit/eligible crew; progress and close
there; then close the WS4 case with a reason. Confirm the patient sees only WS4
status and no internal team records. Retry the same handoff after a deliberately
lost response and check that no duplicate is created. Test a dispatcher without
team membership, another organisation, a patient, an unconfigured route,
stale/revoked membership and attempted early WS4 closure. Verify that a routed
organisation cannot create a parallel WS4 response assignment or provider demo.
Separately cancel a linked team case through its supervisor command, then close
WS4 and confirm the patient sees cancelled. Check that a repeated close operation
returns the same receipt. Do not use a real emergency number for testing.
Also record a backup request in the team incident, offer an eligible second crew,
confirm that primary and backup remain reserved, acknowledge with the backup
medic account, deny an unrelated account, and release before closure. Record a
handover with the primary medic, confirm it from a different mapped receiving
account, and verify medic self-confirmation and revoked receiver access are
denied. The receiving inbox and backup crew inbox are in Settings when the team
flag is enabled; dispatch opens backup controls from the linked response panel.

For 005, additionally test primary and backup offers past their deadline, repeat
the worker scan without duplicate alerts, send/read backup messages across two
accounts, record an observed callback result, reject transport without a matched
patient or selected active receiving facility, reroute a failed handover, and
close a no-patient/refusal case only after independent supervisor review. Check
that released units need fresh readiness review. Use synthetic data and verify
the actual receiving facility IDs and location freshness; directory entries do
not prove capacity or acceptance.

Local combined PostgreSQL rehearsal:
`py -3 test/backend/ws4/run_team_ems_bridge_tests.py --pg-bin <PostgreSQL-bin>`.
It does not verify the current hosted schema, Supabase Auth/PostgREST,
multi-device operation, a real EMS service or regulatory approval. The bridge
must be installed and manually tested on the intended backend before enabling
the flag or treating the demo as accepted.

This package targets an **existing Corvia database**. It is an upgrade candidate
rehearsed against the selected schema and legacy trigger/policy definitions from
the supplied 5 October export. It is not proof of the current deployed schema,
successful Auth/PostgREST integration, operational approval or live readiness.
Do not apply the fresh `ws4_dev/001_secure_core.sql` bootstrap to the shared database.

## What now works in code

**8 October response update:** the connected unit/crew workflow, independent
readiness review, exclusive reservation, acknowledgement, milestones, exceptions,
team messages and receiving-hospital confirmation are implemented. Read
[RESPONSE_WORKFLOW.md](RESPONSE_WORKFLOW.md) for the current source-file map,
WS5/WS6 dependency boundary, setup and full manual acceptance matrix. Local SQL
and Flutter verification do not establish hosted deployment or final demo acceptance.

The actual enabled emergency route supports explicit patient intake, optional
location/address/details, same-operation recovery, pending cancellation, and a
request for dispatch to review cancellation after acceptance. Dispatchers can
claim, set priority, record internal notes, exchange patient messages and close
with a reason. The server restricts management to the incident owner or a
supervisor in that incident's organisation. Patient views cannot read internal notes.
The owner/scoped supervisor can also open the device phone app with the patient's
supplied callback number; no call is started automatically and no number is guessed.

Messages use server-assigned senders and idempotent receipts. “Saved to Corvia”
means server persistence, not a read receipt. Reads page 50 messages at a time;
the app refreshes every 15 seconds or manually. Unknown mutation outcomes retain
the exact action identity/payload within the open panel; refreshing never resends.
Closing/reloading the panel discards its in-memory draft/uncertain operation, so
check saved state before composing a new message. No sensitive draft is written
to local preferences. Durable encrypted offline messaging is not implemented.

History records genuine events. A note/priority update is no longer incorrectly
recorded as a new claim. The history API currently rejects incomplete or over-100
event histories; it does not silently invent or truncate a timeline. Recent
internal actions show the latest 50; older commands remain in the private ledger.

The recorded incident location can be opened explicitly in OpenStreetMap. There
are no fake moving ambulances or invented hospital availability. Emergency calling
is visible before sign-in and while startup is waiting or fails. Native installed
app behavior still needs device testing; a browser that has never cached the app
cannot download it for the first time without internet.

## Apply safely to the intended backend

1. The backend owner runs `preflight.sql` on the exact target project and reviews
   the returned metadata against this package. It exports no patient rows or keys.
   Confirm a backup/restore path and rehearse the full current schema first.
2. Resolve incompatible columns/triggers, invalid legacy incident rows and unsafe
   callable registration functions before rollout. The SQL refuses known conflicts
   and does not silently repair or delete old records. Review the old voice/ICE and
   legacy `incident_messages` policies separately: new messages use private storage,
   but this upgrade does not certify or repair every legacy communications table.
3. Review the explicit compatibility changes below. In the same SQL-editor request,
   prepend `SET corvia.ws4_shared_review = 'approved';` to the complete generated
   `001_shared_upgrade.sql`, then execute as the database owner. This flag records
   an intentional owner decision; it is not a substitute for review or permission.
   Do not set it merely to bypass a failed preflight. The package runs in one
   transaction and refuses reapplication. It has not been applied by this work.
4. Provision the agreed organisation IDs, active dispatcher/supervisor memberships
   and patient routes in `ws4_private.organisations`, `memberships` and
   `patient_routes` using actual Auth UUIDs. No organisation, account, role or route
   is guessed or automatically assigned. WS5's final identifier mapping still
   requires agreement. Existing incidents retain null routing until separately
   reviewed; no historical audit events are fabricated for them.
5. Test through normal signed-in patient/dispatcher/supervisor JWTs, including a
   different organisation, inactive user and revoked membership. Only then build
   with the target's public configuration and
   `CORVIA_EMERGENCY_DISPATCH_ENABLED=true`. An owner/service key must never be
   embedded in Flutter. Keep demo fixtures synthetic and identify them explicitly.

For the already bootstrapped owned development project, use additive 002, 003,
004 and 005 in order after inspecting which are installed. The shared upgrade is a
different path and refuses an already extended incident schema. Neither path
requires maintaining Jandre's local database. Disposable local test clusters are
verification fixtures, not an application dependency.

## Compatibility changes the backend owner must approve

| Area | Intended change |
| --- | --- |
| Existing data | Existing profile and incident rows/IDs are preserved; no reset, automatic migration of clinical data or fabricated audit backfill. Invalid old statuses/location require explicit prior review. |
| Roles | Flutter profile roles remain navigation hints. New incident authority uses owner-managed memberships/routes. The profile trigger blocks direct self-promotion/reactivation and other users' direct profile edits. Check legitimate staff/admin signup and profile workflows against the full current schema. |
| Incident policies | A restrictive scope policy prevents old permissive policies from granting cross-organisation access. Table and column grants are narrowed; old arbitrary incident writers may now fail intentionally. |
| Existing functions | Dispatch access/claim helpers are replaced with the reviewed contracts and owner. The eight-key legacy claim response remains; newly introduced APIs return bigint IDs/versions as strings. |
| Legacy rows | Unmapped incidents are not automatically visible to dispatch. Old patients can retain authorized own-row access, but their old requests do not acquire a fabricated intake operation or timeline. Plan a separate reviewed routing/archive decision. |
| Audit and operations | State/version/event/operation receipt commit atomically. Any ledger failure rolls the command back. New private tables have no client direct grants. |
| Fleet | New private response assignments have explicit reservation/release and independently reviewed readiness. Active response assignments block closure. Legacy `incident_responder_assignments` still block closure because their completion semantics remain unverified. |
| Demo provider | Disabled by default; no HTTP request, credentials, real ER24 records or emergency calls are created. See `PROVIDER_CONTRACT.md`. |

The private schema is `ws4_private` on the shared upgrade. The legacy policy token
`ws4-dev-core-1` is retained for wire compatibility; it is a version identifier,
not proof that a backend is a test environment. Installation markers on this path
explicitly record `synthetic_only=false`.

Security design references: explicit function privileges and fixed search paths
follow [Supabase function guidance](https://supabase.com/docs/guides/database/functions);
the restrictive policy is used alongside existing policies according to
[Supabase RLS guidance](https://supabase.com/docs/guides/database/postgres/row-level-security).

## Demo and manual checks

Use separate patient and dispatcher browser profiles; include a second dispatcher,
a supervisor, an unrelated patient and another organisation for negative checks.

| Step | Expected evidence |
| --- | --- |
| Open without login; delay startup | Emergency number remains available. No incident or call starts automatically. |
| Submit synthetic request with and without GPS | One saved request for its operation; correct address/provenance; no invented coordinates. |
| Claim from two dispatcher sessions | One owner; losing session refreshes; one claim event. |
| Set priority and add an internal note | Version increments; history says update, not another claim. Patient cannot see the note. |
| Exchange messages and load older messages | Correct server sender, persisted once per operation, no claims about read/delivery receipts. Unrelated accounts denied. |
| Drop a mutation response | Unknown result is visible; saved-state refresh does not mutate; explicit same-action retry does not duplicate. |
| Request cancellation after claim | Dispatch sees the request; no automatic terminal transition or external cancellation. |
| Enable a synthetic provider demo on an isolated/demo-approved backend | Test accepted, rejected, unavailable and unknown on separate incidents. Unknown blocks another provider request and closure; reconciliation uses the existing request. |
| Finish provider demo and close | Explicit recorded reason; genuine resolution event; patient and dispatcher refresh to the same status. Any real Fleet assignment blocks unsupported closure. |
| Revoke membership/change account | Protected messages/details clear; stale callbacks and retries cannot restore access. |
| Direct call fallback | Check a harmless test-number handoff or inspect the dialler and cancel. Never place an emergency call as a test. |

## Still outside the verified completion boundary

The WS4 response dependency layer is implemented and locally tested; unpublished
WS5/WS6 implementations still need comparison when received. Normal Supabase Auth,
the deployed schema and multi-session/device rehearsal remain unverified. Full
Fleet/clinical-documentation products, in-app voice and a real ER24 adapter are
outside this demo implementation. Owner-managed synthetic credentials/readiness
must never be represented as real clinical verification. The remote fetch on
8 October succeeded and found no newer Testing/Eugene baseline.

Generate this package with `python tools/build_ws4_shared_upgrade.py`. Verify with
`test/backend/ws4/run_shared_upgrade_tests.py`, `run_dispatch_operations_tests.py`
and `run_response_workflow_tests.py`
using the existing portable PostgreSQL `--pg-bin` path. The generated SQL must
match the builder output before review or deployment.
