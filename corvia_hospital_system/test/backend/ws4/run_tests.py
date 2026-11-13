"""Run the vulnerable baseline contract on a NEW isolated local PostgreSQL 15.

No existing database URL or data directory is accepted. No Windows service is
installed. This intentionally reproduces defects; green is not security approval.
"""
import argparse
import concurrent.futures
import datetime
import hashlib
import json
import os
from pathlib import Path
import secrets
import socket
import subprocess
import time
import uuid

ROOT = Path(__file__).resolve().parent
FLAGS = subprocess.CREATE_NO_WINDOW if os.name == 'nt' else 0


def uid(n):
    return f'00000000-0000-4000-8000-{n:012d}'


class Database:
    def __init__(self, binaries, work):
        self.binaries = binaries
        self.work = work
        self.data = work/'data'
        self.env = {k:v for k,v in os.environ.items() if not k.upper().startswith('PG')}
        self.env['PGPASSWORD'] = secrets.token_urlsafe(32)
        self.env['PGCONNECT_TIMEOUT'] = '5'
        with socket.socket() as sock:
            sock.bind(('127.0.0.1',0))
            self.port = sock.getsockname()[1]
        self.started = False

    def exe(self,name):
        return str(self.binaries/(name+('.exe' if os.name=='nt' else '')))

    def command(self,args,**kwargs):
        return subprocess.run(args,env=self.env,encoding='utf-8',errors='replace',
                              creationflags=FLAGS,**kwargs)

    def start(self):
        version=self.command([self.exe('postgres'),'--version'],capture_output=True,check=True,timeout=10).stdout.strip()
        if not version.startswith('postgres (PostgreSQL) 15.'):
            raise RuntimeError('This baseline requires PostgreSQL 15.x: '+version)
        self.version=version
        password=self.work/'init-password.txt'
        password.write_text(self.env['PGPASSWORD'],encoding='utf-8')
        try:
            result=self.command([self.exe('initdb'),'-D',str(self.data),'-U','postgres',
                                 '--auth=scram-sha-256','--encoding=UTF8','--locale=C',
                                 '--pwfile='+str(password)],capture_output=True,timeout=90)
            (self.work/'initdb.log').write_text(result.stdout+result.stderr,encoding='utf-8')
            result.check_returncode()
        finally:
            password.unlink(missing_ok=True)
        with (self.data/'postgresql.conf').open('a',encoding='utf-8') as stream:
            stream.write(f"\nlisten_addresses = '127.0.0.1'\nport = {self.port}\nmax_connections = 12\nshared_buffers = '32MB'\n")
        # On Windows a background server may inherit captured pipe handles,
        # making communicate() wait after pg_ctl exits. Use a real log file.
        try:
            with (self.work/'pg_ctl.log').open('w',encoding='utf-8') as log:
                result=self.command([self.exe('pg_ctl'),'-D',str(self.data),'-l',str(self.work/'postgres.log'),
                                     '-w','-t','30','start'],stdout=log,stderr=log,timeout=40)
        finally:
            self.started=(self.data/'postmaster.pid').exists()
        result.check_returncode()

    def sql(self,sql,actor=None,role='authenticated',rollback=False):
        preamble="SET statement_timeout='10s'; SET lock_timeout='8s';\n"
        if actor is not None:
            preamble+=f"SET ROLE {role}; SET request.jwt.claim.sub='{uid(actor) if actor else ''}';\n"
        body=preamble+('BEGIN;\n' if rollback else '')+sql+('\nROLLBACK;' if rollback else '')
        result=self.command([self.exe('psql'),'-X','-qAt','-v','ON_ERROR_STOP=1','-v','VERBOSITY=verbose',
                             '-h','127.0.0.1','-p',str(self.port),'-U','postgres','-d','postgres'],
                            input=body,capture_output=True,timeout=20)
        return result

    def stop(self):
        if self.started:
            self.command([self.exe('pg_ctl'),'-D',str(self.data),'-m','fast','-w','-t','20','stop'],
                         capture_output=True,timeout=30,check=True)
            self.started=False


def run(db,results):
    for name in ('catalog.sql','fixtures.sql'):
        db.sql((ROOT/'baseline'/name).read_text(encoding='utf-8')).check_returncode()

    def case(name,sql,expected='t',actor=1,state=None,gap=False):
        result=db.sql(sql,actor=actor,role='anon' if actor==0 else 'authenticated',rollback=True)
        passed=(result.returncode!=0 and f'{state}:' in result.stderr) if state else (result.returncode==0 and result.stdout.strip()==expected)
        results.append({'name':name,'passed':passed,'kind':'KNOWN_BASELINE_GAP' if gap else 'COMPATIBILITY',
                        'sqlstate_expected':state,'stdout':result.stdout.strip(),'stderr':result.stderr.strip()})
        print(('PASS ' if passed else 'FAIL ')+name,flush=True)
        if not passed:
            raise AssertionError(name+': '+result.stdout+result.stderr)

    case('patient sees only own incidents','SELECT count(*)=5 FROM public.incidents;')
    case('unrelated patient cannot read first incident','SELECT count(*)=0 FROM public.incidents WHERE id=101;',actor=2)
    case('anonymous incident read returns no rows','SELECT count(*)=0 FROM public.incidents;',actor=0)
    case('ordinary patient claim denied','SELECT public.corvia_dispatch_accept_incident(101);',state='42501')
    case('anonymous claim denied','SELECT public.corvia_dispatch_accept_incident(101);',actor=0,state='42501')
    case('inactive dispatcher claim denied','SELECT public.corvia_dispatch_accept_incident(101);',actor=6,state='42501')
    case('doctor role alone cannot claim','SELECT public.corvia_dispatch_accept_incident(101);',actor=7,state='42501')
    case('missing incident has established error','SELECT public.corvia_dispatch_accept_incident(9999);',actor=3,state='P0002')
    for incident in (103,104,105,106):
        case(f'nonpending or unknown state {incident} cannot be claimed',f'SELECT public.corvia_dispatch_accept_incident({incident});',actor=3,state='P0001')
    case('claim returns exact legacy fields and actor',f"""
      WITH claim AS (SELECT public.corvia_dispatch_accept_incident(101) AS j)
      SELECT j->>'id'='101' AND j->>'user_id'='{uid(1)}'
        AND j->>'status'='in_progress' AND j->>'assigned_dispatcher_user_id'='{uid(3)}'
        AND (j->>'accepted_at')::timestamptz IS NOT NULL
        AND (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(j) k)=
          ARRAY['accepted_at','assigned_dispatcher_user_id','created_at','id','latitude','longitude','status','user_id']
      FROM claim;""",actor=3)
    case('same owner retry returns identical claim',"""DO $$ DECLARE a jsonb; b jsonb; BEGIN
      a:=public.corvia_dispatch_accept_incident(101); b:=public.corvia_dispatch_accept_incident(101);
      IF a IS DISTINCT FROM b THEN RAISE EXCEPTION 'retry changed claim'; END IF;
      END $$; SELECT true;""",actor=3)
    case('supervisor claim supported',"SELECT public.corvia_dispatch_accept_incident(101)->>'status'='in_progress';",actor=5)
    case('patient cannot forge dispatcher owner',f"UPDATE public.incidents SET assigned_dispatcher_user_id='{uid(3)}' WHERE id=101;",state='42501')
    case('patient pending cancellation compatibility',"""UPDATE public.incidents SET status='cancelled'
      WHERE id=101 AND status='pending' AND assigned_dispatcher_user_id IS NULL;
      SELECT status='cancelled' FROM public.incidents WHERE id=101;""")
    case('ordinary profile edit preserved',f"UPDATE public.profiles SET first_name='Edited synthetic' WHERE user_id='{uid(1)}'; SELECT first_name='Edited synthetic' FROM public.profiles WHERE user_id='{uid(1)}';")
    case('profile user_type change blocked',f"UPDATE public.profiles SET user_type='admin' WHERE user_id='{uid(1)}';",state='P0001')
    case('patient profile registration and repeated upsert supported',f"""
      INSERT INTO public.profiles(user_id,first_name,role,user_type,is_active) VALUES ('{uid(8)}','New synthetic','patient','patient',true)
      ON CONFLICT (user_id) DO UPDATE SET role=excluded.role,user_type=excluded.user_type,is_active=excluded.is_active;
      INSERT INTO public.profiles(user_id,first_name,role,user_type,is_active) VALUES ('{uid(8)}','New synthetic','patient','patient',true)
      ON CONFLICT (user_id) DO UPDATE SET role=excluded.role,user_type=excluded.user_type,is_active=excluded.is_active;
      SELECT count(*)=1 FROM public.profiles WHERE user_id='{uid(8)}';""",actor=8)
    case('B01 self promotion reaches dispatch authority',f"UPDATE public.profiles SET role='dispatcher' WHERE user_id='{uid(1)}'; SELECT public.corvia_is_dispatch_operator();",gap=True)
    case('B01 self promotion can claim another patient incident',f"UPDATE public.profiles SET role='dispatcher' WHERE user_id='{uid(1)}'; SELECT public.corvia_dispatch_accept_incident(102)->>'assigned_dispatcher_user_id'='{uid(1)}';",gap=True)
    case('B01 inactive profile can reactivate itself',f"UPDATE public.profiles SET is_active=true WHERE user_id='{uid(6)}'; SELECT public.corvia_is_dispatch_operator();",actor=6,gap=True)
    case('B01 NULL activation passes current helper',f"UPDATE public.profiles SET is_active=NULL WHERE user_id='{uid(3)}'; SELECT public.corvia_is_dispatch_operator();",actor=3,gap=True)
    case('B04 patient can set arbitrary lifecycle state',"UPDATE public.incidents SET status='unsupported_terminal' WHERE id=101; SELECT status='unsupported_terminal' FROM public.incidents WHERE id=101;",gap=True)
    case('B05 dispatcher sees incident outside proposed fixture coverage',"SELECT count(*)=1 FROM public.incidents WHERE id=102;",actor=3,gap=True)
    case('profile INSERT can self assert admin user_type',f"INSERT INTO public.profiles(user_id,user_type,role) VALUES ('{uid(9)}','admin','admin'); SELECT public.is_admin();",actor=9,gap=True)

    # Hold a real row lock in one connection; verify another connection actually
    # waits on a PostgreSQL lock before committing the winner.
    def race(name,first,second,loser_state=None,second_actor=4,expected_output=None):
        db.sql(f"INSERT INTO public.incidents(id,user_id,latitude,longitude,status) OVERRIDING SYSTEM VALUE VALUES (201,'{uid(1)}',-30,25,'pending');").check_returncode()
        command=[db.exe('psql'),'-X','-qAt','-v','ON_ERROR_STOP=1','-h','127.0.0.1','-p',str(db.port),'-U','postgres','-d','postgres']
        proc=subprocess.Popen(command,stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,
                              env=db.env,text=True,encoding='utf-8',creationflags=FLAGS)
        try:
            proc.stdin.write(f"SET statement_timeout='15s'; SET ROLE authenticated; SET request.jwt.claim.sub='{uid(first)}'; BEGIN;\n")
            proc.stdin.write(("UPDATE public.incidents SET status='cancelled' WHERE id=201;" if first==1 else 'SELECT public.corvia_dispatch_accept_incident(201);')+'\n\\echo LOCK_HELD\n')
            proc.stdin.flush()
            with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
                def wait_marker():
                    while True:
                        line=proc.stdout.readline()
                        if not line: raise RuntimeError('Lock holder exited before readiness')
                        if line.strip()=='LOCK_HELD': return
                pool.submit(wait_marker).result(timeout=10)
                future=pool.submit(db.sql,"SET application_name='ws4_race_waiter'; "+second,second_actor)
                deadline=time.monotonic()+5
                waiting=False
                while time.monotonic()<deadline:
                    query=db.sql("SELECT EXISTS (SELECT 1 FROM pg_stat_activity WHERE application_name='ws4_race_waiter' AND wait_event_type='Lock');")
                    if query.returncode==0 and query.stdout.strip()=='t':
                        waiting=True
                        break
                    time.sleep(.05)
                proc.stdin.write('COMMIT;\n\\q\n')
                proc.stdin.flush()
                proc.wait(timeout=10)
                result=future.result(timeout=12)
                passed=waiting and proc.returncode==0 and ((result.returncode!=0 and f'{loser_state}:' in result.stderr) if loser_state else result.returncode==0)
                if expected_output is not None:
                    passed=passed and result.stdout.strip()==expected_output
                results.append({'name':name,'passed':passed,'kind':'CONCURRENCY','observed_lock_wait':waiting,'stderr':result.stderr.strip()})
                print(('PASS ' if passed else 'FAIL ')+name,flush=True)
                if not passed: raise AssertionError(name)
        finally:
            if proc.poll() is None:
                proc.kill()
                proc.wait(timeout=5)
            for stream in (proc.stdin,proc.stdout,proc.stderr): stream.close()
        return db.sql('SELECT row_to_json(i) FROM public.incidents i WHERE id=201;')

    state=json.loads(race('two dispatchers: second claim waits then conflicts',3,'SELECT public.corvia_dispatch_accept_incident(201);','P0001').stdout)
    if state['assigned_dispatcher_user_id']!=uid(3): raise AssertionError('Wrong race winner')
    db.sql('DELETE FROM public.incidents WHERE id=201;').check_returncode()
    state=json.loads(race('cancel first: waiting claim rejects cancelled incident',1,'SELECT public.corvia_dispatch_accept_incident(201);','P0001').stdout)
    if state['status']!='cancelled' or state['assigned_dispatcher_user_id'] is not None: raise AssertionError('Cancellation race state invalid')
    db.sql('DELETE FROM public.incidents WHERE id=201;').check_returncode()
    state=json.loads(race('claim first: conditional patient cancellation affects zero rows',3,
        "WITH changed AS (UPDATE public.incidents SET status='cancelled' WHERE id=201 AND status='pending' AND assigned_dispatcher_user_id IS NULL RETURNING id) SELECT count(*)=0 FROM changed;",
        second_actor=1,expected_output='t').stdout)
    if state['status']!='in_progress' or state['assigned_dispatcher_user_id']!=uid(3): raise AssertionError('Claim/cancel final state invalid')
    case('B04 direct patient update bypasses conditional cancellation',"UPDATE public.incidents SET status='cancelled' WHERE id=201; SELECT status='cancelled' AND assigned_dispatcher_user_id IS NOT NULL FROM public.incidents WHERE id=201;",gap=True)

    failed=db.sql('BEGIN; SELECT public.corvia_dispatch_accept_incident(101); SELECT 1/0;',actor=3)
    unchanged=db.sql('SELECT status=\'pending\' AND assigned_dispatcher_user_id IS NULL AND accepted_at IS NULL FROM public.incidents WHERE id=101;')
    passed=failed.returncode!=0 and '22012:' in failed.stderr and unchanged.returncode==0 and unchanged.stdout.strip()=='t'
    results.append({'name':'failed transaction rolls back claim ownership and state','passed':passed,'kind':'COMPATIBILITY'})
    print(('PASS ' if passed else 'FAIL ')+'failed transaction rolls back claim ownership and state',flush=True)
    if not passed: raise AssertionError('Failed transaction retained claim')


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--pg-bin',type=Path,required=True,help='Existing portable/installed PostgreSQL 15 bin directory')
    args=parser.parse_args()
    # Always create a new task-owned directory. Never reset/delete caller data.
    work=ROOT.parents[2]/'build'/'ws4-db'/uuid.uuid4().hex
    work.mkdir(parents=True,exist_ok=False)
    db=Database(args.pg_bin.resolve(),work)
    results=[]
    report={'scope':'VULNERABLE BASELINE ONLY; no correction, deployment or Supabase API verification',
            'started_at':datetime.datetime.now(datetime.timezone.utc).isoformat(),'results':results,
            'baseline_sha256':hashlib.sha256((ROOT/'baseline/catalog.sql').read_bytes()).hexdigest()}
    try:
        db.start()
        report['postgres_version']=db.version
        report['local_port']=db.port
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
