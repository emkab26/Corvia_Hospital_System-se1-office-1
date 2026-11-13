import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { randomUUID } from 'node:crypto';
import { PGlite } from '@electric-sql/pglite';

const owner='10000000-0000-4000-8000-000000000001';
const other='10000000-0000-4000-8000-000000000002';
const staff='10000000-0000-4000-8000-000000000003';
const hospital='20000000-0000-4000-8000-000000000001';
async function database(t) {
  const db=new PGlite();
  t.after(()=>db.close());
  // Minimal documented existing contract, not a copy of the hosted schema.
  await db.exec(`
    create role anon; create role authenticated; create role service_role bypassrls;
    create schema auth;
    create table auth.users(id uuid primary key);
    create function auth.uid() returns uuid language sql stable as
      $$ select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid $$;
    grant usage on schema auth,public to anon,authenticated,service_role;
    grant execute on function auth.uid() to anon,authenticated,service_role;
    create table public.profiles(id uuid primary key,user_id uuid,user_type text,is_active boolean default true);
    create table public.patients(id uuid primary key,profile_id uuid,hospital_id uuid);
    create table public.hospital_admins(profile_id uuid,hospital_id uuid);
    create table public.pricing_plans(code text primary key,name text,billing_period text,price_cents bigint,currency text,is_active boolean);
    insert into auth.users values('${owner}'),('${other}'),('${staff}');
    insert into profiles(id,user_id,user_type) values('${owner}','${owner}','patient'),('${other}','${other}','patient'),('${staff}','${staff}','hospital_admin');
    insert into hospital_admins values('${staff}','${hospital}');
    insert into patients values(gen_random_uuid(),'${owner}','${hospital}');
    insert into pricing_plans values('monthly','Monthly access','monthly',14900,'ZAR',true),('disabled','Disabled','monthly',1,'ZAR',false);
  `);
  await db.exec(await readFile(new URL('../../supabase/migrations/20261006_corvia_payfast_portal.sql',import.meta.url),'utf8'));
  return db;
}
async function create(db,user=owner,key=randomUUID(),environment='sandbox',plan='monthly') {
  return (await db.query('select * from corvia_create_payment($1,$2,$3,$4,$5)',[user,'demo@example.test',plan,key,environment])).rows[0];
}
async function notify(db,payment,status='COMPLETE',provider='12345',digest=randomUUID()) {
  return (await db.query("select corvia_record_notification($1,$2,'raw','canonical',$3,$4,'197.97.145.144') as id",[payment.id,digest,provider,status])).rows[0].id;
}
async function role(db,user) { await db.exec(`set role authenticated; set request.jwt.claim.sub='${user}';`); }

test('billing escalation is scoped, auditable, rerunnable and cannot change paid state',async t=>{
 const db=await database(t);const payment=await create(db);
 const upgrade=await readFile(new URL('../../supabase/migrations/20261009_corvia_payment_escalation.sql',import.meta.url),'utf8');
 await db.exec(upgrade);await db.exec(upgrade);
 await role(db,owner);
 await assert.rejects(()=>db.query('select corvia_payment_escalate($1,$2,false)',[payment.id,'Please investigate']),/Billing staff access/);
 await role(db,staff);
 await db.query('select corvia_payment_escalate($1,$2,false)',[payment.id,'Check outstanding notification']);
 await db.query('select corvia_payment_escalate($1,$2,false)',[payment.id,'Check outstanding notification']);
 assert.equal((await db.query("select * from corvia_payment_events where event_type='staff_review_raised'")).rows.length,1);
 await db.query('select corvia_payment_escalate($1,$2,true)',[payment.id,'Provider support contacted; waiting for signed ITN']);
 assert.equal((await db.query('select status from corvia_payment_attempts')).rows[0].status,'pending');
 assert.equal((await db.query('select state from corvia_payment_reviews')).rows[0].state,'resolved');
 await role(db,other);assert.equal((await db.query('select * from corvia_payment_reviews')).rows.length,0);
});

test('migration: price snapshot, idempotent checkout, disabled plans and throttling',async t=>{
  const db=await database(t);const key=randomUUID();
  const payment=await create(db,owner,key);
  assert.equal(Number(payment.amount_cents),14900);assert.equal(payment.hospital_id,hospital);
  assert.equal((await create(db,owner,key)).id,payment.id);
  await assert.rejects(create(db,owner,key,'live'),/Idempotency/);
  await assert.rejects(create(db,owner,randomUUID(),'sandbox','disabled'),/unavailable/);
  for(let i=0;i<4;i++) await create(db);
  await assert.rejects(create(db),/Too many/);
});
test('migration: duplicate notifications cannot duplicate receipts or extend access',async t=>{
  const db=await database(t);const payment=await create(db);const digest=randomUUID();
  const n=await notify(db,payment,'COMPLETE','12345',digest);
  assert.equal((await db.query('select corvia_apply_notification($1) as status',[n])).rows[0].status,'paid');
  const before=(await db.query('select * from corvia_payment_entitlements')).rows[0];
  assert.equal(await notify(db,payment,'COMPLETE','12345',digest),n);
  await db.query('select corvia_apply_notification($1)',[n]);
  const after=(await db.query('select * from corvia_payment_entitlements')).rows;
  assert.equal(after.length,1);assert.equal(after[0].valid_until.toISOString(),before.valid_until.toISOString());
  assert.equal((await db.query('select * from corvia_payment_receipts')).rows.length,1);
  assert.equal((await db.query('select duplicate_count from corvia_payment_attempts')).rows[0].duplicate_count,1);
});
test('migration: late cancellation cannot regress success; reused provider ID is flagged',async t=>{
  const db=await database(t);const first=await create(db);const second=await create(db,other);
  await db.query('select corvia_apply_notification($1)',[await notify(db,first)]);
  await db.query('select corvia_apply_notification($1)',[await notify(db,first,'CANCELLED')]);
  await db.query('select corvia_apply_notification($1)',[await notify(db,second)]);
  const a=(await db.query('select status,reason_code from corvia_payment_attempts where id=$1',[first.id])).rows[0];
  const b=(await db.query('select status,reason_code from corvia_payment_attempts where id=$1',[second.id])).rows[0];
  assert.equal(a.status,'paid');assert.equal(a.reason_code,'conflicting_final_state');
  assert.equal(b.status,'pending');assert.equal(b.reason_code,'provider_reference_reused');
});
test('migration: customer/staff scope and mutation restrictions',async t=>{
  const db=await database(t);const payment=await create(db);await create(db,other);
  await role(db,owner);
  assert.equal((await db.query('select id from corvia_payment_attempts')).rows.length,1);
  await assert.rejects(db.query('select email from corvia_payment_attempts'),/permission denied/);
  await assert.rejects(db.query('select * from corvia_payment_notifications'),/permission denied/);
  await assert.rejects(db.query("update corvia_payment_attempts set status='paid'"),/permission denied/);
  await assert.rejects(db.query('select corvia_apply_notification($1)',[randomUUID()]),/permission denied/);
  await assert.rejects(create(db),/permission denied/);
  await role(db,staff);
  assert.deepEqual((await db.query('select id from corvia_payment_attempts')).rows.map(r=>r.id),[payment.id]);
  assert.ok((await db.query('select * from corvia_payment_events')).rows.every(e=>e.payment_id===payment.id));
  await db.exec(`reset role;update profiles set is_active=false where user_id='${staff}';`);
  await role(db,staff);
  assert.equal((await db.query('select id from corvia_payment_attempts')).rows.length,0);
  await db.exec('reset role;set role anon;');
  await assert.rejects(db.query('select id from corvia_payment_attempts'),/permission denied/);
});
test('migration: sandbox access requires explicit test-environment opt-in',async t=>{
  const db=await database(t);const payment=await create(db);
  await db.query('select corvia_apply_notification($1)',[await notify(db,payment)]);
  await role(db,owner);
  assert.equal((await db.query('select corvia_payment_access() as active')).rows[0].active,false);
  await db.exec('reset role;update corvia_payment_settings set allow_sandbox_access=true;');
  await role(db,owner);
  assert.equal((await db.query('select corvia_payment_access() as active')).rows[0].active,true);
  await role(db,other);
  assert.equal((await db.query('select corvia_payment_access() as active')).rows[0].active,false);
});
