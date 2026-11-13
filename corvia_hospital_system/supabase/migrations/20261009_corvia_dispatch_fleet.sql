-- Shared Dispatch / Fleet upgrade. Run AFTER 11_install_fleet_paramedic.sql.
-- Keeps the existing paramedic incident, crew and unit identities.
begin;
create table if not exists public.corvia_ops_memberships (
 hospital_id uuid not null references public.hospitals(id),user_id uuid not null references auth.users(id),
 role text not null check(role in ('dispatcher','supervisor')),active boolean not null default true,
 granted_by uuid not null,updated_at timestamptz not null default now(),primary key(hospital_id,user_id)
);
create table if not exists public.corvia_ops_bases (
 base_id bigint generated always as identity primary key,hospital_id uuid not null references public.hospitals(id),
 name text not null check(length(trim(name)) between 2 and 150),address text not null,phone text,
 latitude numeric,longitude numeric,active boolean not null default true,unique(hospital_id,name),
 check(latitude between -90 and 90),check(longitude between -180 and 180)
);
create table if not exists public.corvia_ops_readiness (
 check_id bigint generated always as identity primary key,hospital_id uuid not null references public.hospitals(id),
 unit_id bigint not null references public.corvia_ws6_units_actual(unit_id),actor uuid not null,
 vehicle_ok boolean not null,equipment_ok boolean not null,oxygen_ok boolean not null,fuel_ok boolean not null,
 communications_ok boolean not null,cleaning_ok boolean not null,notes text not null,
 recorded_at timestamptz not null default now(),expires_at timestamptz not null default(now()+interval '12 hours')
);
create table if not exists public.corvia_ops_faults (
 fault_id bigint generated always as identity primary key,hospital_id uuid not null references public.hospitals(id),
 unit_id bigint not null references public.corvia_ws6_units_actual(unit_id),description text not null,
 reported_by uuid not null,reported_at timestamptz not null default now(),resolved_by uuid,resolved_at timestamptz,resolution text,
 check((resolved_at is null and resolved_by is null) or (resolved_at is not null and resolved_by is not null and length(trim(resolution))>=5))
);
create table if not exists public.corvia_ops_messages (
 message_id bigint generated always as identity primary key,hospital_id uuid not null references public.hospitals(id),
 incident_id bigint not null references public.corvia_ws6_incidents_actual(incident_id),sender uuid not null,
 message text not null check(length(trim(message)) between 1 and 2000),recorded_at timestamptz not null,received_at timestamptz not null default now()
);
create table if not exists public.corvia_ops_message_reads (
 message_id bigint not null references public.corvia_ops_messages(message_id),hospital_id uuid not null,user_id uuid not null,read_at timestamptz not null default now(),primary key(message_id,user_id)
);
alter table public.corvia_ws6_units_actual add column if not exists response_capability text not null default 'BLS' check(response_capability in ('BLS','ILS','ALS'));
alter table public.corvia_ws6_units_actual add column if not exists compliance_expiry_date date;
alter table public.corvia_ws6_units_actual add column if not exists base_id bigint references public.corvia_ops_bases(base_id);
alter table public.corvia_ws6_ems_members add column if not exists clinical_category text not null default 'BLS' check(clinical_category in ('BLS','ILS','ALS'));
alter table public.corvia_ws6_ems_members add column if not exists credential_evidence text;
alter table public.corvia_ws6_ems_members add column if not exists credential_verified_by uuid;
alter table public.corvia_ws6_ems_members add column if not exists credential_verified_at timestamptz;
alter table public.corvia_ws6_incidents_actual add column if not exists claimed_by uuid;
alter table public.corvia_ws6_incidents_actual add column if not exists claimed_at timestamptz;
alter table public.corvia_ws6_incidents_actual add column if not exists dispatch_state text not null default 'pending' check(dispatch_state in ('pending','claimed','assigned','escalated','closed','cancelled'));
alter table public.corvia_ws6_incidents_actual add column if not exists required_capability text not null default 'BLS' check(required_capability in ('BLS','ILS','ALS'));
alter table public.corvia_ws6_incidents_actual add column if not exists acknowledgement_due_at timestamptz;

create or replace function public.corvia_ops_role(h uuid) returns text language sql stable security definer set search_path=public as $$
 select case when public.corvia_ws6_is_hospital_admin(h) then 'admin' else
 (select mm.role from public.corvia_ops_memberships mm join public.profiles pr on pr.user_id=mm.user_id and pr.is_active join public.hospitals hh on hh.id=mm.hospital_id and hh.is_active where mm.hospital_id=h and mm.user_id=auth.uid() and mm.active) end;
$$;
create or replace function public.corvia_ops_controller(h uuid) returns boolean language sql stable security definer set search_path=public as $$ select public.corvia_ops_role(h) is not null $$;

-- Preserve the reviewed gateway as an internal implementation. Upgrade its
-- controller predicate without changing the meaning of hospital-admin checks.
do $$ declare f regprocedure; src text; begin
 if to_regprocedure('public.corvia_ems_command_core(uuid,uuid,uuid,text,jsonb)') is null then
  alter function public.corvia_ems_command(uuid,uuid,uuid,text,jsonb) rename to corvia_ems_command_core;
 end if;
 if to_regprocedure('public.corvia_ems_workspace_core(uuid,uuid,bigint)') is null then
  alter function public.corvia_ems_workspace(uuid,uuid,bigint) rename to corvia_ems_workspace_core;
 end if;
 foreach f in array array['public.corvia_ems_access()'::regprocedure,'public.corvia_ems_open(uuid,text)'::regprocedure,'public.corvia_ems_check(uuid,uuid)'::regprocedure,'public.corvia_ems_allowed(uuid,bigint)'::regprocedure,'public.corvia_ems_workspace_core(uuid,uuid,bigint)'::regprocedure,'public.corvia_ems_command_core(uuid,uuid,uuid,text,jsonb)'::regprocedure] loop
  src:=pg_get_functiondef(f);
  src:=replace(src,'public.corvia_ws6_is_hospital_admin(','public.corvia_ops_controller(');
  execute src;
 end loop;
end $$;

create or replace function public.corvia_ems_allowed(h uuid,i bigint) returns boolean language sql stable security definer set search_path=public as $$
 select exists(select 1 from public.corvia_ws6_incidents_actual where hospital_id=h and incident_id=i)
 and (public.corvia_ops_controller(h) or exists (
 select 1 from public.corvia_ws6_incident_assignments_actual a
 join public.corvia_ws6_crews c on c.crew_id=a.crew_id and c.hospital_id=h
 join public.corvia_ws6_shifts_actual sh on sh.shift_id=c.shift_id and sh.hospital_id=h
 join public.corvia_ws6_crew_members_actual cm on cm.crew_id=c.crew_id and cm.hospital_id=h
 where a.hospital_id=h and a.incident_id=i and a.is_active
 and cm.member_id=public.corvia_ems_member(h) and cm.is_active and cm.left_datetime is null
 and c.crew_status='Active' and c.start_datetime<=now() and c.end_datetime>now()
 and sh.shift_status='Active' and sh.start_datetime<=now() and sh.end_datetime>now()));
$$;

create or replace function public.corvia_ops_eligibility(h uuid,u bigint,cap text default 'BLS') returns text language plpgsql stable security definer set search_path=public as $$
declare vehicle public.corvia_ws6_units_actual%rowtype; ck public.corvia_ops_readiness%rowtype; c public.corvia_ws6_crews%rowtype; need int;
begin
 select * into vehicle from public.corvia_ws6_units_actual where hospital_id=h and unit_id=u;
 if not found or not vehicle.is_active then return 'Vehicle is inactive or unavailable'; end if;
 if vehicle.status<>'Available' or vehicle.readiness_status not in ('ready','idle') then return 'Vehicle is assigned, off duty or in maintenance'; end if;
 if vehicle.compliance_expiry_date is null or vehicle.compliance_expiry_date<(now() at time zone 'Africa/Johannesburg')::date then return 'Vehicle compliance documents need review'; end if;
 need:=array_position(array['BLS','ILS','ALS'],cap);
 if need is null or array_position(array['BLS','ILS','ALS'],vehicle.response_capability)<need then return 'Vehicle capability does not meet incident requirements'; end if;
 if exists(select 1 from public.corvia_ops_faults where hospital_id=h and unit_id=u and resolved_at is null) then return 'An unresolved vehicle fault blocks dispatch'; end if;
 select * into ck from public.corvia_ops_readiness where hospital_id=h and unit_id=u order by recorded_at desc,check_id desc limit 1;
 if ck.check_id is null or ck.expires_at<=now() then return 'A current readiness inspection is required'; end if;
 if not (ck.vehicle_ok and ck.equipment_ok and ck.oxygen_ok and ck.fuel_ok and ck.communications_ok and ck.cleaning_ok) then return 'The latest readiness inspection failed'; end if;
 select cc.* into c from public.corvia_ws6_crews cc join public.corvia_ws6_shifts_actual sh on sh.shift_id=cc.shift_id and sh.hospital_id=h where cc.hospital_id=h and cc.unit_id=u and cc.crew_status='Active' and cc.start_datetime<=now() and cc.end_datetime>now() and sh.shift_status='Active' and sh.start_datetime<=now() and sh.end_datetime>now() order by cc.crew_id limit 1;
 if c.crew_id is null then return 'No active time-bounded crew shift'; end if;
 if not exists(select 1 from public.corvia_ws6_crew_members_actual where hospital_id=h and crew_id=c.crew_id and is_active) then return 'Crew manifest is empty'; end if;
 if exists(select 1 from public.corvia_ws6_crew_members_actual cm join public.corvia_ws6_ems_members em on em.member_id=cm.member_id where cm.hospital_id=h and cm.crew_id=c.crew_id and cm.is_active and (em.hospital_id<>h or not em.is_active or em.verification_status<>'verified' or em.verification_expiry_date is null or em.verification_expiry_date<(now() at time zone 'Africa/Johannesburg')::date or em.credential_verified_by is null or em.credential_verified_by=em.auth_user_id)) then return 'Crew needs current independently verified credentials'; end if;
 if not exists(select 1 from public.corvia_ws6_crew_members_actual cm join public.corvia_ws6_ems_members em on em.member_id=cm.member_id where cm.hospital_id=h and cm.crew_id=c.crew_id and cm.is_active and array_position(array['BLS','ILS','ALS'],em.clinical_category)>=need) then return 'Crew clinical category is insufficient'; end if;
 return null;
end $$;

create or replace function public.corvia_ops_assignment_guard() returns trigger language plpgsql security definer set search_path=public as $$
declare u bigint; reason text; cap text;
begin
 if not new.is_active then return new; end if;
 select unit_id into u from public.corvia_ws6_crews where hospital_id=new.hospital_id and crew_id=new.crew_id;
 select required_capability into cap from public.corvia_ws6_incidents_actual where hospital_id=new.hospital_id and incident_id=new.incident_id;
 if u is null or cap is null then raise exception 'Assignment hospital mismatch'; end if;
 reason:=public.corvia_ops_eligibility(new.hospital_id,u,cap);
 if reason is not null then raise exception '%',reason; end if;
 return new;
end $$;
drop trigger if exists corvia_ops_assignment_guard on public.corvia_ws6_incident_assignments_actual;
create trigger corvia_ops_assignment_guard before insert or update of crew_id,is_active on public.corvia_ws6_incident_assignments_actual for each row execute function public.corvia_ops_assignment_guard();

create or replace function public.corvia_ems_workspace(h uuid,s uuid,i bigint default null) returns jsonb language plpgsql security definer set search_path=public as $$
declare r jsonb; vals jsonb; role_name text;
begin
 r:=public.corvia_ems_workspace_core(h,s,i);role_name:=public.corvia_ops_role(h);
 r:=r||jsonb_build_object('operations_role',role_name,'is_admin',role_name='admin','can_dispatch',role_name is not null);
 if i is null and role_name is not null then
  select coalesce(jsonb_agg(to_jsonb(u)||jsonb_build_object('eligibility_reason',public.corvia_ops_eligibility(h,u.unit_id),'location_stale',u.location_updated_at is null or u.location_updated_at<now()-interval '5 minutes')),'[]') into vals from public.corvia_ws6_units_actual u where hospital_id=h;
  r:=r||jsonb_build_object('units_actual',vals);
  select coalesce(jsonb_agg(to_jsonb(t)),'[]') into vals from public.corvia_ops_bases t where hospital_id=h;r:=r||jsonb_build_object('bases',vals);
  select coalesce(jsonb_agg(to_jsonb(t)),'[]') into vals from public.corvia_ops_faults t where hospital_id=h;r:=r||jsonb_build_object('faults',vals);
  select coalesce(jsonb_agg(to_jsonb(t)),'[]') into vals from public.corvia_ops_readiness t where hospital_id=h;r:=r||jsonb_build_object('readiness',vals);
  if role_name='admin' then
   select coalesce(jsonb_agg(to_jsonb(t)||jsonb_build_object('email',u.email)),'[]') into vals from public.corvia_ops_memberships t join auth.users u on u.id=t.user_id where hospital_id=h;r:=r||jsonb_build_object('operators',vals);
  end if;
 end if;
 if i is not null then
  select coalesce(jsonb_agg(to_jsonb(t)||jsonb_build_object('acknowledged',exists(select 1 from public.corvia_ops_message_reads rd where rd.message_id=t.message_id and rd.user_id<>t.sender)) order by received_at),'[]') into vals from public.corvia_ops_messages t where hospital_id=h and incident_id=i;
  r:=r||jsonb_build_object('messages',vals);
  if role_name in ('dispatcher','supervisor') then
   -- Dispatch receives operational context, not the crew's clinical record.
   r:=r-array['patients_actual','patient_allergies','patient_medications','patient_conditions','emergency_contacts','patient_special_risks','patient_qr_confirmations','observations','clinical_notes','treatments','treatment_timeline','handovers','audit_logs'];
   select coalesce(jsonb_agg(jsonb_build_object('action_type',action_type,'action_datetime',action_datetime,'reason',reason) order by action_datetime),'[]') into vals
   from public.corvia_ws6_audit_logs where hospital_id=h and incident_id=i and action_type in ('claim','assign','decline','exception','fault','status','message','message_read');
   r:=r||jsonb_build_object('audit_logs',vals);
  end if;
 end if;
 return r;
end $$;

create or replace function public.corvia_ems_command(h uuid,s uuid,op uuid,action text,p jsonb) returns jsonb language plpgsql security definer set search_path=public as $$
declare role_name text; i bigint; u bigint; rid bigint; actor uuid; inc public.corvia_ws6_incidents_actual%rowtype; result jsonb; rec public.corvia_ems_receipts%rowtype; checked boolean;
begin
 perform public.corvia_ems_check(h,s);role_name:=public.corvia_ops_role(h);
 if op is null or jsonb_typeof(p)<>'object' then raise exception 'Operation and form data required'; end if;
 perform pg_advisory_xact_lock(hashtextextended(h::text,0));
 select rr.* into rec from public.corvia_ems_receipts rr where rr.hospital_id=h and rr.actor=auth.uid() and rr.operation_id=op;
 if found then if rec.action<>action or rec.payload<>p then raise exception 'Operation ID was already used for different data'; end if;return rec.result;end if;
 i:=nullif(p->>'incident_id','')::bigint;u:=nullif(p->>'unit_id','')::bigint;
 if i is not null then
  if not public.corvia_ems_allowed(h,i) then raise exception 'Incident access denied'; end if;
  select * into inc from public.corvia_ws6_incidents_actual where incident_id=i and hospital_id=h for update;
 end if;
 if action in ('operator','base','readiness','fault_resolve','unit','member','facility','shift','crew_member','end_shift','unit_status','navigation') and role_name is distinct from 'admin' then raise exception 'Hospital administrator access required'; end if;
 if role_name in ('dispatcher','supervisor') and action not in ('incident','assign','claim','decline','exception','message','message_read','preferences','session_revoke','patient','patient_link','hazard','location','fault') then raise exception 'This action requires clinical crew or hospital administrator access';end if;
 if action in ('claim','assign','incident') and role_name is null then raise exception 'Dispatcher access required'; end if;
 if action='member' and p->>'verification_status'='verified' then
  select id into actor from auth.users where lower(email)=lower(p->>'email');
  if actor=auth.uid() then raise exception 'A second administrator must verify your credentials'; end if;
  if coalesce(length(trim(p->>'credential_evidence')),0)<5 then raise exception 'Credential evidence / registration reference required'; end if;
 end if;
 if action='assign' then
  if inc.claimed_by is null then raise exception 'Claim the incident before assignment'; end if;
  if inc.claimed_by<>auth.uid() then raise exception 'Claim or take over this incident before assignment'; end if;
 end if;
 if action not in ('operator','base','readiness','fault','fault_resolve','claim','exception','message','message_read') then
  if action='status' and p->>'status' in ('Accepted','En Route') and exists(
   select 1 from public.corvia_ws6_incident_assignments_actual aa join public.corvia_ws6_crews cc on cc.crew_id=aa.crew_id
   join public.corvia_ws6_units_actual uu on uu.unit_id=cc.unit_id
   where aa.hospital_id=h and aa.incident_id=i and aa.is_active and
    (uu.readiness_status='maintenance' or uu.compliance_expiry_date is null or uu.compliance_expiry_date<(now() at time zone 'Africa/Johannesburg')::date
     or exists(select 1 from public.corvia_ops_faults ff where ff.hospital_id=h and ff.unit_id=uu.unit_id and ff.resolved_at is null)
     or not coalesce((select rr.expires_at>now() and rr.vehicle_ok and rr.equipment_ok and rr.oxygen_ok and rr.fuel_ok and rr.communications_ok and rr.cleaning_ok from public.corvia_ops_readiness rr where rr.hospital_id=h and rr.unit_id=uu.unit_id order by rr.recorded_at desc,rr.check_id desc limit 1),false)))
  then raise exception 'Vehicle is no longer ready. Contact dispatch for reassignment';end if;
  result:=public.corvia_ems_command_core(h,s,op,action,p);
  if action='unit' then
   if p?'base_id' and not exists(select 1 from public.corvia_ops_bases where hospital_id=h and base_id=(p->>'base_id')::bigint and active) then raise exception 'Base does not belong to this hospital'; end if;
   update public.corvia_ws6_units_actual set response_capability=coalesce(p->>'response_capability',response_capability),compliance_expiry_date=coalesce((p->>'compliance_expiry_date')::date,compliance_expiry_date),base_id=coalesce((p->>'base_id')::bigint,base_id) where hospital_id=h and unit_id=(result->>'id')::bigint;
  elsif action='member' then
   update public.corvia_ws6_ems_members set clinical_category=coalesce(p->>'clinical_category',clinical_category),credential_evidence=coalesce(p->>'credential_evidence',credential_evidence),credential_verified_by=case when p->>'verification_status'='verified' then auth.uid() else credential_verified_by end,credential_verified_at=case when p->>'verification_status'='verified' then now() else credential_verified_at end where hospital_id=h and member_id=(result->>'id')::bigint;
  elsif action='incident' then
   update public.corvia_ws6_incidents_actual set required_capability=coalesce(p->>'required_capability','BLS') where hospital_id=h and incident_id=(result->>'id')::bigint;
  elsif action='assign' then
   update public.corvia_ws6_incidents_actual set dispatch_state='assigned',acknowledgement_due_at=now()+interval '2 minutes' where hospital_id=h and incident_id=i;
  elsif action='status' then update public.corvia_ws6_incidents_actual set dispatch_state=case when p->>'status'='Closed' then 'closed' else dispatch_state end,acknowledgement_due_at=null where incident_id=i and hospital_id=h;
  elsif action='decline' then update public.corvia_ws6_incidents_actual set dispatch_state='escalated',acknowledgement_due_at=null where incident_id=i and hospital_id=h;
  end if;
  return result;
 end if;
 if i is not null and (inc.status='Closed' or (p->>'revision')::bigint is distinct from inc.revision) then raise exception 'Incident is closed or changed. Refresh before saving.';end if;
 if action='operator' then
  select id into actor from auth.users where lower(email)=lower(p->>'email');if actor is null then raise exception 'An existing account email is required';end if;
  insert into public.corvia_ops_memberships(hospital_id,user_id,role,active,granted_by) values(h,actor,p->>'role',(p->>'active')::boolean,auth.uid()) on conflict(hospital_id,user_id) do update set role=excluded.role,active=excluded.active,granted_by=excluded.granted_by,updated_at=now();result:=jsonb_build_object('saved',true);
 elsif action='base' then
  insert into public.corvia_ops_bases(hospital_id,name,address,phone,latitude,longitude) values(h,p->>'name',p->>'address',p->>'phone',(p->>'latitude')::numeric,(p->>'longitude')::numeric) returning base_id into rid;result:=jsonb_build_object('id',rid);
 elsif action in ('readiness','fault','fault_resolve') then
  if not exists(select 1 from public.corvia_ws6_units_actual where hospital_id=h and unit_id=u) then raise exception 'Vehicle not found'; end if;
  if action='fault' and role_name is null and not exists(select 1 from public.corvia_ws6_incident_assignments_actual aa join public.corvia_ws6_crews cc on cc.crew_id=aa.crew_id where aa.hospital_id=h and aa.is_active and cc.unit_id=u and public.corvia_ems_allowed(h,aa.incident_id)) then raise exception 'Vehicle access denied';end if;
  if action='readiness' then
   if coalesce(length(trim(p->>'notes')),0)<3 then raise exception 'Inspection notes required';end if;
   insert into public.corvia_ops_readiness(hospital_id,unit_id,actor,vehicle_ok,equipment_ok,oxygen_ok,fuel_ok,communications_ok,cleaning_ok,notes) values(h,u,auth.uid(),(p->>'vehicle_ok')::boolean,(p->>'equipment_ok')::boolean,(p->>'oxygen_ok')::boolean,(p->>'fuel_ok')::boolean,(p->>'communications_ok')::boolean,(p->>'cleaning_ok')::boolean,p->>'notes') returning check_id into rid;
   checked:=(p->>'vehicle_ok')::boolean and (p->>'equipment_ok')::boolean and (p->>'oxygen_ok')::boolean and (p->>'fuel_ok')::boolean and (p->>'communications_ok')::boolean and (p->>'cleaning_ok')::boolean;
   update public.corvia_ws6_units_actual set readiness_status=case when not checked then 'maintenance' when status='Assigned' then readiness_status else 'ready' end,status=case when status='Assigned' then status when checked then 'Available' else 'Out of Service' end,availability_revision=availability_revision+1 where hospital_id=h and unit_id=u;
  elsif action='fault' then
   if coalesce(length(trim(p->>'description')),0)<5 then raise exception 'Fault description required';end if;
   insert into public.corvia_ops_faults(hospital_id,unit_id,description,reported_by) values(h,u,p->>'description',auth.uid()) returning fault_id into rid;
   update public.corvia_ws6_units_actual set readiness_status='maintenance',status=case when status='Assigned' then status else 'Out of Service' end,availability_revision=availability_revision+1 where hospital_id=h and unit_id=u;
   update public.corvia_ws6_incidents_actual set dispatch_state='escalated',revision=revision+1 where hospital_id=h and incident_id in (select aa.incident_id from public.corvia_ws6_incident_assignments_actual aa join public.corvia_ws6_crews cc on cc.crew_id=aa.crew_id where aa.hospital_id=h and aa.is_active and cc.unit_id=u);
  else
   update public.corvia_ops_faults set resolved_by=auth.uid(),resolved_at=now(),resolution=p->>'resolution' where hospital_id=h and unit_id=u and fault_id=(p->>'fault_id')::bigint and resolved_at is null returning fault_id into rid;
   if rid is null then raise exception 'Open fault not found';end if;
   -- A new inspection is required after repair; do not silently restore readiness.
   update public.corvia_ops_readiness set expires_at=least(expires_at,now()) where hospital_id=h and unit_id=u;
  end if;result:=jsonb_build_object('id',rid);
 elsif action='claim' then
  if i is null then raise exception 'Incident required';end if;
  if inc.claimed_by is not null and inc.claimed_by<>auth.uid() then
   if role_name not in ('admin','supervisor') or coalesce(length(trim(p->>'reason')),0)<5 then raise exception 'Incident is already claimed. Supervisor takeover requires a reason';end if;
  end if;
  update public.corvia_ws6_incidents_actual set claimed_by=auth.uid(),claimed_at=now(),dispatch_state=case when dispatch_state='pending' then 'claimed' else dispatch_state end where hospital_id=h and incident_id=i;result:=jsonb_build_object('claimed',true);
 elsif action='exception' then
  if i is null or coalesce(length(trim(p->>'reason')),0)<5 or p->>'kind' not in ('cancelled','no_patient','unsafe_scene','refusal','unit_failure','backup_required') then raise exception 'Choose an exception and give a reason';end if;
  if p->>'kind'='cancelled' then
   if role_name not in ('admin','supervisor') or role_name is null then raise exception 'Supervisor cancellation required';end if;
   if exists(select 1 from public.corvia_ws6_incident_patients where hospital_id=h and incident_id=i and is_active) then raise exception 'Patients are linked: complete their handovers before closure';end if;
   update public.corvia_ws6_units_actual set status='Available',readiness_status=case when readiness_status='maintenance' then 'maintenance' else 'ready' end,availability_revision=availability_revision+1 where hospital_id=h and unit_id in (select cc.unit_id from public.corvia_ws6_crews cc join public.corvia_ws6_incident_assignments_actual aa on aa.crew_id=cc.crew_id where aa.hospital_id=h and aa.incident_id=i and aa.is_active);
   update public.corvia_ws6_incident_assignments_actual set is_active=false,assignment_status='Completed' where hospital_id=h and incident_id=i and is_active;
   update public.corvia_ws6_incidents_actual set status='Closed',closed_datetime=now(),dispatch_state='cancelled' where hospital_id=h and incident_id=i;
  else update public.corvia_ws6_incidents_actual set dispatch_state='escalated' where hospital_id=h and incident_id=i;end if;
  result:=jsonb_build_object('exception',p->>'kind');
 elsif action='message' then
  if i is null then raise exception 'Incident required';end if;
  if coalesce((p->>'recorded_at')::timestamptz,now())>now()+interval '5 minutes' then raise exception 'Message time is in the future';end if;
  insert into public.corvia_ops_messages(hospital_id,incident_id,sender,message,recorded_at) values(h,i,auth.uid(),p->>'message',coalesce((p->>'recorded_at')::timestamptz,now())) returning message_id into rid;result:=jsonb_build_object('id',rid);
 elsif action='message_read' then
  if i is null or not exists(select 1 from public.corvia_ops_messages where hospital_id=h and incident_id=i and message_id=(p->>'message_id')::bigint and sender<>auth.uid()) then raise exception 'Message not found';end if;
  insert into public.corvia_ops_message_reads(message_id,hospital_id,user_id) values((p->>'message_id')::bigint,h,auth.uid()) on conflict do nothing;result:=jsonb_build_object('read',true);
 end if;
 if i is not null then update public.corvia_ws6_incidents_actual set revision=revision+1 where hospital_id=h and incident_id=i;end if;
 insert into public.corvia_ws6_audit_logs(hospital_id,actor_auth_user_id,incident_id,action_type,entity_type,entity_id,new_value,reason) values(h,auth.uid(),i,action,action,coalesce(rid,u),result,coalesce(p->>'reason',p->>'notes',p->>'description'));
 insert into public.corvia_ems_receipts(hospital_id,actor,operation_id,action,payload,result) values(h,auth.uid(),op,action,p,result);
 return result;
end $$;

do $$ declare t record;f record;begin
 for t in select tablename from pg_tables where schemaname='public' and tablename like 'corvia_ops_%' loop
  execute format('alter table public.%I enable row level security',t.tablename);execute format('revoke all on public.%I from public,anon,authenticated',t.tablename);
 end loop;
 for f in select p.oid::regprocedure sig from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and (p.proname like 'corvia_ops_%' or p.proname in ('corvia_ems_command_core','corvia_ems_workspace_core')) loop
  execute format('revoke all on function %s from public,anon,authenticated',f.sig);
 end loop;
end $$;
revoke all on function public.corvia_ems_command(uuid,uuid,uuid,text,jsonb),public.corvia_ems_workspace(uuid,uuid,bigint) from public,anon;
grant execute on function public.corvia_ems_command(uuid,uuid,uuid,text,jsonb),public.corvia_ems_workspace(uuid,uuid,bigint) to authenticated;
notify pgrst,'reload schema';
commit;
