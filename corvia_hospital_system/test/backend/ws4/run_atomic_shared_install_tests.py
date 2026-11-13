"""Rehearse the coastit atomic SQL bundle on a fresh local PostgreSQL 15."""

import argparse
import importlib.util
import json
from pathlib import Path
import uuid

from run_tests import Database, ROOT, uid
from run_patient_intake_tests import REPO, require, request


def _load_builder():
    path = REPO / 'tools/build_ws4_atomic_shared_install.py'
    spec = importlib.util.spec_from_file_location('atomic_ws4', path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _load_access_builder():
    path = REPO / 'tools/build_ws4_shared_demo_access.py'
    spec = importlib.util.spec_from_file_location('shared_demo_access', path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--pg-bin', type=Path, required=True)
    args = parser.parse_args()
    work = REPO / 'build/ws4-atomic-rehearsal' / uuid.uuid4().hex
    work.mkdir(parents=True)
    db = Database(args.pg_bin.resolve(), work)
    report = {'results': []}
    try:
        db.start()
        require(db.sql((ROOT / 'baseline/catalog.sql').read_text(encoding='utf-8')))
        require(db.sql((ROOT / 'baseline/fixtures.sql').read_text(encoding='utf-8')))
        require(db.sql("UPDATE public.incidents SET status='pending' WHERE id IN (105,106);"))
        require(db.sql('''
          ALTER TABLE auth.users ADD COLUMN email text;
          UPDATE auth.users SET email='synthetic-'||right(id::text,1)||'@example.test';
          CREATE TABLE public.hospitals(id uuid PRIMARY KEY,name text,is_active boolean NOT NULL);
          CREATE TABLE public.hospital_admins(hospital_id uuid,profile_id uuid);
          CREATE TABLE public.patients(profile_id uuid,hospital_id uuid);
          INSERT INTO public.hospitals VALUES
            ('aaaaaaaa-1111-4111-8111-111111111111','Synthetic hospital',true);
          INSERT INTO public.patients VALUES
            ('00000000-0000-4000-8000-000000000001',
             'aaaaaaaa-1111-4111-8111-111111111111');
          CREATE ROLE ws4_test_api LOGIN;
          GRANT authenticated TO ws4_test_api;
        '''))
        for name in ('11_install_fleet_paramedic.sql',
                     '13_dispatch_fleet_upgrade.sql'):
            require(db.sql((REPO / 'supabase/scripts/workstreams' / name)
                           .read_text(encoding='utf-8')))
        require(db.sql('''CREATE FUNCTION public.register_auth_user_temp(text,text)
          RETURNS uuid LANGUAGE sql SECURITY DEFINER AS
          $$ SELECT gen_random_uuid() $$;
          GRANT EXECUTE ON FUNCTION public.register_auth_user_temp(text,text)
          TO anon,authenticated;'''))
        bundle = _load_builder().build()
        unapproved = db.sql(bundle)
        if unapproved.returncode == 0 or 'Explicit external owner review' not in unapproved.stderr:
            raise AssertionError('Generated installer must not approve itself')
        report['results'].append('generated installer refuses missing external approval')
        bundle = "SET corvia.ws4_shared_review='approved';\n" + bundle
        injected = bundle.replace(
            '\nCOMMIT;\n',
            "\nDO $$ BEGIN RAISE EXCEPTION 'intentional rollback check'; END $$;\nCOMMIT;\n",
        )
        if injected == bundle:
            raise AssertionError('Could not inject rollback check')
        failed = db.sql(injected)
        if failed.returncode == 0 or 'intentional rollback check' not in failed.stderr:
            raise AssertionError('Atomic rollback check did not fail as expected')
        if require(db.sql("SELECT to_regnamespace('ws4_private') IS NULL;")) != 't':
            raise AssertionError('Failed transaction left WS4 schema behind')
        if require(db.sql("SELECT has_function_privilege('anon',"
                          "'public.register_auth_user_temp(text,text)','EXECUTE');")) != 't':
            raise AssertionError('Failed transaction changed signup grant')
        report['results'].append('failed install rolls back schema and grant')
        result = db.sql(bundle)
        require(result)
        report['results'].append('atomic migration committed')
        checks = (
            "SELECT to_regclass('ws4_private.push_outbox') IS NOT NULL;",
            "SELECT to_regclass('ws4_private.ems_handoff_routes') IS NOT NULL;",
            "SELECT count(*)=6 FROM public.incidents;",
            "SELECT NOT has_function_privilege('anon',"
            "'public.register_auth_user_temp(text,text)','EXECUTE');",
        )
        for sql in checks:
            result = require(db.sql(sql)).strip()
            if result != 't':
                raise AssertionError(f'{sql} returned {result}')
            report['results'].append(sql)
        demo = _load_access_builder().build(
            organisation='aaaaaaaa-2222-4222-8222-222222222222',
            hospital='aaaaaaaa-1111-4111-8111-111111111111',
            patient=uid(1), dispatcher=uid(3), supervisor=uid(5))
        wrong_role = demo.replace(uid(1), uid(7))
        denied = db.sql(wrong_role)
        if denied.returncode == 0 or 'role-matched accounts required' not in denied.stderr:
            raise AssertionError('Wrong-role demo patient was not rejected')
        if require(db.sql("SELECT count(*) FROM ws4_private.organisations;")) != '0':
            raise AssertionError('Rejected provisioning left an organisation')
        require(db.sql(demo))
        report['results'].append('guarded demo access installed')
        if require(db.sql("SELECT count(*)=2 FROM ws4_private.memberships WHERE active;")) != 't':
            raise AssertionError('Demo dispatch memberships missing')
        if require(db.sql("SELECT count(*)=1 FROM ws4_private.ems_handoff_routes WHERE NOT active;")) != 't':
            raise AssertionError('Team handoff route must remain inactive')
        if require(db.sql("SELECT count(*)=6 AND bool_and(organisation_id IS NULL) FROM public.incidents;")) != 't':
            raise AssertionError('Legacy incidents were changed')
        incident = json.loads(require(db.sql(f'SELECT {request(980)};', actor=1)))['incident_id']
        if require(db.sql(f"SELECT public.corvia_dispatch_accept_incident({incident})->>'status';", actor=3)) != 'in_progress':
            raise AssertionError('Provisioned dispatcher cannot claim the patient incident')
        report['results'].append('reviewed patient-to-dispatcher incident flow')
        repeated = db.sql(demo)
        if repeated.returncode == 0 or 'requires manual review' not in repeated.stderr:
            raise AssertionError('Repeated demo provisioning was not rejected')
        report['results'].append('rerun refuses to overwrite existing mappings')
        report['passed'] = True
    except Exception as error:
        report.update(passed=False, error=str(error))
        raise
    finally:
        db.stop()
        report['server_stopped'] = not db.started
        (work / 'result.json').write_text(json.dumps(report, indent=2),
                                          encoding='utf-8')
        print('Report: ' + str(work / 'result.json'), flush=True)


if __name__ == '__main__':
    main()
