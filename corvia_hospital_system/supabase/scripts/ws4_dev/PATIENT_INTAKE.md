# Synthetic patient intake contract

`002_patient_intake.sql` is an additive development delta for Jandre's owned
`corvia-ws4-dev` project (`lejaaweexxspjlmlrtfc`) after `001_secure_core.sql`.
It is **not installed by adding this file**, not a shared Corvia migration, and
does not integrate Fleet, Paramedic, ER24, chat or clinical triage. Use synthetic
data only. Never run the bootstrap again as an upgrade.

## Activation and recovery

Activation is an explicit patient action. Opening a page, collecting GPS or
starting the phone dialler must not invoke the request RPC automatically.

`corvia_patient_request_emergency` takes all seven named arguments:

| Argument | SQL type | Rule |
| --- | --- | --- |
| `p_operation_id` | UUID | Required, nonzero, stable for this request and retries. |
| `p_latitude` / `p_longitude` | double precision | Both absent, or both finite and in geographic range. |
| `p_location_accuracy` | double precision | Required with coordinates, finite and nonnegative; otherwise null. |
| `p_location_captured_at` | timestamp with time zone | Required with coordinates; preserve the actual capture instant. Otherwise null. |
| `p_address` | text | Optional; trim, normalize empty to null; at most 300 characters. |
| `p_details` | text | Optional; trim, normalize empty to null; at most 1,000 characters. |

The server derives `location_source`: `gps` when a complete fix is supplied,
`manual` when only an address is supplied, or `unavailable` without either. GPS
is optional. Never substitute `(0,0)` or a fresh timestamp for failed collection.
A genuine fix at `(0,0)` remains a valid coordinate; its metadata is required.
For a **new** GPS request, capture age must be no more than 120 seconds and no
more than 30 seconds in the future. These are technical demo validation settings,
not clinical response standards. An exact retry after the fix ages remains valid
and retains the original captured time.

The operation identity is `(authenticated user, operation UUID)`. The server
fingerprints the canonical supplied payload; the same identity and payload
returns the existing incident's **current** state without another incident or
event. Different data with an already-used identity fails with SQLSTATE `22023`.
Retrying must not collect a replacement GPS fix or silently change details.
The database locks and rechecks active patient profile and routing authority on
each request and replay. Route deletion/change or deactivation denies recovery
of a former scope with `42501`; the client must not treat that as a missing row.

`corvia_patient_request_status(p_operation_id uuid)` returns the current own
record, or JSON null when no committed own operation is found. A different
patient's operation is indistinguishable from missing. Lookup uses the same
operation lock and waits for an already executing request transaction. **Null
does not prove that a delayed original network request can never arrive.** Keep
the original identity during uncertain recovery and do not automatically create
a new operation. Persisting only the operation ID avoids storing emergency
details locally; after restart, recover from the server before allowing a new
request. Any safe retry needing the original payload must obtain/reconcile it
without inventing changed values under that ID.

The client stores only that opaque ID under the signed-in user's local settings.
This is retry protection for the **same operation**, not a global one-incident
policy: two devices or two newly opened tabs can create different operation IDs.
Do not describe this as preventing every duplicate emergency across devices.
Any one-active-request policy needs an explicit server rule and user recovery
flow; none is assumed in this delta.

## Response

Both RPCs return the same object when present:

```json
{
  "operation_id": "20000000-0000-4000-8000-000000000001",
  "incident_id": "102",
  "user_id": "00000000-0000-4000-8000-000000000001",
  "status": "pending",
  "version": "1",
  "created_at": "2026-10-07T12:00:00+00:00",
  "latitude": null,
  "longitude": null,
  "location_source": "manual",
  "location_accuracy": null,
  "location_captured_at": null,
  "address": "Synthetic entrance A",
  "details": "Synthetic demonstration only"
}
```

Incident ID and version are positive bigint **strings**, including on web.
Status uses the existing `pending`, `in_progress`, `resolved`, `cancelled`
vocabulary. Responses must match the current user and requested operation.
`pending` means Corvia recorded the incident, not that a dispatcher, crew or ER24
accepted it. The existing claim RPC keeps its eight-key legacy response.

| Outcome | Meaning |
| --- | --- |
| Valid request/replay | Authoritative current incident returned. |
| `22023` | Invalid input or changed payload under an existing operation. |
| `42501` | Inactive/non-patient/missing route, changed scope, or denied function. |
| Transport timeout | Outcome unknown; reconcile the original operation. |
| Missing function | This backend has not installed the contract; fail visibly. |
| Lookup JSON null | No committed own operation visible at this lookup; retain ambiguity if an earlier request remains in flight. |

## Database changes and compatibility

The migration checks the synthetic core marker and database owner, refuses repeat
installation/schema conflicts, and records `ws4-patient-intake-1` in a private RLS
table. It adds nullable paired coordinates, source/accuracy/capture metadata and
bounded address/details to `incidents`. Existing coordinates get source `legacy`
because their capture provenance is unknown. New RPC-created incidents never
use `legacy`. Old direct coordinate inserts still work with this label; their
existing column grants cannot write the new fields, route or dispatcher owner.

Private operation rows contain actor, operation UUID, SHA-256 payload fingerprint
and incident reference; they do not duplicate address/details. An advisory
transaction lock serializes the actor+operation key; its hash collision can only
serialize unrelated requests. The primary key and stored fingerprint remain the
identity checks. The incident insert, existing creation event and operation row
commit together. An audit failure or outer rollback preserves none of them.

Functions use security-definer owner execution, an empty search path, qualified
application objects and explicit authenticated-only public execution grants.
Anonymous and service-role execution, direct operation access and internal helper
execution are denied. Existing incident RLS, claim/cancellation rules and version
increment behavior remain in place. There is no generic lifecycle command here.

`corvia_dispatch_access_context()` retains policy `ws4-dev-core-1` and its original
authority checks, and additionally advertises `read_intake_details` after these
columns exist. The dispatcher client must request new fields only when that
capability is present. An unmodified core remains usable with its old projection.

## Local verification and later hosted application

Use the existing portable PostgreSQL 15 runtime; the runner always creates a fresh
loopback cluster and stops it in `finally`. It accepts no hosted URL or existing
database directory:

```powershell
python test/backend/ws4/run_patient_intake_tests.py --pg-bin $env:CORVIA_PG_BIN
```

Coverage includes migration guards, hostile default grants, ownership and routing,
location/text validation, same/changed-payload replay, aged GPS retry, string-ID
responses, current-state recovery, private helper denial, legacy contracts, audit
rollback and observed lock-contention races for duplicates, recovery, profile
deactivation and route edits. Result JSON records SQL hashes and server shutdown.
SQL role stubs do not establish real Supabase Auth/JWT/PostgREST success.

Verified locally on 7 October 2026 with PostgreSQL 15.19: **78 checks passed**,
including **7 observed lock-contention races**, and the test server stopped.
Recorded report: `build/ws4-patient-intake-db/f5198ab858914fd2b00e7e4c740c5989/result.json`.
Tested delta SHA-256: `69321548f02167133b716b16f091e421cf87d2849539d78ca27ebac1689fcdd6`.
This result is for the exact local SQL delta; hosted installation/API and real-app
verification remain separate work.

Before any hosted application: inspect the exact current schema/grants and target,
review the delta and local results, and apply only to the named owned synthetic
project under the applicable approval workflow. Then verify signed-in positive,
negative and concurrent API behavior and two real app sessions. Update evidence
with actual results; this document by itself claims neither deployment nor a
successful hosted test.

## Client entry and compatibility

With `CORVIA_EMERGENCY_DISPATCH_ENABLED=true`, the actual `EmergencyPage` now opens
`EmergencyIntakePage`. Opening, polling, location lookup and phone handoff do not
submit an incident. Patients may supply an address, brief details, a recorded GPS
fix, or no location. A deliberate submit stores the operation ID before calling
the RPC. A timeout is an unknown outcome; lookup precedes retry with the original
identity and frozen payload. Signing out or changing accounts clears protected
screen state and ignores late results. Only an explicitly chosen new request
after a confirmed terminal record clears the old operation reference.

The build flag remains false by default, retaining the independent phone-first
entry until migration and authenticated integration are verified. The previous
voice screen remains `LegacyDispatchEmergencyPage` for regression coverage; the
normal enabled route no longer invokes its automatic intake/call setup. This
checkpoint does not complete communications. The subsequent
[cancellation and history checkpoint](CANCEL_AND_HISTORY.md), using additive
migration 003, adds confirmed pending-request cancellation and persisted history
to this screen. Both migrations still require separate hosted verification.

Dispatchers query the new columns only with the server's `read_intake_details`
capability. The detail panel labels supplied text as patient-reported, describes
GPS as a recorded snapshot, and retains immutable details across the compatible
eight-key claim result only when incident, patient and coordinates match. A
capability change clears the old queue and details. Malformed intake is review-only.
Legacy numeric incident IDs beyond JavaScript's exact integer range are rejected
for actions; a future API projection must supply bigint strings throughout to
make those very large IDs operational. New patient RPCs already use strings.
