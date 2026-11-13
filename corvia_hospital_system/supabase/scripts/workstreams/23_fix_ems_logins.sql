-- EMS logins (13 Oct 2026).
--
-- paramedic@co.za: the Auth user exists but has no public.profiles row, so
-- the app shows "Profile not found" (user id d167391d-1974-4fcd-9b32-7060bad9ba1d).
-- fleetmanager@co.za: has a profile (role patient, no name) but no Fleet
-- membership, so the workspace says "No workspace access".
--
-- After this script, link both in the app: Hospital Admin > Fleet Management
-- > Personnel (fleet manager as an administrator, paramedic as crew). Once
-- linked, signing in opens the Fleet & Paramedic workspace automatically.

begin;

-- 1. Create the missing profile. 'patient' is the only non-staff role the
--    profiles check constraint allows; Fleet access comes from Personnel.
insert into public.profiles (user_id, email, first_name, surname, role, user_type, is_active)
select u.id, u.email, 'Paramedic', 'Test', 'patient', 'patient', true
from auth.users u
where u.email = 'paramedic@co.za'
  and not exists (select 1 from public.profiles p where p.user_id = u.id);

-- 2. Give the fleet manager a display name.
update public.profiles
set first_name = coalesce(nullif(trim(first_name), ''), 'Fleet'),
    surname    = coalesce(nullif(trim(surname), ''), 'Manager'),
    updated_at = now()
where email = 'fleetmanager@co.za';

-- The Supabase SQL editor runs each Run as its own session, so the script
-- must commit itself; a separate `commit;` run afterwards commits nothing.
commit;

-- 3. Check (after commit).
select p.email, p.first_name, p.surname, p.role
from public.profiles p
where p.email in ('paramedic@co.za', 'fleetmanager@co.za');

