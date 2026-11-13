-- SQL Editor owner-only synthetic seed.
-- Use this when the RPC seed reports that auth.uid() is missing in SQL Editor.
-- It creates no patient and does not touch legacy incidents/responders.
-- Run Workstream 6 migration first.

do $$
declare
  v_hospital uuid := 'c6c7adb9-be6b-4dd6-ac47-17becd153df6'::uuid;
  v_unit uuid := gen_random_uuid();
  v_crew uuid := gen_random_uuid();
  v_incident uuid := gen_random_uuid();
begin
  insert into public.corvia_ws6_units(
    id, hospital_id, call_sign, unit_type, readiness_status, synthetic, created_by
  ) values (
    v_unit, v_hospital,
    'CV-' || substr(replace(gen_random_uuid()::text, '-', ''), 1, 6),
    'ambulance', 'idle', true, null
  );

  insert into public.corvia_ws6_crew_members(
    id, hospital_id, auth_user_id, display_name, role, credential_status
  ) values (
    v_crew, v_hospital, gen_random_uuid(), 'SQL Editor Demo Paramedic',
    'paramedic', 'verified'
  );

  insert into public.corvia_ws6_shifts(
    hospital_id, unit_id, crew_member_id, starts_at, ends_at, status
  ) values (
    v_hospital, v_unit, v_crew, now() - interval '15 minutes',
    now() + interval '12 hours', 'active'
  );

  insert into public.corvia_ws6_incidents(
    id, hospital_id, incident_number, priority, status, summary, synthetic, created_by
  ) values (
    v_incident, v_hospital,
    'WS6-SQL-' || substr(replace(gen_random_uuid()::text, '-', ''), 1, 8),
    'urgent', 'pending', 'Synthetic WS6 SQL Editor test incident', true, null
  );

  raise notice 'Synthetic Workstream 6 data created: unit %, incident %', v_unit, v_incident;
end;
$$;

select call_sign, unit_type, readiness_status, availability_revision, created_at
from public.corvia_ws6_units
where hospital_id = 'c6c7adb9-be6b-4dd6-ac47-17becd153df6'::uuid
order by created_at desc;

select incident_number, priority, status, summary, synthetic, created_at
from public.corvia_ws6_incidents
where hospital_id = 'c6c7adb9-be6b-4dd6-ac47-17becd153df6'::uuid
order by created_at desc;
