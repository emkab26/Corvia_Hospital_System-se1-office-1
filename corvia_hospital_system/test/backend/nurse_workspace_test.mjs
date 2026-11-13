// Isolated synthetic PostgreSQL tests, never a connection to Supabase.
// Setup: npm install --prefix build/nurse-workspace-tests --no-package-lock @electric-sql/pglite
// Run: node test/backend/nurse_workspace_test.mjs
import { PGlite } from '../../build/nurse-workspace-tests/node_modules/@electric-sql/pglite/dist/index.js';
import { readFile } from 'node:fs/promises';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';

const db = new PGlite();
const ids = Object.fromEntries([
  'hospital', 'otherHospital', 'nurse', 'nurseProfile', 'otherNurse', 'otherNurseProfile',
  'patientUser', 'patientProfile', 'patient', 'otherPatient', 'unassigned', 'taskPatient',
  'futurePatient', 'expiredPatient', 'building', 'otherBuilding', 'floor', 'inactiveFloor',
  'ward1', 'ward2', 'provider',
].map(key => [key, randomUUID()]));
try {
  await db.exec(`
    create role anon;
    create role authenticated;
    create schema auth;
    create function auth.uid() returns uuid language sql stable as
      $$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
    create table hospitals(id uuid primary key, name text, is_active boolean default true);
    create table profiles(user_id uuid primary key, id uuid unique, first_name text,
      surname text, phone_number text, phone text, email text, id_number text,
      date_of_birth date, role text default 'patient', is_active boolean default true);
    create table hospital_nurses(id uuid default gen_random_uuid(), hospital_id uuid,
      profile_id uuid, nurse_user_id uuid, is_active boolean default true,
      created_at timestamptz default now());
    create table patients(id uuid primary key, profile_id uuid, patient_number text,
      first_name text, surname text, phone text, email text, date_of_birth date,
      gender text, medical_aid_provider text, medical_aid_provider_id uuid,
      medical_aid_member_number text, medical_aid_plan text);
    create table medical_aid_providers(id uuid primary key, name text);
    create table nurse_patient_assignments(id uuid default gen_random_uuid(), hospital_id uuid,
      nurse_user_id uuid, patient_id uuid, status text default 'active',
      assigned_at timestamptz default now(), start_at timestamptz default now(), end_at timestamptz);
    create table nursing_tasks(id uuid default gen_random_uuid(), hospital_id uuid,
      assigned_nurse_user_id uuid, patient_id uuid, title text, status text default 'pending',
      created_at timestamptz default now());
    create table prescriptions(id uuid default gen_random_uuid(), patient_id uuid, status text);
    create table hospital_buildings(id uuid primary key, hospital_id uuid, name text, is_active boolean default true);
    create table hospital_floors(id uuid primary key, hospital_id uuid, building_id uuid,
      name text, is_active boolean default true);
    create table hospital_wards(id uuid primary key default gen_random_uuid(), hospital_id uuid,
      building_id uuid, floor_id uuid, name text, code text, is_active boolean default true);

    -- Context selection is a fixture dependency, matching the exported function's
    -- canonical profile/latest-active-hospital selection without unrelated legacy fallbacks.
    create function corvia_current_nurse_context() returns jsonb language sql stable security definer as $$
      select jsonb_build_object('signed_in', auth.uid() is not null, 'profile_found', p.id is not null,
        'is_nurse', p.role = 'nurse', 'is_active', p.is_active, 'hospital_found', n.hospital_id is not null,
        'profile_id', p.id, 'nurse_user_id', p.user_id, 'hospital_id', n.hospital_id,
        'hospital_name', 'Test hospital', 'nurse_name', p.first_name, 'role', p.role)
      from profiles p left join lateral (
        select * from hospital_nurses n where n.is_active
          and (n.profile_id = p.id or n.nurse_user_id = p.user_id)
        order by n.created_at desc limit 1
      ) n on true where p.user_id = auth.uid()
    $$;
    create function corvia_nurse_collect_lab_specimen() returns text language sql as $$ select 'legacy'::text $$;

    insert into hospitals values ('${ids.hospital}', 'Hospital A', true), ('${ids.otherHospital}', 'Hospital B', true);
    insert into profiles(user_id,id,first_name,surname,role) values
      ('${ids.nurse}','${ids.nurseProfile}','Nurse','A','nurse'),
      ('${ids.otherNurse}','${ids.otherNurseProfile}','Nurse','B','nurse');
    insert into profiles(user_id,id,first_name,surname,phone_number,email,id_number,date_of_birth) values
      ('${ids.patientUser}','${ids.patientProfile}','Profile first','Profile surname','0123456789',
       'patient@example.test','SYNTHETIC-ID','1990-03-12');
    insert into hospital_nurses(hospital_id,profile_id,nurse_user_id) values
      ('${ids.hospital}','${ids.nurseProfile}','${ids.nurse}'),
      ('${ids.otherHospital}','${ids.otherNurseProfile}','${ids.otherNurse}');
    insert into medical_aid_providers values('${ids.provider}','Resolved provider');
    insert into patients(id,profile_id,patient_number,first_name,surname,phone,medical_aid_provider_id,medical_aid_member_number) values
      ('${ids.patient}','${ids.patientUser}','PAT-001','  ','Patient surname','', '${ids.provider}','MEMBER-1');
    insert into patients(id,patient_number,first_name) values
      ('${ids.otherPatient}','PAT-B','Other hospital patient'),
      ('${ids.unassigned}','PAT-U','Unassigned patient'),
      ('${ids.taskPatient}','PAT-T','Task patient'),
      ('${ids.futurePatient}','PAT-F','Future patient'),
      ('${ids.expiredPatient}','PAT-E','Expired patient');
    insert into nurse_patient_assignments(hospital_id,nurse_user_id,patient_id) values
      ('${ids.hospital}','${ids.nurse}','${ids.patient}'),
      ('${ids.hospital}','${ids.nurse}','${ids.patient}'),
      ('${ids.otherHospital}','${ids.nurse}','${ids.otherPatient}');
    insert into nurse_patient_assignments(hospital_id,nurse_user_id,patient_id,start_at) values
      ('${ids.hospital}','${ids.nurse}','${ids.futurePatient}',now()+interval '1 day');
    insert into nurse_patient_assignments(hospital_id,nurse_user_id,patient_id,end_at) values
      ('${ids.hospital}','${ids.nurse}','${ids.expiredPatient}',now()-interval '1 day');
    insert into nursing_tasks(hospital_id,assigned_nurse_user_id,patient_id,title) values
      ('${ids.hospital}','${ids.nurse}','${ids.taskPatient}','Hospital A task'),
      (null,'${ids.nurse}','${ids.patient}','Legacy task for assigned patient'),
      (null,'${ids.nurse}','${ids.unassigned}','Unscoped legacy task'),
      ('${ids.otherHospital}','${ids.nurse}','${ids.otherPatient}','Hospital B task');
    insert into prescriptions(patient_id,status) values
      ('${ids.patient}','active'), ('${ids.patient}','active'),
      ('${ids.patient}','completed'), ('${ids.patient}','cancelled'),
      ('${ids.otherPatient}','active'), ('${ids.taskPatient}','active'),
      ('${ids.futurePatient}','active'), ('${ids.expiredPatient}','active');
    insert into hospital_buildings values
      ('${ids.building}','${ids.hospital}','Main building',true),
      ('${ids.otherBuilding}','${ids.otherHospital}','Other building',true);
    insert into hospital_floors values
      ('${ids.floor}','${ids.hospital}','${ids.building}','First floor',true),
      ('${ids.inactiveFloor}','${ids.hospital}','${ids.building}','Closed floor',false);
    insert into hospital_wards(hospital_id,building_id,floor_id,name,code,is_active,id) values
      ('${ids.hospital}','${ids.building}','${ids.floor}','ICU','ICU-A',true,'${ids.ward1}'),
      ('${ids.hospital}','${ids.building}','${ids.floor}','ICU','ICU-B',true,'${ids.ward2}'),
      ('${ids.hospital}','${ids.building}','${ids.floor}','Closed ward',null,false,gen_random_uuid()),
      ('${ids.hospital}','${ids.building}','${ids.inactiveFloor}','Closed floor ward',null,true,gen_random_uuid()),
      ('${ids.hospital}','${ids.otherBuilding}','${ids.floor}','Wrong parent hospital',null,true,gen_random_uuid());

    grant usage on schema public, auth to authenticated, anon;
    grant select on profiles, patients, prescriptions to authenticated;
    alter table profiles enable row level security;
    create policy own_profile on profiles for select to authenticated using(user_id = auth.uid());
    alter table patients enable row level security;
    alter table prescriptions enable row level security;
  `);
  const legacy = (await db.query("select pg_get_functiondef('corvia_nurse_collect_lab_specimen()'::regprocedure) definition")).rows[0].definition;
  const migration = await readFile(new URL('../../supabase/migrations/20261022_corvia_nurse_workspace.sql', import.meta.url), 'utf8');
  await db.exec(migration);
  await db.exec(migration);
  const countMigration = await readFile(new URL('../../supabase/migrations/20261022_corvia_nurse_workspace_prescription_count.sql', import.meta.url), 'utf8');
  await db.exec(countMigration);
  await db.exec(countMigration);
  assert.equal((await db.query("select pg_get_functiondef('corvia_nurse_collect_lab_specimen()'::regprocedure) definition")).rows[0].definition, legacy);
  assert.equal((await db.query("select has_function_privilege('anon','corvia_nurse_workspace_v1()','execute') allowed")).rows[0].allowed, false);
  assert.equal((await db.query("select has_function_privilege('anon','corvia_nurse_active_prescription_count_v1()','execute') allowed")).rows[0].allowed, false);

  async function actor(user, role = 'authenticated') {
    await db.exec('reset role');
    await db.query("select set_config('request.jwt.claim.sub',$1,false)", [user ?? '']);
    await db.exec(`set role ${role}`);
  }
  async function workspace() {
    return (await db.query('select corvia_nurse_workspace_v1() value')).rows[0].value;
  }
  async function prescriptionCount() {
    return (await db.query('select corvia_nurse_active_prescription_count_v1() value')).rows[0].value;
  }
  await actor(ids.nurse);
  assert.equal((await db.query('select * from patients')).rows.length, 0);
  assert.equal((await db.query('select * from profiles')).rows.length, 1);
  assert.equal((await db.query('select * from prescriptions')).rows.length, 0);
  const counts = await prescriptionCount();
  assert.equal(counts.active_prescriptions, 2);
  assert.equal(counts.hospital_id, ids.hospital);
  assert.equal(counts.nurse_user_id, ids.nurse);
  const result = await workspace();
  assert.equal(result.context.hospital_id, ids.hospital);
  assert.equal(result.assignments.length, 2);
  assert.deepEqual(new Set(result.patients.map(p => p.id)), new Set([ids.patient, ids.taskPatient]));
  const patient = result.patients.find(p => p.id === ids.patient);
  assert.equal(patient.first_name, 'Profile first');
  assert.equal(patient.surname, 'Patient surname');
  assert.equal(patient.phone, '0123456789');
  assert.equal(patient.id_number, 'SYNTHETIC-ID');
  assert.equal(patient.date_of_birth, '1990-03-12');
  assert.equal(patient.medical_aid_provider, 'Resolved provider');
  assert.equal(patient.medical_aid_member_number, 'MEMBER-1');
  assert.equal(result.tasks.length, 2);
  assert.deepEqual(new Set(result.wards.map(w => w.id)), new Set([ids.ward1, ids.ward2]));
  assert.equal(result.wards[0].building_name, 'Main building');

  await actor(ids.otherNurse);
  const other = await workspace();
  assert.equal(other.context.hospital_id, ids.otherHospital);
  assert.equal(other.patients.length, 0);
  assert.equal((await prescriptionCount()).active_prescriptions, 0);
  await actor(null);
  await assert.rejects(workspace, /session has expired/);
  await assert.rejects(prescriptionCount, /session has expired/);
  await actor(ids.patientUser);
  await assert.rejects(workspace, /active nurse account/);
  await assert.rejects(prescriptionCount, /active nurse account/);
  await actor(ids.nurse, 'anon');
  await assert.rejects(workspace, /permission denied/);
  await assert.rejects(prescriptionCount, /permission denied/);

  // Revoked membership, disabled account and disabled hospital must fail closed.
  await db.exec(`reset role; update hospital_nurses set is_active=false where nurse_user_id='${ids.nurse}'`);
  await actor(ids.nurse);
  await assert.rejects(workspace, /not linked/);
  await db.exec(`reset role; update hospital_nurses set is_active=true where nurse_user_id='${ids.nurse}';
    update profiles set is_active=false where user_id='${ids.nurse}'`);
  await actor(ids.nurse);
  await assert.rejects(workspace, /active nurse account/);
  await db.exec(`reset role; update profiles set is_active=true where user_id='${ids.nurse}';
    update hospitals set is_active=false where id='${ids.hospital}'`);
  await actor(ids.nurse);
  await assert.rejects(workspace, /not linked/);
  await db.exec(`reset role; update hospitals set is_active=true where id='${ids.hospital}';
    update hospital_wards set is_active=false`);
  await actor(ids.nurse);
  assert.deepEqual((await workspace()).wards, []);
  console.log('PASS: nurse workspace and prescription count resolve RLS-hidden data; isolate hospital/assignment/task access; count active prescriptions once per record; filter wards; reject invalid roles; rerun safely; preserve legacy RPCs.');
} finally {
  await db.close();
}
