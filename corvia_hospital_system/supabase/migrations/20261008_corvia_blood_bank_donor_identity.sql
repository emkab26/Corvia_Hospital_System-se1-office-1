-- Run after the blood-bank base, workspace and patient-search migrations.
-- Stores donor identity in a private table; stock views expose only a recorded flag.
begin;
set local lock_timeout = '10s';

alter table public.corvia_bb_units
  add column if not exists donor_identity_recorded boolean not null default false;

create table if not exists corvia_bb_private.donor_identities (
  hospital_id uuid not null references public.corvia_bb_settings(hospital_id),
  unit_id uuid not null references public.corvia_bb_units(id),
  operation_id uuid not null,
  donor_id_number text not null
    check (length(trim(donor_id_number)) between 6 and 40),
  recorded_by uuid not null references auth.users(id),
  recorded_at timestamptz not null default now(),
  primary key (hospital_id,unit_id),
  unique (recorded_by,operation_id)
);
revoke all on corvia_bb_private.donor_identities from public,anon,authenticated,service_role;
create trigger corvia_bb_donor_identity_immutable
  before update or delete on corvia_bb_private.donor_identities
  for each row execute function corvia_bb_private.immutable_event();
create trigger corvia_bb_donor_identity_no_truncate
  before truncate on corvia_bb_private.donor_identities
  for each statement execute function corvia_bb_private.immutable_event();

create function public.corvia_bb_receive_donor_unit(
  p_hospital_id uuid,p_operation_id uuid,p_payload jsonb
)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
  v_role text;
  v_donor_id text := trim(p_payload->>'donor_id_number');
  v_result jsonb;
  v_unit public.corvia_bb_units;
  v_existing corvia_bb_private.donor_identities;
begin
  v_role := corvia_bb_private.member_role(p_hospital_id);
  if coalesce(v_role,'') not in ('manager','technician') then
    raise exception 'Donor receipt denied' using errcode='42501';
  end if;
  if p_operation_id is null or p_payload->>'source' <> 'internal' then
    raise exception 'Donor identity is only accepted for internally collected units';
  end if;
  if v_donor_id is null or length(v_donor_id) not between 6 and 40
      or v_donor_id !~ '^[[:alnum:] -]+$' then
    raise exception 'Enter a valid donor ID number';
  end if;

  -- The existing command owns receipt validation, duplicate protection and replay.
  v_result := public.corvia_bb_command(
    p_hospital_id,p_operation_id,'receive',p_payload
  );
  select * into v_unit from public.corvia_bb_units
    where hospital_id=p_hospital_id and unit_number=trim(p_payload->>'unit_number')
    for update;
  if not found then raise exception 'Received unit could not be located'; end if;

  select * into v_existing from corvia_bb_private.donor_identities
    where hospital_id=p_hospital_id and unit_id=v_unit.id;
  if found then
    if v_existing.operation_id<>p_operation_id
        or v_existing.donor_id_number<>v_donor_id then
      raise exception 'Donor identity already recorded for this unit';
    end if;
  else
    insert into corvia_bb_private.donor_identities(
      hospital_id,unit_id,operation_id,donor_id_number,recorded_by
    ) values (
      p_hospital_id,v_unit.id,p_operation_id,v_donor_id,auth.uid()
    );
    insert into public.corvia_bb_movements(
      hospital_id,unit_id,action,actor_id,reason,after_record,evidence
    ) values (
      p_hospital_id,v_unit.id,'donor_identity_recorded',auth.uid(),
      trim(p_payload->>'reason'),
      jsonb_build_object('donor_identity_recorded',true),
      jsonb_build_object('kind','private_donor_identity','donor_id_present',true)
    );
  end if;
  update public.corvia_bb_units set donor_identity_recorded=true
    where hospital_id=p_hospital_id and id=v_unit.id;
  return jsonb_set(v_result,'{donor_identity_recorded}','true'::jsonb,true);
end $$;

revoke all on function public.corvia_bb_receive_donor_unit(uuid,uuid,jsonb)
  from public,anon,service_role;
grant execute on function public.corvia_bb_receive_donor_unit(uuid,uuid,jsonb)
  to authenticated;
notify pgrst,'reload schema';
commit;
