# WS4 Developer 1 patient and communications checkpoint — 12 October 2026

## Shared backend compatibility finding (12 October)

The current `001_shared_upgrade.sql` must not be installed on coastit yet.
Its new `ws4_private.guard_profile()` trigger rejects profile writes whenever
`current_user` is not `postgres`. Read-only inspection of the live catalog
confirmed seven existing hospital/laboratory administration RPCs that update
`public.profiles` and run as `SECURITY DEFINER` under `supabase_admin`.
The trigger would therefore reject their legitimate role updates. The live
`block_user_type_change()` trigger independently rejects changes to
`user_type`; staff-link paths that change that field need their own baseline
compatibility check. No shared migration or account change was applied.

A compatible profile-authority design must be tested with the current patient
registration upsert, ordinary profile editing, the live staff/lab RPCs, and
direct patient self-promotion denial. Do not replace the guard with a blanket
`supabase_admin` exemption. The migration also changes direct incident
permissions; legacy incident readers/writers, the nine existing incidents,
and any consumer of `register_auth_user_temp(text,text)` need review before
installation. The target still needs a verified restore path, explicit
patient routes and dispatcher memberships, and team EMS memberships/crews
before the linked response demo can run.

Branch: `feature/ws4-patient-comms`, created from `origin/Testing` at `9bc88cc`. This checkpoint is uncommitted and has **not** been pushed or installed on the shared backend.

## Implemented and locally verified

- Patient Settings hides the staff-workspace navigation in patient mode. Other staff views keep their existing Settings behavior.
- Emergency contacts are partitioned by account on the current device while the remote gate is off. The old unowned `emergency_contacts` key is deliberately not imported. With 010 installed and `CORVIA_WS4_CONTACTS_ENABLED=true`, contacts are server scoped, editable across devices, and individually opt in to alerts. One durable alert is queued per opted-in contact per confirmed incident. Queued, provider accepted, delivered and failed are distinct patient-visible states. No provider worker is installed, so an alert is not sent merely by being queued.
- Nearby services accepts manually entered coordinates when device location is unavailable; it validates the range, rejects stale async results, and bounds location and directory waits. Directory data is advisory, not confirmed service availability.
- The patient intake view can show a coarse linked-EMS progress projection when `CORVIA_WS4_TEAM_EMS_HANDOFF_ENABLED=true` and the new `006_patient_progress.sql` is installed. Only the owning active patient receives stage and a unit location no older than five minutes; no crew identity or clinical record is returned. An unavailable response clears the prior projection.
- The patient can deliberately start an in-app WebRTC voice call after an incident is confirmed **only** when `CORVIA_WS4_VOICE_ENABLED=true` and `007_incident_voice.sql` plus Developer 2's responder UI are installed. Voice start, answer, exchange, ICE and end use dedicated scoped RPCs. Ending voice never closes an incident. The old `public.call_sessions` and `public.call_ice_candidates` are not used by this path.
- Microphone denial now releases incomplete local call state, so a retry requests the microphone again without starting a server call. A completed offer retains its operation ID after an uncertain server response to avoid duplicate starts.
- The caller can mute/unmute its local microphone track without closing the incident. A two-device call and TURN/network-loss behavior still require a manual test.
- With 008 installed and `CORVIA_WS4_REQUESTER_IDENTITY_ENABLED=true`, in-scope dispatch sees the account holder's minimum-field name; the UI says “Name unavailable” if the name is absent or access fails. This is labeled requester, never casualty. With 009 installed and `CORVIA_WS4_CALLBACK_ENABLED=true`, the patient may provide a validated optional callback number; only the current claimed dispatcher can fetch it.
- 011 defines a provider-neutral generic push outbox and account-scoped device registration/revocation RPCs. `Ws4PushSubscriptionService` is the client contract. A platform token source and worker are not yet connected, so device-wide push does not occur.

## Installation and Developer 2 contract

Update for this branch: `lib/widgets/dispatcher_voice_panel.dart` and
`lib/controllers/dispatcher_voice_controller.dart` now provide a dispatcher
responder UI candidate. The Developer 2 instructions below describe the
original contract, not an outstanding coding assignment. Two-device audio,
claim revocation and network behaviour still require manual verification.

On a backed-up isolated target, install reviewed WS4 `001` through `005` and team EMS migrations first. Review and install `006_patient_progress.sql` through `011_patient_push_outbox.sql` in numeric order. None provisions routes, memberships, accounts, units or provider credentials. Keep each app gate off until its target function and cross-account behavior are tested. Never enable against an unprepared shared backend. [BACKEND_SQL_FOR_REVIEW.md](BACKEND_SQL_FOR_REVIEW.md) contains the exact files, read-only preflight queries, order, gates and remaining provider work.

Developer 2 can poll `corvia_ws4_voice_incoming()` as the currently claimed dispatcher. It returns only `{incident_id, session_id, created_at}` for that actor's ringing sessions. Then call `corvia_ws4_voice_exchange(incident_id, session_id, after_id)` to get the caller offer and ICE candidates, create a WebRTC answer, submit it with `corvia_ws4_voice_answer(incident_id, session_id, answer_sdp)`, exchange new ICE with `corvia_ws4_voice_candidate(incident_id, session_id, operation_id, candidate)`, and finish via `corvia_ws4_voice_end(incident_id, session_id)`. The client service has `incoming`, `answer`, `exchange`, `candidate`, and `end` methods. Keep the incident lifecycle independent of voice. Test two signed-in devices and rejection after a claim or membership changes. The incident owner can initiate but cannot answer; only the current claimed, scoped dispatcher can answer. The SQL has a 60-second unanswered window and a 60-minute maximum session age. Schedule `corvia_ws4_voice_purge()` under service authority to delete signalling older than 24 hours; Flutter must never hold a service credential.

`corvia_ws4_patient_progress(incident_id)` returns only `incident_id`, `stage`, `observed_at`, and possibly `unit_latitude`, `unit_longitude`, `location_at`. Developer 2 should not replace it with the staff-only team snapshot. The stage is the team's recorded state, not a guarantee that help is arriving. There is no real ER24 API connection.

## Live backend findings (read-only SQL catalog inspection)

The accessible self-hosted Supabase backend has `public.call_sessions`, `public.call_ice_candidates`, and team WS6 incident/unit tables. It does **not** have `ws4_private.installation` or any public `corvia_ws4*`/patient emergency RPC found by catalog query. The current legacy ICE policies show `call_ice_candidates_select:true` and `call_ice_candidates_insert:all`; do not use them for the new voice flow. These observations describe the inspected backend at this checkpoint, not a deployed release or data classification.

### Shared-project preflight, 12 October (read only)

The signed-in self-hosted SQL editor runs as `supabase_admin`. A `BEGIN READ ONLY; SET LOCAL ROLE postgres; SELECT current_user; ROLLBACK;` check returned `postgres`, so owner-role execution has a reversible path. No migration or grant change was applied. The core upgrade still refuses the current `public.register_auth_user_temp(text,text)` grant: it is `SECURITY DEFINER`, creates already-confirmed Auth users, and explicitly grants `EXECUTE` to `anon` and `authenticated`. The user confirmed that Testing is the live app version and will remain so. In the latest locally available `origin/Testing` (`9bc88cc`), Flutter signup calls `supabase.auth.signUp` and no Dart caller of the RPC exists; revoking that grant does not affect this checked-in signup path. A remote-tip check failed authentication, so `9bc88cc` cannot be independently confirmed as the current server tip. An older `TODO.md` in the stale local `Testing` ref and historical refs describes the RPC as a signup workaround for missing SMTP, but conflicts with the available Testing source. PostgreSQL function tracking is `none`. A five-day API Gateway path search found no RPC calls but also no `/rest/v1/` traffic, so logs cannot establish whether any non-app client uses it. The larger rollout risk is independent: the migration restricts incident access and requires provisioned patient routes and active dispatcher memberships, neither of which the install creates for existing accounts. Review and provision these before enabling the WS4 flow on the shared project.

The live project has nine legacy `public.incidents` rows: eight `pending`, one `in_progress`. All nine belong to accounts whose email addresses match README demo accounts, but this does not authorize deleting or reclassifying their incident records. The upgrade's basic invalid-row and conflicting-column checks returned zero/false. Legacy rows receive no invented organisation route and will not automatically enter the new WS4 dispatch queue. The team EMS command, role function and tables are present; there is one hospital and three units, but zero `corvia_ops_memberships` and zero crews. A linked ambulance handoff cannot complete without reviewed memberships, eligible crews and route mapping.

The self-hosted dashboard exposes no backup/restore control, and no restorable snapshot or restore procedure was verified. Existing incident/profile policies and triggers are present, including a lab-admin profile trigger; `001_shared_upgrade.sql` changes these shared access paths and revokes direct incident writes. Some legacy app paths still write `public.incidents` directly. Therefore do not install 001–007 on this project until the backend owner confirms recovery, the registration function's consumers, current-app compatibility, and the disposition of the nine legacy incidents. Then rehearse the exact schema with synthetic data, install in reviewed order, provision mapped roles/routes/crews, and test signed-in patient/dispatcher/Fleet/Paramedic flows before enabling flags. This is a no-go finding, not a deployed WS4 backend.

## Verification

- Full Flutter suite: **820 passed** after the 008–011 and push-client additions.
- Focused account, Settings, nearby, progress, intake and voice service tests passed.
- The focused voice-controller retry test and adjacent voice, progress and contact tests passed (8 tests); focused analysis of the voice files found no issues.
- Focused analysis of all 22 changed/new application source files: **no issues**. Complete analyzer reports 12 findings confined to unchanged admin/doctor files. Web build passed; its Wasm dry run reported three `flutter_tts` package interoperability warnings, but the normal web build succeeded.
- Isolated PostgreSQL 15.8 rehearsal: **224 passed**, including installation of 006–011, scoped requester/callback access, contact opt-in/outbox dedup, push registration/rotation/revocation/role denial, and earlier team/voice checks. Evidence: ignored local `build/ws4-dev1-rehearsal/f2541079ae18422c82a3864b54898a31/result.json`; `server_stopped=true`.
- No live migration, two-device audio, device push, contact alert delivery, real provider call, or manual full-app journey was performed.

## Remaining before a complete Developer 1 demo handoff

1. A backend owner must review the intended test backend schema, install the already reviewed WS4 stack there, then review and install 006/007. The inspected live project currently lacks the WS4 core. Do not run the synthetic test installer on it.
2. Developer 2 must implement and test the responder side and incoming-call UI against the same voice contract. Then verify real two-device audio, microphone denial, unanswered timeout, network loss, claim revocation, reconnect, and ending voice without ending the incident. TURN configuration may be needed across real networks.
3. A server-side contact-alert sender, provider verification/webhook, device token source, push sender, delivery receipts, consent and opt-out handling, and deep-link ownership checks remain. The outboxes and app contract are prepared, but they do not send or prove delivery. Do not label an outbox or provider acceptance as delivered. Keep provider-dependent functionality off in the demo until the sender is integrated and tested.
4. Manually test the patient journey, linked Fleet/Paramedic status, nearest-service fallback and Dispatcher integration with synthetic accounts on an isolated backend. Compare Developer 2's branch when it lands; do not overwrite their UI or merge to Testing solely because local tests passed.

The source of truth for each installed function is the target catalog, not the presence of SQL files in Git.
