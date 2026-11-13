# Corvia live QA status — 10 October 2026

This checklist reconciles the supplied issue PDF and live QA report with the
current `Testing` code. A page or database object being present does not prove
that the hosted Supabase deployment or real user accounts are configured.

## Implemented in Flutter

- Admissions now exposes **Add Bed** and opens Hospital Structure on the Beds tab.
- Admissions, Hospital Structure and Live Bed Board use a horizontal summary
  strip on narrow screens so the main content and tabs retain usable height.
- Hospital Structure checks duplicate bed numbers and room capacity before save.
- Fleet vehicle registration is required; compliance expiry cannot be in the
  past; BLS, ILS and ALS show their full descriptions.
- Emergency/paramedic forms have top spacing so the first floating label remains
  visible.
- Initially unidentified EMS patients can be completed later through **Edit
  patient details** after the SQL upgrade is installed.
- The Patient QR dialog closes its own dialog rather than popping the incident page.
- Visitor capture/pass dialogs protect the first floating label from clipping.
- AI Booking Queue, Billing and Reports use readable theme colours in dark mode.
  Refresh controls, report headings and the final statistic icon remain visible.
- The AI Booking Queue back button returns to the Hospital Admin dashboard.
- The compact Hospital Admin menu has an explicit accessibility button label.

## Supabase action required

Run the following whole files in SQL Editor as the database owner, in this order:

1. `supabase/scripts/workstreams/13_dispatch_fleet_upgrade.sql` when the Fleet
   Operations page still reports that its upgrade is missing.
2. `supabase/scripts/workstreams/18_install_live_qa_fixes.sql`. Its final row must
   show `true` for patient update, vehicle validation and bed capacity validation.
3. For the Blood Bank patient-search installation message, run
   `supabase/migrations/20261008_corvia_blood_bank_workspace.sql`, followed by
   `supabase/migrations/20261008_corvia_blood_bank_patient_search.sql`, then
   `Documentation/workstreams/03_verify_blood_bank.sql`.

The Blood Bank clinical-authority notice is an intentional safety gate. A real
hospital approval/policy reference must be recorded before reservation and issue
are enabled. The commented owner-only statement is in
`Documentation/workstreams/02_configure_blood_bank.sql`.

## Deployment or account work still required

- Reset or verify the supplied Fleet Manager and Paramedic test accounts. The QA
  report says their credentials were rejected before a workspace could load.
- Confirm that the tested Hospital Admin Auth user has an active Blood Bank
  manager membership in the intended hospital.
- Retest QR/camera scanning on a real HTTPS or localhost origin with browser and
  operating-system camera permission. A black local preview is not enough to
  diagnose device permission or camera-driver behaviour.
- Profile the initial dashboard delay on the deployed environment. The report
  records a delay but does not identify whether it is authentication, network,
  database or rendering time.
- Run signed-in, role-separated mutation tests for stock movement, admission,
  dispatch, paramedic clinical capture and handover. The supplied live QA report
  deliberately covered mainly read-only/navigation paths.

## Local verification completed

- `dart analyze`: no compile errors; existing repository warnings remain.
- Focused Flutter tests: 12 passed.
- Live-QA PostgreSQL migration test: passed, including a safe rerun.
- Flutter web release build: completed successfully.
