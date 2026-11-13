-- OPTIONAL TEST DATA ONLY. This creates one synthetic Fleet/Paramedic set for
-- Corvia Medical Hospital 1. It does not create a real patient or incident.
-- Run the Workstream 6 migration first.

select public.corvia_ws6_create_demo_set(
  'c6c7adb9-be6b-4dd6-ac47-17becd153df6'::uuid,
  'Demo Paramedic'
);

-- Safe status view for checking the synthetic workspace.
select call_sign, unit_type, readiness_status, availability_revision,
       active, created_at
from public.corvia_ws6_units
where hospital_id = 'c6c7adb9-be6b-4dd6-ac47-17becd153df6'::uuid
order by created_at desc;

select incident_number, priority, status, summary, synthetic, created_at
from public.corvia_ws6_incidents
where hospital_id = 'c6c7adb9-be6b-4dd6-ac47-17becd153df6'::uuid
order by created_at desc;
