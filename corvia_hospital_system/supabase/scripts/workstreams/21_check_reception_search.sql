-- Reception "Search Patient" returns "No patients found".
-- The app calls public.reception_search_patients(p_search), which is not in
-- the Git repository. Everything here is read only.

-- 1. The live definition. Look at its WHERE clause: which columns it searches
--    and whether it limits results to the receptionist's hospital.
select pg_get_functiondef(p.oid)
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname = 'reception_search_patients';

-- 2. Whether the demo patients are linked to a hospital at all. If the
--    function filters by hospital, patients with neither a hospital_id nor a
--    patient_hospital_links row can never be found by reception.
select
  pa.patient_number,
  pa.first_name,
  pa.surname,
  pr.email,
  pa.hospital_id,
  (select count(*) from public.patient_hospital_links l
    where l.patient_id = pa.id) as hospital_links
from public.patients pa
left join public.profiles pr on pr.user_id = pa.profile_id
order by pr.email;

-- 3. Which hospital the reception account belongs to.
select s.*
from public.corvia_hospital_reception_staff s
-- reception_staff.profile_id references profiles.id (not user_id).
join public.profiles pr on pr.id = s.profile_id
where pr.email = 'reception@co.za';
