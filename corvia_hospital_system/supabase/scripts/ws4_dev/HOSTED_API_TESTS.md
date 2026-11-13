# Synthetic hosted Auth/API checkpoint

Target only: `corvia-ws4-dev`, `lejaaweexxspjlmlrtfc`. The bootstrap must already
be installed. This runner is not an application, migration, ER24 integration,
production readiness check or replacement for the full local SQL regression suite.

## Run privately

Use a local PowerShell terminal in the repository, with Python 3 available:

```powershell
python test/backend/ws4/run_hosted_api_tests.py --confirm-project lejaaweexxspjlmlrtfc
```

Enter this project's publishable (or legacy anon) key, then its secret (or legacy
service-role) key at the hidden prompts. Obtain them from this project's Supabase
Settings / API Keys. **Do not paste keys in chat, commands, files, Flutter or notes.**
The process also accepts `CORVIA_WS4_PUBLIC_KEY` and `CORVIA_WS4_ADMIN_KEY` from an
already-secure process environment; hidden prompts are preferred for manual use.
Legacy key claims are a wrong-target check, not JWT signature verification.

The runner creates five synthetic Auth users with confirmed `example.invalid`
addresses and random in-memory passwords, signs them in through Supabase Auth,
checks their JWTs through `/auth/v1/user`, and inserts own patient profiles.
It sends no invitation or recovery email. Accounts/passwords are test fixtures,
not operator credentials or evidence of real email ownership. No real patient
data may be entered. The fixed API origin rejects redirects; the privileged key
is confined to Auth provisioning and cannot be used for the data checks.

It then pauses and prints the path to `build/ws4-hosted-api/<run>/provision.sql`.
Keep the terminal running. Review that exact generated file and the account UUIDs
in its non-secret report. It checks server-managed Auth provenance, the synthetic
installation marker and existing patient profiles before granting **three scoped
synthetic dispatcher memberships**, two organisations and two patient routes.
Apply only to the named owned development project as its database owner. A browser
agent must obtain action-time approval before granting these new permissions.
Confirm the transaction succeeded before typing `provisioned` in the terminal.

The runner tests patient/profile isolation, self-promotion denial, trusted dispatch
scope, three synthetic incidents at `(0,0)`, cross-organisation denial, competing
HTTP claims, same-owner retry and cancellation. Concurrent HTTP submissions do not
prove database lock contention; the separate local SQL suite verifies actual waits.

At the second pause, review and execute only this run's `revoke.sql`, which disables
the two synthetic A dispatchers. Type `revoked`. Existing JWTs must then lose their
dispatch context, claim retry and incident visibility without signing out.

## Failures and evidence

Reports and SQL live under ignored `build/ws4-hosted-api/`; credentials, passwords
and JWTs are never included. The runner makes no automatic retries or deletions.
If interrupted or a request times out, inspect `report.json` (including any pending
account email) and the actual project before retrying. A failed HTTP response or
timeout does not prove that a preceding write was rolled back. Complete review
promptly: an expired JWT while paused is an incomplete run, not a passing result.

Accounts and synthetic rows remain. Passwords are not retained after exit; further
interactive login would require owner-managed recovery/reset. No automatic cleanup
is provided. A successful report establishes this bounded Auth/API contract only;
full app startup, calls/chat, Fleet/Paramedic and ER24 still need separate checks.

The dashboard's table/function exposure summary is not a substitute for actual
authenticated requests and installed grants. Never enable broad grants merely to
make an exposure count change.

Offline verification:

```powershell
python -m unittest discover -s test/backend/ws4 -p test_hosted_api_runner.py -v
python test/backend/ws4/run_hosted_provision_tests.py --pg-bin $env:CORVIA_PG_BIN
```

The second command creates/stops a fresh loopback PostgreSQL 15 cluster and checks
generated provisioning SQL, including failed provenance and repeat refusal. Its
Auth rows are local stubs only and must never be inserted into a hosted project.

References checked 7 October 2026: [API keys](https://supabase.com/docs/guides/getting-started/api-keys),
[Auth admin create user](https://supabase.com/docs/reference/python/auth-admin-createuser).
