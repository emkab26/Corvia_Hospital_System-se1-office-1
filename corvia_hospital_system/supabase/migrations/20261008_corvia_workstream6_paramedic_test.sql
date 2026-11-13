-- Corvia Workstream 6: paramedic readiness and dispatch test contract.
-- This is an additive, namespaced contract. It deliberately does not alter the
-- legacy incidents/responders tables or claim to be the missing WS4 Fleet release.
-- It gives the team a safe synthetic workspace to test the WS6 Task 1 workflow.

begin;

create table if not exists public.corvia_ws6_units (
  id uuid primary key default gen_random_uuid(),
  hospital_id uuid not null references public.hospitals(id),
  call_sign text not null,
  unit_type text not null default 'ambulance',
  readiness_status text not null default 'idle'
    check (readiness_status in ('ready', 'idle', 'en_route', 'on_scene', 'transporting', 'maintenance', 'off_duty')),
  availability_revision bigint not null default 0,
  latitude numeric,
  longitude numeric,
  location_updated_at timestamptz,
  active boolean not null default true,
  notes text,
  created_by uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (hospital_id, call_sign)
);

create table if not exists public.corvia_ws6_crew_members (
  id uuid primary key default gen_random_uuid(),
  hospital_id uuid not null references public.hospitals(id),
  auth_user_id uuid not null,
  display_name text not null,
  role text not null default 'paramedic',
  credential_status text not null default 'pending'
    check (credential_status in ('pending', 'verified', 'expired', 'suspended')),
  credential_expires_at timestamptz,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  unique (hospital_id, auth_user_id)
);

create table if not exists public.corvia_ws6_shifts (
  id uuid primary key default gen_random_uuid(),
  hospital_id uuid not null references public.hospitals(id),
  unit_id uuid not null references public.corvia_ws6_units(id),
  crew_member_id uuid not null references public.corvia_ws6_crew_members(id),
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  status text not null default 'active'
    check (status in ('scheduled', 'active', 'ended', 'cancelled')),
  created_at timestamptz not null default now(),
  check (ends_at > starts_at)
);

create table if not exists public.corvia_ws6_incidents (
  id uuid primary key default gen_random_uuid(),
  hospital_id uuid not null references public.hospitals(id),
  incident_number text not null,
  priority text not null default 'routine'
    check (priority in ('routine', 'urgent', 'emergency', 'critical')),
  status text not null default 'pending'
    check (status in ('pending', 'accepted', 'dispatched', 'en_route', 'on_scene', 'transporting', 'at_hospital', 'resolved', 'cancelled')),
  summary text not null,
  synthetic boolean not null default true,
  created_by uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (hospital_id, incident_number)
);

create table if not exists public.corvia_ws6_assignments (
  id uuid primary key default gen_random_uuid(),
  hospital_id uuid not null references public.hospitals(id),
  incident_id uuid not null references public.corvia_ws6_incidents(id),
  unit_id uuid not null references public.corvia_ws6_units(id),
  status text not null default 'assigned'
    check (status in ('assigned', 'acknowledged', 'released', 'cancelled')),
  assigned_by uuid,
  assigned_at timestamptz not null default now(),
  acknowledged_at timestamptz,
  released_at timestamptz,
  expected_revision bigint not null,
  unique (incident_id, unit_id)
);

create table if not exists public.corvia_ws6_events (
  id uuid primary key default gen_random_uuid(),
  hospital_id uuid not null references public.hospitals(id),
  entity_type text not null,
  entity_id uuid not null,
  event_type text not null,
  actor_auth_user_id uuid,
  payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create unique index if not exists corvia_ws6_active_incident_assignment_idx
  on public.corvia_ws6_assignments (incident_id)
  where status in ('assigned', 'acknowledged');

create unique index if not exists corvia_ws6_active_unit_assignment_idx
  on public.corvia_ws6_assignments (unit_id)
  where status in ('assigned', 'acknowledged');

create index if not exists corvia_ws6_unit_lookup_idx
  on public.corvia_ws6_units (hospital_id, readiness_status, active);

create index if not exists corvia_ws6_incident_lookup_idx
  on public.corvia_ws6_incidents (hospital_id, status, created_at desc);

create or replace function public.corvia_ws6_is_hospital_admin(p_hospital_id uuid)
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select exists (
    select 1
    from public.hospital_admins ha
    where ha.hospital_id = p_hospital_id
      and (
        ha.profile_id = auth.uid()
        or ha.profile_id = (
          select p.id from public.profiles p where p.user_id = auth.uid() limit 1
        )
      )
  ) or session_user in ('postgres', 'service_role');
$$;

alter table public.corvia_ws6_units enable row level security;
alter table public.corvia_ws6_crew_members enable row level security;
alter table public.corvia_ws6_shifts enable row level security;
alter table public.corvia_ws6_incidents enable row level security;
alter table public.corvia_ws6_assignments enable row level security;
alter table public.corvia_ws6_events enable row level security;

drop policy if exists corvia_ws6_units_admin_read on public.corvia_ws6_units;
create policy corvia_ws6_units_admin_read on public.corvia_ws6_units
  for select to authenticated
  using (public.corvia_ws6_is_hospital_admin(hospital_id));

drop policy if exists corvia_ws6_crew_admin_read on public.corvia_ws6_crew_members;
create policy corvia_ws6_crew_admin_read on public.corvia_ws6_crew_members
  for select to authenticated
  using (public.corvia_ws6_is_hospital_admin(hospital_id));

drop policy if exists corvia_ws6_shifts_admin_read on public.corvia_ws6_shifts;
create policy corvia_ws6_shifts_admin_read on public.corvia_ws6_shifts
  for select to authenticated
  using (public.corvia_ws6_is_hospital_admin(hospital_id));

drop policy if exists corvia_ws6_incidents_admin_read on public.corvia_ws6_incidents;
create policy corvia_ws6_incidents_admin_read on public.corvia_ws6_incidents
  for select to authenticated
  using (public.corvia_ws6_is_hospital_admin(hospital_id));

drop policy if exists corvia_ws6_assignments_admin_read on public.corvia_ws6_assignments;
create policy corvia_ws6_assignments_admin_read on public.corvia_ws6_assignments
  for select to authenticated
  using (public.corvia_ws6_is_hospital_admin(hospital_id));

drop policy if exists corvia_ws6_events_admin_read on public.corvia_ws6_events;
create policy corvia_ws6_events_admin_read on public.corvia_ws6_events
  for select to authenticated
  using (public.corvia_ws6_is_hospital_admin(hospital_id));

revoke all on table public.corvia_ws6_units, public.corvia_ws6_crew_members,
  public.corvia_ws6_shifts, public.corvia_ws6_incidents,
  public.corvia_ws6_assignments, public.corvia_ws6_events from anon;
grant select on table public.corvia_ws6_units, public.corvia_ws6_crew_members,
  public.corvia_ws6_shifts, public.corvia_ws6_incidents,
  public.corvia_ws6_assignments, public.corvia_ws6_events to authenticated;

create or replace function public.corvia_ws6_create_incident(
  p_hospital_id uuid,
  p_priority text,
  p_summary text
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

  v_number := 'WS6-' || to_char(clock_timestamp(), 'YYYYMMDDHH24MISSMS') || '-' || substr(replace(gen_random_uuid()::text, '-', ''), 1, 6);
  insert into public.corvia_ws6_incidents(
    hospital_id, incident_number, priority, summary, created_by
  ) values (
    p_hospital_id, v_number, p_priority, trim(p_summary), auth.uid()
  ) returning * into v_incident;

  insert into public.corvia_ws6_events(hospital_id, entity_type, entity_id, event_type, actor_auth_user_id, payload)
  values (p_hospital_id, 'incident', v_incident.id, 'created', auth.uid(), jsonb_build_object('synthetic', true));
  return v_incident;
end;
$$;

create or replace function public.corvia_ws6_create_demo_set(
  p_hospital_id uuid,
  p_display_name text default 'Demo Paramedic'
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_unit public.corvia_ws6_units;
  v_crew public.corvia_ws6_crew_members;
  v_shift public.corvia_ws6_shifts;
  v_incident public.corvia_ws6_incidents;
  v_demo_auth_user uuid := coalesce(auth.uid(), gen_random_uuid());
begin
  if not public.corvia_ws6_is_hospital_admin(p_hospital_id) then
    raise exception 'Hospital administrator access is required';
  end if;

  insert into public.corvia_ws6_units(hospital_id, call_sign, unit_type, readiness_status, created_by)
  values (
    p_hospital_id,
    'CV-' || substr(replace(gen_random_uuid()::text, '-', ''), 1, 6),
    'ambulance', 'idle', auth.uid()
  ) returning * into v_unit;

  insert into public.corvia_ws6_crew_members(hospital_id, auth_user_id, display_name, role, credential_status)
  values (p_hospital_id, v_demo_auth_user, coalesce(nullif(trim(p_display_name), ''), 'Demo Paramedic'), 'paramedic', 'verified')
  on conflict (hospital_id, auth_user_id) do update
    set display_name = excluded.display_name,
        credential_status = 'verified',
        active = true
  returning * into v_crew;

  insert into public.corvia_ws6_shifts(hospital_id, unit_id, crew_member_id, starts_at, ends_at, status)
  values (p_hospital_id, v_unit.id, v_crew.id, now() - interval '15 minutes', now() + interval '12 hours', 'active')
  returning * into v_shift;

  v_incident := public.corvia_ws6_create_incident(p_hospital_id, 'urgent', 'Synthetic WS6 test incident');
  return jsonb_build_object(
    'unit_id', v_unit.id,
    'crew_member_id', v_crew.id,
    'shift_id', v_shift.id,
    'incident_id', v_incident.id,
    'incident_number', v_incident.incident_number
  );
end;
$$;

create or replace function public.corvia_ws6_assign_unit(
  p_hospital_id uuid,
  p_incident_id uuid,
  p_unit_id uuid,
  p_expected_revision bigint
) returns public.corvia_ws6_assignments
language plpgsql
security definer
set search_path = public
as $$
declare
  v_unit public.corvia_ws6_units;
  v_incident public.corvia_ws6_incidents;
  v_assignment public.corvia_ws6_assignments;
begin
  if not public.corvia_ws6_is_hospital_admin(p_hospital_id) then
    raise exception 'Hospital administrator access is required';
  end if;

  select * into v_unit from public.corvia_ws6_units
  where id = p_unit_id and hospital_id = p_hospital_id and active
  for update;
  if not found then raise exception 'Unit not found'; end if;
  if v_unit.availability_revision <> p_expected_revision then
    raise exception 'Unit availability changed; refresh before assigning';
  end if;
  if v_unit.readiness_status not in ('idle', 'ready') then
    raise exception 'Unit is not eligible for assignment';
  end if;
  if not exists (
    select 1 from public.corvia_ws6_shifts s
    join public.corvia_ws6_crew_members c on c.id = s.crew_member_id
    where s.hospital_id = p_hospital_id and s.unit_id = p_unit_id
      and s.status = 'active' and s.starts_at <= now() and s.ends_at > now()
      and c.active and c.credential_status = 'verified'
      and (c.credential_expires_at is null or c.credential_expires_at > now())
  ) then
    raise exception 'Unit has no active verified crew shift';
  end if;

  select * into v_incident from public.corvia_ws6_incidents
  where id = p_incident_id and hospital_id = p_hospital_id
  for update;
  if not found then raise exception 'Incident not found'; end if;
  if v_incident.status not in ('pending', 'accepted') then
    raise exception 'Incident is not assignable';
  end if;
  if exists (select 1 from public.corvia_ws6_assignments where incident_id = p_incident_id and status in ('assigned', 'acknowledged')) then
    raise exception 'Incident already has an active unit';
  end if;

  insert into public.corvia_ws6_assignments(hospital_id, incident_id, unit_id, assigned_by, expected_revision)
  values (p_hospital_id, p_incident_id, p_unit_id, auth.uid(), v_unit.availability_revision)
  returning * into v_assignment;

  update public.corvia_ws6_units
  set readiness_status = 'en_route', availability_revision = availability_revision + 1, updated_at = now()
  where id = p_unit_id;
  update public.corvia_ws6_incidents
  set status = 'dispatched', updated_at = now()
  where id = p_incident_id;
  insert into public.corvia_ws6_events(hospital_id, entity_type, entity_id, event_type, actor_auth_user_id, payload)
  values (p_hospital_id, 'assignment', v_assignment.id, 'assigned', auth.uid(), jsonb_build_object('unit_id', p_unit_id, 'incident_id', p_incident_id));
  return v_assignment;
end;
$$;

create or replace function public.corvia_ws6_set_unit_status(
  p_hospital_id uuid,
  p_unit_id uuid,
  p_new_status text,
  p_expected_revision bigint,
  p_reason text default null
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
  if p_new_status not in ('ready', 'idle', 'en_route', 'on_scene', 'transporting', 'maintenance', 'off_duty') then
    raise exception 'Invalid unit status';
  end if;
  select * into v_unit from public.corvia_ws6_units
  where id = p_unit_id and hospital_id = p_hospital_id for update;
  if not found then raise exception 'Unit not found'; end if;
  if v_unit.availability_revision <> p_expected_revision then
    raise exception 'Unit availability changed; refresh before updating';
  end if;
  if p_new_status in ('ready', 'idle') and exists (
    select 1 from public.corvia_ws6_assignments a where a.unit_id = p_unit_id and a.status in ('assigned', 'acknowledged')
  ) then
    raise exception 'An active assignment keeps this unit unavailable';
  end if;
  update public.corvia_ws6_units
  set readiness_status = p_new_status,
      notes = coalesce(nullif(trim(coalesce(p_reason, '')), ''), notes),
      availability_revision = availability_revision + 1,
      updated_at = now()
  where id = p_unit_id
  returning * into v_unit;
  insert into public.corvia_ws6_events(hospital_id, entity_type, entity_id, event_type, actor_auth_user_id, payload)
  values (p_hospital_id, 'unit', p_unit_id, 'status_changed', auth.uid(), jsonb_build_object('status', p_new_status, 'reason', p_reason));
  return v_unit;
end;
$$;

create or replace function public.corvia_ws6_status_lookup(p_hospital_id uuid)
returns jsonb
language sql
security definer
stable
set search_path = public
as $$
  select jsonb_build_object(
    'units', coalesce((select jsonb_agg(to_jsonb(u) order by u.call_sign) from public.corvia_ws6_units u where u.hospital_id = p_hospital_id and u.active), '[]'::jsonb),
    'incidents', coalesce((select jsonb_agg(to_jsonb(i) order by i.created_at desc) from public.corvia_ws6_incidents i where i.hospital_id = p_hospital_id and i.status not in ('resolved', 'cancelled')), '[]'::jsonb),
    'generated_at', now()
  )
  where public.corvia_ws6_is_hospital_admin(p_hospital_id);
$$;

revoke all on function public.corvia_ws6_is_hospital_admin(uuid) from public, anon;
grant execute on function public.corvia_ws6_is_hospital_admin(uuid) to authenticated;
revoke all on function public.corvia_ws6_create_incident(uuid, text, text) from public, anon;
grant execute on function public.corvia_ws6_create_incident(uuid, text, text) to authenticated;
revoke all on function public.corvia_ws6_create_demo_set(uuid, text) from public, anon;
grant execute on function public.corvia_ws6_create_demo_set(uuid, text) to authenticated;
revoke all on function public.corvia_ws6_assign_unit(uuid, uuid, uuid, bigint) from public, anon;
grant execute on function public.corvia_ws6_assign_unit(uuid, uuid, uuid, bigint) to authenticated;
revoke all on function public.corvia_ws6_set_unit_status(uuid, uuid, text, bigint, text) from public, anon;
grant execute on function public.corvia_ws6_set_unit_status(uuid, uuid, text, bigint, text) to authenticated;
revoke all on function public.corvia_ws6_status_lookup(uuid) from public, anon;
grant execute on function public.corvia_ws6_status_lookup(uuid) to authenticated;

commit;
