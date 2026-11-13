-- READ ONLY. Workstream 5 (Inpatient Ward & Bed Management) preflight.
-- Run this in the Supabase SQL Editor before adding any ward/bed migration.
-- It returns metadata and function definitions only; it never selects patient rows
-- and it does not create, update, delete, or grant anything.

select current_database() as database_name, version() as postgres_version;

-- 1. Confirm the tables and the fields used by the Flutter ward, bed and admission pages.
select table_schema,
       table_name,
       ordinal_position,
       column_name,
       data_type,
       udt_name,
       is_nullable,
       column_default
from information_schema.columns
where table_schema = 'public'
  and table_name in (
    'hospital_buildings',
    'hospital_floors',
    'hospital_wards',
    'hospital_rooms',
    'hospital_beds',
    'hospital_admissions',
    'patient_bed_assignments',
    'bed_status_history'
  )
order by table_name, ordinal_position;

-- 2. Check for the Workstream 5 fields that are not safe to assume from the export.
select table_name,
       column_name,
       data_type,
       udt_name,
       is_nullable,
       column_default
from information_schema.columns
where table_schema = 'public'
  and table_name in ('hospital_beds', 'patient_bed_assignments', 'bed_status_history')
  and column_name in (
    'reserved_until',
    'reservation_expires_at',
    'reserved_at',
    'cleaning_started_at',
    'cleaned_at',
    'last_cleaned_at',
    'sanitized_at',
    'sanitation_notes',
    'maintenance_reason',
    'evs_notified_at',
    'evs_notification_id'
  )
order by table_name, column_name;

-- 3. Constraints and indexes must protect the bed state machine and concurrent allocation.
select n.nspname as schema_name,
       c.relname as table_name,
       con.conname,
       case con.contype
         when 'p' then 'primary_key'
         when 'f' then 'foreign_key'
         when 'u' then 'unique'
         when 'c' then 'check'
         when 'x' then 'exclusion'
         else con.contype::text
       end as constraint_type,
       pg_get_constraintdef(con.oid) as definition
from pg_constraint con
join pg_class c on c.oid = con.conrelid
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public'
  and c.relname in (
    'hospital_buildings',
    'hospital_floors',
    'hospital_wards',
    'hospital_rooms',
    'hospital_beds',
    'hospital_admissions',
    'patient_bed_assignments',
    'bed_status_history'
  )
order by c.relname, con.conname;

select schemaname,
       tablename,
       indexname,
       indexdef
from pg_indexes
where schemaname = 'public'
  and tablename in (
    'hospital_beds',
    'hospital_admissions',
    'patient_bed_assignments',
    'bed_status_history'
  )
order by tablename, indexname;

-- 4. Triggers show whether status history, reservation expiry and cleaning metadata
-- are already maintained by the database.
select n.nspname as schema_name,
       c.relname as table_name,
       t.tgname as trigger_name,
       pg_get_triggerdef(t.oid) as trigger_definition,
       p.proname as trigger_function
from pg_trigger t
join pg_class c on c.oid = t.tgrelid
join pg_namespace n on n.oid = c.relnamespace
left join pg_proc p on p.oid = t.tgfoid
where not t.tgisinternal
  and n.nspname = 'public'
  and c.relname in (
    'hospital_beds',
    'hospital_admissions',
    'patient_bed_assignments',
    'bed_status_history'
  )
order by c.relname, t.tgname;

-- 5. Existing ward/admission RPC contracts. Return definitions so a later migration
-- can extend the real signatures instead of replacing unknown deployed functions.
select n.nspname as schema_name,
       p.proname as function_name,
       pg_get_function_identity_arguments(p.oid) as arguments,
       pg_get_function_result(p.oid) as result_type,
       p.prosecdef as security_definer,
       pg_get_userbyid(p.proowner) as owner,
       pg_get_functiondef(p.oid) as definition
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname in ('public', 'ws4_private', 'ws4_dev_private')
  and (
    p.proname ilike '%bed%'
    or p.proname ilike '%ward%'
    or p.proname ilike '%admission%'
    or p.proname ilike '%discharge%'
    or p.proname ilike '%transfer%'
    or p.proname ilike '%reserv%'
    or p.proname ilike '%clean%'
    or p.proname ilike '%sanit%'
    or p.proname ilike '%evs%'
  )
order by n.nspname, p.proname, pg_get_function_identity_arguments(p.oid);

-- 6. RLS policies and table privileges for the ward/bed workflow.
select schemaname,
       tablename,
       policyname,
       roles,
       cmd,
       qual,
       with_check
from pg_policies
where schemaname in ('public', 'ws4_private', 'ws4_dev_private')
  and tablename in (
    'hospital_buildings',
    'hospital_floors',
    'hospital_wards',
    'hospital_rooms',
    'hospital_beds',
    'hospital_admissions',
    'patient_bed_assignments',
    'bed_status_history'
  )
order by schemaname, tablename, policyname;

select table_schema,
       table_name,
       grantee,
       privilege_type
from information_schema.role_table_grants
where table_schema in ('public', 'ws4_private', 'ws4_dev_private')
  and table_name in (
    'hospital_buildings',
    'hospital_floors',
    'hospital_wards',
    'hospital_rooms',
    'hospital_beds',
    'hospital_admissions',
    'patient_bed_assignments',
    'bed_status_history'
  )
order by table_schema, table_name, grantee, privilege_type;

-- 7. Function EXECUTE grants for the contracts returned above.
select n.nspname as schema_name,
       p.proname as function_name,
       pg_get_function_identity_arguments(p.oid) as arguments,
       p.proacl as permissions
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname in ('public', 'ws4_private', 'ws4_dev_private')
  and (
    p.proname ilike '%bed%'
    or p.proname ilike '%ward%'
    or p.proname ilike '%admission%'
    or p.proname ilike '%discharge%'
    or p.proname ilike '%transfer%'
    or p.proname ilike '%reserv%'
    or p.proname ilike '%clean%'
    or p.proname ilike '%sanit%'
    or p.proname ilike '%evs%'
  )
order by n.nspname, p.proname, pg_get_function_identity_arguments(p.oid);

-- 8. Compact gap summary. A false value means that requirement is not evidenced
-- by the deployed metadata and needs an agreed additive design after this preflight.
select
  exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name = 'hospital_beds'
      and column_name in ('reserved_until', 'reservation_expires_at')
  ) as has_reservation_expiry,
  exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name = 'hospital_beds'
      and column_name in ('cleaned_at', 'last_cleaned_at', 'sanitized_at')
  ) as has_sanitation_timestamp,
  exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name = 'hospital_beds'
      and column_name in ('evs_notified_at', 'evs_notification_id')
  ) as has_evs_tracking,
  exists (
    select 1 from pg_trigger t
    join pg_class c on c.oid = t.tgrelid
    join pg_namespace n on n.oid = c.relnamespace
    where not t.tgisinternal
      and n.nspname = 'public'
      and c.relname = 'hospital_beds'
      and (
        pg_get_triggerdef(t.oid) ilike '%bed_status_history%'
        or pg_get_functiondef(t.tgfoid) ilike '%bed_status_history%'
      )
  ) as has_bed_history_trigger,
  exists (
    select 1 from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname ilike '%reservation%'
  ) as has_reservation_rpc,
  exists (
    select 1 from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and (p.proname ilike '%clean%' or p.proname ilike '%sanit%')
  ) as has_cleaning_rpc;
