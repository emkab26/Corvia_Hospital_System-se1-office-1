"""Rehearse the shared upgrade on the supplied catalog fixture, never a remote database."""
import argparse
import importlib.util
import json
from pathlib import Path
import uuid
from run_tests import Database, ROOT, uid
from run_patient_intake_tests import REPO, require, A, B, request, operation

spec=importlib.util.spec_from_file_location('build_shared',REPO/'tools/build_ws4_shared_upgrade.py')
builder=importlib.util.module_from_spec(spec)
spec.loader.exec_module(builder)

def run(db,results):
    def check(name,sql,actor=None,state=None,expected='t'):
        result=db.sql(sql,actor=actor)
        ok=(result.returncode!=0 and (state in result.stderr)) if state else (result.returncode==0 and result.stdout.strip()==expected)
        results.append(dict(name=name,passed=ok,stdout=result.stdout.strip(),stderr=result.stderr.strip()))
        print(('PASS ' if ok else 'FAIL ')+name,flush=True)
        if not ok: raise AssertionError(name+': '+result.stdout+result.stderr)
    require(db.sql((ROOT/'baseline/catalog.sql').read_text(encoding='utf-8')))
    require(db.sql((ROOT/'baseline/fixtures.sql').read_text(encoding='utf-8')))
    require(db.sql("CREATE TABLE public.ws4_test_unrelated(id int PRIMARY KEY, value text); INSERT INTO public.ws4_test_unrelated VALUES(1,'unchanged');"))
    sql=builder.build()
    check('owner approval is required',sql,state='Database owner must review')
    check('failed approval leaves no new schema',"SELECT to_regnamespace('ws4_private') IS NULL;")
    approved="SET corvia.ws4_shared_review='approved';\n"+sql
    check('invalid legacy statuses refuse migration',approved,state='Legacy incidents require explicit data review')
    check('invalid legacy rows preserved',"SELECT count(*)=2 FROM public.incidents WHERE status IS NULL OR status='unrecognised';")
    # Test-fixture correction only. The real upgrade never repairs these silently.
    require(db.sql("UPDATE public.incidents SET status='pending' WHERE id IN (105,106);"))
    require(db.sql("CREATE FUNCTION public.register_auth_user_temp() RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $$ BEGIN NULL; END $$; GRANT EXECUTE ON FUNCTION public.register_auth_user_temp() TO anon;"))
    check('anonymous privileged registration blocks rollout',approved,state='anonymous privileged registration')
    require(db.sql('REVOKE ALL ON FUNCTION public.register_auth_user_temp() FROM PUBLIC,anon;'))
    require(db.sql("ALTER TABLE public.profiles ALTER COLUMN role SET DEFAULT 'admin';"))
    check('unsafe signup default refuses migration',approved,state='Profile defaults or RLS differ')
    require(db.sql("ALTER TABLE public.profiles ALTER COLUMN role SET DEFAULT 'patient';"))
    require(db.sql("CREATE ROLE ws4_unsafe_parent; GRANT UPDATE(role) ON public.profiles TO ws4_unsafe_parent; GRANT ws4_unsafe_parent TO authenticated;"))
    check('inherited authority grants refuse migration',approved,state='Inherited profile authority privileges require review')
    require(db.sql('REVOKE ws4_unsafe_parent FROM authenticated;'))
    result=db.sql(approved)
    if result.returncode: raise AssertionError(result.stdout+result.stderr)
    results.append(dict(name='shared upgrade applies atomically to reviewed catalog fixture',passed=True))
    check('existing incident data and identifiers preserved',"SELECT count(*)=6 AND min(id)=101 AND max(id)=106 AND bool_and(latitude=-30 AND longitude=25) FROM public.incidents;")
    check('unrelated module unchanged',"SELECT value='unchanged' FROM public.ws4_test_unrelated WHERE id=1;")
    check('profiles and clinical role preserved',f"SELECT role='doctor' AND first_name='Synthetic 7' FROM public.profiles WHERE user_id='{uid(7)}';")
    check('legacy incident routing is not invented',"SELECT bool_and(organisation_id IS NULL) FROM public.incidents;")
    check('no fabricated historical events',"SELECT count(*)=0 FROM ws4_private.incident_events;")
    check('provider demo remains off',"SELECT NOT provider_demo_enabled FROM ws4_private.operations_settings;")
    check('rerun refuses existing upgrade',approved,state='upgrade already installed')
    check('patient cannot self-promote',f"UPDATE public.profiles SET role='dispatcher' WHERE user_id='{uid(1)}';",actor=1,state='42501')
    check('old profile role grants no dispatch access','SELECT public.corvia_dispatch_access_context();',actor=3,state='42501')
    require(db.sql(f"""
      INSERT INTO ws4_private.organisations VALUES ('{A}','Test region A'),('{B}','Test region B');
      INSERT INTO ws4_private.patient_routes VALUES ('{uid(1)}','{A}'),('{uid(2)}','{B}');
      INSERT INTO ws4_private.memberships VALUES ('{uid(3)}','{A}','dispatcher',true),('{uid(4)}','{B}','dispatcher',true);
    """))
    a=json.loads(require(db.sql(f'SELECT {request(700)};',actor=1)))['incident_id']
    b=json.loads(require(db.sql(f'SELECT {request(701)};',actor=2)))['incident_id']
    check('old broad dispatch policy cannot cross scope',f'SELECT count(*)=0 FROM public.incidents WHERE id={b};',actor=3)
    check('scoped new incident can be read',f'SELECT count(*)=1 FROM public.incidents WHERE id={a};',actor=3)
    check('legacy unsafe coordinate update denied',f'UPDATE public.incidents SET latitude=0 WHERE id={a};',actor=1,state='42501')
    require(db.sql(f'SELECT public.corvia_dispatch_accept_incident({a});',actor=3))
    check('new incident command works with legacy triggers',f"SELECT public.corvia_dispatch_command({a},'{operation(702)}',2,'note','{{\"text\":\"Synthetic shared rehearsal\"}}')->>'version'='3';",actor=3)
    check('patient does not receive internal notes',f"SELECT public.corvia_incident_workspace({a})->'recent_actions'='[]'::jsonb;",actor=1)
    check('message contract works on upgraded catalog',f"SELECT public.corvia_send_incident_message({a},'{operation(703)}','Synthetic shared message')->>'incident_id'='{a}';",actor=1)
    check('cross-org messages denied',f'SELECT public.corvia_incident_messages({a});',actor=4,state='42501')
    check('close works without an assignment',f"SELECT public.corvia_dispatch_command({a},'{operation(704)}',3,'close','{{\"text\":\"Synthetic closure\"}}')->>'version'='4';",actor=3)
    check('second patient cancellation works',f"SELECT public.corvia_patient_cancel_emergency('{operation(701)}',1)->>'status'='cancelled';",actor=2)
    check('history has true created claimed updated resolved sequence',f"SELECT public.corvia_incident_history({a})->'events'->3->>'event_type'='resolved';",actor=1)
    unit,crew=str(uuid.uuid4()),str(uuid.uuid4())
    require(db.sql(f"""
      INSERT INTO ws4_private.response_units(id,organisation_id,label,ready,readiness_valid_until,latitude,longitude,location_at,location_source)
        VALUES('{unit}','{A}','Synthetic shared unit',false,now()+interval '1 hour',-26,28,now(),'operator');
      INSERT INTO ws4_private.response_crews(id,organisation_id,unit_id,label,active,verified_until,shift_start,shift_end)
        VALUES('{crew}','{A}','{unit}','Synthetic shared crew',true,now()+interval '1 day',now()-interval '1 hour',now()+interval '8 hours');
      INSERT INTO ws4_private.response_crew_members VALUES('{crew}','{uid(7)}',true,now()+interval '1 day');
      UPDATE ws4_private.response_units SET ready=true WHERE id='{unit}';
      INSERT INTO ws4_private.response_readiness_reviews VALUES('{uid(6)}','{operation(760)}','{unit}',1,'{{"text":"Synthetic shared review"}}','{{}}',true,now()+interval '1 hour',now());
    """))
    response=json.loads(require(db.sql(f'SELECT {request(750)};',actor=1)))['incident_id']
    require(db.sql(f'SELECT public.corvia_dispatch_accept_incident({response});',actor=3))
    version=require(db.sql(f"SELECT version FROM ws4_private.response_units WHERE id='{unit}';"))
    allocation=json.loads(require(db.sql(f"SELECT public.corvia_response_command({response},'{operation(751)}',2,'assign','{{\"unit_id\":\"{unit}\",\"unit_version\":\"{version}\",\"purpose\":\"primary\"}}');",actor=3)))
    check('shared response unit is reserved',f"SELECT count(*)=1 FROM ws4_private.response_assignments WHERE incident_id={response} AND active;")
    check('explicit crew membership works without rewriting clinical profile',f"SELECT public.corvia_response_workspace({response})->>'role'='crew';",actor=7)
    check('unrelated shared patient denied crew workspace',f'SELECT public.corvia_response_workspace({response});',actor=2,state='42501')
    check('shared response prevents premature close',f"SELECT public.corvia_dispatch_command({response},'{operation(752)}',3,'close','{{\"text\":\"invalid early close\"}}');",actor=3,state='P0001')
    check('shared crew acknowledgement persists',f"SELECT public.corvia_response_command({response},'{operation(753)}',3,'acknowledge','{{\"assignment_id\":\"{allocation['assignment_id']}\"}}')->>'version'='4';",actor=7)
    check('existing doctor role remains unchanged',f"SELECT role='doctor' FROM public.profiles WHERE user_id='{uid(7)}';")
    # Preflight is read-only and excludes row contents.
    result=db.sql((REPO/'supabase/scripts/ws4_release/preflight.sql').read_text(encoding='utf-8'))
    require(result)
    metadata=json.loads(result.stdout)
    assert metadata['upgrade_present'] is True
    results.append(dict(name='read-only preflight returns metadata after upgrade',passed=True))

def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--pg-bin',type=Path,required=True);args=parser.parse_args()
    work=REPO/'build/ws4-shared-rehearsal'/uuid.uuid4().hex;work.mkdir(parents=True)
    db=Database(args.pg_bin.resolve(),work);report={'results':[]}
    try:
        db.start();run(db,report['results']);report['passed']=True
    except Exception as error:
        report.update(passed=False,error=str(error));raise
    finally:
        db.stop();report['server_stopped']=not db.started
        (work/'result.json').write_text(json.dumps(report,indent=2),encoding='utf-8');print('Report: '+str(work/'result.json'),flush=True)

if __name__=='__main__': main()
