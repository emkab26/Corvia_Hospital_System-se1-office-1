-- Apply after Batch 49.
-- Returns patient display details inside the authorised nurse queue so the
-- client does not need direct RLS-sensitive reads from patients or profiles.
begin;

create or replace function public.corvia_nurse_lab_collection_queue_v3()
returns table (
  lab_result_id uuid,
  patient_id uuid,
  patient_name text,
  patient_number text,
  test_name text,
  status text,
  created_at timestamptz,
  lab_organization_id uuid,
  lab_name text,
  lab_type text
)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_auth_user_id uuid := auth.uid();
  v_hospital_id uuid;
begin
  if v_auth_user_id is null then
    raise exception using
      errcode = '42501',
      message = 'You must be signed in as a nurse.';
  end if;

  select nurse.hospital_id
  into v_hospital_id
  from public.profiles profile
  join public.hospital_nurses nurse
    on nurse.profile_id in (profile.id, profile.user_id)
    and nurse.is_active is not false
  where profile.user_id = v_auth_user_id
    and profile.is_active is not false
  order by (nurse.nurse_user_id = v_auth_user_id) desc
  limit 1;

  if v_hospital_id is null then
    raise exception using
      errcode = '42501',
      message = 'No active hospital nurse profile is linked to this account.';
  end if;

  return query
  select
    lab_result.id,
    lab_result.patient_id,
    coalesce(
      nullif(
        trim(concat_ws(
          ' ',
          coalesce(
            nullif(trim(patient.first_name), ''),
            nullif(trim(patient_profile.first_name), '')
          ),
          coalesce(
            nullif(trim(patient.surname), ''),
            nullif(trim(patient_profile.surname), '')
          )
        )),
        ''
      ),
      'Patient record'
    ),
    coalesce(
      nullif(trim(patient.patient_number), ''),
      lab_result.patient_id::text
    ),
    coalesce(nullif(trim(lab_result.test_name), ''), 'Laboratory test'),
    coalesce(lab_result.status, 'pending'),
    lab_result.created_at,
    organization.id,
    organization.name,
    organization.lab_type
  from public.lab_results lab_result
  join public.patients patient
    on patient.id = lab_result.patient_id
  left join public.profiles patient_profile
    on patient_profile.user_id = patient.profile_id
  join public.lab_organizations organization
    on organization.id = lab_result.lab_organization_id
  where lab_result.hospital_id = v_hospital_id
    and (
      organization.lab_type = 'private'
      or organization.hospital_id = v_hospital_id
    )
    and lower(replace(replace(trim(coalesce(lab_result.status, 'pending')), '-', '_'), ' ', '_'))
      in ('pending', 'ordered', 'requested', 'awaiting', 'scheduled')
    and not exists (
      select 1
      from public.lab_specimen_container_tests specimen_test
      join public.lab_specimen_containers specimen
        on specimen.id = specimen_test.container_id
      where specimen_test.lab_result_id = lab_result.id
        and specimen.status <> 'rejected'
    )
  order by lab_result.created_at asc;
end;
$$;

revoke all on function public.corvia_nurse_lab_collection_queue_v3()
  from public, anon;
grant execute on function public.corvia_nurse_lab_collection_queue_v3()
  to authenticated;

notify pgrst, 'reload schema';
commit;
