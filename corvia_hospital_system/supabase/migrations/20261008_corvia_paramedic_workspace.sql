-- Run AFTER 20261008_corvia_workstream6_database_contract.sql.
-- Additive migration. No demo inserts, no conversion of synthetic records.
begin;

alter table public.corvia_ws6_incidents_actual add column if not exists revision bigint not null default 0;
alter table public.corvia_ws6_patients_actual add column if not exists identity_number varchar(50);
alter table public.corvia_ws6_patient_qr_confirmations alter column scanned_patient_id drop not null;
alter table public.corvia_ws6_device_sessions alter column user_id drop not null;
alter table public.corvia_ws6_device_sessions add column if not exists auth_user_id uuid;
alter table public.corvia_ws6_device_sessions add column if not exists session_token uuid default gen_random_uuid();
create unique index if not exists corvia_ems_session_token on public.corvia_ws6_device_sessions(session_token);
alter table public.corvia_ws6_audit_logs add column if not exists actor_auth_user_id uuid;
create table if not exists public.corvia_ems_receipts (
  hospital_id uuid not null references public.hospitals(id), actor uuid not null,
  operation_id uuid not null, action text not null, payload jsonb not null,
  result jsonb not null, created_at timestamptz not null default now(),
  primary key(hospital_id,actor,operation_id)
);
create table if not exists public.corvia_ems_preferences (
  hospital_id uuid not null references public.hospitals(id), actor uuid not null,
  critical_alerts boolean not null default true, navigation_app text not null default 'none'
    check(navigation_app in ('none','google_maps','waze')),
  primary key(hospital_id,actor)
);
create table if not exists public.corvia_ems_navigation (
  hospital_id uuid not null references public.hospitals(id), app text not null
    check(app in ('google_maps','waze')), approved boolean not null default false,
  primary key(hospital_id,app)
);

create or replace function public.corvia_ws6_is_hospital_admin(p_hospital_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select auth.uid() is not null and exists (
    select 1 from public.hospital_admins ha
    join public.hospitals h on h.id=ha.hospital_id and h.is_active
    join public.profiles p on p.user_id=auth.uid() and p.is_active
    where ha.hospital_id=p_hospital_id and ha.profile_id in (p.id,p.user_id)
  );
$$;

create or replace function public.corvia_ems_member(h uuid)
returns bigint language sql stable security definer set search_path = public as $$
 select member_id from public.corvia_ws6_ems_members
 where hospital_id=h and auth_user_id=auth.uid() and is_active
   and verification_status='verified'
   and verification_expiry_date is not null and verification_expiry_date >= (now() at time zone 'Africa/Johannesburg')::date
 order by member_id limit 1;
$$;

create or replace function public.corvia_ems_allowed(h uuid,i bigint)
returns boolean language sql stable security definer set search_path = public as $$
 select exists(select 1 from public.corvia_ws6_incidents_actual where hospital_id=h and incident_id=i)
 and (public.corvia_ws6_is_hospital_admin(h) or exists (
   select 1 from public.corvia_ws6_incident_assignments_actual a
   join public.corvia_ws6_crews c on c.crew_id=a.crew_id and c.hospital_id=h
   join public.corvia_ws6_shifts_actual s on s.shift_id=c.shift_id and s.hospital_id=h
   join public.corvia_ws6_crew_members_actual cm on cm.crew_id=c.crew_id and cm.hospital_id=h
   where a.hospital_id=h and a.incident_id=i and (a.is_active or (a.assignment_status='Completed' and exists(select 1 from public.corvia_ws6_incidents_actual ii where ii.incident_id=i and ii.status='Closed')))
    and cm.member_id=public.corvia_ems_member(h) and cm.is_active and cm.left_datetime is null
    and c.crew_status='Active' and c.start_datetime<=now() and c.end_datetime>now()
    and s.shift_status='Active' and s.start_datetime<=now() and s.end_datetime>now()
 ));
$$;

create or replace function public.corvia_ems_access()
returns jsonb language sql stable security definer set search_path = public as $$
 select coalesce(jsonb_agg(jsonb_build_object('id',id,'name',name,'is_admin',public.corvia_ws6_is_hospital_admin(id)) order by name),'[]')
 from public.hospitals where is_active and auth.uid() is not null
 and (public.corvia_ws6_is_hospital_admin(id) or public.corvia_ems_member(id) is not null);
$$;

create or replace function public.corvia_ems_open(h uuid,device text)
returns uuid language plpgsql security definer set search_path = public as $$
declare t uuid;
begin
 if auth.uid() is null or not exists(select 1 from public.hospitals where id=h and is_active)
 or not (public.corvia_ws6_is_hospital_admin(h) or public.corvia_ems_member(h) is not null) then
   raise exception 'Hospital administrator or verified paramedic access is required'; end if;
 insert into public.corvia_ws6_device_sessions(hospital_id,user_id,auth_user_id,device_id,expiry_datetime)
 values(h,public.corvia_ems_member(h),auth.uid(),left(coalesce(device,'Workspace'),200),now()+interval '12 hours')
 returning session_token into t;
 return t;
end; $$;

create or replace function public.corvia_ems_check(h uuid,s uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
 if auth.uid() is null or not exists(select 1 from public.hospitals where id=h and is_active)
 or not (public.corvia_ws6_is_hospital_admin(h) or public.corvia_ems_member(h) is not null) then
 raise exception 'Workspace access was removed'; end if;
 update public.corvia_ws6_device_sessions set last_activity_datetime=now(),last_sync_datetime=now()
 where hospital_id=h and session_token=s and auth_user_id=auth.uid() and session_status='Active'
 and expiry_datetime>now() and last_activity_datetime>now()-interval '15 minutes';
 if not found then raise exception 'Session expired or revoked. Reopen the workspace.'; end if;
end; $$;

create or replace function public.corvia_ems_workspace(h uuid,s uuid,i bigint default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare r jsonb='{}'; a boolean; tbl text; rows jsonb; predicate text;
begin
 perform public.corvia_ems_check(h,s);
 a:=public.corvia_ws6_is_hospital_admin(h);
 if i is not null and not public.corvia_ems_allowed(h,i) then raise exception 'Incident access denied'; end if;
 r:=jsonb_build_object('is_admin',a,'member_id',public.corvia_ems_member(h),'server_time',now());
 if i is null then
   select coalesce(jsonb_agg(to_jsonb(q)),'[]') into rows from (
     select * from public.corvia_ws6_incidents_actual t where hospital_id=h and public.corvia_ems_allowed(h,incident_id)
     order by (status='Closed'),created_datetime desc limit 200
   ) q;
   r:=r||jsonb_build_object('incidents',rows);
   foreach tbl in array array['units_actual','ems_members','shifts_actual','crews','crew_members_actual','receiving_facilities'] loop
    if a or tbl='receiving_facilities' then
      execute format('select coalesce(jsonb_agg(to_jsonb(t)),''[]'') from public.corvia_ws6_%I t where hospital_id=$1',tbl) into rows using h;
      r:=r||jsonb_build_object(tbl,rows);
    end if;
   end loop;
 else
   select to_jsonb(t) into rows from public.corvia_ws6_incidents_actual t where incident_id=i and hospital_id=h;
   r:=r||jsonb_build_object('incident',rows);
   foreach tbl in array array['incident_assignments_actual','incident_patients','incident_hazards','incident_locations','incident_status_history','observations','clinical_notes','treatments','treatment_timeline','handovers','audit_logs'] loop
    execute format('select coalesce(jsonb_agg(to_jsonb(t)),''[]'') from public.corvia_ws6_%I t where hospital_id=$1 and incident_id=$2',tbl) into rows using h,i;
    r:=r||jsonb_build_object(tbl,rows);
   end loop;
   -- Never return the identity of a mismatched, unrelated scanned patient.
   select coalesce(jsonb_agg(to_jsonb(t)-'scanned_patient_id'),'[]') into rows from public.corvia_ws6_patient_qr_confirmations t where hospital_id=h and incident_id=i;
   r:=r||jsonb_build_object('patient_qr_confirmations',rows);
   foreach tbl in array array['patients_actual','patient_allergies','patient_medications','patient_conditions','emergency_contacts','patient_special_risks'] loop
    execute format('select coalesce(jsonb_agg(to_jsonb(t)),''[]'') from public.corvia_ws6_%I t where hospital_id=$1 and patient_id in (select patient_id from public.corvia_ws6_incident_patients where hospital_id=$1 and incident_id=$2 and is_active)',tbl) into rows using h,i;
    r:=r||jsonb_build_object(tbl,rows);
   end loop;
 end if;
 select coalesce(jsonb_agg(to_jsonb(t)-'session_token'-'auth_user_id'),'[]') into rows from public.corvia_ws6_device_sessions t where hospital_id=h and auth_user_id=auth.uid();
 r:=r||jsonb_build_object('sessions',rows);
 select to_jsonb(t) into rows from public.corvia_ems_preferences t where hospital_id=h and actor=auth.uid();
 r:=r||jsonb_build_object('preferences',coalesce(rows,'{}'));
 select coalesce(jsonb_agg(to_jsonb(t)),'[]') into rows from public.corvia_ems_navigation t where hospital_id=h;
 return r||jsonb_build_object('navigation',rows);
end; $$;

-- Internal insert helper; callers can never execute it directly. Keys are
-- allowlisted in the command function, then server-owned scope/actor keys added.
create or replace function public.corvia_ems_insert(tbl text,pk text,p jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare cols text; vals text; r jsonb;
begin
 select string_agg(format('%I',key),','),string_agg(format('x.%I',key),',') into cols,vals from jsonb_object_keys(p) key;
 execute format('insert into public.%I(%s) select %s from jsonb_populate_record(null::public.%I,$1) x returning to_jsonb(%I.*)',tbl,cols,vals,tbl,tbl) into r using p;
 return r;
end; $$;

create or replace function public.corvia_ems_command(h uuid,s uuid,op uuid,action text,p jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
 a boolean; m bigint; i bigint; pid bigint; rev bigint; incident public.corvia_ws6_incidents_actual%rowtype;
 old jsonb; result jsonb; body jsonb; cols text[]; tbl text; pk text; rid bigint; member bigint; unit bigint; crew bigint;
 original timestamptz; target text; next_status text; scanned bigint; matched boolean; assignment bigint; c record;
 receipt public.corvia_ems_receipts%rowtype;
begin
 perform public.corvia_ems_check(h,s);
 if op is null or jsonb_typeof(p)<>'object' then raise exception 'Operation and form data required'; end if;
 a:=public.corvia_ws6_is_hospital_admin(h); m:=public.corvia_ems_member(h);
 i:=nullif(p->>'incident_id','')::bigint; pid:=nullif(p->>'patient_id','')::bigint;
 -- Serialize a hospital's mutations to make resource checks and retries atomic.
 perform pg_advisory_xact_lock(hashtextextended(h::text,0));
 select * into receipt from public.corvia_ems_receipts where hospital_id=h and actor=auth.uid() and operation_id=op;
 if found then
  if receipt.action<>action or receipt.payload<>p then raise exception 'Operation ID was already used for different data'; end if;
  return receipt.result;
 end if;
 -- A receipt confirms the caller's own committed operation (IDs/status only).
 -- New writes still require current incident access, including after decline.
 if i is not null and not public.corvia_ems_allowed(h,i) then raise exception 'Incident access denied'; end if;
 if i is null and not a and action not in ('preferences','session_revoke') then raise exception 'Administrator access required'; end if;
 if i is not null then
  select * into incident from public.corvia_ws6_incidents_actual where hospital_id=h and incident_id=i for update;
  if incident.status='Closed' then raise exception 'Closed incidents are read only'; end if;
  if nullif(p->>'revision','')::bigint is distinct from incident.revision
   and not (action in ('observation','note','treatment') and exists(select 1 from public.corvia_ws6_incident_assignments_actual where hospital_id=h and incident_id=i and is_active and assignment_id=nullif(p->>'assignment_id','')::bigint))
   then raise exception 'Incident changed. Refresh and review before saving.'; end if;
  if p?'assignment_id' and not exists(select 1 from public.corvia_ws6_incident_assignments_actual where hospital_id=h and incident_id=i and is_active and assignment_id=nullif(p->>'assignment_id','')::bigint) then raise exception 'Assignment changed. Review this clinical record before submitting.'; end if;
 end if;
 if pid is not null and not exists(select 1 from public.corvia_ws6_incident_patients where hospital_id=h and incident_id=i and patient_id=pid and is_active) then
  raise exception 'Patient is not assigned to this incident'; end if;
 original:=coalesce(nullif(p->>'recorded_at','')::timestamptz,now());
 if original>now()+interval '5 minutes' or original<now()-interval '7 days' then raise exception 'Recorded time must be within the past seven days'; end if;

 if action in ('unit','member','facility','incident','patient','hazard','observation','note','treatment','allergy','medication','condition','contact','risk','location') then
  case action
   when 'unit' then tbl:='units_actual';pk:='unit_id';cols:=array['unit_number','registration_number','vehicle_type','base_location'];
   when 'member' then tbl:='ems_members';pk:='member_id';cols:=array['employee_number','first_name','last_name','email','phone_number','qualification','verification_status','verification_expiry_date','is_active'];
   when 'facility' then tbl:='receiving_facilities';pk:='facility_id';cols:=array['facility_code','facility_name','address','phone_number','emergency_department','is_active'];
   when 'incident' then tbl:='incidents_actual';pk:='incident_id';cols:=array['priority','incident_type','dispatch_notes','scene_address','latitude','longitude'];
   when 'patient' then tbl:='patients_actual';pk:='patient_id';cols:=array['patient_number','identity_number','first_name','last_name','date_of_birth','sex','patient_recorded_blood_type'];
   when 'hazard' then tbl:='incident_hazards';pk:='hazard_id';cols:=array['hazard_type','description','severity'];
   when 'observation' then tbl:='observations';pk:='observation_id';cols:=array['heart_rate','respiratory_rate','systolic_bp','diastolic_bp','spo2','temperature','gcs','notes'];
   when 'note' then tbl:='clinical_notes';pk:='note_id';cols:=array['note_text'];
   when 'treatment' then tbl:='treatments';pk:='treatment_id';cols:=array['treatment_type','description','outcome'];
   when 'allergy' then tbl:='patient_allergies';pk:='allergy_id';cols:=array['allergen','reaction','severity'];
   when 'medication' then tbl:='patient_medications';pk:='medication_id';cols:=array['medication_name','dosage','frequency','notes'];
   when 'condition' then tbl:='patient_conditions';pk:='condition_id';cols:=array['condition_name','severity','notes'];
   when 'contact' then tbl:='emergency_contacts';pk:='emergency_contact_id';cols:=array['name','relationship','phone_number','priority'];
   when 'risk' then tbl:='patient_special_risks';pk:='risk_id';cols:=array['risk_type','description','severity'];
   when 'location' then tbl:='incident_locations';pk:='location_id';cols:=array['latitude','longitude','address','location_type','accuracy_meters'];
  end case;
  if action in ('unit','member','facility','incident') and not a then raise exception 'Administrator access required'; end if;
  if action not in ('unit','member','facility','incident') and i is null then raise exception 'Select an incident'; end if;
  if action in ('observation','note','treatment','allergy','medication','condition','contact','risk') and pid is null then raise exception 'Select a patient'; end if;
  select coalesce(jsonb_object_agg(key,value),'{}') into body from jsonb_each(p) where key=any(cols) and value<>'null'::jsonb;
  if exists(select 1 from jsonb_each_text(body) where value is not null and btrim(value)='') then raise exception 'Remove empty optional fields'; end if;
  body:=body||jsonb_build_object('hospital_id',h);
  if action='member' then
   if body->>'verification_status'='verified' and nullif(body->>'verification_expiry_date','')::date is null then raise exception 'Credential expiry is required'; end if;
   select id into target from auth.users where lower(email)=lower(body->>'email');
   if target is null then raise exception 'Staff email must belong to an existing signed-up account'; end if;
   if exists(select 1 from public.corvia_ws6_ems_members where hospital_id=h and auth_user_id=target::uuid and member_id<>coalesce((p->>'id')::bigint,0)) then raise exception 'This staff account is already linked'; end if;
   body:=body||jsonb_build_object('auth_user_id',target);
  end if;
  if action='incident' then body:=body||jsonb_build_object('incident_number','EMS-'||to_char(now(),'YYYYMMDD')||'-'||left(op::text,8),'created_by',auth.uid()); end if;
  if action='patient' then
   if (body->>'date_of_birth')::date>current_date then raise exception 'Date of birth cannot be in the future'; end if;
   if not body?'patient_number' then body:=body||jsonb_build_object('patient_number','EMS-P-'||left(op::text,12)); end if;
  end if;
  if action in ('hazard','observation','note','treatment','location') then body:=body||jsonb_build_object('incident_id',i); end if;
  if action in ('observation','note','treatment','allergy','medication','condition','contact','risk') then body:=body||jsonb_build_object('patient_id',pid); end if;
  if action in ('observation','note') then body:=body||jsonb_build_object('recorded_by',m,'recorded_at',original,'sync_status','Sent'); end if;
  if action='treatment' then body:=body||jsonb_build_object('performed_by',m,'performed_at',original,'sync_status','Sent'); end if;
  if action='hazard' then body:=body||jsonb_build_object('identified_by',m,'identified_at',original); end if;
  if action='location' then body:=body||jsonb_build_object('recorded_at',original); end if;
  if action in ('location','incident') and ((body->>'latitude')::numeric not between -90 and 90 or (body->>'longitude')::numeric not between -180 and 180 or (body?'latitude')<>(body?'longitude')) then raise exception 'Enter both valid coordinates'; end if;
  if action='observation' then
   if (p->>'heart_rate')::integer not between 0 and 350 or (p->>'respiratory_rate')::integer not between 0 and 100
    or (p->>'systolic_bp')::integer not between 0 and 350 or (p->>'diastolic_bp')::integer not between 0 and 250
    or (p->>'spo2')::numeric not between 0 and 100 or (p->>'temperature')::numeric not between 20 and 50 or (p->>'gcs')::integer not between 3 and 15 then raise exception 'Check observation values and units'; end if;
   if not (body ?| array['heart_rate','respiratory_rate','systolic_bp','diastolic_bp','spo2','temperature','gcs']) then raise exception 'Enter at least one observation'; end if;
  end if;
  -- Only nonclinical catalog records may be edited. Clinical corrections are new entries.
  rid:=nullif(p->>'id','')::bigint;
  if rid is not null then
   if action not in ('unit','member','facility') or not a then raise exception 'This record is append only'; end if;
   execute format('select to_jsonb(t) from public.corvia_ws6_%I t where hospital_id=$1 and %I=$2 for update',tbl,pk) into old using h,rid;
   if old is null then raise exception 'Record not found'; end if;
   select string_agg(format('%I=x.%I',key,key),',') into target from jsonb_object_keys(body) key where key<>'hospital_id';
   execute format('update public.corvia_ws6_%I t set %s from jsonb_populate_record(null::public.corvia_ws6_%I,$1) x where t.hospital_id=$2 and t.%I=$3 returning to_jsonb(t)',tbl,target,tbl,pk) into result using body,h,rid;
  else result:=public.corvia_ems_insert('corvia_ws6_'||tbl,pk,body); rid:=(result->>pk)::bigint; end if;
  if action='patient' then insert into public.corvia_ws6_incident_patients(hospital_id,incident_id,patient_id) values(h,i,rid); end if;
  if action='location' and body->>'location_type'='Scene' then
   update public.corvia_ws6_incidents_actual set latitude=coalesce((body->>'latitude')::numeric,latitude),longitude=coalesce((body->>'longitude')::numeric,longitude),scene_address=coalesce(body->>'address',scene_address) where hospital_id=h and incident_id=i;
  elsif action='location' and body->>'location_type'='Crew' then
   update public.corvia_ws6_units_actual set latitude=(body->>'latitude')::numeric,longitude=(body->>'longitude')::numeric,location_updated_at=original where hospital_id=h and unit_id in (select cc.unit_id from public.corvia_ws6_crews cc join public.corvia_ws6_incident_assignments_actual aa on aa.crew_id=cc.crew_id where aa.hospital_id=h and aa.incident_id=i and aa.is_active);
  end if;
  if action='incident' then i:=rid; end if;
  if action in ('observation','note','treatment') then
   insert into public.corvia_ws6_offline_sync_queue(hospital_id,user_id,incident_id,entity_type,entity_id,operation_type,original_timestamp,queue_status,last_attempt_at)
   values(h,m,i,action,rid,'Create',original,'Sent',now());
   insert into public.corvia_ws6_treatment_timeline(hospital_id,incident_id,patient_id,event_type,event_description,event_datetime,recorded_by)
   values(h,i,pid,action,case action when 'note' then left(p->>'note_text',2000) when 'treatment' then p->>'treatment_type' else 'Observations recorded' end,original,m);
  end if;
  result:=jsonb_build_object('id',rid);

 elsif action='shift' then
  if not a then raise exception 'Administrator access required'; end if;
  member:=(p->>'member_id')::bigint;unit:=(p->>'unit_id')::bigint;
  if not exists(select 1 from public.corvia_ws6_ems_members where member_id=member and hospital_id=h and is_active and verification_status='verified' and verification_expiry_date>=current_date) then raise exception 'Select verified staff with current credentials'; end if;
  if not exists(select 1 from public.corvia_ws6_units_actual where unit_id=unit and hospital_id=h and is_active and status='Available') then raise exception 'Unit is not available'; end if;
  if p->>'start_datetime' is null or p->>'end_datetime' is null or (p->>'start_datetime')::timestamptz>now() or (p->>'end_datetime')::timestamptz<=now() or (p->>'end_datetime')::timestamptz>(p->>'start_datetime')::timestamptz+interval '24 hours' then raise exception 'Active shift must include now and last no more than 24 hours'; end if;
  if exists(select 1 from public.corvia_ws6_crew_members_actual cm join public.corvia_ws6_crews cc using(crew_id) where cm.member_id=member and cm.is_active and cc.crew_status='Active' and cc.end_datetime>now()) then raise exception 'Member already belongs to an active crew'; end if;
  if exists(select 1 from public.corvia_ws6_shifts_actual where hospital_id=h and shift_status='Active' and end_datetime>now() and (member_id=member or unit_id=unit)) then raise exception 'Member or unit already has an active shift'; end if;
  insert into public.corvia_ws6_shifts_actual(hospital_id,member_id,unit_id,start_datetime,end_datetime,shift_status,verified_at)
  values(h,member,unit,(p->>'start_datetime')::timestamptz,(p->>'end_datetime')::timestamptz,'Active',now()) returning shift_id into rid;
  insert into public.corvia_ws6_crews(hospital_id,crew_code,unit_id,shift_id,start_datetime,end_datetime)
  values(h,'CREW-'||rid,unit,rid,(p->>'start_datetime')::timestamptz,(p->>'end_datetime')::timestamptz) returning crew_id into crew;
  insert into public.corvia_ws6_crew_members_actual(hospital_id,crew_id,member_id,crew_role) values(h,crew,member,'Lead paramedic');
  update public.corvia_ws6_units_actual set readiness_status='ready',availability_revision=availability_revision+1 where unit_id=unit and hospital_id=h;
  result:=jsonb_build_object('id',rid,'crew_id',crew);
 elsif action='crew_member' then
  if not a then raise exception 'Administrator access required'; end if;
  member:=(p->>'member_id')::bigint;crew:=(p->>'crew_id')::bigint;
  if not exists(select 1 from public.corvia_ws6_crews where hospital_id=h and crew_id=crew and crew_status='Active' and end_datetime>now()) then raise exception 'Crew is not active'; end if;
  if not exists(select 1 from public.corvia_ws6_ems_members where hospital_id=h and member_id=member and is_active and verification_status='verified' and verification_expiry_date>=current_date) then raise exception 'Member credentials are not current'; end if;
  if exists(select 1 from public.corvia_ws6_crew_members_actual cm join public.corvia_ws6_crews c using(crew_id) where cm.member_id=member and cm.is_active and c.crew_status='Active' and c.end_datetime>now()) then raise exception 'Member already belongs to an active crew'; end if;
  insert into public.corvia_ws6_crew_members_actual(hospital_id,crew_id,member_id,crew_role) values(h,crew,member,coalesce(nullif(p->>'crew_role',''),'Paramedic')) returning crew_member_id into rid;
  result:=jsonb_build_object('id',rid);
 elsif action='end_shift' then
  if not a then raise exception 'Administrator access required'; end if;
  rid:=(p->>'shift_id')::bigint;
  select * into c from public.corvia_ws6_crews where hospital_id=h and shift_id=rid and crew_status='Active';
  if not found then raise exception 'Active shift not found'; end if;
  if exists(select 1 from public.corvia_ws6_incident_assignments_actual where hospital_id=h and crew_id=c.crew_id and is_active) then raise exception 'Complete or reassign the active incident first'; end if;
  update public.corvia_ws6_shifts_actual set shift_status='Completed',end_datetime=greatest(now(),start_datetime+interval '1 second') where hospital_id=h and shift_id=rid;
  update public.corvia_ws6_crews set crew_status='Off Duty',end_datetime=greatest(now(),start_datetime+interval '1 second') where crew_id=c.crew_id;
  update public.corvia_ws6_crew_members_actual set is_active=false,left_datetime=now() where crew_id=c.crew_id;
  update public.corvia_ws6_units_actual set readiness_status='off_duty',availability_revision=availability_revision+1 where unit_id=c.unit_id and hospital_id=h;
  result:=jsonb_build_object('id',rid);
 elsif action='unit_status' then
  if not a then raise exception 'Administrator access required'; end if;
  unit:=(p->>'unit_id')::bigint;target:=p->>'status';
  if target not in ('idle','maintenance','off_duty','ready') or coalesce(length(trim(p->>'reason')),0)<3 then raise exception 'Choose a status and give a reason'; end if;
  if not exists(select 1 from public.corvia_ws6_units_actual where hospital_id=h and unit_id=unit and status<>'Assigned' and availability_revision=(p->>'unit_revision')::bigint) then raise exception 'Unit is assigned or changed. Refresh first.'; end if;
  update public.corvia_ws6_units_actual set readiness_status=target,status=case when target='maintenance' then 'Out of Service' else 'Available' end,availability_revision=availability_revision+1 where hospital_id=h and unit_id=unit;
  result:=jsonb_build_object('id',unit);
 elsif action='assign' then
  if not a or i is null then raise exception 'Administrator and incident required'; end if;
  crew:=(p->>'crew_id')::bigint;
  if incident.status not in ('Dispatched','Accepted','En Route','On Scene') then raise exception 'Cannot change crew during transport or after handover'; end if;
  select c1.* into c from public.corvia_ws6_crews c1 join public.corvia_ws6_shifts_actual sh on sh.shift_id=c1.shift_id and sh.hospital_id=h
  join public.corvia_ws6_units_actual u on u.unit_id=c1.unit_id and u.hospital_id=h
  where c1.hospital_id=h and c1.crew_id=crew and c1.crew_status='Active' and c1.start_datetime<=now() and c1.end_datetime>now()
   and sh.shift_status='Active' and sh.start_datetime<=now() and sh.end_datetime>now()
   and u.is_active and u.status='Available' and u.readiness_status in ('idle','ready');
  if not found then raise exception 'Crew, shift or vehicle is not available'; end if;
  if not exists(select 1 from public.corvia_ws6_crew_members_actual where hospital_id=h and crew_id=crew and is_active)
   or exists(select 1 from public.corvia_ws6_crew_members_actual cm join public.corvia_ws6_ems_members em on em.member_id=cm.member_id where cm.hospital_id=h and cm.crew_id=crew and cm.is_active and (em.hospital_id<>h or not em.is_active or em.verification_status<>'verified' or em.verification_expiry_date is null or em.verification_expiry_date<current_date)) then raise exception 'All crew credentials must be current'; end if;
  if exists(select 1 from public.corvia_ws6_incident_assignments_actual where hospital_id=h and crew_id=crew and is_active) then raise exception 'Crew already assigned'; end if;
  if exists(select 1 from public.corvia_ws6_incident_assignments_actual where hospital_id=h and incident_id=i and is_active) then
   if coalesce(length(trim(p->>'reason')),0)<3 then raise exception 'Give a reassignment reason'; end if;
   update public.corvia_ws6_units_actual set status='Available',readiness_status='ready',availability_revision=availability_revision+1 where hospital_id=h and unit_id in (select cc.unit_id from public.corvia_ws6_crews cc join public.corvia_ws6_incident_assignments_actual aa on aa.crew_id=cc.crew_id where aa.incident_id=i and aa.is_active);
   update public.corvia_ws6_incident_assignments_actual set is_active=false,assignment_status='Declined' where hospital_id=h and incident_id=i and is_active;
  end if;
  insert into public.corvia_ws6_incident_assignments_actual(hospital_id,incident_id,crew_id,assigned_by) values(h,i,crew,m) returning assignment_id into rid;
  update public.corvia_ws6_units_actual set status='Assigned',readiness_status='ready',availability_revision=availability_revision+1 where hospital_id=h and unit_id=c.unit_id;
  update public.corvia_ws6_incidents_actual set status='Dispatched',assigned_datetime=now() where hospital_id=h and incident_id=i;
  result:=jsonb_build_object('id',rid);
 elsif action='decline' then
  if i is null or incident.status<>'Dispatched' or coalesce(length(trim(p->>'reason')),0)<3 then raise exception 'Only a newly dispatched assignment can be declined; give a reason'; end if;
  select aa.assignment_id,cc.unit_id into assignment,unit from public.corvia_ws6_incident_assignments_actual aa join public.corvia_ws6_crews cc on cc.crew_id=aa.crew_id where aa.hospital_id=h and aa.incident_id=i and aa.is_active;
  if assignment is null then raise exception 'No active assignment'; end if;
  update public.corvia_ws6_incident_assignments_actual set is_active=false,assignment_status='Declined' where assignment_id=assignment;
  update public.corvia_ws6_units_actual set status='Available',readiness_status='ready',availability_revision=availability_revision+1 where hospital_id=h and unit_id=unit;
  result:=jsonb_build_object('declined',true);
 elsif action='status' then
  target:=p->>'status';
  next_status:=case incident.status when 'Dispatched' then 'Accepted' when 'Accepted' then 'En Route' when 'En Route' then 'On Scene' when 'On Scene' then 'Transporting' when 'Transporting' then 'At Hospital' when 'At Hospital' then 'Handed Over' when 'Handed Over' then 'Closed' end;
  if i is null or target is distinct from next_status then raise exception 'Invalid incident status transition'; end if;
  select aa.assignment_id,cc.unit_id into assignment,unit from public.corvia_ws6_incident_assignments_actual aa join public.corvia_ws6_crews cc on cc.crew_id=aa.crew_id where aa.hospital_id=h and aa.incident_id=i and aa.is_active;
  if assignment is null then raise exception 'Assign an available crew first'; end if;
  if not exists(select 1 from public.corvia_ws6_incident_assignments_actual aa join public.corvia_ws6_crews cc on cc.crew_id=aa.crew_id join public.corvia_ws6_shifts_actual sh on sh.shift_id=cc.shift_id where aa.assignment_id=assignment and cc.crew_status='Active' and cc.start_datetime<=now() and cc.end_datetime>now() and sh.shift_status='Active' and sh.start_datetime<=now() and sh.end_datetime>now()) then raise exception 'Crew shift is no longer active'; end if;
  if exists(select 1 from public.corvia_ws6_incident_assignments_actual aa join public.corvia_ws6_crew_members_actual cm on cm.crew_id=aa.crew_id join public.corvia_ws6_ems_members em on em.member_id=cm.member_id where aa.assignment_id=assignment and cm.is_active and (not em.is_active or em.verification_status<>'verified' or em.verification_expiry_date is null or em.verification_expiry_date<current_date)) then raise exception 'Crew credentials need review'; end if;
  if target in ('Handed Over','Closed') and (not exists(select 1 from public.corvia_ws6_incident_patients where incident_id=i and hospital_id=h and is_active) or exists(select 1 from public.corvia_ws6_incident_patients ip where ip.incident_id=i and ip.hospital_id=h and ip.is_active and not exists(select 1 from public.corvia_ws6_handovers ho where ho.incident_id=i and ho.patient_id=ip.patient_id and ho.hospital_id=h and ho.acknowledged))) then raise exception 'Each assigned patient needs an acknowledged handover'; end if;
  update public.corvia_ws6_incidents_actual set status=target,closed_datetime=case when target='Closed' then now() end where hospital_id=h and incident_id=i;
  if target='Accepted' then update public.corvia_ws6_incident_assignments_actual set assignment_status='Accepted',accepted_datetime=now() where assignment_id=assignment; end if;
  if target='Closed' then update public.corvia_ws6_incident_assignments_actual set assignment_status='Completed',is_active=false where assignment_id=assignment; end if;
  update public.corvia_ws6_units_actual set readiness_status=case target when 'En Route' then 'en_route' when 'On Scene' then 'on_scene' when 'Transporting' then 'transporting' when 'Closed' then 'ready' else readiness_status end,status=case when target='Closed' then 'Available' else status end,availability_revision=availability_revision+1 where hospital_id=h and unit_id=unit;
  insert into public.corvia_ws6_incident_status_history(hospital_id,incident_id,status,status_datetime,sender_id,sync_status,sent_at) values(h,i,target,original,m,'Sent',now());
  result:=jsonb_build_object('status',target);
 elsif action='patient_link' then
  if i is null then raise exception 'Select an incident'; end if;
  -- Exact number/ID lookup within this hospital. No browsing unrelated clinical records.
  if coalesce(length(trim(p->>'identifier')),0)<3 then raise exception 'Enter the exact patient number or identity number'; end if;
  if (select count(*) from public.corvia_ws6_patients_actual where hospital_id=h and (patient_number=p->>'identifier' or identity_number=p->>'identifier'))>1 then raise exception 'More than one patient matches. Use the unique patient number.'; end if;
  select patient_id into rid from public.corvia_ws6_patients_actual where hospital_id=h and (patient_number=p->>'identifier' or identity_number=p->>'identifier');
  if rid is null then
   -- Adapt existing hospital patients into an EMS snapshot only after an exact
   -- hospital-scoped lookup; do not alter the hospital's master patient record.
   select count(*),min(pp.id::text) into member,target from public.patients pp
    left join public.profiles pr on pr.user_id=pp.profile_id
    where pp.hospital_id=h and (pp.patient_number=p->>'identifier'
     or coalesce(to_jsonb(pp)->>'id_number',to_jsonb(pr)->>'id_number')=p->>'identifier');
   if member>1 then raise exception 'More than one patient matches. Use the unique patient number.'; end if;
   if member=1 then
    select jsonb_build_object('hospital_id',h,'source_patient_uuid',pp.id,'patient_number',pp.patient_number,
      'first_name',coalesce(nullif(to_jsonb(pp)->>'first_name',''),nullif(to_jsonb(pr)->>'first_name',''),'Unknown'),
      'last_name',coalesce(nullif(to_jsonb(pp)->>'surname',''),to_jsonb(pr)->>'surname'),
      'identity_number',coalesce(to_jsonb(pp)->>'id_number',to_jsonb(pr)->>'id_number'))
    into body from public.patients pp left join public.profiles pr on pr.user_id=pp.profile_id where pp.id=target::uuid and pp.hospital_id=h;
    result:=public.corvia_ems_insert('corvia_ws6_patients_actual','patient_id',body);rid:=(result->>'patient_id')::bigint;
   end if;
  end if;
  if rid is null then raise exception 'Patient not found. Capture the patient details first.'; end if;
  insert into public.corvia_ws6_incident_patients(hospital_id,incident_id,patient_id) values(h,i,rid) on conflict(incident_id,patient_id) do nothing;
  result:=jsonb_build_object('id',rid);
 elsif action='qr' then
  if pid is null then raise exception 'Select the assigned patient first'; end if;
  target:=p->>'code';
  if target like 'CORVIA_EMS_PATIENT|v=1|patient_number=%' then target:=substr(target,length('CORVIA_EMS_PATIENT|v=1|patient_number=')+1); end if;
  select patient_id into scanned from public.corvia_ws6_patients_actual where hospital_id=h and patient_number=target;
  if target like 'CORVIA_PATIENT|v=1|patient_id=%' or target like 'CORVIA_EMERGENCY|v=1|patient_id=%' then
    select patient_id into scanned from public.corvia_ws6_patients_actual where hospital_id=h and source_patient_uuid::text=split_part(target,'patient_id=',2);
  end if;
  matched:=coalesce(scanned=pid,false);
  insert into public.corvia_ws6_patient_qr_confirmations(hospital_id,incident_id,assigned_patient_id,scanned_patient_id,scanned_by,match_status)
  values(h,i,pid,case when matched then scanned end,m,case when matched then 'Match' else 'Mismatch' end) returning qr_confirmation_id into rid;
  update public.corvia_ws6_incident_patients set confirmation_status=case when matched then 'Confirmed' else 'Mismatch' end,confirmed_at=case when matched then now() end,confirmed_by=case when matched then m end where hospital_id=h and incident_id=i and patient_id=pid;
  result:=jsonb_build_object('id',rid,'match',matched);
 elsif action='qr_acknowledge' then
  update public.corvia_ws6_patient_qr_confirmations set acknowledged=true,warning_displayed=true where hospital_id=h and incident_id=i and assigned_patient_id=pid and qr_confirmation_id=(p->>'id')::bigint and match_status='Mismatch' returning qr_confirmation_id into rid;
  if rid is null then raise exception 'Mismatch not found'; end if;
  result:=jsonb_build_object('id',rid);
 elsif action='handover' then
  if pid is null or incident.status<>'At Hospital' then raise exception 'Patient must be at hospital before handover'; end if;
  if not exists(select 1 from public.corvia_ws6_receiving_facilities where hospital_id=h and facility_id=(p->>'facility_id')::bigint and is_active) then raise exception 'Select an active receiving facility'; end if;
  if coalesce(length(trim(p->>'receiver_name')),0)<2 or coalesce(length(trim(p->>'handover_summary')),0)<5 then raise exception 'Receiver and clinical summary required'; end if;
  insert into public.corvia_ws6_handovers(hospital_id,incident_id,patient_id,facility_id,receiver_name,receiver_role,handover_summary,handover_datetime,completed_by,notes)
  values(h,i,pid,(p->>'facility_id')::bigint,p->>'receiver_name',p->>'receiver_role',p->>'handover_summary',original,m,p->>'notes') returning handover_id into rid;
  result:=jsonb_build_object('id',rid);
 elsif action='handover_acknowledge' then
  if coalesce(length(trim(p->>'reason')),0)<5 then raise exception 'Record how the receiver acknowledged the handover'; end if;
  update public.corvia_ws6_handovers set acknowledged=true,acknowledged_datetime=now(),notes=concat_ws(E'\n',notes,p->>'reason') where hospital_id=h and incident_id=i and patient_id=pid and handover_id=(p->>'id')::bigint and not acknowledged returning handover_id into rid;
  if rid is null then raise exception 'Pending handover not found'; end if;
  result:=jsonb_build_object('id',rid);
 elsif action='preferences' then
  target:=coalesce(p->>'navigation_app','none');
  if target<>'none' and not exists(select 1 from public.corvia_ems_navigation where hospital_id=h and app=target and approved) then raise exception 'Navigation application is not approved'; end if;
  insert into public.corvia_ems_preferences(hospital_id,actor,critical_alerts,navigation_app) values(h,auth.uid(),coalesce((p->>'critical_alerts')::boolean,true),target)
  on conflict(hospital_id,actor) do update set critical_alerts=excluded.critical_alerts,navigation_app=excluded.navigation_app;
  if m is not null then insert into public.corvia_ws6_notification_settings(hospital_id,user_id,allow_critical_alerts) values(h,m,coalesce((p->>'critical_alerts')::boolean,true)) on conflict(hospital_id,user_id) do update set allow_critical_alerts=excluded.allow_critical_alerts,show_patient_information=false,show_incident_details=false,updated_datetime=now(); end if;
  result:='{"saved":true}';
 elsif action='navigation' then
  if not a then raise exception 'Administrator access required'; end if;
  insert into public.corvia_ems_navigation(hospital_id,app,approved) values(h,p->>'app',(p->>'approved')::boolean) on conflict(hospital_id,app) do update set approved=excluded.approved;
  result:='{"saved":true}';
 elsif action='session_revoke' then
  update public.corvia_ws6_device_sessions set session_status='Revoked' where hospital_id=h and auth_user_id=auth.uid() and session_id=(p->>'id')::bigint returning session_id into rid;
  if rid is null then raise exception 'Session not found'; end if;
  result:=jsonb_build_object('id',rid);
 else raise exception 'Unknown action'; end if;

 if i is not null then update public.corvia_ws6_incidents_actual set revision=revision+1 where hospital_id=h and incident_id=i; end if;
 insert into public.corvia_ws6_audit_logs(hospital_id,user_id,actor_auth_user_id,incident_id,patient_id,action_type,entity_type,entity_id,old_value,new_value,reason)
 values(h,m,auth.uid(),i,pid,action,coalesce(tbl,action),rid,old,result,left(p->>'reason',1000));
 insert into public.corvia_ems_receipts(hospital_id,actor,operation_id,action,payload,result) values(h,auth.uid(),op,action,p,result);
 return result;
end; $$;

-- Close the earlier prototype RPC surface and direct table access. All clients
-- must use the scoped gateway. Do not relax these grants for SQL Editor testing.
do $$ declare f record;t record; begin
 for f in select p.oid::regprocedure signature from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and (p.proname like 'corvia_ws6_%' or p.proname like 'corvia_ems_%') loop
  execute format('revoke all on function %s from public,anon,authenticated',f.signature);
 end loop;
 for t in select tablename from pg_tables where schemaname='public' and (tablename like 'corvia_ws6_%' or tablename like 'corvia_ems_%') loop
  execute format('alter table public.%I enable row level security',t.tablename);
  execute format('revoke all on public.%I from public,anon,authenticated',t.tablename);
 end loop;
end $$;
grant execute on function public.corvia_ems_access() to authenticated;
grant execute on function public.corvia_ems_open(uuid,text) to authenticated;
grant execute on function public.corvia_ems_workspace(uuid,uuid,bigint) to authenticated;
grant execute on function public.corvia_ems_command(uuid,uuid,uuid,text,jsonb) to authenticated;
notify pgrst,'reload schema';
commit;
