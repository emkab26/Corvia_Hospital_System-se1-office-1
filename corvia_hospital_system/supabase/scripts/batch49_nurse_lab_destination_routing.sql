-- Apply after Batch 48.
-- Adds destination-aware nurse collection while preserving the original queue
-- and collection RPC signatures used by older clients.
begin;

create or replace function public.corvia_nurse_lab_collection_queue_v2()
returns table (
  lab_result_id uuid,
  patient_id uuid,
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
    coalesce(nullif(trim(lab_result.test_name), ''), 'Laboratory test'),
    coalesce(lab_result.status, 'pending'),
    lab_result.created_at,
    organization.id,
    organization.name,
    organization.lab_type
  from public.lab_results lab_result
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

-- Keep the established collection signature, but persist and return the
-- destination selected by the ordering doctor.
create or replace function public.corvia_nurse_collect_lab_specimen(
  p_lab_result_id uuid,
  p_specimen_type text,
  p_collection_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_auth_user_id uuid := auth.uid();
  v_hospital_id uuid;
  v_lab_result public.lab_results%rowtype;
  v_organization public.lab_organizations%rowtype;
  v_container public.lab_specimen_containers%rowtype;
  v_specimen_type text := trim(coalesce(p_specimen_type, ''));
  v_collection_note text := nullif(trim(coalesce(p_collection_note, '')), '');
  v_status text;
begin
  if v_auth_user_id is null then
    raise exception using
      errcode = '42501',
      message = 'You must be signed in as a nurse.';
  end if;

  if p_lab_result_id is null then
    raise exception using
      errcode = '22004',
      message = 'A laboratory order is required.';
  end if;

  if char_length(v_specimen_type) < 2 or char_length(v_specimen_type) > 120 then
    raise exception using
      errcode = '22023',
      message = 'Select a valid specimen type.';
  end if;

  if v_collection_note is not null and char_length(v_collection_note) > 2000 then
    raise exception using
      errcode = '22001',
      message = 'The collection note is too long.';
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

  select lab_result.*
  into v_lab_result
  from public.lab_results lab_result
  where lab_result.id = p_lab_result_id
    and lab_result.hospital_id = v_hospital_id
  for update;

  if not found then
    raise exception using
      errcode = 'P0002',
      message = 'The laboratory order was not found in your hospital.';
  end if;

  select organization.*
  into v_organization
  from public.lab_organizations organization
  where organization.id = v_lab_result.lab_organization_id
    and (
      organization.lab_type = 'private'
      or organization.hospital_id = v_hospital_id
    )
  limit 1;

  if not found then
    raise exception using
      errcode = 'P0002',
      message = 'This laboratory order has no valid receiving laboratory.';
  end if;

  v_status := lower(
    replace(
      replace(trim(coalesce(v_lab_result.status, 'pending')), '-', '_'),
      ' ',
      '_'
    )
  );
  if v_status not in ('pending', 'ordered', 'requested', 'awaiting', 'scheduled') then
    raise exception using
      errcode = 'P0001',
      message = 'This laboratory order is not awaiting specimen collection.';
  end if;

  if exists (
    select 1
    from public.lab_specimen_container_tests specimen_test
    join public.lab_specimen_containers specimen
      on specimen.id = specimen_test.container_id
    where specimen_test.lab_result_id = v_lab_result.id
      and specimen.status <> 'rejected'
  ) then
    raise exception using
      errcode = '23505',
      message = 'This laboratory order already has an active specimen label.';
  end if;

  insert into public.lab_specimen_containers (
    container_code,
    hospital_id,
    patient_id,
    specimen_type,
    status,
    collected_by_nurse_user_id,
    collection_note,
    lab_organization_id
  ) values (
    'CVS-' || to_char(now() at time zone 'utc', 'YYYYMMDD') || '-' ||
      upper(substring(replace(gen_random_uuid()::text, '-', '') from 1 for 10)),
    v_hospital_id,
    v_lab_result.patient_id,
    v_specimen_type,
    'collected',
    v_auth_user_id,
    v_collection_note,
    v_organization.id
  )
  returning * into v_container;

  insert into public.lab_specimen_container_tests (
    container_id,
    lab_result_id
  ) values (
    v_container.id,
    v_lab_result.id
  );

  update public.lab_results
  set status = 'sample_collected'
  where id = v_lab_result.id;

  return jsonb_build_object(
    'container_id', v_container.id,
    'container_code', v_container.container_code,
    'specimen_type', v_container.specimen_type,
    'lab_result_id', v_lab_result.id,
    'patient_id', v_lab_result.patient_id,
    'lab_organization_id', v_organization.id,
    'lab_name', v_organization.name,
    'lab_type', v_organization.lab_type,
    'status', 'sample_collected'
  );
end;
$$;

revoke all on function public.corvia_nurse_lab_collection_queue_v2() from public, anon;
grant execute on function public.corvia_nurse_lab_collection_queue_v2() to authenticated;

revoke all on function public.corvia_nurse_collect_lab_specimen(uuid, text, text) from public, anon;
grant execute on function public.corvia_nurse_collect_lab_specimen(uuid, text, text) to authenticated;

notify pgrst, 'reload schema';
commit;
