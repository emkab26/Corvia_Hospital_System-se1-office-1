# Isolated WS4 development core

This directory is a **fresh-project bootstrap for synthetic WS4 database testing**.
It is not a shared Corvia migration, hospital-system clone, Fleet implementation,
ER24 adapter or operational emergency system. Do not place it in an automatically
deployed migrations folder. The legacy batch17/18 scripts were removed by the
Eugene merge; their historical provenance is recorded below.

Intended hosted target: Jandre's `corvia-ws4-dev`, reference
`lejaaweexxspjlmlrtfc`, Frankfurt (`eu-central-1`), in his Free organisation.
Use no real patient data. Project identity is not a secret; database passwords and
privileged keys must never be placed here, in Flutter, reports or Obsidian.

## What this checkpoint implements

`001_secure_core.sql` installs only profiles, incidents, private synthetic scope/
membership/routing, private append-only client audit, and these public functions:

- `corvia_is_dispatch_operator()` consults server-managed membership plus explicit
  active profile state. Editing a profile role cannot grant dispatch authority.
- `corvia_dispatch_access_context()` returns the authenticated user, active scopes,
  roles, read/claim capabilities, policy version `ws4-dev-core-1` and server time.
  It denies absent/inactive/revoked membership, including when a queue is empty.
  This is a development contract; there is no new Flutter caller in this checkpoint.
- `corvia_dispatch_accept_incident(p_incident_id bigint)` retains the batch18
  response's eight keys, typed errors, row locking and same-owner retry. It adds
  scope checking, locked authority checks, a version increment and one claim event
  in the same transaction. A retry performs no second update/event. Claimant access
  is checked again before retry results are returned.

Patients retain own-profile insert/upsert/edit and the existing incident insert
and conditional cancellation shapes. The database also rejects an unconditional
cancellation after claim. Profile `role`, `user_type`, `is_active`, identity and
creation time cannot be changed by a client. Initial self-registration is patient
only. Dispatcher display roles are set by the owner; membership grants authority.
New self-registered patients are active, but cannot create incidents until the
owner explicitly provisions their **synthetic** route. No catch-all route exists.

Private organisation, membership and patient-route tables are test environment
authority, not accepted WS5 identities. Production routing/coverage and provider
handoff must still be agreed. Never name a synthetic organisation ER24 or imply
ER24 received/accepted a case. No resources, crew or acknowledgements are created.

The owner (`postgres`) provisions membership and activation through reviewed SQL;
no client-callable administrative RPC or profile-to-membership bootstrap exists.
`service_role` is intentionally not granted this development API surface. Private
tables have RLS and no client grants. Public tables use explicit least-purpose
grants and RLS. Private helper execution is allowed only where the policies/trigger
need it. Triggers that distinguish the database owner use SECURITY INVOKER;
SECURITY DEFINER functions use an empty search path and qualified object names.

All incident mutations produce a private audit event with actor, previous/new
status, version and server time; no message, coordinates or credentials are copied
into events. Clients cannot edit/read this private audit table. It is not a usable
UI timeline or a complete access/export audit or retention policy.

## Compatibility and deliberate limitations

Source contracts: `lib/services/emergency_dispatch_service.dart`,
`lib/services/patient_incident_service.dart`,
`lib/services/dispatch_call_controller.dart`. Historical SQL contracts are available
at commit `a89824d1af98d60048daca7ffe2e4fd20d1105cb` under
`Documentation/batch17_dispatch_incoming_emergencies.sql` and
`Documentation/batch18_dispatch_accept_emergency.sql`; they are no longer current
checkout files. They are provenance, not a current shared-backend migration. Do
not replay batch17: its replacement `profiles_role_check` omits laboratory roles,
and its broad incident policies do not provide this core's scope protection.

Legacy status vocabulary remains pending/in_progress/resolved/cancelled. Client
commands here are limited to create, claim and cancel an unclaimed incident.
Operational completion/resolution requires the next agreed lifecycle command;
there is no client arbitrary-status write or invented clinical completion rule.

`profiles.user_id` references Auth; `profiles.id` is a separate UUID. Incidents
remain bigint. The minimal profile supports the patient fields from the supplied
catalog, but intentionally restricts user types to patient and roles to this WS4
test surface. **Do not apply it to existing multi-role profiles.**

The full app cannot be certified against this core alone. AuthGate/AccountModeService
and signup also use patient/staff/module relations or RPCs which are not installed
here. Calls, ICE, chat, storage, Realtime publication, Fleet, Paramedic, maps and
hospital functionality are not installed or simulated. No existing configuration
is redirected to this project. Flutter's `testing` configuration may later select
this hosted development origin with an exact expected-origin match; the label
does not make this the team's Testing backend.

Patient activation does not yet have an operation-ID retry contract. Claim retry
is the legacy same-owner/same-incident contract. Audit insertion is atomic, but
there is no generic operation-result store, notification outbox or worker here.
These remain release requirements where the full WS4 plan calls for them.

## Install and verify

1. Run the local suite below and review the exact SQL and SHA-256 from its result.
2. Verify the dashboard target reference above, Free plan, Data API enabled,
   automatic table exposure disabled and automatic RLS enabled. Do not change
   a paid plan or any shared Corvia project. Review exposed schemas; do not add
   `ws4_dev_private` to the API.
3. Obtain action-time confirmation for the exact hosted install and its API
   permissions. Run only `001_secure_core.sql` as the project database owner.
   Never run the vulnerable `test/backend/ws4/baseline/catalog.sql` in Supabase.
4. The install is transactional. It refuses existing public application tables,
   views, `corvia_*` functions, or its private schema. Do not remove that guard to
   force an install. Investigate any conflict instead. Failure rolls back changes.
5. Run `verify_core.sql` and retain its non-secret metadata result. Verify actual
   grants/RLS/function owners and search paths, not just a success notification.
6. Provision isolated synthetic Auth identities using supported Supabase Auth,
   then owner-managed profiles, two synthetic organisations, scoped memberships
   and patient routes. Do not insert hand-crafted Auth rows in the hosted project.
   SQL test fixture IDs are not real Auth accounts and must not be uploaded.
7. Test real signed-in Auth/API allow/deny, claim races, revocation and cancellation.
   SQL role simulation is not a substitute for these hosted checks. Verify app
   prerequisites before attempting a full UI login or claiming end-to-end success.

The bootstrap is one-shot. A second run refuses rather than resetting data.
For a failed transaction no rollback script is needed. After successful install,
stop writes and review a forward repair; any destructive reset of the synthetic
environment needs separate authorization. Never roll back to vulnerable grants.

## Local verification

For the subsequent real Auth/API checkpoint, follow
[HOSTED_API_TESTS.md](HOSTED_API_TESTS.md). Its offline tests verify the runner and
generated provisioning SQL; they do not establish hosted API success.

From the repository root, with Python and an existing PostgreSQL 15 runtime:

```powershell
python test/backend/ws4/run_secure_dev_tests.py --pg-bin $env:CORVIA_PG_BIN
```

The runner creates a new cluster under ignored `build/ws4-secure-db/`, uses a
random loopback port/password, tests the exact bootstrap and stops the server in
`finally`. It accepts no connection URL or existing data directory. It reuses the
baseline runner's isolated lifecycle without altering the vulnerable fixture or
its original regression tests. Test Auth is a UID stub, not a token verifier.
It tests against hostile default grants as well as RLS and observes genuine
PostgreSQL lock waits between independent sessions for concurrency assertions.

Result JSON contains the SQL hash, runtime, checks and shutdown result. Full
Flutter regression/static/build verification is reported separately. Neither
local SQL tests nor a compiled app establish operational/legal approval.

Design references checked 7 October 2026:
[Supabase function security](https://supabase.com/docs/guides/database/functions),
[RLS](https://supabase.com/docs/guides/database/postgres/row-level-security),
[explicit API grants](https://supabase.com/docs/guides/api/securing-your-api).

## Client access checkpoint (7 October 2026)

The dispatch dashboard now requires `corvia_dispatch_access_context()` with the
validated `ws4-dev-core-1` contract. It checks access before and after queue reads
and immediately before claims. Profile roles remain entry hints; server membership
controls supervisor presentation and the explicit capability controls claiming.
A missing function or untrusted response closes dispatch access with a safe error;
it must not fall back to profile authority. Other hospital routes are unaffected.

This function is confirmed only in this isolated bootstrap. Shared rollout needs
a reviewed equivalent authority contract and compatible policy version first.
Do not install this fresh-project bootstrap on the shared hospital database.

Queue checks and pre-claim checks have a 15-second client wait bound. A sent claim
also has a 15-second UI deadline; expiry means outcome unknown, not rollback.
Refresh reconciles state before any further action. Late results cannot replace a
new snapshot; account changes prevent exposing an old actor's response. These are
UI bounds, not clinical response targets or remote cancellation guarantees.

Access is rechecked on refresh/polling, not pushed instantly to the client. RLS
and the claim transaction remain authoritative regardless of displayed UI state.
See `test/ws4_dispatch_access_context_test.dart`, service foundation tests and
the actual dashboard lifecycle tests for negative and race coverage.

## Explicit patient intake checkpoint (7 October 2026)

The additive [patient intake contract](PATIENT_INTAKE.md) and
`002_patient_intake.sql` extend this owned synthetic core. They support deliberate
submission, optional location/address/details, durable same-operation retries and
patient status recovery. The actual enabled patient route now uses this flow;
dispatcher details are capability-gated so the original core projection remains
compatible. Default phone-first behavior is retained until the selected backend
has the new migration and passes authenticated integration tests.

The delta is locally tested, not installed on any hosted backend by committing
these files. It does not itself complete cancellation/timeline controls, Fleet, Paramedic,
communications, ER24 integration or production readiness. Do not replay bootstrap
001 as an upgrade. Refer to the contract for exact arguments and safe deployment
boundaries.

## Cancellation and history checkpoint (7 October 2026)

The additive [cancellation and history contract](CANCEL_AND_HISTORY.md) and
`003_cancel_and_history.sql` follow 002. Patients explicitly confirm cancellation
of an unclaimed pending request; version checks and a persisted cancellation
identity prevent competing claims or repeated attempts from duplicating effects.
Unknown outcomes require status recovery. Patient and dispatcher screens display
only saved audit events, with authority checks and safe account-change handling.

Local verification: 689 Flutter tests and 87 database checks passed, including
14 observed lock-contention races. These files have not installed 002 or 003 on
a hosted backend. Real Auth/API integration and manual multi-session checks remain.
The default phone-first build and stopped-app state are unchanged.

## Operations and shared-schema upgrade checkpoint (7 October 2026)

`004_dispatch_operations.sql` adds reasoned operational commands, internal notes,
priority, patient cancellation requests after claim, private patient/dispatch
messages, scoped patient callback details and owner-enabled provider simulation.
It fixes the audit trigger so ordinary operational updates do not become claims.
Provider simulation remains off by default and never calls ER24.

For an existing shared Corvia backend, use the separately guarded and rehearsed
[shared upgrade package](../ws4_release/README.md), not this fresh bootstrap.
That package preserves existing data and requires current-schema/owner review,
explicit membership/routing setup and authenticated integration verification.
Neither a shared nor hosted database was changed by adding these files.

## Response workflow checkpoint (8 October 2026)

`005_response_workflow.sql` follows 004 and adds the real unit/crew reservation,
independent readiness review, acknowledgement, response milestones, scoped team
messages, exceptions and hospital receipt. It reads canonical `public.hospitals`
without creating a competing directory. It requires reviewed owner provisioning
of organisations, crews, verification/shift times, reviewers and receiving staff.
Only synthetic credentials/records are appropriate on this development path.

See [the response implementation and demo runbook](../ws4_release/RESPONSE_WORKFLOW.md)
for exact files, lifecycle, negative tests and what remains unverified. Generate
one-time synthetic setup SQL with `tools/build_ws4_response_demo.py`; it does not
execute SQL, create accounts, grant real clinical qualifications or mark units ready.
Never apply that synthetic provisioning script or this fresh core to shared data.
