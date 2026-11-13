"""Verify the WS4 development bootstrap on a NEW loopback PostgreSQL cluster.

No hosted target, password argument, existing database or data directory accepted.
Supabase Auth/JWT/PostgREST are not simulated beyond auth.uid() identity for SQL.
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

from run_tests import Database, FLAGS, ROOT, uid

REPO = ROOT.parents[2]
BOOTSTRAP = REPO / 'supabase/scripts/ws4_dev/001_secure_core.sql'
A = '10000000-0000-4000-8000-000000000001'
B = '10000000-0000-4000-8000-000000000002'


def require(result):
    if result.returncode:
        raise AssertionError(result.stdout + result.stderr)
    return result.stdout.strip()


def run(db, results):
    require(db.sql("""
      CREATE ROLE anon NOLOGIN;
      CREATE ROLE authenticated NOLOGIN;
      CREATE ROLE service_role NOLOGIN BYPASSRLS;
      CREATE SCHEMA auth;
      CREATE TABLE auth.users(id uuid PRIMARY KEY);
      CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE AS $$
        SELECT nullif(current_setting('request.jwt.claim.sub', true), '')::uuid;
      $$;
      GRANT USAGE ON SCHEMA auth, public TO anon, authenticated, service_role;
      -- Hostile defaults prove explicit REVOKE handles old hosting defaults too.
      ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO anon, authenticated, service_role;
      ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON FUNCTIONS TO anon, authenticated, service_role;
      ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO anon, authenticated, service_role;
    """))
    bootstrap = BOOTSTRAP.read_text(encoding='utf-8')
    require(db.sql('CREATE TABLE public.existing_app_data(id int); INSERT INTO public.existing_app_data VALUES (1);'))
    failed = db.sql(bootstrap)
    if failed.returncode == 0 or require(db.sql('SELECT count(*)=1 FROM public.existing_app_data;')) != 't':
        raise AssertionError('Bootstrap did not preserve existing application data')
    require(db.sql('DROP TABLE public.existing_app_data;'))  # Only the new isolated test DB.
    require(db.sql(bootstrap))
    if db.sql(bootstrap).returncode == 0:
        raise AssertionError('Second bootstrap must refuse existing installation')
    results.append({'name': 'fresh-schema and repeat-install refusal preserve objects', 'passed': True})
    require(db.sql(f"""
      INSERT INTO auth.users SELECT ('00000000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid
        FROM generate_series(1,12) n;
      INSERT INTO public.profiles(user_id,first_name,role,is_active)
        SELECT id,'Synthetic '||right(id::text,2),
          CASE WHEN id='{uid(5)}' THEN 'dispatch_supervisor'
            WHEN id IN ('{uid(3)}','{uid(4)}','{uid(6)}','{uid(7)}','{uid(10)}','{uid(11)}')
            THEN 'dispatcher' ELSE 'patient' END, id <> '{uid(6)}'
        FROM auth.users WHERE id NOT IN ('{uid(8)}','{uid(9)}');
      INSERT INTO ws4_dev_private.organisations VALUES ('{A}','Synthetic A'),('{B}','Synthetic B');
      INSERT INTO ws4_dev_private.memberships VALUES
        ('{uid(3)}','{A}','dispatcher',true), ('{uid(4)}','{A}','dispatcher',true),
        ('{uid(5)}','{A}','dispatch_supervisor',true), ('{uid(6)}','{A}','dispatcher',true),
        ('{uid(10)}','{B}','dispatcher',true), ('{uid(11)}','{A}','dispatcher',false);
      INSERT INTO ws4_dev_private.patient_routes VALUES ('{uid(1)}','{A}'),('{uid(2)}','{B}');
      INSERT INTO public.incidents(id,user_id,latitude,longitude,organisation_id)
        OVERRIDING SYSTEM VALUE VALUES (101,'{uid(1)}',0,0,'{A}'), (102,'{uid(2)}',0,0,'{B}');
      SELECT setval(pg_get_serial_sequence('public.incidents','id'),102);
    """))

    def case(name, sql, actor=1, state=None, expected='t'):
        r = db.sql(sql, actor=actor, role='anon' if actor == 0 else 'authenticated', rollback=True)
        passed = (r.returncode != 0 and f'{state}:' in r.stderr) if state else (r.returncode == 0 and r.stdout.strip() == expected)
        results.append({'name': name, 'passed': passed, 'sqlstate_expected': state,
                        'stdout': r.stdout.strip(), 'stderr': r.stderr.strip()})
        print(('PASS ' if passed else 'FAIL ') + name, flush=True)
        if not passed:
            raise AssertionError(name + ': ' + r.stdout + r.stderr)

    case('patient sees own scope only', 'SELECT array_agg(id)=ARRAY[101::bigint] FROM public.incidents;')
    case('dispatcher sees own organisation only', 'SELECT array_agg(id)=ARRAY[101::bigint] FROM public.incidents;', actor=3)
    case('second organisation sees its own incident', 'SELECT array_agg(id)=ARRAY[102::bigint] FROM public.incidents;', actor=10)
    case('anonymous incident reads denied', 'SELECT * FROM public.incidents;', actor=0, state='42501')
    case('anonymous profile reads denied', 'SELECT * FROM public.profiles;', actor=0, state='42501')
    case('anonymous RPC denied', 'SELECT public.corvia_dispatch_accept_incident(101);', actor=0, state='42501')
    for actor in (1,6,7,11):
        case(f'claim requires trusted active membership ({actor})', 'SELECT public.corvia_dispatch_accept_incident(101);', actor=actor, state='42501')
        case(f'access context denies absent authority ({actor})', 'SELECT public.corvia_dispatch_access_context();', actor=actor, state='42501')
    case('access context returns explicit membership and policy', f"SELECT public.corvia_dispatch_access_context()->>'policy_version'='ws4-dev-core-1' AND public.corvia_dispatch_access_context()->'memberships'->0->>'organisation_id'='{A}';", actor=3)
    case('other organisation indistinguishable from absent incident', 'SELECT public.corvia_dispatch_accept_incident(102);', actor=3, state='P0002')
    case('missing incident legacy error retained', 'SELECT public.corvia_dispatch_accept_incident(9999);', actor=3, state='P0002')
    for field, value in (('role', "'dispatcher'"), ('user_type', "'admin'"), ('is_active', 'NULL')):
        case(f'profile cannot self-change {field}', f"UPDATE public.profiles SET {field}={value} WHERE user_id='{uid(1)}';", state='42501')
    case('inactive profile cannot self-activate', f"UPDATE public.profiles SET is_active=true WHERE user_id='{uid(6)}';", actor=6, state='42501')
    case('initial profile cannot self-assert admin', f"INSERT INTO public.profiles(user_id,role,user_type) VALUES ('{uid(9)}','admin','admin');", actor=9, state='42501')
    case('initial profile cannot self-assert dispatcher', f"INSERT INTO public.profiles(user_id,role) VALUES ('{uid(9)}','dispatcher');", actor=9, state='42501')
    case('ordinary own profile edit succeeds', f"UPDATE public.profiles SET first_name='Synthetic changed' WHERE user_id='{uid(1)}'; SELECT first_name='Synthetic changed' FROM public.profiles;")
    case('patient profile insert and repeat upsert preserved', f"""
      INSERT INTO public.profiles(user_id,role,user_type,is_active) VALUES ('{uid(8)}','patient','patient',true)
      ON CONFLICT(user_id) DO UPDATE SET role=excluded.role,user_type=excluded.user_type,is_active=excluded.is_active;
      INSERT INTO public.profiles(user_id,role,user_type,is_active) VALUES ('{uid(8)}','patient','patient',true)
      ON CONFLICT(user_id) DO UPDATE SET role=excluded.role,user_type=excluded.user_type,is_active=excluded.is_active;
      SELECT count(*)=1 FROM public.profiles;
    """, actor=8)
    case('private membership cannot be read', 'SELECT * FROM ws4_dev_private.memberships;', state='42501')
    case('private membership cannot be self-granted', f"INSERT INTO ws4_dev_private.memberships VALUES ('{uid(1)}','{A}','dispatcher',true);", state='42501')
    case('client-controlled session flag cannot bypass profile protection', f"SET app.ws4_internal='true'; UPDATE public.profiles SET role='dispatcher' WHERE user_id='{uid(1)}';", state='42501')
    case('private routing cannot be edited', f"UPDATE ws4_dev_private.patient_routes SET organisation_id='{B}';", state='42501')
    case('legacy patient activation routes on server', f"INSERT INTO public.incidents(user_id,latitude,longitude,status) VALUES ('{uid(1)}',0,0,'pending'); SELECT count(*)=2 AND bool_and(organisation_id='{A}') FROM public.incidents;")
    case('unprovisioned route fails explicitly', f"INSERT INTO public.incidents(user_id,latitude,longitude) VALUES ('{uid(12)}',0,0);", actor=12, state='42501')
    case('cannot submit for another patient', f"INSERT INTO public.incidents(user_id,latitude,longitude) VALUES ('{uid(2)}',0,0);", state='42501')
    case('cannot select route through insert', f"INSERT INTO public.incidents(user_id,latitude,longitude,organisation_id) VALUES ('{uid(1)}',0,0,'{B}');", state='42501')
    case('cannot forge initial lifecycle', f"INSERT INTO public.incidents(user_id,latitude,longitude,status) VALUES ('{uid(1)}',0,0,'resolved');", state='42501')
    for lat in ('91', "'NaN'", "'Infinity'"):
        case(f'invalid latitude {lat} rejected', f"INSERT INTO public.incidents(user_id,latitude,longitude) VALUES ('{uid(1)}',{lat},0);", state='23514')
    case('patient cannot advance arbitrary state', "UPDATE public.incidents SET status='resolved' WHERE id=101;", state='42501')
    case('patient cannot rewrite location', 'UPDATE public.incidents SET latitude=20 WHERE id=101;', state='42501')
    case('patient cannot forge owner', f"UPDATE public.incidents SET assigned_dispatcher_user_id='{uid(3)}' WHERE id=101;", state='42501')
    case('patient cancellation retained', "UPDATE public.incidents SET status='cancelled' WHERE id=101 AND status='pending' AND assigned_dispatcher_user_id IS NULL; SELECT status='cancelled' AND version=2 FROM public.incidents WHERE id=101;")
    case('dispatcher cannot direct-write other patient state', "WITH changed AS (UPDATE public.incidents SET status='cancelled' WHERE id=101 RETURNING id) SELECT count(*)=0 FROM changed;", actor=3)
    case('cannot delete incident', 'DELETE FROM public.incidents WHERE id=101;', state='42501')
    case('cannot truncate incident', 'TRUNCATE public.incidents;', state='42501')
    case('cannot forge or read private audit', 'INSERT INTO ws4_dev_private.incident_events(incident_id,version,event_type,status) VALUES (101,2,\'claimed\',\'in_progress\');', actor=3, state='42501')
    case('legacy claim shape and actor preserved', f"""
      WITH claim AS (SELECT public.corvia_dispatch_accept_incident(101) j)
      SELECT j->>'status'='in_progress' AND j->>'assigned_dispatcher_user_id'='{uid(3)}'
        AND j->>'id'='101' AND j->>'user_id'='{uid(1)}' AND j->>'accepted_at' IS NOT NULL
        AND (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(j) k)=
          ARRAY['accepted_at','assigned_dispatcher_user_id','created_at','id','latitude','longitude','status','user_id']
      FROM claim;
    """, actor=3)
    case('same owner retry leaves version unchanged', "SELECT public.corvia_dispatch_accept_incident(101)=public.corvia_dispatch_accept_incident(101); SELECT version=2 FROM public.incidents WHERE id=101;", actor=3, expected='t\nt')
    case('supervisor claim preserved', "SELECT public.corvia_dispatch_accept_incident(101)->>'status'='in_progress';", actor=5)

    # A real committed claim proves audit uniqueness and direct cancellation denial.
    require(db.sql('SELECT public.corvia_dispatch_accept_incident(101);', actor=3))
    require(db.sql('SELECT public.corvia_dispatch_accept_incident(101);', actor=3))
    case('patient cannot cancel after claim even without client predicates', "UPDATE public.incidents SET status='cancelled' WHERE id=101;", state='42501')
    case('competing claimant conflicts', 'SELECT public.corvia_dispatch_accept_incident(101);', actor=4, state='P0001')
    case('audit exactly once for claim and retry', f"SELECT count(*)=2 AND count(*) FILTER(WHERE event_type='claimed' AND actor_user_id='{uid(3)}')=1 FROM ws4_dev_private.incident_events WHERE incident_id=101;", actor=None)
    require(db.sql(f"UPDATE ws4_dev_private.memberships SET active=false WHERE user_id='{uid(3)}';"))
    case('revoked owner cannot retry', 'SELECT public.corvia_dispatch_accept_incident(101);', actor=3, state='42501')
    case('revoked member loses scope read', 'SELECT count(*)=0 FROM public.incidents;', actor=3)
    require(db.sql(f"UPDATE ws4_dev_private.memberships SET active=true WHERE user_id='{uid(3)}';"))

    def new_incident(number):
        require(db.sql(f"INSERT INTO public.incidents(id,user_id,latitude,longitude,organisation_id) OVERRIDING SYSTEM VALUE VALUES ({number},'{uid(1)}',0,0,'{A}');"))

    new_incident(201)
    failed = db.sql('BEGIN; SELECT public.corvia_dispatch_accept_incident(201); SELECT 1/0;', actor=3)
    if '22012:' not in failed.stderr:
        raise AssertionError('Expected injected transaction failure')
    case('failed transaction rolls back state and audit', "SELECT status='pending' AND version=1 AND (SELECT count(*)=1 FROM ws4_dev_private.incident_events WHERE incident_id=201) FROM public.incidents WHERE id=201;", actor=None)
    # Cause the audit INSERT itself to fail. The claim must not survive it.
    require(db.sql("CREATE FUNCTION ws4_dev_private.fail_event() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION 'Injected audit failure'; END $$; CREATE TRIGGER fail_event BEFORE INSERT ON ws4_dev_private.incident_events FOR EACH ROW WHEN (NEW.incident_id=201 AND NEW.version=2) EXECUTE FUNCTION ws4_dev_private.fail_event();"))
    case('audit failure aborts claim', 'SELECT public.corvia_dispatch_accept_incident(201);', actor=3, state='P0001')
    case('audit failure leaves no state effect', 'SELECT status=\'pending\' AND version=1 FROM public.incidents WHERE id=201;', actor=None)
    require(db.sql('DROP TRIGGER fail_event ON ws4_dev_private.incident_events;'))

    def race(name, holder_sql, waiter_sql, holder_actor, waiter_actor, state=None, expected=None):
        command = [db.exe('psql'), '-X', '-qAt', '-v', 'ON_ERROR_STOP=1', '-h', '127.0.0.1', '-p', str(db.port), '-U', 'postgres', '-d', 'postgres']
        proc = subprocess.Popen(command, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                env=db.env, text=True, encoding='utf-8', creationflags=FLAGS)
        try:
            actor_sql = f"SET ROLE authenticated; SET request.jwt.claim.sub='{uid(holder_actor)}';" if holder_actor else ''
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
                future = pool.submit(db.sql, "SET application_name='ws4_secure_waiter'; " + waiter_sql, waiter_actor)
                deadline = time.monotonic() + 5
                waiting = False
                while time.monotonic() < deadline:
                    if require(db.sql("SELECT EXISTS(SELECT 1 FROM pg_stat_activity WHERE application_name='ws4_secure_waiter' AND wait_event_type='Lock');")) == 't':
                        waiting = True
                        break
                    time.sleep(.05)
                proc.stdin.write('COMMIT;\n\\q\n')
                proc.stdin.flush()
                proc.wait(timeout=10)
                r = future.result(timeout=12)
                passed = waiting and proc.returncode == 0 and ((r.returncode != 0 and f'{state}:' in r.stderr) if state else r.returncode == 0)
                if expected is not None:
                    passed = passed and r.stdout.strip() == expected
                results.append({'name': name, 'passed': passed, 'observed_lock_wait': waiting, 'stderr': r.stderr.strip()})
                print(('PASS ' if passed else 'FAIL ') + name, flush=True)
                if not passed:
                    raise AssertionError(name + ': ' + r.stdout + r.stderr)
        finally:
            if proc.poll() is None:
                proc.kill()
                proc.wait(timeout=5)
            for stream in (proc.stdin, proc.stdout, proc.stderr):
                stream.close()

    for n in (202,203,204,205,206):
        new_incident(n)
    race('two claimants serialize to one winner', 'SELECT public.corvia_dispatch_accept_incident(202);', 'SELECT public.corvia_dispatch_accept_incident(202);', 3,4,state='P0001')
    case('claim race has one owner and one claim event', f"SELECT assigned_dispatcher_user_id='{uid(3)}' AND version=2 AND (SELECT count(*)=2 FROM ws4_dev_private.incident_events WHERE incident_id=202) FROM public.incidents WHERE id=202;", actor=None)
    race('cancellation first blocks waiting claim', "UPDATE public.incidents SET status='cancelled' WHERE id=203;", 'SELECT public.corvia_dispatch_accept_incident(203);',1,3,state='P0001')
    race('claim first blocks unconditional patient cancellation', 'SELECT public.corvia_dispatch_accept_incident(204);', "UPDATE public.incidents SET status='cancelled' WHERE id=204;",3,1,state='42501')
    race('claim first conditional cancellation changes zero rows', 'SELECT public.corvia_dispatch_accept_incident(205);', "WITH changed AS (UPDATE public.incidents SET status='cancelled' WHERE id=205 AND status='pending' AND assigned_dispatcher_user_id IS NULL RETURNING id) SELECT count(*)=0 FROM changed;",3,1,expected='t')
    race('membership revocation first denies waiting claim', f"UPDATE ws4_dev_private.memberships SET active=false WHERE user_id='{uid(4)}';", 'SELECT public.corvia_dispatch_accept_incident(206);',None,4,state='42501')
    case('revocation race leaves incident pending', "SELECT status='pending' AND version=1 FROM public.incidents WHERE id=206;", actor=None)
    race('claim first finishes before revocation', 'SELECT public.corvia_dispatch_accept_incident(206);', f"UPDATE ws4_dev_private.memberships SET active=false WHERE user_id='{uid(3)}';",3,None)
    case('revocation after claim blocks retry', 'SELECT public.corvia_dispatch_accept_incident(206);', actor=3,state='42501')
    require(db.sql(f"UPDATE ws4_dev_private.memberships SET active=true WHERE user_id='{uid(4)}';"))
    new_incident(207)
    race('profile deactivation first denies waiting claim', f"UPDATE public.profiles SET is_active=false WHERE user_id='{uid(4)}';", 'SELECT public.corvia_dispatch_accept_incident(207);',None,4,state='42501')
    case('deactivation race leaves incident pending', "SELECT status='pending' AND version=1 FROM public.incidents WHERE id=207;", actor=None)
    metadata = json.loads(require(db.sql((BOOTSTRAP.parent / 'verify_core.sql').read_text(encoding='utf-8'))))
    passed = len(metadata['tables']) == 7 and all(t['rls'] for t in metadata['tables'])
    results.append({'name': 'read-only verification report covers all seven protected tables', 'passed': passed})
    if not passed:
        raise AssertionError('Metadata verification failed')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--pg-bin', type=Path, required=True)
    args = parser.parse_args()
    work = REPO / 'build/ws4-secure-db' / uuid.uuid4().hex
    work.mkdir(parents=True, exist_ok=False)
    db = Database(args.pg_bin.resolve(), work)
    results = []
    report = {'scope': 'SECURE SYNTHETIC DEV CORE ONLY; not a shared-backend migration or Auth/API test',
              'started_at': datetime.datetime.now(datetime.timezone.utc).isoformat(), 'results': results,
              'bootstrap_sha256': hashlib.sha256(BOOTSTRAP.read_bytes()).hexdigest()}
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
