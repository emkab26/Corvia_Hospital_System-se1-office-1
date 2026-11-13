# Synthetic cancellation and incident history

`003_cancel_and_history.sql` is an additive development delta after
`001_secure_core.sql` and `002_patient_intake.sql`, for Jandre's owned synthetic
`corvia-ws4-dev` project (`lejaaweexxspjlmlrtfc`). Adding this file does not install
it. It is not a shared Corvia migration or a Fleet, Paramedic, ER24, communications
or clinical integration. Use synthetic data only; do not replay 001 or 002 as an
upgrade on an existing database.

## Patient cancellation

Cancellation requires an explicit patient confirmation. Opening a page, restoring
a request, refreshing history or starting a call must never cancel automatically.
`public.corvia_patient_cancel_emergency(p_operation_id uuid,
p_expected_version bigint)` uses the **existing intake operation UUID** and the
last confirmed incident version. Both arguments are required; the operation UUID
must be nonzero and the version positive. The server resolves the incident from
the authenticated patient's operation; the caller cannot supply another patient
or choose an incident independently.

The active patient profile and current route are locked using the 002 scope
helper. The command then takes the same actor/operation advisory lock as intake
and recovery, and locks the owned incident. Only an unclaimed `pending` incident
with the exact expected version may be cancelled. The private intake operation
row records `cancel_expected_version`; the incident becomes `cancelled`, its
version increases once, and the existing audit trigger records the actor, server
time, previous status and new status. All three writes commit together or roll
back together. There is no new generic command ledger, cancellation reason field,
or lifecycle framework.

An identical retry with the original expected version returns the current
cancelled record without another update, version increment or event. A changed
expected version under an already recorded cancellation is invalid identity
reuse. A cancellation made through the preserved legacy direct update has no
command ledger record, so this RPC returns a conflict; the existing status lookup
can recover the current cancelled state. A claimed or resolved request cannot be
cancelled through this command. This is a Corvia record change, not cancellation
of a telephone call, dispatched vehicle or external provider response.

The response is exactly the existing 002 thirteen-key patient object:
`operation_id`, `incident_id`, `user_id`, `status`, `version`, `created_at`,
`latitude`, `longitude`, `location_source`, `location_accuracy`,
`location_captured_at`, `address`, `details`. Incident ID and version remain
positive bigint **strings**, including on web. The client must validate the
actor, operation and incident against the request it is displaying.

| Outcome | Meaning and recovery |
| --- | --- |
| Success or identical recorded retry | Authoritative current cancelled record returned. |
| `22023` | Invalid arguments or changed expected version under a recorded cancellation. |
| `P0001` | Stale version, claimed/terminal incident, or legacy cancellation not recorded by this command. Refresh the original operation; do not overwrite a claim locally. |
| `42501` | Inactive/non-patient, absent route, changed scope, unknown/foreign operation or denied execution. Clear protected state. |
| Transport timeout | Outcome unknown. Preserve the original operation and expected version, then use `corvia_patient_request_status` to reconcile. |
| Missing RPC | Contract unavailable. Fail visibly; do not fall back silently to direct mutation. |

A confirmed terminal lookup establishes current state. A still-pending lookup
does not prove a delayed cancellation can never arrive; retain the cancellation
identity during uncertainty. Do not silently replace the expected version on a
retry. Existing create/lookup RPCs continue to return the current incident after
cancellation.

## Incident history

`public.corvia_incident_history(p_incident_id bigint)` returns only persisted
private audit events. Access requires an authenticated active profile and either
an owned incident with an active patient role and matching current route, or an
active membership in the incident's organisation. Missing incidents and denied
scope both fail with `42501`; denial is never represented as an empty timeline.
The profile, incident and applicable route/membership are locked and checked so
concurrent authority revocation is ordered against the read transaction.

```json
{
  "incident_id": "102",
  "events": [
    {
      "version": "1",
      "event_type": "created",
      "recorded_at": "2026-10-07T12:00:00+00:00",
      "status": "pending",
      "previous_status": null
    },
    {
      "version": "2",
      "event_type": "cancelled",
      "recorded_at": "2026-10-07T12:01:00+00:00",
      "status": "cancelled",
      "previous_status": "pending"
    }
  ]
}
```

Each event has exactly those five keys. Events are ordered by numeric version,
with ID/version serialized as strings and timestamps in UTC. Supported event
types are `created`, `claimed`, `cancelled`, `resolved`. A claim has status
`in_progress` and previous status `pending`; resolution has status `resolved`
and previous status `in_progress`. No actor UUID, patient details, coordinates,
address, organisation ID or contact information is exposed in the history object.
Audit rows and audit writes remain private.

The client accepts a complete chain beginning with creation at version 1, with
consecutive versions and each previous status matching the preceding event.
Missing, repeated or contradictory events produce an unavailable-history state;
they are never filled in from a client assumption.

The response supports at most **100 events**. The database checks up to 101 rows
and raises `P0001` on overflow rather than silently truncating. An incident with
no persisted audit rows also fails `P0001`; the API does not invent a creation
event from the incident's current state. This projection does not manufacture
dispatch, communication, transport or provider events that do not exist.

## Compatibility and scope

The owner-only migration requires both synthetic installation markers, refuses
repeat installation or conflicting objects, and records private marker
`ws4-cancel-and-history-1`. Its only operation-row addition is nullable positive
`cancel_expected_version`. Public functions use security-definer execution with
an empty search path; new execution grants are revoked from `PUBLIC`, `anon`,
`service_role` and hosting defaults, then granted only to `authenticated`.

The existing 001 claim RPC, column-level legacy insert/cancel grants, 002 intake
RPCs, RLS policies and event trigger remain unchanged. Dispatch access context
keeps policy `ws4-dev-core-1` and tokens `read_incidents`, `claim_incident`,
`read_intake_details`, adding `read_incident_history`. Clients must gate dispatch
history on that capability and clear history when authority or capability changes.
The delta does not broaden event-trigger semantics for future owner/admin edits;
any wider lifecycle commands and corresponding audit rules need a separate design.

## Local verification and hosted boundary

Run with the existing portable PostgreSQL 15 runtime:

```powershell
python test/backend/ws4/run_cancel_and_history_tests.py --pg-bin $env:CORVIA_PG_BIN
```

The runner reuses the existing loopback-only harness and creates a fresh cluster;
it accepts neither a hosted URL nor an existing data directory, and stops the
server in `finally`. Reports under `build/ws4-cancel-history-db/<run>/result.json`
record SQL hashes, outcomes, observed lock waits, PostgreSQL version and shutdown.
Coverage includes install/grant/authority denial, unchanged response shapes,
redacted stored events, ordering, UTC and large bigint strings, stale and claimed
conflicts, exact/changed-version retry, legacy recovery, event bounds, audit and
outer rollback, cancel-versus-claim in both lock orders, parallel cancellation,
history following a committed cancellation, and profile/route/membership races.
The bound tests use explicitly synthetic private audit fixtures in rolled-back
transactions; they do not establish a new valid lifecycle transition.

Local SQL role stubs do not verify real Supabase Auth/JWT/PostgREST, hosted
installation, app integration, deployment or production readiness. Before hosted
application, inspect the exact owned synthetic target and current schema/grants,
review this delta and its actual local report, and follow the applicable approval
workflow. Hosted positive/negative/concurrent API and real-session verification
remain separate evidence. This document does not claim those checks passed.

Verified locally on 7 October 2026: **87 checks passed**, including **14 observed
lock-contention races**, on PostgreSQL 15.19. The temporary server stopped.
Report: `build/ws4-cancel-history-db/81ca5547b202420b853f788aa99df1f0/result.json`.
Migration 003 SHA-256:
`fabd2ef508b39bf414a9441c06a49e242e5b0a7a66d5414c6f87379ce86a921d`.
The full Flutter suite passes **689 tests**, covering cancellation confirmation,
conflicting claims, unknown outcomes, exact response validation, saved history,
account changes and late-result rejection as well as existing regressions.
Neither migration 002 nor 003 was applied to a hosted backend for this checkpoint.
