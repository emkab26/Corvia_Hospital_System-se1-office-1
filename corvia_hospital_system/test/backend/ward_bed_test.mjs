// node test/backend/ward_bed_test.mjs
// Disposable PostgreSQL WASM database only. Never connects to Supabase.
import { PGlite } from '../../tmp/blood-bank-tests/node_modules/@electric-sql/pglite/dist/index.js';
import { readFile } from 'node:fs/promises';
import assert from 'node:assert/strict';

const db = new PGlite();
const id = n => `20000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const adminUser = id(1);
const adminProfile = id(2);
const outsiderUser = id(3);
const outsiderProfile = id(4);
const hospital = id(10);
const otherHospital = id(11);
const bed = id(20);
const occupiedBed = id(21);
const migration = await readFile(
  new URL('../../supabase/migrations/20261008_corvia_workstream5_ward_bed.sql', import.meta.url),
  'utf8',
);

let passed = 0;

await db.exec(`
create role anon;
create role authenticated;
create role service_role;
create schema auth;
create table auth.users (id uuid primary key);
create function auth.uid() returns uuid language sql stable as
$$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;

create table public.profiles (
  id uuid primary key,
  user_id uuid unique not null references auth.users(id)
);
create table public.hospitals (
  id uuid primary key,
  name text not null,
  is_active boolean not null default true
);
create table public.hospital_admins (
  hospital_id uuid not null references public.hospitals(id),
  profile_id uuid not null,
  role text not null,
  primary key (hospital_id, profile_id)
);
create table public.hospital_beds (
  id uuid primary key,
  hospital_id uuid not null references public.hospitals(id),
  bed_number text not null,
  status text not null,
  is_active boolean not null default true,
  updated_by uuid,
  updated_at timestamptz not null default now()
);
create table public.patient_bed_assignments (
  id uuid primary key,
  hospital_id uuid not null references public.hospitals(id),
  bed_id uuid not null references public.hospital_beds(id),
  status text not null,
  ended_at timestamptz
);

insert into auth.users values ('${adminUser}'), ('${outsiderUser}');
insert into public.profiles values
  ('${adminProfile}', '${adminUser}'),
  ('${outsiderProfile}', '${outsiderUser}');
insert into public.hospitals(id, name) values
  ('${hospital}', 'Ward Test Hospital'),
  ('${otherHospital}', 'Other Hospital');
insert into public.hospital_admins values
  ('${hospital}', '${adminProfile}', 'admin');
insert into public.hospital_beds(id, hospital_id, bed_number, status) values
  ('${bed}', '${hospital}', 'A-01', 'available'),
  ('${occupiedBed}', '${hospital}', 'A-02', 'occupied'),
  ('${id(22)}', '${otherHospital}', 'B-01', 'available');
insert into public.patient_bed_assignments(id, hospital_id, bed_id, status)
values ('${id(30)}', '${hospital}', '${occupiedBed}', 'active');
`);

await db.exec(migration);

async function as(user, run) {
  await db.exec('set role authenticated');
  await db.query(`select set_config('request.jwt.claim.sub', $1, false)`, [user]);
  try {
    return await run();
  } finally {
    await db.exec('reset role');
  }
}

async function change(user, bedId, status, reason = null, expiry = null, sanitation = null) {
  return as(user, async () => (
    await db.query(
      'select (corvia_mh_set_bed_status($1,$2,$3,$4,$5,$6)).*',
      [hospital, bedId, status, reason, expiry, sanitation],
    )
  ).rows[0]);
}

async function test(name, run) {
  try {
    await run();
    console.log(`PASS ${name}`);
    passed++;
  } catch (error) {
    console.error(`FAIL ${name}`);
    throw error;
  }
}

await test('anonymous users cannot call the status RPC', async () => {
  await db.exec('set role anon');
  try {
    await assert.rejects(
      db.query('select corvia_mh_set_bed_status($1,$2,$3)', [hospital, bed, 'blocked']),
      /permission denied/,
    );
  } finally {
    await db.exec('reset role');
  }
});

await test('non-admin users cannot change a hospital bed', () =>
  assert.rejects(change(outsiderUser, bed, 'blocked'), /administrator access/));

await test('reservations require a future expiry', () =>
  assert.rejects(change(adminUser, bed, 'reserved'), /future expiry/));

await test('administrator can reserve a bed', async () => {
  const expiry = '2090-10-10T12:00:00Z';
  const row = await change(adminUser, bed, 'reserved', null, expiry);
  assert.equal(row.status, 'reserved');
  assert.equal(new Date(row.reserved_until).getTime(), new Date(expiry).getTime());
});

await test('expired reservations return to available on refresh', async () => {
  await db.query(
    "update hospital_beds set reserved_until = now() - interval '1 minute' where id = $1",
    [bed],
  );
  const result = await as(adminUser, async () => (
    await db.query('select corvia_mh_expire_bed_reservations($1) as count', [hospital])
  ).rows[0]);
  assert.equal(result.count, 1);
  const row = (await db.query('select status, reserved_until from hospital_beds where id = $1', [bed])).rows[0];
  assert.equal(row.status, 'available');
  assert.equal(row.reserved_until, null);
});

await test('maintenance requires a recorded reason', () =>
  assert.rejects(change(adminUser, bed, 'maintenance'), /maintenance reason/));

await test('maintenance reason is stored and cleared when status changes', async () => {
  let row = await change(adminUser, bed, 'maintenance', 'Broken side rail');
  assert.equal(row.maintenance_reason, 'Broken side rail');
  row = await change(adminUser, bed, 'blocked');
  assert.equal(row.maintenance_reason, null);
});

await test('cleaning records EVS workflow and requires sanitation sign-off', async () => {
  let row = await change(adminUser, bed, 'cleaning');
  assert.ok(row.cleaning_started_at);
  assert.ok(row.evs_notified_at);
  assert.equal(row.sanitation_notes, null);
  await assert.rejects(change(adminUser, bed, 'available'), /sanitation notes/);
  row = await change(adminUser, bed, 'available', null, null, 'Terminal clean complete');
  assert.ok(row.cleaned_at);
  assert.equal(row.sanitation_notes, 'Terminal clean complete');
});

await test('active patient assignment keeps a bed occupied', () =>
  assert.rejects(change(adminUser, occupiedBed, 'cleaning'), /active patient assignment/));

await test('beds from another hospital cannot be changed', () =>
  assert.rejects(change(adminUser, id(22), 'blocked'), /Bed not found/));

await test('migration is safe to run again', async () => {
  await db.exec(migration);
  assert.equal(
    (await db.query("select count(*)::int as count from pg_proc where proname = 'corvia_mh_set_bed_status'")).rows[0].count,
    1,
  );
});

await test('verification SQL reports the complete installation', async () => {
  const verification = await readFile(
    new URL('../../supabase/scripts/workstreams/17_verify_ward_bed.sql', import.meta.url),
    'utf8',
  );
  await db.exec(verification);
  const row = (await db.query(`
    select
      to_regprocedure('public.corvia_mh_expire_bed_reservations(uuid)') is not null as expiry,
      to_regprocedure('public.corvia_mh_set_bed_status(uuid,uuid,text,text,timestamptz,text)') is not null as status
  `)).rows[0];
  assert.equal(row.expiry, true);
  assert.equal(row.status, true);
});

console.log(`Ward & Bed backend tests passed: ${passed}`);
await db.close();
