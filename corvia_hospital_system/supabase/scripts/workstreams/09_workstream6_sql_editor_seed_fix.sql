-- Run this small fix once if 08_seed_workstream6_demo.sql was run in the
-- Supabase SQL Editor and returned "Hospital administrator access is required".
-- SQL Editor owner sessions do not have auth.uid(); normal app users still need
-- an active hospital_admins link. This does not grant table access to anon.

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

revoke all on function public.corvia_ws6_is_hospital_admin(uuid) from public, anon;
grant execute on function public.corvia_ws6_is_hospital_admin(uuid) to authenticated;

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
  values (p_hospital_id, 'CV-' || substr(replace(gen_random_uuid()::text, '-', ''), 1, 6), 'ambulance', 'idle', auth.uid())
  returning * into v_unit;

  insert into public.corvia_ws6_crew_members(hospital_id, auth_user_id, display_name, role, credential_status)
  values (p_hospital_id, v_demo_auth_user, coalesce(nullif(trim(p_display_name), ''), 'Demo Paramedic'), 'paramedic', 'verified')
  on conflict (hospital_id, auth_user_id) do update
    set display_name = excluded.display_name, credential_status = 'verified', active = true
  returning * into v_crew;

  insert into public.corvia_ws6_shifts(hospital_id, unit_id, crew_member_id, starts_at, ends_at, status)
  values (p_hospital_id, v_unit.id, v_crew.id, now() - interval '15 minutes', now() + interval '12 hours', 'active')
  returning * into v_shift;

  v_incident := public.corvia_ws6_create_incident(p_hospital_id, 'urgent', 'Synthetic WS6 test incident');
  return jsonb_build_object('unit_id', v_unit.id, 'crew_member_id', v_crew.id,
    'shift_id', v_shift.id, 'incident_id', v_incident.id, 'incident_number', v_incident.incident_number);
end;
$$;

revoke all on function public.corvia_ws6_create_demo_set(uuid, text) from public, anon;
grant execute on function public.corvia_ws6_create_demo_set(uuid, text) to authenticated;

-- After this query succeeds, run 08_seed_workstream6_demo.sql again.
