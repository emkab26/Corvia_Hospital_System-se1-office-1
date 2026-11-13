-- READ ONLY: patient UUIDs eligible for the current blood-bank request workflow.
-- Use patient_uuid, not auth_user_uuid or the hospital UUID.
select
  p.id as patient_uuid,
  p.patient_number,
  coalesce(
    nullif(trim(concat_ws(' ', p.first_name, p.surname)), ''),
    nullif(trim(concat_ws(' ', pr.first_name, pr.surname)), ''),
    nullif(trim(p.email), ''),
    nullif(trim(pr.email), ''),
    'Name not recorded'
  ) as patient_name,
  p.profile_id as auth_user_uuid
from public.patients p
left join public.profiles pr on pr.user_id = p.profile_id
where p.hospital_id = 'c6c7adb9-be6b-4dd6-ac47-17becd153df6'::uuid
  and p.is_active is true
order by patient_name, p.patient_number;
