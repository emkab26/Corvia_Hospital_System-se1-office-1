-- READ ONLY. Run in Supabase SQL Editor before the blood-bank migration.
-- This returns schema/permissions only, never patient rows or credentials.
select current_database() as database_name, version() as postgres_version;

select table_schema, table_name, column_name, data_type, udt_name, is_nullable
from information_schema.columns
where (table_schema = 'public' and table_name in (
  'profiles', 'hospitals', 'patients', 'hospital_staff', 'hospital_beds',
  'hospital_wards', 'hospital_admissions', 'patient_bed_assignments',
  'patient_hospital_links', 'incidents', 'responders', 'dispatch_profiles'))
  or table_name like 'corvia_bb_%'
order by table_schema, table_name, ordinal_position;

select n.nspname as schema_name, c.relname as table_name,
       con.conname, pg_get_constraintdef(con.oid) as definition
from pg_constraint con
join pg_class c on c.oid = con.conrelid
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public' and c.relname in (
  'profiles', 'hospital_beds', 'patient_bed_assignments', 'incidents')
order by c.relname, con.conname;

select schemaname, tablename, policyname, roles, cmd, qual, with_check
from pg_policies
where schemaname in ('public', 'ws4_private', 'ws4_dev_private')
  and (tablename in ('profiles', 'incidents', 'responders', 'hospital_staff')
       or tablename like 'corvia_bb_%')
order by schemaname, tablename, policyname;

select n.nspname as schema_name, p.proname,
       pg_get_function_identity_arguments(p.oid) as arguments,
       pg_get_function_result(p.oid) as result_type, p.prosecdef as security_definer,
       p.proacl as permissions
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname in ('public', 'ws4_private', 'ws4_dev_private')
  and (p.proname like '%dispatch%' or p.proname like '%fleet%'
       or p.proname like '%paramedic%' or p.proname like 'corvia_bb_%'
       or p.proname in ('corvia_mh_assign_bed', 'corvia_mh_discharge_admission'))
order by n.nspname, p.proname;
