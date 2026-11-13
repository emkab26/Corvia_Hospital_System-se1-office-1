"""Validate generated owner provisioning on a NEW loopback DB; no hosted access."""
import argparse
import json
from pathlib import Path
import uuid

from run_tests import Database
from run_hosted_api_tests import LABELS, ROOT, provision_sql


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--pg-bin', type=Path, required=True)
    args = parser.parse_args()
    work = ROOT / 'build/ws4-provision-sql' / uuid.uuid4().hex
    work.mkdir(parents=True)
    db = Database(args.pg_bin.resolve(), work)
    report = {'scope': 'LOCAL SQL ONLY; not real Auth', 'checks': [], 'passed': False}

    def sql(text):
        result = db.sql(text)
        if result.returncode:
            raise AssertionError(result.stderr)
        return result.stdout.strip()

    def check(name, ok):
        report['checks'].append({'name': name, 'passed': ok})
        if not ok:
            raise AssertionError(name)
        print('PASS ' + name)

    try:
        db.start()
        sql("""CREATE ROLE anon NOLOGIN; CREATE ROLE authenticated NOLOGIN;
          CREATE ROLE service_role NOLOGIN BYPASSRLS; CREATE SCHEMA auth;
          CREATE TABLE auth.users(id uuid PRIMARY KEY,email text,raw_app_meta_data jsonb);
          CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE AS $$
            SELECT nullif(current_setting('request.jwt.claim.sub',true),'')::uuid;
          $$; GRANT USAGE ON SCHEMA auth,public TO anon,authenticated,service_role;""")
        sql((ROOT/'supabase/scripts/ws4_dev/001_secure_core.sql').read_text(encoding='utf-8'))
        run_id = uuid.uuid4().hex[:12]
        accounts = {label: {'id': str(uuid.uuid4()), 'email': f'ws4-{run_id}-{label}@example.invalid'} for label in LABELS}
        organisations = [str(uuid.uuid4()), str(uuid.uuid4())]
        for account in accounts.values():
            sql(f"INSERT INTO auth.users VALUES ('{account['id']}','{account['email']}', '{{}}'); INSERT INTO public.profiles(user_id) VALUES ('{account['id']}');")
        generated = provision_sql(accounts, organisations, run_id)
        check('missing server provenance refuses grants', db.sql(generated).returncode != 0)
        check('failed provenance leaves organisations empty', sql('SELECT count(*)=0 FROM ws4_dev_private.organisations') == 't')
        sql(f"UPDATE auth.users SET raw_app_meta_data=jsonb_build_object('ws4_test_run','{run_id}');")
        sql(generated)
        check('reviewed fixtures create exactly three active memberships', sql('SELECT count(*)=3 AND bool_and(active) FROM ws4_dev_private.memberships') == 't')
        check('reviewed fixtures route two patients', sql('SELECT count(*)=2 FROM ws4_dev_private.patient_routes') == 't')
        check('repeat provisioning refuses duplicate grants', db.sql(generated).returncode != 0)
        check('repeat failure preserves memberships', sql('SELECT count(*)=3 FROM ws4_dev_private.memberships') == 't')
        report['passed'] = True
    finally:
        try:
            db.stop()
            report['server_stopped'] = not db.started
        finally:
            (work/'report.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
            print('Report: ' + str(work/'report.json'))


if __name__ == '__main__':
    main()
