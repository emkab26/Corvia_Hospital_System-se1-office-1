-- Corvia Workstream 5: additive ward/bed operations.
-- Run after reviewing supabase/scripts/workstreams/06_workstream5_ward_bed_preflight.sql.
-- This migration does not replace the existing admission/transfer RPCs.

begin;

alter table public.hospital_beds
  add column if not exists reserved_until timestamptz,
  add column if not exists cleaning_started_at timestamptz,
  add column if not exists cleaned_at timestamptz,
  add column if not exists sanitation_notes text,
  add column if not exists maintenance_reason text,
  add column if not exists evs_notified_at timestamptz;

create index if not exists hospital_beds_reservation_expiry_idx
  on public.hospital_beds (hospital_id, reserved_until)
  where status = 'reserved' and reserved_until is not null;

create or replace function public.corvia_mh_expire_bed_reservations(
  p_hospital_id uuid
) returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid;
  v_count integer;
begin
  select p.id into v_actor
  from public.profiles p
  where p.user_id = auth.uid()
  limit 1;

  if not exists (
    select 1
    from public.hospital_admins ha
    where ha.hospital_id = p_hospital_id
      and (ha.profile_id = auth.uid() or ha.profile_id = v_actor)
  ) then
    raise exception 'Hospital administrator access is required';
  end if;

  update public.hospital_beds
  set status = 'available',
      reserved_until = null,
      updated_by = v_actor,
      updated_at = now()
  where hospital_id = p_hospital_id
    and status = 'reserved'
    and reserved_until is not null
    and reserved_until <= now();

  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

create or replace function public.corvia_mh_set_bed_status(
  p_hospital_id uuid,
  p_bed_id uuid,
  p_new_status text,
  p_reason text default null,
  p_reserved_until timestamptz default null,
  p_sanitation_notes text default null
) returns public.hospital_beds
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid;
  v_bed public.hospital_beds;
  v_has_assignment boolean;
  v_reason text := nullif(trim(coalesce(p_reason, '')), '');
begin
  if p_new_status not in ('available', 'reserved', 'cleaning', 'maintenance', 'blocked') then
    raise exception 'This operation only changes non-occupied bed states';
  end if;

  select p.id into v_actor
  from public.profiles p
  where p.user_id = auth.uid()
  limit 1;

  if not exists (
    select 1
    from public.hospital_admins ha
    where ha.hospital_id = p_hospital_id
      and (ha.profile_id = auth.uid() or ha.profile_id = v_actor)
  ) then
    raise exception 'Hospital administrator access is required';
  end if;

  select * into v_bed
  from public.hospital_beds
  where id = p_bed_id and hospital_id = p_hospital_id
  for update;

  if not found then
    raise exception 'Bed not found in this hospital';
  end if;

  select exists (
    select 1
    from public.patient_bed_assignments a
    where a.hospital_id = p_hospital_id
      and a.bed_id = p_bed_id
      and a.status = 'active'
      and a.ended_at is null
  ) into v_has_assignment;

  if v_has_assignment then
    raise exception 'An active patient assignment keeps this bed occupied';
  end if;

  if p_new_status = 'reserved'
     and (p_reserved_until is null or p_reserved_until <= now()) then
    raise exception 'A reservation must have a future expiry time';
  end if;

  if p_new_status = 'maintenance' and v_reason is null then
    raise exception 'A maintenance reason is required';
  end if;

  if p_new_status = 'available'
     and v_bed.status = 'cleaning'
     and nullif(trim(coalesce(p_sanitation_notes, '')), '') is null then
    raise exception 'Record sanitation notes before making a cleaning bed available';
  end if;

  update public.hospital_beds
  set status = p_new_status,
      reserved_until = case when p_new_status = 'reserved' then p_reserved_until else null end,
      cleaning_started_at = case
        when p_new_status = 'cleaning' and v_bed.status <> 'cleaning' then now()
        else cleaning_started_at
      end,
      cleaned_at = case when p_new_status = 'available' and v_bed.status = 'cleaning' then now() else cleaned_at end,
      sanitation_notes = case
        when p_new_status = 'cleaning' and v_bed.status <> 'cleaning' then null
        when p_new_status = 'available' and v_bed.status = 'cleaning'
          then nullif(trim(coalesce(p_sanitation_notes, '')), '')
        else sanitation_notes
      end,
      maintenance_reason = case
        when p_new_status = 'maintenance' then v_reason
        else null
      end,
      evs_notified_at = case
        when p_new_status = 'cleaning' and v_bed.status <> 'cleaning' then now()
        else evs_notified_at
      end,
      updated_by = v_actor,
      updated_at = now()
  where id = p_bed_id and hospital_id = p_hospital_id
  returning * into v_bed;

  return v_bed;
end;
$$;

revoke all on function public.corvia_mh_expire_bed_reservations(uuid) from public, anon, service_role;
grant execute on function public.corvia_mh_expire_bed_reservations(uuid) to authenticated;
revoke all on function public.corvia_mh_set_bed_status(uuid, uuid, text, text, timestamptz, text) from public, anon, service_role;
grant execute on function public.corvia_mh_set_bed_status(uuid, uuid, text, text, timestamptz, text) to authenticated;

commit;
