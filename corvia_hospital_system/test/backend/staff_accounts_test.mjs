import { PGlite } from '../../tmp/blood-bank-tests/node_modules/@electric-sql/pglite/dist/index.js';
import { readFile } from 'node:fs/promises';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';

const db = new PGlite();
const actor = randomUUID();
const actorProfile = randomUUID();
const target = randomUUID();
const targetProfile = randomUUID();
const hospital = randomUUID();
const department = randomUUID();

await db.exec(`
  create role anon;
  create role authenticated;
  create schema auth;
  create table auth.users(id uuid primary key, email text);
  create function auth.uid() returns uuid language sql stable
    as $$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;

  create table public.hospitals(
    id uuid primary key, name text not null, is_active boolean not null default true,
    created_at timestamptz not null default now()
  );
  create table public.profiles(
    user_id uuid primary key references auth.users(id), id uuid unique,
    first_name text, surname text, email text, role text default 'patient',
    user_type text default 'patient', is_active boolean default true,
    updated_at timestamptz default now()
  );
  create table public.hospital_admins(
    id uuid primary key default gen_random_uuid(), hospital_id uuid not null references public.hospitals(id),
    profile_id uuid not null, role text not null default 'admin',
    created_at timestamptz not null default now()
  );
  create table public.departments(
    id uuid primary key, hospital_id uuid not null references public.hospitals(id),
    name text not null, is_active boolean not null default true
  );
  create table public.doctors(
    id uuid primary key default gen_random_uuid(), profile_id uuid not null unique,
    specialization text not null, license_number text unique, hospital_id uuid,
    first_name text, surname text, email text, full_name text, specialty text,
    department text, department_id uuid, is_active boolean not null default true,
    status text not null default 'available', updated_at timestamptz default now()
  );
  create table public.hospital_nurses(
    id uuid primary key default gen_random_uuid(), hospital_id uuid not null,
    profile_id uuid not null, nurse_user_id uuid, is_active boolean not null default true,
    updated_at timestamptz default now()
  );
  create table public.pharmacists(
    id uuid primary key default gen_random_uuid(), profile_id uuid not null unique,
    hospital_id uuid not null, employee_number text unique, license_number text unique,
    pharmacy_name text, department_name text, is_active boolean not null default true,
    created_by uuid, updated_at timestamptz default now()
  );
  create table public.corvia_hospital_reception_staff(
    id uuid primary key default gen_random_uuid(), profile_id uuid not null,
    hospital_id uuid not null, department_id uuid, employee_number text,
    is_active boolean not null default true, updated_at timestamptz default now()
  );
  create table public.hospital_staff(
    id uuid primary key default gen_random_uuid(), hospital_id uuid, profile_id uuid,
    doctor_id uuid, staff_role text not null default 'staff', department text,
    is_active boolean default true, updated_at timestamptz default now()
  );
  create table public.lab_organizations(
    id uuid primary key default gen_random_uuid(), name text not null, lab_type text not null,
    hospital_id uuid, is_active boolean not null default true,
    created_at timestamptz not null default now()
  );
  create table public.hospital_lab_admin_accounts(
    id uuid primary key default gen_random_uuid(), profile_id uuid not null unique,
    lab_organization_id uuid not null, appointed_by_user_id uuid not null,
    is_active boolean not null default true, updated_at timestamptz default now()
  );

  insert into auth.users values
    ('${actor}', 'admin@corvia.test'), ('${target}', 'doctor@corvia.test');
  insert into public.profiles(user_id,id,first_name,surname,email,role,user_type) values
    ('${actor}','${actorProfile}','Hospital','Admin','admin@corvia.test','hospital_admin','hospital_admin'),
    ('${target}','${targetProfile}','Alex','Medic','doctor@corvia.test','patient','patient');
  insert into public.hospitals(id,name) values('${hospital}','Corvia Test Hospital');
  insert into public.hospital_admins(hospital_id,profile_id) values('${hospital}','${actor}');
  insert into public.departments values('${department}','${hospital}','Emergency Medicine',true);
`);

const migration = await readFile(
  new URL('../../supabase/scripts/workstreams/19_install_hospital_staff_accounts.sql', import.meta.url),
  'utf8',
);
await db.exec(migration);
await db.exec(migration);
await db.query("select set_config('request.jwt.claim.sub',$1,false)", [actor]);
await db.exec('set role authenticated');

const search = (
  await db.query('select public.corvia_admin_search_accounts_json($1,$2) value', ['doctor@', 25])
).rows[0].value;
assert.equal(search.length, 1);
assert.equal(search[0].profile_id, targetProfile);

const linked = (
  await db.query(
    'select public.corvia_admin_link_staff_account($1,$2,$3,$4,$5,$6,$7) value',
    [targetProfile, 'doctor', department, 'Emergency Medicine', 'HPCSA-1', null, null],
  )
).rows[0].value;
assert.equal(linked.linked, true);

const staff = (await db.query('select * from public.corvia_admin_list_staff_accounts()')).rows;
assert.equal(staff.length, 1);
assert.equal(staff[0].specialization, 'Emergency Medicine');
assert.equal(staff[0].department_name, 'Emergency Medicine');
assert.deepEqual(staff[0].linked_roles, ['doctor']);

await db.exec('reset role');
assert.equal((await db.query('select count(*)::int count from public.doctors')).rows[0].count, 1);
assert.equal((await db.query('select role from public.profiles where user_id=$1', [target])).rows[0].role, 'doctor');

await db.exec('set role authenticated');
await db.query('select public.corvia_admin_remove_staff_account($1)', [targetProfile]);
await db.exec('reset role');
assert.equal((await db.query('select count(*)::int count from public.doctors where is_active')).rows[0].count, 0);
assert.equal((await db.query('select role from public.profiles where user_id=$1', [target])).rows[0].role, 'patient');

await db.exec('set role authenticated');
const lab = (
  await db.query('select public.corvia_admin_appoint_hospital_lab_admin($1) value', [targetProfile])
).rows[0].value;
assert.equal(lab.appointed, true);
assert.equal((await db.query('select count(*)::int count from public.corvia_admin_list_hospital_lab_admins()')).rows[0].count, 1);

await db.exec('reset role');
console.log('PASS: hospital admin staff account search, linking, fields, removal and lab admin appointment');
await db.close();
