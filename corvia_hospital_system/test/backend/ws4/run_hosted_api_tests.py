"""Real Auth/API checks for Jandre's SYNTHETIC development project only.

Creates five synthetic accounts; never targets shared Corvia or ER24. Secrets are
read from a private terminal/environment, kept in memory and never put in reports.
Owner SQL is generated for separate review/execution; this script cannot grant it.
No automatic retries, account deletion, schema changes or configuration changes.
"""
import argparse
import base64
import concurrent.futures
import datetime
import getpass
import json
import os
from pathlib import Path
import re
import secrets
import sys
import urllib.error
import urllib.request
import uuid
import warnings

PROJECT = 'lejaaweexxspjlmlrtfc'
ORIGIN = f'https://{PROJECT}.supabase.co'
ROOT = Path(__file__).resolve().parents[3]
LABELS = ('patient_a', 'patient_b', 'dispatcher_a', 'dispatcher_a2', 'dispatcher_b')


class SafeFailure(Exception):
    """Only fixed descriptions/status codes; never attach response or credentials."""


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def validate_key(value, privileged=False):
    prefix = 'sb_secret_' if privileged else 'sb_publishable_'
    if value.startswith(prefix) and len(value) > len(prefix) + 10:
        return value
    try:
        parts = value.split('.')
        if len(parts) != 3:
            raise ValueError()
        claims = json.loads(base64.urlsafe_b64decode(parts[1] + '=' * (-len(parts[1]) % 4)))
        if not isinstance(claims, dict) or claims.get('role') != ('service_role' if privileged else 'anon') or claims.get('ref') != PROJECT:
            raise ValueError()
    except (ValueError, TypeError, KeyError):
        raise SafeFailure('Wrong key type or project. Use this development project only.') from None
    return value


def read_key(name, prompt, privileged=False):
    value = os.environ.get(name, '').strip()
    if not value:
        if not sys.stdin.isatty():
            raise SafeFailure('A private interactive terminal is required for key entry.')
        with warnings.catch_warnings():
            warnings.simplefilter('error', getpass.GetPassWarning)
            try:
                value = getpass.getpass(prompt).strip()
            except getpass.GetPassWarning:
                raise SafeFailure('Hidden key entry is unavailable; refusing to echo credentials.') from None
    return validate_key(value, privileged)


def request(method, path, key, token=None, data=None, admin=False):
    allowed = path.startswith('/auth/v1/') or path.startswith('/rest/v1/')
    if not allowed or '://' in path or '\\' in path or method not in ('GET','POST','PATCH'):
        raise SafeFailure('Request outside the fixed development API refused.')
    if admin != path.startswith('/auth/v1/admin/'):
        raise SafeFailure('Admin key is restricted to Auth user provisioning.')
    validate_key(key, privileged=admin)
    headers = {'apikey':key, 'Content-Type':'application/json', 'Prefer':'return=representation'}
    if token:
        headers['Authorization'] = 'Bearer ' + token
    elif admin and not key.startswith('sb_secret_'):
        headers['Authorization'] = 'Bearer ' + key
    payload = json.dumps(data).encode() if data is not None else None
    req = urllib.request.Request(ORIGIN + path, data=payload, headers=headers, method=method)
    opener = urllib.request.build_opener(NoRedirect())
    try:
        with opener.open(req, timeout=20) as response:
            raw = response.read(2_000_000)
            return response.status, json.loads(raw) if raw else None
    except urllib.error.HTTPError as error:
        try:
            body = json.loads(error.read(64_000))
            code = body.get('code', body.get('error_code', ''))
            code = code if isinstance(code, str) and re.fullmatch(r'[A-Za-z0-9_]{1,60}', code) else ''
        except (ValueError, AttributeError):
            code = ''
        return error.code, {'code':code}
    except (urllib.error.URLError, TimeoutError, OSError, ValueError):
        raise SafeFailure('Transport/response failure; outcome may be unknown. Do not blindly rerun provisioning.') from None


def provision_sql(accounts, organisations, run_id):
    # Only generated UUIDs and reserved synthetic addresses are interpolated.
    if not re.fullmatch(r'[a-f0-9]{12}', run_id) or set(accounts) != set(LABELS):
        raise SafeFailure('Invalid synthetic run identity or account set.')
    for label, account in accounts.items():
        if str(uuid.UUID(account['id'])) != account['id']:
            raise SafeFailure('Non-canonical fixture UUID refused.')
        if account['email'] != f'ws4-{run_id}-{label}@example.invalid':
            raise SafeFailure('Non-synthetic fixture identity refused.')
    a, b = (str(uuid.UUID(value)) for value in organisations)
    if a == b or len({v['id'] for v in accounts.values()}) != 5:
        raise SafeFailure('Fixture identities must be distinct.')
    rows = ',\n'.join(f"('{v['id']}'::uuid,'{v['email']}')" for v in accounts.values())
    staff = ','.join(f"'{accounts[n]['id']}'::uuid" for n in LABELS[2:])
    memberships = ',\n'.join(f"('{accounts[n]['id']}','{b if n=='dispatcher_b' else a}','dispatcher',true)" for n in LABELS[2:])
    return f"""-- SYNTHETIC WS4 RUN {run_id}; ONLY corvia-ws4-dev / {PROJECT}.
-- Review and approve these three test memberships before execution.
BEGIN;
DO $$ BEGIN
 IF current_user <> 'postgres' OR NOT EXISTS (SELECT 1 FROM ws4_dev_private.installation
   WHERE synthetic_only AND contract_version='ws4-dev-core-1') THEN
   RAISE EXCEPTION 'Wrong development installation/owner';
 END IF;
 IF (SELECT count(*) FROM (VALUES {rows}) expected(id,email)
   JOIN auth.users u ON u.id=expected.id AND u.email=expected.email
     AND u.raw_app_meta_data->>'ws4_test_run'='{run_id}'
   JOIN public.profiles p ON p.user_id=u.id AND p.role='patient' AND p.is_active IS TRUE) <> 5 THEN
   RAISE EXCEPTION 'Synthetic account provenance/profile mismatch';
 END IF;
END $$;
INSERT INTO ws4_dev_private.organisations(id,label) VALUES
 ('{a}','Synthetic WS4 A {run_id}'),('{b}','Synthetic WS4 B {run_id}');
UPDATE public.profiles SET role='dispatcher' WHERE user_id IN ({staff});
INSERT INTO ws4_dev_private.memberships(user_id,organisation_id,role,active) VALUES
 {memberships};
INSERT INTO ws4_dev_private.patient_routes(user_id,organisation_id) VALUES
 ('{accounts['patient_a']['id']}','{a}'),('{accounts['patient_b']['id']}','{b}');
COMMIT;
"""


def run(work, report, public_key, admin_key):
    accounts = report['accounts']
    sessions = {}
    run_id = report['run_id']

    def save():
        (work/'report.json').write_text(json.dumps(report,indent=2),encoding='utf-8')

    def check(name, condition):
        report['checks'].append({'name':name,'passed':bool(condition)})
        save()
        print(('PASS ' if condition else 'FAIL ') + name, flush=True)
        if not condition:
            raise SafeFailure('Assertion failed: ' + name)

    def api(label, method, path, data=None):
        return request(method, path, public_key, sessions.get(label), data)

    def denied(response, code='42501'):
        status, body = response
        return status in (401,403) and isinstance(body,dict) and body.get('code') == code

    # Prove correct API installation before creating accounts; no admin probe used.
    check('anonymous incident API denies access', denied(api(None,'GET','/rest/v1/incidents?select=id')))
    check('anonymous claim API denies access', denied(api(None,'POST','/rest/v1/rpc/corvia_dispatch_accept_incident',{'p_incident_id':1})))
    report['phase'] = 'creating_synthetic_auth_accounts'
    save()
    for label in LABELS:
        email = f'ws4-{run_id}-{label}@example.invalid'
        password = secrets.token_urlsafe(36)
        # This marker is server-managed and checked by the owner SQL.
        report['pending_creation'] = email
        save()
        status, user = request('POST','/auth/v1/admin/users',admin_key, data={
            'email':email,'password':password,'email_confirm':True,
            'app_metadata':{'ws4_test_run':run_id},
            'user_metadata':{'display_name':'Synthetic WS4 '+label}},admin=True)
        check('create synthetic '+label, status in (200,201) and isinstance(user,dict) and 'id' in user)
        user_id = str(uuid.UUID(user['id']))
        accounts[label] = {'id':user_id,'email':email}
        report.pop('pending_creation',None)
        save()
        status, login = request('POST','/auth/v1/token?grant_type=password',public_key,
                                data={'email':email,'password':password})
        password = None
        check('real password login '+label, status==200 and isinstance(login,dict) and login.get('user',{}).get('id')==user_id and bool(login.get('access_token')))
        sessions[label] = login['access_token']
        login = None
        status, user = api(label,'GET','/auth/v1/user')
        check('server verifies JWT '+label, status==200 and user.get('id')==user_id)
        status, profile = api(label,'POST','/rest/v1/profiles',{'user_id':user_id,'first_name':'Synthetic '+label,'role':'patient','user_type':'patient','is_active':True})
        check('own patient profile creation '+label,status==201 and isinstance(profile,list) and len(profile)==1 and profile[0]['user_id']==user_id)
    admin_key = None
    organisations = [str(uuid.uuid4()), str(uuid.uuid4())]
    report['organisations'] = organisations
    (work/'provision.sql').write_text(provision_sql(accounts,organisations,run_id),encoding='utf-8')
    (work/'revoke.sql').write_text(f"-- Revoke only this synthetic run's A dispatchers.\nBEGIN;\nUPDATE ws4_dev_private.memberships SET active=false WHERE organisation_id='{organisations[0]}' AND user_id IN ('{accounts['dispatcher_a']['id']}','{accounts['dispatcher_a2']['id']}');\nCOMMIT;\n",encoding='utf-8')
    report['phase'] = 'awaiting_reviewed_provision_sql'
    save()
    print('Owner review required: '+str(work/'provision.sql'),flush=True)
    if input('After this exact SQL is approved, applied and verified, type provisioned: ').strip()!='provisioned':
        raise SafeFailure('Stopped before membership-dependent tests.')

    for label in LABELS:
        status, profiles = api(label,'GET','/rest/v1/profiles?select=user_id')
        check('profile isolation '+label,status==200 and profiles==[{'user_id':accounts[label]['id']}])
    check('self-promotion denied',denied(api('patient_a','PATCH','/rest/v1/profiles?user_id=eq.'+accounts['patient_a']['id'],{'role':'dispatcher'})))
    for label in LABELS[2:]:
        status, context = api(label,'POST','/rest/v1/rpc/corvia_dispatch_access_context',{})
        expected_org = organisations[1 if label=='dispatcher_b' else 0]
        check('trusted access context '+label,status==200 and context.get('user_id')==accounts[label]['id'] and context.get('memberships')==[{'organisation_id':expected_org,'role':'dispatcher'}])
    check('patient access context denied',denied(api('patient_a','POST','/rest/v1/rpc/corvia_dispatch_access_context',{})))
    ids = report['incident_ids'] = {}
    for name, patient in (('claim','patient_a'),('cancel','patient_a'),('other_org','patient_b')):
        status, rows = api(patient,'POST','/rest/v1/incidents',{'user_id':accounts[patient]['id'],'latitude':0,'longitude':0,'status':'pending'})
        check('synthetic incident activation '+name,status==201 and isinstance(rows,list) and len(rows)==1)
        ids[name] = rows[0]['id']
        save()
    for label, expected in [('patient_a',{ids['claim'],ids['cancel']}),('patient_b',{ids['other_org']}),('dispatcher_a',{ids['claim'],ids['cancel']}),('dispatcher_b',{ids['other_org']})]:
        status, rows = api(label,'GET','/rest/v1/incidents?select=id')
        check('incident scope '+label,status==200 and {r['id'] for r in rows}==expected)
    status, error = api('dispatcher_b','POST','/rest/v1/rpc/corvia_dispatch_accept_incident',{'p_incident_id':ids['claim']})
    check('cross-org claim hidden',status==404 and error.get('code')=='P0002')
    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
        futures = {label:pool.submit(api,label,'POST','/rest/v1/rpc/corvia_dispatch_accept_incident',{'p_incident_id':ids['claim']}) for label in ('dispatcher_a','dispatcher_a2')}
        outcomes = {label:f.result() for label,f in futures.items()}
    winners = [label for label,(status,body) in outcomes.items() if status==200]
    check('HTTP competing claims have one winner',len(winners)==1 and sum(status==400 and body.get('code')=='P0001' for status,body in outcomes.values())==1)
    winner = winners[0]
    status, retry = api(winner,'POST','/rest/v1/rpc/corvia_dispatch_accept_incident',{'p_incident_id':ids['claim']})
    check('same-owner HTTP retry preserves result',status==200 and retry==outcomes[winner][1])
    check('patient cannot cancel claimed incident',denied(api('patient_a','PATCH',f"/rest/v1/incidents?id=eq.{ids['claim']}",{'status':'cancelled'})))
    status, rows = api('patient_a','PATCH',f"/rest/v1/incidents?id=eq.{ids['cancel']}&status=eq.pending&assigned_dispatcher_user_id=is.null",{'status':'cancelled'})
    check('legacy conditional cancellation succeeds',status==200 and len(rows)==1 and rows[0]['status']=='cancelled')
    report['phase'] = 'awaiting_synthetic_membership_revocation'
    save()
    print('Revocation check SQL: '+str(work/'revoke.sql'),flush=True)
    if input('After that exact revocation is applied, type revoked: ').strip()!='revoked':
        raise SafeFailure('Stopped before revocation checks.')
    check('existing JWT loses revoked dispatch authority',denied(api(winner,'POST','/rest/v1/rpc/corvia_dispatch_access_context',{})))
    check('revoked claimant cannot retry',denied(api(winner,'POST','/rest/v1/rpc/corvia_dispatch_accept_incident',{'p_incident_id':ids['claim']})))
    status, rows = api(winner,'GET','/rest/v1/incidents?select=id')
    check('revoked dispatcher sees no incidents',status==200 and rows==[])
    report['phase']='complete'
    report['passed']=True
    save()


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--confirm-project',required=True,choices=[PROJECT])
    parser.parse_args()
    work=ROOT/'build/ws4-hosted-api'/uuid.uuid4().hex
    work.mkdir(parents=True,exist_ok=False)
    report={'project':PROJECT,'run_id':uuid.uuid4().hex[:12],
            'started_at':datetime.datetime.now(datetime.timezone.utc).isoformat(),
            'scope':'Synthetic Auth/API only; no full app or ER24 integration',
            'phase':'preflight','passed':False,'accounts':{},'checks':[]}
    print('Target: '+ORIGIN+' (owned synthetic development project only).')
    print('Creates five synthetic accounts and three test incidents. No email is sent.')
    print('Passwords/tokens stay in memory. Accounts remain after the run; no cleanup is automatic.')
    print('Report and owner-reviewed SQL: '+str(work),flush=True)
    try:
        public_key=read_key('CORVIA_WS4_PUBLIC_KEY','Project publishable/anon key (hidden): ')
        admin_key=read_key('CORVIA_WS4_ADMIN_KEY','Project secret/service-role key (hidden; never paste in chat): ',True)
        run(work,report,public_key,admin_key)
    except (SafeFailure,EOFError,KeyboardInterrupt) as error:
        report['error']=str(error) if isinstance(error,SafeFailure) else 'Input ended; run incomplete.'
        print(report['error'],file=sys.stderr)
    except Exception:
        # Exception bodies can contain transport/auth response data; do not print them.
        report['error']='Unexpected runner failure; inspect non-secret phase/checks. Do not blindly rerun.'
        print(report['error'],file=sys.stderr)
    finally:
        (work/'report.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
    return 0 if report['passed'] else 1


if __name__=='__main__':
    sys.exit(main())
