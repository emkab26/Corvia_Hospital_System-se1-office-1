-- Blood-bank foundation. Run ONCE, as database owner, after 00_preflight.sql.
-- Additive: does not replace existing Auth, hospital, patient or dispatch objects.
-- Exact reruns and name collisions fail atomically instead of masking schema drift.
begin;
set local lock_timeout = '10s';

do $$
begin
  if not exists (select 1 from information_schema.columns where table_schema='public'
    and table_name='profiles' and column_name='user_id' and udt_name='uuid')
    or not exists (select 1 from information_schema.columns where table_schema='public'
    and table_name='patients' and column_name='hospital_id' and udt_name='uuid') then
    raise exception 'Unexpected Corvia baseline. Run and review 00_preflight.sql.';
  end if;
end $$;

create schema corvia_bb_private;
revoke all on schema corvia_bb_private from public, anon, authenticated, service_role;

create table public.corvia_bb_settings (
  hospital_id uuid primary key references public.hospitals(id),
  operating_mode text not null check (operating_mode in ('receiver','collector','hybrid')),
  clinical_issue_enabled boolean not null default false,
  clinical_authority_reference text,
  check (not clinical_issue_enabled or length(trim(clinical_authority_reference)) > 0
    and clinical_authority_reference is not null)
);
-- Assigned only by the database owner. Existing profile labels grant no access.
create table public.corvia_bb_memberships (
  hospital_id uuid not null references public.corvia_bb_settings(hospital_id),
  user_id uuid not null references auth.users(id),
  role text not null check (role in ('manager','technician','clinician','ward')),
  active boolean not null default true,
  granted_at timestamptz not null default now(),
  granted_by uuid not null references auth.users(id),
  reason text not null check (length(trim(reason)) > 0),
  primary key (hospital_id,user_id)
);
create table public.corvia_bb_products (
  id uuid primary key default gen_random_uuid(),
  hospital_id uuid not null references public.corvia_bb_settings(hospital_id),
  name text not null check (length(trim(name)) > 0),
  component text not null check (length(trim(component)) > 0),
  active boolean not null default true,
  unique (hospital_id,id), unique (hospital_id,name)
);
create table public.corvia_bb_locations (
  id uuid primary key default gen_random_uuid(),
  hospital_id uuid not null references public.corvia_bb_settings(hospital_id),
  name text not null check (length(trim(name)) > 0),
  location_type text not null check (location_type in
    ('fridge','freezer','platelet','quarantine','disposal','transit','other')),
  active boolean not null default true,
  unique (hospital_id,id), unique (hospital_id,name)
);
create table public.corvia_bb_units (
  id uuid primary key default gen_random_uuid(),
  hospital_id uuid not null references public.corvia_bb_settings(hospital_id),
  unit_number text not null check (length(trim(unit_number)) between 1 and 100),
  product_id uuid not null,
  location_id uuid not null,
  source text not null check (source in ('internal','external')),
  supplier text, lot_number text, donation_reference text, collected_at timestamptz,
  abo text not null check (abo in ('A','B','AB','O')),
  rhd text not null check (rhd in ('positive','negative')),
  group_source_reference text not null check (length(trim(group_source_reference)) > 0),
  expires_at timestamptz not null,
  status text not null default 'available' check (status in
    ('available','reserved','issued','quarantined','recalled','disposed')),
  cold_chain_broken boolean not null default false,
  recalled boolean not null default false,
  version integer not null default 1,
  received_by uuid not null references auth.users(id),
  received_at timestamptz not null default now(),
  unique (hospital_id,id), unique (hospital_id,unit_number),
  foreign key (hospital_id,product_id) references public.corvia_bb_products(hospital_id,id),
  foreign key (hospital_id,location_id) references public.corvia_bb_locations(hospital_id,id),
  check (source <> 'external' or (supplier is not null and length(trim(supplier)) > 0
    and lot_number is not null and length(trim(lot_number)) > 0)),
  check (source <> 'internal' or (donation_reference is not null
    and length(trim(donation_reference)) > 0 and collected_at is not null)),
  check (collected_at is null or expires_at > collected_at)
);
create table public.corvia_bb_requests (
  id uuid primary key default gen_random_uuid(),
  hospital_id uuid not null references public.corvia_bb_settings(hospital_id),
  patient_id uuid not null references public.patients(id),
  product_id uuid not null,
  quantity integer not null check (quantity between 1 and 100),
  required_at timestamptz not null,
  status text not null default 'pending' check (status in ('pending','approved','cancelled')),
  requested_by uuid not null references auth.users(id),
  requested_at timestamptz not null default now(),
  approved_by uuid references auth.users(id), approved_at timestamptz,
  approval_reference text,
  unique (hospital_id,id),
  foreign key (hospital_id,product_id) references public.corvia_bb_products(hospital_id,id)
);
create table public.corvia_bb_reservations (
  id uuid primary key default gen_random_uuid(), hospital_id uuid not null,
  unit_id uuid not null, request_id uuid not null,
  status text not null check (status in ('active','issued','cancelled')),
  created_by uuid not null references auth.users(id), created_at timestamptz not null default now(),
  foreign key (hospital_id,unit_id) references public.corvia_bb_units(hospital_id,id),
  foreign key (hospital_id,request_id) references public.corvia_bb_requests(hospital_id,id)
);
create unique index corvia_bb_one_reservation on public.corvia_bb_reservations(unit_id)
  where status='active';
create table public.corvia_bb_issues (
  id uuid primary key default gen_random_uuid(), hospital_id uuid not null,
  unit_id uuid not null, request_id uuid not null,
  issued_by uuid not null references auth.users(id), issued_at timestamptz not null default now(),
  compatibility_reference text not null check (length(trim(compatibility_reference)) > 0),
  recipient text not null check (length(trim(recipient)) > 0),
  returned_at timestamptz,
  foreign key (hospital_id,unit_id) references public.corvia_bb_units(hospital_id,id),
  foreign key (hospital_id,request_id) references public.corvia_bb_requests(hospital_id,id)
);
create unique index corvia_bb_one_open_issue on public.corvia_bb_issues(unit_id)
  where returned_at is null;
create table public.corvia_bb_movements (
  id bigint generated always as identity primary key,
  hospital_id uuid not null references public.corvia_bb_settings(hospital_id),
  unit_id uuid, request_id uuid,
  action text not null, actor_id uuid not null references auth.users(id),
  occurred_at timestamptz not null default now(), reason text not null,
  before_record jsonb, after_record jsonb,
  evidence jsonb not null default '{}'::jsonb,
  foreign key (hospital_id,unit_id) references public.corvia_bb_units(hospital_id,id),
  foreign key (hospital_id,request_id) references public.corvia_bb_requests(hospital_id,id)
);
create index corvia_bb_movement_lookup on public.corvia_bb_movements(hospital_id,unit_id,id desc);
create index corvia_bb_stock_expiry on public.corvia_bb_units(hospital_id,expires_at,id);
create table corvia_bb_private.commands (
  actor_id uuid not null references auth.users(id), operation_id uuid not null,
  hospital_id uuid not null, action text not null, payload jsonb not null,
  result jsonb not null, created_at timestamptz not null default now(),
  primary key (actor_id,operation_id)
);

create function corvia_bb_private.immutable_event() returns trigger
language plpgsql set search_path = '' as $$
begin raise exception 'Blood-bank audit events are immutable'; end $$;
create trigger corvia_bb_immutable before update or delete on public.corvia_bb_movements
  for each row execute function corvia_bb_private.immutable_event();
create trigger corvia_bb_no_truncate before truncate on public.corvia_bb_movements
  for each statement execute function corvia_bb_private.immutable_event();

-- Administrative changes are also recorded, including owner provisioning.
-- No Auth identity is fabricated for SQL-editor sessions.
create table corvia_bb_private.configuration_events (
  id bigint generated always as identity primary key,
  table_name text not null, action text not null,
  actor_id uuid, database_session text not null,
  occurred_at timestamptz not null default now(),
  before_record jsonb, after_record jsonb
);
create function corvia_bb_private.configuration_audit() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  insert into corvia_bb_private.configuration_events(table_name,action,actor_id,database_session,before_record,after_record)
    values(tg_table_name,tg_op,auth.uid(),session_user,
      case when tg_op<>'INSERT' then to_jsonb(old) end,
      case when tg_op<>'DELETE' then to_jsonb(new) end);
  return null;
end $$;
do $$
declare t text;
begin
  foreach t in array array['settings','memberships','products','locations'] loop
    execute format('create trigger corvia_bb_config_audit after insert or update or delete on public.corvia_bb_%I for each row execute function corvia_bb_private.configuration_audit()',t);
  end loop;
end $$;
create trigger corvia_bb_config_immutable before update or delete on corvia_bb_private.configuration_events
  for each row execute function corvia_bb_private.immutable_event();
create trigger corvia_bb_config_no_truncate before truncate on corvia_bb_private.configuration_events
  for each statement execute function corvia_bb_private.immutable_event();

create function corvia_bb_private.member_role(p_hospital uuid) returns text
language sql stable security definer set search_path = '' as $$
  select m.role from public.corvia_bb_memberships m
  join public.profiles p on p.user_id=m.user_id and p.is_active is true
  join public.hospitals h on h.id=m.hospital_id and h.is_active is true
  where m.hospital_id=p_hospital and m.user_id=auth.uid() and m.active;
$$;

-- RLS is defense in depth; Flutter uses only the limited RPCs below.
do $$
declare t text;
begin
  foreach t in array array['settings','memberships','products','locations','units',
    'requests','reservations','issues','movements'] loop
    execute format('alter table public.corvia_bb_%I enable row level security',t);
    execute format('revoke all on public.corvia_bb_%I from public,anon,authenticated,service_role',t);
  end loop;
end $$;
revoke all on all tables in schema corvia_bb_private from public,anon,authenticated,service_role;
revoke all on sequence public.corvia_bb_movements_id_seq from public,anon,authenticated,service_role;

create function public.corvia_bb_access() returns jsonb
language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object('hospital_id',h.id,'hospital_name',h.name,
    'role',m.role) order by h.name),'[]'::jsonb)
  from public.corvia_bb_memberships m join public.hospitals h on h.id=m.hospital_id
  where m.user_id=auth.uid() and corvia_bb_private.member_role(h.id) is not null;
$$;

create function public.corvia_bb_dashboard(p_hospital_id uuid,
  p_search text default '', p_status text default '', p_offset integer default 0)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare result jsonb; v_role text; v_now timestamptz := now();
begin
  v_role := corvia_bb_private.member_role(p_hospital_id);
  if v_role is null then raise exception 'Blood-bank access denied' using errcode='42501'; end if;
  if p_offset is null or p_offset < 0 or length(p_search)>100 then
    raise exception 'Invalid page or search'; end if;
  select jsonb_build_object(
    'role',v_role,'server_time',v_now,
    'settings',(select to_jsonb(s) from public.corvia_bb_settings s where hospital_id=p_hospital_id),
    'products',(select coalesce(jsonb_agg(to_jsonb(p) order by name),'[]'::jsonb)
      from public.corvia_bb_products p where hospital_id=p_hospital_id and active),
    'locations',(select coalesce(jsonb_agg(to_jsonb(l) order by name),'[]'::jsonb)
      from public.corvia_bb_locations l where hospital_id=p_hospital_id and active),
    'units',(select coalesce(jsonb_agg(to_jsonb(u) order by expires_at,id),'[]'::jsonb) from (
      select u.*, p.name as product_name, l.name as location_name,
        u.expires_at<=v_now as expired,
        (u.expires_at>v_now and u.expires_at<=v_now+interval '24 hours') as expires_within_24h
      from public.corvia_bb_units u
      join public.corvia_bb_products p on p.id=u.product_id
      join public.corvia_bb_locations l on l.id=u.location_id
      where u.hospital_id=p_hospital_id
        and (p_status='' or u.status=p_status)
        and (p_search='' or position(lower(p_search) in lower(concat_ws(' ',
          u.unit_number,u.lot_number,u.donation_reference)))>0)
      order by u.expires_at,u.id limit 50 offset p_offset
    ) u),
    'matching_count',(select count(*) from public.corvia_bb_units u where hospital_id=p_hospital_id
      and (p_status='' or status=p_status)
      and (p_search='' or position(lower(p_search) in lower(concat_ws(' ',
        unit_number,lot_number,donation_reference)))>0)),
    'counts',(select jsonb_build_object('total',count(*),
      'available',count(*) filter (where status='available' and expires_at>v_now
        and not cold_chain_broken and not recalled),
      'expired',count(*) filter (where expires_at<=v_now and status<>'disposed'),
      'held',count(*) filter (where status in ('quarantined','recalled')))
      from public.corvia_bb_units where hospital_id=p_hospital_id)
  ) into result;
  return result;
end $$;

create function public.corvia_bb_history(p_hospital_id uuid,p_unit_id uuid,
  p_offset integer default 0) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  if corvia_bb_private.member_role(p_hospital_id) is null then
    raise exception 'Blood-bank access denied' using errcode='42501'; end if;
  if p_offset is null or p_offset<0 then raise exception 'Invalid page'; end if;
  return (select coalesce(jsonb_agg(to_jsonb(e) order by e.occurred_at desc,e.event_id desc),'[]'::jsonb)
    from (select id::text as event_id,action,actor_id,occurred_at,reason,before_record,after_record,evidence
      from public.corvia_bb_movements where hospital_id=p_hospital_id and unit_id=p_unit_id
      order by id desc limit 50 offset p_offset) e);
end $$;

create function public.corvia_bb_requests_list(p_hospital_id uuid,p_offset integer default 0)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  if corvia_bb_private.member_role(p_hospital_id) is null then
    raise exception 'Blood-bank access denied' using errcode='42501'; end if;
  if p_offset is null or p_offset<0 then raise exception 'Invalid page'; end if;
  return (select coalesce(jsonb_agg(to_jsonb(r) order by requested_at desc,id),'[]'::jsonb)
    from (select r.*,p.name as product_name,
      (select count(*) from public.corvia_bb_issues i where i.request_id=r.id) as issued_count
      from public.corvia_bb_requests r join public.corvia_bb_products p on p.id=r.product_id
      where r.hospital_id=p_hospital_id order by requested_at desc,id limit 50 offset p_offset) r);
end $$;

-- All writes are atomic, hospital-scoped, authenticated and idempotent.
-- Serialising writes per hospital also protects request quantities across units.
create function public.corvia_bb_command(p_hospital_id uuid,p_operation_id uuid,
  p_action text,p_payload jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_actor uuid := auth.uid(); v_role text; v_reason text := trim(p_payload->>'reason');
  v_settings public.corvia_bb_settings; v_unit public.corvia_bb_units;
  v_request public.corvia_bb_requests; v_location public.corvia_bb_locations;
  v_old jsonb; v_result jsonb; v_previous corvia_bb_private.commands;
  v_request_id uuid; v_unit_id uuid; v_count integer;
begin
  if v_actor is null or p_operation_id is null or p_action is null
    or p_payload is null or jsonb_typeof(p_payload)<>'object' then
    raise exception 'Authenticated actor, operation ID, action and object payload required'; end if;
  if octet_length(p_payload::text)>16000 then raise exception 'Payload too large'; end if;
  select * into v_settings from public.corvia_bb_settings
    where hospital_id=p_hospital_id for update;
  v_role := corvia_bb_private.member_role(p_hospital_id);
  if not found or v_role is null then
    raise exception 'Blood-bank access denied' using errcode='42501'; end if;
  perform 1 from public.corvia_bb_memberships where hospital_id=p_hospital_id
    and user_id=v_actor for share;
  perform 1 from public.profiles where user_id=v_actor for share;
  perform 1 from public.hospitals where id=p_hospital_id for share;
  -- Recheck after locking, in case a revocation committed while waiting.
  v_role := corvia_bb_private.member_role(p_hospital_id);
  if v_role is null then raise exception 'Blood-bank access denied' using errcode='42501'; end if;
  -- Same actor/key across hospitals must also serialize and reject changed payloads.
  perform pg_advisory_xact_lock(hashtextextended(v_actor::text||p_operation_id::text,0));
  select * into v_previous from corvia_bb_private.commands
    where actor_id=v_actor and operation_id=p_operation_id;
  if found then
    if v_previous.hospital_id<>p_hospital_id or v_previous.action<>p_action
      or v_previous.payload<>p_payload then raise exception 'Operation ID reused with different data'; end if;
    return v_previous.result;
  end if;
  if v_reason is null or length(v_reason)=0 or length(v_reason)>1000 then
    raise exception 'A reason of 1 to 1000 characters is required'; end if;
  if p_action in ('request','approve_request','cancel_request') then
    if p_action='request' then
      if v_role not in ('manager','clinician') then raise exception 'Requesting clinician access required' using errcode='42501'; end if;
      perform 1 from public.patients where id=(p_payload->>'patient_id')::uuid
        and hospital_id=p_hospital_id and is_active is true for share;
      if not found then raise exception 'Patient is not active in this hospital'; end if;
      perform 1 from public.corvia_bb_products where id=(p_payload->>'product_id')::uuid
        and hospital_id=p_hospital_id and active for share;
      if not found then raise exception 'Active hospital product required'; end if;
      insert into public.corvia_bb_requests(hospital_id,patient_id,product_id,quantity,required_at,requested_by)
      values(p_hospital_id,(p_payload->>'patient_id')::uuid,(p_payload->>'product_id')::uuid,
        (p_payload->>'quantity')::integer,(p_payload->>'required_at')::timestamptz,v_actor)
      returning * into v_request;
    else
      select * into v_request from public.corvia_bb_requests where hospital_id=p_hospital_id
        and id=(p_payload->>'request_id')::uuid for update;
      if not found then raise exception 'Request not found'; end if;
      v_old := to_jsonb(v_request);
      if p_action='approve_request' then
        if v_role<>'manager' then raise exception 'Manager access required' using errcode='42501'; end if;
        if not v_settings.clinical_issue_enabled then raise exception 'Clinical issue is not configured for this hospital'; end if;
        if v_request.status<>'pending' then raise exception 'Only pending requests can be approved'; end if;
        if coalesce(length(trim(p_payload->>'approval_reference')),0)=0 then
          raise exception 'External clinical approval reference required'; end if;
        update public.corvia_bb_requests set status='approved',approved_by=v_actor,approved_at=now(),
          approval_reference=trim(p_payload->>'approval_reference') where id=v_request.id returning * into v_request;
      else
        if v_role<>'manager' and not(v_role='clinician' and v_request.requested_by=v_actor) then
          raise exception 'Request cancellation denied' using errcode='42501'; end if;
        if exists(select 1 from public.corvia_bb_issues where request_id=v_request.id) then
          raise exception 'Issued requests cannot be cancelled'; end if;
        if exists(select 1 from public.corvia_bb_reservations where request_id=v_request.id and status='active') then
          raise exception 'Cancel unit reservations first'; end if;
        update public.corvia_bb_requests set status='cancelled' where id=v_request.id returning * into v_request;
      end if;
    end if;
    v_request_id := v_request.id;
    v_result := to_jsonb(v_request);
  else
    if v_role not in ('manager','technician') and not(v_role='ward' and p_action='return') then
      raise exception 'Stock operation denied' using errcode='42501'; end if;
    if p_action='receive' then
      if (v_settings.operating_mode='receiver' and p_payload->>'source'<>'external')
        or (v_settings.operating_mode='collector' and p_payload->>'source'<>'internal') then
        raise exception 'Source does not match hospital operating mode'; end if;
      select * into v_location from public.corvia_bb_locations where hospital_id=p_hospital_id
        and id=(p_payload->>'location_id')::uuid and active for share;
      if not found or v_location.location_type in ('quarantine','disposal','transit') then
        raise exception 'Active stock storage location required'; end if;
      perform 1 from public.corvia_bb_products where hospital_id=p_hospital_id
        and id=(p_payload->>'product_id')::uuid and active for share;
      if not found then raise exception 'Active hospital product required'; end if;
      if (p_payload->>'expires_at')::timestamptz<=now() then raise exception 'Cannot receive expired stock as available'; end if;
      if (p_payload->>'collected_at')::timestamptz>now() then raise exception 'Collection cannot be in the future'; end if;
      insert into public.corvia_bb_units(hospital_id,unit_number,product_id,location_id,source,
        supplier,lot_number,donation_reference,collected_at,abo,rhd,group_source_reference,expires_at,received_by)
      values(p_hospital_id,trim(p_payload->>'unit_number'),(p_payload->>'product_id')::uuid,
        v_location.id,p_payload->>'source',nullif(trim(p_payload->>'supplier'),''),
        nullif(trim(p_payload->>'lot_number'),''),nullif(trim(p_payload->>'donation_reference'),''),
        (p_payload->>'collected_at')::timestamptz,p_payload->>'abo',p_payload->>'rhd',
        trim(p_payload->>'group_source_reference'),(p_payload->>'expires_at')::timestamptz,v_actor)
      returning * into v_unit;
    else
      select * into v_unit from public.corvia_bb_units where hospital_id=p_hospital_id
        and id=(p_payload->>'unit_id')::uuid for update;
      if not found then raise exception 'Unit not found'; end if;
      v_old := to_jsonb(v_unit);
      if (p_payload->>'version')::integer is distinct from v_unit.version then
        raise exception 'Stock changed. Refresh before retrying this action' using errcode='40001'; end if;
      if v_unit.status='disposed' then raise exception 'Disposed stock cannot be changed'; end if;
      if p_action in ('reserve','issue') then
        if not v_settings.clinical_issue_enabled then raise exception 'Clinical issue is not configured for this hospital'; end if;
        if v_unit.expires_at<=now() or v_unit.recalled or v_unit.cold_chain_broken
          or v_unit.status not in ('available','reserved') then raise exception 'Unit is not issuable'; end if;
        perform 1 from public.corvia_bb_locations where id=v_unit.location_id and active
          and location_type not in ('quarantine','disposal','transit') for share;
        if not found then raise exception 'Storage location is not issuable'; end if;
        perform 1 from public.corvia_bb_products where id=v_unit.product_id and active for share;
        if not found then raise exception 'Product is inactive'; end if;
        select * into v_request from public.corvia_bb_requests where hospital_id=p_hospital_id
          and id=(p_payload->>'request_id')::uuid for update;
        if not found or v_request.status<>'approved' or v_request.product_id<>v_unit.product_id then
          raise exception 'Approved request for this hospital and product required'; end if;
        perform 1 from public.patients where id=v_request.patient_id and hospital_id=p_hospital_id
          and is_active is true for share;
        if not found then raise exception 'Patient is no longer active in this hospital'; end if;
        v_request_id := v_request.id;
        if exists(select 1 from public.corvia_bb_reservations where unit_id=v_unit.id
          and status='active' and request_id<>v_request.id) then raise exception 'Unit reserved for another request'; end if;
        select (select count(*) from public.corvia_bb_issues where request_id=v_request.id)
          + (select count(*) from public.corvia_bb_reservations where request_id=v_request.id
             and status='active' and unit_id<>v_unit.id) into v_count;
        if v_count>=v_request.quantity then raise exception 'Requested quantity already allocated'; end if;
        if p_action='reserve' then
          if v_unit.status<>'available' then raise exception 'Only available units can be reserved'; end if;
          insert into public.corvia_bb_reservations(hospital_id,unit_id,request_id,status,created_by)
            values(p_hospital_id,v_unit.id,v_request.id,'active',v_actor);
          v_unit.status := 'reserved';
        else
          if coalesce(length(trim(p_payload->>'compatibility_reference')),0)=0
            or coalesce(length(trim(p_payload->>'recipient')),0)=0 then
            raise exception 'External compatibility evidence and receiving person required'; end if;
          insert into public.corvia_bb_issues(hospital_id,unit_id,request_id,issued_by,compatibility_reference,recipient)
            values(p_hospital_id,v_unit.id,v_request.id,v_actor,trim(p_payload->>'compatibility_reference'),trim(p_payload->>'recipient'));
          update public.corvia_bb_reservations set status='issued' where unit_id=v_unit.id and status='active';
          v_unit.status := 'issued';
        end if;
      elsif p_action='cancel_reservation' then
        if v_unit.status<>'reserved' then raise exception 'Unit is not reserved'; end if;
        update public.corvia_bb_reservations set status='cancelled' where unit_id=v_unit.id and status='active';
        v_unit.status := 'available';
      elsif p_action='transfer' then
        if v_unit.status not in ('available','reserved') then raise exception 'Only stock in storage can be transferred'; end if;
      elsif p_action in ('quarantine','recall','dispose','return') then
        if p_action in ('recall','dispose') and v_role<>'manager' then
          raise exception 'Manager access required' using errcode='42501'; end if;
        if p_action='return' then
          if not exists(select 1 from public.corvia_bb_issues where unit_id=v_unit.id and returned_at is null) then
            raise exception 'No outstanding issue to return'; end if;
          if coalesce(length(trim(p_payload->>'condition')),0)=0 then raise exception 'Return condition required'; end if;
          update public.corvia_bb_issues set returned_at=now() where unit_id=v_unit.id and returned_at is null;
          v_unit.status := case when v_unit.recalled then 'recalled' else 'quarantined' end;
        elsif p_action='recall' then
          v_unit.recalled := true; v_unit.status := 'recalled';
        else
          if exists(select 1 from public.corvia_bb_issues where unit_id=v_unit.id and returned_at is null) then
            raise exception 'Return issued stock before quarantine or disposal'; end if;
          v_unit.status := case when p_action='dispose' then 'disposed' else 'quarantined' end;
        end if;
        update public.corvia_bb_reservations set status='cancelled' where unit_id=v_unit.id and status='active';
      else raise exception 'Unknown blood-bank action';
      end if;
      if p_action in ('transfer','return','quarantine','dispose') then
        select * into v_location from public.corvia_bb_locations where hospital_id=p_hospital_id
          and id=(p_payload->>'location_id')::uuid and active for share;
        if not found then raise exception 'Active hospital location required'; end if;
        if p_action='transfer' and v_location.location_type in ('quarantine','disposal','transit') then
          raise exception 'Use a controlled quarantine or disposal action'; end if;
        if p_action in ('quarantine','return') and v_location.location_type<>'quarantine' then
          raise exception 'Quarantine location required'; end if;
        if p_action='dispose' and v_location.location_type<>'disposal' then raise exception 'Disposal location required'; end if;
        v_unit.location_id := v_location.id;
      end if;
      if coalesce((p_payload->>'cold_chain_broken')::boolean,false) then
        if p_action not in ('quarantine','return','dispose','recall') then raise exception 'Cold-chain breaks require stock to be held'; end if;
        v_unit.cold_chain_broken := true;
      end if;
      update public.corvia_bb_units set status=v_unit.status,location_id=v_unit.location_id,
        recalled=v_unit.recalled,cold_chain_broken=v_unit.cold_chain_broken,version=version+1
        where id=v_unit.id returning * into v_unit;
    end if;
    v_unit_id := v_unit.id; v_result := to_jsonb(v_unit);
  end if;
  insert into public.corvia_bb_movements(hospital_id,unit_id,request_id,action,actor_id,reason,before_record,after_record,evidence)
    values(p_hospital_id,v_unit_id,v_request_id,p_action,v_actor,v_reason,v_old,v_result,
      p_payload - array['reason','patient_id']);
  insert into corvia_bb_private.commands(actor_id,operation_id,hospital_id,action,payload,result)
    values(v_actor,p_operation_id,p_hospital_id,p_action,p_payload,v_result);
  return v_result;
end $$;

revoke all on all functions in schema corvia_bb_private from public,anon,authenticated,service_role;
revoke all on function public.corvia_bb_access() from public,anon,service_role;
revoke all on function public.corvia_bb_dashboard(uuid,text,text,integer) from public,anon,service_role;
revoke all on function public.corvia_bb_history(uuid,uuid,integer) from public,anon,service_role;
revoke all on function public.corvia_bb_requests_list(uuid,integer) from public,anon,service_role;
revoke all on function public.corvia_bb_command(uuid,uuid,text,jsonb) from public,anon,service_role;
grant execute on function public.corvia_bb_access() to authenticated;
grant execute on function public.corvia_bb_dashboard(uuid,text,text,integer) to authenticated;
grant execute on function public.corvia_bb_history(uuid,uuid,integer) to authenticated;
grant execute on function public.corvia_bb_requests_list(uuid,integer) to authenticated;
grant execute on function public.corvia_bb_command(uuid,uuid,text,jsonb) to authenticated;
notify pgrst,'reload schema';
commit;
