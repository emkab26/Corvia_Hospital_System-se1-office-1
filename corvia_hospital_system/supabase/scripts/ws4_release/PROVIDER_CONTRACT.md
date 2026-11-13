# Provider boundary: demo now, verified integration later

The database currently supports a deterministic **provider demo**, not an ER24
connection. The operator explicitly selects accepted, rejected, unavailable or
unknown. The result persists with the incident and is labelled DEMO in both
workspaces. No external request is sent. Enable only through a reviewed owner
change to `operations_settings.provider_demo_enabled`; the default is false.
For the shared package the schema is `ws4_private`; for the existing owned
synthetic bootstrap it is `ws4_dev_private`.

A request uses one operation UUID. Unknown outcome cannot create another provider
request; `reconcile_provider` resolves the same simulated request. A confirmed
accepted response must be explicitly recorded complete before closure. This
models uncertainty and recovery, not ER24's real protocols or dispatch authority.

For a future real adapter, retain server-controlled authorization, stable request
identity and the separation between Corvia claim and provider acceptance. Replace
the simulation behind a server-only request/reconciliation boundary; do not let
Flutter post a desired provider outcome. The missing ER24 material must establish:

- Approved request fields/consent and purpose, credentials, sandbox and endpoints.
- Idempotency semantics and a status lookup for a lost response.
- Provider incident IDs, acceptance/rejection meanings and rate limits.
- Verified webhook signatures, replay handling and ordering/version rules.
- Cancellation, transfer, completion and support/escalation procedures.

Persist delivery intent before external work and reconcile before retrying;
provider response persistence must not depend on an open browser. Implement and
test the worker/outbox, credentials and verified callback path when that actual
contract is supplied. These pieces are deliberately not described as implemented.

Direct calling remains independent of provider status and internet-dependent
services. An uncertain or failed provider response presents the call option; the
user still chooses whether to open the device dialler. No automated emergency
calls, invented dispatch confirmations or clinical guarantees are permitted.
