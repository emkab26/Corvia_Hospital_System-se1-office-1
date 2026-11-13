"""Generate reviewed synthetic provisioning SQL; never connect or create accounts.

Requires existing distinct Auth users with profiles, a Synthetic organisation and
a Synthetic hospital in the owned synthetic-only project. Never use on shared.
"""
import argparse
from pathlib import Path
import uuid


def build(organisation, hospital, patient, dispatcher, supervisor, crew_a, crew_b, receiver):
    values = [str(uuid.UUID(v)) for v in (organisation, hospital, patient, dispatcher, supervisor, crew_a, crew_b, receiver)]
    organisation, hospital, patient, dispatcher, supervisor, crew_a, crew_b, receiver = values
    if len(set(values[2:])) != 6:
        raise ValueError('Use six distinct test identities')
    unit_a, unit_b, manifest_a, manifest_b = [str(uuid.uuid5(uuid.UUID(organisation), 'ws4-demo-'+name)) for name in ('unit-a','unit-b','crew-a','crew-b')]
    users = ','.join("'"+v+"'::uuid" for v in values[2:])
    return f"""-- GENERATED synthetic-only preparation. Review IDs before executing as owner.
-- One-time provisioning; conflicts roll back. No passwords, new Auth users or live provider calls.
BEGIN;
SET LOCAL lock_timeout='5s';
DO $$ BEGIN
  IF current_user<>'postgres' OR NOT EXISTS(SELECT 1 FROM ws4_dev_private.installation WHERE synthetic_only)
    OR NOT EXISTS(SELECT 1 FROM ws4_dev_private.organisations WHERE id='{organisation}' AND label LIKE 'Synthetic %')
    OR NOT EXISTS(SELECT 1 FROM public.hospitals WHERE id='{hospital}' AND name LIKE 'Synthetic %' AND is_active IS TRUE AND latitude IS NOT NULL AND longitude IS NOT NULL) THEN
    RAISE EXCEPTION 'Owned synthetic-only project and reviewed synthetic organisation/hospital required'; END IF;
  IF (SELECT count(*) FROM public.profiles p JOIN auth.users a ON a.id=p.user_id WHERE p.user_id IN ({users}) AND p.is_active IS TRUE)<>6 THEN
    RAISE EXCEPTION 'Six existing active synthetic Auth users and matching profiles required'; END IF;
END $$;
INSERT INTO ws4_dev_private.memberships VALUES('{dispatcher}','{organisation}','dispatcher',true),('{supervisor}','{organisation}','dispatch_supervisor',true) ON CONFLICT DO NOTHING;
INSERT INTO ws4_dev_private.patient_routes VALUES('{patient}','{organisation}') ON CONFLICT DO NOTHING;
DO $$ BEGIN
  IF NOT EXISTS(SELECT 1 FROM ws4_dev_private.memberships WHERE user_id='{dispatcher}' AND organisation_id='{organisation}' AND role='dispatcher' AND active)
    OR NOT EXISTS(SELECT 1 FROM ws4_dev_private.memberships WHERE user_id='{supervisor}' AND organisation_id='{organisation}' AND role='dispatch_supervisor' AND active)
    OR NOT EXISTS(SELECT 1 FROM ws4_dev_private.patient_routes WHERE user_id='{patient}' AND organisation_id='{organisation}') THEN
    RAISE EXCEPTION 'Existing membership or patient route conflicts; nothing overwritten'; END IF;
END $$;
-- Only navigation hints on the owned synthetic project; authority is above.
UPDATE public.profiles SET role='dispatcher' WHERE user_id='{dispatcher}';
UPDATE public.profiles SET role='dispatch_supervisor' WHERE user_id='{supervisor}';
INSERT INTO ws4_dev_private.response_fleet_reviewers VALUES('{supervisor}','{organisation}',true);
INSERT INTO ws4_dev_private.response_destinations VALUES('{hospital}','{organisation}',true);
INSERT INTO ws4_dev_private.response_receivers VALUES('{receiver}','{hospital}',true);
INSERT INTO ws4_dev_private.response_units(id,organisation_id,label,latitude,longitude,location_at,location_source)
 SELECT v.id,'{organisation}',v.label,h.latitude,h.longitude,now(),'operator' FROM public.hospitals h
 CROSS JOIN (VALUES('{unit_a}'::uuid,'Synthetic demo unit A'),('{unit_b}'::uuid,'Synthetic demo unit B')) v(id,label) WHERE h.id='{hospital}';
INSERT INTO ws4_dev_private.response_crews(id,organisation_id,unit_id,label,active,verified_until,shift_start,shift_end) VALUES
 ('{manifest_a}','{organisation}','{unit_a}','Synthetic crew A',true,now()+interval '8 hours',now(),now()+interval '8 hours'),
 ('{manifest_b}','{organisation}','{unit_b}','Synthetic crew B',true,now()+interval '8 hours',now(),now()+interval '8 hours');
INSERT INTO ws4_dev_private.response_crew_members VALUES('{manifest_a}','{crew_a}',true,now()+interval '8 hours'),('{manifest_b}','{crew_b}',true,now()+interval '8 hours');
-- Units remain NOT READY. Signed-in independent reviewer must record the checklist.
-- Operator-entered synthetic positions become stale after five minutes. Crew can
-- share a real device position explicitly, or the owner can review fresh synthetic coordinates.
COMMIT;
"""


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('organisation','hospital','patient','dispatcher','supervisor','crew-a','crew-b','receiver'):
        parser.add_argument('--'+name, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    content = build(args.organisation,args.hospital,args.patient,args.dispatcher,args.supervisor,args.crew_a,args.crew_b,args.receiver)
    # Avoid silently replacing a previously reviewed provisioning file.
    with args.output.open('x',encoding='utf-8') as output:
        output.write(content)
    print('Generated reviewed synthetic provisioning SQL: '+str(args.output))


if __name__ == '__main__':
    main()
