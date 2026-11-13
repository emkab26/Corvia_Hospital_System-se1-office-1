-- Ward & Bed installation verification (read-only).
-- Run after supabase/migrations/20261008_corvia_workstream5_ward_bed.sql.

-- 1. One-row installation result. Every value should be true.
select
  to_regclass('public.hospital_beds') is not null as has_hospital_beds,
  to_regclass('public.patient_bed_assignments') is not null as has_bed_assignments,
  exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'hospital_beds'
      and column_name = 'reserved_until'
  ) as has_reservation_expiry,
  exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'hospital_beds'
      and column_name = 'cleaning_started_at'
  ) as has_cleaning_started_at,
  exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'hospital_beds'
      and column_name = 'cleaned_at'
  ) as has_cleaned_at,
  exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'hospital_beds'
      and column_name = 'sanitation_notes'
  ) as has_sanitation_notes,
  exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'hospital_beds'
      and column_name = 'maintenance_reason'
  ) as has_maintenance_reason,
  exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'hospital_beds'
      and column_name = 'evs_notified_at'
  ) as has_evs_tracking,
  to_regprocedure('public.corvia_mh_expire_bed_reservations(uuid)') is not null
    as has_reservation_rpc,
  to_regprocedure(
    'public.corvia_mh_set_bed_status(uuid,uuid,text,text,timestamptz,text)'
  ) is not null as has_status_rpc,
  to_regclass('public.hospital_beds_reservation_expiry_idx') is not null
    as has_reservation_index;

-- 2. Authenticated users may call the guarded RPCs. The RPCs still verify
-- hospital administrator membership before changing data.
select
  has_function_privilege(
    'authenticated',
    'public.corvia_mh_expire_bed_reservations(uuid)',
    'EXECUTE'
  ) as authenticated_can_expire_reservations,
  has_function_privilege(
    'authenticated',
    'public.corvia_mh_set_bed_status(uuid,uuid,text,text,timestamptz,text)',
    'EXECUTE'
  ) as authenticated_can_request_status_change,
  not has_function_privilege(
    'anon',
    'public.corvia_mh_expire_bed_reservations(uuid)',
    'EXECUTE'
  ) as anon_cannot_expire_reservations,
  not has_function_privilege(
    'anon',
    'public.corvia_mh_set_bed_status(uuid,uuid,text,text,timestamptz,text)',
    'EXECUTE'
  ) as anon_cannot_change_status;

-- 3. Current operational counts by hospital and bed status.
select
  h.id as hospital_uuid,
  h.name as hospital,
  b.status,
  count(*) as beds
from public.hospital_beds b
join public.hospitals h on h.id = b.hospital_id
group by h.id, h.name, b.status
order by h.name, b.status;

-- 4. Active assignment consistency. This should return no rows.
select
  b.hospital_id,
  b.id as bed_id,
  b.bed_number,
  b.status,
  count(a.id) as active_assignments
from public.hospital_beds b
join public.patient_bed_assignments a
  on a.hospital_id = b.hospital_id
 and a.bed_id = b.id
 and a.status = 'active'
 and a.ended_at is null
where b.status <> 'occupied'
group by b.hospital_id, b.id, b.bed_number, b.status;
