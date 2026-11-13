# WS4 local and deployment configuration

Slice A changes backend selection to explicit build arguments. The tracked `.env` is no longer loaded or included as a Flutter asset. It has not been deleted. Do not copy its contents into tests, notes or logs. `flutter_dotenv` remains installed for unrelated consumers; dependencies were not upgraded.

Without configuration the profile is `local` and startup fails for a missing public client key. It never falls back to the existing remote backend. This is an intentional startup compatibility change: existing run/deployment commands must supply build configuration.

For an **already provisioned isolated local Supabase backend**, use PowerShell:

```powershell
flutter run -d chrome --dart-define=CORVIA_ENV=local --dart-define=SUPABASE_URL=http://127.0.0.1:54321 --dart-define=SUPABASE_ANON_KEY=$env:CORVIA_LOCAL_PUBLIC_KEY
```

Local endpoints are restricted to loopback and Android emulator `10.0.2.2`. This command does not provision a database. The [isolated PostgreSQL contract harness](../test/backend/ws4/README.md) reconstructs selected profile/incident metadata using synthetic identities; it is not a complete Supabase backend and cannot serve the app. Local contract fakes live only in tests and are not production resources.

Testing/live must explicitly provide `CORVIA_ENV`, HTTPS `SUPABASE_URL`, matching `CORVIA_EXPECTED_BACKEND_ORIGIN` and the public client `SUPABASE_ANON_KEY`. An origin match confirms deliberate configuration, not whether that backend is deployed for Testing or contains real data. That still requires owner evidence. Do not use a service-role/secret key or a user's token. No real backend is selected by the tests/build checks here.

The optional AI service now uses `AI_SUPABASE_URL`, `AI_SUPABASE_ANON_KEY`, `AI_FUNCTION_NAME` and `CORVIA_EXPECTED_AI_ORIGIN` build arguments, with the same local/HTTPS endpoint safeguards. Missing AI configuration keeps its existing unavailable/fallback behaviour.

All optional settings also use `--dart-define`: `OAUTH_REDIRECT_URL`, `MAPTILER_KEY`, `STUN_SERVER`, `TURN_SERVER`, `TURN_USERNAME`, `TURN_CREDENTIAL`, `EMERGENCY_CANCEL_PIN`. Values compiled into Flutter are extractable; no privileged TURN or backend secrets belong here. Legacy cancellation PIN is confirmation UI only and not authorization. The next backend slice must replace legacy cancellation with a server policy.

Docker now uses Flutter 3.44.1, matching CI. Compose requires a deliberate environment selection. Existing OAuth defaults must be replaced with the target's registered callback before use. Container configuration is not deployment evidence.

Safe offline validation (cached dependencies/toolchain):

```powershell
flutter test --no-pub
flutter analyze --no-pub --no-fatal-infos --no-fatal-warnings
flutter build web --release --no-pub --dart-define=CORVIA_ENV=local --dart-define=SUPABASE_ANON_KEY=synthetic-build-only
```

The synthetic key above is deliberately unusable for a real backend. A build passing does not prove login, calls, assignments, Android or any deployed policy. Deployment requires the plan's separate integration and release checklist.

CI's debug APK likewise uses explicit local emulator configuration with a synthetic key. It is a compilation check, not a usable connected release. To test on an Android emulator against an already provisioned local Supabase backend, use:

```powershell
if ([string]::IsNullOrWhiteSpace($env:CORVIA_LOCAL_PUBLIC_KEY)) { throw 'Set the local backend public client key first.' }
flutter build apk --debug --dart-define=CORVIA_ENV=local --dart-define=SUPABASE_URL=http://10.0.2.2:54321 --dart-define=SUPABASE_ANON_KEY=$env:CORVIA_LOCAL_PUBLIC_KEY
```

Physical devices cannot reach the host through emulator loopback. Use an owner-approved HTTPS Testing endpoint with an exact expected origin; do not disable endpoint validation or point local tests at a shared database to bypass missing infrastructure. Apply the optional callback/map/TURN defines required by the feature being tested. Neither the public key nor build arguments prove backend identity or permission to write test data.
