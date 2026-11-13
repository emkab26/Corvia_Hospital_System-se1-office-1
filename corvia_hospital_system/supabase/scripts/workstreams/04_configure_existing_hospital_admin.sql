-- Run AFTER the blood-bank installation. SQL Editor / postgres role.
-- Proposed initial blood-bank manager and granting administrator: admin@co.za.
-- Uses that account's EXISTING hospital_admins link; never chooses an arbitrary hospital.
-- Creates no patient data and keeps clinical issue disabled on new configurations.
begin;
do $$
declare
  v_admin uuid := 'ba9f9d42-fc7d-4532-aa3f-c8b07f5da145';
  v_hospital uuid;
  v_hospitals uuid[];
begin
  if not exists (
    select 1 from public.profiles
    where user_id = v_admin and is_active is true
  ) then
    raise exception 'The selected administrator account is missing or inactive.';
  end if;

  select array_agg(distinct h.id) into v_hospitals
  from public.hospital_admins a
  join public.hospitals h on h.id = a.hospital_id
  where a.profile_id = v_admin
    and a.role in ('admin', 'manager')
    and h.is_active is true;

  if coalesce(cardinality(v_hospitals), 0) <> 1 then
    raise exception 'Expected exactly one active hospital linked to admin@co.za; found %. Run the hospital-link query and select the correct hospital.',
      coalesce(cardinality(v_hospitals), 0);
  end if;
  v_hospital := v_hospitals[1];

  insert into public.corvia_bb_settings (hospital_id, operating_mode)
  values (v_hospital, 'receiver')
  on conflict (hospital_id) do nothing;

  insert into public.corvia_bb_memberships (
    hospital_id, user_id, role, granted_by, reason
  ) values (
    v_hospital, v_admin, 'manager', v_admin,
    'Initial blood-bank setup for the designated existing hospital administrator; executed by database owner.'
  ) on conflict (hospital_id, user_id) do nothing;

  if not exists (
    select 1 from public.corvia_bb_memberships
    where hospital_id = v_hospital and user_id = v_admin
      and role = 'manager' and active
  ) then
    raise exception 'Existing membership is inactive or has another role. This setup will not reactivate or promote it.';
  end if;

  insert into public.corvia_bb_products (hospital_id, name, component)
  values
    (v_hospital, 'Whole blood', 'Whole blood'),
    (v_hospital, 'Packed red blood cells', 'Red cells'),
    (v_hospital, 'Fresh frozen plasma', 'Plasma'),
    (v_hospital, 'Cryoprecipitate', 'Cryoprecipitate'),
    (v_hospital, 'Pooled platelets', 'Platelets'),
    (v_hospital, 'Apheresis platelets', 'Platelets'),
    (v_hospital, 'Washed red cells', 'Red cells'),
    (v_hospital, 'Irradiated red cells', 'Red cells'),
    (v_hospital, 'Irradiated platelets', 'Platelets'),
    (v_hospital, 'Convalescent plasma', 'Plasma')
  on conflict (hospital_id, name) do nothing;

  -- Review these names against the hospital's actual storage locations.
  insert into public.corvia_bb_locations (hospital_id, name, location_type)
  values
    (v_hospital, 'Main blood fridge', 'fridge'),
    (v_hospital, 'Plasma freezer', 'freezer'),
    (v_hospital, 'Platelet storage', 'platelet'),
    (v_hospital, 'Quarantine hold', 'quarantine'),
    (v_hospital, 'Disposal holding area', 'disposal')
  on conflict (hospital_id, name) do nothing;
end $$;
commit;

select h.name as hospital, m.user_id, m.role, m.active,
  s.operating_mode, s.clinical_issue_enabled,
  (select count(*) from public.corvia_bb_products p
    where p.hospital_id = h.id) as products,
  (select count(*) from public.corvia_bb_locations l
    where l.hospital_id = h.id) as locations
from public.corvia_bb_memberships m
join public.hospitals h on h.id = m.hospital_id
join public.corvia_bb_settings s on s.hospital_id = h.id
where m.user_id = 'ba9f9d42-fc7d-4532-aa3f-c8b07f5da145';
