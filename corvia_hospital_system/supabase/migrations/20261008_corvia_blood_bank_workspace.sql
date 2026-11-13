-- Run AFTER 20261008_corvia_blood_bank.sql. Additive, one-time extension.
begin;
set local lock_timeout = '10s';

create function public.corvia_bb_patient_options(p_hospital_id uuid,p_search text)
returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
  if coalesce(corvia_bb_private.member_role(p_hospital_id),'') not in ('manager','clinician') then
    raise exception 'Patient search denied' using errcode='42501';
  end if;
  if p_search is null or length(trim(p_search))<2 then return '[]'::jsonb; end if;
  if length(p_search)>100 then raise exception 'Search too long'; end if;
  return (select coalesce(jsonb_agg(to_jsonb(r) order by r.patient_number,r.id),'[]'::jsonb) from (
    select p.id,p.patient_number,
      coalesce(nullif(trim(concat_ws(' ',p.first_name,p.surname)),''),'Unnamed patient') as patient_name
    from public.patients p
    where p.hospital_id=p_hospital_id and p.is_active is true
      and position(lower(trim(p_search)) in lower(concat_ws(' ',p.patient_number,p.first_name,p.surname)))>0
    order by p.patient_number,p.id limit 25
  ) r);
end $$;

create function public.corvia_bb_request_options(p_hospital_id uuid,p_unit_id uuid,p_search text default '')
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_unit public.corvia_bb_units;
begin
  if coalesce(corvia_bb_private.member_role(p_hospital_id),'') not in ('manager','technician') then
    raise exception 'Request search denied' using errcode='42501'; end if;
  if p_search is null or length(p_search)>100 then raise exception 'Invalid search'; end if;
  select * into v_unit from public.corvia_bb_units where hospital_id=p_hospital_id and id=p_unit_id;
  if not found then raise exception 'Unit not found'; end if;
  return (select coalesce(jsonb_agg(to_jsonb(r) order by r.required_at,r.id),'[]'::jsonb) from (select * from (
    select q.id,q.patient_id,p.patient_number,
      coalesce(nullif(trim(concat_ws(' ',p.first_name,p.surname)),''),'Unnamed patient') as patient_name,
      q.required_at,q.quantity,q.quantity - (
        select count(*) from public.corvia_bb_issues i where i.request_id=q.id
      ) - (
        select count(*) from public.corvia_bb_reservations rv
        where rv.request_id=q.id and rv.status='active' and rv.unit_id<>p_unit_id
      ) as remaining
    from public.corvia_bb_requests q join public.patients p on p.id=q.patient_id
    where q.hospital_id=p_hospital_id and q.status='approved' and q.product_id=v_unit.product_id
      and p.hospital_id=p_hospital_id and p.is_active is true
      and not exists (select 1 from public.corvia_bb_reservations rv
        where rv.unit_id=p_unit_id and rv.status='active' and rv.request_id<>q.id)
      and (p_search='' or position(lower(trim(p_search)) in lower(concat_ws(' ',q.id,p.patient_number,p.first_name,p.surname)))>0)
  ) candidates where remaining>0 order by required_at,id limit 25) r);
end $$;

create table corvia_bb_private.scan_events (
  id bigint generated always as identity primary key,
  hospital_id uuid not null references public.corvia_bb_settings(hospital_id),
  actor_id uuid not null references auth.users(id), operation_id uuid not null,
  raw_scan text not null check (length(raw_scan) between 1 and 500),
  unit_id uuid references public.corvia_bb_units(id),
  result text not null check (result in ('matched','not_found')),
  occurred_at timestamptz not null default now(),
  unique(actor_id,operation_id)
);
revoke all on corvia_bb_private.scan_events from public,anon,authenticated,service_role;
create trigger corvia_bb_scan_immutable before update or delete on corvia_bb_private.scan_events
for each row execute function corvia_bb_private.immutable_event();
create trigger corvia_bb_scan_no_truncate before truncate on corvia_bb_private.scan_events
for each statement execute function corvia_bb_private.immutable_event();

create function public.corvia_bb_lookup_scan(p_hospital_id uuid,p_operation_id uuid,p_raw_scan text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_scan text:=trim(p_raw_scan); v_unit public.corvia_bb_units;
  v_previous corvia_bb_private.scan_events; v_found boolean;
begin
  if corvia_bb_private.member_role(p_hospital_id) is null then
    raise exception 'Blood-bank access denied' using errcode='42501'; end if;
  if p_operation_id is null or v_scan is null or length(v_scan) not between 1 and 500 then
    raise exception 'Scan must contain 1 to 500 characters'; end if;
  perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text||p_operation_id::text,1));
  select * into v_previous from corvia_bb_private.scan_events
    where actor_id=auth.uid() and operation_id=p_operation_id;
  if found and (v_previous.hospital_id<>p_hospital_id or v_previous.raw_scan<>p_raw_scan) then
    raise exception 'Scan operation ID reused with different data'; end if;
  if v_scan ~* '^corvia:bb:unit:[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    select * into v_unit from public.corvia_bb_units
      where hospital_id=p_hospital_id and id=substring(v_scan from 16)::uuid;
  else
    -- Exact unit-number match. No guessed supplier/GS1 blood-group or expiry parsing.
    select * into v_unit from public.corvia_bb_units
      where hospital_id=p_hospital_id and unit_number=v_scan;
  end if;
  v_found:=found;
  insert into corvia_bb_private.scan_events(hospital_id,actor_id,operation_id,raw_scan,unit_id,result)
    values(p_hospital_id,auth.uid(),p_operation_id,p_raw_scan,
      case when v_found then v_unit.id end,case when v_found then 'matched' else 'not_found' end)
    on conflict(actor_id,operation_id) do nothing;
  if not v_found then return jsonb_build_object('status','not_found'); end if;
  return jsonb_build_object('status','matched','unit_id',v_unit.id,'unit_number',v_unit.unit_number);
end $$;

create function public.corvia_bb_prepare_label(p_hospital_id uuid,p_operation_id uuid,
  p_unit_id uuid,p_version integer,p_reason text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_unit public.corvia_bb_units; v_payload jsonb; v_result jsonb;
  v_previous corvia_bb_private.commands;
begin
  perform 1 from public.corvia_bb_settings where hospital_id=p_hospital_id for update;
  perform 1 from public.corvia_bb_memberships where hospital_id=p_hospital_id and user_id=auth.uid() for share;
  perform 1 from public.profiles where user_id=auth.uid() for share;
  perform 1 from public.hospitals where id=p_hospital_id for share;
  if coalesce(corvia_bb_private.member_role(p_hospital_id),'') not in ('manager','technician') then
    raise exception 'Label preparation denied' using errcode='42501'; end if;
  if p_operation_id is null or p_reason is null or length(trim(p_reason)) not between 1 and 1000 then
    raise exception 'Operation ID and print/reprint reason required'; end if;
  select * into v_unit from public.corvia_bb_units
    where hospital_id=p_hospital_id and id=p_unit_id for update;
  if not found then raise exception 'Unit not found'; end if;
  if p_version is distinct from v_unit.version then
    raise exception 'Stock changed. Refresh before printing' using errcode='40001'; end if;
  v_payload:=jsonb_build_object('unit_id',p_unit_id,'version',p_version,'reason',p_reason);
  perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text||p_operation_id::text,0));
  select * into v_previous from corvia_bb_private.commands
    where actor_id=auth.uid() and operation_id=p_operation_id;
  if found then
    if v_previous.hospital_id<>p_hospital_id or v_previous.action<>'prepare_label'
      or v_previous.payload<>v_payload then raise exception 'Operation ID reused with different data'; end if;
    return v_previous.result;
  end if;
  select to_jsonb(v_unit)||jsonb_build_object('hospital_name',h.name,'product_name',p.name,
    'location_name',l.name,'generated_at',now(),'qr_value','corvia:bb:unit:'||v_unit.id,
    'label_number',1+(select count(*) from public.corvia_bb_movements
      where unit_id=v_unit.id and action='label_prepared')) into v_result
  from public.hospitals h,public.corvia_bb_products p,public.corvia_bb_locations l
  where h.id=p_hospital_id and p.id=v_unit.product_id and l.id=v_unit.location_id;
  insert into public.corvia_bb_movements(hospital_id,unit_id,action,actor_id,reason,after_record,evidence)
    values(p_hospital_id,p_unit_id,'label_prepared',auth.uid(),trim(p_reason),to_jsonb(v_unit),
      jsonb_build_object('label_number',v_result->'label_number','kind','supplemental_inventory_reference',
        'physical_print_confirmed',false));
  insert into corvia_bb_private.commands(actor_id,operation_id,hospital_id,action,payload,result)
    values(auth.uid(),p_operation_id,p_hospital_id,'prepare_label',v_payload,v_result);
  return v_result;
end $$;

revoke all on function public.corvia_bb_patient_options(uuid,text) from public,anon,service_role;
revoke all on function public.corvia_bb_request_options(uuid,uuid,text) from public,anon,service_role;
revoke all on function public.corvia_bb_lookup_scan(uuid,uuid,text) from public,anon,service_role;
revoke all on function public.corvia_bb_prepare_label(uuid,uuid,uuid,integer,text) from public,anon,service_role;
grant execute on function public.corvia_bb_patient_options(uuid,text) to authenticated;
grant execute on function public.corvia_bb_request_options(uuid,uuid,text) to authenticated;
grant execute on function public.corvia_bb_lookup_scan(uuid,uuid,text) to authenticated;
grant execute on function public.corvia_bb_prepare_label(uuid,uuid,uuid,integer,text) to authenticated;
notify pgrst,'reload schema';
commit;
