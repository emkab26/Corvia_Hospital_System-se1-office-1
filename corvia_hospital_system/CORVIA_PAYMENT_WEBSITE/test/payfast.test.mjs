import test from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { signature, encode, cents, parseNotification, validSource, paymentLink, validLink, checkoutFields } from '../src/payfast.mjs';
import { loadConfig } from '../src/config.mjs';
import { escape } from '../src/views.mjs';

const config = { baseUrl: 'https://pay.example', linkSecret: 'test-secret-with-at-least-32-characters', merchantId: '10000100', merchantKey: 'public-merchant-key', passphrase: 'test pass', sandbox: true };
const payment = { id: '10000000-0000-4000-8000-000000000001', created_at: '2026-10-07T10:00:00Z', email: 'demo@example.test', amount_cents: 14900, plan_name: 'Monthly' };

test('PHP-compatible encoding and exact integer cents', () => {
  assert.equal(encode("A B+~!'()*"), 'A+B%2B%7E%21%27%28%29%2A');
  assert.equal(cents('149.01'), 14901);
  for (const value of ['149.001', '-1.00', '1e3', 'NaN', '149']) assert.throws(() => cents(value));
});
test('checkout signatures preserve prescribed order and omit blanks', () => {
  const fields = [['merchant_id','10000100'],['name_first',' A B '],['item_description',''],['amount','10.00']];
  const canonical = 'merchant_id=10000100&name_first=A+B&amount=10.00&passphrase=test+pass';
  assert.equal(signature(fields,'test pass'), createHash('md5').update(canonical).digest('hex'));
  assert.notEqual(signature([...fields].reverse(),'test pass'), signature(fields,'test pass'));
});
test('ITN signatures retain blank fields and whitespace', () => {
  const parsed = parseNotification('m_payment_id=abc&custom_str1=&name_first=+A+&signature=abc');
  assert.equal(parsed.canonical, 'm_payment_id=abc&custom_str1=&name_first=+A+');
  assert.equal(signature(parsed.entries,'pass',false), createHash('md5').update(`${parsed.canonical}&passphrase=pass`).digest('hex'));
  assert.throws(() => parseNotification('amount_gross=1.00&amount_gross=2.00&signature=x'));
  assert.throws(() => parseNotification('signature=x&amount_gross=1.00'));
});
test('private links expire and cannot be reused for another reference', () => {
  const url = new URL(paymentLink(payment,config));
  assert.equal(validLink(payment.id,url.searchParams,config,Date.parse('2026-10-07T11:00:00Z')),true);
  assert.equal(validLink('other',url.searchParams,config,Date.parse('2026-10-07T11:00:00Z')),false);
  assert.equal(validLink(payment.id,url.searchParams,config,Date.parse('2026-10-08T10:00:00Z')),false);
});
test('checkout is one payment and passphrase is never emitted', () => {
  const fields = Object.fromEntries(checkoutFields(payment,config));
  assert.equal(fields.amount,'149.00');
  assert.equal(fields.m_payment_id,payment.id);
  assert.equal(fields.subscription_type,undefined);
  assert.equal(fields.passphrase,undefined);
  assert.ok(fields.notify_url.startsWith(config.baseUrl));
  assert.ok(!JSON.stringify(fields).includes(config.passphrase));
});
test('source validation accepts published ranges/DNS and rejects spoofed sources', async () => {
  const dns = async () => ['203.0.113.5'];
  assert.equal(await validSource('::ffff:197.97.145.144',dns),true);
  assert.equal(await validSource('203.0.113.5',dns),true);
  assert.equal(await validSource('127.0.0.1',dns),false);
});
test('configuration fails closed for missing secrets and accidental production', () => {
  assert.throws(() => loadConfig({}), /Missing configuration/);
  assert.throws(() => loadConfig({PAYFAST_MODE:'live'}), /Live payments/);
  assert.throws(() => loadConfig({PORTAL_PREVIEW:'true',PORTAL_BASE_URL:'http://public.example'}), /HTTPS/);
  assert.equal(loadConfig({PORTAL_PREVIEW:'true'}).sandbox,true);
  assert.equal(escape('<script>"&'), '&lt;script&gt;&quot;&amp;');
});
