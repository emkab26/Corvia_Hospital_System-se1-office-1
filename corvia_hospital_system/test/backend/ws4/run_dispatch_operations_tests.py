"""Exercise WS4 operations in a disposable loopback PostgreSQL cluster, never a supplied DB."""
import argparse
import concurrent.futures
import hashlib
import json
from pathlib import Path
import uuid
from run_tests import Database, uid
from run_patient_intake_tests import REPO, CORE, DELTA as INTAKE, A, B, require, operation, request

HISTORY = REPO / 'supabase/scripts/ws4_dev/003_cancel_and_history.sql'
OPERATIONS = REPO / 'supabase/scripts/ws4_dev/004_dispatch_operations.sql'


def setup(db):
    require(db.sql("""
      CREATE ROLE anon NOLOGIN; CREATE ROLE authenticated NOLOGIN; CREATE ROLE service_role NOLOGIN BYPASSRLS;
      CREATE SCHEMA auth; CREATE TABLE auth.users(id uuid PRIMARY KEY);
      CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE AS $$
        SELECT nullif(current_setting('request.jwt.claim.sub',true),'')::uuid $$;
      GRANT USAGE ON SCHEMA auth,public TO anon,authenticated,service_role;
      ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO anon,authenticated,service_role;
      ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON FUNCTIONS TO anon,authenticated,service_role;
    """))
    for path in (CORE, INTAKE, HISTORY, OPERATIONS):
        require(db.sql(path.read_text(encoding='utf-8')))
    require(db.sql(f"""
      INSERT INTO auth.users SELECT ('00000000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid FROM generate_series(1,7) n;
      INSERT INTO public.profiles(user_id,role,is_active) SELECT id,CASE WHEN id IN ('{uid(3)}','{uid(5)}','{uid(6)}','{uid(7)}') THEN 'dispatcher' ELSE 'patient' END,id<>'{uid(4)}' FROM auth.users;
      INSERT INTO ws4_dev_private.organisations VALUES ('{A}','Synthetic Operations A'),('{B}','Synthetic Operations B');
      INSERT INTO ws4_dev_private.patient_routes VALUES ('{uid(1)}','{A}'),('{uid(2)}','{B}'),('{uid(4)}','{A}');
      INSERT INTO ws4_dev_private.memberships VALUES ('{uid(3)}','{A}','dispatcher',true),('{uid(5)}','{A}','dispatcher',true),('{uid(6)}','{A}','dispatch_supervisor',true),('{uid(7)}','{B}','dispatcher',true);
    """))


def run(db, results):
    def case(name, sql, actor=3, state=None, expected='t', rollback=True):
        r = db.sql(sql, actor=actor, role='anon' if actor == 0 else 'authenticated', rollback=rollback)
        ok = (r.returncode != 0 and f'{state}:' in r.stderr) if state else (r.returncode == 0 and r.stdout.strip() == expected)
        results.append(dict(name=name, passed=ok, stdout=r.stdout.strip(), stderr=r.stderr.strip()))
        print(('PASS ' if ok else 'FAIL ') + name, flush=True)
        if not ok:
            raise AssertionError(name + ': ' + r.stdout + r.stderr)

    incident = json.loads(require(db.sql(f'SELECT {request(1)};', actor=1)))['incident_id']
    def command(n=10, version=2, kind='note', payload=None):
        data = json.dumps(payload if payload is not None else {'text':'Synthetic internal note'}).replace("'", "''")
        return f"public.corvia_dispatch_command({incident},'{operation(n)}',{version},'{kind}','{data}'::jsonb)"
    def send(n=50, body='Synthetic hello'):
        return f"public.corvia_send_incident_message({incident},'{operation(n)}','{body}')"
    get = f'public.corvia_incident_workspace({incident})'
    messages = f'public.corvia_incident_messages({incident})'
    case('workspace capability advertised', "SELECT public.corvia_dispatch_access_context()->'capabilities' ? 'incident_workspace';")
    for actor in (0,2,4,7):
        case(f'workspace denial {actor}', f'SELECT {get};', actor=actor, state='42501')
        case(f'message read denial {actor}', f'SELECT {messages};', actor=actor, state='42501')
        case(f'command denial {actor}', f'SELECT {command()};', actor=actor, state='42501')
    case('pending cannot be managed', f'SELECT {command(version=1)};', state='P0001')
    require(db.sql(f'SELECT public.corvia_dispatch_accept_incident({incident});', actor=3))
    case('claim owner can manage', f"SELECT ({get}->>'can_manage')::boolean;")
    require(db.sql(f"UPDATE public.profiles SET phone_number='+27 (11) 000-0000' WHERE user_id='{uid(1)}';"))
    case('owner receives normalized patient callback', f"SELECT {get}->>'callback_number'='+27110000000';")
    case('other dispatcher does not receive callback', f"SELECT {get}->>'callback_number' IS NULL;", actor=5)
    case('patient projection excludes callback field value', f"SELECT {get}->>'callback_number' IS NULL;", actor=1)
    case('other dispatcher cannot manage', f'SELECT {command()};', actor=5, state='42501')
    case('patient cannot write internal notes', f'SELECT {command()};', actor=1, state='42501')
    case('supervisor can record reason', f"SELECT {command()}->>'version'='3';", actor=6)
    case('stale version refused', f'SELECT {command(version=1)};', state='P0001')
    for payload in ({'text':''},{'text':None},{'text':'x'*1001},{'text':'x','actor_id':uid(3)},{'text':4}):
        case('invalid or forged command payload', f'SELECT {command(payload=payload)};', state='22023')
    case('note commit', f"SELECT {command()}->>'version'='3';", rollback=False)
    case('exact retry returns original receipt', f"SELECT {command()}->>'version'='3';")
    case('changed replay rejected', f'SELECT {command(payload={"text":"different"})};', state='22023')
    case('note produces update not another claim', f"SELECT count(*)=1 FROM ws4_dev_private.incident_events WHERE incident_id={incident} AND event_type='claimed';", actor=None)
    case('one note event and no replay version increment', f"SELECT version=3 AND (SELECT count(*) FROM ws4_dev_private.incident_events WHERE incident_id={incident})=3 FROM public.incidents WHERE id={incident};", actor=None)
    case('patient internal notes redacted', f"SELECT {get}->'recent_actions'='[]'::jsonb;", actor=1)
    case('dispatch sees saved note', f"SELECT {get}->'recent_actions'->0->>'text'='Synthetic internal note';")
    case('priority update', f"SELECT {command(11,3,'set_priority',{'priority':'urgent'})}->>'version'='4';", rollback=False)
    case('patient cancellation request does not cancel claimed incident', f"SELECT {command(12,4,'request_cancellation',{'text':'Synthetic change of plan'})}->>'version'='5';", actor=1, rollback=False)
    case('cancellation request visible to owner', f"SELECT ({get}->>'cancellation_requested')::boolean AND {get}->>'status'='in_progress';")
    case('provider demo disabled by default', f"SELECT {command(13,5,'simulate_provider',{'scenario':'unknown'})};", state='42501')
    require(db.sql('UPDATE ws4_dev_private.operations_settings SET provider_demo_enabled=true;'))
    case('uncertain provider scenario persists', f"SELECT {command(13,5,'simulate_provider',{'scenario':'unknown'})}->>'version'='6';", rollback=False)
    case('uncertain provider visible and labelled demo', f"SELECT {get}->>'provider_state'='unknown' AND ({get}->>'provider_demo')::boolean;", actor=1)
    case('unknown provider cannot be resubmitted', f"SELECT {command(14,6,'simulate_provider',{'scenario':'accepted'})};", state='P0001')
    case('unknown provider blocks closure', f"SELECT {command(14,6,'close',{'text':'Synthetic closure'})};", state='P0001')
    case('reconcile existing request', f"SELECT {command(14,6,'reconcile_provider',{})}->>'version'='7';", rollback=False)
    case('accepted provider still blocks closure', f"SELECT {command(15,7,'close',{'text':'Synthetic closure'})};", state='P0001')
    case('record provider completion', f"SELECT {command(15,7,'provider_completed',{'text':'Synthetic provider reported finished'})}->>'version'='8';", rollback=False)
    require(db.sql("CREATE FUNCTION ws4_dev_private.test_fail_command() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION 'Synthetic ledger failure'; END $$; CREATE TRIGGER test_fail_command BEFORE INSERT ON ws4_dev_private.dispatch_commands FOR EACH ROW EXECUTE FUNCTION ws4_dev_private.test_fail_command();"))
    case('ledger failure aborts whole command', f"SELECT {command(160,8,'set_priority',{'priority':'standard'})};", state='P0001')
    case('ledger failure rolls back state version and audit', f"SELECT i.version=8 AND w.priority='urgent' AND (SELECT count(*) FROM ws4_dev_private.incident_events WHERE incident_id={incident})=8 FROM public.incidents i JOIN ws4_dev_private.incident_workspace w ON w.incident_id=i.id WHERE i.id={incident};", actor=None)
    require(db.sql('DROP TRIGGER test_fail_command ON ws4_dev_private.dispatch_commands; DROP FUNCTION ws4_dev_private.test_fail_command();'))
    case('patient message commit', f"SELECT {send()}->>'incident_id'='{incident}';", actor=1, rollback=False)
    case('message exact retry', f"SELECT {send()}->>'id'='1';", actor=1)
    case('message changed replay', f"SELECT {send(body='Different')};", actor=1, state='22023')
    case('other dispatcher cannot send', f'SELECT {send(51)};', actor=5, state='42501')
    case('dispatch reply', f"SELECT {send(51,'Synthetic reply')}->>'id'='2';", rollback=False)
    case('server determines sender and does not expose actor', f"SELECT {messages}->'messages'->0->>'sender'='dispatch' AND NOT ({messages}->'messages'->0 ? 'actor_id');", actor=1)
    for n in range(52,103):
        require(db.sql(f'SELECT {send(n)};', actor=1))
    case('message page bounded to fifty', f"SELECT jsonb_array_length({messages}->'messages')=50 AND {messages}->>'next_cursor' IS NOT NULL;")
    case('older message cursor is exclusive', f"SELECT jsonb_array_length(public.corvia_incident_messages({incident},4)->'messages')=3;")
    case('private message table denied', 'SELECT * FROM ws4_dev_private.messages;', state='42501')
    case('private demo setting denied', 'UPDATE ws4_dev_private.operations_settings SET provider_demo_enabled=true;', state='42501')
    case('service role does not inherit new RPC', f"SET ROLE service_role; SELECT {get};", actor=None,state='42501')
    require(db.sql('CREATE TABLE public.incident_responder_assignments(incident_id bigint);'))
    require(db.sql(f'INSERT INTO public.incident_responder_assignments VALUES({incident});'))
    case('unresolved Fleet assignment blocks closure', f"SELECT {command(16,8,'close',{'text':'Synthetic reason'})};", state='P0001')
    require(db.sql('DROP TABLE public.incident_responder_assignments;'))
    # Concurrent stale commands have exactly one successful version change.
    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
        rs = list(pool.map(lambda n: db.sql(f'SELECT {command(n,8)};',actor=3), (110,111)))
    ok = sum(r.returncode==0 for r in rs)==1 and any('P0001:' in r.stderr for r in rs)
    results.append(dict(name='competing versioned commands have one winner',passed=ok))
    if not ok: raise AssertionError('Command race failed')
    case('closure persists', f"SELECT {command(16,9,'close',{'text':'Synthetic duplicate request; no resource assigned'})}->>'version'='10';", rollback=False)
    case('closed state returned to patient', f"SELECT {get}->>'status'='resolved';", actor=1)
    case('closed incident denies new message', f'SELECT {send(150)};', actor=1, state='P0001')
    case('closed incident denies new command', f'SELECT {command(151,10)};', state='P0001')
    require(db.sql(f"UPDATE ws4_dev_private.memberships SET active=false WHERE user_id='{uid(3)}';"))
    case('revoked member cannot replay', f'SELECT {command()};', state='42501')
    require(db.sql(f"UPDATE ws4_dev_private.memberships SET active=true WHERE user_id='{uid(3)}';"))
    for n,scenario in enumerate(('accepted','rejected','unavailable'),200):
        demo_id=json.loads(require(db.sql(f'SELECT {request(n)};',actor=1)))['incident_id']
        require(db.sql(f'SELECT public.corvia_dispatch_accept_incident({demo_id});',actor=3))
        case(f'demo {scenario} is persisted',f"SELECT public.corvia_dispatch_command({demo_id},'{operation(n+100)}',2,'simulate_provider','{{\"scenario\":\"{scenario}\"}}')->>'version'='3';",rollback=False)
        case(f'patient sees labelled {scenario}',f"SELECT public.corvia_incident_workspace({demo_id})->>'provider_state'='{scenario}' AND (public.corvia_incident_workspace({demo_id})->>'provider_demo')::boolean;",actor=1)


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--pg-bin',type=Path,required=True)
    args=parser.parse_args()
    work=REPO/'build/ws4-operations-db'/uuid.uuid4().hex
    work.mkdir(parents=True)
    db=Database(args.pg_bin.resolve(),work)
    report={'results':[], 'sql_sha256':hashlib.sha256(OPERATIONS.read_bytes()).hexdigest()}
    try:
        db.start(); setup(db); run(db,report['results']); report['passed']=True
    except Exception as error:
        report.update(passed=False,error=str(error)); raise
    finally:
        db.stop(); report['server_stopped']=not db.started
        (work/'result.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
        print('Report: '+str(work/'result.json'),flush=True)

if __name__=='__main__': main()
