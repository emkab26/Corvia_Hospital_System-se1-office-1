// Disposable synthetic PostgreSQL only; never connects to Supabase.
// Uses the same ignored PGlite install as nurse_workspace_test.mjs.
// Run: node test/backend/settings_team_access_test.mjs
import { PGlite } from '../../build/nurse-workspace-tests/node_modules/@electric-sql/pglite/dist/index.js';
import { readFile } from 'node:fs/promises';
import { randomUUID } from 'node:crypto';
import assert from 'node:assert/strict';

const db = new PGlite();
const nurse = randomUUID(), other = randomUUID(), hospital = randomUUID(), otherHospital = randomUUID();
const migration = await readFile('supabase/migrations/20261022_corvia_settings_team_access.sql', 'utf8');
const flag = async (backup, receiving) => {
  const { rows } = await db.query('select public.corvia_ws4_team_settings_access() as access');
  assert.deepEqual(rows[0].access, {
    user_id: nurse, backup_responses: backup, receiving_handovers: receiving,
  });
};
try {
  await db.exec(`
    create role anon; create role authenticated;
    create schema auth;
    create function auth.uid() returns uuid language sql stable as
      $$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
    create table profiles(user_id uuid primary key, is_active boolean);
    create table hospitals(id uuid primary key, is_active boolean);
    insert into profiles values ('${nurse}',true),('${other}',true);
    insert into hospitals values ('${hospital}',true),('${otherHospital}',true);
    select set_config('request.jwt.claim.sub','${nurse}',false);
  `);
  // Installation and reapplication are safe without the optional EMS module.
  await db.exec(migration);
  await db.exec(migration);
  await flag(false, false);
  await db.exec('set role authenticated');
  await flag(false, false);
  await db.exec('reset role; set role anon');
  await assert.rejects(flag(false, false), /permission denied/);
  await db.exec("reset role; select set_config('request.jwt.claim.sub','',false)");
  await assert.rejects(flag(false, false), /Sign in/);

  await db.exec(`
    select set_config('request.jwt.claim.sub','${nurse}',false);
    create schema ws4_private;
    create table public.corvia_ws6_receiving_facilities(facility_id bigint, hospital_id uuid, is_active boolean);
    create table ws4_private.ems_receivers(hospital_id uuid, facility_id bigint, user_id uuid, active boolean);
    create table public.corvia_ws6_ems_members(member_id bigint, hospital_id uuid, auth_user_id uuid,
      is_active boolean, verification_status text, verification_expiry_date date);
    create table public.corvia_ws6_crew_members_actual(crew_id bigint, hospital_id uuid, member_id bigint,
      is_active boolean, left_datetime timestamptz);
    create table public.corvia_ws6_crews(crew_id bigint, hospital_id uuid, shift_id bigint,
      crew_status text, start_datetime timestamptz, end_datetime timestamptz);
    create table public.corvia_ws6_shifts_actual(shift_id bigint, hospital_id uuid,
      shift_status text, start_datetime timestamptz, end_datetime timestamptz);
    create function public.corvia_ws4_backup_overview(bigint default null)
      returns jsonb language sql as $$ select '{"items":[]}'::jsonb $$;
    create function public.corvia_ws4_receiver_inbox()
      returns jsonb language sql as $$ select '{"items":[]}'::jsonb $$;
  `);
  // Exercise the actual reviewed membership helper definitions.
  const receiverSql = await readFile('supabase/scripts/ws4_release/004_team_backup_receiver.sql', 'utf8');
  const receiverStart = receiverSql.indexOf('CREATE FUNCTION ws4_private.receiver_allowed(');
  assert(receiverStart >= 0);
  await db.exec(receiverSql.slice(receiverStart, receiverSql.indexOf('$$;', receiverStart) + 3));
  const emsSql = await readFile('supabase/migrations/20261008_corvia_paramedic_workspace.sql', 'utf8');
  const emsStart = emsSql.indexOf('create or replace function public.corvia_ems_member(');
  assert(emsStart >= 0);
  await db.exec(emsSql.slice(emsStart, emsSql.indexOf('$$;', emsStart) + 3));
  await flag(false, false);

  await db.exec(`
    insert into public.corvia_ws6_receiving_facilities values (1,'${hospital}',true);
    insert into ws4_private.ems_receivers values ('${hospital}',1,'${other}',true);
  `);
  await flag(false, false); // Another account's membership cannot grant a link.
  await db.exec(`insert into ws4_private.ems_receivers values ('${hospital}',1,'${nurse}',true)`);
  await flag(false, true); // Authorised even when no handovers exist.
  for (const [table, field, restore] of [
    ['ws4_private.ems_receivers', 'active', true],
    ['public.corvia_ws6_receiving_facilities', 'is_active', true],
    ['public.hospitals', 'is_active', true],
  ]) {
    await db.exec(`update ${table} set ${field}=false`);
    await flag(false, false);
    await db.exec(`update ${table} set ${field}=${restore}`);
  }

  await db.exec(`
    insert into public.corvia_ws6_ems_members values
      (1,'${hospital}','${nurse}',true,'verified',current_date+1);
    insert into public.corvia_ws6_crew_members_actual values (1,'${hospital}',1,true,null);
    insert into public.corvia_ws6_crews values
      (1,'${hospital}',1,'Active',now()-interval '1 hour',now()+interval '1 hour');
    insert into public.corvia_ws6_shifts_actual values
      (1,'${hospital}','Active',now()-interval '1 hour',now()+interval '1 hour');
  `);
  await flag(true, true); // No backup offer is needed to show an empty inbox.
  for (const [change, restore] of [
    ["update corvia_ws6_ems_members set verification_status='pending'", "update corvia_ws6_ems_members set verification_status='verified'"],
    ["update corvia_ws6_ems_members set verification_expiry_date=current_date-1", "update corvia_ws6_ems_members set verification_expiry_date=current_date+1"],
    ['update corvia_ws6_crew_members_actual set left_datetime=now()', 'update corvia_ws6_crew_members_actual set left_datetime=null'],
    ["update corvia_ws6_crews set crew_status='Inactive'", "update corvia_ws6_crews set crew_status='Active'"],
    ["update corvia_ws6_crews set start_datetime=now()+interval '1 minute'", "update corvia_ws6_crews set start_datetime=now()-interval '1 hour'"],
    ["update corvia_ws6_shifts_actual set end_datetime=now()-interval '1 minute'", "update corvia_ws6_shifts_actual set end_datetime=now()+interval '1 hour'"],
    [`update corvia_ws6_crew_members_actual set hospital_id='${otherHospital}'`, `update corvia_ws6_crew_members_actual set hospital_id='${hospital}'`],
  ]) {
    await db.exec(change);
    await flag(false, true);
    await db.exec(restore);
  }
  await db.exec(`update profiles set is_active=false where user_id='${nurse}'`);
  await flag(false, false);
  console.log('Settings team access PostgreSQL checks passed (optional installation, permissions, receiver membership, verified crew, shifts and hospital isolation).');
} finally {
  await db.close();
}
