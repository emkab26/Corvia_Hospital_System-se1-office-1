"""Generate guarded access SQL for reviewed existing shared-backend demo users.

This tool only writes SQL. It never connects to a database or creates Auth users.
Run the output only after the reviewed WS4 installation and a restore plan exist.
The team EMS route stays inactive; Fleet/Paramedic access is separate.
"""

import argparse
from pathlib import Path
from uuid import UUID


def build(*, organisation: str, hospital: str, patient: str,
          dispatcher: str, supervisor: str) -> str:
    ids = {name: str(UUID(value)) for name, value in {
        'organisation': organisation, 'hospital': hospital,
        'patient': patient, 'dispatcher': dispatcher,
        'supervisor': supervisor,
    }.items()}
    if len({ids['patient'], ids['dispatcher'], ids['supervisor']}) != 3:
        raise ValueError('Patient, dispatcher and supervisor must be distinct users')
    return f"""-- REVIEWED SHARED DEMO ACCESS CANDIDATE. No Auth user or incident is created.
-- The team EMS handoff route remains inactive. This does not enroll medics or crews.
-- Verify the five UUIDs, exact project, restorable backup and current catalog.
BEGIN;
SET LOCAL ROLE postgres;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '30s';
DO $$ BEGIN
  IF to_regclass('ws4_private.installation') IS NULL
     OR to_regclass('ws4_private.ems_handoff_routes') IS NULL
     OR NOT EXISTS (SELECT 1 FROM ws4_private.installation
                    WHERE contract_version='ws4-dev-core-1') THEN
    RAISE EXCEPTION 'Reviewed WS4 core and EMS bridge must be installed';
  END IF;
  IF EXISTS (SELECT 1 FROM ws4_private.organisations
             WHERE id='{ids['organisation']}'::uuid)
     OR EXISTS (SELECT 1 FROM ws4_private.ems_handoff_routes
                WHERE hospital_id='{ids['hospital']}'::uuid)
     OR EXISTS (SELECT 1 FROM ws4_private.patient_routes
                WHERE user_id='{ids['patient']}'::uuid)
     OR EXISTS (SELECT 1 FROM ws4_private.memberships
                WHERE user_id IN ('{ids['dispatcher']}'::uuid,
                                  '{ids['supervisor']}'::uuid)) THEN
    RAISE EXCEPTION 'Existing organisation, hospital route or account mapping requires manual review';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.hospitals
                 WHERE id='{ids['hospital']}'::uuid AND is_active IS TRUE)
     OR NOT EXISTS (SELECT 1 FROM public.profiles pr
         JOIN public.patients pa ON pa.profile_id::text=pr.user_id::text
         JOIN auth.users au ON au.id=pr.user_id
         WHERE pr.user_id='{ids['patient']}'::uuid AND pr.role='patient'
           AND pr.is_active IS TRUE AND pa.hospital_id='{ids['hospital']}'::uuid)
     OR NOT EXISTS (SELECT 1 FROM public.profiles pr
         JOIN auth.users au ON au.id=pr.user_id
         WHERE pr.user_id='{ids['dispatcher']}'::uuid AND pr.role='dispatcher'
           AND pr.is_active IS TRUE)
     OR NOT EXISTS (SELECT 1 FROM public.profiles pr
         JOIN auth.users au ON au.id=pr.user_id
         WHERE pr.user_id='{ids['supervisor']}'::uuid
           AND pr.role='dispatch_supervisor' AND pr.is_active IS TRUE) THEN
    RAISE EXCEPTION 'Reviewed active hospital and distinct existing role-matched accounts required';
  END IF;
END $$;
INSERT INTO ws4_private.organisations(id,label)
VALUES ('{ids['organisation']}'::uuid,'WS4 reviewed demo dispatch');
INSERT INTO ws4_private.patient_routes(user_id,organisation_id)
VALUES ('{ids['patient']}'::uuid,'{ids['organisation']}'::uuid);
INSERT INTO ws4_private.memberships(user_id,organisation_id,role,active)
VALUES ('{ids['dispatcher']}'::uuid,'{ids['organisation']}'::uuid,'dispatcher',true),
       ('{ids['supervisor']}'::uuid,'{ids['organisation']}'::uuid,'dispatch_supervisor',true);
INSERT INTO ws4_private.ems_handoff_routes(organisation_id,hospital_id,active)
VALUES ('{ids['organisation']}'::uuid,'{ids['hospital']}'::uuid,false);
DO $$ BEGIN
  IF (SELECT count(*) FROM ws4_private.memberships
      WHERE organisation_id='{ids['organisation']}'::uuid AND active)=2
     AND (SELECT count(*) FROM ws4_private.patient_routes
          WHERE organisation_id='{ids['organisation']}'::uuid)=1
     AND EXISTS (SELECT 1 FROM ws4_private.ems_handoff_routes
          WHERE organisation_id='{ids['organisation']}'::uuid AND active=false)
  THEN RETURN;
  END IF;
  RAISE EXCEPTION 'Demo access postcondition failed';
END $$;
COMMIT;
"""


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('organisation', 'hospital', 'patient', 'dispatcher',
                 'supervisor'):
        parser.add_argument('--' + name, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    output = args.output.resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    with output.open('x', encoding='utf-8') as file:
        file.write(build(**{name: getattr(args, name) for name in
                            ('organisation', 'hospital', 'patient',
                             'dispatcher', 'supervisor')}))
    print(output)


if __name__ == '__main__':
    main()
