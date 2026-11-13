-- Workstream 6 real operations upgrade.
-- Keeps the namespaced test contract but adds real admin-entry RPCs.
-- Existing synthetic rows remain marked synthetic and are not used as real records.

begin;

alter table public.corvia_ws6_crew_members
  alter column auth_user_id drop not null,
  add column if not exists staff_identifier text,
  add column if not exists credential_reference text;

alter table public.corvia_ws6_units
  add column if not exists synthetic boolean not null default true;

alter table public.corvia_ws6_units
  alter column synthetic set default true;

-- Rows created by the earlier SQL-editor demo had no actor identity. Keep them
-- out of the real operations screen while preserving them for test audit review.
update public.corvia_ws6_units
set synthetic = true
where created_by is null and synthetic = false;

create or replace function public.corvia_ws6_create_incident(
  p_hospital_id uuid,
  p_priority text,
  p_summary text,
  p_synthetic boolean default false
) returns public.corvia_ws6_incidents
language plpgsql
security definer
set search_path = public
as $$
declare
  v_incident public.corvia_ws6_incidents;
  v_number text;
begin
  if not public.corvia_ws6_is_hospital_admin(p_hospital_id) then
    raise exception 'Hospital administrator access is required';
  end if;
  if p_priority not in ('routine', 'urgent', 'emergency', 'critical') then
    raise exception 'Invalid incident priority';
  end if;
  if nullif(trim(coalesce(p_summary, '')), '') is null then
    raise exception 'Incident summary is required';
  end if;

  v_number := case when p_synthetic then 'WS6-SYN-' else 'WS6-' end
    || to_char(clock_timestamp(), 'YYYYMMDDHH24MISSMS')
    || '-' || substr(replace(gen_random_uuid()::text, '-', ''), 1, 6);
  insert into public.corvia_ws6_incidents(
    hospital_id, incident_number, priority, summary, synthetic, created_by
  ) values (
    p_hospital_id, v_number, p_priority, trim(p_summary), p_synthetic, auth.uid()
  ) returning * into v_incident;

  insert into public.corvia_ws6_events(
    hospital_id, entity_type, entity_id, event_type, actor_auth_user_id, payload
  ) values (
    p_hospital_id, 'incident', v_incident.id, 'created', auth.uid(),
    jsonb_build_object('synthetic', p_synthetic)
  );
  return v_incident;
end;
$$;

create or replace function public.corvia_ws6_create_unit(
  p_hospital_id uuid,
  p_call_sign text,
  p_unit_type text default 'ambulance',
  p_readiness_status text default 'idle',
  p_notes text default null
) returns public.corvia_ws6_units
language plpgsql
security definer
set search_path = public
as $$
declare
  v_unit public.corvia_ws6_units;
begin
  if not public.corvia_ws6_is_hospital_admin(p_hospital_id) then
    raise exception 'Hospital administrator access is required';
  end if;
  if nullif(trim(coalesce(p_call_sign, '')), '') is null then
    raise exception 'Call sign is required';
  end if;
  if p_readiness_status not in ('ready', 'idle', 'maintenance', 'off_duty') then
    raise exception 'New units may only start as ready, idle, maintenance or off duty';
  end if;
  insert into public.corvia_ws6_units(
    hospital_id, call_sign, unit_type, readiness_status, notes, synthetic, created_by
  ) values (
    p_hospital_id, trim(p_call_sign), coalesce(nullif(trim(p_unit_type), ''), 'ambulance'),
    p_readiness_status, nullif(trim(coalesce(p_notes, '')), ''), false, auth.uid()
  ) returning * into v_unit;
  insert into public.corvia_ws6_events(hospital_id, entity_type, entity_id, event_type, actor_auth_user_id, payload)
  values (p_hospital_id, 'unit', v_unit.id, 'registered', auth.uid(), jsonb_build_object('call_sign', v_unit.call_sign));
  return v_unit;
exception when unique_violation then
  raise exception 'A unit with this call sign already exists at this hospital';
end;
$$;

create or replace function public.corvia_ws6_register_shift(
  p_hospital_id uuid,
  p_unit_id uuid,
  p_display_name text,
  p_staff_identifier text,
  p_role text default 'paramedic',
  p_credential_status text default 'pending',
  p_credential_reference text default null,
  p_auth_user_id uuid default null,
  p_starts_at timestamptz default now(),
  p_ends_at timestamptz default null
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_crew public.corvia_ws6_crew_members;
  v_shift public.corvia_ws6_shifts;
  v_ends_at timestamptz := coalesce(p_ends_at, p_starts_at + interval '12 hours');
begin
  if not public.corvia_ws6_is_hospital_admin(p_hospital_id) then
    raise exception 'Hospital administrator access is required';
  end if;
  if nullif(trim(coalesce(p_display_name, '')), '') is null then
    raise exception 'Crew member name is required';
  end if;
  if nullif(trim(coalesce(p_staff_identifier, '')), '') is null then
    raise exception 'Staff identifier is required';
  end if;
  if p_credential_status not in ('pending', 'verified', 'expired', 'suspended') then
    raise exception 'Invalid credential status';
  end if;
  if v_ends_at <= p_starts_at then
    raise exception 'Shift end must be after shift start';
  end if;
  if not exists (select 1 from public.corvia_ws6_units where id = p_unit_id and hospital_id = p_hospital_id and active) then
    raise exception 'Active unit not found';
  end if;

  if p_auth_user_id is not null then
    insert into public.corvia_ws6_crew_members(
      hospital_id, auth_user_id, display_name, staff_identifier, role,
      credential_status, credential_reference
    ) values (
      p_hospital_id, p_auth_user_id, trim(p_display_name), trim(p_staff_identifier),
      coalesce(nullif(trim(p_role), ''), 'paramedic'), p_credential_status,
      nullif(trim(coalesce(p_credential_reference, '')), '')
    )
    on conflict (hospital_id, auth_user_id) do update
      set display_name = excluded.display_name,
          staff_identifier = excluded.staff_identifier,
          role = excluded.role,
          credential_status = excluded.credential_status,
          credential_reference = excluded.credential_reference,
          active = true
    returning * into v_crew;
  else
    insert into public.corvia_ws6_crew_members(
      hospital_id, auth_user_id, display_name, staff_identifier, role,
      credential_status, credential_reference
    ) values (
      p_hospital_id, null, trim(p_display_name), trim(p_staff_identifier),
      coalesce(nullif(trim(p_role), ''), 'paramedic'), p_credential_status,
      nullif(trim(coalesce(p_credential_reference, '')), '')
    ) returning * into v_crew;
  end if;

  insert into public.corvia_ws6_shifts(
    hospital_id, unit_id, crew_member_id, starts_at, ends_at, status
  ) values (
    p_hospital_id, p_unit_id, v_crew.id, p_starts_at, v_ends_at,
    case when p_starts_at <= now() and v_ends_at > now() then 'active' else 'scheduled' end
  ) returning * into v_shift;

  insert into public.corvia_ws6_events(hospital_id, entity_type, entity_id, event_type, actor_auth_user_id, payload)
  values (p_hospital_id, 'shift', v_shift.id, 'registered', auth.uid(), jsonb_build_object('crew_member_id', v_crew.id, 'unit_id', p_unit_id));
  return jsonb_build_object('crew_member_id', v_crew.id, 'shift_id', v_shift.id);
end;
$$;

revoke all on function public.corvia_ws6_create_incident(uuid, text, text, boolean) from public, anon;
grant execute on function public.corvia_ws6_create_incident(uuid, text, text, boolean) to authenticated;
revoke all on function public.corvia_ws6_create_unit(uuid, text, text, text, text) from public, anon;
grant execute on function public.corvia_ws6_create_unit(uuid, text, text, text, text) to authenticated;
revoke all on function public.corvia_ws6_register_shift(uuid, uuid, text, text, text, text, text, uuid, timestamptz, timestamptz) from public, anon;
grant execute on function public.corvia_ws6_register_shift(uuid, uuid, text, text, text, text, text, uuid, timestamptz, timestamptz) to authenticated;

commit;
