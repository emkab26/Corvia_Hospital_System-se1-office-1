# Corvia Hospital System - MyCorvia

> **13 October 2026 demo:** See the [demo delivery plan and checklist](https://git.coastit.co.za/CoastIT_Corvia/Corvia_Hospital_System/wiki/Demo-Delivery-Plan-13-October-2026) for the six workstreams, initial repository findings, 7-12 October targets and rehearsal checks. This is a demo milestone; production readiness is tracked separately.

The standalone website is in the top-level [CORVIA_PAYMENT_WEBSITE](CORVIA_PAYMENT_WEBSITE/README.md) folder. See that guide for local preview, sandbox configuration, migration, Edge Functions and integration checks still required before the demo.

**9 October handoff:** Workstreams 1–6 are Blood Bank, PayFast checkout, Payment monitoring, Emergency dashboard, Fleet management and Paramedic system. See the [current Flutter pages, local payment website and Supabase SQL run order](https://git.coastit.co.za/CoastIT_Corvia/Corvia_Hospital_System/wiki/Workstreams-Start-Here-2026-10-09). The separately supplied inpatient-bed PDF is a separate module. The named WS4 team release and legacy voice-call integration remain pending; the guide distinguishes local validation from hosted acceptance.

A cross-platform healthcare and hospital operations platform built with **Flutter** and **Supabase**, targeting Android, iOS, Windows, macOS, Linux, web development builds and Android Wear OS support.

MyCorvia connects patients, doctors, specialists, nurses, reception staff, pharmacists and hospital administrators under one authenticated, multi-hospital healthcare platform.

The system currently includes patient appointments, prescriptions, pharmacy dispensing, lab results, telehealth, emergency workflows, wearable integration, AI nurse assistance, hospital administration, reception check-ins, nurse workflows, specialist requests and referrals, patient notifications, hospital admissions, bed management, visitor workflows, interhospital transfers and a versioned digital hospital documentation engine.

> **Status:** Pre-deployment / active development.
>
> Core functionality is substantially built, but the project still requires final regression testing, remaining RLS/security review, controlled-form runtime deployment, official form approval, warning cleanup and production hardening.
>
> **Backend:** Self-hosted Supabase at `supabase.coastit.co.za`.
>
> **Main working branch:** `Testing`
>
> **Do not push directly to Main.**
>
> **Requirements and audits:** the SRD and audit reports live in the [project wiki](https://git.coastit.co.za/CoastIT_Corvia/Corvia_Hospital_System/wiki). Outstanding work is tracked as issues, not in the repo.
>
> **Selectable themes:** candidate palettes ship as light/dark variants. The default is Modern Light. Colours should flow through `CorviaColors` and `context.c*` extensions. Avoid unnecessary hardcoded `Color(0xFF...)` values.
>
> **Last README update:** 2026-10-09.

---

# Current Development Snapshot

As of 2026-08-23:

- Patient, doctor, specialist, nurse, reception, pharmacist and hospital-admin flows are present.
- Pharmacist workflow has been added.
- Pharmacist Dashboard now includes shared Settings access.
- Multi-hospital data separation architecture has been added.
- Reception hospital-context and doctor/department filtering infrastructure has been added.
- Nurse hospital-context, shift and assigned-patient infrastructure has been expanded.
- Doctor clinical-record workflows have been expanded.
- Doctor Risk Factors can be recorded and edited through clinical records.
- Doctor Immunisation records can be created and edited.
- New doctor-created clinical records automatically use the signed-in doctor identity.
- Doctor clinical records support hospital context where available.
- Treatment selection supports dynamic options and a custom `Other` option.
- Doctor lab ordering supports dynamic test options and a custom `Other` option.
- Lab ordering and lab-result workflows use the existing `lab_results` lifecycle instead of requiring a duplicate order table.
- Doctor lab requests can store hospital and department context where available.
- Hospital structure management supports buildings, floors, wards, rooms and beds.
- Hospital admissions and patient bed assignments are supported.
- Visitor management and visitor scanning interfaces are present.
- Interhospital transfer workflows and document handling are present.
- Patient notifications and patient transfer status pages are present.
- Digital Hospital Forms Engine foundation is implemented.
- Controlled official form registry and approval infrastructure is implemented.
- Controlled PDF master storage and version binding infrastructure is implemented.
- Controlled PDF visual mapping/calibration infrastructure is implemented.
- Patient-safe released-form PDF evidence infrastructure is implemented.
- Controlled PDF page geometry foundation is implemented.
- Controlled PDF Unicode font safety foundation is implemented.
- Wear OS Android module has been added.
- Local medication reminder notifications are configured.
- Immediate editor-level compile errors identified during the current backlog work have been corrected.
- Final repository-wide `flutter analyze`, regression testing and production validation remain part of the final testing phase.

Important production limitations:

- Controlled official forms are **not automatically production approved**.
- Demo/planning form templates remain subject to hospital, clinical, legal, privacy and records-management approval.
- Controlled forms should remain `production_approved = false` until all required approval gates have passed.
- The `render-controlled-form` Edge Function runtime still requires deployment and runtime verification by the Supabase host/admin.
- The current developer environment does not have authority to independently deploy Supabase Edge Functions to the hosted environment.

---

# Quick Start for New Team Members

1. Read this README completely.
2. Pull the latest `Testing` branch.
3. Run `flutter pub get`.
4. Read [explicit backend configuration](supabase/scripts/ws4_local_setup.md). Flutter no longer loads or bundles `.env`.
5. Select an authorized backend and pass its public client configuration at build/run time.
6. Run the app on Chrome, Windows or Android.
7. Test the role/module you are working on before changing code.
8. Run `dart format lib` where appropriate.
9. Run `flutter analyze`.
10. Search for unresolved Git conflict markers before pushing.
11. Commit to `Testing` or to a feature branch created from `Testing`.
12. Never force-push shared branches unless specifically coordinated with the team.

Useful pre-push conflict check:

```bash
git grep -n -e "^<<<<<<< " -e "^=======$" -e "^>>>>>>> "
```

This command should return no unresolved merge markers.

---

# Tech Stack

| Layer | Technology |
|------|------------|
| Frontend | Flutter 3.x / Dart |
| Backend / Auth / DB | Self-hosted Supabase PostgreSQL, Auth, Storage, Realtime and Edge Functions |
| Maps | MapTiler, `flutter_map`, OpenStreetMap / Overpass where applicable |
| Real-time / Video | WebRTC via `flutter_webrtc`, signalled through Supabase |
| Health data | Health Connect / HealthKit via Flutter `health` package |
| Wearables | Health platform integration + Android Wear OS module |
| Wear OS communication | Google Play Services Wearable API |
| Biometric auth | `local_auth` |
| Local settings | `shared_preferences` |
| Local notifications | `flutter_local_notifications`, `timezone`, `flutter_timezone` |
| Voice | `speech_to_text` and `flutter_tts` |
| PDF generation | `pdf`, `printing` |
| File selection | `file_picker` |
| Cryptographic hashing | `crypto` |
| Payments | PayFast through Supabase Edge Function |
| Environment config | Explicit Dart build defines, `lib/config/env.dart` and `lib/config/backend_environment.dart` |
| Theme | `lib/theme/app_theme.dart` |
| Logging | `debugPrint` / `logging` |
| QR | `qr_flutter`, `pretty_qr_code`, `mobile_scanner` |

---

# Getting Started

## Prerequisites

- Flutter SDK stable channel
- Dart SDK compatible with `pubspec.yaml`
- Android Studio for Android and Wear OS development

### Hosted development startup on Windows

Keep only public client settings in `.env`: `SUPABASE_URL`,
`SUPABASE_ANON_KEY`, `MAPTILER_KEY`, `OAUTH_REDIRECT_URL`, and `STUN_SERVER`.
In a debug build, plain `flutter run` loads this asset if no backend
`--dart-define` values were supplied. Select Chrome when prompted; the hosted
testing backend is validated before login. Explicit defines still take
precedence, and release builds never use this debug fallback. Never add a
service-role key or other private setting to `.env`.

The optional Windows launcher `python tools/run_corvia.py` (with
`--device chrome` or an Android device ID) prepares an ignored local defines
file from the same public settings. It never prints the key.

For the Android Studio Run button, run `python tools/run_corvia.py --prepare`
after changing `.env`, then select the shared **Corvia Hosted Testing** Flutter
Run configuration in `.run/Corvia Hosted Testing.run.xml`. Its target is
`lib/main.dart` and its additional argument is
`--dart-define-from-file=.corvia-dev-defines.json`. Keep that generated JSON
local. Plain `flutter run` now uses the debug asset fallback above.
- Xcode for iOS development
- Supabase environment access
- MapTiler API key
- Physical Android device where Health Connect testing is required
- Wear OS emulator/device where wearable integration is being tested
- Appropriate Supabase admin/host assistance for Edge Function deployment

---

## 1. Clone and install dependencies

```bash
git clone <repo-url>
cd Corvia_Hospital_System
git checkout Testing
flutter pub get
```

---

## 2. Backend configuration

Flutter reads compile-time configuration. It does **not** load the root `.env` or bundle it as an asset. Plain `flutter run` fails startup if no public client key is provided; there is no remote fallback.

See [WS4 local and deployment configuration](supabase/scripts/ws4_local_setup.md) for local, Testing/live, OAuth, maps, TURN and optional AI settings. Use only the backend's public client key. Never put service-role keys or server secrets into a Flutter build, configuration file or Git.

The local profile requires a separately provisioned local Supabase backend. The isolated PostgreSQL contract tests under `test/backend/ws4/` do not provide Auth, HTTP or Realtime services for running the application.

## 3. Run the app

For an already provisioned isolated local Supabase backend, set `CORVIA_LOCAL_PUBLIC_KEY` in your PowerShell session to its public client key, then run:

```powershell
if ([string]::IsNullOrWhiteSpace($env:CORVIA_LOCAL_PUBLIC_KEY)) { throw 'Set the local backend public client key first.' }
flutter run -d chrome --dart-define=CORVIA_ENV=local --dart-define=SUPABASE_URL=http://127.0.0.1:54321 --dart-define=SUPABASE_ANON_KEY=$env:CORVIA_LOCAL_PUBLIC_KEY
```

Use `flutter devices` to select another supported device. Android emulator builds use `http://10.0.2.2:54321` to reach the host backend. Physical-device and shared Testing/live setup require a deliberately approved endpoint; see the configuration guide. Choose its registered OAuth callback before testing sign-in.

---

## 4. Deploy the web build with Docker

The repository includes `Dockerfile`, `nginx.conf` and `compose.yaml` for serving the compiled Flutter Web application from an Nginx container. Docker Compose reads its environment file and passes the selected configuration as build arguments. This is separate from Flutter configuration: Flutter itself does not read `.env`.

Create an ignored `.env.local` with public client settings for the backend approved by its owner. For a Testing web build, the required shape is:

```env
CORVIA_ENV=testing
SUPABASE_URL=https://your-approved-supabase-host
CORVIA_EXPECTED_BACKEND_ORIGIN=https://your-approved-supabase-host
SUPABASE_ANON_KEY=<public-client-key>
OAUTH_REDIRECT_URL=https://app.example.com/login-callback
```

Build and start the container:

```bash
docker compose --env-file .env.local build --no-cache
docker compose --env-file .env.local up -d
```

The container serves the application on `127.0.0.1:8080`:

```bash
docker compose --env-file .env.local logs corvia-web
curl -I http://127.0.0.1:8080
```

The expected response is `HTTP/1.1 200 OK`. If a manually created container named `corvia-web` already exists, stop and remove it once before starting Compose:

```bash
docker stop corvia-web
docker rm corvia-web
docker compose --env-file .env.local up -d
```

On a VPS, place an HTTPS reverse proxy such as Caddy, Nginx Proxy Manager or Nginx in front of the container and forward the public domain to `127.0.0.1:8080`. Open ports 80 and 443 in the VPS firewall. HTTPS is required for browser camera and microphone permissions.

Configure the production domain and OAuth callback in Supabase Auth before testing login. Test authentication, database access, Realtime updates, QR scanning, camera/microphone permissions, emergency WebRTC calls and refreshing nested routes such as `/dashboard`.

The browser build contains the Supabase anonymous key by design. Never place a Supabase service-role key or other server secret in client build configuration. Keep local configuration out of Git. The previously tracked `.env` has not been deleted or cleaned from history by this change.

---

## 5. Quality checks

```bash
flutter pub get
dart format lib
flutter analyze
```

The final repository-wide analyzer pass is performed during the final regression/cleanup phase.

Warnings may include categories such as:

- Deprecated Flutter APIs
- Deprecated `withOpacity`
- Deprecated form-field `value`
- Async `BuildContext` usage
- Unused imports
- Unused fields
- Unused methods
- Unnecessary type checks
- Style/lint findings
- Protected member usage

These should continue to be cleaned gradually.

Do not ignore actual compile errors.

---

# Project Structure

The project is organised primarily by role and shared system responsibility.

```text
lib/
├── auth/
│   ├── auth_gate.dart
│   ├── biometric_lock_page.dart
│   ├── device_verification_page.dart
│   ├── face_recognition_login.dart
│   ├── face_recognition_registration.dart
│   ├── linked_devices_page.dart
│   ├── login.dart
│   ├── register.dart
│   └── role_choice_page.dart
│
├── config/
│   └── env.dart
│
├── constants/
├── models/
│   └── corvia_wearable_snapshot.dart
│
├── pages/
│   │
│   ├── admin/
│   │   ├── controlled_form_master_viewer_page.dart
│   │   ├── controlled_form_render_mapping_page.dart
│   │   ├── controlled_form_visual_calibration_page.dart
│   │   ├── controlled_hospital_forms_page.dart
│   │   ├── hospital_admissions_page.dart
│   │   ├── hospital_bed_board_page.dart
│   │   ├── hospital_structure_page.dart
│   │   ├── hospital_visitor_scanner_page.dart
│   │   ├── hospital_visitors_page.dart
│   │   ├── interhospital_transfer_document_upload_page.dart
│   │   ├── interhospital_transfers_page.dart
│   │   ├── manage_beds_page.dart
│   │   ├── manage_buildings_page.dart
│   │   ├── manage_floors_page.dart
│   │   ├── manage_rooms_page.dart
│   │   └── manage_wards_page.dart
│   │
│   ├── doctor/
│   │   ├── doctor_dashboard.dart
│   │   ├── doctor_appointments.dart
│   │   ├── doctor_add_patient_record.dart
│   │   ├── doctor_clinical_lab_request_sheet.dart
│   │   ├── doctor_prescription_dashboard.dart
│   │   ├── doctor_patient_management.dart
│   │   ├── doctor_patient_records.dart
│   │   ├── doctor_medical_records.dart
│   │   ├── doctor_qr_scanner.dart
│   │   ├── doctor_reception_queue_page.dart
│   │   ├── doctor_reportviewing.dart
│   │   ├── doctor_specialist_referral_page.dart
│   │   └── doctor_telehealth.dart
│   │
│   ├── forms/
│   │   ├── corvia_forms_button.dart
│   │   ├── corvia_forms_navigator.dart
│   │   ├── dynamic_hospital_form_page.dart
│   │   ├── hospital_form_audit_page.dart
│   │   ├── hospital_form_pdf_preview_page.dart
│   │   ├── hospital_forms_page.dart
│   │   ├── patient_released_forms_page.dart
│   │   └── role_hospital_forms_page.dart
│   │
│   ├── hospital/
│   │   ├── hospital_admin_shell.dart
│   │   ├── hospital_dashboard_page.dart
│   │   ├── hospital_patients_page.dart
│   │   ├── hospital_doctors_page.dart
│   │   ├── hospital_pharmacists_page.dart
│   │   ├── hospital_appointments_page.dart
│   │   ├── hospital_qr_checkins_page.dart
│   │   ├── hospital_ai_booking_queue_page.dart
│   │   ├── hospital_departments_page.dart
│   │   ├── hospital_locations_page.dart
│   │   ├── hospital_emergency_page.dart
│   │   ├── hospital_billing_page.dart
│   │   ├── hospital_reports_page.dart
│   │   ├── hospital_settings_page.dart
│   │   └── widgets/
│   │       └── hospital_operations_dashboard_panel.dart
│   │
│   ├── nurse/
│   │   ├── nurse_dashboard_page.dart
│   │   ├── nurse_assigned_patients_page.dart
│   │   ├── nurse_observations_page.dart
│   │   ├── nurse_medication_rounds_page.dart
│   │   ├── nurse_tasks_page.dart
│   │   └── nurse_shift_page.dart
│   │
│   ├── patient/
│   │   ├── dashboard.dart
│   │   ├── appointments_page.dart
│   │   ├── patient_booking_home_page.dart
│   │   ├── book_appointment.dart
│   │   ├── appointment_confirmation.dart
│   │   ├── my_prescriptions.dart
│   │   ├── patient_pharmacy_status_page.dart
│   │   ├── patient_transfer_status_page.dart
│   │   ├── patient_notifications_page.dart
│   │   ├── ai_nurse.dart
│   │   ├── ai_symptom_intake.dart
│   │   ├── billing.dart
│   │   ├── chat_page_user.dart
│   │   ├── chat_with_doctor.dart
│   │   ├── dispatch.dart
│   │   ├── doctor_detail.dart
│   │   ├── doctor_patient_timeline.dart
│   │   ├── emergency.dart
│   │   ├── emergency_contacts_page.dart
│   │   ├── emergency_qr_profile.dart
│   │   ├── find_a_doctor.dart
│   │   ├── lab_request_form.dart
│   │   ├── lab_result_explainer.dart
│   │   ├── lab_results.dart
│   │   ├── medical_aid_info.dart
│   │   ├── medication_reminders.dart
│   │   ├── patient_records.dart
│   │   ├── profile.dart
│   │   ├── reception_check_in_qr.dart
│   │   ├── reminders.dart
│   │   ├── report_a_doctor_page.dart
│   │   ├── scan_qr_code.dart
│   │   ├── wearables.dart
│   │   ├── notifications/
│   │   │   └── patient_notifications_page.dart
│   │   └── specialist/
│   │       └── specialist_request_page.dart
│   │
│   ├── pharmacist/
│   │   ├── pharmacist_dashboard_page.dart
│   │   └── pharmacist_prescription_detail_page.dart
│   │
│   ├── reception/
│   │   ├── reception_dashboard.dart
│   │   ├── reception_booking_page.dart
│   │   ├── reception_patient_search.dart
│   │   ├── reception_qr_check_in_page.dart
│   │   ├── reception_queue_page.dart
│   │   ├── reception_walk_in_page.dart
│   │   └── specialist/
│   │       └── reception_specialist_requests_page.dart
│   │
│   └── shared/
│       ├── policy_page.dart
│       ├── settings.dart
│       └── terms_and_conditions.dart
│
├── repositories/
│
├── services/
│   ├── account_access_service.dart
│   ├── account_mode_service.dart
│   ├── controlled_form_service.dart
│   ├── doctor_clinical_service.dart
│   ├── hospital_admission_service.dart
│   ├── hospital_form_context_service.dart
│   ├── hospital_form_engine_service.dart
│   ├── hospital_form_pdf_service.dart
│   ├── hospital_operations_service.dart
│   ├── hospital_structure_service.dart
│   ├── hospital_visitor_service.dart
│   ├── interhospital_transfer_service.dart
│   ├── lab_catalog_service.dart
│   ├── notification_service.dart
│   ├── nurse_service.dart
│   ├── patient_notification_service.dart
│   ├── patient_transfer_status_service.dart
│   ├── settings_service.dart
│   ├── transfer_document_picker_service.dart
│   └── wearable_service.dart
│
├── theme/
├── utils/
├── widgets/
│   └── patient_notification_bell.dart
│
└── main.dart
```

Android Wear OS module:

```text
android/
└── wear/
    ├── build.gradle.kts
    └── src/
        └── main/
            ├── AndroidManifest.xml
            └── kotlin/
                └── com/example/mycorvia/wear/
                    ├── CorviaWearListenerService.kt
                    ├── CorviaWearStore.kt
                    └── MainActivity.kt
```

---

# Login and Routing Logic

After successful login, `AuthGate` routes users using database-authoritative Supabase profile and hospital/staff relationship data.

| Role | Routing |
|------|---------|
| `hospital_admin` | Hospital Command Centre |
| `reception` | Reception Dashboard |
| `patient` | Patient Dashboard |
| `doctor` | Clinical staff / role-choice flow where dual access exists |
| `specialist` | Clinical staff / role-choice flow where dual access exists |
| `nurse` | Clinical staff / role-choice flow where dual access exists |
| `pharmacist` | Pharmacist workflow/dashboard |

Important role rules:

- Hospital Admin accounts are admin-only.
- Hospital Admin users must not be offered patient mode.
- Doctors, specialists and nurses may also be patients.
- A clinical staff role must not be overwritten merely to give that user patient access.
- Clinical staff may have dual staff/patient access where properly linked.
- Reception users route directly to the Reception Dashboard.
- Patient users route directly to the Patient Dashboard.
- Pharmacist access is role-based and hospital scoped.
- Hospital-specific access must remain isolated to the relevant hospital unless a valid transfer/shared workflow explicitly permits cross-hospital access.
- Staff/patient mode-switch availability should come from database-authoritative account relationship logic rather than manually trusting stale client-side role flags.

---

# Multi-Hospital Architecture

Corvia is designed to support multiple hospitals while keeping operational data scoped correctly.

Primary hierarchy:

```text
Hospital
→ Building
→ Floor
→ Ward
→ Room
→ Bed
→ Admission / Patient Assignment
```

The design supports multiple hospitals operating independently.

Hospital data should remain separated by hospital context.

Cross-hospital movement is expected to happen only through approved workflows such as interhospital transfer.

Important hospital context concepts include:

- Hospital membership
- Hospital administrators
- Hospital staff access
- Hospital departments
- Hospital wards
- Admissions
- Beds
- Transfers
- Hospital-specific form templates
- Hospital-specific controlled official forms

---

# Test Accounts

These accounts are for internal development/demo use only.

Do not use real patient data with these accounts.

## Core Staff Accounts

| Role | Email | Password | Notes |
|------|-------|----------|-------|
| Reception | `reception@co.za` | `Test1234!` | Reception Dashboard |
| Nurse | `nurse@co.za` | `Test1234!` | Nurse test account |
| Specialist | `specialist@co.za` | `Test1234!` | Specialist/clinical staff test account |
| Pharmacist | `pharmacist@co.za` | `Test1234!` | Test account for the Pharmacist Dashboard and hospital dispensing workflow |

## Hospital Admin

| Role | Email | Password | Notes |
|------|-------|----------|-------|
| Hospital Admin | `admin@co.za` | `Test1234!` | Hospital Command Centre; use this account for the Fleet Management demo. |

## Hospital Laboratory

| Role | Email | Password | Notes |
|------|-------|----------|-------|
| Lab Worker | `tom@co.za` | `Test1234!` | Receives hospital specimens and submits laboratory results; cannot verify or release them. |
| Lab Verifier | `liz@co.za` | `Test1234!` | Lab Verifier account |
| Lab Admin | `sam@co.za` | `Test1234!` | Hospital Lab Admin account |

## Doctors

| Name | Email | Password | Notes |
|------|-------|----------|-------|
| Dr. James Mitchell | `dr.james.mitchell@corvia.co.za` | `Doctor@2025` | Original seed doctor |
| Dr. John Smith | `john.smith@corvia.co.za` | `Test1234!` | Test doctor |
| Dr. Mary Johnson | `mary.johnson@corvia.co.za` | `Test1234!` | Test doctor |

## EMS accounts — do not use for the demo

These logins are retained for repair and testing, but are **not approved demo
accounts**. Do not present any EMS screen as live dispatch until its hosted
backend and role permissions have been verified.

| Role | Email | Why it is excluded |
|------|-------|--------------------|
| Fleet manager | `fleetmanager@co.za` | Hosted profile is marked `patient`, so this login opens Patient Dashboard; scoped Fleet permissions and routing are not ready. |
| Dispatcher | `dispatcher@co.za` | The live incoming queue failed to load. The current Flutter route is a labelled, read-only DEMO preview only. |
| Dispatch Supervisor | `dispatchsupervisor@co.za` | The live incoming queue failed to load. The current Flutter route is a labelled, read-only DEMO preview only. |
| Paramedic | `paramedic@co.za` | Sign-in succeeds, but no matching profile is available to the app (`Profile not found`); verified EMS access is not ready. |

## Patients

| Name | Email | Password |
|------|-------|----------|
| Alice Brown | `alice.brown@corvia.co.za` | `Test1234!` |
| Bob Williams | `bob.williams@corvia.co.za` | `Test1234!` |
| Carol Davis | `carol.davis@corvia.co.za` | `Test1234!` |
| David Miller | `david.miller@corvia.co.za` | `Test1234!` |
| Emma Wilson | `emma.wilson@corvia.co.za` | `Test1234!` |

Passwords above are test-only credentials and must not be reused for production accounts.

---

# Features

What a signed-in user can reach from their dashboard today, by role. A page that exists in `lib/` but has no route to it is listed under [Built but not wired in](#built-but-not-wired-in), not here. Deeper workflow notes for doctors, specialists, forms and hospital operations follow in the sections after this one.

## Accounts and access

- Email and password registration and login
- `AuthGate` routes each account to its role dashboard: patient, doctor/specialist, reception, nurse, pharmacist, laboratory, dispatch, hospital admin
- Biometric app lock and new-device verification
- Switch Mode between the clinical and patient views, shown only to accounts that `AccountModeService` marks as eligible
- Shared Settings across roles: theme palettes in light and dark, text size, screen tint overlay, wider letter spacing, Verdana reading font, bold text, appointment and medication reminder toggles, critical health alerts, voice input and read-back, Face ID and fingerprint login, location and microphone permissions, build version

## Patient

Home tab quick actions:

- Emergency: hold for 3 seconds to open a live voice call to dispatch, stream location, and chat with the operator on the incident
- Emergency QR profile and emergency contacts
- Specialist Request
- Appointments: book through doctor search, check in by QR, report a doctor from a past appointment
- My Prescriptions: active and completed prescriptions with search, refill-due warnings, and pharmacy details. Patients cannot request a refill or stop a course. There is no share, PDF export or prescription QR code yet; the placeholder buttons were removed until those are built
- Check-In QR, plus walk-in check-in by scanning the hospital code
- Lab Results: request a lab, edit a pending request, AI explanation of a result
- AI Nurse
- Patient Timeline
- Reminders, including locally scheduled medication notifications
- Patient Records
- Chat with Doctor
- Find a Doctor, with doctor details, booking and chat
- My Hospital Forms
- Visitor Access: invite and manage visitors
- Nearby Services map
- Wearables, paired with the Wear OS companion app, plus linked device management

Elsewhere in the patient app:

- Profile: personal details, medical aid, billing, sign out. Address and phone number are read-only until Edit details; Cancel restores the saved values
- Billing hands off to the standalone payment website for PayFast checkout and shows payment status from the payment monitor
- Notifications centre from the bell, which links through to transfer status and pharmacy collection status

## Doctor

- Dashboard stats: appointments today, my patients, active prescriptions, outstanding labs, completed visits
- Appointments
- Patient management, limited to doctor-linked patients, with patient timeline access
- Clinical records stamped with the signed-in doctor and hospital context: risk factors, immunisations, treatments from a dynamic list with a custom `Other` entry
- Prescriptions: multi-medicine, edit after creation, repeat and refill handling
- Lab orders: dynamic test catalogue with custom tests, hospital and department aware, tracked from collection through to the doctor releasing results to the patient
- Scan a patient QR code
- Reception queue
- Patient messages
- Telehealth sessions. There is no in-app video call yet, the only WebRTC in the app is the emergency dispatch call
- Specialist referrals: submit and track status
- Clinical forms for a selected patient
- Workload analytics

## Reception

Reception Command Centre with live counts for appointments, check-ins, waiting, urgent and walk-in patients, plus:

- Book appointments, filtered to the hospital's departments and doctors
- Patient search
- QR check-in scanner and the reception walk-in QR display
- New walk-in registration
- Patient queue
- Specialist requests: assign a specialist, confirm a date, request referral documents, reject, reschedule
- Admission and consent forms

## Nurse

- Shift management with clock in and clock out
- Assigned patients
- Observations and vitals
- Medication rounds
- Nursing tasks
- Specimen collection for lab orders

## Pharmacist

Hospital-scoped prescription queue with this lifecycle:

```text
received -> verified -> preparing -> ready_for_collection -> collected
                                  \-> unable_to_dispense (with reason)
                                  \-> cancelled
```

- Verify the prescription against the patient, prepare, mark ready, confirm collection
- Patient is notified at each step and sees it on their pharmacy status page
- Pharmacy Dispensing and Collection form

## Laboratory

- Lab workspace that switches between the worker and verifier dashboards
- Worker: receive specimens or a whole transport bag
- Verifier: results awaiting verification, results returned for correction
- Hospital lab admin page for lab-administrator accounts

## Dispatch

- Incoming emergency calls and unassigned incidents
- Triage and unit assignment
- Live operations map with hospitals and available ambulances
- Fleet availability
- Active and completed incidents
- Reports

## Paramedic

Paramedic workspace, listed in doctor and nurse Settings only for staff the backend grants dispatch or patient-care access, or from the hospital admin Fleet Management section:

- Shift start and end, with unit readiness changes
- Assigned incidents with navigation to scene
- Scan a patient QR code at the scene
- Clinical records captured offline and synced when the connection returns
- Vehicle inspections, fault reports and repairs
- Bases and fleet operations
- Device sessions for the signed-in paramedic

## Blood Bank

Listed in doctor and nurse Settings only for staff with a hospital blood-bank membership, or from the hospital admin menu:

- Stock search, by text or by scanning a unit label with the camera
- Receive and return blood units
- Blood requests
- Event history per unit

## Payments

- `CORVIA_PAYMENT_WEBSITE/` is a standalone site for PayFast checkout, backed by the `create-payment` Edge Function
- Hospital Billing has a payment monitor where admins verify a payment with PayFast and record or resolve a review, through the `payment-review` Edge Function

Paramedic, Blood Bank and Payments are workstreams for the 13 October 2026 demo. Hosted acceptance is still open on several of them; the [demo delivery plan](https://git.coastit.co.za/CoastIT_Corvia/Corvia_Hospital_System/wiki/Demo-Delivery-Plan-13-October-2026) tracks which are verified.

## Hospital Admin

Hospital Command Centre, scoped to the admin's linked hospital:

- Dashboard with live hospital statistics
- Patients, doctors, pharmacists and staff accounts
- Appointments, QR check-ins and the AI booking queue
- Departments and locations
- Hospital structure: buildings, floors, wards, rooms, beds
- Live bed board and admissions
- Visitor access with a visitor QR scanner
- Interhospital transfers
- Emergency overview and an Emergency Dispatch section
- Fleet management, including the paramedic workspace
- Blood Bank
- Lab results and laboratory governance
- Billing and reports
- Controlled hospital forms, with PDF render mapping and visual calibration
- Settings

## Wear OS

`android/wear` is a Wear OS companion module; `CorviaWearListenerService` receives its readings on the phone. The patient Wearables page shows the data.

## Built but not wired in

These pages exist but nothing navigates to them. Either wire them up or delete them.

| Page | File | Note |
| --- | --- | --- |
| `AiSymptomIntakePage` | `lib/pages/patient/ai_symptom_intake.dart` | Retired from the dashboard, duplicates AI Nurse |
| `AppointmentConfirmationPage` | `lib/pages/patient/appointment_confirmation.dart` | |
| `DispatchDashboard` | `lib/pages/patient/dispatch.dart` | Emergency dispatch runs from the Emergency page instead |
| `GenerateCodePage` | `lib/pages/patient/generate_code_page.dart` | |
| `PatientBookingHomePage` | `lib/pages/patient/patient_booking_home_page.dart` | |
| `ScanQrCodePage` | `lib/pages/patient/scan_qr_code.dart` | |
| `RisksImmunizations` | `lib/pages/patient/risk_immunizations.dart` | Doctors manage these in patient records |
| `PatientReleasedFormsPage` | `lib/pages/forms/patient_released_forms_page.dart` | Patients cannot currently open released forms |
| `DoctorReportViewingPage` | `lib/pages/doctor/doctor_reportviewing.dart` | |
| `LabVerificationQueuePage` | `lib/pages/lab/lab_verification_queue_page.dart` | |
| `ControlledFormMasterViewerPage` | `lib/pages/admin/controlled_form_master_viewer_page.dart` | |
| `InterhospitalTransferDocumentUploadPage` | `lib/pages/admin/interhospital_transfer_document_upload_page.dart` | |
| `FaceRecognitionLogin`, `FaceRecognitionRegister` | `lib/auth/face_recognition_*.dart` | |
| `CorviaSubscriptionCard` | `lib/widgets/corvia_subscription_card.dart` | Widget, not placed on any screen |
| `CorviaFeatureGate` | `lib/widgets/corvia_feature_gate.dart` | Widget, not placed on any screen |

---

# Doctor Clinical Records

Doctor clinical records use the existing Corvia clinical data model rather than creating unnecessary duplicate tables.

Primary clinical record table:

```text
medical_records
```

Supported record concepts include:

```text
treatment_plan
risk_factor
immunization
```

Doctor-created records use the currently authenticated doctor identity.

Where hospital context is available, new records can include:

```text
doctor_id
patient_id
hospital_id
record_type
title
description
record_date
```

Doctor-created Risk Factors and Immunisations can be edited by the doctor that created them, subject to database Row Level Security.

Legacy patient medical conditions may still be displayed as historical/risk information even where they originated outside the newer doctor-created `risk_factor` records.

---

# Doctor Lab Workflow

Corvia uses the existing:

```text
lab_results
```

table as the laboratory order/result lifecycle.

Relevant fields include:

```text
id
patient_id
doctor_id
test_name
result
file_url
created_at
status
hospital_id
department_id
```

A normal doctor lab flow is:

```text
Doctor
→ Select authorised patient
→ Select dynamic lab test
→ Create pending lab_results row
→ Laboratory workflow progresses
→ Result/status/file can update the same row
```

This avoids creating an unnecessary disconnected duplicate lab-order table.

Dynamic lab options can use the Corvia configuration catalogue while still supporting:

```text
Other
```

for custom investigations when required.

---

# Specialist Workflow

The specialist workflow supports patient-created requests and doctor-created referrals.

## Patient flow

1. Patient opens Specialist Request.
2. Patient selects specialty.
3. Patient selects urgency.
4. Patient chooses preferred time.
5. Referral status/relevant information is recorded.
6. Request is stored in `specialist_requests`.
7. Reception can review the request.
8. Patient receives notifications when the request status changes.

## Doctor referral flow

1. Doctor opens Refer to Specialist.
2. Doctor selects a patient.
3. Doctor selects specialty.
4. Doctor selects urgency.
5. Doctor selects hospital and preferred time.
6. Doctor adds reason and clinical notes.
7. Referral is submitted to Reception.
8. Doctor can track status changes.

## Reception flow

1. Reception opens Specialist Requests.
2. Reception sees patient requests and doctor referrals.
3. Reception assigns a specialist.
4. Reception confirms appointment date/time.
5. Confirmed request can create an appointment.
6. Reception can request referral documentation.
7. Reception can reject requests.
8. Reception can reschedule requests.

Statuses include:

```text
pending
assigned
confirmed
rescheduled
referral_required
rejected
cancelled
```

---

# Hospital Structure and Bed Management

Hospitals can manage their physical structure through:

```text
Buildings
Floors
Wards
Rooms
Beds
```

Admin pages include:

```text
manage_buildings_page.dart
manage_floors_page.dart
manage_wards_page.dart
manage_rooms_page.dart
manage_beds_page.dart
hospital_structure_page.dart
hospital_bed_board_page.dart
```

Bed workflows support hospital admission and patient-location tracking foundations.

---

# Hospital Admissions

Hospital admissions infrastructure supports:

- Hospital-scoped admissions
- Patient admission records
- Bed assignments
- Room/ward placement
- Patient movement foundations
- Bed Board integration
- Admin admission workflow
- Admission-aware hospital operations

Hospital admission access must remain role and hospital scoped.

---

# Visitor Management

Visitor functionality includes:

- Hospital visitor management page
- Visitor scanner page
- Hospital visitor service
- Ward-aware visitor rules foundation
- Visitor access workflows
- QR-based visitor scanning foundations

Hospital-specific visitor policies must remain configurable and should account for clinical restrictions such as ICU or other controlled wards.

---

# Interhospital Transfers

Corvia includes a structured interhospital transfer foundation.

Interfaces and services include:

- Interhospital transfer management
- Patient transfer status
- Transfer document upload
- Transfer status history
- Transfer access logging
- Transfer document storage
- Hospital-scoped access controls

Transfer workflows should be the controlled mechanism for moving patient-care context between hospitals.

---

# Notifications

Corvia currently supports multiple notification mechanisms.

## Application notifications

Used for workflows such as:

- Specialist status changes
- Pharmacy status
- Patient workflow updates
- Transfer status
- Other hospital events

Relevant services/widgets include:

```text
patient_notification_service.dart
patient_notification_bell.dart
patient_notifications_page.dart
```

## Local medication reminders

Medication reminders use local device notifications through:

```yaml
flutter_local_notifications
timezone
flutter_timezone
```

These notifications are scheduled on the patient's device.

They are designed to continue working locally without requiring server push delivery.

---

# Wearables and Wear OS

Corvia includes patient wearable infrastructure.

Flutter-side components include:

```text
lib/models/corvia_wearable_snapshot.dart
lib/services/wearable_service.dart
lib/services/wearable_link_service.dart
lib/pages/patient/wearables.dart
```

Android Wear OS components include:

```text
android/wear/
```

Wear OS support currently includes:

- Wear module Gradle configuration
- Wear manifest
- Wear activity
- Wear listener service
- Wear local store
- Google Play Services Wearable dependency
- Flutter-side wearable snapshot model
- Patient Wearables page

Wearable functionality still requires device/emulator regression testing before production use.

Wearables must not be treated as a replacement for certified hospital monitoring devices unless specifically validated and approved.

---

# Digital Hospital Forms Engine

Corvia includes a versioned Digital Hospital Form Engine.

The engine is intended to support:

- Hospital-specific templates
- Form versions
- Dynamic fields
- Conditional fields
- Role permissions
- Patient forms
- Staff forms
- Signatures
- Attachments
- Audit history
- PDF export
- Patient release
- Break-glass workflows
- Legal holds
- Hospital context
- Controlled official document support

Core tables include:

```text
hospital_form_templates
hospital_form_template_versions
hospital_form_template_fields
hospital_form_role_permissions
hospital_form_instances
hospital_form_instance_values
hospital_form_signatures
hospital_form_attachments
hospital_form_audit_events
hospital_form_break_glass_sessions
hospital_form_legal_holds
hospital_form_exports
```

Important Flutter components include:

```text
dynamic_hospital_form_page.dart
hospital_forms_page.dart
role_hospital_forms_page.dart
hospital_form_audit_page.dart
hospital_form_pdf_preview_page.dart
patient_released_forms_page.dart
hospital_form_engine_service.dart
hospital_form_pdf_service.dart
```

---

# Hospital Form Template Catalogue

The current form engine contains a substantial planning/demo catalogue.

Current seeded catalogue:

```text
Phase 1: 11 templates
Phase 2: 23 templates
Phase 3: 30 templates
Total:   64 templates
```

This does **not** mean that 64 official statutory hospital documents are legally approved for production.

The catalogue serves as the digital workflow/form-engine foundation.

Demo/seed forms should retain metadata such as:

```text
demo_only = true
production_approved = false
production_approval_required = true
```

where applicable.

Exact statutory forms require official source documents, version control and approval.

---

# Controlled Official Forms

Corvia contains a separate controlled-document system for forms that require exact official layout/version management.

Examples can include controlled statutory or legal documents such as:

- J88-related documentation
- Form 22
- W.Cl.4 / W.Cl.5
- RAF documentation
- Mental Health Care Act documentation
- NMC documents
- DHA-1663
- Other hospital-specific or statutory documents

These documents must not be reconstructed from memory and automatically treated as official.

The system stores registry metadata such as:

- Official form identity
- Official source
- Version
- Effective date
- Retired date
- Storage location
- File hash
- Layout review
- Clinical review
- Legal review
- Privacy review
- Records-management review
- Hospital approval
- Production approval

Controlled registry tables include:

```text
hospital_controlled_form_registry
hospital_controlled_form_versions
hospital_controlled_form_approval_events
hospital_controlled_form_instance_bindings
```

Current controlled registry seed count:

```text
15 controlled form registry items
```

At the current development stage, controlled registry items should not be interpreted as production-approved official masters unless their required approval state explicitly confirms that.

---

# Controlled Form Approval Gates

Controlled official forms may require the following approval areas:

```text
source
layout
clinical
legal
privacy
records
hospital
```

Production approval should only occur after all required gates for that document have been completed.

The form engine is designed to fail closed where production evidence is incomplete.

---

# Controlled Official PDF Storage

Controlled official master PDFs are stored separately from normal patient-generated exports.

Private bucket:

```text
controlled-hospital-forms
```

Expected path structure:

```text
<hospital_id>/<registry_id>/<controlled_version_id>/<filename>.pdf
```

Controls include:

- Private storage
- Controlled upload preparation
- Controlled upload finalisation
- SHA-256 evidence
- Append-only version model
- No normal client overwrite
- Controlled lifecycle
- Instance binding to exact master version

Controlled master PDFs should never silently change after being used for a patient form instance.

---

# Controlled Master to Patient Instance Binding

Patient form instances can be bound to the exact controlled form version used for rendering.

This provides evidence of:

- Which official master was used
- Which form version was used
- Which patient form instance was generated
- Controlled status at the time
- Relevant verification evidence

Finalisation guards are designed to prevent controlled forms from being completed without valid controlled-master evidence where required.

---

# Patient-Safe Released Forms Security

Patient Released Forms have additional security controls.

A patient should only access:

- Their own forms
- Finalised/completed forms
- Forms that were explicitly released to them
- Fields explicitly marked patient-visible
- Patient-visible attachments
- Patient-visible signatures
- Safe controlled-master verification evidence

Patient-safe responses must not expose internal controlled-document implementation data such as:

- Internal storage paths
- Internal storage IDs
- Internal controlled version IDs where not necessary
- SHA-256 hashes
- Internal approval metadata
- Internal staff-only audit information

The system includes patient-safe RPCs and field-level visibility controls for this purpose.

---

# Controlled PDF Mapping

Controlled official PDF masters can be mapped to Corvia form data.

Mapping infrastructure supports:

- Render profiles
- Field mapping keys
- Source scope
- Source key
- Static values
- Widget type
- Page number
- X/Y position
- Width/height
- Font size
- Font
- Text alignment
- Wrapping
- Maximum lines
- Checkbox values
- Prefix/suffix
- Date formatting
- Metadata
- Mapping review
- Mapping approval
- Mapping retirement

Flutter interfaces include:

```text
controlled_form_render_mapping_page.dart
controlled_form_visual_calibration_page.dart
```

Approved mappings are protected from normal mutation.

Retired mappings remain immutable.

---

# Controlled PDF Page Geometry

Controlled rendering includes an immutable per-page geometry foundation.

Geometry supports:

- MediaBox coordinates
- MediaBox dimensions
- CropBox coordinates
- CropBox dimensions
- Page rotation
- Displayed crop coordinate space
- Geometry source
- Source master SHA
- Verification metadata

Mapped fields are expected to remain within verified page bounds.

This is required for reliable exact-layout rendering.

---

# Controlled PDF Unicode Font Safety

Controlled forms include a Unicode font safety foundation.

Private font bucket:

```text
controlled-form-fonts
```

Font records can include:

- Font key
- Font name
- Family
- Style
- Format
- Private storage path
- MIME type
- Size
- SHA-256
- Licensing evidence
- Glyph-check requirements
- Approval lifecycle

Render fields can be linked to approved font assets.

A mapping requiring controlled Unicode rendering should not be approved without suitable approved font evidence.

Actual font files are private assets and must not be distributed through the repository or README.

---

# Controlled Form Rendering Runtime

The planned/runtime Edge Function is:

```text
render-controlled-form
```

The rendering architecture is intended to support:

- Controlled master retrieval
- Source-master hash verification
- Mapping manifest loading
- Page geometry
- Form data lookup
- Overlay rendering
- AcroForm handling where applicable
- Output storage
- Output lifecycle
- Export evidence
- Unicode font embedding
- Glyph validation
- Rotation/crop transforms

## Current status

The database, Flutter and security foundations are substantially implemented.

However:

```text
render-controlled-form
```

still requires the final runtime update for:

- Per-page geometry transforms
- Crop/rotation handling
- Unicode font loading
- Font embedding
- Glyph verification
- Output verification
- Final runtime regression testing

It also requires deployment by the authorised Supabase host/admin.

The normal app developer must not assume Edge Function deployment rights.

---

# Edge Functions

Existing/expected Edge Function responsibilities include:

```text
corvia-ai
render-controlled-form
```

`corvia-ai` handles AI Nurse/cloud AI routing.

`render-controlled-form` is intended to handle controlled official PDF rendering.

Do not combine every backend responsibility into one large Edge Function.

The current self-hosted Supabase environment may also contain a default/test function such as:

```text
hello
```

Do not overwrite an existing function unless the Supabase host/admin confirms that it is safe and unused.

---

# AI Nurse / Cloud AI Flow

Current AI flow:

```text
Flutter AI Nurse
→ Supabase Edge Function: corvia-ai
→ Gemini primary model
→ Groq fallback model
→ safety fallback response
```

The AI context loader can include:

- Current profile
- Patient record
- Emergency profile
- Active prescriptions
- Future appointments
- Medication reminders
- Symptom intakes
- Lab explanations
- Timeline items

AI safety rules include:

- Do not provide a medical diagnosis.
- Do not independently prescribe medication.
- Do not invent dosage changes.
- Emergency symptoms must be escalated.
- Existing medical information must be treated carefully.
- AI output must not replace qualified clinical judgement.

---

# Database Schema

The original/main executable schema is located under:

```text
Supabase/database/setup_new_server.sql
```

Additional migrations have expanded the database significantly.

## Core tables

```text
profiles
patients
doctors
appointments
prescriptions
prescription_logs
medical_records
medical_details
lab_results
incidents
incident_messages
call_sessions
call_ice_candidates
chats
messages
unread_status
subscriptions
pricing_plans
medical_aid_providers
audit_log
doctor_unavailable_slots
```

## Hospital operations

```text
hospitals
hospital_admins
departments
reception_checkins
hospital_ai_booking_requests
emergency_profiles
patient_timeline_items
ai_symptom_intakes
```

## Nursing and hospital staff

```text
hospital_nurses
nurse_shift_logs
```

Hospital-specific deployments may include additional assignment/task tables used by the Nurse workspace.

## Pharmacy

Core pharmacy infrastructure includes:

```text
pharmacists
prescription_dispenses
```

Pharmacy status changes are expected to remain hospital scoped.

## Multi-hospital structure

```text
hospital_settings
patient_hospital_links
hospital_buildings
hospital_floors
hospital_wards
ward_visitor_rules
hospital_rooms
hospital_beds
hospital_admissions
patient_bed_assignments
patient_room_transfers
bed_status_history
```

## Interhospital transfers

```text
interhospital_transfers
interhospital_transfer_documents
interhospital_transfer_status_history
interhospital_transfer_access_logs
```

## Specialist workflow

```text
specialist_requests
user_notifications
```

## Digital hospital forms

```text
hospital_form_templates
hospital_form_template_versions
hospital_form_template_fields
hospital_form_role_permissions
hospital_form_instances
hospital_form_instance_values
hospital_form_signatures
hospital_form_attachments
hospital_form_audit_events
hospital_form_break_glass_sessions
hospital_form_legal_holds
hospital_form_exports
```

## Controlled official forms

```text
hospital_controlled_form_registry
hospital_controlled_form_versions
hospital_controlled_form_approval_events
hospital_controlled_form_instance_bindings
hospital_controlled_form_render_profiles
hospital_controlled_form_render_fields
hospital_controlled_form_render_pages
hospital_controlled_form_render_font_assets
hospital_controlled_form_render_outputs
```

---

# Important RPC / Backend Functions

The project contains many hospital-specific PostgreSQL functions and RPCs.

Examples include:

```text
create_doctor_specialist_referral
assign_specialist_request
confirm_specialist_request
corvia_insert_user_notification
corvia_patient_user_id
corvia_doctor_user_id
corvia_update_dispense_status
```

Reception hospital-context helpers include:

```text
corvia_reception_departments
corvia_reception_doctors
corvia_reception_hospital_context
```

Nurse/hospital-admin helpers include:

```text
corvia_admin_assign_nurse
corvia_admin_end_nurse_assignment
corvia_admin_hospital_id
corvia_admin_hospital_nurses
corvia_admin_link_nurse
corvia_admin_unlinked_nurses
corvia_current_nurse_context
```

Multi-hospital helpers include concepts such as:

```text
corvia_mh_current_profile_id
corvia_mh_is_patient_owner
corvia_mh_is_admin_for_hospital
corvia_mh_is_staff_for_hospital
corvia_mh_role_for_hospital
corvia_mh_can_manage_structure
corvia_mh_can_manage_admissions
corvia_mh_can_manage_transfers
corvia_mh_can_access_transfer
corvia_mh_can_manage_transfer_record
```

Form-engine functions include concepts such as:

```text
corvia_form_create_template
corvia_form_create_version
corvia_form_publish_version
corvia_form_start_instance
corvia_form_save_value
corvia_form_submit_instance
corvia_form_sign_instance
corvia_form_finalize_instance
corvia_form_release_to_patient
corvia_form_add_attachment
corvia_form_start_break_glass
corvia_form_end_break_glass
corvia_form_place_legal_hold
corvia_form_log_export
```

Controlled-form functions include:

```text
corvia_controlled_instance_binding_status
corvia_controlled_patient_instance_verification
corvia_controlled_render_create_profile
corvia_controlled_render_save_field
corvia_controlled_render_save_page_geometry
corvia_controlled_render_assign_font
corvia_controlled_render_font_catalog
corvia_controlled_render_font_manifest
```

RPC names and signatures must be verified against the live database before changing Flutter service calls.

---

# Security Model

Security is based primarily on:

- Supabase Auth
- PostgreSQL Row Level Security
- Hospital membership
- Role-based access
- Patient ownership
- Staff/hospital assignment
- Controlled RPC access
- Private storage buckets
- Immutable controlled records
- Audit events
- Patient-visible field flags
- Legal hold support
- Break-glass support

Important security principles:

- Patients see only permitted own data.
- Hospital staff see hospital-scoped data relevant to their role.
- Nurses should see assigned/relevant patients only.
- Reception should not gain unrestricted clinical access.
- Pharmacists should not gain unrestricted clinical access.
- Hospital admins are hospital scoped.
- Doctors should only mutate clinical records permitted by doctor/patient relationship and RLS.
- Controlled-form internal data must not leak to patient-facing responses.
- Anonymous access to sensitive RPCs/tables must remain disabled unless intentionally required.
- Service-role credentials must never be shipped in the Flutter app.

---

# Key Files to Know

| File | Purpose |6
|------|---------|
| `lib/main.dart` | App startup |
| `lib/config/env.dart` | Typed environment accessor |
| `lib/auth/auth_gate.dart` | Post-login routing |
| `lib/auth/login.dart` | Login page |
| `lib/auth/register.dart` | Registration page |
| `lib/auth/role_choice_page.dart` | Staff/patient role choice |
| `lib/auth/biometric_lock_page.dart` | Biometric lock |
| `lib/theme/app_theme.dart` | Theme and context colour extensions |
| `lib/pages/patient/dashboard.dart` | Patient dashboard |
| `lib/pages/patient/patient_pharmacy_status_page.dart` | Patient pharmacy status |
| `lib/pages/patient/patient_transfer_status_page.dart` | Patient transfer status |
| `lib/pages/patient/specialist/specialist_request_page.dart` | Patient specialist request |
| `lib/pages/patient/report_a_doctor_page.dart` | Patient doctor-report workflow |
| `lib/pages/doctor/doctor_dashboard.dart` | Doctor dashboard |
| `lib/pages/doctor/doctor_add_patient_record.dart` | Doctor clinical record creation |
| `lib/pages/doctor/doctor_patient_records.dart` | Patient clinical record viewer/editor |
| `lib/pages/doctor/doctor_medical_records.dart` | Doctor medical-record workspace |
| `lib/pages/doctor/doctor_clinical_lab_request_sheet.dart` | Dynamic doctor lab request workflow |
| `lib/pages/doctor/doctor_specialist_referral_page.dart` | Doctor specialist referrals |
| `lib/pages/reception/reception_dashboard.dart` | Reception dashboard |
| `lib/pages/reception/specialist/reception_specialist_requests_page.dart` | Reception specialist workflow |
| `lib/pages/nurse/nurse_dashboard_page.dart` | Nurse dashboard |
| `lib/pages/pharmacist/pharmacist_dashboard_page.dart` | Pharmacist dashboard |
| `lib/pages/pharmacist/pharmacist_prescription_detail_page.dart` | Pharmacist prescription workflow |
| `lib/pages/hospital/hospital_admin_shell.dart` | Hospital admin shell |
| `lib/pages/hospital/hospital_dashboard_page.dart` | Hospital dashboard |
| `lib/pages/admin/hospital_structure_page.dart` | Hospital structure management |
| `lib/pages/admin/hospital_bed_board_page.dart` | Bed Board |
| `lib/pages/admin/hospital_admissions_page.dart` | Hospital admissions |
| `lib/pages/admin/hospital_visitors_page.dart` | Visitor management |
| `lib/pages/admin/interhospital_transfers_page.dart` | Interhospital transfers |
| `lib/pages/admin/controlled_hospital_forms_page.dart` | Controlled forms admin |
| `lib/pages/admin/controlled_form_master_viewer_page.dart` | Controlled PDF viewer |
| `lib/pages/admin/controlled_form_render_mapping_page.dart` | Controlled PDF mapping |
| `lib/pages/admin/controlled_form_visual_calibration_page.dart` | Visual calibration |
| `lib/pages/forms/dynamic_hospital_form_page.dart` | Dynamic form instance |
| `lib/pages/forms/patient_released_forms_page.dart` | Patient released forms |
| `lib/services/account_mode_service.dart` | Database-authoritative account mode access |
| `lib/services/doctor_clinical_service.dart` | Doctor clinical context, records and labs |
| `lib/services/lab_catalog_service.dart` | Dynamic lab catalogue |
| `lib/services/nurse_service.dart` | Nurse hospital/shift/workspace service |
| `lib/services/controlled_form_service.dart` | Controlled-form Flutter service |
| `lib/services/hospital_form_engine_service.dart` | Form-engine service |
| `lib/services/hospital_form_pdf_service.dart` | PDF generation/security |
| `lib/services/hospital_structure_service.dart` | Hospital structure |
| `lib/services/hospital_admission_service.dart` | Admissions |
| `lib/services/hospital_visitor_service.dart` | Visitor workflows |
| `lib/services/interhospital_transfer_service.dart` | Transfer workflows |
| `lib/services/patient_notification_service.dart` | Patient notifications |
| `lib/services/notification_service.dart` | Local medication notifications |
| `lib/services/wearable_service.dart` | Wearable data |
| `lib/widgets/patient_notification_bell.dart` | Patient notification UI |
| `Supabase/database/setup_new_server.sql` | Main/base SQL |

---

# Current Backlog Progress

The current structured backlog has progressed through the following implementation batches:

```text
Batch 1  - Auth / database-authoritative Switch Mode
Batch 2  - Appointment checked_in / no_show status support
Batch 3  - Patient + Doctor Labs
Batch 4  - Report a Doctor
Batch 5  - Reception doctor filtering + hospital context
Batch 6  - Nurse hospital linking/context/workspace
Batch 7  - Doctor clinical records, Risk Factors, Immunisations and Labs
Batch 8  - Pharmacist Settings + README
```

These implementation batches have been addressed.

Runtime regression, RLS verification and final repository-wide analysis are still required before production release.

Next unresolved implementation section:

```text
Batch 9 - Hospital Theme Consistency
```

Target hospital pages include:

```text
hospital_qr_checkins_page.dart
hospital_ai_booking_queue_page.dart
hospital_departments_page.dart
hospital_locations_page.dart
hospital_emergency_page.dart
hospital_billing_page.dart
hospital_reports_page.dart
```

---

# Remaining Work

The following work remains before Corvia should be considered production ready.

## 1. Hospital Theme Consistency

Review and align hospital-admin operational pages with the Corvia theme system.

Target pages include:

```text
hospital_qr_checkins_page.dart
hospital_ai_booking_queue_page.dart
hospital_departments_page.dart
hospital_locations_page.dart
hospital_emergency_page.dart
hospital_billing_page.dart
hospital_reports_page.dart
```

Use:

```text
CorviaColors
context.cBgPrimary
context.cBgSecondary
context.cTextPrimary
context.cTextSecondary
context.cTextMuted
context.cDivider
context.cAccentReadable
```

Avoid unnecessary hardcoded colours.

---

## 2. Patient Emergency UX + Lab Explainer Shortcut

Remaining patient UX work includes final review of:

- Emergency access/navigation
- Emergency presentation
- Lab Result Explainer shortcut/discovery
- Patient-facing error and empty states

---

## 3. First-Login Profile Bootstrap + Final Auth Verification

Verify:

- New profile creation
- First login
- Role routing
- Dual-role clinical accounts
- Hospital Admin restrictions
- Reception routing
- Pharmacist routing
- Sign-out/login cycle
- Database-authoritative role and relationship resolution

---

## 4. Full role regression testing

Test:

- Hospital Admin
- Reception
- Doctor
- Specialist
- Nurse
- Pharmacist
- Patient

Test both normal users and dual-role clinical accounts where applicable.

---

## 5. Multi-hospital regression testing

Verify:

- Hospital A cannot access Hospital B operational data.
- Admins only manage their assigned hospital.
- Staff access follows hospital context.
- Patient transfers work without breaking ownership/access.
- Admission/bed movement remains hospital scoped.
- Visitor access remains hospital scoped.
- Reception department/doctor lists remain hospital scoped.
- Nurse assignments remain hospital scoped.
- Pharmacy queue remains hospital scoped.
- Doctor clinical records use valid hospital context where required.

---

## 6. Final RLS/security review

Verify:

- Patient ownership
- Staff role scope
- Hospital scope
- Nurse assignments
- Pharmacist access
- Reception limitations
- Doctor medical-record access
- Lab-result access
- Controlled forms
- Attachments
- Signatures
- Exports
- Transfer documents
- Break-glass
- Legal holds
- Storage buckets

---

## 7. Controlled official form master onboarding

For each official controlled form:

- Obtain official source.
- Record source authority.
- Upload exact PDF.
- Calculate/verify hash.
- Record version.
- Record effective date.
- Perform layout review.
- Perform clinical review.
- Perform legal review.
- Perform privacy review.
- Perform records-management review.
- Perform hospital approval.
- Approve for production only after required gates pass.

---

## 8. Controlled PDF renderer runtime

Complete and verify:

- Geometry manifest support
- MediaBox transforms
- CropBox transforms
- Page rotation handling
- Unicode font loading
- Font embedding
- Glyph validation
- Output hash verification
- Output lifecycle
- Export logging
- Regression tests

Then provide the final Edge Function code/instructions to the authorised Supabase host/admin for deployment.

---

## 9. Controlled font assets

No production font asset should be assumed available merely because the database foundation exists.

Required:

- Approved font source
- Licensing evidence
- Private upload
- SHA-256 evidence
- Glyph coverage verification
- Mapping assignment
- Runtime renderer testing

---

## 10. Specialist workflow regression

Verify:

- Patient notifications
- Doctor referral tracking
- Appointment creation
- Rejection
- Reschedule
- Referral documentation
- Specialist assignment

---

## 11. Nurse workflow regression

Verify:

- Shifts
- Assigned patients
- Ward filtering
- Observations
- Medication rounds
- Tasks
- Escalations
- Admin assignment
- Hospital nurse link
- Active nurse context
- Settings
- Switch Mode where authorised

---

## 12. Pharmacist regression

Verify:

- Hospital queue
- Prescription verification
- Preparing status
- Ready-for-collection status
- Patient notification
- Collection confirmation
- Unable-to-dispense reason
- Timeline event
- Hospital isolation
- Pharmacy form access
- Shared Settings access
- Sign out and re-login

---

## 13. Doctor clinical regression

Verify:

- Doctor identity auto-link
- Patient selector
- Risk Factor creation
- Risk Factor editing
- Immunisation creation
- Immunisation editing
- Treatment selection
- Custom `Other` treatment
- Dynamic lab tests
- Custom `Other` lab test
- Lab order creation
- Hospital/department context
- Existing pending lab row result update
- Medical-record RLS
- Lab-result RLS

---

## 14. Wearable testing

Verify:

- Flutter wearable page
- Health-platform data
- Wear OS app
- Wearable listener
- Phone/watch communication
- Background handling
- Device disconnection
- Permission denial
- Unsupported devices

---

## 15. Warning cleanup

Final analyzer cleanup may include:

- Deprecated `withOpacity`
- Deprecated form-field `value`
- Unused imports
- Unused fields
- Unused methods
- Async context warnings
- Type-check warnings
- Protected member usage
- General style/lint findings

One previously relevant warning exists around:

```text
lib/pages/patient/patient_records.dart
```

and should be reviewed during final cleanup.

---

## 16. Production checklist

Before production:

- Android regression
- iOS regression
- Chrome/web regression
- Windows regression
- Wear OS regression
- Supabase backup
- Database migration review
- RLS test suite
- Edge Function deployment verification
- Edge Function secret review
- `.env` review
- Storage bucket review
- No service-role key in client
- No real patient data in demo accounts
- No production passwords in screenshots/issues
- Official forms approved
- Controlled mappings approved
- Security review completed
- Clinical sign-off completed
- Legal/privacy/records-management sign-off where applicable

---

# Branching and Git Rules

Primary working branch:

```text
Testing
```

Do not push directly to:

```text
Main
```

Recommended workflow:

```bash
git checkout Testing
git pull --rebase origin Testing
flutter pub get
flutter analyze
git status
git add -A
git commit -m "Your commit message"
git pull --rebase origin Testing
git push origin Testing
```

Before pushing, always check for merge markers:

```bash
git grep -n -e "^<<<<<<< " -e "^=======$" -e "^>>>>>>> "
```

A clean repository should return no unresolved merge markers.

If a rebase conflict occurs:

1. Do not blindly run `git add`.
2. Inspect the conflicting file.
3. Preserve required changes from both sides.
4. Remove all merge markers.
5. Run the marker check again.
6. Run `flutter pub get` if `pubspec.yaml` changed.
7. Run `flutter analyze`.
8. Stage resolved files.
9. Run `git rebase --continue`.
10. Push only after the rebase completes.

Avoid force-pushing shared team branches.

---

# Useful Commands

## Flutter

```bash
flutter pub get
dart format lib
flutter analyze
flutter test
flutter clean
flutter devices
# Run/build commands need explicit configuration; see supabase/scripts/ws4_local_setup.md.
# Compilation check only: this synthetic key cannot authenticate to a backend.
flutter build apk --debug --dart-define=CORVIA_ENV=local --dart-define=SUPABASE_URL=http://10.0.2.2:54321 --dart-define=SUPABASE_ANON_KEY=synthetic-build-only
```

## Git

```bash
git status
git branch
git branch --show-current
git remote -v
git fetch origin
git add -A
git commit -m "message"
git pull --rebase origin Testing
git rebase --continue
git push origin Testing
```

Conflict-marker check:

```bash
git grep -n -e "^<<<<<<< " -e "^=======$" -e "^>>>>>>> "
```

---

# Troubleshooting

| Symptom | Likely Cause | Fix |
|---------|--------------|-----|
| Login loops back to login | Profile or RLS issue | Check `profiles` and role/hospital links |
| Hospital Admin lands on patient dashboard | Incorrect role routing | Check database-authoritative account access and `hospital_admins` |
| Reception cannot see specialist requests | RLS/role issue | Check reception permissions and specialist request policies |
| Reception doctor list is wrong | Hospital/department context issue | Check `corvia_reception_hospital_context`, `corvia_reception_departments` and `corvia_reception_doctors` |
| Doctor referral fails | RPC or permission mismatch | Check referral RPC signature and RLS |
| Doctor clinical record fails | Doctor/RLS/context mismatch | Check `current_doctor_id()`, doctor profile link and `medical_records` policies |
| Doctor lab request fails | Lab RLS or context issue | Check `lab_results`, doctor ID, hospital ID and department ID |
| Specialist confirmation fails | Missing specialist/appointment data | Check assignment and confirm RPC |
| Patient notification missing | Notification insert/RLS issue | Check patient notification service/RPC |
| Pharmacist queue empty unexpectedly | Hospital/role scope issue | Check pharmacist hospital assignment and prescription data |
| Pharmacy status not updating | Dispense status/RLS issue | Check `corvia_update_dispense_status` and `prescription_dispenses` workflow |
| Pharmacist Settings missing | Old pharmacist dashboard file | Confirm current `pharmacist_dashboard_page.dart` includes `SettingsPage` |
| Nurse sees no patients | Missing assignment or hospital link | Check hospital nurse link, ward/shift assignments and current nurse context |
| Nurse dashboard cannot load | Nurse context/RLS issue | Check `corvia_current_nurse_context` and `hospital_nurses` |
| Hospital Bed Board empty | Structure/admission data missing | Check wards, rooms, beds and admissions |
| Visitor scan denied | Visitor rule/hospital mismatch | Check ward visitor policy and hospital context |
| Transfer unavailable | Access/hospital/RLS issue | Check transfer permissions and hospital links |
| Patient cannot open released form | Form not finalised/released | Check finalised status, release timestamp and patient visibility |
| Controlled form cannot finalise | Missing controlled binding | Check controlled master/version binding |
| Controlled mapping cannot approve | Geometry/font/approval evidence incomplete | Verify mapping approval prerequisites |
| Wearable communication fails | Device/emulator/permission issue | Check Wear OS connection and permissions |
| Medication notification classes unresolved | Dependencies not installed | Run `flutter pub get` and verify notification dependencies |
| Gradle Kotlin file fails after rebase | Merge markers remain | Run repository-wide conflict-marker check |
| Missing backend configuration at startup | Flutter no longer loads `.env` | Supply explicit build defines; see `supabase/scripts/ws4_local_setup.md` |
| Google sign-in fails | OAuth configuration incomplete | Check Supabase and Google callback configuration |
| Registration email fails | SMTP configuration issue | Check GoTrue SMTP / test auto-confirm policy |
| Health Connect unavailable | Device/emulator limitation | Use supported physical Android device |

---

# Security Notes

- Never commit production secrets.
- Never commit Supabase service-role keys.
- Never ship service-role credentials in Flutter.
- Never use real patient data in demo/test accounts.
- Never expose controlled-document private storage paths to patients.
- Never expose internal PDF hashes unnecessarily to patient interfaces.
- Never overwrite clinical staff roles simply to provide patient access.
- Never offer patient mode to hospital-admin-only accounts.
- Keep sensitive tables protected by RLS.
- Keep private form/storage buckets private.
- Keep controlled official masters immutable after approval/use.
- Keep audit trails append-only where required.
- Ensure patient-facing form access is released intentionally.
- Use break-glass access only where justified and audited.
- Respect legal hold restrictions.
- Treat medical information as sensitive data.
- Controlled statutory forms require official source and approval before production use.
- Test-account credentials in this README are development/demo credentials only and must not be reused in production.
- Pharmacist access must remain hospital scoped.
- Nurse access must remain assignment/hospital scoped.
- Doctor clinical writes must remain constrained by RLS and valid doctor identity.

---

# Clinical and Legal Disclaimer

Corvia Medical is software infrastructure.

The presence of a digital form, workflow, AI feature, medical field, wearable reading or clinical interface inside the application does not by itself make that feature clinically, legally or regulatorily approved.

Hospitals remain responsible for:

- Clinical governance
- Official documentation approval
- Legal approval
- Privacy compliance
- Records management
- Operational policies
- Staff authorisation
- Device suitability
- Patient consent where required
- Final production sign-off

Controlled statutory forms must use the correct official source and approved version.

AI-generated information must not replace qualified clinical judgement.

Wearable data must not automatically be treated as equivalent to certified hospital monitoring equipment unless formally validated and approved.

---

# Final Development Sequence

Current implementation progress:

```text
Batches 1-8 completed
```

Next development sequence:

```text
Batch 9
Hospital Theme Consistency

Batch 10
Patient Emergency UX + Lab Explainer Shortcut

Batch 11
First-login Profile Bootstrap + final Auth server verification

Batch 12
Final formatting, analyzer cleanup, regression testing and push
```

Final validation should include:

```bash
dart format .
flutter analyze
```

Then test:

```text
Patient
Doctor
Specialist
Nurse
Reception
Pharmacist
Hospital Admin
Dual-role clinical users
Multi-hospital separation
Chrome
Windows
Android
```

Only after the final validation should the completed work be committed and pushed to:

```text
Testing
```

---

# Licence and Credits

Proprietary software.

**Coast IT Pty (Ltd)**

Internal team use only.

Do not redistribute without authorisation.
