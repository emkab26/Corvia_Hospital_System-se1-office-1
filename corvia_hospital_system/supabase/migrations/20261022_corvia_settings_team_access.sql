-- Read-only Settings visibility for the optional WS4/team EMS bridge.
-- Safe before that optional module is installed: its shortcuts stay hidden.
-- Existing RPCs and permissions are unchanged.
begin;

create or replace function public.corvia_ws4_team_settings_access()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  actor uuid := auth.uid();
  backup_access boolean := false;
  receiving_access boolean := false;
begin
  if actor is null then
    raise exception 'Sign in to view workspace access' using errcode = '42501';
  end if;

  if exists(select 1 from public.profiles where user_id = actor and is_active) then
    -- Match the current, verified crew and shift required by backupOverview.
    -- No active offer is required: an authorised empty inbox is still usable.
    if to_regprocedure('public.corvia_ws4_backup_overview(bigint)') is not null
       and to_regprocedure('public.corvia_ems_member(uuid)') is not null then
      select exists(
        select 1 from public.corvia_ws6_crew_members_actual cm
        join public.corvia_ws6_crews c
          on c.crew_id = cm.crew_id and c.hospital_id = cm.hospital_id
        join public.corvia_ws6_shifts_actual sh
          on sh.shift_id = c.shift_id and sh.hospital_id = c.hospital_id
        join public.hospitals h on h.id = cm.hospital_id and h.is_active
        where cm.member_id = public.corvia_ems_member(cm.hospital_id)
          and cm.is_active and cm.left_datetime is null
          and c.crew_status = 'Active' and c.start_datetime <= now() and c.end_datetime > now()
          and sh.shift_status = 'Active' and sh.start_datetime <= now() and sh.end_datetime > now()
      ) into backup_access;
    end if;

    -- Receiving access is separately provisioned, including for clinical staff.
    if to_regprocedure('public.corvia_ws4_receiver_inbox()') is not null
       and to_regprocedure('ws4_private.receiver_allowed(uuid,bigint)') is not null then
      select exists(
        select 1 from ws4_private.ems_receivers r
        where r.user_id = actor
          and ws4_private.receiver_allowed(r.hospital_id, r.facility_id)
      ) into receiving_access;
    end if;
  end if;

  return jsonb_build_object('user_id', actor,
    'backup_responses', backup_access, 'receiving_handovers', receiving_access);
end;
$$;

revoke all on function public.corvia_ws4_team_settings_access() from public, anon;
grant execute on function public.corvia_ws4_team_settings_access() to authenticated;
notify pgrst, 'reload schema';
commit;
