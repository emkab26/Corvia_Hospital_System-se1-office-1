"""Test corrected profile permissions using the 12 October audit and local PG15.

No remote URL is accepted. Audit RPC bodies/policies are loaded unchanged;
missing dependent tables/helpers are EXPLICIT synthetic substitutes, not proof
of exact hosted compatibility. --postgrest adds real signed JWT HTTP tests.
"""
import argparse
import base64
import hashlib
import hmac
import importlib.util
import json
import os
from pathlib import Path
import re
import secrets
import socket
import subprocess
import time
import urllib.request
import urllib.error
import uuid

from run_tests import Database, ROOT, uid, FLAGS
from run_patient_intake_tests import REPO, require

AUDIT_HASH = "7c6de51227fc33ee1f8b93baba66d95577878a1a10d4c28c90d29129da3ac57e"
HOSPITAL = "aaaaaaaa-1111-4111-8111-111111111111"
LAB = "aaaaaaaa-2222-4222-8222-222222222222"


def fixture(db, audit):
    require(db.sql((ROOT / "baseline/catalog.sql").read_text()))
    require(db.sql((ROOT / "baseline/fixtures.sql").read_text()))
    require(db.sql("UPDATE public.incidents SET status='pending' WHERE id IN (105,106);"))
    # Additional dependency shapes from the existing synthetic staff test.
    source = (REPO / "test/backend/staff_accounts_test.mjs").read_text()
    for match in re.finditer(r"  create table public\.(\w+)\([\s\S]*?\n  \);", source):
        if match[1] != "profiles":
            require(db.sql(match[0]))
    require(db.sql("""
      ALTER TABLE auth.users ADD COLUMN email text;
      UPDATE auth.users SET email='synthetic-'||right(id::text,1)||'@example.test';
      GRANT SELECT ON auth.users TO supabase_admin;
      ALTER TABLE public.lab_worker_accounts ADD COLUMN id uuid DEFAULT gen_random_uuid(),
        ADD COLUMN lab_organization_id uuid, ADD UNIQUE(profile_id);
      ALTER TABLE public.pharmacists ADD COLUMN phone text,
        ADD COLUMN created_at timestamptz DEFAULT now(),
        ADD COLUMN license_verification_status text, ADD COLUMN license_verified_at timestamptz,
        ADD COLUMN license_verified_by uuid;
      CREATE TABLE public.hospital_lab_access_audit(lab_organization_id uuid,
        actor_user_id uuid,target_profile_id uuid,action text,details jsonb);
      CREATE TABLE public.patients(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
        profile_id uuid,hospital_id uuid,patient_number text,first_name text,surname text,
        phone text,email text,date_of_birth date,gender text,address text,blood_type text,
        allergies text,medical_conditions text,emergency_contact_name text,
        emergency_contact_phone text,medical_aid_provider text,medical_aid_member_number text,
        qr_code_value text,is_active boolean,updated_at timestamptz);
    """))
    require(db.sql((REPO / "supabase/scripts/workstreams/19_install_hospital_staff_accounts.sql").read_text()))
    require(db.sql("ALTER FUNCTION public.corvia_admin_staff_hospital_id() OWNER TO supabase_admin;"))
    # Helpers were NOT exported in the audit. These strict test doubles model
    # actor scoping, but cannot certify the real helpers or linked read policies.
    require(db.sql("""
      CREATE FUNCTION public.corvia_admin_hospital_id() RETURNS uuid
      LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$ DECLARE h uuid; BEGIN
        h:=public.corvia_admin_staff_hospital_id();
        IF h IS NULL THEN RAISE EXCEPTION 'Hospital administrator access is required'; END IF;
        RETURN h; END $$;
      CREATE FUNCTION public.doctor_can_view_linked_patient_profile(uuid) RETURNS boolean
        LANGUAGE sql AS $$ SELECT false $$;
      CREATE FUNCTION public.corvia_pharmacist_can_access_profile(uuid) RETURNS boolean
        LANGUAGE sql AS $$ SELECT false $$;
      CREATE FUNCTION public.corvia_current_hospital_lab_admin_context() RETURNS jsonb
      LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$ DECLARE l uuid; BEGIN
        SELECT a.lab_organization_id INTO l FROM public.hospital_lab_admin_accounts a
          JOIN public.profiles p ON p.id=a.profile_id
          WHERE p.user_id=auth.uid() AND p.is_active IS TRUE AND a.is_active;
        IF l IS NULL THEN RAISE EXCEPTION 'Lab access denied' USING ERRCODE='42501'; END IF;
        RETURN jsonb_build_object('lab_organization_id',l); END $$;
      CREATE FUNCTION public.corvia_current_private_lab_admin_context() RETURNS jsonb
        LANGUAGE sql SECURITY DEFINER SET search_path='' AS $$
          SELECT public.corvia_current_hospital_lab_admin_context() $$;
      CREATE FUNCTION public.corvia_lab_admin_candidate(p uuid,l uuid) RETURNS boolean
        LANGUAGE sql SECURITY DEFINER SET search_path='' AS $$ SELECT
          EXISTS(SELECT 1 FROM public.profiles WHERE id=p AND is_active IS TRUE
            AND role IN ('patient','lab_worker'))
          AND NOT EXISTS(SELECT 1 FROM public.lab_worker_accounts
            WHERE profile_id=p AND lab_organization_id<>l) $$;
      CREATE OR REPLACE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE AS $$
        SELECT coalesce(nullif(current_setting('request.jwt.claim.sub',true),''),
          nullif(current_setting('request.jwt.claims',true),'')::jsonb->>'sub')::uuid $$;
      GRANT SELECT ON public.hospital_admins,public.patients TO authenticated;
      DO $$ DECLARE t record; BEGIN
        FOR t IN SELECT tablename FROM pg_tables WHERE schemaname='public' LOOP
          EXECUTE format('ALTER TABLE public.%I OWNER TO supabase_admin',t.tablename);
        END LOOP;
      END $$;
    """))
    for policy in audit["policies"]:
        name = '"' + policy['policyname'].replace('"', '""') + '"'
        sql = f"DROP POLICY IF EXISTS {name} ON public.profiles; CREATE POLICY {name} ON public.profiles AS {policy['permissive']} FOR {policy['cmd']} TO authenticated"
        if policy['qual']: sql += " USING (" + policy['qual'] + ")"
        if policy['with_check']: sql += " WITH CHECK (" + policy['with_check'] + ")"
        require(db.sql("SET search_path=public,auth; " + sql + ";"))
    for grant in audit['column_grants']:
        require(db.sql(f"GRANT {grant['privilege_type']} ({grant['column_name']}) ON public.profiles TO {grant['grantee']};"))
    for function in audit['profile_writing_functions']:
        # Auth registration needs the full GoTrue catalog/extensions; its grant
        # is covered separately in the atomic suite, never call it here.
        if function['signature'].startswith('register_auth_user_temp'): continue
        signature = 'public.' + function['signature']
        require(db.sql(function['function_sql'] + f"; ALTER FUNCTION {signature} OWNER TO {function['owner']}; REVOKE ALL ON FUNCTION {signature} FROM PUBLIC,anon,authenticated;"))
        for role,key in [('anon','anon_execute'),('authenticated','authenticated_execute')]:
            if function[key]: require(db.sql(f"GRANT EXECUTE ON FUNCTION {signature} TO {role};"))
    require(db.sql(f"""
      INSERT INTO public.profiles(user_id,role,user_type) VALUES('{uid(9)}','hospital_admin','hospital_admin');
      INSERT INTO public.hospitals(id,name) VALUES('{HOSPITAL}','Synthetic hospital');
      INSERT INTO public.hospital_admins(hospital_id,profile_id) VALUES('{HOSPITAL}','{uid(9)}');
      INSERT INTO public.lab_organizations(id,name,lab_type,hospital_id)
        VALUES('{LAB}','Synthetic lab','hospital','{HOSPITAL}');
    """))


def run(db, audit, results):
    fixture(db, audit)
    def check(name, sql, actor=None, error=None):
        response=db.sql(sql,actor=actor)
        ok=(response.returncode != 0 and error in response.stderr) if error else (response.returncode==0 and response.stdout.strip()=='t')
        results.append({'name':name,'passed':ok,'stderr':response.stderr.strip()})
        print(('PASS ' if ok else 'FAIL ')+name,flush=True)
        if not ok: raise AssertionError(name+': '+response.stdout+response.stderr)
    # Exact profile columns/defaults from the audit; constraints remain from the
    # older baseline because the new audit did not export them.
    actual=json.loads(require(db.sql("""SELECT json_agg(json_build_object(
      'column_name',a.attname,'data_type',format_type(a.atttypid,a.atttypmod),
      'not_null',a.attnotnull,'default_expression',pg_get_expr(d.adbin,d.adrelid)) ORDER BY a.attnum)
      FROM pg_attribute a LEFT JOIN pg_attrdef d ON d.adrelid=a.attrelid AND d.adnum=a.attnum
      WHERE a.attrelid='public.profiles'::regclass AND a.attnum>0 AND NOT a.attisdropped;""")))
    expected=[{k:v for k,v in c.items() if k in actual[0]} for c in audit['columns']]
    if actual != expected: raise AssertionError('Profile schema differs from audit')
    results.append({'name':'profile column types, defaults and nullability match audit','passed':True})
    spec=importlib.util.spec_from_file_location('builder',REPO/'tools/build_ws4_shared_upgrade.py')
    builder=importlib.util.module_from_spec(spec);spec.loader.exec_module(builder)
    require(db.sql("SET corvia.ws4_shared_review='approved';"+builder.build()))
    # Same RPC payload as PostgREST upsert, INCLUDING the conflict key in UPDATE.
    upsert=f"""INSERT INTO public.profiles(user_id,first_name) VALUES('{uid(8)}','New')
      ON CONFLICT(user_id) DO UPDATE SET user_id=excluded.user_id,first_name=excluded.first_name;
      SELECT role='patient' AND user_type='patient' AND is_active FROM public.profiles WHERE user_id='{uid(8)}';"""
    check('patient signup defaults',upsert,8)
    check('patient repeated upsert',upsert,8)
    check('own normal profile edit',f"UPDATE public.profiles SET first_name='Edited' WHERE user_id='{uid(1)}'; SELECT first_name='Edited' FROM public.profiles WHERE user_id='{uid(1)}';",1)
    for col,value in [('role',"'dispatcher'"),('user_type',"'admin'"),('is_active','true'),('id',f"'{uid(2)}'"),('created_at','now()')]:
        check('direct '+col+' write denied',f"UPDATE public.profiles SET {col}={value} WHERE user_id='{uid(6)}';",6,'42501')
    check('identity reassignment denied',f"UPDATE public.profiles SET user_id='{uid(9)}' WHERE user_id='{uid(8)}';",8,'42501')
    check('cross-user edit affects no rows',f"WITH changed AS (UPDATE public.profiles SET first_name='Attack' WHERE user_id='{uid(2)}' RETURNING 1) SELECT count(*)=0 FROM changed;",1)
    check('anonymous insert denied',f"INSERT INTO public.profiles(user_id) VALUES('{uid(8)}');",0,'42501')
    check('forged initial authority denied',f"INSERT INTO public.profiles(user_id,role) VALUES('{uid(8)}','admin');",8,'42501')
    check('legacy own incidents still readable',"SELECT count(*)=5 FROM public.incidents;",1)
    check('patient cannot invoke staff writer',f"SELECT public.corvia_admin_link_staff_account('{uid(1)}','nurse');",1,'Hospital administrator access')
    check('audited nurse link succeeds',f"SELECT (public.corvia_admin_link_staff_account('{uid(1)}','nurse')->>'linked')::boolean;",9)
    check('role and user_type changed by authorized RPC',f"SELECT role='nurse' AND user_type='nurse' FROM public.profiles WHERE user_id='{uid(1)}';")
    check('audited staff removal succeeds',f"SELECT (public.corvia_admin_remove_staff_account('{uid(1)}')->>'removed')::boolean;",9)
    check('audited pharmacist upsert succeeds',"SELECT (public.corvia_admin_link_pharmacist('synthetic-2@example.test')->>'success')::boolean;",9)
    check('audited lab admin appointment succeeds',f"SELECT (public.corvia_admin_appoint_hospital_lab_admin('{uid(7)}')->>'appointed')::boolean;",9)
    check('audited hospital lab worker link succeeds',f"SELECT (public.corvia_hospital_lab_admin_link_worker('{uid(1)}',false)->>'is_active')::boolean;",7)
    check('audited hospital lab worker removal succeeds',f"SELECT NOT (public.corvia_hospital_lab_admin_update_worker('{uid(1)}',false,false)->>'is_active')::boolean;",7)
    check('audited private lab worker link executes',f"SELECT (public.corvia_private_lab_admin_link_worker('{uid(1)}',false)->>'is_active')::boolean;",7)
    profile=require(db.sql(f"SELECT id FROM public.profiles WHERE user_id='{uid(7)}';"))
    check('audited hospital lab admin removal succeeds',f"SELECT (public.corvia_admin_remove_hospital_lab_admin('{profile}')->>'removed')::boolean;",9)
    # Exercise the actual exported patient function, repaired by the generator.
    check('inactive user cannot reactivate via patient RPC',"SELECT * FROM public.corvia_upsert_my_patient_profile();",6,'42501')
    check('patient RPC preserves inactive state',f"SELECT is_active IS FALSE FROM public.profiles WHERE user_id='{uid(6)}';")
    check('active patient RPC still works',"SELECT count(*)=1 FROM public.corvia_upsert_my_patient_profile(p_first_name=>'Patient');",8)
    check('patient RPC does not demote staff',"SELECT count(*)=1 FROM public.corvia_upsert_my_patient_profile();",2)
    check('staff authority is retained',f"SELECT role='pharmacist' AND user_type='pharmacist' FROM public.profiles WHERE user_id='{uid(2)}';")


def http_tests(db, executable, results):
    secret=secrets.token_urlsafe(40)
    password=secrets.token_urlsafe(32)
    require(db.sql(f"CREATE ROLE ws4_http LOGIN NOINHERIT PASSWORD '{password}'; GRANT anon,authenticated TO ws4_http;"))
    with socket.socket() as s:
        s.bind(('127.0.0.1',0)); port=s.getsockname()[1]
    env={k:v for k,v in db.env.items() if not k.upper().startswith('PGRST_')}
    env['PATH']=str(db.binaries)+os.pathsep+env.get('PATH','')
    env.update(PGRST_DB_URI=f'postgresql://ws4_http:{password}@127.0.0.1:{db.port}/postgres',
        PGRST_DB_SCHEMAS='public',PGRST_DB_ANON_ROLE='anon',PGRST_SERVER_HOST='127.0.0.1',
        PGRST_SERVER_PORT=str(port),PGRST_JWT_SECRET=secret,PGRST_DB_POOL='3')
    def token(actor,valid=True):
        enc=lambda v:base64.urlsafe_b64encode(json.dumps(v,separators=(',',':')).encode()).rstrip(b'=')
        body=enc({'alg':'HS256','typ':'JWT'})+b'.'+enc({'role':'authenticated','sub':uid(actor),'exp':int(time.time())+300})
        sig=hmac.new((secret if valid else 'wrong-secret').encode(),body,hashlib.sha256).digest()
        return (body+b'.'+base64.urlsafe_b64encode(sig).rstrip(b'=')).decode()
    def request(method,path,payload=None,actor=None,valid=True,prefer=None):
        headers={'Content-Type':'application/json'}
        if actor is not None: headers['Authorization']='Bearer '+token(actor,valid)
        if prefer:headers['Prefer']=prefer
        req=urllib.request.Request(f'http://127.0.0.1:{port}/'+path,
            data=json.dumps(payload).encode() if payload is not None else None,headers=headers,method=method)
        try:
            with urllib.request.urlopen(req,timeout=10) as r:return r.status,r.read().decode()
        except urllib.error.HTTPError as e:return e.code,e.read().decode()
    with (db.work/'postgrest.log').open('w') as log:
        proc=subprocess.Popen([str(executable)],env=env,stdout=log,stderr=log,creationflags=FLAGS)
        try:
            for _ in range(100):
                if proc.poll() is not None:raise RuntimeError('PostgREST exited; see local log')
                try:
                    if request('GET','')[0]==200:break
                except (urllib.error.URLError,TimeoutError):pass
                time.sleep(.1)
            else:raise RuntimeError('PostgREST did not become ready')
            cases=[
              ('signed JWT own read','GET','profiles?user_id=eq.'+uid(8),None,8,200,True,None),
              ('forged JWT rejected','GET','profiles',None,8,401,False,None),
              ('HTTP direct promotion denied','PATCH','profiles?user_id=eq.'+uid(8),{'role':'admin'},8,403,True,None),
              ('HTTP anonymous write denied','POST','profiles',{'user_id':uid(8)},None,401,True,None),
              ('HTTP repeated signup upsert','POST','profiles?on_conflict=user_id',{'user_id':uid(8),'first_name':'HTTP patient'},8,(200,201),True,'resolution=merge-duplicates,return=representation'),
              ('HTTP inactive patient RPC denied','POST','rpc/corvia_upsert_my_patient_profile',{},6,403,True,None),
              ('HTTP authorized staff RPC','POST','rpc/corvia_admin_link_staff_account',{'p_profile_id':uid(8),'p_staff_role':'nurse'},9,200,True,None),
            ]
            for name,method,path,payload,actor,status,valid,prefer in cases:
                actual,body=request(method,path,payload,actor,valid,prefer)
                ok=actual in status if isinstance(status,tuple) else actual==status
                if name=='signed JWT own read':ok=ok and len(json.loads(body))==1
                if name=='HTTP repeated signup upsert':
                    row=json.loads(body)[0]
                    ok=ok and row['role']=='patient' and row['user_type']=='patient' and row['is_active'] is True
                results.append({'name':name,'passed':ok,'http_status':actual})
                print(('PASS ' if ok else 'FAIL ')+name,flush=True)
                if not ok:raise AssertionError(name+': '+str(actual)+' '+body)
        finally:
            proc.terminate();proc.wait(timeout=10)


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--pg-bin',type=Path,required=True)
    parser.add_argument('--audit',type=Path,required=True)
    parser.add_argument('--postgrest',type=Path)
    args=parser.parse_args()
    raw=args.audit.read_bytes()
    if hashlib.sha256(raw).hexdigest()!=AUDIT_HASH:raise ValueError('Audit changed; review before updating pinned hash')
    audit=json.loads(raw.decode('utf-8-sig'))
    work=REPO/'build/ws4-profile-probe'/uuid.uuid4().hex;work.mkdir(parents=True)
    db=Database(args.pg_bin.resolve(),work)
    report={'results':[],'audit_sha256':AUDIT_HASH,'deployment_approved':False,
      'limitations':['Dependency tables use synthetic shapes, constraints are from 5 October baseline.',
        'Authorization helpers not in audit are test doubles; doctor/pharmacist linked read helpers deny all.',
        'Auth/GoTrue signup, actual hosted JWT keys and full target staging are not tested.',
        'Existing staff helper does not check profile activation; revoked admin access needs separate review.']}
    try:
        db.start();report['postgres_version']=db.version
        run(db,audit,report['results'])
        if args.postgrest:http_tests(db,args.postgrest.resolve(),report['results'])
        report['passed']=True
    except Exception as error:
        report.update(passed=False,error=str(error));raise
    finally:
        db.stop();report['server_stopped']=not db.started
        (work/'result.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
        print('Report: '+str(work/'result.json'),flush=True)


if __name__=='__main__':main()
