"""Build one reviewable, all-or-nothing WS4 SQL transaction for coastit.

This prints SQL only. It does not connect to or change a database. The team
Fleet/Paramedic contracts (workstreams 11 and 13) must already exist. Do not
execute without reviewing the exact target's backup, catalog and consumers of
register_auth_user_temp(text,text).
"""

from pathlib import Path
import argparse

ROOT = Path(__file__).resolve().parents[1]
RELEASE = ROOT / 'supabase/scripts/ws4_release'
FILES = (
    '001_shared_upgrade.sql',
    '002_team_ems_handoff.sql',
    '003_team_ems_completion.sql',
    '004_team_backup_receiver.sql',
    '005_team_operational_completion.sql',
    '006_patient_progress.sql',
    '007_incident_voice.sql',
    '008_scoped_requester_identity.sql',
    '009_patient_callback.sql',
    '010_contact_alert_outbox.sql',
    '011_patient_push_outbox.sql',
)


def _transaction_body(path: Path) -> str:
    lines = path.read_text(encoding='utf-8').splitlines()
    begins = [i for i, line in enumerate(lines) if line.strip().upper() == 'BEGIN;']
    commits = [i for i, line in enumerate(lines) if line.strip().upper() == 'COMMIT;']
    if len(begins) != 1 or len(commits) != 1 or commits[0] != len(lines) - 1:
        raise ValueError(f'Unexpected transaction boundary in {path.name}')
    if any(line.strip() for line in lines[:begins[0]] if not line.lstrip().startswith('--')):
        raise ValueError(f'Unexpected SQL before BEGIN in {path.name}')
    return '\n'.join(lines[begins[0] + 1:commits[0]])


def build() -> str:
    prefix = '''-- Review the exact project before execution. SQL Editor runs as
-- supabase_admin, which must be a member of postgres. No account or demo
-- resource is provisioned by this transaction.
BEGIN;
SET LOCAL ROLE postgres;
-- The operator must set the review marker outside this generated bundle,
-- after explicit approval, target rehearsal and verified recovery planning.
DO $$ BEGIN
  IF current_setting('corvia.ws4_shared_review',true) IS DISTINCT FROM 'approved' THEN
    RAISE EXCEPTION 'Explicit external owner review approval is required';
  END IF;
END $$;
-- Current Flutter signup uses auth.signUp, not this legacy function. Unknown
-- external consumers must be resolved before applying this permission change.
REVOKE EXECUTE ON FUNCTION public.register_auth_user_temp(text,text)
  FROM PUBLIC, anon, authenticated;
'''
    sections = [prefix]
    for name in FILES:
        sections.append(f'\n-- BEGIN reviewed {name}\n')
        sections.append(_transaction_body(RELEASE / name))
        sections.append(f'\n-- END reviewed {name}\n')
    sections.append('''
DO $$ BEGIN
  IF to_regclass('ws4_private.installation') IS NULL
     OR to_regclass('ws4_private.ems_handoff_routes') IS NULL
     OR to_regclass('ws4_private.push_outbox') IS NULL
     OR has_function_privilege('anon',
       'public.register_auth_user_temp(text,text)', 'EXECUTE') THEN
    RAISE EXCEPTION 'WS4 atomic install verification failed';
  END IF;
END $$;
COMMIT;
''')
    return '\n'.join(sections)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(build(), encoding='utf-8')
    print(args.output)
