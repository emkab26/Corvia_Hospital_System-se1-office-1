-- Corvia live QA fixes (2026-10-10)
-- Run once in the Supabase SQL Editor after workstream scripts 11 and 13.
-- Safe to run again.

begin;

do $$
begin
  if to_regclass('public.corvia_ws6_units_actual') is null then
    raise exception 'Fleet/Paramedic base is missing. Run 11_install_fleet_paramedic.sql first';
  end if;

  if not exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'corvia_ws6_units_actual'
      and column_name = 'compliance_expiry_date'
  ) then
    raise exception 'Fleet/Paramedic upgrade is missing. Run 13_dispatch_fleet_upgrade.sql before this QA script';
  end if;

  if to_regclass('public.hospital_rooms') is null
     or to_regclass('public.hospital_beds') is null then
    raise exception 'Hospital room/bed tables are missing. Install the Ward & Bed package first';
  end if;

  if to_regprocedure('public.corvia_ems_check(uuid,uuid)') is null
     or to_regprocedure('public.corvia_ems_allowed(uuid,bigint)') is null then
    raise exception 'Fleet/Paramedic RPCs are incomplete. Run packages 11 and 13 before this QA script';
  end if;
end;
$$;

create or replace function public.corvia_ws6_validate_vehicle()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if nullif(btrim(new.registration_number), '') is null then
    raise exception 'Registration number is required';
  end if;

  if new.compliance_expiry_date is not null
     and new.compliance_expiry_date < (now() at time zone 'Africa/Johannesburg')::date then
    raise exception 'Vehicle compliance expiry cannot be in the past';
  end if;

  return new;
end;
$$;

drop trigger if exists corvia_ws6_validate_vehicle on public.corvia_ws6_units_actual;
create trigger corvia_ws6_validate_vehicle
before insert or update of registration_number, compliance_expiry_date
on public.corvia_ws6_units_actual
for each row execute function public.corvia_ws6_validate_vehicle();

create or replace function public.corvia_validate_room_bed_capacity()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  room_capacity integer;
  active_beds integer;
begin
  if new.is_active is false then
    return new;
  end if;

  select capacity
    into room_capacity
  from public.hospital_rooms
  where id = new.room_id
    and hospital_id = new.hospital_id;

  if room_capacity is null then
    raise exception 'The selected room does not belong to this hospital';
  end if;

  select count(*)
    into active_beds
  from public.hospital_beds b
  where b.hospital_id = new.hospital_id
    and b.room_id = new.room_id
    and b.is_active
    and b.id is distinct from new.id;

  if active_beds >= room_capacity then
    raise exception 'This room is full (% of % beds)', active_beds, room_capacity;
  end if;

  return new;
end;
$$;

drop trigger if exists corvia_validate_room_bed_capacity on public.hospital_beds;
create trigger corvia_validate_room_bed_capacity
before insert or update of room_id, hospital_id, is_active
on public.hospital_beds
for each row execute function public.corvia_validate_room_bed_capacity();

create or replace function public.corvia_ems_update_patient(
  h uuid,
  s uuid,
  i bigint,
  pid bigint,
  p jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  updated_patient public.corvia_ws6_patients_actual%rowtype;
begin
  perform public.corvia_ems_check(h, s);

  if not public.corvia_ems_allowed(h, i) then
    raise exception 'Incident access denied';
  end if;

  if not exists (
    select 1
    from public.corvia_ws6_incident_patients ip
    where ip.hospital_id = h
      and ip.incident_id = i
      and ip.patient_id = pid
      and ip.is_active
  ) then
    raise exception 'Patient is not assigned to this incident';
  end if;

  if nullif(p->>'date_of_birth', '')::date > current_date then
    raise exception 'Date of birth cannot be in the future';
  end if;

  update public.corvia_ws6_patients_actual
  set
    patient_number = coalesce(nullif(btrim(p->>'patient_number'), ''), patient_number),
    identity_number = coalesce(nullif(btrim(p->>'identity_number'), ''), identity_number),
    first_name = coalesce(nullif(btrim(p->>'first_name'), ''), first_name),
    last_name = coalesce(nullif(btrim(p->>'last_name'), ''), last_name),
    date_of_birth = coalesce(nullif(p->>'date_of_birth', '')::date, date_of_birth),
    sex = coalesce(nullif(p->>'sex', ''), sex),
    patient_recorded_blood_type = coalesce(
      nullif(p->>'patient_recorded_blood_type', ''),
      patient_recorded_blood_type
    )
  where hospital_id = h
    and patient_id = pid
  returning * into updated_patient;

  if updated_patient.patient_id is null then
    raise exception 'Patient was not found';
  end if;

  insert into public.corvia_ws6_audit_logs (
    hospital_id,
    user_id,
    incident_id,
    patient_id,
    action_type,
    entity_type,
    entity_id,
    new_value,
    reason
  ) values (
    h,
    public.corvia_ems_member(h),
    i,
    pid,
    'patient_update',
    'patient',
    pid,
    to_jsonb(updated_patient),
    'Patient identification details updated after initial capture'
  );

  return to_jsonb(updated_patient);
end;
$$;

revoke all on function public.corvia_ems_update_patient(uuid, uuid, bigint, bigint, jsonb)
from public, anon;
grant execute on function public.corvia_ems_update_patient(uuid, uuid, bigint, bigint, jsonb)
to authenticated;

notify pgrst, 'reload schema';
commit;

-- Verification: all three values must be true.
select
  to_regprocedure('public.corvia_ems_update_patient(uuid,uuid,bigint,bigint,jsonb)') is not null
    as has_patient_update_rpc,
  exists (
    select 1 from pg_trigger
    where tgname = 'corvia_ws6_validate_vehicle' and not tgisinternal
  ) as has_vehicle_validation,
  exists (
    select 1 from pg_trigger
    where tgname = 'corvia_validate_room_bed_capacity' and not tgisinternal
  ) as has_bed_capacity_validation;
