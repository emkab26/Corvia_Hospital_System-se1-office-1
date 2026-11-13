# Corvia PayFast payment portal

Implements website checkout and Corvia payment monitoring for the 13 October demo. The default is PayFast sandbox. Blood bank and EMS work are outside this implementation.

## Implemented flow

1. A customer selects an existing active ZAR plan on this website, or starts checkout from Flutter Billing.
2. The portal validates the Corvia bearer session. The database snapshots the plan name/price and derives the hospital from the patient account. Client-supplied prices and user IDs are ignored.
3. The customer receives a private, expiring checkout URL and reviews a single payment on PayFast. Monthly/yearly products buy one access period; **automatic recurring debits are not enabled**.
4. The ITN receiver checks signature, source address, merchant, reference and exact amount, stores the notification privately, and asks PayFast to validate it server to server.
5. A verified notification updates the ledger atomically, creates one receipt and grants one access period. Duplicate notifications do not extend access twice. Late cancellation/failure cannot overwrite success.
6. Patient Billing shows payment history and receipts. Hospital Billing shows its scoped monitoring queue, audit history and controlled verification action. Aged pending, mismatched, duplicate and failed attempts are visible.

The old `subscriptions` table remains intact. `CorviaSubscriptionService` checks verified payment entitlements, then existing active legacy subscriptions. The shared `SupabaseService.hasActiveSubscription()` uses this service. New payments are not inserted into unknown legacy invoice/subscription schemas; their receipts and periods have separate tables. Legacy billing statistics and invoice history remain labelled separately from the new PayFast monitor.

## Local website preview

Requires Node 22.13 or newer. The website is deliberately kept in the top-level `CORVIA_PAYMENT_WEBSITE` folder. From that folder:

On Windows, you can also double-click `START_LOCAL_WEBSITE.bat`; it starts the local preview and prints the address.

```powershell
npm run preview
```

Open `http://127.0.0.1:8080`. This mode has clearly labelled illustrative prices and disabled checkout. It does not read secrets, accept logins or simulate a successful payment. No npm install is required to run the portal; runtime code uses Node built-ins.

Flutter debug Billing now includes this local address, an open button and a read-only `/healthz` connection check. Set `PAYMENT_WEBSITE_URL` in Flutter's `.env` to override the origin. A release build requires an explicit HTTPS URL. This website address is independent of authenticated checkout URLs, which remain HTTPS-only. Health responses are public metadata with CORS enabled; checkout routes do not inherit that CORS permission.

`START_LOCAL_WEBSITE.bat` always starts a visual preview. Its sign-in and checkout button are intentionally disabled, even when valid Corvia credentials are entered. To run the configured service, copy `.env.example` to `.env`, add the required Supabase and PayFast values, and run `START_CONFIGURED_WEBSITE.bat` (or `npm start`). A real PayFast checkout still requires a public HTTPS `PORTAL_BASE_URL` so PayFast can reach the ITN endpoint.

## Configure the sandbox integration

1. Review and apply `../supabase/migrations/20261006_corvia_payfast_portal.sql` **once to the test database**. It creates new objects in a transaction and expects the existing `pricing_plans`, `profiles`, `patients` and `hospital_admins` contracts. The tests use a minimal schema fixture, not a dump of your hosted database. Confirm actual column types, role linkage and grants before deployment.
2. Copy `.env.example` to `.env` inside this directory. Fill the test Supabase URL, anon and service-role keys, your PayFast sandbox merchant ID/key/passphrase and a random `PORTAL_LINK_SECRET` of at least 32 characters. Keep this file server-side. Do not put the service key or passphrase in the Flutter `.env`, web assets or version control.
3. Set `PORTAL_BASE_URL` to the portal's public HTTPS origin. PayFast must be able to reach `/payfast/itn`; a localhost page cannot receive external notifications. Configure an HTTPS reverse proxy to the Node process. Do not log checkout/status URL query strings, login bodies or ITN payloads.
4. Run `npm start`, or `docker compose up --build -d`. Compose binds to loopback port 8080 for the reverse proxy. Docker is optional.
5. Deploy `../supabase/functions/create-payment/index.ts` and `../supabase/functions/payment-review/index.ts` to the test Edge runtime. Set `PAYMENT_PORTAL_URL` to the same HTTPS origin and `PAYMENT_ALLOWED_ORIGINS` to comma-separated exact Flutter web origins. Mobile requests without an Origin header are accepted only with a bearer token. Keep the gateway's JWT verification enabled; the portal independently checks the bearer session.
6. Confirm active `pricing_plans` entries have `code`, `name`, `description`, `price_cents`, `currency`, `billing_period`, `is_active` and `display_order`. Supported checkout amounts are R5.00 to R9,999,999.99, in ZAR. `monthly` and `yearly` grant timed access. Other billing periods create a payment receipt without inventing an access duration.
7. Rebuild Flutter and run the sandbox checklist below. Returning to the app refreshes the payment and access cards; refresh remains available manually.

`create-subscription/index.ts` was already present with misplaced Flutter test code. It has been preserved and is **not used by this new flow**. Do not deploy it as part of these payment changes; restore its intended source separately if another client needs that endpoint.

### Source-address validation behind a proxy

The portal normally uses the actual socket peer. `TRUSTED_CLIENT_IP_HEADER` may name a header such as `x-real-ip` only if your reverse proxy overwrites that header with the real source IP and the application origin is inaccessible directly. Do not forward a user-supplied IP header. Multiple/comma-separated IP values are rejected. Without this setup the proxy's own address will fail validation, keeping the payment unconfirmed. Signatures, source checks and server confirmation are also enforced in sandbox.

### Sandbox access

Sandbox receipts are always labelled as test receipts. Sandbox payments do not grant application access by default. To rehearse access activation **on an isolated test database only**, an administrator can run:

```sql
update public.corvia_payment_settings
set allow_sandbox_access = true
where singleton;
```

Never enable this on a production database. Live and sandbox records/provider IDs are separated; the portal rejects records from the other environment. Live processing additionally requires both `PAYFAST_MODE=live` and `PAYFAST_LIVE_ENABLED=true`, live merchant configuration and HTTPS. None of these live changes has been made.

## Monitoring and reconciliation

Hospital staff can read attempts belonging to their hospital, inspect an immutable client-visible event history and use **Verify with PayFast**. Customers can only read their own attempts; neither role can directly edit payment states, receipts, raw notifications or access periods.

Verification replays the stored, signed, source-checked notification through PayFast's validation endpoint, then applies it transactionally. This covers transient provider/database failures after receipt. If no notification arrived, the attempt is flagged with `no_notification_request_payfast_itn_resend`; request a resend from the merchant ITN dashboard. Aged pending attempts appear under **Needs review** after 30 minutes. No browser action or staff status edit can substitute for provider confirmation.

This implementation provides controlled reconciliation, not a scheduled polling service. Refund execution/status lookup, tax invoices, outbound receipt email and automatic recurring billing are not enabled. A receipt is available in the website and Flutter only after payment confirmation. Handle provider refunds with the finance owner until a verified refund integration and entitlement-revocation policy are agreed. Do not assume a historical payment confirmation proves no later refund occurred.

The monitor pages through 100 attempts at a time in scope; search/status filters apply to the current page. The additive `20261009_corvia_payment_escalation.sql` upgrade adds staff-only billing review/resolve actions with audit reasons, without changing provider state or entitlements. Resolution means a staff follow-up was resolved, not that the provider confirmed payment. Payment links are bearer capabilities: they expire after 24 hours and reveal only the payment summary/receipt. New checkout submission pages expire after 30 minutes; signed late ITNs are still processed.

## Tests

```powershell
npm ci
npm test
```

Only the tests require the pinned PGlite development dependency. Tests execute the actual migration in an isolated PostgreSQL engine and exercise price snapshots, idempotency, duplicate receipts/access, RLS, grants, failed transitions and sandbox gating. HTTP tests exercise real local routes with mocked Supabase/provider services. Edge adapter tests execute the handlers under a Node TypeScript harness; they do not replace deployment testing in Deno.

From the repository root:

```powershell
flutter test --no-pub test/corvia_payment_test.dart
dart analyze lib/services/corvia_payfast_service.dart lib/services/corvia_subscription_service.dart lib/services/supabase_service.dart lib/widgets/corvia_subscription_card.dart lib/widgets/corvia_payment_monitor.dart lib/pages/patient/billing.dart lib/pages/hospital/hospital_billing_page.dart test/corvia_payment_test.dart
```

### Hosted sandbox acceptance (still required)

Local verification on 7 October 2026: 24 Node/SQL/Edge-handler tests passed; seven Flutter payment/subscription tests passed; focused Dart analysis reported no issues. The website preview was checked in the browser, including plan selection, a narrow viewport without horizontal overflow, and no browser console errors. No hosted migration, Edge deployment or genuine PayFast transaction was performed in this change.

- [ ] Apply the migration against the actual test schema; verify hospital membership and inactive-user boundaries with real test roles.
- [ ] Configure public HTTPS, proxy source-IP handling, Edge runtime and merchant sandbox settings.
- [ ] Pay from the website and Flutter; compare amount/reference and see pending become confirmed after a genuine ITN.
- [ ] Return or cancel before ITN; confirm the browser alone cannot activate access.
- [ ] Resend an ITN; confirm a single receipt and unchanged access expiry.
- [ ] Exercise mismatch, delayed confirmation and provider outage; use the review action and inspect events.
- [ ] Test customer A/customer B and hospital A/hospital B access in the deployed environment.
- [ ] Verify receipts, app-resume refresh, expiry and sandbox access policy on the intended demo device.

## References

Protocol choices follow the [PayFast custom integration documentation](https://developers.payfast.co.za/?capcode=xMzF): prescribed checkout field order, PHP-style encoding, all-field ITN signatures and server confirmation. Source ranges were checked against the [PayFast network documentation](https://developers.payfast.co.za/) on 7 October 2026; DNS supplements the published ranges. Recheck provider documentation before a production rollout.
