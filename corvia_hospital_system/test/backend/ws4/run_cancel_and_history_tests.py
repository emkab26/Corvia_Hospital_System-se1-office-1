"""Verify additive cancellation/history on a NEW isolated PostgreSQL 15 cluster.

Accepts no hosted URL or existing data directory. SQL auth.uid stubs do not
verify real Supabase Auth, JWT, PostgREST, Flutter or operational integration.
"""
import argparse
import concurrent.futures
import datetime
import hashlib
import json
from pathlib import Path
import subprocess
import time
import uuid

from run_tests import Database, FLAGS, uid
from run_patient_intake_tests import REPO, CORE, DELTA as INTAKE, A, B, operation, request, require

DELTA = REPO / 'supabase/scripts/ws4_dev/003_cancel_and_history.sql'


def cancel(number, version=1):
    return f"public.corvia_patient_cancel_emergency('{operation(number)}',{version})"


def run(db, results):
    def record(name, passed, **evidence):
        results.append({'name': name, 'passed': passed, **evidence})
        print(('PASS ' if passed else 'FAIL ') + name, flush=True)
        if not passed:
            raise AssertionError(name + ': ' + str(evidence))

    def case(name, sql, actor=1, state=None, expected='t', rollback=True):
        result = db.sql(sql, actor=actor, role='anon' if actor == 0 else 'authenticated',
                        rollback=rollback)
        passed = (result.returncode != 0 and f'{state}:' in result.stderr) if state else (
            result.returncode == 0 and result.stdout.strip() == expected)
        record(name, passed, sqlstate_expected=state,
               stdout=result.stdout.strip(), stderr=result.stderr.strip())

    def create(number, actor=1):
        return json.loads(require(db.sql(f'SELECT {request(number)};', actor=actor)))['incident_id']

    def race(name, holder_sql, waiter_sql, holder_actor, waiter_actor, state=None, expect_wait=True):
        # Reuse the existing 002 loopback Database and observed-lock test pattern.
        command = [db.exe('psql'), '-X', '-qAt', '-v', 'ON_ERROR_STOP=1',
                   '-h', '127.0.0.1', '-p', str(db.port), '-U', 'postgres', '-d', 'postgres']
        proc = subprocess.Popen(command, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                stderr=subprocess.PIPE, env=db.env, text=True,
                                encoding='utf-8', creationflags=FLAGS)
        try:
            actor_sql = (f"SET ROLE authenticated; SET request.jwt.claim.sub='{uid(holder_actor)}';"
                         if holder_actor else '')
            proc.stdin.write(f"SET statement_timeout='15s'; {actor_sql} BEGIN; {holder_sql}\n\\echo LOCK_HELD\n")
            proc.stdin.flush()
            with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
                def ready():
                    while True:
                        line = proc.stdout.readline()
                        if not line:
                            raise RuntimeError('Lock holder exited')
                        if line.strip() == 'LOCK_HELD':
                            return
                pool.submit(ready).result(timeout=10)
                future = pool.submit(db.sql, "SET application_name='ws4_cancel_history_waiter'; " + waiter_sql,
                                     waiter_actor)
                deadline = time.monotonic() + 5
                waiting = False
                while time.monotonic() < deadline:
                    if require(db.sql("SELECT EXISTS(SELECT 1 FROM pg_stat_activity WHERE "
                                      "application_name='ws4_cancel_history_waiter' AND wait_event_type='Lock');")) == 't':
                        waiting = True
                        break
                    if future.done():
                        break
                    time.sleep(.05)
                proc.stdin.write('COMMIT;\n\\q\n')
                proc.stdin.flush()
                proc.wait(timeout=10)
                result = future.result(timeout=12)
                passed = waiting == expect_wait and proc.returncode == 0 and (
                    (result.returncode != 0 and f'{state}:' in result.stderr)
                    if state else result.returncode == 0)
                record(name, passed, observed_lock_wait=waiting,
                       stdout=result.stdout.strip(), stderr=result.stderr.strip())
        finally:
            if proc.poll() is None:
                proc.kill()
                proc.wait(timeout=5)
            for stream in (proc.stdin, proc.stdout, proc.stderr):
                stream.close()

    case('delta refuses absent prerequisite markers', DELTA.read_text(encoding='utf-8'),
         actor=None, state='P0001', rollback=False)
    require(db.sql("""
      CREATE ROLE anon NOLOGIN;
      CREATE ROLE authenticated NOLOGIN;
      CREATE ROLE service_role NOLOGIN BYPASSRLS;
      CREATE SCHEMA auth;
      CREATE TABLE auth.users(id uuid PRIMARY KEY);
      CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE AS $$
        SELECT nullif(current_setting('request.jwt.claim.sub',true),'')::uuid;
      $$;
      GRANT USAGE ON SCHEMA auth,public TO anon,authenticated,service_role;
      ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO anon,authenticated,service_role;
      ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON FUNCTIONS TO anon,authenticated,service_role;
      ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO anon,authenticated,service_role;
    """))
    require(db.sql(CORE.read_text(encoding='utf-8')))
    case('delta refuses missing intake marker', DELTA.read_text(encoding='utf-8'),
         actor=None, state='P0001', rollback=False)
    require(db.sql(INTAKE.read_text(encoding='utf-8')))
    require(db.sql(f"""
      INSERT INTO auth.users SELECT ('00000000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid
        FROM generate_series(1,7) n;
      INSERT INTO public.profiles(user_id,role,is_active)
        SELECT id,CASE WHEN id IN ('{uid(3)}','{uid(6)}','{uid(7)}') THEN 'dispatcher' ELSE 'patient' END,
          id<>'{uid(4)}' FROM auth.users;
      INSERT INTO ws4_dev_private.organisations VALUES ('{A}','Synthetic Cancel A'),('{B}','Synthetic Cancel B');
      INSERT INTO ws4_dev_private.patient_routes VALUES
        ('{uid(1)}','{A}'),('{uid(2)}','{B}'),('{uid(3)}','{A}'),('{uid(4)}','{A}');
      INSERT INTO ws4_dev_private.memberships VALUES
        ('{uid(3)}','{A}','dispatcher',true),('{uid(6)}','{B}','dispatcher',true),
        ('{uid(7)}','{A}','dispatcher',false);
      ALTER DEFAULT PRIVILEGES IN SCHEMA ws4_dev_private GRANT ALL ON TABLES TO anon,authenticated,service_role;
      ALTER DEFAULT PRIVILEGES IN SCHEMA ws4_dev_private GRANT ALL ON FUNCTIONS TO anon,authenticated,service_role;
    """))
    case('ordinary patient cannot install delta', DELTA.read_text(encoding='utf-8'),
         actor=1, state='P0001', rollback=False)
    require(db.sql(DELTA.read_text(encoding='utf-8')))
    case('reapplication refuses without resetting records', DELTA.read_text(encoding='utf-8'),
         actor=None, state='P0001', rollback=False)
    case('dispatch capability includes all existing tokens plus history',
         "SELECT public.corvia_dispatch_access_context()->'capabilities'="
         "'[\"read_incidents\",\"claim_incident\",\"read_intake_details\",\"read_incident_history\"]'::jsonb;", actor=3)
    case('ordinary patient cannot acquire dispatch capability',
         'SELECT public.corvia_dispatch_access_context();', state='42501')
    incident = create(1)

    for actor in (0, 2, 3, 4, 5):
        case(f'cancel denies unauthorized actor {actor}', f'SELECT {cancel(1)};', actor=actor, state='42501')
    for actor in (0, 2, 4, 5, 6, 7):
        case(f'history denies unauthorized actor {actor}',
             f'SELECT public.corvia_incident_history({incident});', actor=actor, state='42501')
    for expression in (cancel(1), f'public.corvia_incident_history({incident})'):
        case('authenticated function requires nonempty auth identity: ' + expression.split('(')[0],
             f'SET ROLE authenticated; SELECT {expression};', actor=None, state='42501')
        case('service role denied: ' + expression.split('(')[0],
             f"SET ROLE service_role; SET request.jwt.claim.sub='{uid(1)}'; SELECT {expression};",
             actor=None, state='42501')
    for table in ('patient_intake_operations', 'incident_events', 'cancel_and_history_installation'):
        case('private table read denied: ' + table,
             f'SELECT * FROM ws4_dev_private.{table};', state='42501')
    case('private audit insert denied',
         f"INSERT INTO ws4_dev_private.incident_events(incident_id,version,event_type,status) VALUES ({incident},2,'cancelled','cancelled');",
         state='42501')
    case('cancel ledger cannot be forged',
         f"UPDATE ws4_dev_private.patient_intake_operations SET cancel_expected_version=1 WHERE operation_id='{operation(1)}';",
         state='42501')
    for value in ('NULL', '0', '-1'):
        case('invalid expected version rejected: ' + value,
             f'SELECT {cancel(1, value)};', state='22023')
    for value in ('NULL', "'00000000-0000-0000-0000-000000000000'"):
        case('invalid operation identity rejected: ' + value,
             f'SELECT public.corvia_patient_cancel_emergency({value},1);', state='22023')
    case('unknown cancellation identity denied', f'SELECT {cancel(999)};', state='42501')
    case('unknown history incident denied', 'SELECT public.corvia_incident_history(999999);', state='42501')
    case('null history incident denied', 'SELECT public.corvia_incident_history(NULL);', state='42501')
    case('stale expected version conflicts', f'SELECT {cancel(1, 2)};', state='P0001')
    case('stale conflict leaves state and ledger untouched',
         f"SELECT i.status='pending' AND i.version=1 AND o.cancel_expected_version IS NULL "
         f"FROM public.incidents i JOIN ws4_dev_private.patient_intake_operations o ON o.incident_id=i.id WHERE i.id={incident};", actor=None)

    cancelled = json.loads(require(db.sql(f'SELECT {cancel(1)};', actor=1)))
    expected_keys = {'operation_id', 'incident_id', 'user_id', 'status', 'version', 'created_at',
                     'latitude', 'longitude', 'location_source', 'location_accuracy', 'location_captured_at',
                     'address', 'details'}
    record('cancel returns unchanged 13-key intake contract with string identity/version',
           set(cancelled) == expected_keys and cancelled['operation_id'] == operation(1)
           and cancelled['incident_id'] == incident and isinstance(cancelled['incident_id'], str)
           and cancelled['user_id'] == uid(1) and cancelled['status'] == 'cancelled'
           and cancelled['version'] == '2')
    replay = json.loads(require(db.sql(f'SELECT {cancel(1)};', actor=1)))
    record('same cancellation retry returns identical current result', replay == cancelled)
    case('changed expected version under recorded cancellation rejected', f'SELECT {cancel(1, 2)};', state='22023')
    case('cancel/retry persist one version increment and one actor/time event', f"""
      SELECT (SELECT version=2 AND status='cancelled' FROM public.incidents WHERE id={incident})
        AND (SELECT cancel_expected_version=1 FROM ws4_dev_private.patient_intake_operations WHERE incident_id={incident})
        AND (SELECT count(*)=2 FROM ws4_dev_private.incident_events WHERE incident_id={incident})
        AND EXISTS(SELECT 1 FROM ws4_dev_private.incident_events WHERE incident_id={incident}
          AND version=2 AND event_type='cancelled' AND previous_status='pending' AND status='cancelled'
          AND actor_user_id='{uid(1)}' AND recorded_at IS NOT NULL);
    """, actor=None)
    case('existing request lookup reconciles committed cancellation',
         f"SELECT public.corvia_patient_request_status('{operation(1)}')->>'status'='cancelled';")
    case('existing creation retry returns current cancelled record',
         f"SELECT {request(1)}->>'status'='cancelled';")

    history = json.loads(require(db.sql(f'SELECT public.corvia_incident_history({incident});', actor=1)))
    event_keys = {'version', 'event_type', 'recorded_at', 'status', 'previous_status'}
    record('history is exact ordered redacted string-ID event contract',
           set(history) == {'incident_id', 'events'} and history['incident_id'] == incident
           and len(history['events']) == 2 and all(set(event) == event_keys for event in history['events'])
           and [event['version'] for event in history['events']] == ['1', '2']
           and [event['event_type'] for event in history['events']] == ['created', 'cancelled']
           and [event['status'] for event in history['events']] == ['pending', 'cancelled']
           and [event['previous_status'] for event in history['events']] == [None, 'pending']
           and all(event['recorded_at'].endswith('+00:00') for event in history['events']))
    dispatch_history = json.loads(require(db.sql(f'SELECT public.corvia_incident_history({incident});', actor=3)))
    record('active in-scope dispatcher sees same redacted persisted history', history == dispatch_history)
    case('history values match stored audit fields and timestamp instants', f"""
      SET TimeZone='Africa/Johannesburg';
      SET request.jwt.claim.sub='{uid(1)}';
      SELECT count(*)=2 AND bool_and(
        j->>'version'=e.version::text AND j->>'event_type'=e.event_type
        AND (j->>'recorded_at')::timestamptz=e.recorded_at AND j->>'status'=e.status
        AND (j->>'previous_status') IS NOT DISTINCT FROM e.previous_status)
      FROM jsonb_array_elements(public.corvia_incident_history({incident})->'events') j
      JOIN ws4_dev_private.incident_events e ON e.incident_id={incident} AND e.version=(j->>'version')::bigint;
    """, actor=None)
    case('history UTC output is independent of caller timezone',
         f"SET TimeZone='Africa/Johannesburg'; SELECT public.corvia_incident_history({incident})->'events'->0->>'recorded_at' LIKE '%+00:00';")
    case('own route mismatch explicitly denies history and cancellation', f"""
      UPDATE ws4_dev_private.patient_routes SET organisation_id='{B}' WHERE user_id='{uid(1)}';
      SET ROLE authenticated; SET request.jwt.claim.sub='{uid(1)}';
      SELECT public.corvia_incident_history({incident});
    """, actor=None, state='42501')
    case('own route mismatch also denies cancellation retry', f"""
      UPDATE ws4_dev_private.patient_routes SET organisation_id='{B}' WHERE user_id='{uid(1)}';
      SET ROLE authenticated; SET request.jwt.claim.sub='{uid(1)}'; SELECT {cancel(1)};
    """, actor=None, state='42501')

    claimed = create(2)
    case('existing claim eight-key contract remains usable',
         f'SELECT count(*)=8 FROM jsonb_object_keys(public.corvia_dispatch_accept_incident({claimed}));', actor=3, rollback=False)
    case('claimed incident cannot be cancelled even with current version', f'SELECT {cancel(2, 2)};', state='P0001')
    case('claimed timeline retains creation and claim',
         f"SELECT public.corvia_incident_history({claimed})->'events'->1->>'event_type'='claimed';")
    require(db.sql(f"UPDATE public.incidents SET status='resolved' WHERE id={claimed};"))
    case('existing resolved audit row is projected without fabricated intermediate event',
         f"WITH h AS (SELECT public.corvia_incident_history({claimed})->'events' e) "
         "SELECT jsonb_array_length(e)=3 AND e->2->>'event_type'='resolved' "
         "AND e->2->>'previous_status'='in_progress' FROM h;")
    case('resolved incident cannot be cancelled', f'SELECT {cancel(2, 3)};', state='P0001')
    legacy = create(3)
    require(db.sql(f"UPDATE public.incidents SET status='cancelled' WHERE id={legacy};", actor=1))
    case('legacy direct cancellation is preserved but not fabricated as command replay',
         f'SELECT {cancel(3)};', state='P0001')
    case('lookup recovers cancellation done through legacy path',
         f"SELECT public.corvia_patient_request_status('{operation(3)}')->>'status'='cancelled';")
    case('direct cancellation after claim remains denied',
         f"UPDATE public.incidents SET status='cancelled' WHERE id={claimed};", state='42501')

    # Test the projection against synthetic private rows; no lifecycle transition
    # API is introduced. These fixture-only mutations are rolled back.
    case('empty persisted history fails instead of inventing creation', f"""
      DELETE FROM ws4_dev_private.incident_events WHERE incident_id={incident};
      SET ROLE authenticated; SET request.jwt.claim.sub='{uid(1)}';
      SELECT public.corvia_incident_history({incident});
    """, actor=None, state='P0001')
    for total, state in ((100, None), (101, 'P0001')):
        case(f'history explicit event bound: {total}', f"""
          INSERT INTO ws4_dev_private.incident_events(incident_id,version,event_type,previous_status,status)
          SELECT {incident},n,'cancelled','pending','cancelled' FROM generate_series(3,{total}) n;
          SET ROLE authenticated; SET request.jwt.claim.sub='{uid(1)}';
          SELECT jsonb_array_length(public.corvia_incident_history({incident})->'events')=100;
        """, actor=None, state=state)
    huge = '9007199254740993'
    case('history preserves bigint ID and version beyond JavaScript exact range', f"""
      INSERT INTO public.incidents(id,user_id,latitude,longitude,organisation_id,version)
        OVERRIDING SYSTEM VALUE VALUES ({huge},'{uid(1)}',0,0,'{A}',{huge});
      SET ROLE authenticated; SET request.jwt.claim.sub='{uid(1)}';
      WITH h AS (SELECT public.corvia_incident_history({huge}) j)
      SELECT jsonb_typeof(j->'incident_id')='string' AND j->>'incident_id'='{huge}'
        AND jsonb_typeof(j->'events'->0->'version')='string' AND j->'events'->0->>'version'='{huge}' FROM h;
    """, actor=None)

    rollback_incident = create(4)
    require(db.sql("""
      CREATE FUNCTION ws4_dev_private.fail_cancel_audit() RETURNS trigger LANGUAGE plpgsql AS $$
      BEGIN RAISE EXCEPTION 'Injected test audit failure'; END $$;
      CREATE TRIGGER fail_cancel_audit BEFORE INSERT ON ws4_dev_private.incident_events
      FOR EACH ROW EXECUTE FUNCTION ws4_dev_private.fail_cancel_audit();
    """))
    case('audit insertion failure aborts cancellation', f'SELECT {cancel(4)};', state='P0001', rollback=False)
    case('audit failure rolls back ledger, incident and event together', f"""
      SELECT (SELECT status='pending' AND version=1 FROM public.incidents WHERE id={rollback_incident})
        AND (SELECT cancel_expected_version IS NULL FROM ws4_dev_private.patient_intake_operations WHERE incident_id={rollback_incident})
        AND (SELECT count(*)=1 FROM ws4_dev_private.incident_events WHERE incident_id={rollback_incident});
    """, actor=None)
    require(db.sql('DROP TRIGGER fail_cancel_audit ON ws4_dev_private.incident_events;'))
    case('outer transaction failure aborts cancellation',
         f'BEGIN; SELECT {cancel(4)}; SELECT 1/0;', state='22012', rollback=False)
    case('outer rollback leaves cancellation identity unused',
         f'SELECT cancel_expected_version IS NULL FROM ws4_dev_private.patient_intake_operations WHERE incident_id={rollback_incident};', actor=None)
    case('safe retry after rollback can cancel', f"SELECT {cancel(4)}->>'status'='cancelled';")

    cancel_winner = create(10)
    race('cancel first blocks then defeats claim', f'SELECT {cancel(10)};',
         f'SELECT public.corvia_dispatch_accept_incident({cancel_winner});', 1, 3, state='P0001')
    claim_winner = create(11)
    race('claim first blocks then defeats cancel',
         f'SELECT public.corvia_dispatch_accept_incident({claim_winner});', f'SELECT {cancel(11)};', 3, 1, state='P0001')
    case('claim/cancel races each leave exactly winner event and version', f"""
      SELECT (SELECT status='cancelled' AND version=2 FROM public.incidents WHERE id={cancel_winner})
        AND (SELECT status='in_progress' AND version=2 FROM public.incidents WHERE id={claim_winner})
        AND (SELECT count(*)=4 FROM ws4_dev_private.incident_events WHERE incident_id IN ({cancel_winner},{claim_winner}))
        AND (SELECT cancel_expected_version IS NULL FROM ws4_dev_private.patient_intake_operations WHERE incident_id={claim_winner});
    """, actor=None)
    parallel = create(12)
    race('parallel identical cancellations serialize into one success',
         f'SELECT {cancel(12)};', f'SELECT {cancel(12)};', 1, 1)
    case('parallel cancellations produce no duplicate event/version',
         f'SELECT count(*)=2 AND max(version)=2 FROM ws4_dev_private.incident_events WHERE incident_id={parallel};', actor=None)
    create(13)
    race('parallel changed-version cancellation waits then fails',
         f'SELECT {cancel(13)};', f'SELECT {cancel(13, 2)};', 1, 1, state='22023')
    history_wait = create(14)
    race('out-of-scope history cannot wait on or acquire another incident lock',
         f'SELECT 1 FROM public.incidents WHERE id={history_wait} FOR UPDATE;',
         f'SELECT public.corvia_incident_history({history_wait});', 1, 2, state='42501', expect_wait=False)
    race('history waits for cancellation commit and reads both persisted events',
         f'SELECT {cancel(14)};', f"""DO $$ BEGIN
           IF public.corvia_incident_history({history_wait})->'events'->1->>'event_type' IS DISTINCT FROM 'cancelled'
             THEN RAISE EXCEPTION 'History missed committed cancellation'; END IF;
         END $$;""", 1, 1)

    create(20)
    race('profile deactivation first denies blocked cancellation',
         f"UPDATE public.profiles SET is_active=false WHERE user_id='{uid(1)}';", f'SELECT {cancel(20)};', None, 1, state='42501')
    require(db.sql(f"UPDATE public.profiles SET is_active=true WHERE user_id='{uid(1)}';"))
    create(21)
    race('cancellation first holds profile until commit', f'SELECT {cancel(21)};',
         f"UPDATE public.profiles SET is_active=false WHERE user_id='{uid(1)}';", 1, None)
    case('revoked patient cannot replay cancellation', f'SELECT {cancel(21)};', state='42501')
    case('revoked patient cannot view former history', f'SELECT public.corvia_incident_history({incident});', state='42501')
    require(db.sql(f"UPDATE public.profiles SET is_active=true WHERE user_id='{uid(1)}';"))
    create(22)
    race('route change first denies blocked cancellation',
         f"UPDATE ws4_dev_private.patient_routes SET organisation_id='{B}' WHERE user_id='{uid(1)}';",
         f'SELECT {cancel(22)};', None, 1, state='42501')
    require(db.sql(f"UPDATE ws4_dev_private.patient_routes SET organisation_id='{A}' WHERE user_id='{uid(1)}';"))
    create(23)
    race('cancellation first holds route until commit', f'SELECT {cancel(23)};',
         f"DELETE FROM ws4_dev_private.patient_routes WHERE user_id='{uid(1)}';", 1, None)
    case('removed route denies cancellation replay', f'SELECT {cancel(23)};', state='42501')
    require(db.sql(f"INSERT INTO ws4_dev_private.patient_routes VALUES ('{uid(1)}','{A}');"))
    race('route deletion first denies blocked patient history',
         f"DELETE FROM ws4_dev_private.patient_routes WHERE user_id='{uid(1)}';",
         f'SELECT public.corvia_incident_history({incident});', None, 1, state='42501')
    require(db.sql(f"INSERT INTO ws4_dev_private.patient_routes VALUES ('{uid(1)}','{A}');"))
    race('patient history holds route until read transaction commits',
         f'SELECT public.corvia_incident_history({incident});',
         f"UPDATE ws4_dev_private.patient_routes SET organisation_id='{B}' WHERE user_id='{uid(1)}';", 1, None)
    case('changed route denies later history', f'SELECT public.corvia_incident_history({incident});', state='42501')
    require(db.sql(f"UPDATE ws4_dev_private.patient_routes SET organisation_id='{A}' WHERE user_id='{uid(1)}';"))
    race('membership revocation first denies blocked dispatch history',
         f"UPDATE ws4_dev_private.memberships SET active=false WHERE user_id='{uid(3)}';",
         f'SELECT public.corvia_incident_history({incident});', None, 3, state='42501')
    require(db.sql(f"UPDATE ws4_dev_private.memberships SET active=true WHERE user_id='{uid(3)}';"))
    race('dispatch history holds membership until read transaction commits',
         f'SELECT public.corvia_incident_history({incident});',
         f"UPDATE ws4_dev_private.memberships SET active=false WHERE user_id='{uid(3)}';", 3, None)
    case('revoked membership denies subsequent history', f'SELECT public.corvia_incident_history({incident});', actor=3, state='42501')
    require(db.sql(f"UPDATE ws4_dev_private.memberships SET active=true WHERE user_id='{uid(3)}';"))
    race('dispatch profile deactivation first denies blocked history',
         f"UPDATE public.profiles SET is_active=false WHERE user_id='{uid(3)}';",
         f'SELECT public.corvia_incident_history({incident});', None, 3, state='42501')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--pg-bin', type=Path, required=True)
    args = parser.parse_args()
    work = REPO / 'build/ws4-cancel-history-db' / uuid.uuid4().hex
    work.mkdir(parents=True, exist_ok=False)
    db = Database(args.pg_bin.resolve(), work)
    results = []
    report = {'scope': 'ADDITIVE SYNTHETIC CANCEL/HISTORY SQL ONLY; no hosted/Auth API verification',
              'started_at': datetime.datetime.now(datetime.timezone.utc).isoformat(), 'results': results,
              'core_sha256': hashlib.sha256(CORE.read_bytes()).hexdigest(),
              'intake_sha256': hashlib.sha256(INTAKE.read_bytes()).hexdigest(),
              'delta_sha256': hashlib.sha256(DELTA.read_bytes()).hexdigest()}
    try:
        db.start()
        report['postgres_version'] = db.version
        run(db, results)
        report['passed'] = True
    except Exception as error:
        report['passed'] = False
        report['error'] = str(error)
        raise
    finally:
        try:
            db.stop()
            report['server_stopped'] = not db.started
        finally:
            (work / 'result.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
            print('Report: ' + str(work / 'result.json'), flush=True)


if __name__ == '__main__':
    main()
