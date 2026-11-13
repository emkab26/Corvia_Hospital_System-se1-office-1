-- Repair patient display names (13 Oct 2026).
--
-- Staff screens (nurse, reception, visitors, appointments) read the name from
-- public.patients, and reception/nurse sessions often cannot read other
-- people's profiles. Many patients rows have an empty name or the "Corvia" /
-- "Patient" placeholder, so those screens showed "Patient 3b1439be" or an
-- email address. This copies real names between profiles and patients; it
-- never invents a name except Alice Brown, the README demo account.
--
-- Run 23_fix_ems_logins.sql first so the fleet manager has a name to copy.
-- Run 20_check_patient_names.sql PART 1 before and after to compare.

begin;

-- 1. patients <- profiles (fills CVP-* rows such as tiaan, zandro, Eugene,
--    and replaces the placeholder on Bob Williams and Emma Wilson).
update public.patients pa
set first_name = trim(pr.first_name),
    surname    = coalesce(nullif(trim(pr.surname), ''), pa.surname),
    updated_at = now()
from public.profiles pr
where pa.profile_id = pr.user_id
  and nullif(trim(pr.first_name), '') is not null
  and not (lower(trim(pr.first_name)) = 'corvia' and lower(trim(coalesce(pr.surname, ''))) = 'patient')
  and (nullif(trim(pa.first_name), '') is null
       or (lower(trim(pa.first_name)) = 'corvia' and lower(trim(coalesce(pa.surname, ''))) = 'patient'));

-- 2. profiles <- patients (replaces the placeholder on Dr James Mitchell).
update public.profiles pr
set first_name = trim(pa.first_name),
    surname    = coalesce(nullif(trim(pa.surname), ''), pr.surname),
    updated_at = now()
from public.patients pa
where pa.profile_id = pr.user_id
  and nullif(trim(pa.first_name), '') is not null
  and not (lower(trim(pa.first_name)) = 'corvia' and lower(trim(coalesce(pa.surname, ''))) = 'patient')
  and (nullif(trim(pr.first_name), '') is null
       or (lower(trim(pr.first_name)) = 'corvia' and lower(trim(coalesce(pr.surname, ''))) = 'patient'));

-- 3. Alice Brown has the placeholder on both rows (README demo account).
update public.profiles
set first_name = 'Alice', surname = 'Brown', updated_at = now()
where email = 'alice.brown@corvia.co.za';

update public.patients
set first_name = 'Alice', surname = 'Brown', updated_at = now()
where profile_id = (select user_id from public.profiles
                    where email = 'alice.brown@corvia.co.za');

-- The Supabase SQL editor runs each Run as its own session, so the script
-- must commit itself; a separate `commit;` run afterwards commits nothing.
commit;

-- 4. Review (after commit): any patient still without a usable name.
select pr.email, pa.patient_number, pa.first_name, pa.surname
from public.patients pa
left join public.profiles pr on pr.user_id = pa.profile_id
where nullif(trim(pa.first_name), '') is null
   or (lower(trim(pa.first_name)) = 'corvia' and lower(trim(coalesce(pa.surname, ''))) = 'patient')
order by pr.email;

