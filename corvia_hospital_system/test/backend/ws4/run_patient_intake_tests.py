"""Test additive patient intake on a NEW isolated PostgreSQL 15 cluster.

No connection URL, existing data directory, hosted target or real Auth accepted.
Identity is a SQL auth.uid stub; this does not verify hosted JWT/PostgREST behavior.
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
CORE = REPO / 'supabase/scripts/ws4_dev/001_secure_core.sql'
DELTA = REPO / 'supabase/scripts/ws4_dev/002_patient_intake.sql'
A = '10000000-0000-4000-8000-000000000001'
B = '10000000-0000-4000-8000-000000000002'


def require(result):
    if result.returncode:
        raise AssertionError(result.stdout + result.stderr)
    return result.stdout.strip()


def operation(number):
    return f'20000000-0000-4000-8000-{number:012d}'


def request(number, lat='NULL', lon='NULL', accuracy='NULL', captured='NULL',
            address='NULL', details='NULL'):
    return (f"public.corvia_patient_request_emergency('{operation(number)}',"
            f"{lat},{lon},{accuracy},{captured},{address},{details})")


def run(db, results):
    def case(name, sql, actor=1, state=None, expected='t', rollback=True):
        result = db.sql(sql, actor=actor, role='anon' if actor == 0 else 'authenticated',
                        rollback=rollback)
        passed = (result.returncode != 0 and f'{state}:' in result.stderr) if state else (
            result.returncode == 0 and result.stdout.strip() == expected)
        results.append({'name': name, 'passed': passed, 'sqlstate_expected': state,
                        'stdout': result.stdout.strip(), 'stderr': result.stderr.strip()})
        print(('PASS ' if passed else 'FAIL ') + name, flush=True)
        if not passed:
            raise AssertionError(name + ': ' + result.stdout + result.stderr)

    case('delta refuses absent synthetic core', DELTA.read_text(encoding='utf-8'),
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
    require(db.sql(f"""
      INSERT INTO auth.users SELECT ('00000000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid
        FROM generate_series(1,6) n;
      INSERT INTO public.profiles(user_id,role,is_active)
        SELECT id,CASE WHEN id='{uid(3)}' THEN 'dispatcher' ELSE 'patient' END,
          id<>'{uid(4)}' FROM auth.users;
      INSERT INTO ws4_dev_private.organisations VALUES ('{A}','Synthetic Intake A'),('{B}','Synthetic Intake B');
      INSERT INTO ws4_dev_private.patient_routes VALUES
        ('{uid(1)}','{A}'),('{uid(2)}','{B}'),('{uid(3)}','{A}'),('{uid(4)}','{A}');
      INSERT INTO ws4_dev_private.memberships VALUES ('{uid(3)}','{A}','dispatcher',true);
      INSERT INTO public.incidents(id,user_id,latitude,longitude,organisation_id)
        OVERRIDING SYSTEM VALUE VALUES (101,'{uid(1)}',0,0,'{A}');
      SELECT setval(pg_get_serial_sequence('public.incidents','id'),101);
      ALTER DEFAULT PRIVILEGES IN SCHEMA ws4_dev_private GRANT ALL ON TABLES TO anon,authenticated,service_role;
      ALTER DEFAULT PRIVILEGES IN SCHEMA ws4_dev_private GRANT ALL ON FUNCTIONS TO anon,authenticated,service_role;
    """))
    case('ordinary patient cannot install delta', DELTA.read_text(encoding='utf-8'),
         actor=1, state='P0001', rollback=False)
    require(db.sql(DELTA.read_text(encoding='utf-8')))
    case('reapplying delta refuses without resetting records', DELTA.read_text(encoding='utf-8'),
         actor=None, state='P0001', rollback=False)
    case('legacy coordinates retain explicit unknown capture provenance',
         "SELECT location_source='legacy' AND latitude=0 AND longitude=0 AND location_captured_at IS NULL FROM public.incidents WHERE id=101;")
    case('dispatch context advertises installed intake projection',
         "SELECT public.corvia_dispatch_access_context()->'capabilities' ? 'read_intake_details';",actor=3)
    case('patient cannot acquire dispatch intake projection capability',
         'SELECT public.corvia_dispatch_access_context();',state='42501')

    for actor in (0,3,4,5):
        case(f'request requires active routed patient ({actor})',
             f'SELECT {request(1)};', actor=actor, state='42501')
        case(f'recovery requires active routed patient ({actor})',
             f"SELECT public.corvia_patient_request_status('{operation(1)}');", actor=actor, state='42501')
    case('service role has no intake execute grant',
         f"SET ROLE service_role; SET request.jwt.claim.sub='{uid(1)}'; SELECT {request(1)};",
         actor=None, state='42501')
    case('private operation rows cannot be read', 'SELECT * FROM ws4_dev_private.patient_intake_operations;', state='42501')
    case('internal projection cannot be called directly',
         f"SELECT ws4_dev_private.patient_intake_response('{operation(1)}',101);", state='42501')
    for field, value in [('details', "'forged'"), ('address', "'forged'"),
                         ('location_source', "'manual'"), ('organisation_id', f"'{B}'")]:
        case(f'legacy UPDATE cannot forge {field}',
             f'UPDATE public.incidents SET {field}={value} WHERE id=101;', state='42501')
        case(f'legacy INSERT cannot supply {field}',
             f"INSERT INTO public.incidents(user_id,latitude,longitude,{field}) VALUES ('{uid(1)}',0,0,{value});",
             state='42501')
    case('legacy coordinate insert contract remains usable',
         f"INSERT INTO public.incidents(user_id,latitude,longitude) VALUES ('{uid(1)}',0,0); SELECT count(*)=2 FROM public.incidents;")
    case('legacy direct insert cannot evade paired location shape',
         f"INSERT INTO public.incidents(user_id,latitude,longitude) VALUES ('{uid(1)}',NULL,NULL);", state='23514')

    payloads = [
        ('paired latitude required', dict(lat='1')),
        ('paired longitude required', dict(lon='1')),
        ('GPS accuracy required', dict(lat='1',lon='1',captured='now()')),
        ('GPS capture timestamp required', dict(lat='1',lon='1',accuracy='1')),
        ('accuracy without coordinates rejected', dict(accuracy='1')),
        ('timestamp without coordinates rejected', dict(captured='now()')),
        ('latitude range rejected', dict(lat='91',lon='1',accuracy='1',captured='now()')),
        ('longitude range rejected', dict(lat='1',lon='181',accuracy='1',captured='now()')),
        ('NaN coordinates rejected', dict(lat="'NaN'",lon='1',accuracy='1',captured='now()')),
        ('infinite coordinates rejected', dict(lat='1',lon="'Infinity'",accuracy='1',captured='now()')),
        ('negative accuracy rejected', dict(lat='1',lon='1',accuracy='-1',captured='now()')),
        ('NaN accuracy rejected', dict(lat='1',lon='1',accuracy="'NaN'",captured='now()')),
        ('infinite accuracy rejected', dict(lat='1',lon='1',accuracy="'Infinity'",captured='now()')),
        ('infinite timestamp rejected', dict(lat='1',lon='1',accuracy='1',captured="'infinity'")),
        ('stale GPS refused for new request', dict(lat='1',lon='1',accuracy='1',captured="now()-interval '121 seconds'")),
        ('future GPS refused for new request', dict(lat='1',lon='1',accuracy='1',captured="now()+interval '31 seconds'")),
        ('address bound enforced', dict(address="repeat('a',301)")),
        ('details bound enforced', dict(details="repeat('a',1001)")),
    ]
    for name, values in payloads:
        case(name, f'SELECT {request(2,**values)};', state='22023')
    case('null operation rejected', f"SELECT {request(2).replace(repr(operation(2)), 'NULL')};", state='22023')

    manual = request(10,address="'  Synthetic entrance A  '",details="'  Demo only  '")
    created = json.loads(require(db.sql(f'SELECT {manual};',actor=1)))
    incident_id = created['incident_id']
    expected_keys = {'operation_id','incident_id','user_id','status','version','created_at',
                     'latitude','longitude','location_source','location_accuracy','location_captured_at','address','details'}
    passed = (set(created)==expected_keys and created['operation_id']==operation(10)
              and isinstance(incident_id,str) and int(incident_id)>0 and created['version']=='1'
              and created['user_id']==uid(1) and created['status']=='pending'
              and created['location_source']=='manual' and created['latitude'] is None
              and created['longitude'] is None and created['location_accuracy'] is None
              and created['location_captured_at'] is None and created['address']=='Synthetic entrance A'
              and created['details']=='Demo only')
    results.append({'name':'explicit manual request returns exact actor-bound string-ID contract','passed':passed})
    if not passed: raise AssertionError('Unexpected intake response shape')
    case('same canonical request reuses incident', f"SELECT {request(10,address=repr('Synthetic entrance A'),details=repr('Demo only'))}->>'incident_id'='{incident_id}';")
    case('changed payload reuse is rejected', f'SELECT {request(10,details=repr("changed"))};', state='22023')
    case('exact retry leaves one incident event and one operation',
         f"SELECT (SELECT count(*)=1 FROM ws4_dev_private.patient_intake_operations WHERE user_id='{uid(1)}' AND operation_id='{operation(10)}') AND (SELECT count(*)=1 FROM ws4_dev_private.incident_events WHERE incident_id={incident_id});", actor=None)
    case('own recovery returns durable record', f"SELECT public.corvia_patient_request_status('{operation(10)}')->>'incident_id'='{incident_id}';")
    case('another patient operation is indistinguishable from missing',
         f"SELECT public.corvia_patient_request_status('{operation(10)}') IS NULL;", actor=2)
    case('absent own operation returns null', f"SELECT public.corvia_patient_request_status('{operation(999)}') IS NULL;")
    case('same operation UUID is separate for another actor',
         f"SELECT {request(10)}->>'user_id'='{uid(2)}';", actor=2)
    case('whitespace and missing details become null without invented location',
         f"WITH r AS (SELECT {request(20,address=repr(' '),details=repr(' '))} j) SELECT j->>'location_source'='unavailable' AND j->>'latitude' IS NULL AND j->>'address' IS NULL AND j->>'details' IS NULL FROM r;")
    boundary_request = request(21,address="repeat('a',300)",details="repeat('b',1000)")
    case('boundary input lengths accepted',
         f"WITH r AS (SELECT {boundary_request} j) SELECT length(j->>'address')=300 AND length(j->>'details')=1000 FROM r;")
    case('fresh GPS preserves captured metadata',
         f"WITH r AS (SELECT {request(22,lat='-26.2',lon='28.0',accuracy='0',captured='now()')} j) SELECT j->>'location_source'='gps' AND (j->>'location_accuracy')::float8=0 AND (j->>'location_captured_at')::timestamptz=now() FROM r;")

    # Exercise aging without waiting two minutes: start near the accepted edge.
    captured = require(db.sql("SELECT clock_timestamp()-interval '117 seconds';"))
    aged_request = request(30,lat='-26.2',lon='28',accuracy='20',captured=repr(captured))
    first = json.loads(require(db.sql(f'SELECT {aged_request};',actor=1)))
    time.sleep(3.3)
    second = json.loads(require(db.sql(f'SELECT {aged_request};',actor=1)))
    passed = first == second and require(db.sql(
        f"SELECT clock_timestamp()-'{captured}'::timestamptz>interval '120 seconds';"))=='t'
    results.append({'name':'same GPS retry after expiry retains one original fix and incident','passed':passed})
    if not passed: raise AssertionError('Aged identical GPS retry failed')

    require(db.sql(f'SELECT public.corvia_dispatch_accept_incident({incident_id});',actor=3))
    case('lookup follows current claim status/version, not stale creation result',
         f"WITH r AS (SELECT public.corvia_patient_request_status('{operation(10)}') j) SELECT j->>'status'='in_progress' AND j->>'version'='2' FROM r;")
    case('replay after claim returns current state', f"SELECT {manual}->>'status'='in_progress';")
    case('legacy claim still returns eight keys for nullable location',
         f"SELECT count(*)=8 FROM jsonb_object_keys(public.corvia_dispatch_accept_incident({incident_id}));",actor=3)
    case('legacy patient cancellation still denied after claim',
         f"UPDATE public.incidents SET status='cancelled' WHERE id={incident_id};",state='42501')
    case('legacy cancel works on new pending manual incident',
         f"UPDATE public.incidents SET status='cancelled' WHERE id={first['incident_id']}; SELECT status='cancelled' AND version=2 FROM public.incidents WHERE id={first['incident_id']};")

    # Any failure rolls back operation identity, incident and its creation event.
    require(db.sql("""
      CREATE FUNCTION ws4_dev_private.fail_intake_audit() RETURNS trigger LANGUAGE plpgsql AS $$
      BEGIN RAISE EXCEPTION 'Injected test audit failure'; END $$;
      CREATE TRIGGER fail_intake_audit BEFORE INSERT ON ws4_dev_private.incident_events
      FOR EACH ROW EXECUTE FUNCTION ws4_dev_private.fail_intake_audit();
    """))
    before = require(db.sql('SELECT count(*) FROM public.incidents;'))
    case('audit insertion failure aborts intake',f'SELECT {request(40)};',state='P0001',rollback=False)
    case('failed intake persists no operation, incident or partial event',
         f"SELECT (SELECT count(*)={before} FROM public.incidents) AND NOT EXISTS(SELECT 1 FROM ws4_dev_private.patient_intake_operations WHERE operation_id='{operation(40)}');",actor=None)
    require(db.sql('DROP TRIGGER fail_intake_audit ON ws4_dev_private.incident_events;'))
    case('outer transaction rollback removes operation and incident',
         f'BEGIN; SELECT {request(41)}; SELECT 1/0;',state='22012',rollback=False)
    case('rolled back operation can safely be reused',f"SELECT {request(41)}->>'status'='pending';")

    def race(name, holder_sql, waiter_sql, holder_actor, waiter_actor, state=None):
        command = [db.exe('psql'),'-X','-qAt','-v','ON_ERROR_STOP=1','-h','127.0.0.1',
                   '-p',str(db.port),'-U','postgres','-d','postgres']
        proc = subprocess.Popen(command,stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,
                                env=db.env,text=True,encoding='utf-8',creationflags=FLAGS)
        try:
            actor_sql = f"SET ROLE authenticated; SET request.jwt.claim.sub='{uid(holder_actor)}';" if holder_actor else ''
            proc.stdin.write(f"SET statement_timeout='15s'; {actor_sql} BEGIN; {holder_sql}\n\\echo LOCK_HELD\n")
            proc.stdin.flush()
            with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
                def ready():
                    while True:
                        line = proc.stdout.readline()
                        if not line: raise RuntimeError('Lock holder exited')
                        if line.strip()=='LOCK_HELD': return
                pool.submit(ready).result(timeout=10)
                future = pool.submit(db.sql,"SET application_name='ws4_intake_waiter'; "+waiter_sql,waiter_actor)
                deadline = time.monotonic()+5
                waiting = False
                while time.monotonic()<deadline:
                    if require(db.sql("SELECT EXISTS(SELECT 1 FROM pg_stat_activity WHERE application_name='ws4_intake_waiter' AND wait_event_type='Lock');"))=='t':
                        waiting = True
                        break
                    time.sleep(.05)
                proc.stdin.write('COMMIT;\n\\q\n')
                proc.stdin.flush()
                proc.wait(timeout=10)
                result = future.result(timeout=12)
                passed = waiting and proc.returncode==0 and (
                    (result.returncode!=0 and f'{state}:' in result.stderr) if state else result.returncode==0)
                results.append({'name':name,'passed':passed,'observed_lock_wait':waiting,
                                'stderr':result.stderr.strip()})
                print(('PASS ' if passed else 'FAIL ')+name,flush=True)
                if not passed: raise AssertionError(name+': '+result.stdout+result.stderr)
        finally:
            if proc.poll() is None:
                proc.kill()
                proc.wait(timeout=5)
            for stream in (proc.stdin,proc.stdout,proc.stderr): stream.close()

    race('duplicate simultaneous operation serializes to one incident',
         f'SELECT {request(50)};',f'SELECT {request(50)};',1,1)
    case('duplicate race leaves one operation and one creation event',
         f"SELECT count(*)=1 AND bool_and((SELECT count(*)=1 FROM ws4_dev_private.incident_events e WHERE e.incident_id=o.incident_id)) FROM ws4_dev_private.patient_intake_operations o WHERE o.operation_id='{operation(50)}';",actor=None)
    race('changed simultaneous payload waits then conflicts',
         f'SELECT {request(51)};',f'SELECT {request(51,details=repr("changed"))};',1,1,state='22023')
    race('recovery waits for an already committing request identity',
         f'SELECT {request(56)};',f"""DO $$ DECLARE v_result jsonb; BEGIN
           v_result := public.corvia_patient_request_status('{operation(56)}');
           IF v_result IS NULL OR v_result->>'operation_id' IS DISTINCT FROM '{operation(56)}'
              OR v_result->>'user_id' IS DISTINCT FROM '{uid(1)}'
              OR v_result->>'status' IS DISTINCT FROM 'pending'
              OR v_result->>'incident_id' IS NULL THEN
             RAISE EXCEPTION 'Recovery did not return the committed own operation';
           END IF;
         END $$;""",1,1)
    race('deactivation first denies blocked request',
         f"UPDATE public.profiles SET is_active=false WHERE user_id='{uid(1)}';",f'SELECT {request(52)};',None,1,state='42501')
    require(db.sql(f"UPDATE public.profiles SET is_active=true WHERE user_id='{uid(1)}';"))
    race('request first finishes before profile deactivation',
         f'SELECT {request(53)};',f"UPDATE public.profiles SET is_active=false WHERE user_id='{uid(1)}';",1,None)
    case('revoked actor cannot recover committed request',
         f"SELECT public.corvia_patient_request_status('{operation(53)}');",state='42501')
    require(db.sql(f"UPDATE public.profiles SET is_active=true WHERE user_id='{uid(1)}';"))
    race('route removal first denies blocked request',
         f"DELETE FROM ws4_dev_private.patient_routes WHERE user_id='{uid(1)}';",f'SELECT {request(54)};',None,1,state='42501')
    require(db.sql(f"INSERT INTO ws4_dev_private.patient_routes VALUES ('{uid(1)}','{A}');"))
    race('request first locks its route until creation commits',
         f'SELECT {request(55)};',f"UPDATE ws4_dev_private.patient_routes SET organisation_id='{B}' WHERE user_id='{uid(1)}';",1,None)
    case('route change explicitly denies old operation recovery',
         f"SELECT public.corvia_patient_request_status('{operation(55)}');",state='42501')
    case('route change cannot replay old operation into a new scope',
         f'SELECT {request(55)};',state='42501')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--pg-bin',type=Path,required=True)
    args = parser.parse_args()
    work = REPO/'build/ws4-patient-intake-db'/uuid.uuid4().hex
    work.mkdir(parents=True,exist_ok=False)
    db = Database(args.pg_bin.resolve(),work)
    results = []
    report = {'scope':'ADDITIVE SYNTHETIC PATIENT INTAKE SQL ONLY; no shared/hosted/Auth API verification',
              'started_at':datetime.datetime.now(datetime.timezone.utc).isoformat(),'results':results,
              'core_sha256':hashlib.sha256(CORE.read_bytes()).hexdigest(),
              'delta_sha256':hashlib.sha256(DELTA.read_bytes()).hexdigest()}
    try:
        db.start()
        report['postgres_version']=db.version
        run(db,results)
        report['passed']=True
    except Exception as error:
        report['passed']=False
        report['error']=str(error)
        raise
    finally:
        try:
            db.stop()
            report['server_stopped']=not db.started
        finally:
            (work/'result.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
            print('Report: '+str(work/'result.json'),flush=True)


if __name__=='__main__':
    main()
