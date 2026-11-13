-- Nurse read model. Apply this whole file before using the updated nurse pages.
-- Additive: existing RPCs, table permissions and older clients are unchanged.
begin;

create or replace function public.corvia_nurse_workspace_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $function$
declare
  v_user_id uuid := auth.uid();
  v_context jsonb;
  v_hospital_id uuid;
  v_workspace jsonb;
begin
  if v_user_id is null then
    raise exception using errcode = '42501', message = 'Your Corvia session has expired.';
  end if;

  -- Use the same hospital selection as the dashboard and shift service.
  v_context := public.corvia_current_nurse_context();
  if not coalesce((v_context->>'signed_in')::boolean, false)
     or not coalesce((v_context->>'profile_found')::boolean, false)
     or not coalesce((v_context->>'is_nurse')::boolean, false)
     or not coalesce((v_context->>'is_active')::boolean, false)
     or nullif(v_context->>'nurse_user_id', '')::uuid is distinct from v_user_id then
    raise exception using errcode = '42501', message = 'An active nurse account is required.';
  end if;

  v_hospital_id := nullif(v_context->>'hospital_id', '')::uuid;
  if v_hospital_id is null or not exists (
    select 1
    from public.hospital_nurses nurse
    join public.profiles profile on profile.user_id = v_user_id
    join public.hospitals hospital on hospital.id = nurse.hospital_id
    where nurse.hospital_id = v_hospital_id
      and nurse.is_active is true
      and profile.is_active is distinct from false
      and hospital.is_active is distinct from false
      and (nurse.profile_id in (profile.id, profile.user_id)
           or nurse.nurse_user_id = v_user_id)
  ) then
    raise exception using errcode = '42501',
      message = 'This nurse account is not linked to an active hospital.';
  end if;

  with active_assignments as (
    select assignment.*
    from public.nurse_patient_assignments assignment
    where assignment.hospital_id = v_hospital_id
      and assignment.nurse_user_id = v_user_id
      and assignment.status = 'active'
      and assignment.start_at <= now()
      and (assignment.end_at is null or assignment.end_at > now())
  ), scoped_tasks as (
    select task.*
    from public.nursing_tasks task
    where task.assigned_nurse_user_id = v_user_id
      and (task.hospital_id = v_hospital_id
           or (task.hospital_id is null and exists (
             select 1 from active_assignments assignment
             where assignment.patient_id = task.patient_id
           )))
  ), patient_ids as (
    select patient_id from active_assignments
    union
    select patient_id from scoped_tasks where patient_id is not null
  ), patient_details as (
    select patient.id,
      jsonb_build_object(
        'id', patient.id,
        'profile_id', patient.profile_id,
        'patient_number', patient.patient_number,
        'first_name', coalesce(nullif(trim(patient.first_name), ''), nullif(trim(profile.first_name), ''), ''),
        'surname', coalesce(nullif(trim(patient.surname), ''), nullif(trim(profile.surname), ''), ''),
        'phone', coalesce(nullif(trim(patient.phone), ''), nullif(trim(profile.phone_number), ''), nullif(trim(profile.phone), ''), ''),
        'email', coalesce(nullif(trim(patient.email), ''), nullif(trim(profile.email), ''), ''),
        'id_number', profile.id_number,
        'date_of_birth', coalesce(patient.date_of_birth, profile.date_of_birth),
        'gender', patient.gender,
        'medical_aid_provider', coalesce(nullif(trim(provider.name), ''), nullif(trim(patient.medical_aid_provider), ''), ''),
        'medical_aid_member_number', patient.medical_aid_member_number,
        'medical_aid_plan', patient.medical_aid_plan
      ) as details
    from patient_ids allowed
    join public.patients patient on patient.id = allowed.patient_id
    -- Canonical FK: patients.profile_id references profiles.user_id, not profiles.id.
    left join public.profiles profile on profile.user_id = patient.profile_id
    left join public.medical_aid_providers provider on provider.id = patient.medical_aid_provider_id
  )
  select jsonb_build_object(
    'context', v_context,
    'assignments', coalesce((
      select jsonb_agg(to_jsonb(assignment) order by assignment.assigned_at desc, assignment.id)
      from active_assignments assignment
    ), '[]'::jsonb),
    'tasks', coalesce((
      select jsonb_agg(to_jsonb(task) order by task.created_at desc, task.id)
      from scoped_tasks task
    ), '[]'::jsonb),
    'patients', coalesce((
      select jsonb_agg(patient.details order by patient.id) from patient_details patient
    ), '[]'::jsonb),
    'wards', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', ward.id, 'name', ward.name, 'code', ward.code,
        'floor_name', floor.name, 'building_name', building.name
      ) order by ward.name, building.name, floor.name, ward.id)
      from public.hospital_wards ward
      join public.hospital_floors floor
        on floor.id = ward.floor_id and floor.hospital_id = v_hospital_id
          and floor.building_id = ward.building_id and floor.is_active is true
      join public.hospital_buildings building
        on building.id = ward.building_id and building.hospital_id = v_hospital_id
          and building.is_active is true
      where ward.hospital_id = v_hospital_id and ward.is_active is true
    ), '[]'::jsonb)
  ) into v_workspace;

  return v_workspace;
end;
$function$;

revoke all on function public.corvia_nurse_workspace_v1() from public, anon;
grant execute on function public.corvia_nurse_workspace_v1() to authenticated;
comment on function public.corvia_nurse_workspace_v1() is
  'Read-only nurse context, assigned/task patient demographics and active hospital wards. No caller-supplied patient or hospital IDs.';

notify pgrst, 'reload schema';
commit;
