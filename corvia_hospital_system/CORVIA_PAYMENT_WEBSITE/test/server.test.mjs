import test from 'node:test';
import assert from 'node:assert/strict';
import { createServer } from '../src/server.mjs';
import { signature, paymentLink } from '../src/payfast.mjs';

const id = '10000000-0000-4000-8000-000000000001';
const config = { baseUrl:'https://pay.example',linkSecret:'test-secret-with-at-least-32-characters',merchantId:'10000100',merchantKey:'key',passphrase:'phrase',environment:'sandbox',sandbox:true,payfastHost:'sandbox.payfast.co.za' };
async function fixture(t, options = {}) {
  const calls = [];
  const payment = { id,user_id:'owner',status:'pending',environment:'sandbox',amount_cents:14900,created_at:new Date().toISOString(),plan_name:'Monthly',billing_period:'monthly',email:'demo@example.test',hospital_id:'hospital' };
  const db = {
    payment:async () => payment,
    plans:async () => [],
    user:async token => { if(token==='invalid') throw new Error('bad session'); return {id:token==='owner'?'owner':'other',email:'demo@example.test'}; },
    create:async(user,plan,key,env) => { calls.push(['create',user,plan,key,env]); return payment; },
    rpc:async(name,args) => { calls.push([name,args]); if(name==='corvia_payment_staff') return false; if(name==='corvia_apply_notification') payment.status='paid'; return 'notification-id'; },
    request:async () => [],
  };
  const server = createServer({...config,...options.config},{db,validSource:async()=>true,confirm:async()=>true,...options.dependencies});
  await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
  t.after(()=>new Promise(resolve=>{server.close(resolve);server.closeAllConnections();}));
  const base = `http://127.0.0.1:${server.address().port}`;
  return { base,payment,calls };
}
function notification(overrides = {}) {
  const fields = Object.entries({m_payment_id:id,pf_payment_id:'12345',payment_status:'COMPLETE',amount_gross:'149.00',merchant_id:config.merchantId,...overrides});
  return new URLSearchParams([...fields,['signature',signature(fields,config.passphrase,false)]]).toString();
}
const form = {'Content-Type':'application/x-www-form-urlencoded'};
test('public health identifies preview without opening cross-origin checkout',async t=>{
  const {base}=await fixture(t,{config:{preview:true}});
  const response=await fetch(`${base}/healthz`,{headers:{Origin:'http://localhost:49290'}});
  assert.equal(response.headers.get('access-control-allow-origin'),'*');
  assert.deepEqual(await response.json(),{app:'corvia-payment-portal',status:'ok',mode:'preview'});
  const checkout=await fetch(`${base}/api/checkout`,{method:'POST',headers:{Origin:'http://localhost:49290'}});
  assert.equal(checkout.status,503);assert.equal(checkout.headers.get('access-control-allow-origin'),null);
});
test('return/cancel never mutate status; receipt is unavailable before confirmation',async t=>{
  const {base,payment,calls}=await fixture(t);
  const query=new URL(paymentLink(payment,config)).search;
  assert.equal((await fetch(`${base}/return/${id}${query}`)).status,200);
  assert.equal((await fetch(`${base}/cancel/${id}${query}`)).status,200);
  assert.equal((await fetch(`${base}/receipt/${id}${query}`)).status,409);
  assert.equal(payment.status,'pending');assert.equal(calls.length,0);
  assert.equal((await fetch(`${base}/api/status/${id}`)).status,403);
});
test('checkout derives identity from bearer and ignores client price/user',async t=>{
  const {base,calls}=await fixture(t);
  const response=await fetch(`${base}/api/checkout`,{method:'POST',headers:{'Content-Type':'application/json',Authorization:'Bearer owner'},body:JSON.stringify({plan_code:'monthly',user_id:'victim',amount_cents:1})});
  assert.equal(response.status,200);assert.equal(calls[0][1].id,'owner');assert.equal(calls[0][2],'monthly');
  assert.equal((await fetch(`${base}/api/checkout`,{method:'POST',headers:{'Content-Type':'application/json'},body:'{}'})).status,401);
});
test('ITN applies state only after all verification checks',async t=>{
  const {base,payment,calls}=await fixture(t);
  const response=await fetch(`${base}/payfast/itn`,{method:'POST',headers:form,body:notification()});
  assert.equal(response.status,200);assert.equal(payment.status,'paid');
  assert.equal(calls[0][0],'corvia_record_notification');assert.equal(calls[1][0],'corvia_apply_notification');
});
test('wrong amount is reviewable but never paid',async t=>{
  const {base,payment,calls}=await fixture(t);
  assert.equal((await fetch(`${base}/payfast/itn`,{method:'POST',headers:form,body:notification({amount_gross:'1.00'})})).status,422);
  assert.equal(payment.status,'pending');assert.equal(calls[0][1].p_reason,'amount_mismatch');
});
test('bad signature and source do not mutate database',async t=>{
  const {base,calls}=await fixture(t,{dependencies:{validSource:async()=>false}});
  assert.equal((await fetch(`${base}/payfast/itn`,{method:'POST',headers:form,body:notification().replace('149.00','148.00')})).status,400);
  assert.equal((await fetch(`${base}/payfast/itn`,{method:'POST',headers:form,body:notification()})).status,403);
  assert.equal(calls.length,0);
});
test('provider failure retains notification for reconciliation without activation',async t=>{
  const {base,payment,calls}=await fixture(t,{dependencies:{confirm:async()=>{throw new Error('timeout');}}});
  assert.equal((await fetch(`${base}/payfast/itn`,{method:'POST',headers:form,body:notification()})).status,503);
  assert.equal(payment.status,'pending');assert.equal(calls[0][0],'corvia_record_notification');
  assert.equal(calls[1][1].p_reason,'provider_unavailable');
});
test('provider INVALID cannot activate payment',async t=>{
  const {base,payment}=await fixture(t,{dependencies:{confirm:async()=>false}});
  assert.equal((await fetch(`${base}/payfast/itn`,{method:'POST',headers:form,body:notification()})).status,422);
  assert.equal(payment.status,'pending');
});
test('unrelated user cannot open private link or reconcile',async t=>{
  const {base}=await fixture(t);
  for(const route of ['payment-link','reconcile']) assert.equal((await fetch(`${base}/api/${route}/${id}`,{method:'POST',headers:{Authorization:'Bearer other'}})).status,403);
});
test('website login requires same-origin form submission; preview is non-transacting',async t=>{
  const {base}=await fixture(t);
  assert.equal((await fetch(`${base}/checkout`,{method:'POST',headers:form,body:'email=a&password=b'})).status,403);
  const preview=await fixture(t,{config:{preview:true}});
  assert.match(await (await fetch(preview.base)).text(),/PREVIEW · CHECKOUT DISABLED/);
  assert.equal((await fetch(`${preview.base}/api/checkout`,{method:'POST'})).status,503);
});
