-- AFTER 20261008_corvia_blood_bank.sql. Run as owner in Supabase SQL Editor.
-- Replace the three UUID placeholders and confirm the operating mode.
-- These are existing Auth user IDs (profiles.user_id), NOT profiles.id.
-- Does not create accounts, rewrite roles, enable clinical issue or seed stock.
begin;
do $$
declare
  v_hospital uuid := 'REPLACE_HOSPITAL_UUID';
  v_manager uuid := 'REPLACE_MANAGER_AUTH_USER_UUID';
  v_grantor uuid := 'REPLACE_GRANTING_ADMIN_AUTH_USER_UUID';
  v_mode text := 'receiver'; -- receiver, collector, hybrid
begin
  if not exists(select 1 from public.hospitals where id=v_hospital and is_active is true)
    or not exists(select 1 from public.profiles where user_id=v_manager and is_active is true)
    or not exists(select 1 from public.profiles where user_id=v_grantor and is_active is true) then
    raise exception 'Choose an active hospital, manager and granting administrator';
  end if;
  insert into public.corvia_bb_settings(hospital_id,operating_mode) values(v_hospital,v_mode);
  insert into public.corvia_bb_memberships(hospital_id,user_id,role,granted_by,reason)
    values(v_hospital,v_manager,'manager',v_grantor,'Initial blood-bank membership approved by hospital administrator');
  insert into public.corvia_bb_products(hospital_id,name,component) values
    (v_hospital,'Whole blood','Whole blood'),
    (v_hospital,'Packed red blood cells','Red cells'),
    (v_hospital,'Fresh frozen plasma','Plasma'),
    (v_hospital,'Cryoprecipitate','Cryoprecipitate'),
    (v_hospital,'Pooled platelets','Platelets'),
    (v_hospital,'Apheresis platelets','Platelets'),
    (v_hospital,'Washed red cells','Red cells'),
    (v_hospital,'Irradiated red cells','Red cells'),
    (v_hospital,'Irradiated platelets','Platelets'),
    (v_hospital,'Convalescent plasma','Plasma');
  -- Replace names with real approved storage locations before running.
  -- No temperatures or automatic shelf-life calculations are assumed.
  insert into public.corvia_bb_locations(hospital_id,name,location_type) values
    (v_hospital,'Main blood fridge','fridge'),
    (v_hospital,'Plasma freezer','freezer'),
    (v_hospital,'Platelet storage','platelet'),
    (v_hospital,'Quarantine hold','quarantine'),
    (v_hospital,'Disposal holding area','disposal');
end $$;
commit;

-- OPTIONAL SEPARATE ACTIONS: edit and execute only the required statement.
-- Add a technician, clinician or ward user using their Auth UUID:
-- insert into public.corvia_bb_memberships(hospital_id,user_id,role,granted_by,reason)
-- values ('HOSPITAL_UUID','AUTH_USER_UUID','technician','ADMIN_AUTH_USER_UUID','Recorded authorisation reference');

-- Revoke access (checked on every RPC; the UI also checks every 30 seconds):
-- update public.corvia_bb_memberships set active=false, reason='Revocation reference'
-- where hospital_id='HOSPITAL_UUID' and user_id='AUTH_USER_UUID';

-- Enable reservation and issue only once this hospital has designated its
-- clinical authority and approved this recorded-evidence workflow:
-- update public.corvia_bb_settings set clinical_issue_enabled=true,
--   clinical_authority_reference='ACTUAL hospital approval / policy reference'
-- where hospital_id='HOSPITAL_UUID';

-- Disable new reservation / issue without losing stock or movement records:
-- update public.corvia_bb_settings set clinical_issue_enabled=false
-- where hospital_id='HOSPITAL_UUID';
