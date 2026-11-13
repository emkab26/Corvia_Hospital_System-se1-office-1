-- Corvia Hospital Admin: staff account linking
-- Run this complete file in Supabase SQL Editor as postgres.

begin;

do $$
declare
  missing text[] := array[]::text[];
  required_table text;
begin
  foreach required_table in array array[
    'profiles', 'hospitals', 'hospital_admins', 'departments',
    'hospital_staff', 'doctors', 'hospital_nurses', 'pharmacists',
    'corvia_hospital_reception_staff', 'lab_organizations',
    'hospital_lab_admin_accounts'
  ] loop
    if to_regclass('public.' || required_table) is null then
      missing := array_append(missing, required_table);
    end if;
  end loop;

  if cardinality(missing) > 0 then
    raise exception 'Staff Accounts prerequisites are missing: %',
      array_to_string(missing, ', ');
  end if;
end $$;

create table if not exists public.corvia_hospital_staff_accounts (
  id uuid primary key default gen_random_uuid(),
  hospital_id uuid not null references public.hospitals(id),
  profile_id uuid not null,
  auth_user_id uuid not null references auth.users(id),
  staff_role text not null check (
    staff_role in ('doctor', 'specialist', 'nurse', 'pharmacist', 'reception')
  ),
  department_id uuid references public.departments(id),
  specialization text,
  license_number text,
  employee_number text,
  pharmacy_name text,
  is_active boolean not null default true,
  linked_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (hospital_id, profile_id, staff_role)
);

create index if not exists corvia_hospital_staff_accounts_hospital_idx
  on public.corvia_hospital_staff_accounts(hospital_id, is_active, staff_role);

alter table public.corvia_hospital_staff_accounts enable row level security;
revoke all on public.corvia_hospital_staff_accounts from public, anon, authenticated;

create or replace function public.corvia_admin_staff_hospital_id()
returns uuid
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select ha.hospital_id
  from public.hospital_admins ha
  left join public.profiles actor_profile
    on actor_profile.user_id = auth.uid()
  join public.hospitals h
    on h.id = ha.hospital_id
   and h.is_active is true
  where auth.uid() is not null
    and (
      ha.profile_id = auth.uid()
      or ha.profile_id = actor_profile.id
    )
  order by ha.created_at
  limit 1;
$$;

create or replace function public.corvia_admin_search_accounts_json(
  p_search text,
  p_limit integer default 25
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_hospital uuid;
  v_search text := lower(trim(coalesce(p_search, '')));
  v_result jsonb;
begin
  v_hospital := public.corvia_admin_staff_hospital_id();
  if v_hospital is null then
    raise exception 'Hospital administrator access is required';
  end if;
  if length(v_search) < 3 then
    raise exception 'Enter at least 3 characters of a name or email address';
  end if;

  select coalesce(jsonb_agg(to_jsonb(result_row) order by result_row.first_name,
    result_row.surname, result_row.email), '[]'::jsonb)
  into v_result
  from (
    select
      coalesce(p.id, p.user_id) as profile_id,
      p.first_name,
      p.surname,
      p.email,
      coalesce(nullif(p.role, ''), nullif(p.user_type, ''), 'patient') as current_role,
      coalesce((
        select jsonb_agg(distinct link.staff_role order by link.staff_role)
        from public.corvia_hospital_staff_accounts link
        where link.hospital_id = v_hospital
          and link.profile_id = coalesce(p.id, p.user_id)
          and link.is_active
      ), '[]'::jsonb) as linked_roles
    from public.profiles p
    where p.is_active is not false
      and (
        lower(coalesce(p.email, '')) like '%' || v_search || '%'
        or lower(coalesce(p.first_name, '')) like '%' || v_search || '%'
        or lower(coalesce(p.surname, '')) like '%' || v_search || '%'
        or lower(trim(coalesce(p.first_name, '') || ' ' || coalesce(p.surname, '')))
          like '%' || v_search || '%'
      )
    order by p.first_name, p.surname, p.email
    limit greatest(1, least(coalesce(p_limit, 25), 50))
  ) result_row;

  return v_result;
end;
$$;

create or replace function public.corvia_admin_link_staff_account(
  p_profile_id uuid,
  p_staff_role text,
  p_department_id uuid default null,
  p_specialization text default null,
  p_license_number text default null,
  p_employee_number text default null,
  p_pharmacy_name text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_hospital uuid;
  v_role text := lower(trim(coalesce(p_staff_role, '')));
  v_profile public.profiles%rowtype;
  v_profile_id uuid;
  v_auth_user_id uuid;
  v_department_name text;
  v_doctor_id uuid;
begin
  v_hospital := public.corvia_admin_staff_hospital_id();
  if v_hospital is null then
    raise exception 'Hospital administrator access is required';
  end if;
  if v_role not in ('doctor', 'specialist', 'nurse', 'pharmacist', 'reception') then
    raise exception 'Unsupported staff role';
  end if;

  select p.* into v_profile
  from public.profiles p
  where p.id = p_profile_id or p.user_id = p_profile_id
  order by case when p.id = p_profile_id then 0 else 1 end
  limit 1;
  if not found or v_profile.is_active is false then
    raise exception 'Select an active registered Corvia account';
  end if;

  v_profile_id := coalesce(v_profile.id, v_profile.user_id);
  v_auth_user_id := v_profile.user_id;

  if p_department_id is not null then
    select d.name into v_department_name
    from public.departments d
    where d.id = p_department_id
      and d.hospital_id = v_hospital
      and d.is_active;
    if not found then
      raise exception 'Select an active department from this hospital';
    end if;
  end if;

  if v_role in ('doctor', 'specialist')
     and nullif(trim(coalesce(p_specialization, '')), '') is null then
    raise exception 'Doctor or specialist field is required';
  end if;

  insert into public.corvia_hospital_staff_accounts(
    hospital_id, profile_id, auth_user_id, staff_role, department_id,
    specialization, license_number, employee_number, pharmacy_name,
    is_active, linked_by, updated_at
  ) values (
    v_hospital, v_profile_id, v_auth_user_id, v_role, p_department_id,
    nullif(trim(coalesce(p_specialization, '')), ''),
    nullif(trim(coalesce(p_license_number, '')), ''),
    nullif(trim(coalesce(p_employee_number, '')), ''),
    nullif(trim(coalesce(p_pharmacy_name, '')), ''),
    true, auth.uid(), now()
  ) on conflict (hospital_id, profile_id, staff_role) do update set
    auth_user_id = excluded.auth_user_id,
    department_id = excluded.department_id,
    specialization = excluded.specialization,
    license_number = excluded.license_number,
    employee_number = excluded.employee_number,
    pharmacy_name = excluded.pharmacy_name,
    is_active = true,
    linked_by = auth.uid(),
    updated_at = now();

  if v_role in ('doctor', 'specialist') then
    insert into public.doctors(
      profile_id, specialization, license_number, hospital_id,
      first_name, surname, email, full_name, specialty,
      department, department_id, is_active
    ) values (
      v_auth_user_id, trim(p_specialization),
      nullif(trim(coalesce(p_license_number, '')), ''), v_hospital,
      v_profile.first_name, v_profile.surname, v_profile.email,
      nullif(trim(coalesce(v_profile.first_name, '') || ' ' || coalesce(v_profile.surname, '')), ''),
      trim(p_specialization), v_department_name, p_department_id, true
    ) on conflict (profile_id) do update set
      specialization = excluded.specialization,
      license_number = excluded.license_number,
      hospital_id = excluded.hospital_id,
      first_name = excluded.first_name,
      surname = excluded.surname,
      email = excluded.email,
      full_name = excluded.full_name,
      specialty = excluded.specialty,
      department = excluded.department,
      department_id = excluded.department_id,
      is_active = true,
      updated_at = now()
    returning id into v_doctor_id;
  elsif v_role = 'nurse' then
    update public.hospital_nurses
    set nurse_user_id = v_auth_user_id, is_active = true, updated_at = now()
    where hospital_id = v_hospital and profile_id = v_profile_id;
    if not found then
      insert into public.hospital_nurses(
        hospital_id, profile_id, nurse_user_id, is_active
      ) values (v_hospital, v_profile_id, v_auth_user_id, true);
    end if;
  elsif v_role = 'pharmacist' then
    insert into public.pharmacists(
      profile_id, hospital_id, employee_number, license_number,
      pharmacy_name, department_name, is_active, created_by
    ) values (
      v_auth_user_id, v_hospital,
      nullif(trim(coalesce(p_employee_number, '')), ''),
      nullif(trim(coalesce(p_license_number, '')), ''),
      nullif(trim(coalesce(p_pharmacy_name, '')), ''),
      coalesce(v_department_name, 'Pharmacy'), true, auth.uid()
    ) on conflict (profile_id) do update set
      hospital_id = excluded.hospital_id,
      employee_number = excluded.employee_number,
      license_number = excluded.license_number,
      pharmacy_name = excluded.pharmacy_name,
      department_name = excluded.department_name,
      is_active = true,
      updated_at = now();
  elsif v_role = 'reception' then
    update public.corvia_hospital_reception_staff
    set department_id = p_department_id,
        employee_number = nullif(trim(coalesce(p_employee_number, '')), ''),
        is_active = true,
        updated_at = now()
    where hospital_id = v_hospital and profile_id = v_profile_id;
    if not found then
      insert into public.corvia_hospital_reception_staff(
        profile_id, hospital_id, department_id, employee_number, is_active
      ) values (
        v_profile_id, v_hospital, p_department_id,
        nullif(trim(coalesce(p_employee_number, '')), ''), true
      );
    end if;
  end if;

  update public.hospital_staff
  set doctor_id = coalesce(v_doctor_id, doctor_id),
      staff_role = v_role,
      department = v_department_name,
      is_active = true,
      updated_at = now()
  where hospital_id = v_hospital
    and profile_id = v_auth_user_id
    and staff_role = v_role;
  if not found then
    insert into public.hospital_staff(
      hospital_id, profile_id, doctor_id, staff_role, department, is_active
    ) values (
      v_hospital, v_auth_user_id, v_doctor_id, v_role, v_department_name, true
    );
  end if;

  update public.profiles
  set role = v_role,
      user_type = v_role,
      updated_at = now()
  where user_id = v_auth_user_id;

  return jsonb_build_object(
    'linked', true,
    'hospital_id', v_hospital,
    'profile_id', v_profile_id,
    'role', v_role
  );
end;
$$;

-- PostgreSQL cannot CREATE OR REPLACE a table-returning function when its OUT
-- columns changed in an older Corvia release. This RPC has no database callers;
-- the Flutter client calls it by name, so replacing this exact signature is safe.
drop function if exists public.corvia_admin_list_staff_accounts();

create function public.corvia_admin_list_staff_accounts()
returns table (
  profile_id uuid,
  first_name text,
  surname text,
  email text,
  "current_role" text,
  linked_roles jsonb,
  specialization text,
  department_name text,
  employee_number text
)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  with hospital_scope as (
    select public.corvia_admin_staff_hospital_id() as hospital_id
  )
  select
    links.profile_id,
    p.first_name,
    p.surname,
    p.email,
    coalesce(nullif(p.role, ''), nullif(p.user_type, ''), 'patient'),
    jsonb_agg(distinct links.staff_role order by links.staff_role),
    string_agg(distinct links.specialization, ', ')
      filter (where links.specialization is not null),
    string_agg(distinct d.name, ', ')
      filter (where d.name is not null),
    string_agg(distinct links.employee_number, ', ')
      filter (where links.employee_number is not null)
  from public.corvia_hospital_staff_accounts links
  join hospital_scope scope on scope.hospital_id = links.hospital_id
  join public.profiles p on p.user_id = links.auth_user_id
  left join public.departments d on d.id = links.department_id
  where links.is_active
  group by links.profile_id, p.first_name, p.surname, p.email, p.role, p.user_type
  order by p.first_name, p.surname, p.email;
$$;

create or replace function public.corvia_admin_remove_staff_account(
  p_profile_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_hospital uuid;
  v_auth_user_id uuid;
  v_profile_id uuid;
begin
  v_hospital := public.corvia_admin_staff_hospital_id();
  if v_hospital is null then
    raise exception 'Hospital administrator access is required';
  end if;

  select p.user_id, coalesce(p.id, p.user_id)
  into v_auth_user_id, v_profile_id
  from public.profiles p
  where p.id = p_profile_id or p.user_id = p_profile_id
  limit 1;
  if v_auth_user_id is null then
    raise exception 'Staff account was not found';
  end if;

  update public.corvia_hospital_staff_accounts
  set is_active = false, updated_at = now(), linked_by = auth.uid()
  where hospital_id = v_hospital and profile_id = v_profile_id and is_active;

  update public.doctors
    set is_active = false, status = 'inactive', updated_at = now()
    where hospital_id = v_hospital and profile_id = v_auth_user_id;
  update public.hospital_nurses
    set is_active = false, updated_at = now()
    where hospital_id = v_hospital
      and (nurse_user_id = v_auth_user_id or profile_id = v_profile_id);
  update public.pharmacists
    set is_active = false, updated_at = now()
    where hospital_id = v_hospital and profile_id = v_auth_user_id;
  update public.corvia_hospital_reception_staff
    set is_active = false, updated_at = now()
    where hospital_id = v_hospital and profile_id = v_profile_id;
  update public.hospital_staff
    set is_active = false, updated_at = now()
    where hospital_id = v_hospital and profile_id = v_auth_user_id;

  if not exists (
    select 1 from public.corvia_hospital_staff_accounts
    where auth_user_id = v_auth_user_id and is_active
  ) then
    update public.profiles
    set role = 'patient', user_type = 'patient', updated_at = now()
    where user_id = v_auth_user_id;
  end if;

  return jsonb_build_object('removed', true, 'profile_id', p_profile_id);
end;
$$;

create or replace function public.corvia_admin_appoint_hospital_lab_admin(
  p_profile_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_hospital uuid;
  v_lab uuid;
  v_profile_id uuid;
  v_hospital_name text;
begin
  v_hospital := public.corvia_admin_staff_hospital_id();
  if v_hospital is null then
    raise exception 'Hospital administrator access is required';
  end if;
  select p.id into v_profile_id
  from public.profiles p
  where (p.id = p_profile_id or p.user_id = p_profile_id)
    and p.is_active is not false
  limit 1;
  if v_profile_id is null then
    raise exception 'Select an active registered Corvia account';
  end if;

  select id into v_lab from public.lab_organizations
  where hospital_id = v_hospital and lab_type = 'hospital'
  order by created_at limit 1;
  if v_lab is null then
    select name into v_hospital_name from public.hospitals where id = v_hospital;
    insert into public.lab_organizations(name, lab_type, hospital_id, is_active)
    values (left(coalesce(v_hospital_name, 'Hospital') || ' Laboratory', 160),
      'hospital', v_hospital, true)
    returning id into v_lab;
  end if;

  insert into public.hospital_lab_admin_accounts(
    profile_id, lab_organization_id, appointed_by_user_id, is_active, updated_at
  ) values (v_profile_id, v_lab, auth.uid(), true, now())
  on conflict (profile_id) do update set
    lab_organization_id = excluded.lab_organization_id,
    appointed_by_user_id = auth.uid(),
    is_active = true,
    updated_at = now();

  update public.profiles set role = 'lab_admin', updated_at = now()
  where id = v_profile_id;
  return jsonb_build_object('appointed', true, 'profile_id', v_profile_id);
end;
$$;

-- Replace the exact list signature for the same OUT-column compatibility reason.
drop function if exists public.corvia_admin_list_hospital_lab_admins();

create function public.corvia_admin_list_hospital_lab_admins()
returns table (
  profile_id uuid,
  first_name text,
  surname text,
  email text,
  is_active boolean
)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select p.id, p.first_name, p.surname, p.email, a.is_active
  from public.hospital_lab_admin_accounts a
  join public.lab_organizations l on l.id = a.lab_organization_id
  join public.profiles p on p.id = a.profile_id
  where l.hospital_id = public.corvia_admin_staff_hospital_id()
  order by p.first_name, p.surname, p.email;
$$;

create or replace function public.corvia_admin_remove_hospital_lab_admin(
  p_profile_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_hospital uuid;
  v_auth_user_id uuid;
begin
  v_hospital := public.corvia_admin_staff_hospital_id();
  if v_hospital is null then
    raise exception 'Hospital administrator access is required';
  end if;
  update public.hospital_lab_admin_accounts a
  set is_active = false, updated_at = now()
  from public.lab_organizations l
  where a.profile_id = p_profile_id
    and l.id = a.lab_organization_id
    and l.hospital_id = v_hospital;
  if not found then
    raise exception 'Lab Admin link was not found';
  end if;

  select user_id into v_auth_user_id from public.profiles where id = p_profile_id;
  if not exists (
    select 1 from public.corvia_hospital_staff_accounts
    where auth_user_id = v_auth_user_id and is_active
  ) then
    update public.profiles set role = 'patient', updated_at = now()
    where id = p_profile_id;
  end if;
  return jsonb_build_object('removed', true, 'profile_id', p_profile_id);
end;
$$;

revoke all on function public.corvia_admin_staff_hospital_id() from public, anon;
revoke all on function public.corvia_admin_search_accounts_json(text, integer) from public, anon;
revoke all on function public.corvia_admin_link_staff_account(uuid, text, uuid, text, text, text, text) from public, anon;
revoke all on function public.corvia_admin_list_staff_accounts() from public, anon;
revoke all on function public.corvia_admin_remove_staff_account(uuid) from public, anon;
revoke all on function public.corvia_admin_appoint_hospital_lab_admin(uuid) from public, anon;
revoke all on function public.corvia_admin_list_hospital_lab_admins() from public, anon;
revoke all on function public.corvia_admin_remove_hospital_lab_admin(uuid) from public, anon;

grant execute on function public.corvia_admin_staff_hospital_id() to authenticated;
grant execute on function public.corvia_admin_search_accounts_json(text, integer) to authenticated;
grant execute on function public.corvia_admin_link_staff_account(uuid, text, uuid, text, text, text, text) to authenticated;
grant execute on function public.corvia_admin_list_staff_accounts() to authenticated;
grant execute on function public.corvia_admin_remove_staff_account(uuid) to authenticated;
grant execute on function public.corvia_admin_appoint_hospital_lab_admin(uuid) to authenticated;
grant execute on function public.corvia_admin_list_hospital_lab_admins() to authenticated;
grant execute on function public.corvia_admin_remove_hospital_lab_admin(uuid) to authenticated;

notify pgrst, 'reload schema';
commit;

-- Verification: every value must be true.
select
  to_regclass('public.corvia_hospital_staff_accounts') is not null as has_staff_links,
  to_regprocedure('public.corvia_admin_search_accounts_json(text,integer)') is not null as has_account_search,
  to_regprocedure('public.corvia_admin_link_staff_account(uuid,text,uuid,text,text,text,text)') is not null as has_staff_link_rpc,
  to_regprocedure('public.corvia_admin_list_staff_accounts()') is not null as has_staff_list_rpc,
  to_regprocedure('public.corvia_admin_remove_staff_account(uuid)') is not null as has_staff_remove_rpc,
  to_regprocedure('public.corvia_admin_appoint_hospital_lab_admin(uuid)') is not null as has_lab_admin_rpc;
