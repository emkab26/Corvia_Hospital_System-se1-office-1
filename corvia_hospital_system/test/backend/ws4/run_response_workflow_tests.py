"""Response contract tests against a new disposable PostgreSQL cluster only."""
import argparse
import concurrent.futures
import json
from pathlib import Path
import uuid
import sys
from run_dispatch_operations_tests import setup, REPO, Database, require, uid, A, B, request, operation

DELTA = REPO / 'supabase/scripts/ws4_dev/005_response_workflow.sql'
U1, U2, U3, C1, C2, C3, H = [str(uuid.UUID(int=n)) for n in range(101, 108)]


def run(db, results):
    require(db.sql('CREATE TABLE public.hospitals(id uuid PRIMARY KEY,name text,latitude double precision,longitude double precision,is_active boolean DEFAULT true);'))
    require(db.sql(DELTA.read_text(encoding='utf-8')))
    require(db.sql(f"""
      INSERT INTO auth.users VALUES ('{uid(8)}'),('{uid(9)}'),('{uid(10)}');
      INSERT INTO public.profiles(user_id) VALUES ('{uid(8)}'),('{uid(9)}'),('{uid(10)}');
      INSERT INTO public.hospitals(id,name,latitude,longitude) VALUES ('{H}','Synthetic receiving hospital',-26,28);
      INSERT INTO ws4_dev_private.response_destinations VALUES ('{H}','{A}',true);
      INSERT INTO ws4_dev_private.response_receivers VALUES ('{uid(10)}','{H}',true);
      INSERT INTO ws4_dev_private.response_units(id,organisation_id,label,ready,readiness_valid_until,latitude,longitude,location_at,location_source)
        VALUES ('{U1}','{A}','Synthetic unit A',true,now()+interval '1 hour',-26,28,now(),'operator'),
        ('{U2}','{A}','Synthetic unit B',true,now()+interval '1 hour',-26,28,now(),'operator'),
        ('{U3}','{B}','Other organisation unit',true,now()+interval '1 hour',-26,28,now(),'operator');
      INSERT INTO ws4_dev_private.response_crews(id,organisation_id,unit_id,label,active,verified_until,shift_start,shift_end)
        VALUES ('{C1}','{A}','{U1}','Crew A',true,now()+interval '1 day',now()-interval '1 hour',now()+interval '8 hours'),
        ('{C2}','{A}','{U2}','Crew B',true,now()+interval '1 day',now()-interval '1 hour',now()+interval '8 hours');
      INSERT INTO ws4_dev_private.response_crew_members VALUES ('{C1}','{uid(8)}',true,now()+interval '1 day'),('{C2}','{uid(9)}',true,now()+interval '1 day');
      UPDATE ws4_dev_private.response_units SET ready=true,version=1;
      INSERT INTO ws4_dev_private.response_fleet_reviewers VALUES('{uid(6)}','{A}',true);
      INSERT INTO ws4_dev_private.response_readiness_reviews
        SELECT '{uid(6)}',gen_random_uuid(),id,1,'{{"text":"Synthetic verified fixture"}}','{{}}',true,now()+interval '1 hour',now() FROM ws4_dev_private.response_units;
    """))
    def case(name, sql, actor=3, state=None, expected='t', rollback=False):
        r = db.sql(sql, actor=actor, role='anon' if actor == 0 else 'authenticated', rollback=rollback)
        passed = (r.returncode != 0 and f'{state}:' in r.stderr) if state else (r.returncode == 0 and r.stdout.strip() == expected)
        results.append(dict(name=name, passed=passed))
        print(('PASS ' if passed else 'FAIL ') + name, flush=True)
        if not passed:
            raise AssertionError(name + ': ' + r.stdout + r.stderr)
    def create(n):
        i=json.loads(require(db.sql(f'SELECT {request(n)};',actor=1)))['incident_id']
        require(db.sql(f'SELECT public.corvia_dispatch_accept_incident({i});',actor=3))
        return i
    incident=create(1000)
    n=2000
    def cmd(action, payload, version=None, incident_id=None, op=None):
        nonlocal n
        n+=1
        i=incident_id or incident
        v=version or require(db.sql(f'SELECT version FROM public.incidents WHERE id={i};'))
        data=json.dumps(payload).replace("'","''")
        return f"public.corvia_response_command({i},'{operation(op or n)}',{v},'{action}','{data}'::jsonb)"
    workspace=f'public.corvia_response_workspace({incident})'
    case('two scoped units visible',f"SELECT jsonb_array_length({workspace}->'units')=2;")
    for actor in (0,1,2,4,7,8,10):
        case(f'unassigned workspace denied actor {actor}',f'SELECT {workspace};',actor=actor,state='42501')
    case('private units cannot be forged','UPDATE ws4_dev_private.response_units SET ready=true;',state='42501')
    case('private audit cannot be deleted','DELETE FROM ws4_dev_private.response_events;',state='42501')
    payload={'unit_id':U1,'unit_version':'1','purpose':'primary'}
    case('other dispatcher cannot allocate',f"SELECT {cmd('assign',payload)};",actor=5,state='42501')
    case('foreign unit denied',f"SELECT {cmd('assign',{**payload,'unit_id':U3})};",state='P0001')
    for column,value in [('ready','false'),('readiness_valid_until',"now()-interval '1 second'"),('location_at',"now()-interval '1 hour'")]:
        case(f'ineligible unit {column}',f"SET ROLE postgres; UPDATE ws4_dev_private.response_units SET {column}={value} WHERE id='{U1}'; SET ROLE authenticated; SELECT {cmd('assign',payload)};",state='P0001',rollback=True)
    assign=cmd('assign',payload,op=3000)
    first=json.loads(require(db.sql(f'SELECT {assign};',actor=3)))
    assignment=first['assignment_id']
    second=json.loads(require(db.sql(f'SELECT {assign};',actor=3)))
    assert first==second
    results.append(dict(name='allocation retry stable',passed=True))
    p={'assignment_id':assignment}
    case('crew receives real assignment',f"SELECT {workspace}->>'role'='crew';",actor=8)
    case('crew inbox contains same incident',f"SELECT public.corvia_response_inbox()->'incidents' ? '{incident}';",actor=8)
    case('other crew denied',f'SELECT {workspace};',actor=9,state='42501')
    other=create(1001)
    case('unit cannot be double booked',f"SELECT {cmd('assign',payload,incident_id=other)};",state='P0001')
    case('active resource prevents closure',f"SELECT public.corvia_dispatch_command({incident},'{operation(3001)}',3,'close','{{\"text\":\"reason\"}}');",state='P0001')
    case('dispatcher cannot acknowledge for crew',f"SELECT {cmd('acknowledge',p)};",state='42501')
    case('acknowledge',f"SELECT {cmd('acknowledge',p)}->>'incident_id'='{incident}';",actor=8)
    case('invalid jump rejected',f"SELECT {cmd('progress',{**p,'state':'transporting'})};",actor=8,state='P0001')
    case('crew cannot resolve exception',f"SELECT {cmd('resolve_exception',{**p,'text':'reason'})};",actor=8,state='42501')
    for state in ('en_route','on_scene'):
        case(state,f"SELECT {cmd('progress',{**p,'state':state})}->>'incident_id'='{incident}';",actor=8)
    case('exception recorded',f"SELECT {cmd('exception',{**p,'reason':'unsafe_scene','text':'Synthetic safety issue'})}->>'incident_id'='{incident}';",actor=8)
    case('new exception cannot erase unresolved safety issue',f"SELECT {cmd('exception',{**p,'reason':'backup','text':'Cannot overwrite safety issue'})};",actor=8,state='P0001')
    case('unresolved exception stops progress',f"SELECT {cmd('progress',{**p,'state':'transporting'})};",actor=8,state='P0001')
    case('supervisor resolves with reason',f"SELECT {cmd('resolve_exception',{**p,'text':'Synthetic safe access confirmed'})}->>'incident_id'='{incident}';",actor=6)
    case('destination required before transport',f"SELECT {cmd('progress',{**p,'state':'transporting'})};",actor=8,state='P0001')
    case('canonical hospital selected',f"SELECT {cmd('destination',{**p,'hospital_id':H,'text':'Receiving destination selected'})}->>'incident_id'='{incident}';",actor=8)
    case('transport requires patient match',f"SELECT {cmd('progress',{**p,'state':'transporting'})};",actor=8,state='P0001')
    case('crew records patient match evidence',f"SELECT {cmd('confirm_patient',{**p,'text':'Synthetic incident subject matched using supplied demo identity'})}->>'incident_id'='{incident}';",actor=8)
    for state in ('transporting','at_hospital','handover_requested'):
        case(state,f"SELECT {cmd('progress',{**p,'state':state,'text':'Synthetic handover summary'})}->>'incident_id'='{incident}';",actor=8)
    case('crew cannot confirm hospital receipt',f"SELECT {cmd('handover_accept',{**p,'text':'Received'})};",actor=8,state='42501')
    case('receiving user confirms handover',f"SELECT {cmd('handover_accept',{**p,'text':'Synthetic patient received'})}->>'incident_id'='{incident}';",actor=10)
    case('released crew loses incident access',f'SELECT {workspace};',actor=8,state='42501')
    case('completed unit requires readiness review',f"SELECT {workspace}->'units'->0->>'reason'='Readiness missing or expired';")
    version=require(db.sql(f'SELECT version FROM public.incidents WHERE id={incident};'))
    case('closure after handover',f"SELECT public.corvia_dispatch_command({incident},'{operation(3500)}',{version},'close','{{\"text\":\"Handover confirmed\"}}')->>'command'='close';")
    # Race for one unit from distinct incidents: exactly one reservation survives.
    i2=create(1002)
    commands=[cmd('assign',{'unit_id':U2,'unit_version':'1','purpose':'primary'},incident_id=i) for i in (other,i2)]
    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
        rs=list(pool.map(lambda q:db.sql(f'SELECT {q};',actor=3),commands))
    assert sum(r.returncode==0 for r in rs)==1, [r.stdout+r.stderr for r in rs]
    results.append(dict(name='concurrent allocations have one winner',passed=True))
    winner=json.loads(next(r.stdout for r in rs if r.returncode==0))
    wi,wa=winner['incident_id'],winner['assignment_id']
    wp={'assignment_id':wa}
    require(db.sql(f"UPDATE ws4_dev_private.response_assignments SET acknowledgement_deadline=now()-interval '1 second' WHERE id='{wa}';"))
    case('late crew acknowledgement denied',f"SELECT {cmd('acknowledge',wp,incident_id=wi)};",actor=9,state='P0001')
    case('timeout remains visible',f"SELECT (public.corvia_response_workspace({wi})->'assignments'->0->>'overdue')::boolean;")
    case('dispatch releases timed out offer',f"SELECT {cmd('expire',wp,incident_id=wi)}->>'incident_id'='{wi}';")
    case('old crew update denied after release',f"SELECT {cmd('progress',{**wp,'state':'en_route'},incident_id=wi)};",actor=9,state='42501')
    case('foreign receiver cannot see other incident',f'SELECT public.corvia_response_workspace({wi});',actor=10,state='42501')
    case('anonymous inbox denied','SELECT public.corvia_response_inbox();',actor=0,state='42501')
    case('ordinary patient cannot open crew inbox','SELECT public.corvia_response_inbox();',actor=1,state='42501')
    require(db.sql(f"UPDATE ws4_dev_private.response_units SET ready=true,readiness_valid_until=now()+interval '1 hour',location_at=now() WHERE id IN ('{U1}','{U2}');"))
    uv=require(db.sql(f"SELECT version FROM ws4_dev_private.response_units WHERE id='{U1}';"))
    allocated=json.loads(require(db.sql(f"SELECT {cmd('assign',{'unit_id':U1,'unit_version':uv,'purpose':'primary'},incident_id=wi)};",actor=3)))
    wp={'assignment_id':allocated['assignment_id']}
    case('previous crew cannot update replacement',f"SELECT {cmd('progress',{**wp,'state':'en_route'},incident_id=wi)};",actor=9,state='42501')
    case('active roster edits refused',f"SET ROLE postgres; UPDATE ws4_dev_private.response_crews SET shift_end=now()+interval '10 hours' WHERE id='{C1}';",state='P0001',rollback=True)
    case('active member replacement refused',f"SET ROLE postgres; DELETE FROM ws4_dev_private.response_crew_members WHERE crew_id='{C1}';",state='P0001',rollback=True)
    require(db.sql(f"UPDATE public.profiles SET is_active=false WHERE user_id='{uid(8)}';"))
    case('revoked crew cannot acknowledge',f"SELECT {cmd('acknowledge',wp,incident_id=wi)};",actor=8,state='42501')
    case('dispatch sees crew revocation',f"SELECT NOT (public.corvia_response_workspace({wi})->'assignments'->1->>'crew_available')::boolean;")
    require(db.sql(f"UPDATE public.profiles SET is_active=true WHERE user_id='{uid(8)}';"))
    case('replacement crew acknowledges',f"SELECT {cmd('acknowledge',wp,incident_id=wi)}->>'incident_id'='{wi}';",actor=8)
    case('dispatcher cannot withdraw acknowledged crew',f"SELECT {cmd('withdraw',{**wp,'text':'review'},incident_id=wi)};",state='42501')
    case('null progress refused',f"SELECT {cmd('progress',wp,incident_id=wi)};",actor=8,state='P0001')
    case('fresh crew device location recorded',f"SELECT {cmd('location',{**wp,'latitude':-26.1,'longitude':28.1,'accuracy_metres':12},incident_id=wi)}->>'incident_id'='{wi}';",actor=8)
    case('invalid device location refused',f"SELECT {cmd('location',{**wp,'latitude':95,'longitude':28.1,'accuracy_metres':12},incident_id=wi)};",actor=8,state='22023')
    for state in ('en_route','on_scene'):
        case('replacement '+state,f"SELECT {cmd('progress',{**wp,'state':state},incident_id=wi)}->>'incident_id'='{wi}';",actor=8)
    case('backup request persisted',f"SELECT {cmd('exception',{**wp,'reason':'backup','text':'Synthetic additional help'},incident_id=wi)}->>'incident_id'='{wi}';",actor=8)
    backup=json.loads(require(db.sql(f"SELECT {cmd('assign',{'unit_id':U2,'unit_version':'1','purpose':'backup'},incident_id=wi)};",actor=3)))
    results.append(dict(name='backup reserves second unit for same incident',passed=True))
    case('crew cannot mutate other assignment',f"SELECT {cmd('acknowledge',{'assignment_id':backup['assignment_id']},incident_id=wi)};",actor=8,state='42501')
    case('backup crew receives shared incident',f"SELECT public.corvia_response_workspace({wi})->>'role'='crew';",actor=9)
    case('response message saved',f"SELECT {cmd('message',{**wp,'text':'Synthetic response message'},incident_id=wi)}->>'incident_id'='{wi}';",actor=8)
    replay=cmd('message',{**wp,'text':'same operation'},incident_id=wi,op=9000)
    receipt=require(db.sql(f'SELECT {replay};',actor=8))
    case('crew message replay is idempotent',f'SELECT {replay};',actor=8,expected=receipt)
    case('operation payload cannot change',f"SELECT {cmd('message',{**wp,'text':'different'},incident_id=wi,op=9000)};",actor=8,state='22023')
    before=require(db.sql(f'SELECT version FROM public.incidents WHERE id={wi};'))
    require(db.sql("CREATE FUNCTION ws4_dev_private.reject_response_test() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION 'synthetic audit failure'; END $$; CREATE TRIGGER reject_response_test BEFORE INSERT ON ws4_dev_private.response_events FOR EACH ROW EXECUTE FUNCTION ws4_dev_private.reject_response_test();"))
    case('audit failure rejects command',f"SELECT {cmd('message',{**wp,'text':'must roll back'},incident_id=wi)};",actor=8,state='P0001')
    assert require(db.sql(f'SELECT version FROM public.incidents WHERE id={wi};'))==before
    results.append(dict(name='audit failure rolls incident version back',passed=True))
    require(db.sql('DROP TRIGGER reject_response_test ON ws4_dev_private.response_events;'))
    case('supervisor withdrawal with reason',f"SELECT {cmd('withdraw',{**wp,'text':'Synthetic reassignment decision'},incident_id=wi)}->>'incident_id'='{wi}';",actor=6)
    case('withdrawn crew cannot replay old message',f'SELECT {replay};',actor=8,state='42501')
    case('idle crew can find own unit',f"SELECT public.corvia_response_my_unit()->'unit'->>'id'='{U1}';",actor=8)
    uv=require(db.sql(f"SELECT version FROM ws4_dev_private.response_units WHERE id='{U1}';"))
    timestamp=require(db.sql('SELECT now()::text;'))
    location=f"public.corvia_response_unit_location('{U1}','{operation(9500)}',{uv},jsonb_build_object('latitude',-26.2,'longitude',28.2,'accuracy_metres',8,'occurred_at','{timestamp}'))"
    case('unrelated crew cannot update unit location',f'SELECT {location};',actor=9,state='42501')
    receipt=require(db.sql(f'SELECT {location};',actor=8))
    case('idle unit location replay stable',f'SELECT {location};',actor=8,expected=receipt)
    case('location does not approve readiness',f"SELECT NOT ready FROM ws4_dev_private.response_units WHERE id='{U1}';",actor=None)
    case('completed incident available to scoped dispatch',f"SELECT public.corvia_response_inbox(true)->'incidents' ? '{incident}';")
    case('completed history includes closure',f"SELECT public.corvia_response_workspace({incident})->'events'->0->>'command'='resolved';")
    uv=require(db.sql(f"SELECT version FROM ws4_dev_private.response_units WHERE id='{U1}';"))
    expiry=require(db.sql("SELECT (now()+interval '1 hour')::text;"))
    checks={key:True for key in ['inspection','equipment','oxygen','fuel','communications','cleaning','documents','no_faults','capability']}
    checks.update(text='Synthetic independent readiness review',valid_until=expiry)
    def review(payload=checks,op=9600):
        data=json.dumps(payload).replace("'","''")
        return f"public.corvia_response_review_readiness('{U1}','{operation(op)}',{uv},'{data}'::jsonb)"
    case('dispatcher cannot self-grant fleet review',f'SELECT {review()};',actor=3,state='42501')
    case('incomplete readiness checklist refused',f"SELECT {review({'text':'missing checks'})};",actor=6,state='22023')
    case('crew cannot approve own readiness',f"SET ROLE postgres; INSERT INTO ws4_dev_private.response_fleet_reviewers VALUES('{uid(8)}','{A}',true); SET ROLE authenticated; SELECT {review()};",actor=8,state='42501',rollback=True)
    receipt=require(db.sql(f'SELECT {review()};',actor=6))
    case('readiness review retry is stable',f'SELECT {review()};',actor=6,expected=receipt)
    case('readiness review restores eligibility',f"SELECT ws4_dev_private.response_unit_reason('{U1}')='Eligible';",actor=None)
    uv=require(db.sql(f"SELECT version FROM ws4_dev_private.response_units WHERE id='{U1}';"))
    require(db.sql(f"SELECT {review({**checks,'oxygen':False},9601)};",actor=6))
    case('failed inspection makes unit unavailable',f"SELECT NOT ready FROM ws4_dev_private.response_units WHERE id='{U1}';",actor=None)
    sys.path.insert(0,str(REPO/'tools'))
    from build_ws4_response_demo import build
    demo_org,demo_hospital=str(uuid.UUID(int=301)),str(uuid.UUID(int=302))
    require(db.sql(f"INSERT INTO ws4_dev_private.organisations VALUES('{demo_org}','Synthetic generator organisation'); INSERT INTO public.hospitals(id,name,latitude,longitude) VALUES('{demo_hospital}','Synthetic generator hospital',-26,28);"))
    for number in range(11,17):
        require(db.sql(f"INSERT INTO auth.users VALUES('{uid(number)}'); INSERT INTO public.profiles(user_id) VALUES('{uid(number)}');"))
    generated=build(demo_org,demo_hospital,*[uid(n) for n in range(11,17)])
    require(db.sql(generated))
    case('generated provisioning leaves units unavailable until reviewed',f"SELECT count(*)=2 AND NOT bool_or(ready) FROM ws4_dev_private.response_units WHERE organisation_id='{demo_org}';",actor=None)
    assert db.sql(generated).returncode!=0
    case('repeated provisioning does not reset units',f"SELECT count(*)=2 FROM ws4_dev_private.response_units WHERE organisation_id='{demo_org}';",actor=None)


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--pg-bin',type=Path,required=True)
    args=parser.parse_args()
    work=REPO/'build/ws4-response-db'/uuid.uuid4().hex
    work.mkdir(parents=True)
    db=Database(args.pg_bin.resolve(),work)
    report={'results':[]}
    try:
        db.start(); setup(db); run(db,report['results']); report['passed']=True
    except Exception as error:
        report.update(passed=False,error=str(error)); raise
    finally:
        db.stop(); report['server_stopped']=not db.started
        (work/'result.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
        print('Report: '+str(work/'result.json'),flush=True)

if __name__=='__main__': main()
