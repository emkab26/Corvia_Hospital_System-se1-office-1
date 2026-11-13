import { PGlite } from '../../tmp/blood-bank-tests/node_modules/@electric-sql/pglite/dist/index.js';
import { readFile } from 'node:fs/promises';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
const db = new PGlite();
const h=randomUUID(),other=randomUUID(),admin=randomUUID(),medic=randomUUID(),outsider=randomUUID();
await db.exec(`create role anon; create role authenticated; create role service_role;
 create schema auth; create table auth.users(id uuid primary key,email text);
 create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid $$;
 create table profiles(id uuid primary key,user_id uuid,is_active boolean);
 create table hospitals(id uuid primary key,name text,is_active boolean);
 create table hospital_admins(hospital_id uuid,profile_id uuid);
 create table patients(id uuid primary key,hospital_id uuid,profile_id uuid,patient_number text,first_name text,surname text,id_number text);
 insert into hospitals values('${h}','Hospital',true),('${other}','Other',true);
 insert into profiles values('${admin}','${admin}',true);
 insert into hospital_admins values('${h}','${admin}');
 insert into auth.users values('${admin}','admin@example.test'),('${medic}','medic@example.test');
 grant usage on schema public,auth to authenticated;
 grant execute on function auth.uid() to authenticated;`);
await db.exec(await readFile(new URL('../../supabase/scripts/workstreams/11_install_fleet_paramedic.sql',import.meta.url),'utf8'));
// Upgrade is rerunnable without resetting data.
await db.exec(await readFile(new URL('../../supabase/migrations/20261008_corvia_paramedic_workspace.sql',import.meta.url),'utf8'));
async function as(id){await db.exec('reset role');await db.query("select set_config('request.jwt.claim.sub',$1,false)",[id]);await db.exec('set role authenticated');}
async function open(){return (await db.query('select corvia_ems_open($1,$2) v',[h,'Test device'])).rows[0].v;}
let session;
async function cmd(action,p={},op=randomUUID()){return (await db.query('select corvia_ems_command($1,$2,$3,$4,$5) v',[h,session,op,action,JSON.stringify(p)])).rows[0].v;}
async function detail(i){return (await db.query('select corvia_ems_workspace($1,$2,$3) v',[h,session,i])).rows[0].v;}
await as(outsider);await assert.rejects(open,/access is required/);
await as(admin);session=await open();
const unit=await cmd('unit',{unit_number:'AMB-1',vehicle_type:'Ambulance'});
const member=await cmd('member',{employee_number:'EMS-1',first_name:'Jane',last_name:'Doe',email:'medic@example.test',verification_status:'verified',verification_expiry_date:'2099-01-01'});
const shift=await cmd('shift',{member_id:member.id,unit_id:unit.id,start_datetime:new Date(Date.now()-10000).toISOString(),end_datetime:new Date(Date.now()+3600000).toISOString()});
await assert.rejects(()=>cmd('end_shift',{shift_id:999999}),/not found/);
const incident=await cmd('incident',{priority:'High',incident_type:'Trauma',dispatch_notes:'Reported injury'});
let d=await detail(incident.id);
await cmd('assign',{incident_id:incident.id,revision:d.incident.revision,crew_id:shift.crew_id});
await assert.rejects(()=>cmd('end_shift',{shift_id:shift.id}),/active incident/);
const adminSession=session;
await as(medic);session=await open();
async function onIncident(action,p={},op){const q=await detail(incident.id);return cmd(action,{incident_id:incident.id,revision:q.incident.revision,...p},op);}
await assert.rejects(()=>cmd('unit',{unit_number:'FORBIDDEN'}),/Administrator/);
await assert.rejects(()=>cmd('status',{incident_id:incident.id,revision:0,status:'Accepted'}),/changed/);
await assert.rejects(()=>onIncident('status',{status:'Transporting'}),/transition/);
await onIncident('status',{status:'Accepted'});
const patient=await onIncident('patient',{first_name:'Patient',last_name:'Example',patient_number:'EMS-P-1',identity_number:'EXAMPLE-ONLY'});
const qr=await onIncident('qr',{patient_id:patient.id,code:'UNKNOWN'});assert.equal(qr.match,false);
await onIncident('qr_acknowledge',{patient_id:patient.id,id:qr.id});
assert.equal((await detail(incident.id)).incident_patients[0].patient_id,patient.id);
assert.equal((await onIncident('qr',{patient_id:patient.id,code:'CORVIA_EMS_PATIENT|v=1|patient_number=EMS-P-1'})).match,true);
await assert.rejects(()=>onIncident('observation',{patient_id:patient.id,spo2:101}),/observation/);
const before=await detail(incident.id),op=randomUUID();
const payload={incident_id:incident.id,revision:before.incident.revision,patient_id:patient.id,note_text:'Clinical note',recorded_at:new Date().toISOString()};
const one=await cmd('note',payload,op),two=await cmd('note',payload,op);assert.deepEqual(one,two);
assert.equal((await detail(incident.id)).clinical_notes.length,1);
await assert.rejects(()=>cmd('note',{...payload,note_text:'Changed'},op),/different data/);
await onIncident('observation',{patient_id:patient.id,heart_rate:85,spo2:97});
const assignmentId=(await detail(incident.id)).incident_assignments_actual[0].assignment_id;
// Two offline notes may append despite a changed revision, but only for the
// exact same assignment, current access and original timestamp.
await cmd('note',{...payload,assignment_id:assignmentId,note_text:'Offline follow-up'},randomUUID());
await assert.rejects(()=>cmd('note',{...payload,assignment_id:999999,note_text:'Wrong assignment'}),/changed/);
await onIncident('treatment',{patient_id:patient.id,treatment_type:'Assessment',description:'Recorded assessment'});
for(const status of ['En Route','On Scene','Transporting','At Hospital']) await onIncident('status',{status});
await assert.rejects(()=>onIncident('status',{status:'Handed Over'}),/handover/);
const medicSession=session;
await as(admin);session=adminSession;
const facility=await cmd('facility',{facility_code:'ED1',facility_name:'Emergency department'});
await as(medic);session=medicSession;
const ho=await onIncident('handover',{patient_id:patient.id,facility_id:facility.id,receiver_name:'Receiving nurse',handover_summary:'Observations and treatment communicated'});
await onIncident('handover_acknowledge',{patient_id:patient.id,id:ho.id,reason:'Receiver verbally confirmed receipt'});
await onIncident('status',{status:'Handed Over'});
await onIncident('status',{status:'Closed'});
await as(admin);session=adminSession;
assert.equal((await detail(incident.id)).incident.status,'Closed');
const followup=await cmd('incident',{priority:'Low',incident_type:'Transfer',dispatch_notes:'Patient linkage check'});
await db.exec('reset role');
await db.query('insert into patients values($1,$2,null,$3,$4,$5,$6)',[randomUUID(),h,'HOSP-1','Imported','Person','LOCAL-ID-1']);
await db.query('insert into patients values($1,$2,null,$3,$4,$5,$6)',[randomUUID(),other,'OTHER-1','Other','Person','OTHER-ID-1']);
await as(admin);session=adminSession;
const linked=await cmd('patient_link',{incident_id:followup.id,revision:1,identifier:'LOCAL-ID-1'});
assert.ok(linked.id);
assert.equal((await detail(followup.id)).patients_actual[0].first_name,'Imported');
await assert.rejects(()=>cmd('patient_link',{incident_id:followup.id,revision:2,identifier:'OTHER-ID-1'}),/not found/);
await assert.rejects(()=>db.query('select corvia_ems_insert($1,$2,$3)', ['corvia_ws6_patients_actual','patient_id','{}']),/permission denied/);
// Expired credentials deny a paramedic even with a previously valid session.
await db.exec('reset role');
await db.query("update corvia_ws6_ems_members set verification_expiry_date='2000-01-01' where member_id=$1",[member.id]);
await as(medic);session=medicSession;await assert.rejects(()=>detail(incident.id),/access was removed/);
await as(admin);session=adminSession;
await assert.rejects(()=>db.query('select * from corvia_ws6_patients_actual'),/permission denied/);
await assert.rejects(()=>db.query('select corvia_ws6_actual_dashboard($1)',[h]),/permission denied/);
await assert.rejects(()=>db.query('select corvia_ems_workspace($1,$2,null)',[other,session]),/access/);
const sessions=(await db.query('select corvia_ems_workspace($1,$2,null) v',[h,session])).rows[0].v.sessions;
await cmd('session_revoke',{id:sessions[0].session_id});
await assert.rejects(()=>detail(incident.id),/expired or revoked/);
console.log('PASS: rerun, tenant isolation, roles, revisions, credentials, dispatch, patient QR, clinical records, idempotency, handover, closure, grants and session revocation');
await db.close();
