-- Apply after Batch 50.
-- Supports multiple samples per order and an optional transport bag.
-- Internal collections use Corvia QR labels. Outsourced collections store only
-- the external laboratory's supplied label references.
begin;

create table if not exists public.lab_specimen_collections (
  id uuid primary key default gen_random_uuid(),
  lab_result_id uuid not null references public.lab_results(id) on delete restrict,
  hospital_id uuid not null references public.hospitals(id) on delete restrict,
  patient_id uuid not null references public.patients(id) on delete restrict,
  lab_organization_id uuid not null references public.lab_organizations(id) on delete restrict,
  label_source text not null check (label_source in ('corvia', 'external')),
  sample_count integer not null check (sample_count between 1 and 10),
  uses_transport_bag boolean not null default false,
  collection_note text,
  collected_by_nurse_user_id uuid not null references auth.users(id) on delete restrict,
  collected_at timestamptz not null default now(),
  constraint lab_specimen_collections_note_length
    check (collection_note is null or char_length(collection_note) <= 2000)
);

create table if not exists public.lab_specimen_bags (
  id uuid primary key default gen_random_uuid(),
  collection_id uuid not null unique
    references public.lab_specimen_collections(id) on delete restrict,
  bag_code text not null unique,
  hospital_id uuid not null references public.hospitals(id) on delete restrict,
  patient_id uuid not null references public.patients(id) on delete restrict,
  lab_organization_id uuid not null references public.lab_organizations(id) on delete restrict,
  label_source text not null check (label_source in ('corvia', 'external')),
  external_label_reference text,
  created_at timestamptz not null default now(),
  constraint lab_specimen_bags_external_label_check check (
    (label_source = 'corvia' and external_label_reference is null)
    or (
      label_source = 'external'
      and nullif(trim(external_label_reference), '') is not null
      and char_length(external_label_reference) <= 160
    )
  )
);

alter table public.lab_specimen_containers
  add column if not exists collection_id uuid
    references public.lab_specimen_collections(id) on delete restrict;
alter table public.lab_specimen_containers
  add column if not exists bag_id uuid
    references public.lab_specimen_bags(id) on delete restrict;
alter table public.lab_specimen_containers
  add column if not exists label_source text not null default 'corvia';
alter table public.lab_specimen_containers
  add column if not exists external_label_reference text;

alter table public.lab_specimen_containers
  add constraint lab_specimen_containers_label_source_check
  check (label_source in ('corvia', 'external'));
alter table public.lab_specimen_containers
  add constraint lab_specimen_containers_external_label_check
  check (
    (label_source = 'corvia' and external_label_reference is null)
    or (
      label_source = 'external'
      and nullif(trim(external_label_reference), '') is not null
      and char_length(external_label_reference) <= 160
    )
  );

create index if not exists lab_specimen_collections_result_idx
  on public.lab_specimen_collections (lab_result_id, collected_at desc);
create index if not exists lab_specimen_containers_collection_idx
  on public.lab_specimen_containers (collection_id, status);
create index if not exists lab_specimen_containers_bag_idx
  on public.lab_specimen_containers (bag_id, status);
create unique index if not exists lab_specimen_external_label_idx
  on public.lab_specimen_containers (
    lab_organization_id,
    lower(external_label_reference)
  )
  where external_label_reference is not null;
create unique index if not exists lab_specimen_bag_external_label_idx
  on public.lab_specimen_bags (
    lab_organization_id,
    lower(external_label_reference)
  )
  where external_label_reference is not null;

alter table public.lab_specimen_collections enable row level security;
alter table public.lab_specimen_bags enable row level security;

revoke all on table public.lab_specimen_collections
  from public, anon, authenticated;
revoke all on table public.lab_specimen_bags
  from public, anon, authenticated;

create or replace function public.corvia_nurse_collect_lab_specimens(
  p_lab_result_id uuid,
  p_samples jsonb,
  p_use_transport_bag boolean default false,
  p_external_bag_reference text default null,
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
  v_collection public.lab_specimen_collections%rowtype;
  v_bag public.lab_specimen_bags%rowtype;
  v_container public.lab_specimen_containers%rowtype;
  v_samples jsonb := coalesce(p_samples, '[]'::jsonb);
  v_sample jsonb;
  v_sample_count integer;
  v_specimen_type text;
  v_external_reference text;
  v_bag_reference text := nullif(trim(coalesce(p_external_bag_reference, '')), '');
  v_collection_note text := nullif(trim(coalesce(p_collection_note, '')), '');
  v_label_source text;
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

  if jsonb_typeof(v_samples) is distinct from 'array' then
    raise exception using
      errcode = '22023',
      message = 'The specimen samples must be supplied as a list.';
  end if;

  v_sample_count := jsonb_array_length(v_samples);
  if v_sample_count < 1 or v_sample_count > 10 then
    raise exception using
      errcode = '22023',
      message = 'Add between 1 and 10 specimen samples.';
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

  v_label_source := case
    when v_organization.lab_type = 'private' then 'external'
    else 'corvia'
  end;

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
      message = 'This laboratory order already has an active specimen collection.';
  end if;

  for v_sample in
    select sample.value
    from jsonb_array_elements(v_samples) sample(value)
  loop
    v_specimen_type := trim(coalesce(v_sample->>'specimen_type', ''));
    v_external_reference := nullif(
      trim(coalesce(v_sample->>'external_label_reference', '')),
      ''
    );

    if char_length(v_specimen_type) < 2 or char_length(v_specimen_type) > 120 then
      raise exception using
        errcode = '22023',
        message = 'Select a valid specimen type for every sample.';
    end if;

    if v_label_source = 'external'
       and (
         v_external_reference is null
         or char_length(v_external_reference) > 160
       ) then
      raise exception using
        errcode = '22023',
        message = 'Enter the external laboratory label for every sample.';
    end if;
  end loop;

  if v_label_source = 'external' and exists (
    select 1
    from jsonb_array_elements(v_samples) sample(value)
    group by lower(trim(sample.value->>'external_label_reference'))
    having count(*) > 1
  ) then
    raise exception using
      errcode = '22023',
      message = 'Every external sample label must be unique.';
  end if;

  if coalesce(p_use_transport_bag, false)
     and v_label_source = 'external'
     and (
       v_bag_reference is null
       or char_length(v_bag_reference) > 160
     ) then
    raise exception using
      errcode = '22023',
      message = 'Enter the external laboratory label for the transport bag.';
  end if;

  insert into public.lab_specimen_collections (
    lab_result_id,
    hospital_id,
    patient_id,
    lab_organization_id,
    label_source,
    sample_count,
    uses_transport_bag,
    collection_note,
    collected_by_nurse_user_id
  ) values (
    v_lab_result.id,
    v_hospital_id,
    v_lab_result.patient_id,
    v_organization.id,
    v_label_source,
    v_sample_count,
    coalesce(p_use_transport_bag, false),
    v_collection_note,
    v_auth_user_id
  )
  returning * into v_collection;

  if coalesce(p_use_transport_bag, false) then
    insert into public.lab_specimen_bags (
      collection_id,
      bag_code,
      hospital_id,
      patient_id,
      lab_organization_id,
      label_source,
      external_label_reference
    ) values (
      v_collection.id,
      case
        when v_label_source = 'corvia' then
          'CVB-' || to_char(now() at time zone 'utc', 'YYYYMMDD') || '-' ||
            upper(substring(replace(gen_random_uuid()::text, '-', '') from 1 for 10))
        else
          'EXTBAG-' || upper(substring(replace(gen_random_uuid()::text, '-', '') from 1 for 12))
      end,
      v_hospital_id,
      v_lab_result.patient_id,
      v_organization.id,
      v_label_source,
      case when v_label_source = 'external' then v_bag_reference else null end
    )
    returning * into v_bag;
  end if;

  for v_sample in
    select sample.value
    from jsonb_array_elements(v_samples) sample(value)
  loop
    v_specimen_type := trim(v_sample->>'specimen_type');
    v_external_reference := nullif(
      trim(coalesce(v_sample->>'external_label_reference', '')),
      ''
    );

    insert into public.lab_specimen_containers (
      container_code,
      hospital_id,
      patient_id,
      specimen_type,
      status,
      collected_by_nurse_user_id,
      collection_note,
      lab_organization_id,
      collection_id,
      bag_id,
      label_source,
      external_label_reference
    ) values (
      case
        when v_label_source = 'corvia' then
          'CVS-' || to_char(now() at time zone 'utc', 'YYYYMMDD') || '-' ||
            upper(substring(replace(gen_random_uuid()::text, '-', '') from 1 for 10))
        else
          'EXTREC-' || upper(substring(replace(gen_random_uuid()::text, '-', '') from 1 for 12))
      end,
      v_hospital_id,
      v_lab_result.patient_id,
      v_specimen_type,
      'collected',
      v_auth_user_id,
      v_collection_note,
      v_organization.id,
      v_collection.id,
      v_bag.id,
      v_label_source,
      case when v_label_source = 'external' then v_external_reference else null end
    )
    returning * into v_container;

    insert into public.lab_specimen_container_tests (
      container_id,
      lab_result_id
    ) values (
      v_container.id,
      v_lab_result.id
    );
  end loop;

  update public.lab_results
  set status = 'sample_collected'
  where id = v_lab_result.id;

  return jsonb_build_object(
    'collection_id', v_collection.id,
    'lab_result_id', v_lab_result.id,
    'patient_id', v_lab_result.patient_id,
    'lab_organization_id', v_organization.id,
    'lab_name', v_organization.name,
    'lab_type', v_organization.lab_type,
    'label_source', v_label_source,
    'specimens', (
      select jsonb_agg(
        jsonb_build_object(
          'container_id', specimen.id,
          'container_code', specimen.container_code,
          'specimen_type', specimen.specimen_type,
          'label_source', specimen.label_source,
          'external_label_reference', specimen.external_label_reference
        )
        order by specimen.created_at, specimen.id
      )
      from public.lab_specimen_containers specimen
      where specimen.collection_id = v_collection.id
    ),
    'bag', case
      when v_bag.id is null then null
      else jsonb_build_object(
        'bag_id', v_bag.id,
        'bag_code', v_bag.bag_code,
        'label_source', v_bag.label_source,
        'external_label_reference', v_bag.external_label_reference
      )
    end,
    'status', 'sample_collected'
  );
end;
$$;

-- Preserve the original single-sample signature for older internal-lab
-- clients. Outsourced collection requires the new external-label workflow.
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
  v_collection jsonb;
  v_specimen jsonb;
begin
  v_collection := public.corvia_nurse_collect_lab_specimens(
    p_lab_result_id,
    jsonb_build_array(
      jsonb_build_object(
        'specimen_type', p_specimen_type,
        'external_label_reference', null
      )
    ),
    false,
    null,
    p_collection_note
  );

  v_specimen := v_collection->'specimens'->0;
  return v_specimen || jsonb_build_object(
    'lab_result_id', v_collection->>'lab_result_id',
    'patient_id', v_collection->>'patient_id',
    'lab_organization_id', v_collection->>'lab_organization_id',
    'lab_name', v_collection->>'lab_name',
    'lab_type', v_collection->>'lab_type',
    'status', v_collection->>'status'
  );
end;
$$;

create or replace function public.corvia_lab_technician_collection_item(
  p_item_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_context jsonb := public.corvia_current_lab_technician_context();
  v_organization_id uuid := (v_context->>'lab_organization_id')::uuid;
  v_specimen public.lab_specimen_containers%rowtype;
  v_bag public.lab_specimen_bags%rowtype;
  v_item jsonb;
begin
  select specimen.*
  into v_specimen
  from public.lab_specimen_containers specimen
  where specimen.id = p_item_id
    and specimen.lab_organization_id = v_organization_id;

  if found then
    v_item := public.corvia_lab_technician_specimen(p_item_id);
    return v_item || jsonb_build_object(
      'container_code', case
        when v_specimen.label_source = 'external' then
          v_specimen.external_label_reference
        else v_specimen.container_code
      end,
      'label_source', v_specimen.label_source,
      'external_label_reference', v_specimen.external_label_reference,
      'is_transport_bag', false
    );
  end if;

  select bag.*
  into v_bag
  from public.lab_specimen_bags bag
  where bag.id = p_item_id
    and bag.lab_organization_id = v_organization_id;

  if not found then
    raise exception 'This specimen or transport bag does not belong to your laboratory.';
  end if;

  return jsonb_build_object(
    'container_id', v_bag.id,
    'container_code', v_bag.bag_code,
    'specimen_type', format(
      'Transport bag (%s samples)',
      (
        select count(*)
        from public.lab_specimen_containers specimen
        where specimen.bag_id = v_bag.id
      )
    ),
    'status', case
      when exists (
        select 1 from public.lab_specimen_containers specimen
        where specimen.bag_id = v_bag.id and specimen.status = 'collected'
      ) then 'collected'
      when exists (
        select 1 from public.lab_specimen_containers specimen
        where specimen.bag_id = v_bag.id and specimen.status = 'received'
      ) then 'received'
      else 'processing'
    end,
    'is_transport_bag', true,
    'tests', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'lab_result_id', result_row.id,
          'test_name', result_row.test_name,
          'result_release_status', result_row.result_release_status,
          'draft_result', case
            when result_row.result_release_status = 'pending'
              then result_row.submitted_result
            else null
          end,
          'draft_file_url', case
            when result_row.result_release_status = 'pending'
              then result_row.submitted_file_url
            else null
          end,
          'verification_return_reason', result_row.verification_return_reason,
          'result_submission_version', result_row.result_submission_version
        )
        order by result_row.created_at
      )
      from (
        select distinct
          lab_result.id,
          lab_result.test_name,
          lab_result.result_release_status,
          lab_result.verification_return_reason,
          lab_result.result_submission_version,
          lab_result.created_at,
          history.result as submitted_result,
          history.file_url as submitted_file_url
        from public.lab_specimen_containers specimen
        join public.lab_specimen_container_tests specimen_test
          on specimen_test.container_id = specimen.id
        join public.lab_results lab_result
          on lab_result.id = specimen_test.lab_result_id
        left join public.lab_result_submission_history history
          on history.lab_result_id = lab_result.id
          and history.submission_version = lab_result.result_submission_version
        where specimen.bag_id = v_bag.id
          and lab_result.lab_organization_id = v_organization_id
      ) result_row
    ), '[]'::jsonb)
  );
end;
$$;

create or replace function public.corvia_lab_technician_collection_queue()
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_context jsonb := public.corvia_current_lab_technician_context();
begin
  return (
    select coalesce(
      jsonb_agg(
        public.corvia_lab_technician_collection_item(queue_item.id)
        order by queue_item.needs_correction desc, queue_item.collected_at
      ),
      '[]'::jsonb
    )
    from (
      select
        specimen.id,
        specimen.collected_at,
        exists (
          select 1
          from public.lab_specimen_container_tests specimen_test
          join public.lab_results lab_result
            on lab_result.id = specimen_test.lab_result_id
          where specimen_test.container_id = specimen.id
            and lab_result.result_release_status = 'pending'
            and lab_result.verification_return_reason is not null
        ) as needs_correction
      from public.lab_specimen_containers specimen
      where specimen.lab_organization_id =
          (v_context->>'lab_organization_id')::uuid
        and specimen.status in ('collected', 'received', 'processing')
        and exists (
          select 1
          from public.lab_specimen_container_tests specimen_test
          join public.lab_results lab_result
            on lab_result.id = specimen_test.lab_result_id
          where specimen_test.container_id = specimen.id
            and lab_result.lab_organization_id = specimen.lab_organization_id
            and lab_result.result_release_status = 'pending'
        )
      order by needs_correction desc, specimen.collected_at
      limit 100
    ) queue_item
  );
end;
$$;

create or replace function public.corvia_lab_worker_receive_collection_item(
  p_item_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_context jsonb := public.corvia_current_lab_technician_context();
  v_worker_id uuid := (v_context->>'worker_id')::uuid;
  v_organization_id uuid := (v_context->>'lab_organization_id')::uuid;
  v_bag public.lab_specimen_bags%rowtype;
begin
  if exists (
    select 1
    from public.lab_specimen_containers specimen
    where specimen.id = p_item_id
      and specimen.lab_organization_id = v_organization_id
  ) then
    return public.corvia_lab_worker_receive_specimen(p_item_id);
  end if;

  select bag.*
  into v_bag
  from public.lab_specimen_bags bag
  where bag.id = p_item_id
    and bag.lab_organization_id = v_organization_id
  for update;

  if not found then
    raise exception 'This specimen or transport bag does not belong to your laboratory.';
  end if;

  if not exists (
    select 1
    from public.lab_specimen_containers specimen
    where specimen.bag_id = v_bag.id
      and specimen.status in ('collected', 'received')
  ) then
    raise exception 'This transport bag has no receivable samples.';
  end if;

  update public.lab_specimen_containers
  set status = 'received',
      received_by_lab_worker_id = coalesce(
        received_by_lab_worker_id,
        v_worker_id
      ),
      received_at = coalesce(received_at, now()),
      updated_at = now()
  where bag_id = v_bag.id
    and status in ('collected', 'received');

  update public.lab_results lab_result
  set status = 'in_progress'
  where lab_result.lab_organization_id = v_organization_id
    and exists (
      select 1
      from public.lab_specimen_containers specimen
      join public.lab_specimen_container_tests specimen_test
        on specimen_test.container_id = specimen.id
      where specimen.bag_id = v_bag.id
        and specimen_test.lab_result_id = lab_result.id
    )
    and lower(replace(replace(
      trim(coalesce(lab_result.status, 'pending')), '-', '_'
    ), ' ', '_')) in (
      'sample_collected', 'pending', 'ordered',
      'requested', 'awaiting', 'scheduled'
    );

  return jsonb_build_object(
    'container_id', v_bag.id,
    'status', 'received',
    'is_transport_bag', true
  );
end;
$$;

create or replace function public.corvia_require_all_lab_specimens_received()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  if new.result_release_status = 'awaiting_verification'
     and new.result_release_status is distinct from old.result_release_status
     and exists (
       select 1
       from public.lab_specimen_container_tests specimen_test
       join public.lab_specimen_containers specimen
         on specimen.id = specimen_test.container_id
       where specimen_test.lab_result_id = new.id
         and specimen.status not in (
           'received', 'processing', 'disposed', 'rejected'
         )
     ) then
    raise exception
      'Receive every required specimen sample before submitting the result.';
  end if;

  return new;
end;
$$;

drop trigger if exists corvia_require_all_lab_specimens_received
  on public.lab_results;
create trigger corvia_require_all_lab_specimens_received
before update on public.lab_results
for each row
execute function public.corvia_require_all_lab_specimens_received();

revoke all on function public.corvia_nurse_collect_lab_specimens(
  uuid, jsonb, boolean, text, text
) from public, anon;
grant execute on function public.corvia_nurse_collect_lab_specimens(
  uuid, jsonb, boolean, text, text
) to authenticated;

revoke all on function public.corvia_nurse_collect_lab_specimen(
  uuid, text, text
) from public, anon;
grant execute on function public.corvia_nurse_collect_lab_specimen(
  uuid, text, text
) to authenticated;

revoke all on function public.corvia_lab_technician_collection_item(uuid)
  from public, anon;
grant execute on function public.corvia_lab_technician_collection_item(uuid)
  to authenticated;

revoke all on function public.corvia_lab_technician_collection_queue()
  from public, anon;
grant execute on function public.corvia_lab_technician_collection_queue()
  to authenticated;

revoke all on function public.corvia_lab_worker_receive_collection_item(uuid)
  from public, anon;
grant execute on function public.corvia_lab_worker_receive_collection_item(uuid)
  to authenticated;

notify pgrst, 'reload schema';
commit;
