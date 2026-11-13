-- Patients showing as "Corvia Patient" in the app.
--
-- The app shows that label only when a patient's name is empty, and the doctor
-- views show whatever name is stored. Run PART 1 (read only) first. Only run
-- PART 2 after reviewing PART 1's output, inside a transaction you can roll back.

-- =========================================================================
-- PART 1 - read only: which patient accounts have a missing or placeholder name
-- =========================================================================
select
  pr.email,
  pr.first_name  as profile_first_name,
  pr.surname     as profile_surname,
  pa.first_name  as patient_first_name,
  pa.surname     as patient_surname,
  pa.patient_number
from public.profiles pr
left join public.patients pa on pa.profile_id = pr.user_id
where coalesce(pr.role, pr.user_type, 'patient') = 'patient'
  and (
    nullif(trim(pr.first_name), '') is null
    or (lower(trim(pr.first_name)) = 'corvia' and lower(trim(pr.surname)) = 'patient')
    or nullif(trim(pa.first_name), '') is null
    or (lower(trim(pa.first_name)) = 'corvia' and lower(trim(pa.surname)) = 'patient')
  )
order by pr.email;

-- =========================================================================
-- PART 2 - repair (review PART 1 first; run inside BEGIN ... COMMIT)
-- Copies a real name from whichever table has one into the one that does not.
-- It never invents a name. Accounts with no name anywhere (for example
-- alice.brown@corvia.co.za, if PART 1 shows both sides empty) must be
-- corrected by hand with the person's real name.
-- =========================================================================
-- begin;
--
-- update public.profiles pr
-- set first_name = pa.first_name,
--     surname    = coalesce(nullif(trim(pa.surname), ''), pr.surname),
--     updated_at = now()
-- from public.patients pa
-- where pa.profile_id = pr.user_id
--   and nullif(trim(pa.first_name), '') is not null
--   and not (lower(trim(pa.first_name)) = 'corvia' and lower(trim(pa.surname)) = 'patient')
--   and (nullif(trim(pr.first_name), '') is null
--        or (lower(trim(pr.first_name)) = 'corvia' and lower(trim(pr.surname)) = 'patient'));
--
-- update public.patients pa
-- set first_name = pr.first_name,
--     surname    = coalesce(nullif(trim(pr.surname), ''), pa.surname),
--     updated_at = now()
-- from public.profiles pr
-- where pa.profile_id = pr.user_id
--   and nullif(trim(pr.first_name), '') is not null
--   and not (lower(trim(pr.first_name)) = 'corvia' and lower(trim(pr.surname)) = 'patient')
--   and (nullif(trim(pa.first_name), '') is null
--        or (lower(trim(pa.first_name)) = 'corvia' and lower(trim(pa.surname)) = 'patient'));
--
-- -- Re-run PART 1; then COMMIT if it looks right, otherwise ROLLBACK.
-- commit;

-- =========================================================================
-- PART 3 - find what is writing the "Corvia" / "Patient" placeholder.
-- Nothing in the Git repository writes it, so look for a database function
-- or trigger that does (read only).
-- =========================================================================
select n.nspname as schema, p.proname as function_name
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname not in ('pg_catalog', 'information_schema')
  and p.prosrc ilike '%''Corvia''%'
  and p.prosrc ilike '%''Patient''%';

-- =========================================================================
-- PART 4 - accounts with the placeholder on BOTH tables (from PART 1, 13 Oct).
-- PART 2 cannot fix these because no real name exists anywhere. Names are
-- the README demo-account names; confirm before running.
-- =========================================================================
-- begin;
-- update public.profiles set first_name = 'Alice', surname = 'Brown', updated_at = now()
--   where email = 'alice.brown@corvia.co.za';
-- update public.patients set first_name = 'Alice', surname = 'Brown', updated_at = now()
--   where profile_id = (select user_id from public.profiles where email = 'alice.brown@corvia.co.za');
-- commit;
