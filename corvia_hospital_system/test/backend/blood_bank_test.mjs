// npm install --prefix tmp/blood-bank-tests --ignore-scripts @electric-sql/pglite
// node test/backend/blood_bank_test.mjs
// Disposable PostgreSQL WASM database only. Never connects to Supabase.
import { PGlite } from '../../tmp/blood-bank-tests/node_modules/@electric-sql/pglite/dist/index.js';
import { readFile } from 'node:fs/promises';
import assert from 'node:assert/strict';

const db = new PGlite();
const id = n => `10000000-0000-4000-8000-${String(n).padStart(12,'0')}`;
const [manager, tech, clinician, ward, outsider] = [1,2,3,4,5].map(id);
const [hospital, otherHospital, product, fridge, quarantine, disposal, patient] = [10,11,20,30,31,32,40].map(id);
const sql = await readFile(new URL('../../supabase/migrations/20261008_corvia_blood_bank.sql',import.meta.url),'utf8');
let passed = 0, operation = 100;
await db.exec(`
create role anon; create role authenticated; create role service_role;
create schema auth;
create table auth.users(id uuid primary key);
create function auth.uid() returns uuid language sql stable as
$$ select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid $$;
grant usage on schema auth to authenticated;
create table public.profiles(user_id uuid primary key references auth.users(id), is_active boolean, id_number text, first_name text, surname text, email text);
create table public.hospitals(id uuid primary key,name text,is_active boolean);
create table public.patients(id uuid primary key,profile_id uuid references public.profiles(user_id),hospital_id uuid references public.hospitals(id),is_active boolean);
insert into auth.users values ${[manager,tech,clinician,ward,outsider].map(x=>`('${x}')`).join(',')};
insert into profiles(user_id,is_active) select id,true from auth.users;
update profiles set id_number='9001015009087' where user_id='${clinician}';
update profiles set first_name='Synthetic',surname='Patient',email='synthetic@example.test' where user_id='${clinician}';
insert into hospitals values ('${hospital}','Synthetic One',true),('${otherHospital}','Synthetic Two',true);
insert into patients(id,profile_id,hospital_id,is_active) values ('${patient}','${clinician}','${hospital}',true),('${id(41)}','${outsider}','${otherHospital}',true);
`);
await db.exec(sql);
await db.exec(`
insert into corvia_bb_settings(hospital_id,operating_mode) values ('${hospital}','hybrid'),('${otherHospital}','receiver');
insert into corvia_bb_memberships(hospital_id,user_id,role,granted_by,reason) values
${[[manager,'manager'],[tech,'technician'],[clinician,'clinician'],[ward,'ward']].map(([user,role])=>`('${hospital}','${user}','${role}','${manager}','Synthetic fixture')`).join(',')};
insert into corvia_bb_memberships(hospital_id,user_id,role,granted_by,reason)
 values ('${otherHospital}','${outsider}','manager','${manager}','Synthetic fixture');
insert into corvia_bb_products(id,hospital_id,name,component) values ('${product}','${hospital}','Test product','Test component');
insert into corvia_bb_locations(id,hospital_id,name,location_type) values
 ('${fridge}','${hospital}','Test fridge','fridge'),('${quarantine}','${hospital}','Test hold','quarantine'),
 ('${disposal}','${hospital}','Test disposal','disposal'),('${id(33)}','${otherHospital}','Other fridge','fridge');
`);

async function as(user, run) {
  await db.exec('set role authenticated');
  await db.query(`select set_config('request.jwt.claim.sub',$1,false)`,[user]);
  try { return await run(); } finally { await db.exec('reset role'); }
}
async function command(user,action,payload,op=id(operation++),h=hospital) {
  return as(user,async()=> (await db.query('select corvia_bb_command($1,$2,$3,$4::jsonb) as result',
    [h,op,action,JSON.stringify({reason:'Synthetic test',...payload})])).rows[0].result);
}
async function test(name,run) {
  try { await run(); console.log(`PASS ${name}`); passed++; }
  catch(error) { console.error(`FAIL ${name}`); throw error; }
}
const receive = {
  unit_number:'TEST-001',product_id:product,location_id:fridge,source:'external',supplier:'Synthetic supplier',
  lot_number:'LOT-TEST',abo:'O',rhd:'positive',group_source_reference:'Synthetic unit label',
  expires_at:'2090-10-10T10:00:00Z',
};
let unit, request;
await test('anonymous execution is denied', async()=>{
  await db.exec('set role anon');
  try { await assert.rejects(db.query('select corvia_bb_access()'),/permission denied/); }
  finally { await db.exec('reset role'); }
});
await test('ordinary users cannot grant themselves membership',()=>as(outsider,()=>assert.rejects(
  db.query('insert into corvia_bb_memberships(hospital_id,user_id,role,granted_by,reason) values ($1,$2,$3,$2,$4)',
    [hospital,outsider,'manager','test']),/permission denied/)));
await test('raw stock reads and mutations denied',()=>as(manager,async()=>{
  await assert.rejects(db.query('select * from corvia_bb_units'),/permission denied/);
  await assert.rejects(db.query("update corvia_bb_units set status='issued'"),/permission denied/);
}));
await test('receipt creates one stock record and audit',async()=>{
  unit=await command(tech,'receive',receive,id(150));
  assert.equal(unit.status,'available');
  assert.equal((await db.query('select count(*)::int as n from corvia_bb_movements')).rows[0].n,1);
});
await test('lost-response retry reuses receipt and audit',async()=>{
  const retry=await command(tech,'receive',receive,id(150));
  assert.equal(retry.id,unit.id);
  assert.equal((await db.query('select count(*)::int as n from corvia_bb_movements')).rows[0].n,1);
});
await test('changed retry payload rejected',()=>assert.rejects(command(tech,'receive',{...receive,unit_number:'OTHER'},id(150)),/reused/));
await test('duplicate unit number with new operation rejected',()=>assert.rejects(command(tech,'receive',receive),/unique constraint/));
await test('expired receipt rejected',()=>assert.rejects(command(tech,'receive',{...receive,unit_number:'EXP',expires_at:'2000-01-01T00:00:00Z'}),/expired/));
await test('wrong-hospital location rejected',()=>assert.rejects(command(tech,'receive',{...receive,unit_number:'WRONG',location_id:id(33)}),/location/));
await test('internal source requires donation and collection',()=>assert.rejects(command(tech,'receive',{...receive,unit_number:'INTERNAL',source:'internal'}),/check constraint/));
await test('source respects receiver configuration',async()=>{
  await db.query("update corvia_bb_settings set operating_mode='receiver' where hospital_id=$1",[hospital]);
  await assert.rejects(command(tech,'receive',{...receive,unit_number:'SOURCE',source:'internal'}),/operating mode/);
  await db.query("update corvia_bb_settings set operating_mode='hybrid' where hospital_id=$1",[hospital]);
});
await test('wrong-hospital reads rejected',()=>as(outsider,()=>assert.rejects(db.query('select corvia_bb_dashboard($1)',[hospital]),/access denied/)));
await test('ward cannot receive',()=>assert.rejects(command(ward,'receive',{...receive,unit_number:'WARD'}),/denied/));
await test('clinician cannot request unrelated patient',()=>assert.rejects(command(clinician,'request',
  {patient_id:id(41),product_id:product,quantity:1,required_at:receive.expires_at}),/Patient/));
await test('create pending request',async()=>{
  request=await command(clinician,'request',{patient_id:patient,product_id:product,quantity:1,required_at:receive.expires_at});
  assert.equal(request.status,'pending');
});
await test('clinical approval disabled by default',()=>assert.rejects(command(manager,'approve_request',
  {request_id:request.id,approval_reference:'Synthetic approval'}),/not configured/));
await db.query("update corvia_bb_settings set clinical_issue_enabled=true,clinical_authority_reference='Synthetic test only' where hospital_id=$1",[hospital]);
await test('technician cannot approve request',()=>assert.rejects(command(tech,'approve_request',
  {request_id:request.id,approval_reference:'Synthetic approval'}),/Manager access/));
await test('unapproved request cannot reserve stock',()=>assert.rejects(command(tech,'reserve',
  {unit_id:unit.id,version:unit.version,request_id:request.id}),/Approved request/));
await test('manager records external approval',async()=>{
  request=await command(manager,'approve_request',{request_id:request.id,approval_reference:'Synthetic external approval'});
  assert.equal(request.approved_by,manager);
});
await test('unit reservation uses approved request',async()=>{
  unit=await command(tech,'reserve',{unit_id:unit.id,version:unit.version,request_id:request.id});
  assert.equal(unit.status,'reserved');
});
await test('stale version cannot update reserved stock',()=>assert.rejects(command(tech,'cancel_reservation',{unit_id:unit.id,version:1}),/Stock changed/));
await test('allocated request cannot be cancelled',()=>assert.rejects(command(manager,'cancel_request',{request_id:request.id}),/reservations/));
await test('quantity protected across separate units',async()=>{
  const other=await command(tech,'receive',{...receive,unit_number:'TEST-002'});
  await assert.rejects(command(tech,'reserve',{unit_id:other.id,version:other.version,request_id:request.id}),/quantity/);
});
await test('issue requires compatibility evidence',()=>assert.rejects(command(tech,'issue',
  {unit_id:unit.id,version:unit.version,request_id:request.id,recipient:'Test ward'}),/compatibility/));
await test('issue saves actor, recipient and evidence once',async()=>{
  unit=await command(tech,'issue',{unit_id:unit.id,version:unit.version,request_id:request.id,
    compatibility_reference:'Synthetic signed crossmatch',recipient:'Test nurse'});
  assert.equal(unit.status,'issued');
  assert.equal((await db.query('select count(*)::int as n from corvia_bb_issues')).rows[0].n,1);
});
await test('issued unit cannot be disposed before return',()=>assert.rejects(command(manager,'dispose',
  {unit_id:unit.id,version:unit.version,location_id:disposal}),/Return issued/));
await test('recall preserves outstanding issue for traceability',async()=>{
  unit=await command(manager,'recall',{unit_id:unit.id,version:unit.version});
  assert.equal(unit.recalled,true);
  assert.equal((await db.query('select returned_at from corvia_bb_issues')).rows[0].returned_at,null);
});
await test('ward return quarantines and retains recall',async()=>{
  unit=await command(ward,'return',{unit_id:unit.id,version:unit.version,location_id:quarantine,
    condition:'Test cold chain uncertain',cold_chain_broken:true});
  assert.equal(unit.status,'recalled'); assert.equal(unit.cold_chain_broken,true);
  assert.ok((await db.query('select returned_at from corvia_bb_issues')).rows[0].returned_at);
});
await test('recalled or broken-chain stock cannot issue',()=>assert.rejects(command(tech,'issue',
  {unit_id:unit.id,version:unit.version,request_id:request.id,compatibility_reference:'test',recipient:'test'}),/not issuable/));
await test('reason required and failed command creates no audit',async()=>{
  const before=(await db.query('select count(*)::int as n from corvia_bb_movements')).rows[0].n;
  await assert.rejects(command(manager,'dispose',{unit_id:unit.id,version:unit.version,location_id:disposal,reason:''}),/reason/);
  assert.equal((await db.query('select count(*)::int as n from corvia_bb_movements')).rows[0].n,before);
});
await test('manager disposal preserves immutable trace',async()=>{
  unit=await command(manager,'dispose',{unit_id:unit.id,version:unit.version,location_id:disposal});
  assert.equal(unit.status,'disposed');
  await assert.rejects(db.query("update corvia_bb_movements set reason='replace'"),/immutable/);
});
await test('disposed stock terminal',()=>assert.rejects(command(manager,'recall',{unit_id:unit.id,version:unit.version}),/Disposed/));
await test('expiry checked at issue time',async()=>{
  const exp=await command(tech,'receive',{...receive,unit_number:'EXPIRE-LATER'});
  await db.query("update corvia_bb_units set expires_at=now()-interval '1 second' where id=$1",[exp.id]);
  await assert.rejects(command(tech,'issue',{unit_id:exp.id,version:exp.version,request_id:request.id}),/not issuable/);
});
await test('dashboard returns server time and exact filtered total',()=>as(manager,async()=>{
  const r=(await db.query('select corvia_bb_dashboard($1,$2) as data',[hospital,'TEST-001'])).rows[0].data;
  assert.ok(r.server_time); assert.equal(r.units.length,1); assert.equal(r.matching_count,1);
}));
await test('revocation prevents reads and previous command replay',async()=>{
  await db.query('update corvia_bb_memberships set active=false where user_id=$1',[tech]);
  await assert.rejects(command(tech,'receive',receive,id(150)),/access denied/);
  await as(tech,()=>assert.rejects(db.query('select corvia_bb_dashboard($1)',[hospital]),/access denied/));
});
await test('inactive profile denied',async()=>{
  await db.query('update profiles set is_active=false where user_id=$1',[manager]);
  await as(manager,()=>assert.rejects(db.query('select corvia_bb_dashboard($1)',[hospital]),/access denied/));
});
await test('repeat migration fails without modifying installed objects',async()=>{
  await assert.rejects(db.exec(sql),/already exists/);
  await db.exec('rollback');
  assert.equal((await db.query('select count(*)::int as n from corvia_bb_units')).rows[0].n,3);
});
await test('configuration audit records provisioning and revocation',async()=>{
  const events=await db.query("select * from corvia_bb_private.configuration_events where table_name='corvia_bb_memberships'");
  assert.ok(events.rows.some(e=>e.action==='UPDATE' && e.after_record.user_id===tech && e.after_record.active===false));
  await assert.rejects(db.query('truncate corvia_bb_private.configuration_events'),/immutable/);
});
await test('installation verification script runs and exposes no direct client privileges',async()=>{
  await db.exec(await readFile(new URL('../../supabase/scripts/workstreams/03_verify_blood_bank.sql',import.meta.url),'utf8'));
  const rows=await db.query("select has_table_privilege('authenticated','public.corvia_bb_units','UPDATE') as allowed");
  assert.equal(rows.rows[0].allowed,false);
});
await test('configuration template aborts unchanged and provisions with real IDs',async()=>{
  const template=await readFile(new URL('../../supabase/scripts/workstreams/02_configure_blood_bank.sql',import.meta.url),'utf8');
  await assert.rejects(db.exec(template),/invalid input syntax for type uuid/);
  await db.exec('rollback');
  await db.query('update profiles set is_active=true where user_id=$1',[manager]);
  await db.query('insert into hospitals values ($1,$2,true)',[id(12),'Synthetic configured hospital']);
  await db.exec(template.replaceAll('REPLACE_HOSPITAL_UUID',id(12))
    .replaceAll('REPLACE_MANAGER_AUTH_USER_UUID',manager)
    .replaceAll('REPLACE_GRANTING_ADMIN_AUTH_USER_UUID',manager));
  assert.equal((await db.query('select count(*)::int as n from corvia_bb_products where hospital_id=$1',[id(12)])).rows[0].n,10);
  assert.equal((await db.query('select clinical_issue_enabled from corvia_bb_settings where hospital_id=$1',[id(12)])).rows[0].clinical_issue_enabled,false);
});
const linkedAdminSql=(await readFile(new URL('../../supabase/scripts/workstreams/04_configure_existing_hospital_admin.sql',import.meta.url),'utf8'))
  .replaceAll('ba9f9d42-fc7d-4532-aa3f-c8b07f5da145',manager);
await db.exec('create table public.hospital_admins(hospital_id uuid,profile_id uuid,role text)');
await test('linked-admin setup refuses a missing hospital link',async()=>{
  await assert.rejects(db.exec(linkedAdminSql),/exactly one active hospital/);
  await db.exec('rollback');
});
await test('linked-admin setup refuses ambiguous hospitals',async()=>{
  await db.query("insert into hospital_admins values ($1,$2,'admin'),($3,$2,'admin')",[hospital,manager,otherHospital]);
  await assert.rejects(db.exec(linkedAdminSql),/exactly one active hospital/);
  await db.exec('rollback');
  await db.query('delete from hospital_admins where hospital_id=$1',[otherHospital]);
});
await test('linked-admin setup can run twice without duplicates or resetting settings',async()=>{
  await db.exec(linkedAdminSql);
  await db.exec(linkedAdminSql);
  const settings=(await db.query('select * from corvia_bb_settings where hospital_id=$1',[hospital])).rows[0];
  assert.equal(settings.operating_mode,'hybrid');
  assert.equal(settings.clinical_issue_enabled,true);
  assert.equal((await db.query('select count(*)::int as n from corvia_bb_products where hospital_id=$1',[hospital])).rows[0].n,11);
  assert.equal((await db.query('select count(*)::int as n from corvia_bb_locations where hospital_id=$1',[hospital])).rows[0].n,8);
});
await test('linked-admin setup never reactivates a revoked membership',async()=>{
  await db.query('update corvia_bb_memberships set active=false where user_id=$1 and hospital_id=$2',[manager,hospital]);
  await assert.rejects(db.exec(linkedAdminSql),/will not reactivate or promote/);
  await db.exec('rollback');
  assert.equal((await db.query('select active from corvia_bb_memberships where user_id=$1 and hospital_id=$2',[manager,hospital])).rows[0].active,false);
});
// Incremental workspace upgrade against the installed base, not a second schema.
await db.exec(`alter table patients add column first_name text;
alter table patients add column surname text;
alter table patients add column patient_number text;`);
await db.query("update patients set first_name='Synthetic',surname='Patient',patient_number='P-001'");
await db.query('update corvia_bb_memberships set active=true where hospital_id=$1',[hospital]);
await db.exec(await readFile(new URL('../../supabase/migrations/20261008_corvia_blood_bank_workspace.sql',import.meta.url),'utf8'));
await db.exec(await readFile(new URL('../../supabase/migrations/20261008_corvia_blood_bank_patient_search.sql',import.meta.url),'utf8'));
await db.exec(await readFile(new URL('../../supabase/migrations/20261008_corvia_blood_bank_donor_identity.sql',import.meta.url),'utf8'));
const rpc = (user,name,args) => as(user,async()=> (await db.query(
  `select ${name}(${args.map((_,i)=>`$${i+1}`).join(',')}) as data`,args)).rows[0].data);
await test('patient search is role scoped and excludes other hospitals',async()=>{
  const rows=await rpc(clinician,'corvia_bb_patient_options',[hospital,'synthetic']);
  assert.deepEqual(rows.map(r=>r.id),[patient]);
  assert.equal((await rpc(manager,'corvia_bb_patient_options',[hospital,'s'])).length,0);
  await assert.rejects(rpc(ward,'corvia_bb_patient_options',[hospital,'Synthetic']),/denied/);
  await assert.rejects(rpc(outsider,'corvia_bb_patient_options',[hospital,'Synthetic']),/denied/);
});
await test('patient search accepts the recorded ID number but returns no UUID input field',async()=>{
  const rows=await rpc(clinician,'corvia_bb_patient_options',[hospital,'9001015009087']);
  assert.equal(rows.length,1);
  assert.equal(rows[0].id,patient);
  assert.equal(rows[0].patient_name,'Synthetic Patient');
  assert.equal(rows[0].id_number,undefined);
});
await test('patient options stay bounded and omit inactive patients',async()=>{
  for(let n=0;n<28;n++) await db.query('insert into patients(id,hospital_id,is_active,first_name,patient_number) values($1,$2,$3,$4,$5)',
    [id(1000+n),hospital,n!==0,'Search Fixture',`F-${n}`]);
  const rows=await rpc(manager,'corvia_bb_patient_options',[hospital,'Search']);
  assert.equal(rows.length,25);
  assert.ok(rows.every(r=>r.id!==id(1000)));
});
await test('internal donor receipt records donor ID privately and only exposes a flag',async()=>{
  const donorOperation=id(1999);
  const donorPayload={...receive,unit_number:'DONOR-001',source:'internal',
    donation_reference:'DONATION-001',collected_at:'2026-10-01T08:00:00Z',
    donor_id_number:'9001015009087',reason:'Donor consent and collection record'};
  const result=await rpc(tech,'corvia_bb_receive_donor_unit',[hospital,donorOperation,donorPayload]);
  assert.equal(result.donor_identity_recorded,true);
  const retry=await rpc(tech,'corvia_bb_receive_donor_unit',[hospital,donorOperation,donorPayload]);
  assert.deepEqual(retry,result);
  const privateRow=(await db.query('select donor_id_number from corvia_bb_private.donor_identities where unit_id=$1',[result.id])).rows[0];
  assert.equal(privateRow.donor_id_number,'9001015009087');
  const movement=(await db.query("select count(*)::int n from corvia_bb_movements where unit_id=$1 and action='donor_identity_recorded'",[result.id])).rows[0];
  assert.equal(movement.n,1);
  const dashboard=await rpc(tech,'corvia_bb_dashboard',[hospital,'DONOR-001','',0]);
  const unit=dashboard.units.find(r=>r.unit_number==='DONOR-001');
  assert.equal(unit.donor_identity_recorded,true);
  assert.equal(JSON.stringify(unit).includes('9001015009087'),false);
});
await test('donor receipt rejects invalid IDs and unauthorised roles',async()=>{
  const payload={...receive,unit_number:'DONOR-BAD',source:'internal',
    donation_reference:'DONATION-BAD',collected_at:'2026-10-01T08:00:00Z',
    donor_id_number:'12',reason:'Synthetic'};
  await assert.rejects(rpc(tech,'corvia_bb_receive_donor_unit',[hospital,id(2002),payload]),/valid donor ID/);
  await assert.rejects(rpc(clinician,'corvia_bb_receive_donor_unit',[hospital,id(2003),{...payload,donor_id_number:'9001015009087'}]),/denied/);
});
const lookupUnit=await command(tech,'receive',{...receive,unit_number:'SCAN-001'});
const scanOperation=id(2000);
await test('Corvia QR and exact supplier unit number resolve the same unit',async()=>{
  const qr=await rpc(tech,'corvia_bb_lookup_scan',[hospital,scanOperation,`corvia:bb:unit:${lookupUnit.id}`]);
  const number=await rpc(ward,'corvia_bb_lookup_scan',[hospital,id(2001),'SCAN-001']);
  assert.equal(qr.unit_id,lookupUnit.id); assert.equal(number.unit_id,lookupUnit.id);
});
await test('scan retries audit once and reject changed payloads',async()=>{
  await rpc(tech,'corvia_bb_lookup_scan',[hospital,scanOperation,`corvia:bb:unit:${lookupUnit.id}`]);
  assert.equal((await db.query('select count(*)::int n from corvia_bb_private.scan_events where operation_id=$1',[scanOperation])).rows[0].n,1);
  await assert.rejects(rpc(tech,'corvia_bb_lookup_scan',[hospital,scanOperation,'DIFFERENT']),/reused/);
});
await test('unknown, partial and cross-hospital scans disclose no unit',async()=>{
  for(const scan of ['SCAN','https://example.test/SCAN-001']) {
    assert.deepEqual(await rpc(tech,'corvia_bb_lookup_scan',[hospital,id(operation++),scan]),{status:'not_found'});
  }
  assert.deepEqual(await rpc(outsider,'corvia_bb_lookup_scan',[otherHospital,id(operation++),`corvia:bb:unit:${lookupUnit.id}`]),{status:'not_found'});
  await assert.rejects(rpc(outsider,'corvia_bb_lookup_scan',[hospital,id(operation++),'SCAN-001']),/denied/);
  await assert.rejects(db.query('delete from corvia_bb_private.scan_events'),/immutable/);
  assert.equal((await db.query('select version from corvia_bb_units where id=$1',[lookupUnit.id])).rows[0].version,lookupUnit.version);
});
let optionsRequest;
await test('request options only include approved requests for this product',async()=>{
  optionsRequest=await command(clinician,'request',{patient_id:patient,product_id:product,quantity:1,required_at:'2090-10-01T10:00:00Z'});
  let options=await rpc(tech,'corvia_bb_request_options',[hospital,lookupUnit.id,'']);
  assert.ok(!options.some(r=>r.id===optionsRequest.id));
  await command(manager,'approve_request',{request_id:optionsRequest.id,approval_reference:'Synthetic external authority'});
  options=await rpc(tech,'corvia_bb_request_options',[hospital,lookupUnit.id,'']);
  assert.equal(options.find(r=>r.id===optionsRequest.id).remaining,1);
  await assert.rejects(rpc(ward,'corvia_bb_request_options',[hospital,lookupUnit.id,'']),/denied/);
  await assert.rejects(rpc(outsider,'corvia_bb_request_options',[otherHospital,lookupUnit.id,'']),/not found/);
});
await test('reservation remains selectable for its unit but consumes other-unit capacity',async()=>{
  const reserved=await command(tech,'reserve',{unit_id:lookupUnit.id,version:lookupUnit.version,request_id:optionsRequest.id});
  const another=await command(tech,'receive',{...receive,unit_number:'SCAN-002'});
  const own=await rpc(tech,'corvia_bb_request_options',[hospital,lookupUnit.id,'']);
  assert.equal(own.length,1); assert.equal(own[0].id,optionsRequest.id);
  const other=await rpc(tech,'corvia_bb_request_options',[hospital,another.id,'']);
  assert.ok(!other.some(r=>r.id===optionsRequest.id));
  Object.assign(lookupUnit,reserved);
});
const labelOp=id(2100);
await test('request picker bounds results and excludes incompatible products',async()=>{
  const unitForOptions=await command(tech,'receive',{...receive,unit_number:'PICKER-LIMIT'});
  for(let n=0;n<27;n++) {
    const q=await command(clinician,'request',{patient_id:patient,product_id:product,quantity:1,required_at:'2090-10-01T10:00:00Z'});
    await command(manager,'approve_request',{request_id:q.id,approval_reference:'Synthetic external authority'});
  }
  await db.query('insert into corvia_bb_products(id,hospital_id,name,component) values($1,$2,$3,$4)',[id(2500),hospital,'Different component','Synthetic']);
  const incompatible=await command(clinician,'request',{patient_id:patient,product_id:id(2500),quantity:1,required_at:'2080-10-01T10:00:00Z'});
  await command(manager,'approve_request',{request_id:incompatible.id,approval_reference:'Synthetic external authority'});
  const rows=await rpc(tech,'corvia_bb_request_options',[hospital,unitForOptions.id,'']);
  assert.equal(rows.length,25);
  assert.ok(rows.every(r=>r.id!==incompatible.id));
});
let label;
await test('label preparation audits once, contains no patient and preserves stock version',async()=>{
  label=await rpc(tech,'corvia_bb_prepare_label',[hospital,labelOp,lookupUnit.id,lookupUnit.version,'Synthetic first print']);
  const retry=await rpc(tech,'corvia_bb_prepare_label',[hospital,labelOp,lookupUnit.id,lookupUnit.version,'Synthetic first print']);
  assert.deepEqual(retry,label); assert.equal(label.label_number,1);
  assert.equal(label.qr_value,`corvia:bb:unit:${lookupUnit.id}`);
  assert.equal(label.patient_id,undefined);
  const events=(await db.query("select * from corvia_bb_movements where unit_id=$1 and action='label_prepared'",[lookupUnit.id])).rows;
  assert.equal(events.length,1); assert.equal(events[0].evidence.physical_print_confirmed,false);
  assert.equal((await db.query('select version from corvia_bb_units where id=$1',[lookupUnit.id])).rows[0].version,lookupUnit.version);
});
await test('label rejects stale stock, wrong roles, changed retry and missing reason',async()=>{
  await assert.rejects(rpc(tech,'corvia_bb_prepare_label',[hospital,id(operation++),lookupUnit.id,0,'test']),/Stock changed/);
  await assert.rejects(rpc(ward,'corvia_bb_prepare_label',[hospital,id(operation++),lookupUnit.id,lookupUnit.version,'test']),/denied/);
  await assert.rejects(rpc(tech,'corvia_bb_prepare_label',[hospital,labelOp,lookupUnit.id,lookupUnit.version,'changed']),/reused/);
  await assert.rejects(rpc(tech,'corvia_bb_prepare_label',[hospital,id(operation++),lookupUnit.id,lookupUnit.version,'']),/reason required/);
  const second=await rpc(manager,'corvia_bb_prepare_label',[hospital,id(operation++),lookupUnit.id,lookupUnit.version,'Synthetic replacement']);
  assert.equal(second.label_number,2);
});
await test('workspace RPCs deny anonymous use and revoked replay',async()=>{
  await db.exec('set role anon');
  try { await assert.rejects(db.query('select corvia_bb_patient_options($1,$2)',[hospital,'test']),/permission denied/); }
  finally { await db.exec('reset role'); }
  await db.query('update corvia_bb_memberships set active=false where hospital_id=$1 and user_id=$2',[hospital,tech]);
  await assert.rejects(rpc(tech,'corvia_bb_prepare_label',[hospital,labelOp,lookupUnit.id,lookupUnit.version,'Synthetic first print']),/denied/);
  await assert.rejects(rpc(tech,'corvia_bb_lookup_scan',[hospital,scanOperation,`corvia:bb:unit:${lookupUnit.id}`]),/denied/);
});
await db.close();
console.log(`${passed} blood-bank PostgreSQL checks passed. Full-schema, concurrent multi-session and hosted JWT checks remain separate.`);
