# ER24 phone handoff: interim WS4 route

## Current MVP: phone-first entry

The patient Emergency tile now opens phone assistance with one tap. The default
`EmergencyPage` does not initialize DispatchCallController, WebRTC, incident
creation, chat, a map, or location/microphone permission requests. The existing
Corvia dispatch page remains intact behind the compile-time flag
`--dart-define=CORVIA_EMERGENCY_DISPATCH_ENABLED=true` (default false).
That opt-in also restores the dashboard's existing hold gesture. This is a UI
mode, not an authorization mechanism or an ER24 integration switch. Only enable
dispatch after validating its backend, permissions, routing and calling services.
ER24 API access will still require a separately implemented and verified adapter.

Call ER24 uses the same external `tel:084124` handoff. Optional address/landmark
and what-happened fields stay in page memory; they are not written to Supabase,
sent to ER24, logged or retained when the page is disposed. They are caller aids,
not submitted incidents. Screen copy states this explicitly. Existing patient
records are not fetched for this mode. Durable incident capture, consent,
retention and routing remain a separate design decision, not an implicit feature.

Get my location is explicitly user-triggered and reuses LocationService. The
whole lookup is bounded to 15 seconds, including permission waits. Unavailable,
invalid, stale (older than two minutes), or implausibly future-dated fixes are
not displayed. A valid snapshot shows its timestamp and estimated accuracy;
no continuous tracking or map/geocoding request is started. Denial, timeout and
late results never gate the phone button; the caller can give a manual address.
The app does not read SIM/device telephone numbers or infer that a call connected.

Rebuild to change modes; there is no patient-facing toggle. Flutter defaults to
phone-first when the define is absent, including existing Docker/CI builds.
Do not add this flag only to `.env`: Flutter uses compile-time defines.

## Earlier implementation checkpoint

7 October 2026. Jandre reports that the team has contacted ER24 but has not yet
received a response or integration access. The patient emergency screen now has
a separate **Call ER24** card, above the existing Corvia incident/call controls.

Number verified on [ER24's official contact page](https://www.er24.co.za/en/corporate/contact.html):
**084 124**, its national emergency contact centre. This is a South African short
number, not a verified international number. No invented country-code conversion
or ER24 partnership/acceptance claim is made.

The button passes only `tel:084124` to the device's external phone handler through
the existing url_launcher dependency. It does not place a WebRTC call, send patient
information to ER24, record a successful call, modify an incident, claim a case or
confirm ambulance dispatch. The user completes the call in their phone app and
gives their location/details to the operator. Normal telephony/device availability
is required. Corvia cannot verify whether the call connected or was answered.

The number remains visible/selectable if no phone handler exists or opening it
fails. Repeated taps while opening are suppressed. No microphone/location/new
phone permission is requested by this card. It remains usable on the emergency
screen while Corvia incident creation or location access fails. Existing app
navigation/authentication still determines access to that screen; this change
does not add a signed-out emergency entry point or certify offline app startup.

Files: `lib/widgets/emergency_phone_card.dart`, mounted in
`lib/pages/patient/emergency.dart`. The widget has no backend/controller dependency.
It is not yet mounted in the operator dashboard and does not implement an audited
operator/provider handover workflow. ER24 integration remains blocked on official
access and agreed contracts; WS5/WS6 integration remains a separate dependency.

## Verification before release

Automated tests replace the phone platform channel: no real emergency number is
called. Cover launch success/failure/exception, duplicate taps, screen disposal,
narrow layout with large text, and presence while incident setup is unavailable.

On an authorised physical device, open the emergency screen with failed incident
setup/location denied and verify the card remains visible and enabled. Tap once,
confirm the phone handler contains **084124**, then cancel without calling. Also
verify desktop/browser behaviour with no phone handler; the manual number must
remain usable. Do not place a test call to an emergency service. An agreed ER24
non-emergency test procedure is needed for any real integration exercise.

Platform documentation: [url_launcher](https://pub.dev/packages/url_launcher).
`launchUrl` is attempted directly with failure handling; no unreliable preflight
`canLaunchUrl` gate or extra package/manifest permission was added.

This fallback is an interim contact feature, not complete WS4 readiness or proof
of clinical, privacy, operational or legal approval.
