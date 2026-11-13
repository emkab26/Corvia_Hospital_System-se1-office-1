# Corvia payment website: server handoff

The page currently running at `http://127.0.0.1:8080` is a local preview. It is not a production payment endpoint. PayFast must reach the ITN endpoint over a public HTTPS URL before a server-confirmed payment can be recorded.

## What the server owner must provide

- A Linux server or hosting service that can run a long-lived Node 22 process or Docker container.
- A public domain such as `pay.corvia.co.za`, with DNS access.
- Public ports 80 and 443. Port 8080 stays private on `127.0.0.1`.
- Supabase URL, anon key and service-role key. The service-role key stays only in the server `.env`.
- PayFast sandbox merchant ID, merchant key and passphrase for acceptance testing.
- Access to deploy the two supplied Supabase Edge Functions.

A static FTP/cPanel upload is insufficient unless that host explicitly supports a persistent Node process and HTTPS reverse proxying. The server performs authentication, PayFast signing, ITN verification and database writes.

## Files in the handoff ZIP

- `website/`: the Node payment website, Docker configuration and this guide.
- `supabase/migrations/20261006_corvia_payfast_portal.sql`: base payment schema and RPCs.
- `supabase/migrations/20261009_corvia_payment_escalation.sql`: payment review/escalation additions.
- `supabase/functions/create-payment/index.ts`: authenticated checkout creation adapter.
- `supabase/functions/payment-review/index.ts`: authenticated review adapter.

The ZIP intentionally contains no completed `.env` file, passwords, API keys or PayFast credentials.

## 1. Prepare Supabase

Back up the database and test the changes against the test Supabase project first. Run the migration files in filename order:

1. `20261006_corvia_payfast_portal.sql`
2. `20261009_corvia_payment_escalation.sql`

Deploy only the supplied `create-payment` and `payment-review` functions for this flow. Configure these Edge Function secrets:

```text
PAYMENT_PORTAL_URL=https://pay.example.co.za
PAYMENT_ALLOWED_ORIGINS=https://your-flutter-web-origin.example
```

Use the exact HTTPS origins, without a trailing path. Do not deploy the older `create-subscription` function as part of this release.

## 2. Configure the payment server

Extract the ZIP on the server and open the `website` folder:

```sh
cp SERVER.env.example .env
```

Edit `.env` and replace every placeholder. Keep `PAYFAST_MODE=sandbox` and `PAYFAST_LIVE_ENABLED=false` until the sandbox acceptance test passes. Generate a strong, unique `PORTAL_LINK_SECRET` and keep it private.

Start the private application container:

```sh
docker compose up --build -d
curl --fail http://127.0.0.1:8080/healthz
```

The health request must return HTTP 200. `compose.yaml` binds the application to localhost so the reverse proxy is the only public entry point.

## 3. Add the public HTTPS address

Point the payment domain's DNS record to the server. Install Caddy or configure the server's existing HTTPS reverse proxy. Copy `Caddyfile.example` into the server Caddy configuration, replace the example domain, then reload Caddy.

The proxy must overwrite `X-Real-IP` with the connecting client's address, as the supplied Caddy example does. Keep `TRUSTED_CLIENT_IP_HEADER=x-real-ip` in `.env`. Never expose port 8080 directly.

Verify from a different internet connection:

```sh
curl --fail https://pay.example.co.za/healthz
```

## 4. Sandbox acceptance test

Do not call the release complete until all of these checks pass:

- The Flutter app creates a checkout for the signed-in user.
- The checkout opens on the public HTTPS payment domain.
- The Corvia user can authenticate and sees the expected plan and amount.
- PayFast sandbox accepts the payment request.
- PayFast can POST an ITN to `https://pay.example.co.za/payfast/itn`.
- A valid ITN changes the matching attempt from `pending` to the server-confirmed result.
- Refreshing or opening the return page alone cannot mark an attempt paid.
- A duplicate ITN is idempotent and does not create a second entitlement or receipt.
- A user cannot read another user's checkout or receipt.
- The receipt/payment state is visible in the Flutter app after refresh.
- Server logs contain no passwords, service-role key, checkout token, ITN payload or signed query string.

## 5. Enable live payments

Only after sandbox acceptance:

1. Replace the three PayFast values with the live merchant credentials.
2. Set `PAYFAST_MODE=live`.
3. Set `PAYFAST_LIVE_ENABLED=true`.
4. Rebuild/restart the container.
5. Make one small live transaction and confirm the ITN, database state, entitlement and receipt end to end.

Sandbox and live credentials are different. Never copy the completed production `.env` back into source control or send it by email/message.

## Release evidence to return to the Corvia team

- The final public HTTPS origin.
- A screenshot or response from `/healthz` with secrets removed.
- The successful PayFast sandbox payment reference.
- Confirmation that its ITN reached the server and the Supabase attempt became server-confirmed.
- Confirmation that the Flutter receipt/status refreshed correctly.

Until that evidence exists, describe the site as deployment-ready source code rather than a 100% verified live payment system.
