import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { stripTypeScriptTypes } from 'node:module';
import vm from 'node:vm';

async function handler(name, fetcher, env = {}) {
  let serve;
  const source = await readFile(new URL(`../../supabase/functions/${name}/index.ts`, import.meta.url),'utf8');
  vm.runInNewContext(stripTypeScriptTypes(source), {
    Deno:{env:{get:key=>({PAYMENT_PORTAL_URL:'https://pay.example',PAYMENT_ALLOWED_ORIGINS:'https://app.example',...env}[key])},serve:fn=>{serve=fn;}},
    Response,Request,AbortSignal,fetch:fetcher,
  });
  return serve;
}
test('checkout adapter forwards bearer and plan only, dropping forged user/price',async()=>{
  let forwarded;
  const run=await handler('create-payment',async(url,init)=>{forwarded={url,...init};return Response.json({url:'https://pay.example/checkout/reference'});});
  const response=await run(new Request('https://edge.example',{method:'POST',headers:{Authorization:'Bearer customer',Origin:'https://app.example'},body:JSON.stringify({plan_code:'monthly',user_id:'victim',amount:1})}));
  assert.equal(response.status,200);
  assert.equal(forwarded.headers.authorization,'Bearer customer');
  assert.deepEqual(JSON.parse(forwarded.body),{plan_code:'monthly'});
  assert.equal(response.headers.get('access-control-allow-origin'),'https://app.example');
});
test('edge adapters fail closed for unknown origins, no auth, and missing configuration',async()=>{
  for(const name of ['create-payment','payment-review']) {
    const run=await handler(name,()=>{throw new Error('must not call');});
    assert.equal((await run(new Request('https://edge.example',{method:'POST',headers:{Origin:'https://evil.example'}}))).status,403);
    assert.equal((await run(new Request('https://edge.example',{method:'POST'}))).status,401);
    assert.equal((await run(new Request('https://edge.example',{method:'GET'}))).status,405);
    assert.equal((await run(new Request('https://edge.example',{method:'OPTIONS',headers:{Origin:'https://app.example'}}))).status,204);
    const missing=await handler(name,()=>{}, {PAYMENT_PORTAL_URL:undefined});
    assert.equal((await missing(new Request('https://edge.example',{method:'POST'}))).status,503);
  }
});
test('review adapter only permits known actions and preserves authentication',async()=>{
  let path;
  const run=await handler('payment-review',async(url,init)=>{path=url;assert.equal(init.headers.authorization,'Bearer staff');return Response.json({message:'checked'});});
  const req=action=>new Request('https://edge.example',{method:'POST',headers:{Authorization:'Bearer staff'},body:JSON.stringify({action,payment_id:'10000000-0000-4000-8000-000000000001'})});
  assert.equal((await run(req('set-paid'))).status,400);
  assert.equal((await run(req('reconcile'))).status,200);
  assert.equal(path,'https://pay.example/api/reconcile/10000000-0000-4000-8000-000000000001');
});
